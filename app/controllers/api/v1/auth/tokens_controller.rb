module Api
  module V1
    module Auth
      class TokensController < Api::V1::BaseController
        def index
          tokens = current_user.api_tokens.active.select(:id, :name, :last_used_at, :expires_at, :created_at)
          render json: tokens
        end

        def create
          token, plain_token = ApiToken.create_with_token!(
            user: current_user,
            name: params[:name] || "token-#{Time.current.to_i}",
            expires_at: params[:expires_at]
          )
          render json: { id: token.id, token: plain_token, name: token.name }, status: :created
        end

        def destroy
          token = current_user.api_tokens.find(params[:id])
          token.revoke!
          render json: { message: "Token revoked" }
        end
      end
    end
  end
end
