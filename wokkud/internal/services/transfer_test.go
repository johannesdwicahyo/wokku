package services

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// streamRec extends fakeDocker's recording style to the streaming exec path:
// it captures whatever is written to stdin and emits canned bytes to stdout,
// so export/import can be driven without a real container.
type streamRec struct {
	stdinSeen bytes.Buffer
	stdoutOut []byte
	err       error
	lastCmd   []string
}

func (s *streamRec) ExecStream(ctx context.Context, container string, stdin io.Reader, stdout io.Writer, cmd ...string) error {
	s.lastCmd = cmd
	if stdin != nil {
		if _, err := io.Copy(&s.stdinSeen, stdin); err != nil {
			return err
		}
	}
	if len(s.stdoutOut) > 0 {
		if _, err := stdout.Write(s.stdoutOut); err != nil {
			return err
		}
	}
	return s.err
}

func TestExportStreamsDumpGzippedToPut(t *testing.T) {
	rec := &streamRec{stdoutOut: []byte("dump-bytes-here")}
	var putBody []byte
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			t.Errorf("method = %s, want PUT", r.Method)
		}
		// B4 gate 4: R2 rejects chunked TE — the PUT must carry a real
		// Content-Length (spooled temp file, not a bare pipe reader).
		if r.ContentLength <= 0 {
			t.Errorf("ContentLength = %d, want > 0 (chunked TE is R2-rejected)", r.ContentLength)
		}
		putBody, _ = io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	n, err := runExport(context.Background(), rec, "dokku.postgres.mydb", ExportParams{
		ServiceType:     "postgres",
		Database:        "mydb",
		PresignedPutURL: srv.URL,
	})
	if err != nil {
		t.Fatal(err)
	}
	// Uploaded body must gunzip back to the raw dump.
	gr, err := gzip.NewReader(bytes.NewReader(putBody))
	if err != nil {
		t.Fatalf("uploaded body is not gzip: %v", err)
	}
	got, _ := io.ReadAll(gr)
	if string(got) != "dump-bytes-here" {
		t.Errorf("round-trip = %q, want %q", got, "dump-bytes-here")
	}
	if n <= 0 {
		t.Errorf("reported bytes = %d, want > 0", n)
	}
	// pg_dump is what runs in the container.
	if len(rec.lastCmd) == 0 || rec.lastCmd[0] != "pg_dump" {
		t.Errorf("cmd = %v, want pg_dump ...", rec.lastCmd)
	}
}

func TestImportStreamsGunzippedToStdin(t *testing.T) {
	// Serve a gzipped fixture; import must gunzip it and feed it to exec stdin.
	var gzbuf bytes.Buffer
	gw := gzip.NewWriter(&gzbuf)
	_, _ = gw.Write([]byte("restore-payload"))
	_ = gw.Close()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(gzbuf.Bytes())
	}))
	defer srv.Close()

	rec := &streamRec{}
	n, err := runImport(context.Background(), rec, "dokku.postgres.mydb", ImportParams{
		ServiceType:     "postgres",
		Database:        "mydb",
		PresignedGetURL: srv.URL,
	})
	if err != nil {
		t.Fatal(err)
	}
	if rec.stdinSeen.String() != "restore-payload" {
		t.Errorf("stdin = %q, want %q", rec.stdinSeen.String(), "restore-payload")
	}
	if n != int64(len("restore-payload")) {
		t.Errorf("reported bytes = %d, want %d", n, len("restore-payload"))
	}
	if len(rec.lastCmd) == 0 || rec.lastCmd[0] != "psql" {
		t.Errorf("cmd = %v, want psql ...", rec.lastCmd)
	}
}

func TestExportSurfacesNonzeroExecExit(t *testing.T) {
	rec := &streamRec{err: errors.New("exec [pg_dump]: exit 1: connection refused")}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.Copy(io.Discard, r.Body)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	_, err := runExport(context.Background(), rec, "dokku.postgres.mydb", ExportParams{
		ServiceType:     "postgres",
		Database:        "mydb",
		PresignedPutURL: srv.URL,
	})
	if err == nil {
		t.Fatal("want error from a failed dump, got nil")
	}
	if !strings.Contains(err.Error(), "exit 1") {
		t.Errorf("error = %v, want it to carry the exec exit", err)
	}
}

