# app/services/pin_point/client.rb
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module PinPoint
  class Client
    DEFAULT_BASE_URL = "https://developers-test.pinpointhq.com".freeze

    class Error < StandardError; end

    class HttpError < Error
      attr_reader :status, :body, :request_id, :method, :path

      def initialize(status:, body:, request_id:, method:, path:)
        @status = status
        @body = body
        @request_id = request_id
        @method = method
        @path = path
        super("Pinpoint API request failed (HTTP #{status}) #{method} #{path} request_id=#{request_id || "n/a"}")
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
      ApplicationData.new(get_application_with_attachments(application_id))
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

    # --- Generic verbs (useful as you expand) ---

    def get(path, params: nil, headers: nil)
      request_json(:get, path, params: params, headers: headers)
    end

    def post(path, body: nil, headers: nil)
      request_json(:post, path, body: body, headers: headers)
    end

    def put(path, body: nil, headers: nil)
      request_json(:put, path, body: body, headers: headers)
    end

    def delete(path, headers: nil)
      request_json(:delete, path, headers: headers)
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

      request_id = extract_request_id(response)
      log_response(:get, uri, response, duration_ms, request_id)

      unless response.is_a?(Net::HTTPSuccess)
        raise HttpError.new(
          status: response.code.to_i,
          body: response.body.to_s,
          request_id: request_id,
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

      post("/api/v1/comments", body: payload)
    end

    # Convenience for your specific message format
    def comment_hibob_record_created(application_id, hibob_employee_id)
      create_comment_for_application(application_id, "Record created with ID: #{hibob_employee_id}")
    end

    private

    attr_reader :api_key, :base_url, :open_timeout, :read_timeout, :logger

    # Some APIs return request ids under different headers; we’ll capture a few common ones.
    REQUEST_ID_HEADERS = [
      "X-Request-Id",
      "X-Request-ID",
      "X-Trace-Id",
      "X-Correlation-Id"
    ].freeze

    def request_json(method, path, params: nil, body: nil, headers: nil)
      uri = build_uri(path, params: params)
      http_request = build_request(method, uri, body: body, headers: headers)

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = perform(uri, http_request)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

      request_id = extract_request_id(response)

      log_response(method, uri, response, duration_ms, request_id)

      case response
      when Net::HTTPSuccess
        parse_json_body(response.body.to_s)
      else
        raise HttpError.new(
          status: response.code.to_i,
          body: response.body.to_s,
          request_id: request_id,
          method: method.to_s.upcase,
          path: uri.request_uri
        )
      end
    rescue JSON::ParserError => e
      raise Error, "Pinpoint API returned invalid JSON: #{e.message}"
    rescue Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError => e
      raise Error, "Pinpoint API request failed: #{e.class}: #{e.message}"
    end

    def build_uri(path, params:)
      base = base_url.end_with?("/") ? base_url : "#{base_url}/"
      uri = URI.join(base, path.sub(%r{\A/+}, ""))

      if params && !params.empty?
        # Rails-ish hash support; converts to query string safely
        uri.query = URI.encode_www_form(params.to_a)
      end

      uri
    end

    def build_request(method, uri, body:, headers:)
      klass =
        case method.to_sym
        when :get    then Net::HTTP::Get
        when :post   then Net::HTTP::Post
        when :put    then Net::HTTP::Put
        when :delete then Net::HTTP::Delete
        else
          raise ArgumentError, "Unsupported HTTP method: #{method.inspect}"
        end

      req = klass.new(uri)
      req["X-API-KEY"] = api_key
      req["Accept"] = "application/json"

      (headers || {}).each { |k, v| req[k] = v }

      if body
        req["Content-Type"] ||= "application/json"
        req.body = body.is_a?(String) ? body : JSON.dump(body)
      end

      req
    end

    def perform(uri, request)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: open_timeout,
        read_timeout: read_timeout
      ) { |http| http.request(request) }
    end

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

    def parse_json_body(body)
      return {} if body.strip.empty?
      JSON.parse(body)
    end

    def extract_request_id(response)
      REQUEST_ID_HEADERS.each do |header|
        value = response[header]
        return value if value && !value.strip.empty?
      end
      nil
    end

    def log_response(method, uri, response, duration_ms, request_id)
      return unless logger

      status = response.code.to_i
      level =
        if status >= 500
          :error
        elsif status >= 400
          :warn
        else
          :info
        end

      logger.public_send(
        level,
        "Pinpoint API #{method.to_s.upcase} #{uri} -> #{status} (#{duration_ms}ms) request_id=#{request_id || "n/a"}"
      )
    end

    def default_logger
      defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
    end
  end
end

