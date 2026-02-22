# app/services/pin_point/application_data.rb
# frozen_string_literal: true

module PinPoint
  class ApplicationData
    def initialize(raw_json)
      @raw_json = raw_json
    end

    def id
      raw_json.dig("data", "id") || raw_json.dig("data", "attributes", "id")
    end

    def first_name
      raw_json.dig("data", "attributes", "first_name")
    end

    def last_name
      raw_json.dig("data", "attributes", "last_name")
    end

    def email
      raw_json.dig("data", "attributes", "email")
    end

    def full_name
      raw_json.dig("data", "attributes", "full_name")
    end

    def attachments
      raw_json.dig("data", "attributes", "attachments") || []
    end

    def attachment_by_context(context)
      attachments.find { |att| att.is_a?(Hash) && att["context"] == context }
    end

    private

    attr_reader :raw_json
  end
end
