# Keep secrets out of the self-host logs: passwords, tokens, 2FA codes
# (otp_code / otp_attempt / otp_backup_codes match :otp, the sign-in
# challenge and recovery codes post as `code`). Rails' default list + code.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  /\Acode\z/, :code_verifier
]
