# frozen_string_literal: true

# config/initializers/rack_attack.rb (for rails apps)

# my_ips = ['127.0.0.1']
# Rack::Attack.blocklist('block admin access') do |req|
#   ips = Settings.my_ips || my_ips
#   req.path.include?('/admin') && ips.exclude?(req.env['REMOTE_ADDR'])
# end

# Rack::Attack.blocklist('block sidekiq access') do |req|
#   ips = Settings.my_ips || my_ips
#   req.path == '/sidekiq' && ips.exclude?(req.env['REMOTE_ADDR'])
# end

# Rack::Attack.throttle('requests by ip', limit: 20, period: 60, &:ip)

# Rack::Attack.throttle('requests by ip', limit: 30, period: 60) do |req|
#   req.ip
# end
