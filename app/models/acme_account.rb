class AcmeAccount < ApplicationRecord
  encrypts :private_key_pem

  # One account row per ACME directory (prod/staging). Generates a fresh
  # RSA account key on first use; reused on every subsequent issuance so
  # we keep a single Let's Encrypt account.
  def self.current(directory:, contact: "mailto:#{ENV.fetch('LETSENCRYPT_EMAIL', 'admin@wokku.cloud')}")
    find_or_create_by!(directory: directory) do |a|
      a.private_key_pem = OpenSSL::PKey::RSA.new(4096).to_pem
      a.contact = contact
    end
  end

  def private_key
    OpenSSL::PKey::RSA.new(private_key_pem)
  end
end
