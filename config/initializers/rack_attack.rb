class Rack::Attack
  Rack::Attack.cache.store = Rails.cache

  # Throttle URL creation: 50 requests per IP per minute
  throttle('url creation by ip', limit: 50, period: 60) do |req|
    req.ip if req.post? && req.path == '/links/generate_short_url'
  end

  # Redirects stay loose — this is your core product traffic, not abuse-prone
  throttle('redirects by ip', limit: 1000, period: 60) do |req|
    req.ip if req.get? && req.path.match?(%r{^/[a-zA-Z0-9]+$})
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
