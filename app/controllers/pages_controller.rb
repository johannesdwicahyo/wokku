# OSS stub for PagesController.
#
# The full wokku-cloud PagesController is stripped via .oss-ignore
# (marketing/landing/pricing/competitor pages don't make sense in OSS).
# But devise/sessions/new.html.erb references terms_path + privacy_path
# at sign-in, so the route helpers must exist. We ship a no-op
# controller with the four routes the views call.

class PagesController < ApplicationController
  def terms
    render plain: "Self-hosted Wokku install — no terms of service apply. " \
                  "See https://wokku.cloud/terms for the managed-cloud terms."
  end

  def privacy
    render plain: "Self-hosted Wokku install — no telemetry, no data leaves your server. " \
                  "See https://wokku.cloud/privacy for the managed-cloud privacy policy."
  end

  def faq
    render plain: "See https://github.com/johannesdwicahyo/wokku for documentation."
  end

  def changelog
    render plain: "See https://github.com/johannesdwicahyo/wokku/releases for the changelog."
  end
end
