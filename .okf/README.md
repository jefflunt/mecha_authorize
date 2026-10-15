# MechaAuthorize — Project Knowledge & Overview

## Mission

`mecha_authorize` enforces closed-by-default route authorization for Ruby on Rails applications from a single YAML registry (`config/mecha_authorize.yml`). Instead of scattering `before_action` callbacks across dozens of controllers where a single omission leaks an endpoint, `mecha_authorize` evaluates every incoming HTTP verb and path against an explicit route policy before any controller action runs.

It implements the three-pillar **MechaRuby** security pattern:
1. **Central Registry (`config/mecha_authorize.yml` + `MechaAuthorize::Matcher` + `MechaAuthorize::Controller`)** — Single source of truth mapping HTTP verbs and route patterns to explicit boolean role flags (`public`, `admin`, `user_ui`, `user_api`, or custom roles). Unmapped routes and unpermitted verbs return `404 Not Found` by default.
2. **Static Auditor (`MechaAuthorize::Auditor::Static`)** — Inspects `Rails.application.routes` and mounted engines against `config/mecha_authorize.yml` to identify unmapped routes, fail CI on dead/stale YAML rules, and detect mounted Rails engines whose base controllers bypass `MechaAuthorize::Controller`.
3. **Behavioral Prober (`MechaAuthorize::Auditor::Prober` + `MechaAuthorize::MatrixTest`)** — Dispatches real HTTP integration requests (`X-Mecha-Authorize-Probe: 1`) across every route for every configured persona (`anonymous`, `admin`, `user_ui`, `user_api`, `restricted`), verifying that authorized personas receive the sentinel `251 Verified` status and unauthorized personas receive `404`/`401`/`403`.

## Directory Layout

- `lib/mecha_authorize.rb` — Top-level module, configuration singleton, and matcher lifecycle (`configure`, `matcher`, `reload!`, `reset_configuration!`).
- `lib/mecha_authorize/version.rb` — Gem version constant (`MechaAuthorize::VERSION`).
- `lib/mecha_authorize/configuration.rb` — Configuration object (`config_path`, `probe_header`, `probe_status`, `debug_colorization`, `on_unauthorized`, `define_role`, `configure_test_matrix`).
- `lib/mecha_authorize/matcher.rb` — Schema validator and route matcher supporting exact `[verb, path]` lookups, `HEAD -> GET` fallback, `*` verb wildcards, `/*` path wildcards, Rails dynamic route URI patterns (`/items/:id`), and regex parameterized fallback.
- `lib/mecha_authorize/controller.rb` — `ActiveSupport::Concern` registering `before_action :authorize_route!`, role access evaluation, `on_unauthorized` callback, and probe sentinel early termination (`HTTP 251`).
- `lib/mecha_authorize/auditor/static.rb` — Static route parity and mounted engine inheritance auditor.
- `lib/mecha_authorize/auditor/prober.rb` — Behavioral route prober that substitutes route parameters and dispatches integration requests per persona.
- `lib/mecha_authorize/matrix_test.rb` — `ActionDispatch::IntegrationTest` subclass that dynamically generates a test method per route for parallel Minitest execution.
- `lib/mecha_authorize/railtie.rb` & `lib/tasks/mecha_authorize.rake` — Automatic Railtie registration for `rails mecha_authorize`, `rails mecha_authorize:verify:static`, `rails mecha_authorize:verify:behavioral`, and `rails mecha_authorize:verify`.
- `test/` — Standalone Minitest unit test suite (`bundle exec rake test`).
