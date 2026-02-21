# app/services/pin_point/client.rb
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module PinPoint
  class Client < Api::BaseClient
    DEFAULT_BASE_URL = "https://developers-test.pinpointhq.com".freeze

    class Error < StandardError; end

    class HttpError < Error
      attr_reader :status, :body, :method, :path

      def initialize(status:, body:,  method:, path:)
        @status = status
        @body = body
        @method = method
        @path = path
        super("Pinpoint API request failed (HTTP #{status}) #{method} #{path} ")
      end
    end

    # Pinpoint docs: API key is sent via X-API-KEY header.
    # - api_key: required
    # - base_url: override for prod vs test if needed
    # - logger: defaults to Rails.logger (if Rails is present), otherwise nil
    def initialize(api_key:, base_url: DEFAULT_BASE_URL, open_timeout: 5, read_timeout: 15, logger: default_logger)
      raise ArgumentError, "api_key is required" if api_key.nil? || api_key.strip.empty?

      @api_key = api_key
      @base_url = base_url
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @logger = logger
    end

    # --- Applications ---

    # GET /api/v1/applications/:id
    def get_application_with_attachments(application_id)
      request_json(:get, "/api/v1/applications/#{application_id}?extra_fields[applications]=attachments")
    end

    # Typed wrapper
    def get_application_data_with_attachments(application_id)
      PinPoint::ApplicationData.new(get_application_with_attachments(application_id))
    end

    # Convenience: fetch application (with attachments) and download the attachment with the given context.
    #
    # Returns:
    # - if to_path provided: written path (String)
    # - else: binary String
    def download_application_attachment(application, context:, to_path: nil)
      attachment = application.attachment_by_context(context)

      raise Error, "No attachment found with context=#{context.inspect} for application_id=#{application_id}" unless attachment

      url = attachment["url"]
      raise Error, "Attachment context=#{context.inspect} is missing url" if url.nil? || url.to_s.strip.empty?

      final_path =
        if to_path
          # If caller passes a directory, write using the attachment filename.
          expanded = to_path.to_s
          if File.extname(expanded).empty? && File.directory?(expanded)
            File.join(expanded, attachment.fetch("filename"))
          else
            expanded
          end
        end

      download_file(url, to_path: final_path)
    end

    # GET /api/v1/applications
    # NOTE: If Pinpoint uses pagination params, pass them via `params: { page: 1, per_page: 50 }`
    def list_applications(params: nil)
      request_json(:get, "/api/v1/applications", params: params)
    end

    # Downloads a file from a full URL (e.g. attachment["url"]).
    #
    # Usage:
    #   bytes = client.download_file(url)
    #   client.download_file(url, to_path: Rails.root.join("tmp", "cv.pdf"))
    #
    # Returns:
    # - if to_path is provided: the string path written to
    # - else: binary String of file contents
    def download_file(url, to_path: nil, headers: nil, max_redirects: 3)
      uri = URI.parse(url)

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = perform_download(uri, headers: headers, max_redirects: max_redirects)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

      log_response(:get, uri, response, duration_ms)

      unless response.is_a?(Net::HTTPSuccess)
        raise HttpError.new(
          status: response.code.to_i,
          body: response.body.to_s,
          method: "GET",
          path: uri.to_s
        )
      end

      if to_path
        File.binwrite(to_path, response.body)
        to_path.to_s
      else
        response.body
      end
    rescue URI::InvalidURIError => e
      raise Error, "Invalid download URL: #{e.message}"
    rescue Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError => e
      raise Error, "Pinpoint file download failed: #{e.class}: #{e.message}"
    end

    # Create a comment on an application (JSON:API).
    #
    # Docs: POST /api/v1/comments [[1]]
    #
    # Example:
    #   client.create_comment_for_application(application_id, "Record created with ID: 123")
    def create_comment_for_application(application_id, body)
      raise ArgumentError, "application_id is required" if application_id.nil? || application_id.to_s.strip.empty?
      raise ArgumentError, "body is required" if body.nil? || body.to_s.strip.empty?

      payload = {
        "data" => {
          "type" => "comments",
          "attributes" => {
            "body_text" => body
          },
          "relationships" => {
            "commentable" => {
              "data" => {
                "type" => "applications",
                "id" => application_id.to_s
              }
            }
          }
        }
      }

      request_json(:post, "/api/v1/comments", body: payload)
    end

    # Convenience for your specific message format
    def comment_hibob_record_created(application_id, hibob_employee_id)
      create_comment_for_application(application_id, "Record created with ID: #{hibob_employee_id}")
    end

    private

    attr_reader :api_key

    def default_headers
      super.merge("X-API-KEY" => api_key)
    end

    def error_class = PinPoint::Client::Error
    def http_error_class = PinPoint::Client::HttpError

    def perform_download(uri, headers:, max_redirects:)
      raise Error, "Too many redirects downloading file" if max_redirects < 0

      req = Net::HTTP::Get.new(uri)
      req["X-API-KEY"] = api_key
      req["Accept"] = "*/*"
      (headers || {}).each { |k, v| req[k] = v }

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: open_timeout,
        read_timeout: read_timeout
      ) { |http| http.request(req) }

      if response.is_a?(Net::HTTPRedirection)
        location = response["location"]
        raise Error, "Redirect without Location header" if location.nil? || location.strip.empty?

        new_uri = URI.parse(location)
        new_uri = uri + location if new_uri.relative?
        return perform_download(new_uri, headers: headers, max_redirects: max_redirects - 1)
      end

      response
    end
  end
end

