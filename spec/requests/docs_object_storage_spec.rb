require "rails_helper"

RSpec.describe "Object storage docs", type: :request do
  context "when object storage is enabled" do
    before { allow(Wokku.config).to receive(:object_storage?).and_return(true) }

    %w[en id].each do |lang|
      it "serves /docs/databases/object-storage in #{lang} and lists it in the sidebar" do
        get "/docs/databases/object-storage", params: { lang: lang }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("s3.wokku.cloud").and include("Rp 400")
        get "/docs/getting-started/first-deploy", params: { lang: lang }
        expect(response.body).to include("databases/object-storage")
      end
    end

    it "includes the page in the search index" do
      get "/docs/search-index.json"
      expect(response.parsed_body.pluck("path")).to include("databases/object-storage")
    end
  end

  context "when object storage is disabled" do
    before { allow(Wokku.config).to receive(:object_storage?).and_return(false) }

    %w[en id].each do |lang|
      it "404s the page and hides it from the #{lang} sidebar" do
        get "/docs/databases/object-storage", params: { lang: lang }
        expect(response).to have_http_status(:not_found)
        get "/docs/getting-started/first-deploy", params: { lang: lang }
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("databases/object-storage")
      end
    end

    it "leaves the page out of the search index" do
      get "/docs/search-index.json"
      expect(response.parsed_body.pluck("path")).not_to include("databases/object-storage")
    end
  end

  it "leaves no minio_bundle references in code" do
    out = `git -C #{Wokku::Engine.root} grep -l -i minio_bundle -- app lib config spec db/seeds.rb ':!spec/requests/docs_object_storage_spec.rb' ':!app/models/plan.rb'`
    expect(out).to eq("")
  end
end
