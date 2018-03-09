Cài đặt
Lan man với lí thuyết thế là đủ, cùng download, giải nén và compile Redis với:

$ wget http://download.redis.io/releases/redis-3.2.5.tar.gz
$ tar xzf redis-3.2.5.tar.gz
$ cd redis-3.2.5
$ make
$ cp src/redis-server src/redis-cli /usr/bin
Để khởi động Redis ta sử dụng câu lệnh:

$ redis-server
2. Tối ưu Rails app với Redis
Tạo dữ liệu
Ở phần demo này mình có 2 bảng là User và Post

# app/models/post.rb
class Post < ActiveRecord::Base
  belongs_to :user
end

# app/models/user.rb
class User < ActiveRecord::Base
  has_many :posts
end
Việc truy vấn với một lượng lớn dữ liệu sẽ mất khá nhiều thời gian query, sẽ mất nhiều thời gian hơn nữa khi ta response cho client. Tiếp theo ta tạo dữ liệu từ file seed.rb, ta cần cài đặt gem faker để tạo dữ liệu ảo.

gem "faker"
Ta tạo ra 10 user và mỗi user có 10000 post

# db/seed.rb
10.times do |n|
  user = User.create! name: Faker::Name.name, address: Faker::Address.city
  10000.times do |m|
    Post.create! title: Faker::Lorem.sentence, content: Faker::Lorem.paragraph,
      user: user
  end
end
Ở controller index ta load hết tất cả 100000 post và trả về ở dạng json.

# app/controllers/posts_controller.rb
class PostsController < ApplicationController
  def index
    @posts = Post.includes(:user).all
    respond_to do |format|
      format.json { render json: @posts, status: :ok }
    end
  end
end
Thử chạy chương trình xem có ổn không nào.

Selection_007.png

Selection_008.png

Ta có thể thấy là với 100000 bản ghi server mất 86ms để truy vấn dữ liệu và mất toàn bộ gần 21s để trả về được cho client dữ liệu dưới dạng json.

Khởi tạo Redis Rails
Tiếp theo ta cần cài đặt một số gem để có thể sử dụng Redis

gem "redis"
gem "redis-namespace"
gem "redis-rails"
gem "redis-rack-cache"
Ta cần khai báo với Rails rằng là sử dụng Redis như một cache store, ở đây ta cần khai báo địa chỉ host, cổng và số thứ tự database (Redis mặc định có 16 database được đánh số thứ tự từ 0-15)

# config/application.rb
config.cache_store = :redis_store, {
  host: "localhost",
  port: 6379,
  db: 0,
}, {expires_in: 7.days}
Ta cần phải tạo ra một Redis instance để có thể gọi được ở trong ứng dụng Rails, bằng việc sử dụng redis-namespace điều này khá dễ dàng. Sau này khi cần thực hiện query Redis sẽ thông qua biến này.

# config/initializers/redis.rb
$redis = Redis::Namespace.new "demo-redis", :redis => Redis.new
Giờ thì ta đã có thể sử dụng được Redis để lưu trữ dữ liệu rồi

# app/controllers/posts_controller.rb
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
Chạy thử và xem kết quả nào

Selection_005.png
Selection_006.png

Server không hề mất thời gian truy vấn dữ liệu thay vào đó là lấy dữ liệu từ Redis (rất nhanh) và cũng chỉ mất tổng cộng hơn 7s để trả lại dữ liệu cho client dưới dạng json, thời gian đã được giảm xuống còn 1/3 so với lúc trước.

Một số vấn đề gặp phải khi sử dụng redis
Khi Redis bị lỗi thì server của chúng ta cũng bị lỗi
Để khắc phục điều này ta cần tạo 1 exception cho việc gọi Redis (good practice), ta có thể viết lại hàm fetch_from_redis

# app/controllers/posts_controller.rb
def fetch_from_redis
  begin
    posts = $redis.get "posts"

    if posts.nil?
      posts = Post.includes(:user).all.to_json
      $redis.set "posts", posts
    end
    posts = JSON.load posts
  rescue => error
    puts error.inspect
    posts = Post.includes(:user).all
  end
  posts
end
Dữ liệu trả về không còn là Active Record
Một điều cần lưu ý là khi ta load dữ liệu từ Redis thì ta cần phải chuyển dữ liệu cần lưu thành string thì mới có thể lưu vào được Redis, và khi lấy ra ta cần phải convert từ string thành hash. Vì vậy khi sử dụng dữ liệu ở view thì cần chú ý vì dữ liệu bây giờ không phải là Active Record nữa.

Việc convert sang json và dump lại thành hash có thể mất nhiều thời gian, ta có thể sử dụng yajl-ruby hay Oj

Dữ liệu khi bị sửa đổi hay xóa thì dữ liệu trong redis sẽ không còn đúng nữa
Có một vấn đề là khi ta cập nhật hay xóa dữ liệu thì khi ta lấy dữ liệu từ Redis ra sẽ không còn đúng nữa, vì vậy ta cần phải có một bước cập nhật dữ liệu Redis mỗi khi có thay đổi về dữ liệu.

Điều này giải quyết khá đơn giản là ta lại xóa dữ liệu trong Redis đi.

class Post < ActiveRecord::Base
  after_save :clear_cache

  private
  def clear_cache
    $redis.del "posts"
  end
end

Đặt key có tính phân biệt
Giả định ở index ta chỉ lấy những posts của user hiện tại, khi đó ta sẽ gặp trường hợp là 2 user khác nhau sẽ lấy cùng một dữ liệu ở Redis vì vậy kết quả sẽ không đúng.

Để giải quyết vấn đề này cũng khá đơn giản, là ta chỉ cần đặt key khi lưu vào Redis có thể phân biệt được 2 user đó, ví dụ ta có thể đặt key là posts&user_id=1 thay vì là posts
