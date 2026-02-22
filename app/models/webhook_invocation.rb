# app/models/webhook_invocation.rb
class WebhookInvocation < ApplicationRecord
  serialize :metadata, coder: JSON
  # payload_json can just be stored as a String; serialize only if you want hash access:
  # serialize :payload_json, coder: JSON

  STATUSES = %w[received processing succeeded failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :received_at, presence: true
end
