class Rack::Attack
  SHORTEN_PATH = '/urls/shorten'
  REDIRECT_PATH = %r{\A/urls/[0-9a-zA-Z]{4,11}\z}

  # Rails still routes /urls/shorten.json and /urls/:code.json; strip the
  # format so those paths share the same throttle buckets as the bare paths.
  def self.throttle_path(req)
    req.path.sub(/\.\w+\z/, '')
  end

  Rack::Attack.cache.store = Rails.cache

  safelist('health check') do |req|
    req.get? && req.path == '/up'
  end

  # Throttle URL creation: 50 requests per IP per minute
  throttle('url creation by ip', limit: 50, period: 60) do |req|
    req.ip if req.post? && throttle_path(req) == SHORTEN_PATH
  end

  # Redirects stay loose — this is core product traffic, not abuse-prone
  throttle('redirects by ip', limit: 1000, period: 60) do |req|
    req.ip if req.get? && throttle_path(req).match?(REDIRECT_PATH)
  end

  self.throttled_responder = lambda do |request|
    [
      429,
      { 'Content-Type' => 'application/json' },
      [
        { error: 'Rate limit exceeded, try again later' }.to_json
      ]
    ]
  end
end
