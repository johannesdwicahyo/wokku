require "rails_helper"

RSpec.describe Apps::ListStats do
  describe ".summary" do
    it "joins the known parts" do
      expect(described_class.summary(cpu_pct: 18.4, mem_mb: 410, requests_24h: 4210)).to eq("18% · 410 MB · 4.2k req/24h")
      expect(described_class.summary(cpu_pct: 3.0, mem_mb: 120, requests_24h: 980)).to eq("3% · 120 MB · 980 req/24h")
    end

    it "leaves out unknown CPU/memory and zero requests, nil when nothing is known" do
      expect(described_class.summary(cpu_pct: nil, mem_mb: nil, requests_24h: 1_500_000)).to eq("1.5M req/24h")
      expect(described_class.summary(cpu_pct: 0.0, mem_mb: 35, requests_24h: 0)).to eq("0% · 35 MB")
      expect(described_class.summary(cpu_pct: nil, mem_mb: nil, requests_24h: 0)).to be_nil
    end
  end
end
