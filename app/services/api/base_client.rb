# app/services/api/base_client.rb
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Api
  class BaseClient
    class Error < StandardError; end

    class HttpError < Error
      attr_reader :status, :body, :method, :path

      def initialize(status:, body:, method:, path:)
        @status = status
        @body = body
        @method = method
        @path = path
        super("HTTP request failed (HTTP #{status}) #{method} #{path}")
      end
    end

    def initialize(base_url:, open_timeout: 5, read_timeout: 15, logger: default_logger)
      raise ArgumentError, "base_url is required" if base_url.nil? || base_url.to_s.strip.empty?

      @base_url = base_url
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @logger = logger
    end

    private

    attr_reader :base_url, :open_timeout, :read_timeout, :logger

    def default_headers
      { "Accept" => "application/json" }
    end

    def build_uri(path, params: nil)
      base = base_url.end_with?("/") ? base_url : "#{base_url}/"
      uri = URI.join(base, path.sub(%r{\A/+}, ""))

      if params && !params.empty?
        uri.query = URI.encode_www_form(params.to_a)
      end

      uri
    end

    def request_json(method, path, params: nil, body: nil, headers: nil)
      uri = build_uri(path, params: params)
      request = build_request(method, uri, body: body, headers: headers)

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = perform(uri, request)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

      log_response(method, uri, response, duration_ms)

      case response
      when Net::HTTPSuccess, Net::HTTPCreated
        parse_json_body(response.body.to_s)
      else
        raise http_error_class.new(
          status: response.code.to_i,
          body: response.body.to_s,
          method: method.to_s.upcase,
          path: uri.request_uri
        )
      end
    rescue JSON::ParserError => e
      raise error_class, "API returned invalid JSON: #{e.message}"
    rescue Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError => e
      raise error_class, "API request failed: #{e.class}: #{e.message}"
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

      # Default + caller headers
      default_headers.merge(headers || {}).each { |k, v| req[k] = v }

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

    def parse_json_body(body)
      return {} if body.strip.empty?
      JSON.parse(body)
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

      logger.public_send(level, "#{self.class.name} #{method.to_s.upcase} #{uri} -> #{status} (#{duration_ms}ms)")
    end

    # Allow subclasses to map to their own error types
    def error_class = Error
    def http_error_class = HttpError

    def default_logger
      defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
    end
  end
end