class UrlMapping < ApplicationRecord
  # Base62 snowflake ids are 4-11 chars (4 after the first ms past epoch; 11 max for 63-bit ids).
  URL_CODE_FORMAT = /\A[0-9a-zA-Z]{4,11}\z/

  validates :url_code, presence: true, uniqueness: true, format: { with: URL_CODE_FORMAT }
  validates :redirect_url, presence: true

  validate :long_url_must_be_valid

  before_validation :generate_url_code, on: :create

  after_update :remove_cached_code, if: -> { saved_change_to_redirect_url? || saved_change_to_url_code? }
  after_destroy :remove_cached_code

  def self.generate_mock_data(count: 100)
    count.times do |i|
      Rails.logger.info("Generating mock data #{i + 1} of #{count}")
      UrlMapping.create(redirect_url: Faker::Internet.url)
    end
  end

  def self.cache_key(code)
    "url_mapping:#{code}"
  end

  def safe_redirect_url
    return nil if redirect_url.blank?

    uri = URI.parse(redirect_url)
    uri.is_a?(URI::HTTP) && uri.host.present? ? uri.to_s : nil
  rescue URI::InvalidURIError
    nil
  end

  private

  def long_url_must_be_valid
    return if redirect_url.blank?

    if safe_redirect_url.blank?
      errors.add(:redirect_url, 'must be a valid http or https URL')
    end
  end

  def generate_url_code
    return if url_code.present?

    next_id = Snowflake::GeneratorService.instance.next_id
    self.url_code = Utils::Base62Service.encode(next_id)
  end

  def remove_cached_code
    [ url_code, url_code_before_last_save ].compact.uniq.each do |code|
      Rails.cache.delete(self.class.cache_key(code))
    end
  end
end
