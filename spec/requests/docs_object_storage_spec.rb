require "rails_helper"

RSpec.describe "Object storage docs", type: :request do
  %w[en id].each do |lang|
    it "serves /docs/databases/object-storage in #{lang}" do
      get "/docs/databases/object-storage", params: { lang: lang }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("s3.wokku.cloud").and include("Rp 400")
    end
  end

  it "leaves no minio_bundle references in code" do
    out = `git -C #{Wokku::Engine.root} grep -l -i minio_bundle -- app lib config spec db/seeds.rb ':!spec/requests/docs_object_storage_spec.rb' ':!app/models/plan.rb'`
    expect(out).to eq("")
  end
end
