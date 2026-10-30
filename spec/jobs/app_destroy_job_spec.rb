require "rails_helper"

RSpec.describe AppDestroyJob, type: :job do
  it "destroys the app through Apps::Destroyer" do
    app = create(:app_record)
    expect(Apps::Destroyer).to receive(:call).with(app, progress: an_instance_of(Apps::DeletionProgress)).and_call_original
    allow(Wokku.config.dns_provider).to receive(:delete_app_record)
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, remove!: true))
    described_class.perform_now(app.id)
    expect(AppRecord.where(id: app.id)).not_to exist
  end

  it "is a no-op when the app is already gone" do
    expect(Apps::Destroyer).not_to receive(:call)
    described_class.perform_now(SecureRandom.uuid)
  end

  it "retries later when a deploy started meanwhile" do
    app = create(:app_record)
    app.deploys.create!(status: :building)
    expect { described_class.perform_now(app.id) }.to have_enqueued_job(described_class).with(app.id)
    expect(AppRecord.where(id: app.id)).to exist
  end
end
