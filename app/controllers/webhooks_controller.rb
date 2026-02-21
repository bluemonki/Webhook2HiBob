# routes.rb
# Routing to define the controller method to handle incoming webhooks
Rails.application.routes.draw do
  resources :webhooks, only: [:create]
end

# app/controllers/webhooks_controller.rb
# Respond to HTTP POST requests sent to the /webhooks route defined above
class WebhooksController < ApplicationController
  skip_forgery_protection

  # - Listen for the new hire event
  # - Use Pinpoint application with `id=8863880` for testing. You can also use any other application.
  def create
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    saved_path = nil

    # don't understand where I get the signing key for this
    # unless verified_request?
    #   render json: { error: "unauthorized" }, status: :unauthorized
    #   return
    # end

    invocation = WebhookInvocation.create!(
      provider: "pinpoint",
      status: "processing",
      received_at: Time.current,
      request_id: request.request_id,
      remote_ip: request.remote_ip,
      user_agent: request.user_agent
    )

    payload = JSON.parse(request.raw_post)

    event = payload["event"]
    triggered_at = payload["triggeredAt"]
    application_id = payload.dig("data", "application", "id")

    invocation.update!(
      event: event,
      triggered_at: (Time.zone.parse(triggered_at) rescue nil),
      application_id: application_id,
      payload_json: { event: event, triggeredAt: triggered_at, applicationId: application_id }.to_json
    )

    if application_id.nil?

      invocation.update!(
        status: "failed",
        http_status: 422,
        error_class: "MissingApplicationId",
        error_message: "missing application id",
        completed_at: Time.current
      )

      render json: { error: "missing application id" }, status: :unprocessable_entity
      return
    end

    # Get the application data from PinPoint
    pinpoint = PinPoint::Client.new(
      api_key: Rails.application.credentials.fetch(:pinpoint_api_key)
    )

    # And the CV attachment
    app_data = pinpoint.get_application_data_with_attachments(application_id)

    # Save this locally
    saved_path = pinpoint.download_application_attachment(
      app_data,
      context: "pdf_cv",
      to_path: Rails.root.join("tmp")
    )


    # Create the basic Employee record in HiBob with details from the Pinpoint application
    # - The employee should be a part of the `New York (Demo)` work site
    # - Any date in the future can be used for start date
    hibob = HiBob::Client.new(
      username: Rails.application.credentials.fetch(:hibob_username),
      password: Rails.application.credentials.fetch(:hibob_password)
    )
    # Create the Employee data from the PinPoint data
    # This defaults the site to New York (Demo) and sets the start date
    # to 2 months from today
    employee_payload = HiBob::EmployeePayload.from_pinpoint(app_data)

    # Check if the employee is already registered
    existing_employee = hibob.find_employee_by_email(app_data.email)
    hibob_employee_id = nil

    unless existing_employee
      # Create the Employee
      hibob_employee_data = hibob.create_employee(employee_payload)
      hibob_employee_id = hibob_employee_data.fetch("id")
    else
      hibob_employee_id = existing_employee.fetch("id")
    end

    invocation.update!(hibob_employee_id: hibob_employee_id)

    # Update the employee record with their CV (that was attached as part of the
    # Pinpoint application, use one with pdf_cv context, as a public document in HiBob
    hibob.upload_shared_document(employee_id: hibob_employee_id,
                                 file_path: saved_path)

    # Add a comment on the Pinpoint application stating the record has been created
    # quoting the HiBob Reference ID for the employee record
    # i.e. “Record created with ID: xxxxxx”
    pinpoint_comment_id = pinpoint.comment_hibob_record_created(application_id, hibob_employee_id)
    invocation.update!(pinpoint_comment_id: pinpoint_comment_id)

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    invocation.update!(
      status: "succeeded",
      http_status: 200,
      completed_at: Time.current,
      duration_ms: duration_ms
    )

    render json: {
      ok: true,
      event: event,
      triggeredAt: triggered_at,
      applicationId: application_id,
      pinpointApplication: app_data
    }, status: :ok
  rescue JSON::ParserError
    invocation&.update!(
      status: "failed",
      http_status: 400,
      error_class: "JSON::ParserError",
      error_message: "invalid JSON",
      completed_at: Time.current
    )
    render json: { error: "invalid JSON" }, status: :bad_request
  rescue PinPoint::Client::HttpError => e
    invocation&.update!(
      status: "failed",
      http_status: 502,
      error_class: e.class.name,
      error_message: e.message,
      completed_at: Time.current,
      metadata: { pinpoint_status: e.status, pinpoint_request_id: e.request_id }.to_json
    )
    render json: { error: "PinPoint error", status: e.status, request_id: e.request_id }, status: :bad_gateway
  rescue HiBob::Client::HttpError => e
    invocation&.update!(
      status: "failed",
      http_status: 502,
      error_class: e.class.name,
      error_message: e.message,
      completed_at: Time.current
    )
    render json: { error: "HiBob error", status: e.status, message: e.message }, status: :bad_gateway
  ensure
    File.delete(saved_path) if saved_path && File.exist?(saved_path)
  end

  private

  def verified_request?
    return false unless hmac_header

    ActiveSupport::SecurityUtils.secure_compare(computed_hmac, hmac_header)
  end

  def hmac_header
    request.headers['PINPOINT-HMAC-SHA256']
  end

  def computed_hmac
    digest = OpenSSL::HMAC.digest(OpenSSL::Digest.new('sha256'), signing_secret, request.body.read)
    Base64.strict_encode64(digest)
  end

  # Your signing secret would typically be stored in encrypted credentials if running Rails 5.1 or later.
  def signing_secret
    Rails.application.credentials.dig(:signing_secret)
  end
end