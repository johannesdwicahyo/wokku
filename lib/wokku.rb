module Wokku
  def self.ee?
    @ee ||= File.directory?(Rails.root.join("ee"))
  end
end
