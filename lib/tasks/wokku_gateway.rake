namespace :wokku do
  namespace :gateway do
    desc "Generate a new SSH key pair for the wokku git gateway. Prints the "\
         "private + public halves. Store the private half as the kamal secret "\
         "WOKKU_GATEWAY_SSH_PRIVATE_KEY and the public half as "\
         "WOKKU_GATEWAY_SSH_PUBLIC_KEY. Run once per environment."
    task :generate_key do
      # ed25519 is short and fast. Let ssh-keygen do the work so the
      # output matches what OpenSSH clients expect.
      tmp = Dir.mktmpdir
      key_path = File.join(tmp, "wokku_gateway_id_ed25519")
      system("ssh-keygen", "-t", "ed25519", "-f", key_path, "-N", "", "-C", "wokku-gateway", "-q") or abort "ssh-keygen failed"
      priv = File.read(key_path)
      pub  = File.read("#{key_path}.pub").strip

      puts "── Private key (set as kamal secret WOKKU_GATEWAY_SSH_PRIVATE_KEY) ──"
      puts priv
      puts "── Public key (set as WOKKU_GATEWAY_SSH_PUBLIC_KEY; commit-safe) ──"
      puts pub
    ensure
      FileUtils.remove_entry(tmp) if tmp && Dir.exist?(tmp)
    end

    desc "Regenerate the authorized_keys file consumed by the host sshd "\
         "for the git user. Path is WOKKU_GIT_AUTHORIZED_KEYS_PATH or "\
         "/etc/wokku/git-authorized-keys. Idempotent."
    task write_authorized_keys: :environment do
      path = Git::AuthorizedKeysWriter.write!(force: true)
      n = SshPublicKey.count
      puts "Wrote #{n} key#{'s' unless n == 1} to #{path}"
    end

    desc "Preview what the authorized_keys file will look like. Doesn't write."
    task preview_authorized_keys: :environment do
      puts Git::AuthorizedKeysWriter.render
    end

    desc "Install the gateway key on every existing Server (for backfill "\
         "after enabling the gateway for the first time)."
    task install_on_all_servers: :environment do
      count = 0
      Server.find_each do |s|
        InstallGatewayKeyOnServerJob.perform_later(s.id)
        count += 1
      end
      puts "Enqueued #{count} InstallGatewayKeyOnServerJob job#{'s' unless count == 1}"
    end

    desc "Install a named key on every Server. Used during rotation to stage "\
         "a replacement key alongside the existing one. "\
         "NAME=<ssh-keys name> PUBKEY=<openssh pubkey line>"
    task add_key_to_servers: :environment do
      name = ENV["NAME"].to_s.strip
      pubkey = ENV["PUBKEY"].to_s.strip
      abort "NAME= is required" if name.empty?
      abort "PUBKEY= is required" if pubkey.empty?

      count = 0
      Server.find_each do |s|
        InstallGatewayKeyOnServerJob.perform_later(s.id, name, pubkey)
        count += 1
      end
      puts "Enqueued add of '#{name}' to #{count} server#{'s' unless count == 1}"
    end

    desc "Remove a named key from every Server's dokku ssh-keys. "\
         "NAME=<ssh-keys name>"
    task remove_key_from_servers: :environment do
      name = ENV["NAME"].to_s.strip
      abort "NAME= is required" if name.empty?
      abort "refusing to remove the active gateway key; rotate first" if name == InstallGatewayKeyOnServerJob::GATEWAY_NAME

      count = 0
      Server.find_each do |s|
        RemoveGatewayKeyFromServerJob.perform_later(s.id, name)
        count += 1
      end
      puts "Enqueued remove of '#{name}' from #{count} server#{'s' unless count == 1}"
    end
  end
end
