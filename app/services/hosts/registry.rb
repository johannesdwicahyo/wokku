# frozen_string_literal: true

require "shellwords"

module Hosts
  # Local per-host docker registry (registry:2 bound to 127.0.0.1:5000,
  # started by wokkud/deploy/install.sh). It exists because `dokku
  # git:from-image` ALWAYS PULLS (never uses local tags) and dokku's
  # post-deploy cleanup force-rmis old image ids — so it serves both
  # wokkud-built images and durable rollback tags. All calls run host-side
  # against loopback via Hosts::Ssh#run_raw; the registry is never
  # exposed off-host.
  class Registry
    HOST = "127.0.0.1:5000"

    def initialize(client)
      @client = client
    end

    # Tags an existing local image into the registry and pushes it.
    # Returns the registry ref (what image_ref should become).
    def push(local_tag)
      ref = "#{HOST}/#{local_tag}"
      @client.run_raw("docker tag #{Shellwords.escape(local_tag)} #{Shellwords.escape(ref)} && docker push #{Shellwords.escape(ref)}")
      ref
    end

    def tags(repo)
      # curl -sf + 404 (repo never pushed) → non-zero exit → run_raw raises CommandError.
      # Empty list is the expected "missing" signal.
      out = @client.run_raw("curl -sf http://#{HOST}/v2/#{Shellwords.escape(repo)}/tags/list")
      Array(JSON.parse(out.to_s)["tags"]).compact
    rescue JSON::ParserError, Hosts::Ssh::CommandError
      []
    end

    # Registry API deletes by manifest DIGEST, not tag — resolve first.
    # Requires REGISTRY_STORAGE_DELETE_ENABLED=true on the container
    # (install.sh sets it). Deleting only unlinks; the weekly
    # garbage-collect cron reclaims blob disk.
    def delete_tag(repo, tag)
      # curl -sfI + 404 (tag already gone) → run_raw raises CommandError → no-op.
      head =
        begin
          @client.run_raw(
            "curl -sfI -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' " \
            "-H 'Accept: application/vnd.oci.image.manifest.v1+json' " \
            "http://#{HOST}/v2/#{Shellwords.escape(repo)}/manifests/#{Shellwords.escape(tag)}"
          )
        rescue Hosts::Ssh::CommandError
          ""
        end
      digest = head.to_s[/docker-content-digest:\s*(\S+)/i, 1]
      return unless digest

      @client.run_raw("curl -sf -X DELETE http://#{HOST}/v2/#{Shellwords.escape(repo)}/manifests/#{Shellwords.escape(digest)}")
      nil
    end
  end
end
