# Web Hook2 HiBob

A small Rails app that receives PinPoint webhooks, downloads attachments, creates
employees in HiBob and records each webhook invocation for inspection.

**Quick Start**
- **Prerequisites:** Install Ruby (use rbenv/rvm), Bundler, and SQLite.
- **Install gems:** `bundle install`
- **Database:** `bin/rails db:create db:migrate` (the project uses SQLite by default)
- **Run server:** `bin/rails server` and open `http://localhost:3000`

**Run Tests**
- Run the full test suite: `bundle exec rspec`
- Tests that exercise external APIs use VCR and WebMock. To record a new cassette
	you must provide valid credentials (either in `config/credentials.yml.enc` or via
	environment variables): `PINPOINT_API_KEY`, `HIBOB_USERNAME`, `HIBOB_PASSWORD`.
- To re-record the webhook VCR cassette: delete the cassette at
	`spec/vcr_cassettes/Webhooks/POST_/webhooks/processes_the_webhook_end-to-end.yml`
	then run the request spec that records it: `bundle exec rspec spec/requests/webhooks_spec.rb`.

**Run the App**
- Run the app with `bin/dev`

**Where to view webhook invocations**
- Web UI: open `http://localhost:3000/webhook_invocations` to see the table of
	recent webhook invocations. The page uses a Turbo frame that loads the table from
	`GET /webhook_invocations/table`.

**VCR / Security notes**
- VCR is configured in `spec/support/vcr.rb`. Sensitive values (PinPoint API key,
	HiBob credentials) are filtered when recording cassettes. The configuration also
	scrubs AWS access key ids that appear in presigned S3 URLs.

**Useful files & routes**
- Controller: [app/controllers/webhooks_controller.rb](app/controllers/webhooks_controller.rb)
- Invocation model: [app/models/webhook_invocation.rb](app/models/webhook_invocation.rb)
- Routes: `resources :webhook_invocations, only: [:index]` and a collection route
	`GET /webhook_invocations/table` (see `config/routes.rb`).

