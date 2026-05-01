module Dashboard
  class SshKeysController < BaseController
    def create
      @key = current_user.ssh_public_keys.build(ssh_key_params)
      @created = @key.save
      track("ssh_key.added", target: @key, metadata: { name: @key.name, fingerprint: @key.fingerprint&.first(16) }) if @created
      @keys = current_user.ssh_public_keys.order(created_at: :desc)
    end

    def destroy
      key = current_user.ssh_public_keys.find(params[:id])
      name = key.name
      key.destroy!
      track("ssh_key.removed", metadata: { name: name })
      @keys = current_user.ssh_public_keys.order(created_at: :desc)
      @key = nil
    end

    private

    def ssh_key_params
      params.require(:ssh_public_key).permit(:name, :public_key)
    end
  end
end
