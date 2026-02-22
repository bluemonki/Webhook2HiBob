class WebhookInvocationsController < ApplicationController
  def index
    @webhook_invocations = WebhookInvocation.order(received_at: :desc).limit(100)
  end

  def table
    @webhook_invocations = WebhookInvocation.order(received_at: :desc).limit(100)
  end
end
