module Api
  module V1
    module Auth
      class TokensController < Api::V1::BaseController
        def index
          tokens = current_user.api_tokens.active.select(:id, :name, :scope, :last_used_at, :expires_at, :created_at)
          render json: tokens
        end

        def create
          expires_at = begin
            ApiToken.expiry_from(params[:expires_at])
          rescue ArgumentError
            return render_api_error(:validation_failed, message: "expires_at must be a date, a time, or \"never\"")
          end
          token, plain_token = ApiToken.create_with_token!(
            user: current_user,
            name: params[:name] || "token-#{Time.current.to_i}",
            scope: params[:scope].presence || "full",
            expires_at: expires_at
          )
          render json: { id: token.id, token: plain_token, name: token.name, scope: token.scope, expires_at: token.expires_at },
                 status: :created
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
