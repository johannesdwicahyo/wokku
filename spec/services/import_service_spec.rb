# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportService do
  let(:destination) { BackupDestination.new(bucket: "wokku-backups", region: "us-east-1", access_key_id: "AKID", secret_access_key: "SECRET") }
  let(:server) { Server.new(name: "jkt-01", host: "10.0.0.1").tap { |s| allow(s).to receive(:backup_destination).and_return(destination) } }
  let(:s3) { instance_double(Aws::S3::Client) }
  let(:uploaded) { {} }

  def db(type: "postgres", managed: true, **attrs)
    DatabaseService.new(name: "pg-main", service_type: type, server: server, wokkud_managed: managed,
                        dsn: "postgres://postgres:s3cr3t@pg-main:5432/pg-main", **attrs)
  end

  def import(database, dump = "CREATE TABLE t (id int);\n")
    described_class.new(database_service: database, dump_io: StringIO.new(dump)).perform!
  end

  before do
    allow(destination).to receive(:s3_client).and_return(s3)
    allow(s3).to receive(:put_object) { |bucket:, key:, body:| uploaded[key] = Zlib.gunzip(body.read) }
    allow(s3).to receive(:delete_object)
    allow(destination).to receive(:s3_presigned_url) { |key| "https://r2.example/#{key}" }
  end

  it "uploads the gzipped dump, runs wokkud service.import from a presigned URL, then deletes the object" do
    database = db
    expect(Services::Ops).to receive(:issue_and_wait!) do |service:, kind:, params:|
      expect(service).to eq(database)
      expect(kind).to eq("service.import")
      expect(params).to include(service_type: "postgres", password: "s3cr3t")
      expect(params[:presigned_get_url]).to start_with("https://r2.example/imports/")
    end

    expect(import(database)).to be(true)
    key = uploaded.keys.first
    expect(uploaded[key]).to eq("CREATE TABLE t (id int);\n")
    expect(s3).to have_received(:delete_object).with(bucket: "wokku-backups", key: key)
  end

  it "imports a shared tenant into its parent's container without the tenant password" do
    parent = DatabaseService.new(name: "dokku-shared-postgres", service_type: "postgres", server: server)
    tenant = db(shared: true, parent_service: parent, shared_db_name: "shop")
    expect(Services::Ops).to receive(:issue_and_wait!) do |service:, params:, **|
      expect(service).to eq(parent)
      expect(params).to include(database: "shop")
      expect(params).not_to have_key(:password)
    end
    import(tenant)
  end

  it "deletes the temp object and re-raises when the op fails (no false 'Imported')" do
    allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Failed.new(ServiceOp.new(kind: "service.import", error: "psql: syntax error", error_code: "import_failed")))
    expect { import(db) }.to raise_error(Services::Ops::Failed)
    expect(s3).to have_received(:delete_object)
  end

  it "refuses redis (not streamable) and unmanaged databases before touching storage" do
    expect { import(db(type: "redis")) }.to raise_error(described_class::UnsupportedTypeError, /redis/)
    expect { import(db(managed: false)) }.to raise_error(described_class::UnsupportedTypeError, /wokkud-managed/)
    expect(s3).not_to have_received(:put_object)
  end
end
