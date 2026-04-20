# Be sure to restart your server when you modify this file.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data, "https://fonts.gstatic.com"
    policy.img_src     :self, :data, :https
    policy.object_src  :none
    policy.script_src  :self, "https://cdn.jsdelivr.net"
    policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.connect_src :self, "wss://wokku.cloud", "https://wokku.cloud"
    policy.frame_src   :none
    policy.base_uri    :self
    policy.form_action :self,
                       "https://sandbox.ipaymu.com",
                       "https://sandbox-payment.ipaymu.com",
                       "https://my.ipaymu.com",
                       "https://payment.ipaymu.com",
                       "https://accounts.google.com",
                       "https://github.com"
  end

  # Report violations without enforcing initially.
  config.content_security_policy_report_only = true
end
