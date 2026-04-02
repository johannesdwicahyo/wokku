module Api
  module V1
    class SshKeysController < BaseController
      def index
        keys = policy_scope(SshPublicKey)
        render json: keys.select(:id, :name, :fingerprint, :created_at)
      end

      def create
        key = current_user.ssh_public_keys.build(ssh_key_params)
        authorize key

        if key.save
          render json: key.as_json(only: [ :id, :name, :fingerprint, :created_at ]), status: :created
        else
          render json: { errors: key.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        key = current_user.ssh_public_keys.find(params[:id])
        authorize key
        key.destroy!
        render json: { message: "SSH key removed" }
      end

      private

      def ssh_key_params
        params.permit(:name, :public_key)
      end
    end
  end
end
