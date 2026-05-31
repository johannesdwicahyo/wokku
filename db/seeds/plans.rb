# OSS seed for plans — single 'free' row so User#assign_default_plan
# (called from a before_validation on create) has a record to point at.
# OSS doesn't bill anyone; the row exists only to satisfy the FK.
#
# Use update_columns-style upsert via raw SQL to dodge required column
# differences between the wokku-cloud Plan schema (Bundle v2 columns,
# pricing, seats) and the OSS plans table (just whatever the first
# create_plans migration declared).

Plan.find_or_create_by!(name: "free") do |p|
  if p.respond_to?(:key=)
    p.key = "free"
  end
  if p.respond_to?(:max_apps=)
    p.max_apps = 0  # OSS doesn't enforce; column requires non-null
  end
end
