# frozen_string_literal: true

require "base64"
require "openssl"

# AES-256-GCM file encryption for DB backups. Object layout: [12-byte IV]
# [16-byte GCM auth tag][ciphertext]. Key from BACKUP_ENCRYPTION_KEY (base64 of
# 32 raw bytes). Authenticated — decrypt raises on tampering or wrong key.
class BackupCipher
  class Error < StandardError; end

  IV_LEN  = 12
  TAG_LEN = 16
  CHUNK   = 64 * 1024

  # Streams plain_path through AES-256-GCM in CHUNK-sized reads (constant
  # memory for GB-scale backups). The GCM tag is only known after the whole
  # stream is processed, so we reserve its slot with a placeholder and seek
  # back to fill it in once encryption finishes.
  #
  # Returns the path of a plain File (via Tempfile.create — no GC finalizer, so
  # the path won't be unlinked out from under the caller). The caller owns it
  # and must unlink it. On any failure the half-written output is removed here.
  def self.encrypt_file(plain_path)
    key = key!
    cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
    cipher.key = key
    iv = cipher.random_iv
    out = Tempfile.create([ "backup_enc", ".bin" ])
    out.binmode
    out.write(iv)
    out.write("\0" * TAG_LEN)
    File.open(plain_path, "rb") do |f|
      while (chunk = f.read(CHUNK))
        out.write(cipher.update(chunk))
      end
    end
    out.write(cipher.final)
    out.seek(IV_LEN)
    out.write(cipher.auth_tag(TAG_LEN))
    out.close
    out.path
  rescue
    cleanup(out)
    raise
  end

  # Streams enc_path through AES-256-GCM in CHUNK-sized reads (constant
  # memory for GB-scale backups). Only the IV+tag header is read eagerly;
  # the rest is decrypted straight to the output Tempfile.
  #
  # Returns the path of a plain File (via Tempfile.create — no GC finalizer).
  # The caller owns it and must unlink it (it holds decrypted plaintext, so
  # leaving it around is an exposure window). On any failure — including a
  # tampered blob failing the GCM check mid-stream — the partial plaintext
  # output is removed here before re-raising.
  def self.decrypt_file(enc_path)
    key = key!
    cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
    cipher.key = key
    out = nil
    File.open(enc_path, "rb") do |f|
      header = f.read(IV_LEN + TAG_LEN)
      raise Error, "ciphertext too short" if header.nil? || header.bytesize < IV_LEN + TAG_LEN

      cipher.iv = header.byteslice(0, IV_LEN)
      cipher.auth_tag = header.byteslice(IV_LEN, TAG_LEN)

      out = Tempfile.create([ "backup_dec", ".gz" ])
      out.binmode
      while (chunk = f.read(CHUNK))
        out.write(cipher.update(chunk))
      end
      out.write(cipher.final)
      out.close
      out.path
    end
  rescue OpenSSL::Cipher::CipherError => e
    cleanup(out)
    raise Error, "backup failed integrity check: #{e.message}"
  rescue
    cleanup(out)
    raise
  end

  # Best-effort removal of a half-written output File. Tempfile.create has no
  # GC finalizer, so orphans no longer self-heal — every failure path must
  # come through here. Swallows errors (nil handle, already-unlinked).
  def self.cleanup(file)
    return unless file

    file.close unless file.closed?
    File.unlink(file.path)
  rescue
    nil
  end

  def self.key!
    raw = ENV["BACKUP_ENCRYPTION_KEY"]
    raise Error, "BACKUP_ENCRYPTION_KEY not set" if raw.blank?

    key = Base64.strict_decode64(raw)
    raise Error, "BACKUP_ENCRYPTION_KEY must decode to 32 bytes" unless key.bytesize == 32

    key
  end
end
