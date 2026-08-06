package services

import (
	"bytes"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/binary"
	"encoding/pem"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// testKeyPair loads the committed test-only RSA key shared with the Ruby
// specs (spec/fixtures/envelope/test_key.pem) and derives the PKIX public
// PEM — the exact string Rails sends in export op params.
func testKeyPair(t *testing.T) (*rsa.PrivateKey, string) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "spec", "fixtures", "envelope", "test_key.pem"))
	if err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		t.Fatal("no PEM block in test_key.pem")
	}
	var priv *rsa.PrivateKey
	if k, err := x509.ParsePKCS8PrivateKey(block.Bytes); err == nil {
		priv = k.(*rsa.PrivateKey)
	} else if k, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		priv = k
	} else {
		t.Fatalf("test_key.pem is neither PKCS8 nor PKCS1: %v", err)
	}
	pubDER, err := x509.MarshalPKIXPublicKey(&priv.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	pubPEM := string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubDER}))
	return priv, pubPEM
}

// unwrapDEK is TEST-ONLY: the agent proper never unwraps (encrypt-only trust
// model) — tests unwrap to verify their own output round-trips.
func unwrapDEK(t *testing.T, priv *rsa.PrivateKey, blob []byte) []byte {
	t.Helper()
	if string(blob[:4]) != wkbMagic {
		t.Fatalf("magic = %q, want %q", blob[:4], wkbMagic)
	}
	wrapLen := int(binary.BigEndian.Uint16(blob[4:6]))
	dek, err := rsa.DecryptOAEP(sha256.New(), nil, priv, blob[6:6+wrapLen], nil)
	if err != nil {
		t.Fatalf("unwrap: %v", err)
	}
	return dek
}

func encryptBytes(t *testing.T, pubPEM string, plain []byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	w, err := newEncryptWriter(&buf, pubPEM)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write(plain); err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func decryptBytes(t *testing.T, dek, blob []byte) ([]byte, error) {
	t.Helper()
	r, err := newDecryptReader(bytes.NewReader(blob), dek)
	if err != nil {
		return nil, err
	}
	return io.ReadAll(r)
}

func TestEnvelopeRoundTrips(t *testing.T) {
	priv, pubPEM := testKeyPair(t)
	for name, plain := range map[string][]byte{
		"multi-frame":    bytes.Repeat([]byte("x"), cryptChunk*2+1234),
		"empty":          {},
		"exact-multiple": bytes.Repeat([]byte("y"), cryptChunk),
	} {
		blob := encryptBytes(t, pubPEM, plain)
		got, err := decryptBytes(t, unwrapDEK(t, priv, blob), blob)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if !bytes.Equal(got, plain) {
			t.Errorf("%s: round-trip mismatch (got %d bytes, want %d)", name, len(got), len(plain))
		}
	}
}

func TestEnvelopeDetectsTruncation(t *testing.T) {
	priv, pubPEM := testKeyPair(t)
	blob := encryptBytes(t, pubPEM, bytes.Repeat([]byte("z"), cryptChunk)) // full frame + empty final (16B)
	_, err := decryptBytes(t, unwrapDEK(t, priv, blob), blob[:len(blob)-16])
	if err == nil || !strings.Contains(err.Error(), "truncated") {
		t.Fatalf("want truncation error, got %v", err)
	}
}

func TestEnvelopeDetectsTampering(t *testing.T) {
	priv, pubPEM := testKeyPair(t)
	blob := encryptBytes(t, pubPEM, []byte("hello world"))
	blob[len(blob)-5] ^= 0xFF
	if _, err := decryptBytes(t, unwrapDEK(t, priv, blob), blob); err == nil {
		t.Fatal("want integrity error on flipped byte, got nil")
	}
}

func TestEnvelopeDetectsFrameReorder(t *testing.T) {
	priv, pubPEM := testKeyPair(t)
	blob := encryptBytes(t, pubPEM, bytes.Repeat([]byte("r"), cryptChunk*2)) // 2 full frames + empty final
	dek := unwrapDEK(t, priv, blob)
	headerLen := 6 + 256 + noncePrefixLen // 2048-bit test key → 256-byte wrap
	frame := cryptChunk + gcmTagLen
	swapped := append([]byte{}, blob...)
	copy(swapped[headerLen:], blob[headerLen+frame:headerLen+2*frame])
	copy(swapped[headerLen+frame:], blob[headerLen:headerLen+frame])
	if _, err := decryptBytes(t, dek, swapped); err == nil {
		t.Fatal("want integrity error on swapped frames, got nil")
	}
}

func TestDecryptRejectsWrongDEKLenAndBadMagic(t *testing.T) {
	if _, err := newDecryptReader(bytes.NewReader([]byte("WKB1....")), []byte("short")); err == nil {
		t.Fatal("want error for non-32-byte dek")
	}
	dek := make([]byte, dekLen)
	if _, err := newDecryptReader(bytes.NewReader([]byte("not-an-envelope")), dek); err == nil {
		t.Fatal("want error for bad magic")
	}
}

func fixturePath(name string) string {
	return filepath.Join("..", "..", "..", "spec", "fixtures", "envelope", name)
}

// Run once with WRITE_FIXTURES=1 to (re)generate go_encrypted.bin — the blob
// the Ruby spec must decrypt. Committed; regenerate only on format change.
func TestGenerateGoFixture(t *testing.T) {
	if os.Getenv("WRITE_FIXTURES") != "1" {
		t.Skip("fixture generator; run with WRITE_FIXTURES=1")
	}
	_, pubPEM := testKeyPair(t)
	plain, err := os.ReadFile(fixturePath("plain.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(fixturePath("go_encrypted.bin"), encryptBytes(t, pubPEM, plain), 0o644); err != nil {
		t.Fatal(err)
	}
}

// The cross-language pin: Ruby-encrypted bytes must decrypt in Go.
func TestDecryptRubyFixture(t *testing.T) {
	priv, _ := testKeyPair(t)
	blob, err := os.ReadFile(fixturePath("ruby_encrypted.bin"))
	if err != nil {
		t.Fatal(err)
	}
	want, err := os.ReadFile(fixturePath("plain.txt"))
	if err != nil {
		t.Fatal(err)
	}
	got, err := decryptBytes(t, unwrapDEK(t, priv, blob), blob)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want) {
		t.Errorf("ruby fixture round-trip mismatch (got %d bytes, want %d)", len(got), len(want))
	}
}
