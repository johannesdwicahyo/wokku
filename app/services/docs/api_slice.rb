module Docs
  # Slices Wokku.config.openapi_path into one OpenAPI document per API
  # reference group (config/docs_api_groups.yml), for the /docs/api pages.
  # Each slice keeps its group's operations, minus hidden ones, and only the
  # components they reach through $ref (plus every security scheme).
  module ApiSlice
    GROUPS = YAML.load_file(Wokku::Engine.root.join("config/docs_api_groups.yml")).map do |g|
      { key: g["key"], title: g["title"].symbolize_keys, tags: g["tags"], intro: g["intro"].to_s }.freeze
    end.freeze
    KEYS = GROUPS.map { |g| g[:key] }.freeze
    DEFAULT_GROUP = "apps".freeze
    TAG_GROUP = GROUPS.flat_map { |g| g[:tags].map { |t| [ t, g[:key] ] } }.to_h.freeze
    # The cloud-only `cloud` tag carries no resource name: route it by path.
    CLOUD_PATHS = { %r{/e?mail(?:/|\z)} => "email-storage", %r{/(?:billing|invoices|plans)(?:/|\z)} => "team-billing" }.freeze
    HIDDEN_ID = /\.dokku\z/ # retired Dokku endpoints (apps.dokku, servers.dokku)
    METHODS = %w[get put post delete options head patch trace].freeze

    EMPTY = { slices: {}.freeze, unmapped: [].freeze }.freeze
    @lock = Mutex.new
    @cache = nil

    class << self
      # [{ key:, title: (current locale), intro_md: }] for groups with operations.
      def groups
        built[:slices].filter_map do |key, slice|
          g = GROUPS.find { |gr| gr[:key] == key }
          { key: key, title: g[:title][I18n.locale.to_sym] || g[:title][:en], intro_md: slice["info"]["description"].to_s }
        end
      end

      # The group's OpenAPI document, or nil for an unknown or empty group.
      def for(key) = built[:slices][key.to_s]

      # Operation tags no group claims (they land in "apps"); a spec keeps it empty.
      def unmapped_tags = built[:unmapped]

      private

      # ponytail: one global lock; a rebuild only happens when the file changes.
      def built
        path = Wokku.config.openapi_path.to_s
        mtime = File.mtime(path)
      rescue Errno::ENOENT
        EMPTY # no spec file: no groups, every page 404s
      else
        key = [ path, mtime, Wokku.config.docs_api_group_intros ]
        @lock.synchronize do
          @cache = build(YAML.safe_load_file(path, aliases: true)).merge(key: key).freeze unless @cache && @cache[:key] == key
          @cache
        end
      end

      def build(doc)
        tag_desc = Array(doc["tags"]).to_h { |t| [ t["name"], t["description"] ] }
        by_group = Hash.new { |h, k| h[k] = {} }
        unmapped = []

        doc.fetch("paths", {}).each do |path, item|
          item.each do |verb, op|
            next unless METHODS.include?(verb) && op.is_a?(Hash)
            next if op["x-internal"] || HIDDEN_ID.match?(op["operationId"].to_s)
            tags = Array(op["tags"])
            unmapped.concat(tags.reject { |t| t == "cloud" || TAG_GROUP.key?(t) })
            group = group_for(path, tags)
            kept = tags.reject { |t| t == "cloud" }.select { |t| TAG_GROUP.fetch(t, DEFAULT_GROUP) == group }
            entry = by_group[group][path] ||= item.except(*METHODS)
            entry[verb] = op.merge("tags" => kept.presence || tags)
          end
        end

        slices = KEYS.filter_map do |key|
          paths = by_group[key]
          next if paths.empty?
          [ key, slice(doc, GROUPS.find { |g| g[:key] == key }, paths, tag_desc) ]
        end.to_h
        { slices: slices.freeze, unmapped: unmapped.uniq.sort.freeze }
      end

      def group_for(path, tags)
        tag = tags.find { |t| t != "cloud" }
        return TAG_GROUP.fetch(tag, DEFAULT_GROUP) if tag
        CLOUD_PATHS.find { |re, _| path.match?(re) }&.last || DEFAULT_GROUP
      end

      def slice(doc, group, paths, tag_desc)
        used = paths.values.flat_map { |item| item.slice(*METHODS).values.flat_map { |op| op["tags"] } }.uniq
        tag_names = (group[:tags] & used) + (used - group[:tags])
        tags = tag_names.map { |t| tag_desc[t] ? { "name" => t, "description" => tag_desc[t] } : { "name" => t } }
        intros = Wokku.config.docs_api_group_intros || {}
        intro = intros[group[:key]] || intros[group[:key].to_sym] ||
                tags.filter_map { |t| t["description"] }.join("\n\n").presence || group[:intro]

        {
          "openapi" => doc["openapi"],
          "info" => (doc["info"] || {}).merge("title" => group[:title][:en], "description" => intro),
          "servers" => doc["servers"],
          "security" => doc["security"],
          "tags" => tags,
          "paths" => paths,
          "components" => components(doc.fetch("components", {}), paths)
        }.compact
      end

      # Transitive closure of #/components/<section>/<name> refs, cycle-safe.
      def components(all, paths)
        seen = {}
        queue = refs(paths)
        while (ref = queue.shift)
          next if seen[ref]
          seen[ref] = true
          node = all.dig(*ref)
          queue.concat(refs(node)) if node
        end
        out = {}
        seen.each_key { |sec, name| (v = all.dig(sec, name)) && (out[sec] ||= {})[name] = v }
        out["securitySchemes"] = all["securitySchemes"] if all["securitySchemes"]
        out
      end

      def refs(node)
        case node
        when Hash
          own = node["$ref"].is_a?(String) && node["$ref"].start_with?("#/components/") ? [ node["$ref"].delete_prefix("#/components/").split("/", 2) ] : []
          own + node.values.flat_map { |v| refs(v) }
        when Array then node.flat_map { |v| refs(v) }
        else []
        end
      end
    end
  end
end
