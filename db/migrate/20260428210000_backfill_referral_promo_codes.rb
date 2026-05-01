class BackfillReferralPromoCodes < ActiveRecord::Migration[8.1]
  # Phase 3 ships an after_create on User that auto-generates a referral
  # code, but every pre-existing user joined before this branch and has
  # nothing. Walk them once and call the same generator the after_create
  # uses — it's idempotent (skips users who already have a code) so a
  # rerun is harmless.
  def up
    return unless defined?(User) && defined?(PromoCode)
    User.find_each do |u|
      u.ensure_referral_promo_code!
    rescue StandardError => e
      say "ensure_referral_promo_code! failed for user #{u.id}: #{e.message}"
    end
  end

  def down
    PromoCode.where(kind: "referral").destroy_all
  end
end
