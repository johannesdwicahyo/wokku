class BlogController < ApplicationController
  layout "landing"

  def index
    @posts = BlogPost.all
  end

  def show
    @post = BlogPost.find(params[:slug])
    redirect_to blog_path, status: :moved_permanently unless @post
  end
end
