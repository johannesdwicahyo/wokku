# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe BackupCipher do
  def with_env(vars)
    saved = ENV.to_h
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    ENV.replace(saved)
  end

  it "round-trips a file: decrypt(encrypt(x)) == x" do
    with_env("BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32)) do
      Dir.mktmpdir do |d|
        plain = File.join(d, "p")
        File.binwrite(plain, "hello \x00 gzip bytes" * 100)
        enc = described_class.encrypt_file(plain)
        expect(File.binread(enc)).not_to eq(File.binread(plain))
        dec = described_class.decrypt_file(enc)
        expect(File.binread(dec)).to eq(File.binread(plain))
      end
    end
  end

  it "raises on a tampered ciphertext (GCM auth)" do
    with_env("BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32)) do
      Dir.mktmpdir do |d|
        plain = File.join(d, "p")
        File.binwrite(plain, "payload")
        enc = described_class.encrypt_file(plain)
        bytes = File.binread(enc).dup
        bytes[-1] = (bytes[-1].ord ^ 0x01).chr
        tampered = File.join(d, "t")
        File.binwrite(tampered, bytes)
        expect { described_class.decrypt_file(tampered) }.to raise_error(BackupCipher::Error)
      end
    end
  end

  it "removes the partial plaintext output when decrypt fails on a tampered blob" do
    with_env("BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32)) do
      Dir.mktmpdir do |d|
        plain = File.join(d, "p")
        File.binwrite(plain, "payload" * 100)
        enc = described_class.encrypt_file(plain)
        bytes = File.binread(enc).dup
        bytes[-1] = (bytes[-1].ord ^ 0x01).chr
        tampered = File.join(d, "t")
        File.binwrite(tampered, bytes)

        # Tempfile.create no longer self-heals via GC — capture the output
        # handle to prove decrypt_file unlinks it itself on the failure path.
        created = nil
        allow(Tempfile).to receive(:create).and_wrap_original do |orig, *args, **kw|
          created = orig.call(*args, **kw)
        end

        expect { described_class.decrypt_file(tampered) }.to raise_error(BackupCipher::Error)
        expect(created).not_to be_nil
        expect(File.exist?(created.path)).to be(false)
      end
    end
  end

  it "raises when the key is absent" do
    with_env("BACKUP_ENCRYPTION_KEY" => nil) do
      Dir.mktmpdir do |d|
        f = File.join(d, "p")
        File.binwrite(f, "x")
        expect { described_class.encrypt_file(f) }.to raise_error(BackupCipher::Error, /key/i)
      end
    end
  end

  it "raises on decrypt when the key is absent" do
    with_env("BACKUP_ENCRYPTION_KEY" => nil) do
      Dir.mktmpdir do |d|
        f = File.join(d, "p")
        File.binwrite(f, "x" * 32)
        expect { described_class.decrypt_file(f) }.to raise_error(BackupCipher::Error, /key/i)
      end
    end
  end

  it "raises on a too-short ciphertext file" do
    with_env("BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32)) do
      Dir.mktmpdir do |d|
        f = File.join(d, "short")
        File.binwrite(f, "x" * 10) # < IV_LEN + TAG_LEN (28)
        expect { described_class.decrypt_file(f) }.to raise_error(BackupCipher::Error, /too short/)
      end
    end
  end

  it "raises when the key decodes to the wrong byte length" do
    with_env("BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 16)) do
      Dir.mktmpdir do |d|
        f = File.join(d, "p")
        File.binwrite(f, "x")
        expect { described_class.encrypt_file(f) }.to raise_error(BackupCipher::Error, /32 bytes/)
      end
    end
  end

  it "round-trips a multi-megabyte file across many chunks" do
    with_env("BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32)) do
      Dir.mktmpdir do |d|
        plain = File.join(d, "big")
        File.binwrite(plain, SecureRandom.random_bytes(5 * 1024 * 1024))
        enc = described_class.encrypt_file(plain)
        dec = described_class.decrypt_file(enc)
        expect(File.binread(dec)).to eq(File.binread(plain))
      end
    end
  end
end
