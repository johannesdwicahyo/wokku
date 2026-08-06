module Git
  # Bare repo store for wokkud_git apps. The repo is a deploy input, not a
  # canonical store: force pushes allowed, gc'd casually, removed with the app.
  class BareRepo
    NAME_RE = /\A[a-z][a-z0-9-]{0,62}\z/
    HOOK = <<~SH
      #!/bin/sh
      exec /rails/bin/wokku-git-post-receive
    SH

    def initialize(app_name)
      raise ArgumentError, "unsafe app name" unless app_name.to_s.match?(NAME_RE)

      @app_name = app_name
    end

    def path = File.join(root, "#{@app_name}.git")
    def exists? = File.directory?(path)

    def ensure!
      return self if exists?

      FileUtils.mkdir_p(root)
      system("git", "init", "--bare", "--initial-branch=main", "--quiet", path, exception: true)
      system("git", "-C", path, "config", "receive.maxInputSize", "536870912", exception: true)
      hook = File.join(path, "hooks", "post-receive")
      File.write(hook, HOOK)
      File.chmod(0o755, hook)
      self
    end

    def remove!
      FileUtils.rm_rf(path)
    end

    private

    def root = ENV["WOKKU_GIT_REPO_ROOT"].presence || "/var/lib/wokku/git"
  end
end
