module ApplicationHelper
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
