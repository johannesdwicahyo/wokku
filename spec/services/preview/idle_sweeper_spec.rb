require "rails_helper"

RSpec.describe Preview::IdleSweeper do
  let(:server) { create(:server) }
  let(:parent) { create(:app_record, server: server) }

  before do
    allow(Lifecycle::Ops).to receive(:stop_formation).and_return({ "web" => 0 })
    allow(Lifecycle::Ops).to receive(:converge!)
  end

  it "sleeps previews idle 7d but younger than 30d" do
    p = create(:app_record, :preview, parent_app: parent, pr_number: 1,
               server: server, last_commit_at: 10.days.ago, status: :running)
    expect(Lifecycle::Ops).to receive(:converge!)
      .with(having_attributes(id: p.id), formation: { "web" => 0 }, allow_empty: true)
    described_class.sweep
    expect(p.reload.status).to eq("stopped")
  end

  it "destroys previews idle 30d+" do
    p = create(:app_record, :preview, parent_app: parent, pr_number: 2,
               server: server, last_commit_at: 31.days.ago, status: :running)
    destroyer = instance_double(Preview::Destroyer, call: true)
    expect(Preview::Destroyer).to receive(:new).with(having_attributes(id: p.id)).and_return(destroyer)
    described_class.sweep
  end

  it "leaves fresh previews alone" do
    create(:app_record, :preview, parent_app: parent, pr_number: 3,
           server: server, last_commit_at: 1.hour.ago, status: :running)
    expect(Lifecycle::Ops).not_to receive(:converge!)
    expect(Preview::Destroyer).not_to receive(:new)
    described_class.sweep
  end

  it "leaves already-stopped previews alone in the sleep band" do
    create(:app_record, :preview, parent_app: parent, pr_number: 4,
           server: server, last_commit_at: 10.days.ago, status: :stopped)
    expect(Lifecycle::Ops).not_to receive(:converge!)
    described_class.sweep
  end

  it "swallows lifecycle op failures when sleeping a preview" do
    p = create(:app_record, :preview, parent_app: parent, pr_number: 5,
               server: server, last_commit_at: 10.days.ago, status: :running)
    op = build_stubbed(:lifecycle_op, status: :failed, error: "boom", error_code: "x")
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Failed.new(op))
    expect { described_class.sweep }.not_to raise_error
    expect(p.reload.status).to eq("running") # not flipped because the call raised
  end

  it "swallows a racing Busy collision (live op already exists) without aborting the sweep" do
    p1 = create(:app_record, :preview, parent_app: parent, pr_number: 6,
                server: server, last_commit_at: 10.days.ago, status: :running)
    p2 = create(:app_record, :preview, parent_app: parent, pr_number: 7,
                server: server, last_commit_at: 10.days.ago, status: :running)
    # Real collision — a live op already in flight for p1 — surfaced through
    # the actual issue! path (no fabricated error), then wired to the one
    # converge! call the sweep would make for p1.
    create(:lifecycle_op, app_record: p1, server: server, status: :pending)
    busy = begin
      Lifecycle::Ops.issue!(p1, "stack.converge", {}, wait: false, timeout: 10)
    rescue Lifecycle::Ops::Busy => e
      e
    end
    expect(busy).to be_a(Lifecycle::Ops::Busy)

    allow(Lifecycle::Ops).to receive(:converge!)
      .with(having_attributes(id: p1.id), formation: { "web" => 0 }, allow_empty: true)
      .and_raise(busy)

    expect { described_class.sweep }.not_to raise_error
    expect(p1.reload.status).to eq("running") # not flipped, raise was swallowed
    expect(p2.reload.status).to eq("stopped") # second preview still processed
  end
end
