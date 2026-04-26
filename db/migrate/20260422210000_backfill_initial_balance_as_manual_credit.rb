class BackfillInitialBalanceAsManualCredit < ActiveRecord::Migration[8.1]
  # Users with a balance but no completed DepositTransaction history
  # (admin seeded directly, grandfathered accounts, goodwill credits
  # from early beta) show an empty ledger because there's nothing to
  # surface as the first credit. This seeds one "manual" transaction
  # per such user so the ledger has a proper opening row.
  def up
    return unless defined?(User) && defined?(DepositTransaction)

    User.find_each do |user|
      settled_idr = user.deposit_transactions
                        .where(status: :completed, currency: "idr")
                        .sum(:amount)
      settled_usd = user.deposit_transactions
                        .where(status: :completed, currency: "usd")
                        .sum(:amount)

      idr_gap = user.balance_idr.to_i - settled_idr.to_i
      usd_gap = user.balance_usd_cents.to_i - settled_usd.to_i

      if idr_gap > 0
        DepositTransaction.create!(
          user: user,
          amount: idr_gap,
          currency: "idr",
          payment_gateway: "manual",
          status: :completed,
          created_at: user.created_at,
          updated_at: user.created_at
        )
      end

      if usd_gap > 0
        DepositTransaction.create!(
          user: user,
          amount: usd_gap,
          currency: "usd",
          payment_gateway: "manual",
          status: :completed,
          created_at: user.created_at,
          updated_at: user.created_at
        )
      end
    end
  end

  def down
    DepositTransaction.where(payment_gateway: "manual").delete_all if defined?(DepositTransaction)
  end
end
