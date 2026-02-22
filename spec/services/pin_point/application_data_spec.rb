# spec/services/pin_point/application_data_spec.rb
require "rails_helper"

RSpec.describe PinPoint::ApplicationData do
  subject(:app_data) { described_class.new(raw_json) }

  let(:raw_json) do
    {
      "data" => {
        "id" => "8863880",
        "attributes" => {
          "first_name" => "Bridget",
          "last_name" => "Parisian",
          "email" => "bridget@example.test",
          "full_name" => "Bridget Parisian",
          "attachments" => [
            { "context" => "cv", "filename" => "cv.pdf", "url" => "https://example.test/cv.pdf" },
            { "context" => "pdf_cv", "filename" => "cv.pdf", "url" => "https://example.test/pdf_cv.pdf" }
          ]
        }
      }
    }
  end

  describe "#id" do
    it "returns data.id when present" do
      expect(app_data.id).to eq("8863880")
    end

    it "falls back to data.attributes.id when data.id is missing" do
      raw_json["data"].delete("id")
      raw_json["data"]["attributes"]["id"] = "123"
      expect(app_data.id).to eq("123")
    end
  end

  it "exposes name/email attributes" do
    expect(app_data.first_name).to eq("Bridget")
    expect(app_data.last_name).to eq("Parisian")
    expect(app_data.email).to eq("bridget@example.test")
    expect(app_data.full_name).to eq("Bridget Parisian")
  end

  describe "#attachments" do
    it "returns [] when attachments missing" do
      raw_json["data"]["attributes"].delete("attachments")
      expect(app_data.attachments).to eq([])
    end
  end

  describe "#attachment_by_context" do
    it "finds the attachment for a given context" do
      att = app_data.attachment_by_context("pdf_cv")
      expect(att).to include("context" => "pdf_cv")
      expect(att["url"]).to eq("https://example.test/pdf_cv.pdf")
    end

    it "returns nil when not found" do
      expect(app_data.attachment_by_context("does_not_exist")).to be_nil
    end
  end
end
