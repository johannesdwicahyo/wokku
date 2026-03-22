module ApplicationHelper
  def template_icon(icon_name)
    icons = {
      "rails" => "🛤️", "ruby" => "💎", "node" => "🟢", "python" => "🐍",
      "go" => "🔷", "java" => "☕", "php" => "🐘", "elixir" => "💧",
      "rust" => "🦀", "analytics" => "📊", "chat" => "💬", "cms" => "📝",
      "automation" => "🔄", "ai" => "🤖", "ecommerce" => "🛒", "monitor" => "📈",
      "security" => "🔒", "storage" => "📦", "mail" => "📧", "rss" => "📰",
      "media" => "🎬", "wiki" => "📖", "link" => "🔗", "db" => "🗄️",
      "calendar" => "📅", "form" => "📋", "git" => "🔀", "api" => "⚡",
      "docker" => "🐳", "search" => "🔍", "url" => "🔗", "whatsapp" => "📱",
      "platform" => "🏗️"
    }
    icons[icon_name.to_s] || "📦"
  end

  def log_line_class(line)
    if line.match?(/error|fatal|panic/i)
      "text-red-400"
    elsif line.match?(/warn/i)
      "text-yellow-500"
    elsif line.match?(/nginx/i)
      "text-blue-400"
    else
      "text-gray-400"
    end
  end
end
