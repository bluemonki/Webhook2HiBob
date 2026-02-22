# spec/services/hi_bob/client_spec.rb
require "rails_helper"
require "json"
require "net/http"

RSpec.describe HiBob::Client do
  let(:username) { "test-user" }
  let(:password) { "test-pass" }

  subject(:client) do
    described_class.new(username: username, password: password)
  end

  def stub_http_with(response, &inspect_request)
    captured_request = nil

    allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
      fake_http = Object.new
      fake_http.define_singleton_method(:request) do |req|
        captured_request = req
        response
      end
      block.call(fake_http)
    end

    inspect_request.call(captured_request) if inspect_request
  end

  describe "#create_employee" do
    it "POSTs JSON to /v1/people with Basic Auth and parses JSON response" do
      payload = { "email" => "jane@example.com", "firstName" => "Jane", "surname" => "Doe" }

      response = Net::HTTPCreated.new("1.1", "201", "Created")
      allow(response).to receive(:body).and_return(JSON.dump({ "id" => "123" }))

      captured_request = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |req|
          captured_request = req
          response
        end
        block.call(fake_http)
      end

      result = client.create_employee(payload)

      expect(result).to eq({ "id" => "123" })
      expect(captured_request).to be_a(Net::HTTP::Post)
      expect(captured_request.path).to eq("/v1/people")
      expect(captured_request["Accept"]).to eq("application/json")
      expect(captured_request["Content-Type"]).to eq("application/json")
      expect(captured_request["Authorization"]).to start_with("Basic ")
      expect(captured_request.body).to eq(JSON.dump(payload))
    end

    it "accepts a payload object that responds to #to_h" do
      payload_obj = instance_double("HiBob::EmployeePayload", to_h: { "email" => "jane@example.com", "firstName" => "Jane", "surname" => "Doe" })

      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return(JSON.dump({ "id" => "123" }))

      captured_request = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |req|
          captured_request = req
          response
        end
        block.call(fake_http)
      end

      client.create_employee(payload_obj)

      expect(captured_request.body).to eq(JSON.dump(payload_obj.to_h))
    end

    it "raises HttpError on non-2xx responses" do
      response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
      allow(response).to receive(:body).and_return("nope")

      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) { |_req| response }
        block.call(fake_http)
      end

      expect {
        client.create_employee({ "email" => "x@example.com", "firstName" => "X", "surname" => "Y" })
      }.to raise_error(HiBob::Client::HttpError) { |e|
        expect(e.status).to eq(400)
        expect(e.body).to eq("nope")
      }
    end
  end

  describe "#upload_shared_document" do
    it "raises ArgumentError when employee_id is blank" do
      expect {
        client.upload_shared_document(employee_id: "", file_path: "/tmp/file.pdf")
      }.to raise_error(ArgumentError, /employee_id is required/)

      expect {
        client.upload_shared_document(employee_id: "   ", file_path: "/tmp/file.pdf")
      }.to raise_error(ArgumentError, /employee_id is required/)

      expect {
        client.upload_shared_document(employee_id: nil, file_path: "/tmp/file.pdf")
      }.to raise_error(ArgumentError, /employee_id is required/)
    end

    it "raises ArgumentError when file_path is blank" do
      expect {
        client.upload_shared_document(employee_id: "123", file_path: "")
      }.to raise_error(ArgumentError, /file_path is required/)

      expect {
        client.upload_shared_document(employee_id: "123", file_path: "   ")
      }.to raise_error(ArgumentError, /file_path is required/)

      expect {
        client.upload_shared_document(employee_id: "123", file_path: nil)
      }.to raise_error(ArgumentError, /file_path is required/)
    end

    it "POSTs multipart data to /docs/people/:id/shared/upload with Basic Auth and parses JSON" do
      file = Tempfile.new([ "cv", ".pdf" ])
      file.binmode
      file.write("%PDF fake")
      file.close

      response = Net::HTTPCreated.new("1.1", "201", "Created")
      allow(response).to receive(:body).and_return(JSON.dump({ "ok" => true }))

      captured_request = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |req|
          captured_request = req
          response
        end
        block.call(fake_http)
      end

      result = client.upload_shared_document(employee_id: "123", file_path: file.path)

      expect(result).to eq({ "ok" => true })

      expect(captured_request).to be_a(Net::HTTP::Post::Multipart)
      expect(captured_request.path).to eq("/v1/docs/people/123/shared/upload")
      expect(captured_request["Accept"]).to eq("application/json")
      expect(captured_request["Authorization"]).to start_with("Basic ")

      # multipart-post sets the content type + boundary automatically
      expect(captured_request["Content-Type"]).to match(/\Amultipart\/form-data;\s*boundary=/)

      # Body should exist (we don't fully parse multipart in a unit test)
      expect(captured_request["Content-Type"]).to match(/\Amultipart\/form-data;\s*boundary=/)

      # multipart-post typically uses streaming, so `body` may be nil.
      expect(captured_request.body_stream).not_to be_nil
    ensure
      file&.unlink
    end

    it "returns {} when HiBob responds with empty body" do
      file = Tempfile.new([ "cv", ".pdf" ])
      file.write("fake")
      file.close

      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return("")

      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) { |_req| response }
        block.call(fake_http)
      end

      result = client.upload_shared_document(employee_id: "123", file_path: file.path)
      expect(result).to eq({})
    ensure
      file&.unlink
    end

    it "raises HttpError on non-2xx responses" do
      file = Tempfile.new([ "cv", ".pdf" ])
      file.write("fake")
      file.close

      response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
      allow(response).to receive(:body).and_return("nope")

      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) { |_req| response }
        block.call(fake_http)
      end

      expect {
        client.upload_shared_document(employee_id: "123", file_path: file.path)
      }.to raise_error(HiBob::Client::HttpError) { |e|
        expect(e.status).to eq(400)
        expect(e.body).to eq("nope")
      }
    ensure
      file&.unlink
    end

    it "closes the underlying file handle even on success" do
      io = instance_double(File)
      expect(io).to receive(:close)

      upload_io = instance_double(UploadIO, io: io)

      allow(File).to receive(:open).and_return(io)
      allow(UploadIO).to receive(:new).and_return(upload_io)

      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return(JSON.dump({ "ok" => true }))

      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) { |_req| response }
        block.call(fake_http)
      end

      client.upload_shared_document(employee_id: "123", file_path: "ignored.pdf")
    end
  end
end
