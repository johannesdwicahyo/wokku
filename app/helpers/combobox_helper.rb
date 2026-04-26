module ComboboxHelper
  # Renders a themed search-select that submits as a hidden input. Keyboard
  # navigable, click-to-open, click-outside to close. Falls back gracefully
  # if Stimulus isn't loaded — the hidden input still posts the current value.
  #
  #   options: Array<[label, value]> or Array<{label:, value:, description:}>
  #   name:    form input name (e.g. "database_service[app_id]")
  #   value:   currently-selected value
  #   placeholder: text shown when no value is selected
  #   id:      DOM id for the trigger (label `for=` if you need it)
  #   data:    extra Stimulus data attributes to merge onto the wrapper
  def combobox_tag(name, options, value: nil, placeholder: "Select…", id: nil, data: {}, required: false)
    normalized = options.map do |opt|
      if opt.is_a?(Array)
        { value: opt[1].to_s, label: opt[0].to_s }
      elsif opt.is_a?(Hash)
        { value: opt[:value].to_s, label: opt[:label].to_s, description: opt[:description].to_s.presence }.compact
      end
    end

    wrapper_data = {
      controller: "combobox",
      "combobox-options-value": normalized.to_json,
      "combobox-placeholder-value": placeholder
    }.merge(data)

    selected = normalized.find { |o| o[:value] == value.to_s }

    content_tag :div, class: "relative", data: wrapper_data do
      hidden = hidden_field_tag(name, value, data: { "combobox-target": "input" }, required: required)
      trigger = content_tag :button, type: "button",
        class: "w-full flex items-center justify-between rounded-md bg-surface-container-low border border-outline-variant/15 px-4 py-2.5 text-sm hover:border-outline-variant/30 focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition cursor-pointer",
        data: { "combobox-target": "trigger", action: "click->combobox#toggle keydown->combobox#triggerKeydown" },
        id: id,
        "aria-haspopup": "listbox",
        "aria-expanded": "false" do
        safe_join([
          content_tag(:span, (selected ? selected[:label] : placeholder),
            class: "truncate #{selected ? 'text-on-surface' : 'text-outline-variant'}",
            data: { "combobox-target": "label" }),
          content_tag(:span, "expand_more", class: "material-symbols-outlined text-[18px] text-outline ml-2 flex-shrink-0")
        ])
      end

      panel = content_tag :div,
        class: "hidden absolute z-40 mt-1 w-full bg-surface-container rounded-md shadow-lg ring-1 ring-outline-variant/20 overflow-hidden",
        data: { "combobox-target": "panel" } do
        safe_join([
          content_tag(:div, class: "p-2 border-b border-outline-variant/15") do
            content_tag(:input, "", type: "text",
              class: "w-full bg-surface-container-low border border-outline-variant/15 rounded px-3 py-1.5 text-sm text-on-surface placeholder-outline-variant focus:outline-none focus:ring-1 focus:ring-primary/30",
              placeholder: "Search…",
              data: { "combobox-target": "search", action: "input->combobox#filter keydown->combobox#searchKeydown" })
          end,
          content_tag(:ul, "", class: "max-h-60 overflow-y-auto p-1 space-y-0.5", role: "listbox", data: { "combobox-target": "list" })
        ])
      end

      safe_join([ hidden, trigger, panel ])
    end
  end
end
