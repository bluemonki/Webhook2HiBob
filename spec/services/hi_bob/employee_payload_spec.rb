# spec/services/hi_bob/employee_payload_spec.rb
require "rails_helper"
require "date"

RSpec.describe HiBob::EmployeePayload do
  describe ".from_pinpoint" do
    let(:pinpoint_app) do
      instance_double(
        "PinPoint::ApplicationData",
        first_name: "John",
        last_name: "Doe",
        email: "johndoe@example.test"
      )
    end

    it "builds the required HiBob payload and applies defaults" do
      # freeze Date.today so the test is deterministic
      allow(Date).to receive(:today).and_return(Date.new(2026, 2, 21))

      payload = described_class.from_pinpoint(pinpoint_app).to_h

      expect(payload).to include(
                           "firstName" => "John",
                           "surname" => "Doe",
                           "email" => "johndoe@example.test"
                         )

      expect(payload["work"]).to include(
                                   "site" => "New York (Demo)",
                                   "startDate" => "2026-04-21" # 2 months from 2026-02-21
                                 )
    end

    it "allows overriding title and department" do
      allow(Date).to receive(:today).and_return(Date.new(2026, 2, 21))

      payload = described_class.from_pinpoint(
        pinpoint_app,
        title: "Chief Engineer",
        department: "Administration"
      ).to_h

      expect(payload["work"]).to include(
                                   "title" => "Chief Engineer",
                                   "department" => "Administration"
                                 )
    end
  end

  describe "#to_h validation" do
    it "raises if required fields are missing" do
      obj = described_class.new(first_name: nil, surname: "Doe", email: "a@b.com")
      expect { obj.to_h }.to raise_error(ArgumentError, /Missing required HiBob fields: firstName/)

      obj = described_class.new(first_name: "John", surname: nil, email: "a@b.com")
      expect { obj.to_h }.to raise_error(ArgumentError, /Missing required HiBob fields: surname/)

      obj = described_class.new(first_name: "John", surname: "Doe", email: nil)
      expect { obj.to_h }.to raise_error(ArgumentError, /Missing required HiBob fields: email/)
    end
  end
end
