require 'rails_helper'

RSpec.describe UrlMapping, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      expect(build(:url_mapping)).to be_valid
    end

    it 'requires redirect_url' do
      mapping = build(:url_mapping, redirect_url: nil)

      expect(mapping).not_to be_valid
      expect(mapping.errors[:redirect_url]).to include("can't be blank")
    end

    it 'requires url_code when not creating' do
      mapping = create(:url_mapping)
      mapping.url_code = nil

      expect(mapping).not_to be_valid
      expect(mapping.errors[:url_code]).to include("can't be blank")
    end

    it 'requires url_code to be unique' do
      first = create(:url_mapping, redirect_url: 'https://example.com/a')
      second = create(:url_mapping, redirect_url: 'https://example.com/b')
      second.url_code = first.url_code

      expect(second).not_to be_valid
      expect(second.errors[:url_code]).to include('has already been taken')
    end

    it 'requires url_code to match the allowed format' do
      mapping = build(:url_mapping, url_code: 'invalid!')

      expect(mapping).not_to be_valid
      expect(mapping.errors[:url_code]).to be_present
    end

    it 'rejects url codes that are too short' do
      mapping = build(:url_mapping, url_code: 'abc')

      expect(mapping).not_to be_valid
      expect(mapping.errors[:url_code]).to be_present
    end

    it 'rejects url codes that are too long' do
      mapping = build(:url_mapping, url_code: 'abcdefghijklmnop')

      expect(mapping).not_to be_valid
      expect(mapping.errors[:url_code]).to be_present
    end

    it 'accepts a valid https URL' do
      mapping = build(:url_mapping, redirect_url: 'https://example.com/path?q=1')

      expect(mapping).to be_valid
    end

    it 'rejects non-http(s) URLs' do
      mapping = build(:url_mapping, redirect_url: 'ftp://example.com/file')

      expect(mapping).not_to be_valid
      expect(mapping.errors[:redirect_url]).to include('must be a valid http or https URL')
    end

    it 'rejects URLs without a host' do
      mapping = build(:url_mapping, redirect_url: 'http://')

      expect(mapping).not_to be_valid
      expect(mapping.errors[:redirect_url]).to include('must be a valid http or https URL')
    end

    it 'rejects malformed URLs' do
      mapping = build(:url_mapping, redirect_url: 'not a url')

      expect(mapping).not_to be_valid
      expect(mapping.errors[:redirect_url]).to include('must be a valid http or https URL')
    end
  end

  describe '#safe_redirect_url' do
    it 'returns the URL for a valid https link' do
      mapping = build(:url_mapping, redirect_url: 'https://example.com/path')

      expect(mapping.safe_redirect_url).to eq('https://example.com/path')
    end

    it 'returns nil for non-http(s) schemes' do
      mapping = build(:url_mapping, redirect_url: 'javascript:alert(1)')

      expect(mapping.safe_redirect_url).to be_nil
    end

    it 'returns nil for malformed URLs' do
      mapping = build(:url_mapping, redirect_url: 'not a url')

      expect(mapping.safe_redirect_url).to be_nil
    end
  end

  describe 'url_code generation' do
    it 'generates url_code from a snowflake id on create' do
      snowflake_id = 4_194_304
      generator = instance_double(Snowflake::GeneratorService, next_id: snowflake_id)
      allow(Snowflake::GeneratorService).to receive(:instance).and_return(generator)

      mapping = create(:url_mapping, url_code: nil, redirect_url: 'https://example.com')

      expect(mapping.url_code).to eq(Utils::Base62Service.encode(snowflake_id))
    end

    it 'preserves an existing link_code on create' do
      expect(Snowflake::GeneratorService).not_to receive(:instance)

      mapping = create(:url_mapping, url_code: 'customcode1', redirect_url: 'https://example.com')

      expect(mapping.url_code).to eq('customcode1')
    end

    it 'generates url_codes that match URL_CODE_FORMAT' do
      mapping = create(:url_mapping, url_code: nil, redirect_url: 'https://example.com')

      expect(mapping.url_code).to match(UrlMapping::URL_CODE_FORMAT)
    end

    it 'generates unique url_codes for each record' do
      mappings = create_list(:url_mapping, 2, url_code: nil, redirect_url: 'https://example.com')

      expect(mappings.map(&:url_code).uniq.size).to eq(2)
    end
  end

  describe 'cache invalidation' do
    around do |example|
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original_cache
    end

    it 'removes the cached redirect on destroy' do
      mapping = create(:url_mapping, redirect_url: 'https://example.com/original')
      cache_key = described_class.cache_key(mapping.url_code)

      Rails.cache.write(cache_key, mapping.safe_redirect_url)
      mapping.destroy!

      expect(Rails.cache.read(cache_key)).to be_nil
    end

    it 'removes the cached redirect when redirect_url is updated' do
      mapping = create(:url_mapping, redirect_url: 'https://example.com/original')
      cache_key = described_class.cache_key(mapping.url_code)

      Rails.cache.write(cache_key, mapping.safe_redirect_url)
      mapping.update!(redirect_url: 'https://example.com/updated')

      expect(Rails.cache.read(cache_key)).to be_nil
    end
  end

  describe '.generate_mock_data' do
    before do
      allow(Rails.logger).to receive(:info)
    end

    it 'creates the requested number of url mappings' do
      expect do
        described_class.generate_mock_data(count: 3)
      end.to change(described_class, :count).by(3)
    end

    it 'generates url codes for each record' do
      described_class.generate_mock_data(count: 2)

      expect(described_class.last(2).map(&:url_code)).to all(be_present)
    end

    it 'logs progress for each record' do
      described_class.generate_mock_data(count: 2)

      expect(Rails.logger).to have_received(:info).with('Generating mock data 1 of 2').ordered
      expect(Rails.logger).to have_received(:info).with('Generating mock data 2 of 2').ordered
    end

    it 'uses deterministic https URLs' do
      described_class.generate_mock_data(count: 2)

      expect(described_class.last(2).map(&:redirect_url)).to contain_exactly(
        'https://example.com/mock/1',
        'https://example.com/mock/2'
      )
    end
  end
end
