module EeHelper
  def ee_feature(partial, **locals)
    render(partial, **locals) rescue nil
  end
end
