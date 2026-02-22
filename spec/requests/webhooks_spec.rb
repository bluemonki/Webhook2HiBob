require "rails_helper"

RSpec.describe "Webhooks", type: :request do
  describe "POST /webhooks", :vcr do
    # tests rely on valid external credentials and a real PinPoint application
    # id.  Set these in `config/credentials.yml.enc` or via environment
    # variables before running the spec for the first time; VCR will record
    # the real HTTP interactions and replay them on subsequent runs.  After
    # the cassette has been recorded you no longer need credentials, so don’t
    # skip when the cassette file already exists.
    before do
      cassette_path = Rails.root.join(
        "spec", "vcr_cassettes", "Webhooks", "POST_", "webhooks", "processes_the_webhook-end-to-end.yml"
      )

      unless cassette_path.exist? || (
             Rails.application.credentials[:pinpoint_api_key].present? &&
             Rails.application.credentials[:hibob_username].present? &&
             Rails.application.credentials[:hibob_password].present?
           )
        skip "provide PinPoint/HiBob credentials to record interaction or run once with credentials to generate cassette"
      end
    end

    let(:application_id) { 8863880 } # test application mentioned in controller comments
    let(:payload) do
      {
        event: "new_hire",
        triggeredAt: Time.current.iso8601,
        data: { application: { id: application_id } }
      }.to_json
    end

    it "processes the webhook end-to-end" do
      expect {
        post webhooks_path, params: payload, headers: { "CONTENT_TYPE" => "application/json" }
      }.to change(WebhookInvocation, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to be true
      expect(body["applicationId"]).to eq(application_id)

      invocation = WebhookInvocation.last
      expect(invocation.status).to eq("succeeded")
      expect(invocation.hibob_employee_id).to be_present
    end
  end

  describe "error cases" do
    it "returns 422 when application id is missing" do
      post webhooks_path, params: { foo: 'bar' }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/missing application id/)
    end

    it "records a failure invocation for invalid JSON" do
      expect {
        post webhooks_path, params: "not json", headers: { "CONTENT_TYPE" => "application/json" }
      }.to change(WebhookInvocation, :count).by(1)

      expect(response).to have_http_status(:bad_request)
      expect(WebhookInvocation.last.status).to eq("failed")
    end
  end
end
