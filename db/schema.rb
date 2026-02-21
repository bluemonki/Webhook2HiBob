# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_21_215841) do
  create_table "webhook_invocations", force: :cascade do |t|
    t.string "application_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_class"
    t.text "error_message"
    t.string "event"
    t.string "hibob_employee_id"
    t.integer "http_status"
    t.text "metadata"
    t.text "payload_json"
    t.string "pinpoint_comment_id"
    t.string "provider", default: "pinpoint", null: false
    t.datetime "received_at", null: false
    t.string "remote_ip"
    t.string "request_id"
    t.boolean "signature_valid"
    t.string "status", default: "received", null: false
    t.datetime "triggered_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["application_id"], name: "index_webhook_invocations_on_application_id"
    t.index ["hibob_employee_id"], name: "index_webhook_invocations_on_hibob_employee_id"
    t.index ["pinpoint_comment_id"], name: "index_webhook_invocations_on_pinpoint_comment_id"
    t.index ["received_at"], name: "index_webhook_invocations_on_received_at"
    t.index ["request_id"], name: "index_webhook_invocations_on_request_id"
    t.index ["status", "received_at"], name: "index_webhook_invocations_on_status_and_received_at"
  end
end
