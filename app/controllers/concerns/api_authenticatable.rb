module ApiAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_token!
    attr_reader :current_api_token
  end

  private

  def authenticate_api_token!
    token_string = extract_token_from_header
    if token_string.blank?
      render json: ApiErrors.payload(:missing_token), status: :unauthorized
      return
    end

    @current_api_token = ApiToken.find_by_token(token_string)
    if @current_api_token.nil? || !@current_api_token.active?
      render json: ApiErrors.payload(:invalid_token), status: :unauthorized
      return
    end

    if @current_api_token.read_only? && !(request.get? || request.head?)
      render json: ApiErrors.payload(:insufficient_scope), status: :forbidden
      return
    end

    @current_api_token.touch_last_used!
    sign_in(@current_api_token.user, store: false) if respond_to?(:sign_in)
  end

  # Secrets (env values, DSNs, bucket keys) go to members+ on a full token
  # only; a read token sees them masked like a team viewer.
  def reveal_secrets?(record)
    !current_api_token&.read_only? && policy(record).update?
  end

  def extract_token_from_header
    header = request.headers["Authorization"]
    header&.match(/^Bearer\s+(.+)$/)&.captures&.first
  end

  def current_user
    @current_api_token&.user || super
  end
end
