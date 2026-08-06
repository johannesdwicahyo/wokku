// crypt.go implements the WKB1 envelope: header ("WKB1" | 2-byte BE wrapped-DEK
// length | RSA-OAEP-SHA256-wrapped DEK | 7-byte nonce prefix) followed by
// AES-256-GCM frames (64KiB plaintext each; nonce = prefix || 4-byte BE frame
// counter || 1-byte final flag). Full frames are non-final; the remainder —
// possibly empty — is the mandatory final frame, so truncation is always
// detectable. The agent receives only the control plane's PUBLIC key: it can
// encrypt every export but decrypt an import only when the control plane
// hands it that one backup's DEK. Ruby mirror: app/services/envelope_cipher.rb
// (cross-language fixtures in spec/fixtures/envelope pin the format).
package services

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/binary"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
)

const (
	wkbMagic       = "WKB1"
	cryptChunk     = 64 * 1024
	gcmTagLen      = 16
	noncePrefixLen = 7
	dekLen         = 32
)

func parsePublicKeyPEM(pubPEM string) (*rsa.PublicKey, error) {
	block, _ := pem.Decode([]byte(pubPEM))
	if block == nil {
		return nil, errors.New("public_key_pem: no PEM block")
	}
	key, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("public_key_pem: %w", err)
	}
	pub, ok := key.(*rsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("public_key_pem: not an RSA key (%T)", key)
	}
	return pub, nil
}

func frameNonce(prefix []byte, counter uint32, final bool) []byte {
	nonce := make([]byte, 12)
	copy(nonce, prefix)
	binary.BigEndian.PutUint32(nonce[noncePrefixLen:], counter)
	if final {
		nonce[11] = 1
	}
	return nonce
}

func newGCM(dek []byte) (cipher.AEAD, error) {
	if len(dek) != dekLen {
		return nil, fmt.Errorf("dek must be %d bytes, got %d", dekLen, len(dek))
	}
	block, err := aes.NewCipher(dek)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

// encryptWriter frames plaintext written to it into a WKB1 stream on dst.
// The header (including the freshly wrapped random DEK) is written by the
// constructor; Close seals the final frame and does NOT close dst.
type encryptWriter struct {
	dst     io.Writer
	gcm     cipher.AEAD
	prefix  []byte
	counter uint32
	buf     []byte
}

func newEncryptWriter(dst io.Writer, pubPEM string) (*encryptWriter, error) {
	pub, err := parsePublicKeyPEM(pubPEM)
	if err != nil {
		return nil, err
	}
	dek := make([]byte, dekLen)
	if _, err := rand.Read(dek); err != nil {
		return nil, err
	}
	wrapped, err := rsa.EncryptOAEP(sha256.New(), rand.Reader, pub, dek, nil)
	if err != nil {
		return nil, fmt.Errorf("wrap DEK: %w", err)
	}
	gcm, err := newGCM(dek)
	if err != nil {
		return nil, err
	}
	prefix := make([]byte, noncePrefixLen)
	if _, err := rand.Read(prefix); err != nil {
		return nil, err
	}
	header := make([]byte, 0, 6+len(wrapped)+noncePrefixLen)
	header = append(header, wkbMagic...)
	header = binary.BigEndian.AppendUint16(header, uint16(len(wrapped)))
	header = append(header, wrapped...)
	header = append(header, prefix...)
	if _, err := dst.Write(header); err != nil {
		return nil, err
	}
	return &encryptWriter{dst: dst, gcm: gcm, prefix: prefix}, nil
}

func (w *encryptWriter) Write(p []byte) (int, error) {
	w.buf = append(w.buf, p...)
	for len(w.buf) >= cryptChunk {
		if err := w.seal(w.buf[:cryptChunk], false); err != nil {
			return 0, err
		}
		w.buf = w.buf[cryptChunk:]
	}
	return len(p), nil
}

func (w *encryptWriter) Close() error {
	return w.seal(w.buf, true)
}

func (w *encryptWriter) seal(chunk []byte, final bool) error {
	ct := w.gcm.Seal(nil, frameNonce(w.prefix, w.counter, final), chunk, nil)
	w.counter++
	_, err := w.dst.Write(ct)
	return err
}

// decryptReader unframes a WKB1 stream given the already-unwrapped DEK (the
// control plane sends it per import op — the agent itself cannot unwrap).
type decryptReader struct {
	src     io.Reader
	gcm     cipher.AEAD
	prefix  []byte
	counter uint32
	plain   []byte
	done    bool
}

func newDecryptReader(src io.Reader, dek []byte) (*decryptReader, error) {
	gcm, err := newGCM(dek)
	if err != nil {
		return nil, err
	}
	head := make([]byte, 6)
	if _, err := io.ReadFull(src, head); err != nil {
		return nil, fmt.Errorf("read header: %w", err)
	}
	if string(head[:4]) != wkbMagic {
		return nil, errors.New("not a WKB1 stream")
	}
	wrapLen := int64(binary.BigEndian.Uint16(head[4:6]))
	if _, err := io.CopyN(io.Discard, src, wrapLen); err != nil { // agent can't unwrap — skip
		return nil, fmt.Errorf("skip wrapped dek: %w", err)
	}
	prefix := make([]byte, noncePrefixLen)
	if _, err := io.ReadFull(src, prefix); err != nil {
		return nil, fmt.Errorf("read nonce prefix: %w", err)
	}
	return &decryptReader{src: src, gcm: gcm, prefix: prefix}, nil
}

func (r *decryptReader) Read(p []byte) (int, error) {
	for len(r.plain) == 0 {
		if r.done {
			return 0, io.EOF
		}
		if err := r.nextFrame(); err != nil {
			return 0, err
		}
	}
	n := copy(p, r.plain)
	r.plain = r.plain[n:]
	return n, nil
}

func (r *decryptReader) nextFrame() error {
	frame := make([]byte, cryptChunk+gcmTagLen)
	n, err := io.ReadFull(r.src, frame)
	final := false
	switch {
	case err == nil:
		// full-size frame: non-final by the frame rule
	case errors.Is(err, io.ErrUnexpectedEOF) && n >= gcmTagLen:
		final = true
	case errors.Is(err, io.EOF):
		return errors.New("truncated stream: missing final frame")
	default:
		return fmt.Errorf("corrupt frame: %w", err)
	}
	plain, err := r.gcm.Open(nil, frameNonce(r.prefix, r.counter, final), frame[:n], nil)
	if err != nil {
		return errors.New("backup failed integrity check (wrong DEK or tampered stream)")
	}
	r.counter++
	r.plain = plain
	r.done = final
	return nil
}
