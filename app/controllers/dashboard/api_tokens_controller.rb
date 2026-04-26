module Dashboard
  class ApiTokensController < BaseController
    def create
      _token, @plain_token = ApiToken.create_with_token!(
        user: current_user,
        name: params[:name] || "token-#{Time.current.to_i}",
        expires_at: nil
      )
      @tokens = current_user.api_tokens.active.order(created_at: :desc)
    end

    def destroy
      token = current_user.api_tokens.find(params[:id])
      token.revoke!
      @tokens = current_user.api_tokens.active.order(created_at: :desc)
      @plain_token = nil
    end
  end
end
