require "rails_helper"
require "tmpdir"

RSpec.describe Docs::ApiSlice do
  let(:titles) { [ "Apps and deploys", "Add-ons", "Domains", "Email and storage", "Team and billing", "Auth and tokens" ] }

  def with_spec(doc)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "v1.yaml")
      File.write(path, doc.to_yaml)
      allow(Wokku.config).to receive(:openapi_path).and_return(Pathname(path))
      yield
    end
  end

  def op(tag, extra = {}) = { "tags" => Array(tag), "responses" => { "200" => { "description" => "ok" } } }.merge(extra)

  describe "against the engine's openapi/v1.yaml" do
    it "lists the constraint table's groups, keys and titles in order" do
      expect(described_class::GROUPS.map { |g| [ g[:key], g[:title][:en] ] }).to eq(
        %w[apps addons domains email-storage team-billing auth].zip(titles)
      )
    end

    it "maps every tag in the spec to a group" do
      expect(described_class.unmapped_tags).to eq([])
    end

    it "puts /api/v1/apps in Apps and deploys and drops apps.dokku" do
      paths = described_class.for("apps")["paths"]
      expect(paths).to include("/api/v1/apps")
      expect(paths).not_to include("/api/v1/apps/{id}/dokku")
      ops = described_class::GROUPS.map { |g| g[:key] }.flat_map { |k| described_class.for(k)&.dig("paths")&.values || [] }
      expect(ops.flat_map(&:values).grep(Hash).map { |o| o["operationId"] }).not_to include("apps.dokku")
    end

    it "drops every operation whose operationId ends in .dokku (incl. servers.dokku)" do
      ids = described_class::KEYS.flat_map { |k| described_class.for(k)&.dig("paths")&.values || [] }
                                 .flat_map(&:values).grep(Hash).filter_map { |o| o["operationId"] }
      expect(ids.grep(/\.dokku\z/)).to eq([])
    end

    it "builds every group slice as a self-contained OpenAPI 3 document" do
      described_class.groups.each do |g|
        slice = described_class.for(g[:key])
        expect(slice.keys).to include("openapi", "info", "paths", "components", "tags")
        expect(slice["paths"]).not_to be_empty
        expect(slice["components"]["securitySchemes"]).to be_present
        refs = slice.to_json.scan(%r{"#/components/(\w+)/([^"]+)"})
        refs.each { |sec, name| expect(slice.dig("components", sec, name)).to be_present, "#{g[:key]}: #{sec}/#{name}" }
      end
    end

    it "gives every group a default intro with the bearer header and an example call" do
      described_class::GROUPS.each do |g|
        expect(g[:intro]).to include("Authorization: Bearer", "curl -H", "/docs/api/authentication"), g[:key]
      end
    end

    it "hides a group with no operations, and returns nil for it" do
      with_spec("openapi" => "3.0.3", "info" => { "title" => "t", "version" => "v1" }, "paths" => { "/api/v1/apps" => { "get" => op("apps") } }) do
        expect(described_class.groups.map { |g| g[:key] }).to eq(%w[apps])
        expect(described_class.for("team-billing")).to be_nil
        expect(described_class.for("nope")).to be_nil
      end
    end
  end

  describe "slicing" do
    before { allow(Wokku.config).to receive(:object_storage?).and_return(true) }

    let(:doc) do
      {
        "openapi" => "3.0.3", "info" => { "title" => "t", "version" => "v1" },
        "security" => [ { "bearer" => [] } ],
        "tags" => [ { "name" => "apps", "description" => "Apps **live** here." }, { "name" => "domains", "description" => "Domains." } ],
        "components" => {
          "securitySchemes" => { "bearer" => { "type" => "http", "scheme" => "bearer" }, "other" => { "type" => "apiKey", "in" => "header", "name" => "X" } },
          "schemas" => {
            "App" => { "type" => "object", "properties" => { "owner" => { "$ref" => "#/components/schemas/User" } } },
            "User" => { "type" => "object", "properties" => { "boss" => { "$ref" => "#/components/schemas/User" } } },
            "Unused" => { "type" => "string" }
          },
          "parameters" => { "Id" => { "name" => "id", "in" => "path", "required" => true, "schema" => { "type" => "string" } } }
        },
        "paths" => {
          "/api/v1/apps/{id}" => {
            "parameters" => [ { "$ref" => "#/components/parameters/Id" } ],
            "get" => op("apps", "responses" => { "200" => { "description" => "ok", "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/App" } } } } }),
            "delete" => op("apps", "x-internal" => true)
          },
          "/api/v1/secret" => { "post" => op("apps", "x-internal" => true) },
          "/api/v1/domains" => { "get" => op("domains") },
          "/api/v1/tunnels" => { "get" => op(%w[tunnels cloud]) },
          "/api/v1/mail/send" => { "post" => op("cloud") },
          "/api/v1/billing/invoices" => { "get" => op(%w[billing cloud]) },
          "/api/v1/plans" => { "get" => op("cloud") },
          "/api/v1/whatever" => { "get" => op("cloud") },
          "/api/v1/brand_new" => { "get" => op("brand_new") }
        }
      }
    end

    it "keeps nested $refs (cycles included), drops unreferenced components, keeps every security scheme" do
      with_spec(doc) do
        slice = described_class.for("apps")
        expect(slice["components"]["schemas"].keys).to contain_exactly("App", "User")
        expect(slice["components"]["parameters"].keys).to eq(%w[Id])
        expect(slice["components"]["securitySchemes"].keys).to contain_exactly("bearer", "other")
        expect(slice["security"]).to eq([ { "bearer" => [] } ])
      end
    end

    it "drops x-internal operations and empty paths" do
      with_spec(doc) do
        paths = described_class.for("apps")["paths"]
        expect(paths["/api/v1/apps/{id}"].keys).to contain_exactly("parameters", "get")
        expect(paths).not_to include("/api/v1/secret")
      end
    end

    it "splits the cloud tag by path and sends unmapped tags to apps" do
      with_spec(doc) do
        expect(described_class.for("domains")["paths"].keys).to eq(%w[/api/v1/domains /api/v1/tunnels])
        expect(described_class.for("email-storage")["paths"].keys).to eq(%w[/api/v1/mail/send])
        expect(described_class.for("team-billing")["paths"].keys).to eq(%w[/api/v1/billing/invoices /api/v1/plans])
        expect(described_class.for("apps")["paths"].keys).to include("/api/v1/whatever", "/api/v1/brand_new")
        expect(described_class.unmapped_tags).to eq(%w[brand_new])
        expect(described_class.for("domains")["paths"]["/api/v1/tunnels"]["get"]["tags"]).to eq(%w[tunnels])
      end
    end

    it "lists only the group's tags, with their descriptions, and uses the engine default intro (not tag descriptions)" do
      with_spec(doc) do
        expect(described_class.for("domains")["tags"]).to eq([ { "name" => "domains", "description" => "Domains." }, { "name" => "tunnels" } ])
        default = described_class::GROUPS.find { |g| g[:key] == "apps" }[:intro]
        expect(described_class.groups.find { |g| g[:key] == "apps" }[:intro_md]).to eq(default)
        expect(described_class.for("apps")["info"]).to include("title" => "Apps and deploys", "description" => default)
      end
    end

    it "prefers Wokku.config.docs_api_group_intros over the engine default" do
      with_spec(doc) do
        allow(Wokku.config).to receive(:docs_api_group_intros).and_return({ "domains" => "Point a name at an app." })
        expect(described_class.for("domains")["info"]["description"]).to eq("Point a name at an app.")
        expect(described_class.groups.find { |g| g[:key] == "domains" }[:intro_md]).to eq("Point a name at an app.")
        default = described_class::GROUPS.find { |g| g[:key] == "team-billing" }[:intro]
        expect(described_class.for("team-billing")["info"]["description"]).to eq(default)
      end
    end

    it "drops tunnel_authorize.* and .dokku operationIds" do
      extra = doc.merge("paths" => doc["paths"].merge(
        "/api/v1/tunnels/authorize" => { "post" => op("tunnels", "operationId" => "tunnel_authorize.create") },
        "/api/v1/domains/x" => { "get" => op("domains", "operationId" => "domains.index") }
      ))
      with_spec(extra) do
        paths = described_class.for("domains")["paths"]
        expect(paths).not_to include("/api/v1/tunnels/authorize")
        expect(paths).to include("/api/v1/domains/x")
      end
    end

    it "drops operationIds listed in Wokku.config.docs_api_hidden_operations, and re-slices when the list changes" do
      extra = doc.merge("paths" => doc["paths"].merge("/api/v1/domains/x" => { "get" => op("domains", "operationId" => "domains.index") }))
      with_spec(extra) do
        expect(described_class.for("domains")["paths"]).to include("/api/v1/domains/x")
        allow(Wokku.config).to receive(:docs_api_hidden_operations).and_return([ "domains.index" ])
        expect(described_class.for("domains")["paths"]).not_to include("/api/v1/domains/x")
      end
    end

    it "hides the Email and storage group unless object storage is configured" do
      with_spec(doc) do
        allow(Wokku.config).to receive(:object_storage?).and_return(false)
        expect(described_class.for("email-storage")).to be_nil
        expect(described_class.groups.map { |g| g[:key] }).not_to include("email-storage")
        allow(Wokku.config).to receive(:object_storage?).and_return(true)
        expect(described_class.for("email-storage")).to be_present
        expect(described_class.groups.map { |g| g[:key] }).to include("email-storage")
      end
    end

    it "defaults docs_api_hidden_operations to an empty array" do
      expect(Wokku::Providers.new.docs_api_hidden_operations).to eq([])
    end

    it "anchors the cloud path split on whole segments" do
      with_spec(doc.merge("paths" => { "/api/v1/mailer_stats" => { "get" => op("cloud") }, "/api/v1/plans_x" => { "get" => op("cloud") } })) do
        expect(described_class.for("apps")["paths"].keys).to eq(%w[/api/v1/mailer_stats /api/v1/plans_x])
        expect(described_class.for("email-storage")).to be_nil
      end
    end

    it "has no groups when the spec file is missing" do
      allow(Wokku.config).to receive(:openapi_path).and_return(Pathname("/nonexistent/v1.yaml"))
      expect(described_class.groups).to eq([])
      expect(described_class.for("apps")).to be_nil
    end

    it "memoises per file mtime" do
      with_spec(doc) do
        first = described_class.for("apps")
        expect(described_class.for("apps")).to equal(first)
        path = Wokku.config.openapi_path
        File.write(path, doc.merge("paths" => { "/api/v1/apps" => { "get" => op("apps") } }).to_yaml)
        File.utime(Time.now + 5, Time.now + 5, path)
        expect(described_class.for("apps")["paths"].keys).to eq(%w[/api/v1/apps])
      end
    end
  end
end
