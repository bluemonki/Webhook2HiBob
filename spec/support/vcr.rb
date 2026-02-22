require 'vcr'
require 'webmock/rspec'

VCR.configure do |c|
  c.cassette_library_dir = Rails.root.join('spec', 'vcr_cassettes')
  c.hook_into :webmock
  c.configure_rspec_metadata!

  # Filter out any real credentials so they don't get committed to git
  c.filter_sensitive_data('<PINPOINT_API_KEY>') { Rails.application.credentials.fetch(:pinpoint_api_key) rescue nil }
  c.filter_sensitive_data('<HIBOB_USERNAME>') { Rails.application.credentials.fetch(:hibob_username) rescue nil }
  c.filter_sensitive_data('<HIBOB_PASSWORD>') { Rails.application.credentials.fetch(:hibob_password) rescue nil }

  # scrub Amazon access key ids that appear in S3 presigned URLs; the pattern is
  # AKIA followed by 16 uppercase alphanumerics.  We apply this both to request
  # URIs and bodies so the value is never committed.
  c.filter_sensitive_data('<AWS_ACCESS_KEY_ID>') do |interaction|
    # try request URI first
    if interaction.request.uri =~ /(AKIA[0-9A-Z]{16})/
      Regexp.last_match(1)
    elsif interaction.response.body.is_a?(String) && interaction.response.body =~ /(AKIA[0-9A-Z]{16})/
      Regexp.last_match(1)
    end
  end

  # Allow localhost requests through (rails server in tests)
  c.ignore_localhost = true
end
