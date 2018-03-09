begin
  $redis = Redis.new
  $redis.ping
rescue Exception => e
  e.inspect
  e.message
  $redis = nil
end
