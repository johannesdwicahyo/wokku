require "test_helper"

class TemplateDeployJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
    @user = users(:one)
  end

  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      TemplateDeployJob.perform_later(
        template_slug: "wordpress",
        app_name: "wp-test",
        server_id: @server.id,
        user_id: @user.id
      )
    end
  end

  test "raises when template slug not found" do
    err = assert_raises(RuntimeError) do
      TemplateDeployJob.perform_now(
        template_slug: "nonexistent-template-xyz",
        app_name: "test-app",
        server_id: @server.id,
        user_id: @user.id
      )
    end
    assert_match(/Template not found/, err.message)
  end

  test "calls TemplateDeployer and marks deploy succeeded on success" do
    fake_app = AppRecord.new(name: "fake-app", server: @server, team: @server.team, creator: @user)
    fake_app.save(validate: false)

    fake_result = { success: true, app: fake_app, log: [ { step: "Done" } ] }
    deploy = deploys(:one)

    TemplateRegistry.class_eval do
      alias_method :original_initialize, :initialize
      alias_method :original_find, :find
      define_method(:initialize) { }
      define_method(:find) { |_slug| { slug: "fake-tmpl", name: "Fake Template" } }
    end

    TemplateDeployer.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |**_kwargs| }
      define_method(:deploy!) { fake_result }
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    TemplateDeployJob.perform_now(
      template_slug: "fake-tmpl",
      app_name: "fake-app",
      server_id: @server.id,
      user_id: @user.id,
      deploy_id: deploy.id
    )

    assert_equal "succeeded", deploy.reload.status
  ensure
    TemplateRegistry.class_eval do
      alias_method :initialize, :original_initialize
      alias_method :find, :original_find
      remove_method :original_initialize
      remove_method :original_find
    end
    TemplateDeployer.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :deploy!
    end
    fake_app&.destroy rescue nil
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end

  test "marks deploy failed when deployer returns failure" do
    fake_result = { success: false, error: "something went wrong", log: [] }
    deploy = deploys(:one)

    TemplateRegistry.class_eval do
      alias_method :original_initialize, :initialize
      alias_method :original_find, :find
      define_method(:initialize) { }
      define_method(:find) { |_slug| { slug: "fail-tmpl", name: "Fail Template" } }
    end

    TemplateDeployer.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |**_kwargs| }
      define_method(:deploy!) { fake_result }
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    TemplateDeployJob.perform_now(
      template_slug: "fail-tmpl",
      app_name: "test-app",
      server_id: @server.id,
      user_id: @user.id,
      deploy_id: deploy.id
    )

    assert_equal "failed", deploy.reload.status
  ensure
    TemplateRegistry.class_eval do
      alias_method :initialize, :original_initialize
      alias_method :find, :original_find
      remove_method :original_initialize
      remove_method :original_find
    end
    TemplateDeployer.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :deploy!
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end
end
