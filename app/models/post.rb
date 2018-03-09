class Post < ApplicationRecord
  belongs_to :user

  after_save :clear_cache

  private
    def clear_cache
      $redis.del "posts"
    end
end
