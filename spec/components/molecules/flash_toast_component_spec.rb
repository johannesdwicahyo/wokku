require "rails_helper"

RSpec.describe Molecules::FlashToastComponent, type: :component do
  it "renders nothing when flash is empty" do
    render_inline(described_class.new(flash: ActionDispatch::Flash::FlashHash.new))
    expect(page).not_to have_css('[data-controller~="motion--flash-toast"]')
  end

  it "renders a success toast for flash[:notice]" do
    fh = ActionDispatch::Flash::FlashHash.new
    fh[:notice] = "Saved"
    render_inline(described_class.new(flash: fh))
    expect(page).to have_text("Saved")
    expect(page).to have_css('[data-motion--flash-toast-kind-value="success"]')
  end
end
