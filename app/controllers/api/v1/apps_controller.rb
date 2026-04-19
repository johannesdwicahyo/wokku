module Api
  module V1
    class AppsController < BaseController
      include PlanEnforceable
      before_action :enforce_free_container_limit!, only: [ :create ]

      def index
        apps = policy_scope(AppRecord)
        apps = apps.main_apps unless params[:include_previews].present?
        apps = apps.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
        render json: apps.select(:id, :name, :server_id, :team_id, :status, :is_preview, :pr_number, :parent_app_id, :created_at)
      end

      def show
        app = AppRecord.find(params[:id])
        authorize app
        render json: app.as_json.merge(
          git_remote: app.git_remote_url,
          push_instructions: "git remote add wokku #{app.git_remote_url} && git push wokku #{app.deploy_branch || 'main'}"
        )
      end

      def create
        server = Server.find(params[:server_id])
        app = server.app_records.build(
          name: params[:name],
          team: server.team,
          creator: current_user,
          deploy_branch: params[:deploy_branch] || "main",
          status: :created
        )
        authorize app

        if (limit = current_user.current_plan&.max_apps) &&
           AppRecord.joins(team: :team_memberships).where(team_memberships: { user_id: current_user.id }).distinct.count >= limit
          render json: { error: "App limit reached for your plan (#{limit})" }, status: :payment_required
          return
        end

        begin
          client = Dokku::Client.new(server)
          Dokku::Apps.new(client).create(app.name)
          app.save!
          Cloudflare::Dns.new.create_app_record(app.name, server.host) rescue nil
          track("app.created", target: app)
          render json: app.as_json.merge(
            git_remote: app.git_remote_url,
            push_instructions: "git remote add wokku #{app.git_remote_url} && git push wokku #{app.deploy_branch || 'main'}"
          ), status: :created
        rescue Dokku::Client::CommandError => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue Dokku::Client::ConnectionError => e
          render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
        end
      end

      def update
        app = AppRecord.find(params[:id])
        authorize app

        begin
          if params[:name].present? && params[:name] != app.name
            client = Dokku::Client.new(app.server)
            Dokku::Apps.new(client).rename(app.name, params[:name])
          end
          app.update!(app_params)
          render json: app
        rescue Dokku::Client::CommandError => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue Dokku::Client::ConnectionError => e
          render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
        end
      end

      def destroy
        app = AppRecord.find(params[:id])
        authorize app

        begin
          client = Dokku::Client.new(app.server)
          Dokku::Apps.new(client).destroy(app.name)
          Cloudflare::Dns.new.delete_app_record(app.name) rescue nil
          track("app.destroyed", target: app)
          app.destroy!
          render json: { message: "App destroyed" }
        rescue Dokku::Client::CommandError => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue Dokku::Client::ConnectionError => e
          render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
        end
      end

      def restart
        app = AppRecord.find(params[:id])
        authorize app
        dokku_process_action(app, :restart)
      end

      def stop
        app = AppRecord.find(params[:id])
        authorize app
        dokku_process_action(app, :stop)
      end

      def start
        app = AppRecord.find(params[:id])
        authorize app
        dokku_process_action(app, :start)
      end

      def deploy
        app = AppRecord.find(params[:id])
        authorize app, :update?

        release = app.releases.create!(description: "Deploy via API")
        deploy = app.deploys.create!(release: release, status: :pending)
        DeployJob.perform_later(deploy.id)
        track("app.deployed", target: app)

        render json: { message: "Deploy triggered", deploy_id: deploy.id, release_id: release.id }, status: :accepted
      end

      def github_connect
        app = AppRecord.find(params[:id])
        authorize app, :update?

        repo = params[:repo]
        branch = params[:branch] || "main"

        return render json: { error: "repo is required" }, status: :unprocessable_entity if repo.blank?

        app.update!(
          github_repo_full_name: repo,
          git_repository_url: "https://github.com/#{repo}.git",
          deploy_branch: branch,
          github_webhook_secret: app.github_webhook_secret || SecureRandom.hex(20)
        )

        render json: { message: "Connected to #{repo} (#{branch})", app_id: app.id, github_repo: repo, deploy_branch: branch }
      end

      def github_disconnect
        app = AppRecord.find(params[:id])
        authorize app, :update?

        app.update!(
          github_repo_full_name: nil,
          github_webhook_secret: nil
        )

        render json: { message: "GitHub disconnected" }
      end

      private

      def app_params
        params.permit(:name, :deploy_branch)
      end

      def dokku_process_action(app, action)
        client = Dokku::Client.new(app.server)
        Dokku::Processes.new(client).public_send(action, app.name)
        track("app.#{action}ed", target: app)
        render json: { message: "App #{action}ed" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end
    end
  end
end
