require "rails_helper"

RSpec.describe "WebhookInvocations", type: :request do
  describe "GET /webhook_invocations" do
    let!(:invocation) do
      WebhookInvocation.create!(
        received_at: 1.hour.ago,
        status: "received",
        application_id: "x",
        hibob_employee_id: 1,
        pinpoint_comment_id: nil,
        http_status: 200
      )
    end

    it "shows the table inside a turbo frame" do
      get webhook_invocations_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("id=\"webhook_invocations_table\"")
      # verify one of the cells from our record
      expect(response.body).to include("<td>received</td>")
    end
  end

  describe "GET /webhook_invocations/table" do
    let!(:invocation) do
      WebhookInvocation.create!(
        received_at: 1.hour.ago,
        status: "received",
        application_id: "x",
        hibob_employee_id: 1,
        pinpoint_comment_id: nil,
        http_status: 200
      )
    end

    it "renders a turbo frame wrapper when called by a frame request" do
      get table_webhook_invocations_path, headers: { "Turbo-Frame" => "webhook_invocations_table" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("id=\"webhook_invocations_table\"")
      expect(response.body).to include("<td>received</td>")
    end

    it "still works without the Turbo-Frame header" do
      get table_webhook_invocations_path
      expect(response.body).to include("<table>")
    end
  end
end
