# frozen_string_literal: true

require "rails_helper"

RSpec.describe Molecules::OauthButtonComponent, type: :component do
  it "renders the wide GitHub button: POST, no Turbo, tracked, decorative icon" do
    render_inline(described_class.new(provider: :github, wide: true))
    form = page.find("form[action='/users/auth/github'][method='post']")
    expect(form[:class]).to include("col-span-2")
    btn = form.find("button")
    expect(btn[:"aria-label"]).to eq("Continue with GitHub")
    expect(btn.text.squish).to eq("Continue with GitHub")
    expect(btn[:"data-turbo"]).to eq("false")
    expect(btn[:"data-track-event-value"]).to eq("signup_started")
    expect(JSON.parse(btn[:"data-track-props-value"])).to eq("provider" => "github")
    expect(btn).to have_css("svg[aria-hidden='true']", visible: :all)
  end

  it "renders a narrow button with the bare provider name and the full accessible name" do
    render_inline(described_class.new(provider: :google_oauth2))
    btn = page.find("form[action='/users/auth/google_oauth2'] button")
    expect(btn.text.squish).to eq("Google")
    expect(btn[:"aria-label"]).to eq("Continue with Google")
    expect(JSON.parse(btn[:"data-track-props-value"])).to eq("provider" => "google")
    expect(page.find("form")[:class].to_s).not_to include("col-span-2")
  end

  it "localizes the accessible name" do
    I18n.with_locale(:id) { render_inline(described_class.new(provider: :bitbucket)) }
    expect(page.find("button")[:"aria-label"]).to eq("Lanjut pakai Bitbucket")
  end

  it "rejects an unknown provider" do
    expect { described_class.new(provider: :myspace) }.to raise_error(KeyError)
  end
end
