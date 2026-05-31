# frozen_string_literal: true

require "rails_helper"

RSpec.describe TemplateDeployer do
  it "builds deploy steps from template" do
    template = {
      slug: "rails-tailwind",
      name: "Rails + Tailwind",
      repo: "https://github.com/rails/rails-new",
      branch: "main",
      addons: [ { "type" => "postgres", "tier" => "mini" } ],
      env: { "RAILS_ENV" => "production" },
      post_deploy: "bin/rails db:migrate"
    }

    deployer = described_class.new(
      template: template,
      app_name: "my-test-app",
      server: servers(:one),
      user: users(:one)
    )

    steps = deployer.build_steps
    expect(steps[0][:action]).to eq(:create_app)
    expect(steps[1][:action]).to eq(:provision_addon)
    expect(steps[2][:action]).to eq(:set_env)
    expect(steps[3][:action]).to eq(:deploy)
    expect(steps[4][:action]).to eq(:post_deploy)
  end
end
