# app/services/hi_bob/employee_payload.rb
# frozen_string_literal: true

require "date"

module HiBob
  class EmployeePayload
    DEFAULT_SITE = "New York (Demo)".freeze

    def initialize(first_name:, surname:, email:, title: nil, department: nil, site: DEFAULT_SITE, start_date: default_start_date)
      @first_name = presence(first_name)
      @surname = presence(surname)
      @email = presence(email)
      @title = presence(title)
      @department = presence(department)
      @site = presence(site) || DEFAULT_SITE
      @start_date = start_date
    end

    # Build from Pinpoint data and supply any missing data via defaults and/or overrides.
    #
    # Example:
    #   payload = HiBob::EmployeePayload.from_pinpoint(pinpoint_app, title: "Chief Engineer", department: "Administration")
    def self.from_pinpoint(pinpoint_application_data, title: nil, department: nil, site: DEFAULT_SITE, start_date: default_start_date)
      new(
        first_name: pinpoint_application_data.first_name,
        surname: pinpoint_application_data.last_name,
        email: pinpoint_application_data.email,
        title: title,
        department: department,
        site: site,
        start_date: start_date
      )
    end

    def to_h
      validate!

      {
        "firstName" => first_name,
        "surname" => surname,
        "email" => email,
        "work" => {
          "site" => site,
          "startDate" => start_date_iso,
          "title" => title,
          "department" => department
        }.compact
      }
    end

    private

    attr_reader :first_name, :surname, :email, :title, :department, :site, :start_date

    def validate!
      missing = []
      missing << "firstName" if first_name.nil?
      missing << "surname" if surname.nil?
      missing << "email" if email.nil?

      return if missing.empty?

      raise ArgumentError, "Missing required HiBob fields: #{missing.join(", ")}"
    end

    def start_date_iso
      d =
        case start_date
        when Date then start_date
        when String then Date.parse(start_date)
        else
          raise ArgumentError, "start_date must be a Date or ISO string"
        end

      d.iso8601
    end

    def presence(value)
      v = value.is_a?(String) ? value.strip : value
      v.nil? || (v.respond_to?(:empty?) && v.empty?) ? nil : v
    end

    def self.default_start_date
      Date.today >> 2 # 2 months from now
    end

    def default_start_date
      self.class.default_start_date
    end
  end
end