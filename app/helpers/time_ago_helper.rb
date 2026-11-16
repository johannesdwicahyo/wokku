# "5 minutes ago" / "5 menit yang lalu" — the word order differs, so the
# whole phrase is translated (call sites used to append a literal " ago").
module TimeAgoHelper
  def time_ago(time)
    I18n.t("time_ago", time: time_ago_in_words(time), default: "%{time} ago")
  end
end
