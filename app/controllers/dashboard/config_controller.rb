module Dashboard
  class ConfigController < BaseController
    before_action :set_app

    def index
      authorize @app, :show?
      sync_config_from_dokku
      @env_vars = @app.env_vars.order(:key)
    end

    def create
      authorize @app, :update?
      @env_var = @app.env_vars.build(env_var_params)

      if @env_var.save
        dokku_config.set(@app.name, { @env_var.key => @env_var.value })
        redirect_to dashboard_app_config_index_path(@app), notice: "#{@env_var.key} added."
      else
        @env_vars = @app.env_vars.order(:key)
        render :index, status: :unprocessable_entity
      end
    end

    def update
      authorize @app, :update?
      @env_var = @app.env_vars.find(params[:id])

      if @env_var.update(value: params[:env_var][:value])
        dokku_config.set(@app.name, { @env_var.key => @env_var.value })
        redirect_to dashboard_app_config_index_path(@app), notice: "#{@env_var.key} updated."
      else
        @env_vars = @app.env_vars.order(:key)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @app, :update?
      @env_var = @app.env_vars.find(params[:id])
      dokku_config.unset(@app.name, @env_var.key)
      @env_var.destroy
      redirect_to dashboard_app_config_index_path(@app), notice: "#{@env_var.key} removed."
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def env_var_params
      params.require(:env_var).permit(:key, :value)
    end

    def dokku_config
      client = Dokku::Client.new(@app.server)
      Dokku::Config.new(client)
    end

    def sync_config_from_dokku
      remote_vars = dokku_config.list(@app.name)
      local_keys = @app.env_vars.pluck(:key)

      # Add new vars from Dokku
      (remote_vars.keys - local_keys).each do |key|
        @app.env_vars.create!(key: key, value: remote_vars[key])
      end

      # Update existing vars if changed on server
      @app.env_vars.each do |env_var|
        if remote_vars.key?(env_var.key) && env_var.value != remote_vars[env_var.key]
          env_var.update!(value: remote_vars[env_var.key])
        end
      end

      # Remove vars deleted on server
      (local_keys - remote_vars.keys).each do |key|
        @app.env_vars.find_by(key: key)&.destroy
      end
    rescue => e
      Rails.logger.warn "Failed to sync config for #{@app.name}: #{e.message}"
    end
  end
end
