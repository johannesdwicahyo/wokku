// transfer.go implements service.export / service.import: spool a datastore
// dump to a gzipped — and, when the control plane sends public_key_pem, a
// WKB1-encrypted (crypt.go) — temp file, then PUT it to presigned R2
// (Content-Length required — R2 rejects chunked TE, B4 gate 4), and stream a
// restore straight from a presigned GET (download -> [decrypt with the
// per-backup DEK from params] -> gunzip -> engine stdin) using ExecStream
// (concurrent stdin/stdout) so a large payload can never deadlock the exec.
package services

import (
	"bufio"
	"compress/gzip"
	"context"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
)

// identRe is the host-side belt-and-suspenders guard on a database/tenant
// name before it becomes an argv element: must start alphanumeric (so it can
// never be read as a `-flag`) and stay within the charset the control plane's
// own naming rules already enforce. Blocks argv flag-smuggling even if the
// control plane is ever tricked into sending a crafted name (same defense
// posture as validSlug for tenant SQL).
var identRe = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$`)

func validateIdent(name string) error {
	if !identRe.MatchString(name) {
		return fmt.Errorf("invalid database identifier %q", name)
	}
	return nil
}

type ExportParams struct { // "service.export"
	ServiceType     string `json:"service_type"`
	Database        string `json:"database"`           // tenant/db name to dump
	Password        string `json:"password,omitempty"` // mariadb/mongo root pw
	PresignedPutURL string `json:"presigned_put_url"`
	PublicKeyPEM    string `json:"public_key_pem,omitempty"` // B4: WKB1-encrypt before PUT; empty = plaintext (legacy)
}

type ImportParams struct { // "service.import"
	ServiceType     string `json:"service_type"`
	Database        string `json:"database"`
	Password        string `json:"password,omitempty"`
	PresignedGetURL string `json:"presigned_get_url"`
	DEK             string `json:"dek,omitempty"` // B4: base64 per-backup DEK, unwrapped by the control plane; empty = plaintext object
	// Replace = restore of one of our own backups: the data is replaced
	// atomically and any error fails the op. Without it (a user's dump
	// import) statements stream into the existing data as before, since
	// foreign dumps often carry harmless errors (unknown owner roles).
	Replace bool `json:"replace,omitempty"`
}

// streamExecer is the slice of dockerAPI transfer needs — the concurrent
// exec. *realDockerAPI (and fakeDocker in tests) satisfy it structurally.
type streamExecer interface {
	ExecStream(ctx context.Context, container string, stdin io.Reader, stdout io.Writer, cmd ...string) error
}

type countingReader struct {
	r io.Reader
	n int64
}

func (c *countingReader) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.n += int64(n)
	return n, err
}

// runExport dumps the datastore and streams the gzipped output to the
// presigned PUT URL. Returns the number of (compressed) bytes uploaded.
func runExport(ctx context.Context, x streamExecer, container string, p ExportParams) (int64, error) {
	cmd, err := dumpCmd(p.ServiceType, p.Database, p.Password)
	if err != nil {
		return 0, err
	}

	// B4 gate 4: R2 (and S3 without streaming SigV4) rejects chunked
	// Transfer-Encoding on presigned PUTs, so the body must carry a real
	// Content-Length — spool the gzipped dump to a temp file first.
	// ponytail: costs host disk = one compressed dump; switch to multipart
	// upload if a dump ever outgrows the agent host's tmp space.
	tmp, err := os.CreateTemp("", "wokkud-export-*.gz")
	if err != nil {
		return 0, err
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()

	var sink io.Writer = tmp
	var enc *encryptWriter
	if p.PublicKeyPEM != "" {
		w, err := newEncryptWriter(tmp, p.PublicKeyPEM)
		if err != nil {
			return 0, err
		}
		enc = w
		sink = enc
	}
	gz := gzip.NewWriter(sink)
	if err := x.ExecStream(ctx, container, nil, gz, cmd...); err != nil {
		return 0, err
	}
	if err := gz.Close(); err != nil {
		return 0, err
	}
	if enc != nil {
		if err := enc.Close(); err != nil { // seals the mandatory final frame
			return 0, err
		}
	}
	st, err := tmp.Stat()
	if err != nil {
		return 0, err
	}
	if _, err := tmp.Seek(0, io.SeekStart); err != nil {
		return 0, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, p.PresignedPutURL, tmp)
	if err != nil {
		return 0, err
	}
	req.ContentLength = st.Size()
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return 0, fmt.Errorf("upload PUT %d: %s", resp.StatusCode, body)
	}
	return st.Size(), nil
}

// runImport downloads the presigned GET, gunzips it, and streams it to the
// engine's restore command on stdin. Returns the number of (decompressed)
// bytes fed to the engine.
func runImport(ctx context.Context, x streamExecer, container string, p ImportParams) (int64, error) {
	cmd, err := restoreCmd(p.ServiceType, p.Database, p.Password, p.Replace)
	if err != nil {
		return 0, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, p.PresignedGetURL, nil)
	if err != nil {
		return 0, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return 0, fmt.Errorf("download GET %d: %s", resp.StatusCode, body)
	}

	var body io.Reader = resp.Body
	if p.DEK != "" {
		dek, err := base64.StdEncoding.DecodeString(p.DEK)
		if err != nil {
			return 0, fmt.Errorf("dek: %w", err)
		}
		if body, err = newDecryptReader(resp.Body, dek); err != nil {
			return 0, err
		}
	}
	gr, err := gzip.NewReader(body)
	if err != nil {
		return 0, fmt.Errorf("gunzip: %w", err)
	}
	defer gr.Close()

	var src io.Reader = gr
	if p.ServiceType == "postgres" {
		// Legacy dokku postgres:export blobs are pg_dump -Fc custom-format
		// archives ("PGDMP" magic) — psql rejects them; pg_restore reads -Fc
		// from stdin. Peek doesn't consume, so the full archive still streams.
		br := bufio.NewReader(gr)
		if head, _ := br.Peek(5); string(head) == "PGDMP" {
			cmd = []string{"pg_restore", "-U", "postgres", "-d", p.Database}
			if p.Replace {
				cmd = append(cmd, "--clean", "--if-exists", "--single-transaction", "--exit-on-error")
			}
		}
		src = br
	}

	cr := &countingReader{r: src}
	if err := x.ExecStream(ctx, container, cr, io.Discard, cmd...); err != nil {
		return 0, err
	}
	return cr.n, nil
}

// dumpCmd / restoreCmd mirror the plugin export/import commands
// (BackupService::EXPORT_COMMANDS / RestoreService::IMPORT_COMMANDS on the
// Rails side). Shared tenants use their engine's branch with the tenant db
// as Database (and, for mariadb, no password — see the env fallback).
func dumpCmd(serviceType, database, password string) ([]string, error) {
	if err := validateIdent(database); err != nil {
		return nil, err
	}
	switch serviceType {
	case "postgres":
		return []string{"pg_dump", "-U", "postgres", database}, nil
	case "mariadb":
		// mariadb:11.x dropped the mysqldump compat symlink (dangling → exec
		// fails); only mariadb-dump works. --single-transaction = consistent
		// InnoDB snapshot without locking the tenant's tables; --routines
		// --events so stored procedures/functions and events survive a restore.
		if password == "" {
			// Shared-mariadb tenants: the control plane never holds the
			// parent's root password — read it from the container env.
			return []string{"sh", "-c", `MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb-dump -uroot --single-transaction --routines --events "$1"`, "mariadb-dump", database}, nil
		}
		return []string{"mariadb-dump", "-uroot", "-p" + password, "--single-transaction", "--routines", "--events", database}, nil
	case "mysql":
		return []string{"mysqldump", "-uroot", "-p" + password, database}, nil
	case "mongodb":
		// Root user lives in the admin DB; scope the dump to this database so
		// it never sweeps admin/config, matching dokku's mongo:export.
		return []string{"mongodump", "--archive", "-u", "root", "-p", password, "--authenticationDatabase", "admin", "--db", database}, nil
	case "redis":
		// RDB snapshot: `redis-cli --rdb` requires a real path (stdout is not
		// supported across versions), so spool to a temp file and cat it.
		// --no-auth-warning keeps the stderr warning out of mixed streams;
		// No password from the control plane (shared parent) → discover the
		// admin password in-container, same as redisAdminWrapper.
		rdb := " --rdb /tmp/wokku-export.rdb >/dev/null && cat /tmp/wokku-export.rdb && rm -f /tmp/wokku-export.rdb"
		if password == "" {
			return []string{"sh", "-c", redisPwDiscovery + `redis-cli --no-auth-warning ${pw:+-a "$pw"}` + rdb}, nil
		}
		return []string{"sh", "-c", "redis-cli --no-auth-warning -a " + shellQuote(password) + rdb}, nil
	default:
		return nil, fmt.Errorf("export unsupported for service_type %q", serviceType)
	}
}

// pgReplacePreamble empties the public schema inside the restore's single
// transaction (a failed restore rolls the drop back too), then hands the
// schema back to the database owner — a shared tenant's role must keep
// CREATE on it. Dumps don't carry DROPs, so without this a restore onto a
// live DB errored on every existing table and duplicated non-PK rows.
const pgReplacePreamble = `DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
DO $$ BEGIN EXECUTE format('ALTER SCHEMA public OWNER TO %I', (SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = current_database())); END $$;
`

func restoreCmd(serviceType, database, password string, replace bool) ([]string, error) {
	if err := validateIdent(database); err != nil {
		return nil, err
	}
	switch serviceType {
	case "postgres":
		if replace {
			return []string{"sh", "-c", `{ printf '%s' "$2"; cat; } | psql -U postgres -d "$1" -v ON_ERROR_STOP=1 --single-transaction`, "psql", database, pgReplacePreamble}, nil
		}
		return []string{"psql", "-U", "postgres", "-d", database}, nil
	case "mariadb":
		// mariadb:11.x dropped the mysql compat symlink; use the mariadb client.
		if password == "" { // shared-mariadb tenant: root password from the container env
			return []string{"sh", "-c", `MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$1"`, "mariadb", database}, nil
		}
		return []string{"mariadb", "-uroot", "-p" + password, database}, nil
	case "mysql":
		return []string{"mysql", "-uroot", "-p" + password, database}, nil
	case "mongodb":
		// --archive carries the db name; auth against admin (where root lives).
		cmd := []string{"mongorestore", "--archive", "-u", "root", "-p", password, "--authenticationDatabase", "admin"}
		if replace {
			cmd = append(cmd, "--drop") // replace collections instead of merging into them
		}
		return cmd, nil
	case "redis":
		// An RDB restore means replacing the data file under a stopped server —
		// there is no stdin-stream restore. Refuse with the manual runbook
		// instead of pretending: stop container, place dump.rdb in the data
		// dir, start container.
		return nil, fmt.Errorf("redis import is not streamable — manual restore: stop the container, replace dump.rdb with the backup, start it")
	default:
		return nil, fmt.Errorf("import unsupported for service_type %q", serviceType)
	}
}

// shellQuote single-quotes a value for the sh -c redis export command —
// passwords are random tokens but must not be able to break the pipeline.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
