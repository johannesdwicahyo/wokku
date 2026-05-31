# OSS stub for routes that point at managed-cloud-only features.
#
# Dashboard views/components reference dozens of route helpers
# (dashboard_billing_path, dashboard_usage_path, etc.) that only make
# sense on wokku.cloud. Rather than patch every view, we keep the
# helpers alive in oss/config/routes.rb by pointing them at this
# controller. Each renders a single "managed-cloud feature" page that
# nudges the visitor to wokku.cloud and shows what they tried to reach.

class CloudOnlyController < ApplicationController
  def show
    feature = params[:feature].to_s.tr("_", " ").presence || "this feature"
    render plain: <<~MSG, content_type: "text/plain"
      #{feature.capitalize} is part of the managed Wokku Cloud product.

      Self-hosted Wokku covers the core web UI: apps, deploys, databases,
      domains, SSL, terminal, metrics. Billing, plans, usage, invoices,
      referrals, and admin promo codes live on wokku.cloud.

      Sign up at https://wokku.cloud — or open an issue at
      https://github.com/johannesdwicahyo/wokku/issues if you'd like to
      see this surface ship in OSS.
    MSG
  end
end
