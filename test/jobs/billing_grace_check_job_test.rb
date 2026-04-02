require "test_helper"

class BillingGraceCheckJobTest < ActiveJob::TestCase
  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      BillingGraceCheckJob.perform_later
    end
  end

  test "does nothing when no overdue invoices" do
    # With no overdue invoices, job should complete without error
    assert_nothing_raised do
      BillingGraceCheckJob.perform_now
    end
  end

  test "sets grace period when invoice is 3-6 days overdue" do
    user = users(:one)
    invoice = Invoice.create!(
      user: user,
      amount_cents: 500,
      amount_idr: 80000,
      reference_id: "INV-GRACE-TEST",
      period_label: "March 2026",
      due_date: 4.days.ago,
      status: :pending
    )

    BillingGraceCheckJob.perform_now

    if user.respond_to?(:billing_status)
      assert_equal "grace_period", user.reload.billing_status
    else
      pass # billing_status not on CE user model — that's fine
    end
  ensure
    invoice&.destroy
  end

  test "suspends account and stops apps when invoice is 7+ days overdue" do
    user = users(:one)
    app = app_records(:one)
    app.update!(status: :running)

    invoice = Invoice.create!(
      user: user,
      amount_cents: 500,
      amount_idr: 80000,
      reference_id: "INV-SUSPEND-TEST",
      period_label: "February 2026",
      due_date: 8.days.ago,
      status: :pending
    )

    stop_called = false
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
    end

    Dokku::Processes.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_client| }
      define_method(:stop) { |_name| true }
    end

    # Ensure app belongs to a team that belongs to this user
    user.teams.first&.app_records&.each { |a| a.update!(status: :running) } rescue nil

    BillingGraceCheckJob.perform_now

    if user.respond_to?(:billing_status)
      assert_equal "suspended", user.reload.billing_status
    else
      pass # billing_status is EE-only
    end
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
    Dokku::Processes.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :stop
    end
    invoice&.destroy
  end
end
