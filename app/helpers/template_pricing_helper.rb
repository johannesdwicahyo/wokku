module TemplatePricingHelper
  # Bundle v2 REVISED 2026-05-31: templates consume a box + optional
  # shared engines from the user's plan quota — no per-resource pricing.
  # See memory/project_bundle_v2_locked_spec.md.
  #
  # Returns the box-size category the template's :min_tier maps to.
  # Mirrors Dashboard::TemplatesController#box_size_for_template so the
  # marketplace card preview agrees with the actual deploy.
  def template_box_size(template)
    tier_name = template[:min_tier].presence ||
                ((template[:addons] || []).any? ? "basic" : "free")
    { "free" => "sleeping", "basic" => "small", "standard" => "medium",
      "performance" => "large", "performance-2x" => "xlarge" }[tier_name] || "small"
  end

  # Short label for template cards / index rows — surfaces what the
  # template consumes from the user's plan instead of legacy per-addon
  # pricing.
  def template_total_label(template)
    box = template_box_size(template)
    addon_count = (template[:addons] || []).size
    label = if addon_count.zero?
      "1 #{box.capitalize} box"
    else
      # Without shared engines (self-host) the template gets its own database.
      kind = Addons::SharedProvisioner.feature_enabled? ? "shared add-on" : "database"
      "1 #{box.capitalize} box + #{addon_count} #{kind}#{'s' if addon_count != 1}"
    end
    # "plan-included" is cloud pricing copy; a self-host has no plan quota.
    wokku_cloud? ? "#{label} · plan-included" : label
  end
end
