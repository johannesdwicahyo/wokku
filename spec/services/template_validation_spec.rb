# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Template validation" do
  let(:registry) { TemplateRegistry.new }

  it "all templates have required fields" do
    registry.all.each do |template|
      expect(template[:name]).to be_present, "#{template[:slug]} missing name"
      expect(template[:slug]).to be_present, "template missing slug"
      expect(template[:category]).to be_present, "#{template[:slug]} missing category"
    end
  end

  it "all templates have docker-compose.yml" do
    registry.all.each do |template|
      path = TemplateRegistry::TEMPLATES_PATH.join(template[:slug], "docker-compose.yml")
      expect(File.exist?(path)).to be_truthy, "#{template[:slug]} missing docker-compose.yml"
    end
  end

  it "all docker_image templates reference an image" do
    # Framework starters (rails, django, nextjs, etc. — shipped 2026-05-12)
    # are git-deploy / buildpack templates and intentionally have no
    # `image:` line. Only validate the docker_image deploy method.
    registry.all.each do |template|
      path = TemplateRegistry::TEMPLATES_PATH.join(template[:slug], "docker-compose.yml")
      next unless File.exist?(path)
      content = File.read(path)
      next unless content.match?(/^#\s*deploy_method:\s*docker_image/)
      expect(content.include?("image:")).to be_truthy, "#{template[:slug]} has no image reference"
    end
  end

  it "pins every deployed image to a version, never :latest" do
    registry.all.each do |template|
      image = template[:docker_image].to_s
      next if image.empty?
      pinned = image.include?("@sha256:") || image.split("/").last.match?(/:(?!latest\z)\S+\z/)
      expect(pinned).to be(true), "#{template[:slug]} deploys unpinned image #{image}"
    end
  end
end
