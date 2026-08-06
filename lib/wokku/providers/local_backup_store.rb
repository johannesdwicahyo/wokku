require "fileutils"

module Wokku
  class Providers
    # OSS default backup_store: platform artifacts (deploy tarballs,
    # control-plane dumps) on the local filesystem. Same interface as the
    # managed DeployArchiveStore (S3/R2). presigned_* return nil — a
    # filesystem has no presignable URL; the OSS remote-upload/build-fetch
    # flow is Phase 3 (self-host) work.
    class LocalBackupStore
      def configured? = true

      def put(key, io)
        path = resolve(key)
        FileUtils.mkdir_p(File.dirname(path))
        # Write-then-rename so a concurrent exists?/read never sees a
        # partially written file (rename is atomic within one dir on POSIX).
        tmp = "#{path}.tmp-#{Process.pid}"
        File.open(tmp, "wb") { |f| IO.copy_stream(io, f) }
        File.rename(tmp, path)
      end

      def exists?(key) = File.file?(resolve(key))

      def delete(key)
        FileUtils.rm_f(resolve(key))
      end

      def list_keys(prefix)
        base = root
        # FNM_DOTMATCH: dotfile keys must be listable or retention can
        # never prune them (File.file? already excludes the ./.. entries).
        Dir.glob(File.join(base, "**", "*"), File::FNM_DOTMATCH).select { |p| File.file?(p) }
           .map { |p| p.delete_prefix("#{base}/") }
           .select { |k| k.start_with?(prefix) }
      end

      def presigned_put(key, expires_in: nil) = nil
      def presigned_get(key, expires_in: nil) = nil

      # Local files can't be presigned, but they CAN be served: the agent
      # archive endpoint (api/v1/agent/archive) uses this to send_file the
      # artifact behind a signed short-lived token.
      def path(key) = resolve(key)

      private

      def root
        # expand_path normalizes trailing-slash and relative roots (either
        # silently broke list_keys' prefix-stripping).
        # ponytail: glob metacharacters ([, {) in the path stay unsupported.
        File.expand_path(ENV.fetch("WOKKU_BACKUP_PATH") { Rails.root.join("storage", "backups").to_s })
      end

      def resolve(key)
        raise ArgumentError, "backup key must not contain '..': #{key.inspect}" if key.split("/").include?("..")
        File.join(root, key)
      end
    end
  end
end
