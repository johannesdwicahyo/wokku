class ApplicationComponent < ViewComponent::Base
  include TimeAgoHelper

  def cx(*classes)
    classes.flatten.compact.join(" ")
  end
end
