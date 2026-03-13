require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "inv-test@example.com", password: "password123456")
  end

  test "valid invoice" do
    inv = Invoice.new(user: @user, amount_cents: 700, status: :paid, stripe_invoice_id: "inv_123")
    assert inv.valid?
  end

  test "default status is pending" do
    inv = Invoice.new(user: @user, amount_cents: 700)
    assert_equal "pending", inv.status
  end

  test "enum statuses" do
    inv = Invoice.new(user: @user, amount_cents: 700)
    inv.status = :paid
    assert inv.paid?
    inv.status = :failed
    assert inv.failed?
    inv.status = :refunded
    assert inv.refunded?
  end
end
