# Serves the connect-a-server installer. The script is PUBLIC — the
# ingest token the operator passes to it is the secret; the wokkud
# binary is compiled into the control-plane image (WOKKUD_BINARY_PATH)
# so installs work pre-release and air-gapped.
class InstallController < ActionController::API
  def script
    template = Wokku::Engine.root.join("lib/wokku/install/wokkud.sh.erb").read
    body = ERB.new(template, trim_mode: "-").result_with_hash(
      control_url: request.base_url,
      wokkud_unit: read_deploy_file("wokkud.service"),
      caddy_unit: read_deploy_file("wokku-caddy.service")
    )
    render plain: body, content_type: "text/x-shellscript"
  end

  def binary
    path = ENV["WOKKUD_BINARY_PATH"].to_s
    unless path.present? && File.file?(path)
      return render plain: "wokkud binary not bundled in this deployment (WOKKUD_BINARY_PATH)", status: :not_found
    end
    send_file path, filename: "wokkud", type: "application/octet-stream"
  end

  private

  # wokkud/ ships inside this repo, so read it from the engine root — the
  # git-gem checkout in wokku-cloud, the repo root standalone (harness/ is
  # the host app there). Not Rails.root: the host app has no wokkud/.
  def read_deploy_file(name)
    Wokku::Engine.root.join("wokkud/deploy", name).read
  end
end
