# Preview all emails at http://localhost:3000/rails/mailers/billing_mailer
class BillingMailerPreview < ActionMailer::Preview
  # http://localhost:3000/rails/mailers/billing_mailer/plan_gifted_solo_en
  def plan_gifted_solo_en
    user = preview_user(locale: "en")
    BillingMailer.plan_gifted(user, "solo", 3)
  end

  # http://localhost:3000/rails/mailers/billing_mailer/plan_gifted_solo_id
  def plan_gifted_solo_id
    user = preview_user(locale: "id")
    BillingMailer.plan_gifted(user, "solo", 3)
  end

  # http://localhost:3000/rails/mailers/billing_mailer/plan_gifted_pro_en
  def plan_gifted_pro_en
    Plan.find_or_create_by!(key: "pro") { |p| p.name = "Pro"; p.price_idr = 240_000 }
    user = preview_user(locale: "en")
    BillingMailer.plan_gifted(user, "pro", 1)
  end

  def invoice_issued
    user = preview_user(locale: "id")
    plan = Plan.find_by(key: "solo") || Plan.find_or_create_by!(key: "solo") { |p| p.name = "Solo"; p.price_idr = 80_000 }
    invoice = Invoice.new(
      user: user, plan: plan, amount_idr: 80_000, amount_cents: 0,
      kind: :renewal, status: :pending,
      period_start: Date.current, period_end: Date.current.next_month,
      period_label: Date.current.strftime("%B %Y"),
      due_date: 7.days.from_now,
      reference_id: "INV-preview-#{SecureRandom.hex(4)}"
    )
    BillingMailer.invoice_issued(user, invoice)
  end

  def apps_suspended
    user = preview_user
    BillingMailer.apps_suspended(user)
  end

  def apps_restored
    user = preview_user
    BillingMailer.apps_restored(user)
  end

  private

  def preview_user(locale: "en")
    # Build, not create — the preview doesn't need to persist.
    User.new(
      email: "preview@wokku.cloud",
      name: "Preview User",
      locale: locale,
      trial_ends_at: 3.months.from_now,
      billing_anchor_date: 3.months.from_now.to_date
    ).tap do |u|
      u.id = "00000000-0000-0000-0000-000000000000" # for url helpers
      Plan.find_or_create_by!(key: "solo") { |p| p.name = "Solo"; p.price_idr = 80_000 }
    end
  end
end
