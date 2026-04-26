class BackfillDynoTierStorage < ActiveRecord::Migration[8.1]
  def up
    storage_by_name = {
      "free"           =>  2_048,
      "basic"          =>  5_120,
      "standard"       => 15_360,
      "performance"    => 30_720,
      "performance-2x" => 61_440
    }

    storage_by_name.each do |name, mb|
      tier = DynoTier.find_by(name: name)
      next unless tier
      tier.update_column(:storage_mb, mb) if tier.storage_mb.to_i != mb
    end
  end

  def down
    # Non-reversible: we don't know prior values. No-op.
  end
end
