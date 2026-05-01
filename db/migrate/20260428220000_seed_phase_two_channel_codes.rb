class SeedPhaseTwoChannelCodes < ActiveRecord::Migration[8.1]
  # Initial Phase 2 channel codes for the marketing rollout. Each maps
  # to a single distribution channel so redemption counts give us
  # per-channel attribution. Idempotent — safe to rerun if the migration
  # is reset.
  CODES = [
    { code: "LARAVELID",  description: "Laravel Indonesia community (Telegram / FB)" },
    { code: "LINKEDIN",   description: "LinkedIn launch post (Bahasa)" },
    { code: "REDDIT",     description: "r/indonesia + r/IndonesiaIT" },
    { code: "SHOWHN",     description: "Show HN launch post" },
    { code: "PRODUCTHUNT", description: "Product Hunt launch" },
    { code: "WOKKU2026",  description: "Generic launch code, IG / public" }
  ].freeze

  def up
    return unless defined?(PromoCode)
    CODES.each do |attrs|
      PromoCode.find_or_create_by!(code: attrs[:code]) do |pc|
        pc.kind                 = "channel_match"
        pc.redeemer_bonus_idr   = 25_000
        pc.inviter_bonus_idr    = 0
        pc.min_deposit_idr      = 25_000
        pc.description          = attrs[:description]
        pc.active               = true
      end
    end
  end

  def down
    return unless defined?(PromoCode)
    PromoCode.where(code: CODES.map { |c| c[:code] }).destroy_all
  end
end
