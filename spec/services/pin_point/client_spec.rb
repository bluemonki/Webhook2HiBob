# spec/services/pin_point/client_spec.rb
require "rails_helper"
require "json"
require "net/http"
require "tempfile"

RSpec.describe PinPoint::Client do
  let(:api_key) { "test-api-key" }

  subject(:client) { described_class.new(api_key: api_key) }

  def stub_net_http_start_with_response(response, &capture_request)
    captured_request = nil

    allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
      fake_http = Object.new
      fake_http.define_singleton_method(:request) do |req|
        captured_request = req
        response
      end
      block.call(fake_http)
    end

    capture_request.call(captured_request) if capture_request
  end

  describe "#initialize" do
    it "raises ArgumentError when api_key is blank" do
      expect { described_class.new(api_key: "") }.to raise_error(ArgumentError, /api_key is required/)
      expect { described_class.new(api_key: "   ") }.to raise_error(ArgumentError, /api_key is required/)
      expect { described_class.new(api_key: nil) }.to raise_error(ArgumentError, /api_key is required/)
    end
  end

  describe "#get_application_with_attachments" do
    it "GETs /api/v1/applications/:id with extra_fields[applications]=attachments and sets X-API-KEY" do
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return(JSON.dump({ "data" => { "id" => "1" } }))

      captured_request = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |req|
          captured_request = req
          response
        end
        block.call(fake_http)
      end

      result = client.get_application_with_attachments(123)

      expect(result).to eq({ "data" => { "id" => "1" } })
      expect(captured_request).to be_a(Net::HTTP::Get)
      expect(captured_request.path).to eq("/api/v1/applications/123?extra_fields[applications]=attachments")
      expect(captured_request["X-API-KEY"]).to eq(api_key)
      expect(captured_request["Accept"]).to eq("application/json")
    end

    it "raises HttpError on non-2xx" do
      response = Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized")
      allow(response).to receive(:body).and_return("nope")

      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) { |_req| response }
        block.call(fake_http)
      end

      expect {
        client.get_application_with_attachments(123)
      }.to raise_error(PinPoint::Client::HttpError) { |e|
        expect(e.status).to eq(401)
        expect(e.body).to eq("nope")
        expect(e.method).to eq("GET")
      }
    end
  end

  describe "#list_applications" do
    it "GETs /api/v1/applications with query params when provided" do
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return(JSON.dump({ "data" => [] }))

      captured_request = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |req|
          captured_request = req
          response
        end
        block.call(fake_http)
      end

      result = client.list_applications(params: { page: 2, per_page: 50 })

      expect(result).to eq({ "data" => [] })
      expect(captured_request).to be_a(Net::HTTP::Get)
      expect(captured_request.path).to eq("/api/v1/applications?page=2&per_page=50")
    end
  end

  describe "#create_comment_for_application" do
    it "POSTs JSON:API to /api/v1/comments for the application" do
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return(JSON.dump({ "data" => { "type" => "comments", "id" => 12345 } }))

      captured_request = nil
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |req|
          captured_request = req
          response
        end
        block.call(fake_http)
      end

      result = client.create_comment_for_application("8863880", "Record created with ID: 123")

      expect(result).to eq( 12345 )
      expect(captured_request).to be_a(Net::HTTP::Post)
      expect(captured_request.path).to eq("/api/v1/comments")
      expect(captured_request["X-API-KEY"]).to eq(api_key)
      expect(captured_request["Accept"]).to eq("application/json")
      expect(captured_request["Content-Type"]).to eq("application/json")

      body = JSON.parse(captured_request.body)
      expect(body.dig("data", "type")).to eq("comments")
      expect(body.dig("data", "attributes", "body_text")).to eq("Record created with ID: 123")
      expect(body.dig("data", "relationships", "commentable", "data", "type")).to eq("applications")
      expect(body.dig("data", "relationships", "commentable", "data", "id")).to eq("8863880")
    end

    it "validates inputs" do
      expect { client.create_comment_for_application("", "hi") }.to raise_error(ArgumentError, /application_id is required/)
      expect { client.create_comment_for_application("1", "") }.to raise_error(ArgumentError, /body is required/)
    end
  end

  describe "#download_file" do
    let(:url) { "https://example.test/file.pdf" }

    it "returns bytes when to_path is nil" do
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return("FILEBYTES")
      allow(response).to receive(:[]).and_return(nil)

      allow(client).to receive(:perform_download).and_return(response)
      allow(client).to receive(:log_response)

      bytes = client.download_file(url)
      expect(bytes).to eq("FILEBYTES")
    end

    it "writes to disk when to_path is provided" do
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return("FILEBYTES")
      allow(response).to receive(:[]).and_return(nil)

      allow(client).to receive(:perform_download).and_return(response)
      allow(client).to receive(:log_response)

      tmp = Tempfile.new(["pin_point", ".pdf"])
      tmp.close

      begin
        path = client.download_file(url, to_path: tmp.path)
        expect(path).to eq(tmp.path)
        expect(File.binread(tmp.path)).to eq("FILEBYTES")
      ensure
        File.delete(tmp.path) if File.exist?(tmp.path)
      end
    end

    it "follows redirects in perform_download" do
      redirect = instance_double(Net::HTTPRedirection)
      allow(redirect).to receive(:is_a?).with(Net::HTTPRedirection).and_return(true)
      allow(redirect).to receive(:[]).with("location").and_return("https://example.test/final.pdf")

      success = instance_double(Net::HTTPSuccess, body: "OK", code: "200", :[] => nil)
      allow(success).to receive(:is_a?).with(Net::HTTPRedirection).and_return(false)

      # perform_download calls Net::HTTP.start internally, so stub it twice:
      call_count = 0
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        call_count += 1
        fake_http = Object.new
        fake_http.define_singleton_method(:request) do |_req|
          call_count == 1 ? redirect : success
        end
        block.call(fake_http)
      end

      # call the private method to focus on redirect behavior
      uri = URI.parse(url)
      response = client.send(:perform_download, uri, headers: nil, max_redirects: 3)
      expect(response).to eq(success)
    end
  end
end