func TestImportSurfacesNonzeroExecExit(t *testing.T) {
	var gzbuf bytes.Buffer
	gw := gzip.NewWriter(&gzbuf)
	_, _ = gw.Write([]byte("x"))
	_ = gw.Close()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(gzbuf.Bytes())
	}))
	defer srv.Close()

	rec := &streamRec{err: errors.New("exec [psql]: exit 3: syntax error")}
	_, err := runImport(context.Background(), rec, "dokku.postgres.mydb", ImportParams{
		ServiceType:     "postgres",
		Database:        "mydb",
		PresignedGetURL: srv.URL,
	})
	if err == nil {
		t.Fatal("want error from a failed restore, got nil")
	}
	if !strings.Contains(err.Error(), "exit 3") {
		t.Errorf("error = %v, want it to carry the exec exit", err)
	}
}

// The dispatch wires service.export/import to the transfer functions and
// reports {"bytes": n}.
func TestDispatchExportReportsBytes(t *testing.T) {
	f := &fakeDocker{streamOut: []byte("abc")}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.Copy(io.Discard, r.Body)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	params, _ := json.Marshal(ExportParams{ServiceType: "postgres", Database: "mydb", PresignedPutURL: srv.URL})
	res, err := runOp(context.Background(), nil, f, &queuedOp{
		kind: "service.export", service: "dokku.postgres.mydb", params: params,
	})
	if err != nil {
		t.Fatal(err)
	}
	m, ok := res.(map[string]any)
	if !ok {
		t.Fatalf("result type = %T, want map", res)
	}
	if m["bytes"].(int64) <= 0 {
		t.Errorf("bytes = %v, want > 0", m["bytes"])
	}
}

// A failed export surfaces as a typed service_export_failed op error.
func TestDispatchExportFailureIsTyped(t *testing.T) {
	f := &fakeDocker{streamErr: errors.New("exec [pg_dump]: exit 1: boom")}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.Copy(io.Discard, r.Body)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	params, _ := json.Marshal(ExportParams{ServiceType: "postgres", Database: "mydb", PresignedPutURL: srv.URL})
	_, err := runOp(context.Background(), nil, f, &queuedOp{
		kind: "service.export", service: "dokku.postgres.mydb", params: params,
	})
	var oe *opError
	if !errors.As(err, &oe) || oe.code != "service_export_failed" {
		t.Fatalf("want typed service_export_failed, got %v", err)
	}
}

// A database name that could smuggle an argv flag is rejected before any exec.
func TestExportRejectsFlagSmugglingDatabase(t *testing.T) {
	rec := &streamRec{}
	_, err := runExport(context.Background(), rec, "dokku.postgres.mydb", ExportParams{
		ServiceType: "postgres", Database: "--exclude-schema=public", PresignedPutURL: "http://unused",
	})
	if err == nil {
		t.Fatal("want rejection of a flag-shaped database name")
	}
	if len(rec.lastCmd) != 0 {
		t.Errorf("exec ran despite invalid ident: %v", rec.lastCmd)
	}
}

// mariadb:11.x ships only the mariadb* client binaries; the mysql/mysqldump
// compat symlinks are dangling and exec fails (verified live on jkt-01,
// 2026-07-18). dump/restore must call mariadb-dump / mariadb, not the mysql
// names, or every dedicated-mariadb backup and restore breaks.
func TestMariadbDumpRestoreUseMariadbBinaries(t *testing.T) {
	dc, err := dumpCmd("mariadb", "appdb", "pw")
	if err != nil || dc[0] != "mariadb-dump" {
		t.Errorf("dump: want mariadb-dump, got %v (err %v)", dc, err)
	}
	rc, err := restoreCmd("mariadb", "appdb", "pw")
	if err != nil || rc[0] != "mariadb" {
		t.Errorf("restore: want mariadb client, got %v (err %v)", rc, err)
	}
}

func TestRedactArgvMasksPassword(t *testing.T) {
	got := redactArgv([]string{"mysqldump", "-uroot", "-psecret", "db"})
	for _, a := range got {
		if a == "-psecret" {
			t.Fatalf("password not redacted: %v", got)
		}
	}
	got2 := redactArgv([]string{"mongodump", "-u", "root", "-p", "secret", "--db", "x"})
	for _, a := range got2 {
		if a == "secret" {
			t.Fatalf("mongo password not redacted: %v", got2)
		}
	}
}

// I1: a CREATE ROLE failure formats its argv into service_ops.error via
// redactArgv — the SQL literal itself (not just a -p/--password flag) must
// be masked so pgProvisionTenant's tenant password never ships to Sentry.
func TestRedactArgvMasksSQLPasswordLiteral(t *testing.T) {
	sql := `CREATE ROLE "x_role" LOGIN PASSWORD 'secret' CONNECTION LIMIT 40;`
	got := redactArgv([]string{"psql", "-U", "postgres", "-c", sql})
	for _, a := range got {
		if strings.Contains(a, "secret") {
			t.Fatalf("SQL password literal not redacted: %v", got)
		}
	}
	joined := strings.Join(got, " ")
	if !strings.Contains(joined, `PASSWORD '***'`) {
		t.Fatalf("want masked PASSWORD '***' literal, got: %v", got)
	}
}

