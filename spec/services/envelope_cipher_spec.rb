require "rails_helper"

RSpec.describe EnvelopeCipher do
  let(:key) { OpenSSL::PKey::RSA.new(File.read(Rails.root.join("spec/fixtures/envelope/test_key.pem"))) }

  # Encrypts content into a WKB1 tempfile; both paths are cleaned by the test process exiting Tempfile scope — leaks are bounded to the test run.
  def encrypt(content)
    plain = Tempfile.create([ "plain", ".bin" ])
    plain.binmode
    plain.write(content)
    plain.close
    described_class.encrypt_file(plain.path, public_key: key.public_key)
  end

  def roundtrip(content)
    enc = encrypt(content)
    dec = described_class.decrypt_file(enc, private_key: key)
    File.binread(dec)
  end

  describe "round-trips" do
    it "content spanning multiple frames" do
      content = Random.bytes(described_class::CHUNK * 2 + 1234)
      expect(roundtrip(content)).to eq(content)
    end

    it "empty content (one empty final frame)" do
      expect(roundtrip("")).to eq("")
    end

    it "content that is an exact multiple of the frame size" do
      content = Random.bytes(described_class::CHUNK)
      expect(roundtrip(content)).to eq(content)
    end
  end

  describe "integrity" do
    it "raises on truncation (final frame removed)" do
      enc = encrypt(Random.bytes(described_class::CHUNK)) # 1 full frame + empty final frame (16B)
      blob = File.binread(enc)
      File.binwrite(enc, blob.byteslice(0, blob.bytesize - 16))
      expect { described_class.decrypt_file(enc, private_key: key) }
        .to raise_error(EnvelopeCipher::Error, /truncated/)
    end

    it "raises on a flipped ciphertext byte" do
      enc = encrypt("hello world")
      blob = File.binread(enc).dup
      blob[blob.bytesize - 5] = (blob.getbyte(blob.bytesize - 5) ^ 0xFF).chr
      File.binwrite(enc, blob)
      expect { described_class.decrypt_file(enc, private_key: key) }
        .to raise_error(EnvelopeCipher::Error, /integrity/)
    end

    it "raises on a non-envelope blob" do
      f = Tempfile.create([ "legacy", ".enc" ])
      f.binmode
      f.write(Random.bytes(64))
      f.close
      expect { described_class.decrypt_file(f.path, private_key: key) }
        .to raise_error(EnvelopeCipher::Error, /WKB1/)
    end

    it "raises Error (not ArgumentError) on a file truncated inside the header" do
      f = Tempfile.create([ "tiny", ".enc" ])
      f.binmode
      f.write("WKB1X") # magic matches, header cut off
      f.close
      expect { described_class.decrypt_file(f.path, private_key: key) }
        .to raise_error(EnvelopeCipher::Error, /truncated header/)
    end
  end

  describe ".unwrap_dek" do
    it "recovers a 32-byte DEK from the header bytes alone" do
      enc = encrypt("payload")
      dek = described_class.unwrap_dek(File.binread(enc, 1024), private_key: key)
      expect(dek.bytesize).to eq(32)
    end

    it "raises with the wrong private key" do
      enc = encrypt("payload")
      other = OpenSSL::PKey::RSA.new(2048)
      expect { described_class.unwrap_dek(File.binread(enc, 1024), private_key: other) }
        .to raise_error(EnvelopeCipher::Error)
    end

    it "raises on non-envelope bytes" do
      expect { described_class.unwrap_dek("not-an-envelope", private_key: key) }
        .to raise_error(EnvelopeCipher::Error, /WKB1/)
    end
  end

  describe ".envelope?" do
    it "is true for envelope files, false for anything else" do
      expect(described_class.envelope?(encrypt("x"))).to be(true)
      f = Tempfile.create([ "gz", ".gz" ])
      f.binmode
      f.write("\x1f\x8b plain gzip")
      f.close
      expect(described_class.envelope?(f.path)).to be(false)
    end
  end

  describe "key sourcing" do
    it ".master_private_key reads credentials and .public_key_pem derives a PKIX PEM" do
      pem = File.read(Rails.root.join("spec/fixtures/envelope/test_key.pem"))
      allow(Rails.application.credentials).to receive(:dig).with(:backup_envelope, :private_key).and_return(pem)
      expect(described_class.master_private_key).to be_a(OpenSSL::PKey::RSA)
      expect(described_class.public_key_pem).to start_with("-----BEGIN PUBLIC KEY-----")
    end

    it "raises a clear error when the credential is missing" do
      allow(Rails.application.credentials).to receive(:dig).with(:backup_envelope, :private_key).and_return(nil)
      expect { described_class.master_private_key }
        .to raise_error(EnvelopeCipher::Error, /backup_envelope\.private_key/)
    end
  end

  describe "cross-language format pin" do
    it "decrypts a wokkud(Go)-encrypted fixture byte-for-byte" do
      fixture = Rails.root.join("spec/fixtures/envelope/go_encrypted.bin").to_s
      dec = described_class.decrypt_file(fixture, private_key: key)
      expect(File.binread(dec)).to eq(File.binread(Rails.root.join("spec/fixtures/envelope/plain.txt")))
    ensure
      File.unlink(dec) if dec && File.exist?(dec)
    end
  end
end
