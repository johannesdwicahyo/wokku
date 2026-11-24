require "rails_helper"

RSpec.describe Atoms::LightsLoaderComponent, type: :component do
  it "renders seven squares, one live, as a labelled status" do
    render_inline(described_class.new(size: :md))
    expect(page).to have_css("span[role='status'][aria-label='Loading'].wk-lights-md")
    expect(page).to have_css("span.wk-lights-sq", count: 7)
    expect(page).to have_css("span.wk-lights-live", count: 1)
  end

  it "uses a custom label and the sm/lg sizes" do
    render_inline(described_class.new(size: :lg, label: "Deploying"))
    expect(page).to have_css("[aria-label='Deploying'].wk-lights-lg")
  end

  it "localises the default label" do
    I18n.with_locale(:id) { render_inline(described_class.new) }
    expect(page).to have_css("[role='status'][aria-label='Memuat']")
  end
end

RSpec.describe "Loading indicators" do
  it "left no legacy spinners in app code" do
    files = Dir[Rails.root.join("..", "app", "{views,components,javascript}", "**", "*.{erb,rb,js}")]
    expect(files).not_to be_empty
    offenders = files.select { |f| File.read(f).match?(/animate-spin|wk-spin\b|wk-spinner/) }
    expect(offenders).to be_empty
  end

  it "has loading.default in en and id" do
    expect(I18n.t("loading.default", locale: :en)).to eq("Loading")
    expect(I18n.t("loading.default", locale: :id)).to eq("Memuat")
  end

  it "renders the spinning button with the sm loader" do
    html = ApplicationController.render(partial: "dashboard/shared/spinning_button", locals: { label: "Restarting", classes: "x" })
    expect(html).to include("wk-lights-sm")
    expect(html).not_to include("animate-spin")
  end
end
