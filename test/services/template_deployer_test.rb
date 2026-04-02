require "test_helper"

class TemplateDeployerTest < ActiveSupport::TestCase
  test "builds deploy steps from template" do
    template = {
      slug: "rails-tailwind",
      name: "Rails + Tailwind",
      repo: "https://github.com/rails/rails-new",
      branch: "main",
      addons: [ { "type" => "postgres", "tier" => "mini" } ],
      env: { "RAILS_ENV" => "production" },
      post_deploy: "bin/rails db:migrate"
    }

    deployer = TemplateDeployer.new(
      template: template,
      app_name: "my-test-app",
      server: servers(:one),
      user: users(:one)
    )

    steps = deployer.build_steps
    assert_equal :create_app, steps[0][:action]
    assert_equal :provision_addon, steps[1][:action]
    assert_equal :set_env, steps[2][:action]
    assert_equal :deploy, steps[3][:action]
    assert_equal :post_deploy, steps[4][:action]
  end
end
