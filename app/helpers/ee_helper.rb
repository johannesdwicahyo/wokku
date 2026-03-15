module EeHelper
  def ee_feature(partial, **locals)
    return unless Wokku.ee?
    render(partial, **locals) rescue nil
  end
end
