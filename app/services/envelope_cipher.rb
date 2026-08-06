# frozen_string_literal: true

require "openssl"

# WKB1 envelope encryption for wokkud-managed DB backups — the Ruby mirror of
# wokkud/internal/services/crypt.go (cross-language fixtures in
# spec/fixtures/envelope pin the wire format). Layout:
#   "WKB1" | wrap_len (2B BE) | RSA-OAEP-SHA256(DEK) | nonce prefix (7B) | frames
#   frame  = AES-256-GCM seal of a 64KiB plaintext chunk (ciphertext || 16B tag)
#   nonce  = prefix || 4B BE frame counter || 1B final flag
# Full frames are non-final; the remainder (possibly empty) is the mandatory
# final frame, so truncation is always detectable. Per-backup random DEK,
# wrapped with the control-plane public key: the agent encrypts everything but
# decrypts only when Rails unwraps and hands it a single backup's DEK.
class EnvelopeCipher
  class Error < StandardError; end

  MAGIC      = "WKB1"
  CHUNK      = 64 * 1024
  TAG_LEN    = 16
  PREFIX_LEN = 7
  DEK_LEN    = 32
  OAEP_OPTS  = {
    "rsa_padding_mode" => "oaep",
    "rsa_oaep_md" => "sha256",
    "rsa_mgf1_md" => "sha256"
  }.freeze

  # Streams plain_path into a WKB1 envelope. Returns the encrypted file's
  # path (Tempfile.create — caller owns and must unlink it). Constant memory.
  def self.encrypt_file(plain_path, public_key:)
    pub = rsa(public_key)
    dek = SecureRandom.random_bytes(DEK_LEN)
    wrapped = pub.encrypt(dek, OAEP_OPTS)
    prefix = SecureRandom.random_bytes(PREFIX_LEN)

    out = Tempfile.create([ "backup_env", ".enc" ])
    out.binmode
    out.write(MAGIC, [ wrapped.bytesize ].pack("n"), wrapped, prefix)

    counter = 0
    final_chunk = ""
    File.open(plain_path, "rb") do |f|
      while (chunk = f.read(CHUNK))
        if chunk.bytesize == CHUNK
          out.write(seal(dek, prefix, counter, false, chunk))
          counter += 1
        else
          final_chunk = chunk
          break
        end
      end
    end
    out.write(seal(dek, prefix, counter, true, final_chunk))
    out.close
    out.path
  rescue
    BackupCipher.cleanup(out)
    raise
  end

  # Streams enc_path back to plaintext. Returns the plaintext file's path
  # (Tempfile.create — caller owns it; it holds a decrypted DB dump, so
  # leaving it around is an exposure window). Raises Error on truncation,
  # tampering, wrong key, or a non-WKB1 blob.
  def self.decrypt_file(enc_path, private_key:)
    out = nil
    File.open(enc_path, "rb") do |f|
      head = f.read(6)
      raise Error, "not a WKB1 envelope" unless head&.byteslice(0, 4) == MAGIC
      raise Error, "truncated header" if head.bytesize < 6

      wrap_len = head.byteslice(4, 2).unpack1("n")
      wrapped = f.read(wrap_len)
      raise Error, "truncated header" if wrapped.nil? || wrapped.bytesize < wrap_len

      dek = unwrap_dek(head + wrapped, private_key: private_key)
      prefix = f.read(PREFIX_LEN)
      raise Error, "truncated header" if prefix.nil? || prefix.bytesize < PREFIX_LEN

      out = Tempfile.create([ "backup_env_dec", ".gz" ])
      out.binmode
      counter = 0
      loop do
        frame = f.read(CHUNK + TAG_LEN)
        raise Error, "truncated stream: missing final frame" if frame.nil?
        raise Error, "corrupt frame" if frame.bytesize < TAG_LEN

        final = frame.bytesize < CHUNK + TAG_LEN
        out.write(open_frame(dek, prefix, counter, final, frame))
        counter += 1
        break if final
      end
      out.close
      out.path
    end
  rescue OpenSSL::Cipher::CipherError
    BackupCipher.cleanup(out)
    raise Error, "backup failed integrity check (wrong key or tampered stream)"
  rescue
    BackupCipher.cleanup(out)
    raise
  end

  # Unwraps the per-backup DEK from raw header bytes (managed restores fetch
  # them via a ranged GET — no full download). Needs at least 6 + wrap_len
  # bytes; 1KB always suffices for RSA ≤ 4096.
  def self.unwrap_dek(header_bytes, private_key:)
    raise Error, "not a WKB1 envelope" unless header_bytes&.byteslice(0, 4) == MAGIC
    raise Error, "header too short" if header_bytes.bytesize < 6

    wrap_len = header_bytes.byteslice(4, 2).unpack1("n")
    wrapped = header_bytes.byteslice(6, wrap_len)
    raise Error, "header too short for wrapped DEK" if wrapped.nil? || wrapped.bytesize < wrap_len

    dek = rsa(private_key).decrypt(wrapped, OAEP_OPTS)
    raise Error, "unwrapped DEK is not #{DEK_LEN} bytes" unless dek.bytesize == DEK_LEN

    dek
  rescue OpenSSL::PKey::PKeyError => e
    raise Error, "DEK unwrap failed: #{e.message}"
  end

  def self.envelope?(path)
    File.binread(path, MAGIC.bytesize) == MAGIC
  end

  # The control-plane keypair. Private key never leaves Rails; the agent gets
  # only public_key_pem (per export op) and per-backup DEKs (per import op).
  def self.master_private_key
    pem = Rails.application.credentials.dig(:backup_envelope, :private_key)
    raise Error, "backup_envelope.private_key not set in Rails credentials" if pem.blank?

    OpenSSL::PKey::RSA.new(pem)
  end

  def self.public_key_pem
    master_private_key.public_key.to_pem
  end

  def self.rsa(key)
    key.is_a?(OpenSSL::PKey::RSA) ? key : OpenSSL::PKey::RSA.new(key)
  end
  private_class_method :rsa

  def self.seal(dek, prefix, counter, final, chunk)
    c = OpenSSL::Cipher.new("aes-256-gcm").encrypt
    c.key = dek
    c.iv = nonce(prefix, counter, final)
    ct = chunk.empty? ? "".b : c.update(chunk) # OpenSSL raises on update("")
    ct << c.final
    ct << c.auth_tag(TAG_LEN)
  end
  private_class_method :seal

  def self.open_frame(dek, prefix, counter, final, frame)
    ct = frame.byteslice(0, frame.bytesize - TAG_LEN)
    c = OpenSSL::Cipher.new("aes-256-gcm").decrypt
    c.key = dek
    c.iv = nonce(prefix, counter, final)
    c.auth_tag = frame.byteslice(-TAG_LEN, TAG_LEN)
    plain = ct.empty? ? "".b : c.update(ct)
    c.final # raises CipherError on tag mismatch
    plain
  end
  private_class_method :open_frame

  def self.nonce(prefix, counter, final)
    prefix + [ counter ].pack("N") + (final ? "\x01".b : "\x00".b)
  end
  private_class_method :nonce
end
