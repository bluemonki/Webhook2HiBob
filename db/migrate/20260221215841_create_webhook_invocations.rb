class CreateWebhookInvocations < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_invocations do |t|
      t.string   :provider, null: false, default: "pinpoint"
      t.string   :event
      t.datetime :triggered_at

      t.datetime :received_at, null: false
      t.datetime :completed_at
      t.integer  :duration_ms

      t.string   :request_id
      t.string   :remote_ip
      t.string   :user_agent
      t.boolean  :signature_valid

      t.string   :application_id
      t.string   :hibob_employee_id
      t.string   :pinpoint_comment_id

      t.string   :status, null: false, default: "received"
      t.integer  :http_status
      t.string   :error_class
      t.text     :error_message

      t.text     :payload_json
      t.text     :metadata

      t.timestamps
    end

    add_index :webhook_invocations, :request_id
    add_index :webhook_invocations, :application_id
    add_index :webhook_invocations, :hibob_employee_id
    add_index :webhook_invocations, :pinpoint_comment_id
    add_index :webhook_invocations, [ :status, :received_at ]
    add_index :webhook_invocations, :received_at
  end
end
