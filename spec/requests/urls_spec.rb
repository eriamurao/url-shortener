require 'rails_helper'

RSpec.describe 'Urls', type: :request do
  describe 'POST /urls/shorten' do
    let(:long_url) { 'https://example.com/some/path' }

    it 'creates a mapping and returns the short URL' do
      expect do
        post shorten_urls_path, params: { long_url: long_url }
      end.to change(UrlMapping, :count).by(1)

      expect(response).to have_http_status(:created)

      mapping = UrlMapping.last
      body = response.parsed_body

      expect(body['short_url']).to include("/urls/#{mapping.url_code}")
      expect(mapping.redirect_url).to eq(long_url)
      expect(mapping.url_code).to match(UrlMapping::URL_CODE_FORMAT)
    end

    it 'returns validation errors for an invalid long URL' do
      expect do
        post shorten_urls_path, params: { long_url: 'not a url' }
      end.not_to change(UrlMapping, :count)

      expect(response).to have_http_status(:unprocessable_content)

      body = response.parsed_body
      expect(body['error']).to be_an(Array)
      expect(body['error']).not_to be_empty
    end

    it 'returns validation errors when long_url is missing' do
      post shorten_urls_path, params: {}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to be_present
    end
  end

  describe 'GET /urls/:id' do
    around do |example|
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original_cache
    end

    it 'redirects to the stored URL with a temporary redirect' do
      mapping = create(:url_mapping, redirect_url: 'https://destination.example/target')

      get url_path(mapping.url_code)

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to('https://destination.example/target')
    end

    it 'returns not found when the link code does not exist' do
      get url_path('abcdefghij')

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_blank
    end

    it 'returns not found for link codes with invalid format' do
      expect(UrlMapping).not_to receive(:find_by)

      get url_path('invalid!')

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_blank
    end

    it 'returns not found for link codes that are too short' do
      expect(UrlMapping).not_to receive(:find_by)

      get url_path('abc')

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_blank
    end

    it 'returns not found for link codes that are too long' do
      expect(UrlMapping).not_to receive(:find_by)

      get url_path('abcdefghijklmnop')

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_blank
    end

    it 'returns not found when the stored redirect URL is not http(s)' do
      mapping = create(:url_mapping, redirect_url: 'https://example.com')
      mapping.update_column(:redirect_url, 'javascript:alert(1)')

      get url_path(mapping.url_code)

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_blank
    end

    it 'serves redirects from cache on subsequent requests' do
      mapping = create(:url_mapping, redirect_url: 'https://destination.example/cached')

      get url_path(mapping.url_code)
      expect(response).to redirect_to('https://destination.example/cached')

      mapping.update_column(:redirect_url, 'https://destination.example/uncached')

      get url_path(mapping.url_code)

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to('https://destination.example/cached')
    end

    it 'returns not found after destroy when the redirect was cached' do
      mapping = create(:url_mapping, redirect_url: 'https://destination.example/cached')

      get url_path(mapping.url_code)
      expect(response).to redirect_to('https://destination.example/cached')

      mapping.destroy!

      get url_path(mapping.url_code)

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_blank
    end

    it 'does not cache missing link codes' do
      code = 'abcdefghij'

      get url_path(code)
      expect(response).to have_http_status(:not_found)

      create(:url_mapping, url_code: code, redirect_url: 'https://example.com/new')

      get url_path(code)

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to('https://example.com/new')
    end
  end
end
