class ApplicationComponent < ViewComponent::Base
  def cx(*classes)
    classes.flatten.compact.join(" ")
  end
end
