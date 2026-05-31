# frozen_string_literal: true

require "rails_helper"

RSpec.describe TemplateDeployJob, type: :job do
  let(:server) { servers(:one) }
  let(:user) { users(:one) }

  it "can be enqueued" do
    expect {
      described_class.perform_later(
        template_slug: "wordpress",
        app_name: "wp-test",
        server_id: server.id,
        user_id: user.id
      )
    }.to have_enqueued_job(described_class)
  end

  it "raises when template slug not found" do
    expect {
      described_class.perform_now(
        template_slug: "nonexistent-template-xyz",
        app_name: "test-app",
        server_id: server.id,
        user_id: user.id
      )
    }.to raise_error(RuntimeError, /Template not found/)
  end

  describe "with a deploy record" do
    let(:deploy) { deploys(:one) }

    before do
      allow_any_instance_of(TemplateRegistry).to receive(:find)
        .and_return({ slug: "fake-tmpl", name: "Fake Template" })
      allow_any_instance_of(TemplateDeployer).to receive(:initialize).and_return(nil)
      allow(DeployChannel).to receive(:broadcast_to).and_return(nil)
    end

    it "marks deploy succeeded on TemplateDeployer success" do
      fake_app = AppRecord.new(name: "fake-app", server: server, team: server.team, creator: user)
      fake_app.save(validate: false)
      allow_any_instance_of(TemplateDeployer).to receive(:deploy!).and_return(
        { success: true, app: fake_app, log: [ { step: "Done" } ] }
      )

      described_class.perform_now(
        template_slug: "fake-tmpl",
        app_name: "fake-app",
        server_id: server.id,
        user_id: user.id,
        deploy_id: deploy.id
      )

      expect(deploy.reload.status).to eq("succeeded")
    end

    it "marks deploy failed when deployer returns failure" do
      allow_any_instance_of(TemplateDeployer).to receive(:deploy!).and_return(
        { success: false, error: "something went wrong", log: [] }
      )

      described_class.perform_now(
        template_slug: "fail-tmpl",
        app_name: "test-app",
        server_id: server.id,
        user_id: user.id,
        deploy_id: deploy.id
      )

      expect(deploy.reload.status).to eq("failed")
    end
  end
end
