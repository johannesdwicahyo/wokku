# Email sign-in code (SignInCodes::Issue / Verify). Step 1 is the email
# field on the sign-in page; step 2 (show) takes the 6-digit code. The
# pending email lives only in the session, never in a URL. Step 1 answers
# the same way whether or not the email has an account. Rate limits live in
# config/initializers/rack_attack.rb.
#
# Turnstile gates create only. A resend rides on the human check of the
# create that started the chain, for at most HUMAN_FOR.
class Users::SignInCodesController < DeviseController
  include TwoFactorSignIn

  SESSION_KEYS = %i[sign_in_code_email sign_in_code_started_at sign_in_code_human_at sign_in_code_resend_at].freeze
  HUMAN_FOR = 30.minutes

  # prepend: last declared runs first, so the flag is checked before anything.
  prepend_before_action :require_no_authentication
  prepend_before_action :require_enabled
  before_action :load_pending_email, only: %i[show verify resend]

  def create
    # Form body only: Rack::Attack keys on req.POST["email"], so the query
    # string or a JSON body must not be able to name a different email.
    return head :unprocessable_content unless request.form_data?

    email = SignInCode.normalize(request.request_parameters["email"])
    return render_step_one(t("sign_in_codes.invalid_email"), email) unless SignInCodes::Issue.valid_format?(email)
    return render_step_one(t("sign_in_codes.bot_check_failed"), email) unless human?

    session[:sign_in_code_human_at] = Time.current.to_i
    issue(email)
  end

  def show
  end

  def verify
    result = SignInCodes::Verify.call(email: @email, code: params[:code], ip: request.remote_ip)
    if result.error
      @code_error = t(result.error == :locked ? "sign_in_codes.locked" : "sign_in_codes.mismatch")
      return render :show, status: :unprocessable_content
    end

    clear_pending_code
    note_signup if result.new_user
    flash[:notice] = t("devise.sessions.signed_in") if sign_in_with_two_factor(result.user)
  end

  def resend
    if Time.current.to_i - session[:sign_in_code_human_at].to_i >= HUMAN_FOR
      clear_pending_code
      return redirect_to new_user_session_path, notice: t("sign_in_codes.start_again")
    end

    issue(@email)
  end

  # "Use a different email".
  def destroy
    clear_pending_code
    redirect_to new_user_session_path
  end

  private

  def require_enabled
    head :not_found unless Wokku.config.email_sign_in
  end

  def issue(email)
    result = SignInCodes::Issue.call(email: email, ip: request.remote_ip, locale: I18n.locale)
    session[:sign_in_code_email] = email
    session[:sign_in_code_started_at] = Time.current.to_i
    # The step-2 countdown runs to Issue's real wait (45 s after a sent code).
    session[:sign_in_code_resend_at] = Time.current.to_i + (result.status == :cooldown ? result.wait : SignInCode::RESEND_AFTER.to_i)
    notice = t("sign_in_codes.cooldown", n: result.wait) if result.status == :cooldown
    redirect_to users_sign_in_code_path, notice: notice
  end

  # Turnstile runs before Issue, so a failed check never hints at accounts.
  def human?
    !Turnstile.enabled? || Turnstile.verify(token: params["cf-turnstile-response"], ip: request.remote_ip, host: request.host)
  end

  def load_pending_email
    @email = session[:sign_in_code_email]
    return if @email.present? && Time.current.to_i - session[:sign_in_code_started_at].to_i < SignInCode::TTL

    clear_pending_code
    redirect_to new_user_session_path, notice: t("sign_in_codes.start_again")
  end

  def clear_pending_code
    SESSION_KEYS.each { |k| session.delete(k) }
  end

  def render_step_one(message, email)
    @email_error = message
    self.resource = resource_class.new(email: email)
    render "devise/sessions/new", status: :unprocessable_content
  end

  # Same as Users::OmniauthCallbacksController#finish_sign_in for a first
  # sign-up (team + welcome mail already ran in Verify).
  def note_signup
    if (tmpl = session.delete(:pending_template)).present?
      flash[:deploy_template] = tmpl
    end
    flash[:posthog_event] = "signup_completed"
    flash[:posthog_props] = { provider: "email" }
  end
end
