module TemplatePricingHelper
  # Compute the monthly cost breakdown for a 1-Click Deploy template,
  # using the cheapest paid dyno (basic) plus the explicitly required
  # add-on tiers from the template definition. Returns USD numbers;
  # views format with format_price for IDR/USD output.
  def template_cost(template)
    dyno_tier = DynoTier.find_by(name: default_dyno_tier_name)
    dyno_monthly = dyno_tier ? dyno_tier.monthly_price_dollars : 0.0

    addons = (template[:addons] || []).filter_map do |addon|
      type = addon["type"] || addon[:type]
      tier_name = addon["tier"] || addon[:tier] || "basic"
      service_tier = ServiceTier.find_by(service_type: type, name: tier_name)
      next nil unless service_tier
      {
        type: type,
        tier: tier_name,
        monthly_usd: service_tier.monthly_price_dollars,
        spec: service_tier.spec || {}
      }
    end

    {
      dyno: dyno_tier && {
        name: dyno_tier.name,
        memory_mb: dyno_tier.memory_mb,
        cpu_shares: dyno_tier.cpu_shares,
        storage_mb: dyno_tier.storage_mb,
        monthly_usd: dyno_monthly,
        sleeps: dyno_tier.sleeps
      },
      addons: addons,
      total_monthly_usd: dyno_monthly + addons.sum { |a| a[:monthly_usd] }
    }
  end

  def template_total_label(template)
    cost = template_cost(template)
    format_price(cost[:total_monthly_usd]) + price_period
  end

  private

  def default_dyno_tier_name
    "basic"
  end
end
