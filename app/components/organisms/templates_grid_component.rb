module Organisms
  class TemplatesGridComponent < ApplicationComponent
    # Re-curated 2026-05-21: vibecoder/agency-friendly picks lead the grid.
    # Row 1 = the canonical 6 referenced in the new positioning copy (PaaS
    # spike A: "the apps you'd install on cPanel"). Row 2 = strong tier-2
    # picks that round out the 12-card grid without diluting the headline.
    TEMPLATES = [
      # Row 1 — vibecoder + agency picks (mirrors landing/pricing copy)
      { name: "Ghost",       cat_en: "CMS",          cat_id: "CMS",            icon: "ghost" },
      { name: "n8n",         cat_en: "Automation",   cat_id: "Otomasi",        icon: "n8n" },
      { name: "WordPress",   cat_en: "CMS",          cat_id: "CMS",            icon: "wordpress" },
      { name: "NocoDB",      cat_en: "Airtable alt", cat_id: "Alt. Airtable",  icon: "nocodb" },
      { name: "Umami",       cat_en: "Analytics",    cat_id: "Analitik",       icon: "umami" },
      { name: "Uptime Kuma", cat_en: "Monitoring",   cat_id: "Monitoring",     icon: "uptimekuma" },
      # Row 2 — tier-2 picks, kept for grid balance and breadth signal
      { name: "Gitea",       cat_en: "Git hosting",  cat_id: "Git hosting",    icon: "gitea" },
      { name: "Vaultwarden", cat_en: "Passwords",    cat_id: "Kata Sandi",     icon: "vaultwarden" },
      { name: "Metabase",    cat_en: "Analytics",    cat_id: "Analitik",       icon: "metabase" },
      { name: "Nextcloud",   cat_en: "Storage",      cat_id: "Storage",        icon: "nextcloud" },
      { name: "Pocketbase",  cat_en: "Backend",      cat_id: "Backend",        icon: "pocketbase" },
      { name: "Directus",    cat_en: "Headless CMS", cat_id: "CMS Headless",   icon: "directus" }
    ].freeze

    def template_count
      @template_count ||= TemplateRegistry.new.all.size
    end

    def category(tpl)
      I18n.locale.to_sym == :id ? tpl[:cat_id] : tpl[:cat_en]
    end

    def templates; TEMPLATES; end
  end
end
