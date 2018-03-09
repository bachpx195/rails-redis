class PostsController < ApplicationController
  def index
    @posts = fetch_from_redis
    respond_to do |format|
      format.json { render json: @posts, status: :ok }
    end
  end

  private
    def fetch_from_redis
      posts = $redis.get "posts"

      if posts.nil?
        posts = Post.includes(:user).all.to_json
        $redis.set "posts", posts
      end
      JSON.load posts
    end
end
