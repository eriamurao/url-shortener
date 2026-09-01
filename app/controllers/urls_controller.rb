class UrlsController < ApplicationController
  def shorten
    mapping = UrlMapping.new(redirect_url: params[:long_url])

    if mapping.save
      render json: { short_url: url_url(mapping.url_code) }, status: :created
    else
      render json: { error: mapping.errors.full_messages }, status: :unprocessable_content
    end
  end

  # Important: Since allow_other_host: true is triggers a warning in Brakeman.
  #   Since this is an intentional open redirect, we should ignore the warning.
  #   When updating this code, make sure to update the fingerprint in config/brakeman.ignore.
  #   Run `bin/rails brakeman:sync_ignore` to update the ignore file.
  def show
    code = params[:id]
    if code.blank? || !code.match?(UrlMapping::URL_CODE_FORMAT)
      head :not_found
      return
    end

    code_key = UrlMapping.cache_key(code)
    redirect_url =
      Rails.cache.fetch(code_key, expires_in: 1.hour, skip_nil: true) do
        UrlMapping.find_by(url_code: code)&.safe_redirect_url
      end

    if redirect_url
      # 302 (temporary) so browsers and caches do not permanently bind the short
      # code to this destination. 301 would be wrong if the mapping is later
      # updated or deleted.
      redirect_to redirect_url, status: :found, allow_other_host: true
    else
      head :not_found
    end
  end
end