// --- redis export/import (B6 agent batch) ---

func TestDumpCmdRedisSpoolsRDBWithAuth(t *testing.T) {
	cmd, err := dumpCmd("redis", "ignored", "s3cr3t")
	if err != nil {
		t.Fatal(err)
	}
	if cmd[0] != "sh" || cmd[1] != "-c" {
		t.Fatalf("redis dump must run through sh -c, got %v", cmd)
	}
	script := cmd[2]
	for _, want := range []string{"--no-auth-warning -a 's3cr3t'", "--rdb /tmp/wokku-export.rdb", "cat /tmp/wokku-export.rdb", "rm -f"} {
		if !strings.Contains(script, want) {
			t.Fatalf("script missing %q: %s", want, script)
		}
	}
}

func TestDumpCmdRedisNoPasswordOmitsAuth(t *testing.T) {
	cmd, err := dumpCmd("redis", "ignored", "")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(cmd[2], "-a ") {
		t.Fatalf("no-auth redis must omit -a, got %s", cmd[2])
	}
}

func TestRestoreCmdRedisRefusesWithRunbook(t *testing.T) {
	if _, err := restoreCmd("redis", "ignored", "x"); err == nil || !strings.Contains(err.Error(), "manual restore") {
		t.Fatalf("redis restore must refuse with the manual runbook, got %v", err)
	}
}

// --- B4: WKB1 envelope wiring (Task 5) ---

// Encryption flip: with public_key_pem set, the PUT body must be a WKB1
// envelope whose decrypted payload gunzips back to the dump.
func TestExportEncryptsWhenPublicKeySent(t *testing.T) {
	priv, pubPEM := testKeyPair(t)
	rec := &streamRec{stdoutOut: []byte("dump-bytes-here")}
	var putBody []byte
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.ContentLength <= 0 {
			t.Errorf("ContentLength = %d, want > 0", r.ContentLength)
		}
		putBody, _ = io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	n, err := runExport(context.Background(), rec, "dokku.postgres.mydb", ExportParams{
		ServiceType: "postgres", Database: "mydb", PresignedPutURL: srv.URL, PublicKeyPEM: pubPEM,
	})
	if err != nil {
		t.Fatal(err)
	}
	if int64(len(putBody)) != n {
		t.Errorf("reported bytes %d != body %d", n, len(putBody))
	}
	if string(putBody[:4]) != wkbMagic {
		t.Fatalf("uploaded body is not a WKB1 envelope: %q", putBody[:4])
	}
	plainGz, err := decryptBytes(t, unwrapDEK(t, priv, putBody), putBody)
	if err != nil {
		t.Fatal(err)
	}
	gr, err := gzip.NewReader(bytes.NewReader(plainGz))
	if err != nil {
		t.Fatalf("decrypted payload is not gzip: %v", err)
	}
	got, _ := io.ReadAll(gr)
	if string(got) != "dump-bytes-here" {
		t.Errorf("round-trip = %q, want %q", got, "dump-bytes-here")
	}
}

func TestExportRejectsGarbagePublicKey(t *testing.T) {
	rec := &streamRec{}
	_, err := runExport(context.Background(), rec, "dokku.postgres.mydb", ExportParams{
		ServiceType: "postgres", Database: "mydb", PresignedPutURL: "http://unused", PublicKeyPEM: "not-a-pem",
	})
	if err == nil {
		t.Fatal("want error for garbage public key")
	}
	if len(rec.lastCmd) != 0 {
		t.Errorf("dump exec ran despite bad key: %v", rec.lastCmd)
	}
}

// Import flip: with dek set, a WKB1-encrypted gzip body must decrypt+gunzip
// into the engine's stdin.
func TestImportDecryptsWithDEK(t *testing.T) {
	priv, pubPEM := testKeyPair(t)
	var gzbuf bytes.Buffer
	gw := gzip.NewWriter(&gzbuf)
	_, _ = gw.Write([]byte("restore-payload"))
	_ = gw.Close()
	blob := encryptBytes(t, pubPEM, gzbuf.Bytes())
	dek := unwrapDEK(t, priv, blob)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(blob)
	}))
	defer srv.Close()

	rec := &streamRec{}
	n, err := runImport(context.Background(), rec, "dokku.postgres.mydb", ImportParams{
		ServiceType: "postgres", Database: "mydb", PresignedGetURL: srv.URL,
		DEK: base64.StdEncoding.EncodeToString(dek),
	})
	if err != nil {
		t.Fatal(err)
	}
	if rec.stdinSeen.String() != "restore-payload" {
		t.Errorf("stdin = %q, want %q", rec.stdinSeen.String(), "restore-payload")
	}
	if n != int64(len("restore-payload")) {
		t.Errorf("bytes = %d, want %d", n, len("restore-payload"))
	}
}

