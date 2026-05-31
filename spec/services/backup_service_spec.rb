# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackupService do
  describe "#export_command" do
    it "returns correct command for postgres" do
      db = DatabaseService.new(name: "my-db", service_type: "postgres")
      service = described_class.new(db)
      expect(service.send(:export_command)).to eq("postgres:export my-db")
    end

    it "returns correct command for mysql" do
      db = DatabaseService.new(name: "my-db", service_type: "mysql")
      service = described_class.new(db)
      expect(service.send(:export_command)).to eq("mysql:export my-db")
    end
  end

  describe "#generate_s3_key" do
    it "generates timestamped path" do
      db = DatabaseService.new(name: "my-db", service_type: "postgres")
      service = described_class.new(db)
      key = service.send(:generate_s3_key, "wokku-backups")
      expect(key).to match(%r{wokku-backups/postgres/my-db/\d{4}-\d{2}-\d{2}})
    end
  end
end
