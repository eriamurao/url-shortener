require 'rails_helper'

RSpec.describe 'Rack::Attack', type: :request do
  around do |example|
    original_rails_cache = Rails.cache
    original_attack_store = Rack::Attack.cache.store
    store = ActiveSupport::Cache::MemoryStore.new
    Rails.cache = store
    Rack::Attack.cache.store = store
    example.run
  ensure
    Rails.cache = original_rails_cache
    Rack::Attack.cache.store = original_attack_store
  end

  before do
    Rack::Attack.enabled = true
    Rack::Attack.reset!
  end

  describe 'POST /urls/shorten' do
    it 'throttles after 50 requests from the same IP' do
      50.times do
        post shorten_urls_path, params: { long_url: 'https://example.com/path' }
        expect(response).to have_http_status(:created)
      end

      post shorten_urls_path, params: { long_url: 'https://example.com/path' }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error']).to eq('Rate limit exceeded, try again later')
    end

    it 'counts .json create requests toward the same limit' do
      49.times do
        post shorten_urls_path, params: { long_url: 'https://example.com/path' }
        expect(response).to have_http_status(:created)
      end

      post '/urls/shorten.json', params: { long_url: 'https://example.com/path' }
      expect(response).to have_http_status(:created)

      post '/urls/shorten.json', params: { long_url: 'https://example.com/path' }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error']).to eq('Rate limit exceeded, try again later')
    end
  end

  describe 'GET /urls/:id' do
    it 'does not throttle a single redirect' do
      mapping = create(:url_mapping, redirect_url: 'https://destination.example/target')

      get url_path(mapping.url_code)

      expect(response).to have_http_status(:found)
    end

    it 'throttles .json redirects with the same limiter as bare paths' do
      mapping = create(:url_mapping, redirect_url: 'https://destination.example/target')
      path = url_path(mapping.url_code)
      json_path = "#{path}.json"

      # Exhaust the redirect bucket without asserting every response status —
      # we only care that format and bare paths share one counter.
      1000.times { get path }

      get json_path

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error']).to eq('Rate limit exceeded, try again later')
    end
  end

  describe 'GET /up' do
    it 'is not throttled as a redirect' do
      get '/up'

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'path matchers' do
    it 'matches shorten and short-code redirects, not the health check' do
      expect('/urls/shorten').to eq(Rack::Attack::SHORTEN_PATH)
      expect('/urls/abcd').to match(Rack::Attack::REDIRECT_PATH)
      expect('/urls/abcdefghijk').to match(Rack::Attack::REDIRECT_PATH)
      expect('/up').not_to match(Rack::Attack::REDIRECT_PATH)
      expect('/urls/abc').not_to match(Rack::Attack::REDIRECT_PATH)
      expect('/links/generate_short_url').not_to eq(Rack::Attack::SHORTEN_PATH)
    end

    it 'strips a trailing format before matching' do
      shorten = Struct.new(:path).new('/urls/shorten.json')
      redirect = Struct.new(:path).new('/urls/abcd.json')
      bare = Struct.new(:path).new('/urls/shorten')

      expect(Rack::Attack.throttle_path(shorten)).to eq('/urls/shorten')
      expect(Rack::Attack.throttle_path(redirect)).to eq('/urls/abcd')
      expect(Rack::Attack.throttle_path(bare)).to eq('/urls/shorten')
      expect(Rack::Attack.throttle_path(redirect)).to match(Rack::Attack::REDIRECT_PATH)
    end
  end
end
