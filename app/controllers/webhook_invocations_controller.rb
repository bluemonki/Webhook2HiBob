class WebhookInvocationsController < ApplicationController
  def index
    @webhook_invocations = WebhookInvocation.order(received_at: :desc).limit(100)
  end

  def table
    @webhook_invocations = WebhookInvocation.order(received_at: :desc).limit(100)
    render partial: "table", locals: { webhook_invocations: @webhook_invocations }
  end
end