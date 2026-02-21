# app/services/hi_bob/client.rb
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "base64"
require "multipart/post"
require "net/http/post/multipart"

module HiBob
  class Client
    DEFAULT_BASE_URL = "https://api.hibob.com/v1".freeze

    class Error < StandardError; end

    class HttpError < Error
      attr_reader :status, :body, :method, :path

      def initialize(status:, body:, method:, path:)
        @status = status
        @body = body
        @method = method
        @path = path
        super("HiBob API request failed (HTTP #{status}) #{method} #{path}")
      end
    end

    def initialize(username:, password:, base_url: DEFAULT_BASE_URL, open_timeout: 5, read_timeout: 20, logger: default_logger)
      raise ArgumentError, "username is required" if username.nil? || username.strip.empty?
      raise ArgumentError, "password is required" if password.nil? || password.strip.empty?

      @username = username
      @password = password
      @base_url = base_url
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @logger = logger
    end

    # Create company employee
    # Accepts either:
    # - Hash payload
    # - HiBob::EmployeePayload (responds to #to_h)
    def create_employee(payload)
      normalized =
        if payload.respond_to?(:to_h)
          payload.to_h
        else
          payload
        end

      post_json("people", normalized)
    end

    def upload_shared_document(employee_id:, file_path:)
      raise ArgumentError, "employee_id is required" if employee_id.nil? || employee_id.to_s.strip.empty?
      raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?

      path = "/docs/people/#{employee_id}/shared/upload"
      uri = build_uri(path)

      upload_io = UploadIO.new(
        File.open(file_path, "rb"),
        "application/octet-stream",
        File.basename(file_path)
      )
      request = Net::HTTP::Post::Multipart.new(uri.request_uri, 'file' => upload_io)
      request["Accept"] = "application/json"
      request["Authorization"] = basic_auth_header(username, password)

      response = perform(uri, request)

      case response
      when Net::HTTPSuccess, Net::HTTPCreated
        body = response.body.to_s
        body.strip.empty? ? {} : JSON.parse(body)
      else
        raise HttpError.new(
          status: response.code.to_i,
          body: response.body.to_s,
          method: "POST",
          path: uri.request_uri
        )
      end
    ensure
      # Ensure the underlying file handle gets closed
      upload_io&.io&.close
    end

    # Search employees (People Search API)
    # Docs: POST /people/search [[1]]
    #
    # Returns the raw response hash (typically includes an "employees" array).
    def search_people(query:, fields: nil, limit: 10, include_inactive: false)
      raise ArgumentError, "query is required" if query.nil? || (query.respond_to?(:empty?) && query.empty?)

      payload = {
        "query" => query,
        "limit" => limit,
        "includeInactive" => include_inactive
      }

      payload["fields"] = fields if fields

      post_json("/people/search", payload)
    end

    # Convenience: find a single employee by email.
    # Returns the first matching employee hash or nil.
    def find_employee_by_email(email, fields: nil, include_inactive: false)
      raise ArgumentError, "email is required" if email.nil? || email.to_s.strip.empty?

      # Query format is documented by HiBob People Search endpoint [[1]].
      # If your tenant requires a different query shape, adjust just this block.
      query = {
        "equals" => {
          "field" => "email",
          "value" => email
        }
      }

      result = search_people(query: query, fields: fields, limit: 1, include_inactive: include_inactive)
      employees = result["employees"]
      return nil unless employees.is_a?(Array)

      employees.first
    end

    private

    attr_reader :username, :password, :base_url, :open_timeout, :read_timeout, :logger

    def post_json(path, payload)
      uri = build_uri(path)
      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["Authorization"] = basic_auth_header(username, password)
      request.body = JSON.dump(payload)

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = perform(uri, request)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

      log_response(:post, uri, response, duration_ms)

      case response
      when Net::HTTPSuccess, Net::HTTPCreated
        body = response.body.to_s
        body.strip.empty? ? {} : JSON.parse(body)
      else
        raise HttpError.new(
          status: response.code.to_i,
          body: response.body.to_s,
          method: "POST",
          path: uri.request_uri
        )
      end
    rescue JSON::ParserError => e
      raise Error, "HiBob API returned invalid JSON: #{e.message}"
    rescue Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError => e
      raise Error, "HiBob API request failed: #{e.class}: #{e.message}"
    end

    def build_uri(path)
      base = base_url.end_with?("/") ? base_url : "#{base_url}/"
      URI.join(base, path.sub(%r{\A/+}, ""))
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

    def basic_auth_header(user, pass)
      encoded = Base64.strict_encode64("#{user}:#{pass}")
      "Basic #{encoded}"
    end

    def log_response(method, uri, response, duration_ms)
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

      logger.public_send(level, "HiBob API #{method.to_s.upcase} #{uri} -> #{status} (#{duration_ms}ms)")
    end

    def default_logger
      defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
    end
  end
end