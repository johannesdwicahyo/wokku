require "rails_helper"

RSpec.describe Molecules::DbSummaryCardComponent, type: :component do
  let(:app) { create(:app_record) }

  it "renders without a primary database (no card snapshot exists yet)" do
    render_inline(described_class.new(app: app))
    expect(page).to have_text("// postgres")
  end

  describe "stat readings" do
    let(:db) { instance_double("DatabaseService") }
    let(:component) { described_class.new(app: app) }

    before do
      allow(app).to receive(:primary_database).and_return(db)
      allow(db).to receive(:respond_to?).with(:size_mb_max).and_return(false)
    end

    it "returns 0 across the board when no stats snapshot has been collected" do
      allow(db).to receive_message_chain(:stats_snapshots, :order, :first).and_return(nil)
      expect(component.usage_mb).to eq(0)
      expect(component.connections).to eq(0)
      expect(component.max_conn).to eq(0)
      expect(component.pct).to eq(0)
    end

    it "reads bytes from the latest stats snapshot" do
      snapshot = double("snap",
        db_size_bytes: 100 * 1024 * 1024, active_connections: 4, max_connections: 100)
      allow(db).to receive_message_chain(:stats_snapshots, :order, :first).and_return(snapshot)

      expect(component.usage_mb).to eq(100.0)
      expect(component.connections).to eq(4)
      expect(component.max_conn).to eq(100)
    end
  end
end