func TestImportRejectsBadDEK(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("WKB1 whatever"))
	}))
	defer srv.Close()
	_, err := runImport(context.Background(), &streamRec{}, "dokku.postgres.mydb", ImportParams{
		ServiceType: "postgres", Database: "mydb", PresignedGetURL: srv.URL, DEK: "!!!not-base64!!!",
	})
	if err == nil {
		t.Fatal("want error for undecodable dek")
	}
}

// Legacy dokku postgres:export blobs are pg_dump -Fc custom-format archives
// ("PGDMP" magic) — psql rejects them; only pg_restore can load them. The
// import must sniff the decompressed head and swap the command, without
// consuming the sniffed bytes.
func TestImportPGDMPDumpUsesPgRestore(t *testing.T) {
	payload := append([]byte("PGDMP"), []byte("\x01\x02binary-archive-rest")...)
	var gzbuf bytes.Buffer
	gw := gzip.NewWriter(&gzbuf)
	_, _ = gw.Write(payload)
	_ = gw.Close()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(gzbuf.Bytes())
	}))
	defer srv.Close()

	rec := &streamRec{}
	n, err := runImport(context.Background(), rec, "dokku.postgres.mydb", ImportParams{
		ServiceType: "postgres", Database: "mydb", PresignedGetURL: srv.URL,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(rec.lastCmd) == 0 || rec.lastCmd[0] != "pg_restore" {
		t.Errorf("cmd = %v, want pg_restore ...", rec.lastCmd)
	}
	if !bytes.Equal(rec.stdinSeen.Bytes(), payload) {
		t.Errorf("stdin lost bytes to the sniff: got %d bytes, want %d", rec.stdinSeen.Len(), len(payload))
	}
	if n != int64(len(payload)) {
		t.Errorf("reported bytes = %d, want %d", n, len(payload))
	}
}

// The sniff composes with WKB1 decryption: an encrypted legacy -Fc blob must
// decrypt, sniff PGDMP, and route to pg_restore.
func TestImportEncryptedPGDMPUsesPgRestore(t *testing.T) {
	priv, pubPEM := testKeyPair(t)
	payload := append([]byte("PGDMP"), []byte("rest-of-archive")...)
	var gzbuf bytes.Buffer
	gw := gzip.NewWriter(&gzbuf)
	_, _ = gw.Write(payload)
	_ = gw.Close()
	blob := encryptBytes(t, pubPEM, gzbuf.Bytes())
	dek := unwrapDEK(t, priv, blob)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(blob)
	}))
	defer srv.Close()

	rec := &streamRec{}
	if _, err := runImport(context.Background(), rec, "dokku.postgres.mydb", ImportParams{
		ServiceType: "postgres", Database: "mydb", PresignedGetURL: srv.URL,
		DEK: base64.StdEncoding.EncodeToString(dek),
	}); err != nil {
		t.Fatal(err)
	}
	if len(rec.lastCmd) == 0 || rec.lastCmd[0] != "pg_restore" {
		t.Errorf("cmd = %v, want pg_restore ...", rec.lastCmd)
	}
	if !bytes.Equal(rec.stdinSeen.Bytes(), payload) {
		t.Errorf("stdin payload mismatch after sniff+decrypt")
	}
}

// PGDMP-looking bytes in a non-postgres import must NOT trigger pg_restore.
func TestImportPGDMPSniffOnlyAppliesToPostgres(t *testing.T) {
	var gzbuf bytes.Buffer
	gw := gzip.NewWriter(&gzbuf)
	_, _ = gw.Write([]byte("PGDMP-coincidence"))
	_ = gw.Close()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(gzbuf.Bytes())
	}))
	defer srv.Close()

	rec := &streamRec{}
	if _, err := runImport(context.Background(), rec, "dokku.mariadb.mydb", ImportParams{
		ServiceType: "mariadb", Database: "mydb", Password: "pw", PresignedGetURL: srv.URL,
	}); err != nil {
		t.Fatal(err)
	}
	if len(rec.lastCmd) == 0 || rec.lastCmd[0] != "mariadb" {
		t.Errorf("cmd = %v, want mariadb client", rec.lastCmd)
	}
}
