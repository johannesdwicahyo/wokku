module Dashboard
  class ConfigController < BaseController
    before_action :set_app

    def index
      authorize @app, :show?
      # EnvVar rows ARE the truth (B6 W2 / W3 flip) — the control plane owns
      # runtime env for every app.
      @env_vars = @app.env_vars.order(:key)
      @env_schema = load_env_schema
    end

    def create
      authorize @app, :update?
      @env_var = @app.env_vars.build(env_var_params)

      if @env_var.save
        redirect_to dashboard_app_config_index_path(@app), notice: "#{@env_var.key} added. Restart the app for changes to take effect."
      else
        @env_vars = @app.env_vars.order(:key)
        render :index, status: :unprocessable_entity
      end
    end

    def update
      authorize @app, :update?
      @env_var = @app.env_vars.find(params[:id])

      if @env_var.update(value: params[:env_var][:value])
        redirect_to dashboard_app_config_index_path(@app), notice: "#{@env_var.key} updated. Restart the app for changes to take effect."
      else
        @env_vars = @app.env_vars.order(:key)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @app, :update?
      @env_var = @app.env_vars.find(params[:id])
      @env_var.destroy
      redirect_to dashboard_app_config_index_path(@app), notice: "#{@env_var.key} removed. Restart the app for changes to take effect."
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def env_var_params
      params.require(:env_var).permit(:key, :value)
    end

    # Backlog 1.4 — read the app.json the user shipped (HEAD of the app's
    # bare repo — W7 Phase 3, no on-host dokku copy anymore) and validate
    # its `env` block against currently-set keys. Returns
    # AppJson::EnvValidator::EMPTY when no schema declared (most apps);
    # the view simply hides the panel in that case.
    def load_env_schema
      AppJson::EnvValidator.call(app_json: repo_app_json, env_keys: @env_vars.pluck(:key))
    rescue => e
      Rails.logger.warn "env schema load failed for #{@app.name}: #{e.message}"
      AppJson::EnvValidator::EMPTY
    end

    # app.json at the bare repo's HEAD, {} when the repo/file is absent.
    def repo_app_json
      repo = Git::BareRepo.new(@app.name)
      return {} unless repo.exists?

      raw = IO.popen([ "git", "-C", repo.path, "show", "HEAD:app.json" ], err: File::NULL, &:read)
      return {} unless $?.success?

      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end
  end
end
