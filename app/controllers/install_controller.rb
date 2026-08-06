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

  # wokkud/ sits at the repo root: Rails.root/wokkud in the monorepo,
  # Rails.root/../wokkud in the exported repo (harness is a subdir).
  def read_deploy_file(name)
    [ Rails.root.join("wokkud/deploy", name),
      Rails.root.join("../wokkud/deploy", name) ].each do |p|
      return p.read if p.file?
    end
    raise "wokkud deploy unit #{name} not found"
  end
end
