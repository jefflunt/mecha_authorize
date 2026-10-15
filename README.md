# MechaAuthorize

`mecha_authorize` provides a YAML-driven, closed-by-default route authorization system for Rails applications. Every incoming request is evaluated against an explicit route registry before controller actions run, with built-in static route parity auditing and behavioral persona matrix probing.

## Installation

Add this line to your application's `Gemfile`:

```ruby
gem "mecha_authorize"
```

Or if developing locally:

```ruby
gem "mecha_authorize", path: "~/code/mecha_authorize"
```

And then execute:

```bash
bundle install
```

## Usage

### 1. Define `config/mecha_authorize.yml`

Declare your application routes and role permissions in `config/mecha_authorize.yml`. Any route not matching an entry in this file is denied by default (404).

```yaml
debug_colorization:
  public: :green
  admin: :light_red
  user_ui: :light_purple
  user_api: :light_cyan
  none: :dark_grey

routes:
  - route_pattern: "/"
    verb: "GET"
    public: true
    admin: false
    user_ui: false
    user_api: false

  - route_pattern: "/home"
    verb: "GET"
    public: false
    admin: true
    user_ui: true
    user_api: false

  - route_pattern: "/admin/*"
    verb: "*"
    public: false
    admin: true
    user_ui: false
    user_api: false

  - route_pattern: "/api/v1/items/:id"
    verbs: ["GET", "PATCH", "DELETE"]
    public: false
    admin: false
    user_ui: false
    user_api: true
```

### 2. Configure the Initializer

Create `config/initializers/mecha_authorize.rb` to define role resolvers and include the controller concern:

```ruby
# config/initializers/mecha_authorize.rb
require "mecha_authorize"

MechaAuthorize.configure do |config|
  config.config_path = Rails.root.join("config/mecha_authorize.yml")

  config.define_role :public do |_user, _request|
    true
  end

  config.define_role :admin do |user, _request|
    user&.admin? || false
  end

  config.define_role :user_ui do |user, _request|
    user&.user_permission&.user_ui? || false
  end

  config.define_role :user_api do |user, _request|
    user&.user_permission&.user_api? || false
  end

  config.on_unauthorized = ->(controller) {
    controller.head :not_found
  }
end

ActiveSupport.on_load(:action_controller_base) do
  include MechaAuthorize::Controller
end
```

### 3. Rake Tasks & Auditing

`mecha_authorize` automatically registers Rake tasks via its Railtie:

```bash
# Print all routes and their colorized authorization matrix
bin/rails mecha_authorize

# Statically audit routes for dead rules and mounted engine bypasses
bin/rails mecha_authorize:verify:static

# Run behavioral persona matrix tests
bin/rails mecha_authorize:verify:behavioral

# Run both static and behavioral verification
bin/rails mecha_authorize:verify
```

### 4. Dynamic Parallel Matrix Testing in Consuming Apps

`mecha_authorize` ships with [`MechaAuthorize::MatrixTest`](lib/mecha_authorize/matrix_test.rb), which dynamically generates an individual Minitest test method per route so that Minitest's parallel worker pool executes route probes across all CPU cores.

In your consuming Rails application's `test/test_helper.rb`, configure the persona callbacks and require the matrix test:

```ruby
MechaAuthorize.configuration.configure_test_matrix(
  setup: -> {
    # Set up test users / tokens for each role
  },
  teardown: -> {
    # Optional teardown logic
  },
  personas: -> {
    {
      anonymous: ->(session) { session.reset!; {} },
      admin: ->(session) { login_as(session, @admin_user); {} },
      user_ui: ->(session) { login_as(session, @ui_user); {} },
      user_api: ->(_session) { { "Authorization" => "Bearer #{@api_jwt}" } },
      restricted: ->(session) { login_as(session, @restricted_user); {} }
    }
  }
)

require "mecha_authorize/matrix_test" unless ENV["MECHA_MATRIX_STANDALONE"] == "1"
```

## Running Tests

To run the gem's standalone test suite:

```bash
bundle exec rake test
```

## License

Copyright 2026 Jeff Lunt. Released under the [MIT License](LICENSE).
