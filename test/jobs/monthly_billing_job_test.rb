require "test_helper"

class MonthlyBillingJobTest < ActiveJob::TestCase
  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      MonthlyBillingJob.perform_later
    end
  end

  test "skips users with zero usage" do
    # No ResourceUsage records — total_cents == 0, no invoice created
    # We test indirectly: the fixture users have no usage records,
    # so running the job should create no invoices for the current period.
    period_start = 1.month.ago.beginning_of_month
    ref_one = "INV-#{users(:one).id}-#{period_start.strftime('%Y%m')}"
    ref_two = "INV-#{users(:two).id}-#{period_start.strftime('%Y%m')}"

    assert_no_difference "Invoice.count" do
      MonthlyBillingJob.perform_now
    end
  end

  test "creates invoice and calls iPaymu for users with billable usage" do
    user = users(:one)
    period_start = 1.month.ago.beginning_of_month
    period_end = 1.month.ago.end_of_month

    usage = ResourceUsage.create!(
      user: user,
      resource_type: "container",
      resource_id_ref: "AppRecord:1",
      tier_name: "basic",
      price_cents_per_hour: 10.0,
      started_at: period_start,
      stopped_at: period_end
    )

    fake_result = { "Status" => 200, "Data" => { "Url" => "https://pay.example.com/1", "SessionID" => "sess_abc" } }

    IpaymuClient.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { }
      define_method(:create_redirect_payment) { |**_kwargs| { "Status" => 200, "Data" => { "Url" => "https://pay.example.com/1", "SessionID" => "sess_abc" } } }
    end

    assert_difference "Invoice.count", 1 do
      MonthlyBillingJob.perform_now
    end

    invoice = Invoice.last
    assert_equal user, invoice.user
    assert_equal "pending", invoice.status
    assert invoice.ipaymu_payment_url.present?
  ensure
    IpaymuClient.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :create_redirect_payment
    end
    usage&.destroy
    Invoice.where(user: user).delete_all
  end

  test "does not duplicate invoices for the same period" do
    user = users(:one)
    period_start = 1.month.ago.beginning_of_month
    ref = "INV-#{user.id}-#{period_start.strftime('%Y%m')}"

    Invoice.create!(
      user: user,
      amount_cents: 100,
      amount_idr: 16000,
      reference_id: ref,
      period_label: period_start.strftime("%B %Y"),
      due_date: Time.current + 3.days,
      status: :pending
    )

    usage = ResourceUsage.create!(
      user: user,
      resource_type: "container",
      resource_id_ref: "AppRecord:1",
      tier_name: "basic",
      price_cents_per_hour: 10.0,
      started_at: period_start,
      stopped_at: period_start + 1.hour
    )

    IpaymuClient.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { }
      define_method(:create_redirect_payment) { |**_kwargs| { "Status" => 200, "Data" => {} } }
    end

    assert_no_difference "Invoice.count" do
      MonthlyBillingJob.perform_now
    end
  ensure
    IpaymuClient.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :create_redirect_payment
    end
    usage&.destroy
    Invoice.where(user: user).delete_all
  end
end
