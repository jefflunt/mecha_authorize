---
type: Overview
title: MechaAuthorize Overview
description: Mission, directory layout, public API, and three-pillar route authorization model for Ruby on Rails.
resource: https://github.com/jefflunt/mecha_authorize
tags: [rails, security, authorization, overview, rubygem]
status: stable
generated: { by: antigravity/gemini-4-argon, at: 2026-10-15T23:20:00Z }
verified: { by: process:rake-test, at: 2026-10-15T23:20:00Z }
sources:
  - id: gemspec
    resource: ../mecha_authorize.gemspec
    title: MechaAuthorize Gem Specification
    author: human:jefflunt
    last_modified: 2026-10-15T23:00:00Z
  - id: entrypoint
    resource: ../lib/mecha_authorize.rb
    title: MechaAuthorize Top-Level Module
    author: human:jefflunt
    last_modified: 2026-10-15T23:00:00Z
  - id: readme
    resource: ../README.md
    title: MechaAuthorize README
    author: human:jefflunt
    last_modified: 2026-10-15T23:00:00Z
---

# Mission

`mecha_authorize` enforces closed-by-default route authorization for Ruby on Rails applications (>= Ruby 3.2, ActiveSupport/ActionPack >= 7.0) from a single YAML registry (`config/mecha_authorize.yml`).[^gemspec] Every incoming HTTP request is evaluated against an explicit route policy before any controller action runs.[^readme]

It implements the three-pillar **MechaRuby** verification model:

1. **Central Registry**: [Route Matcher & Runtime Controller Gate](/architecture/route-matcher-and-controller.md) maps HTTP verbs and route patterns to explicit boolean role flags (`public`, `admin`, `user_ui`, `user_api`, or custom roles). Unmapped routes and unpermitted verbs return `404 Not Found` by default.
2. **Static Auditor**: [Static Route Auditor & Behavioral Persona Prober](/architecture/static-auditor-and-behavioral-prober.md) inspects `Rails.application.routes` and mounted engines against `config/mecha_authorize.yml` to identify unmapped routes, fail CI on dead/stale YAML rules, and detect mounted Rails engines whose base controllers bypass `MechaAuthorize::Controller`.
3. **Behavioral Prober**: [Static Route Auditor & Behavioral Persona Prober](/architecture/static-auditor-and-behavioral-prober.md) dispatches real HTTP integration requests (`X-Mecha-Authorize-Probe: 1`) across every route for every configured persona (`anonymous`, `admin`, `user_ui`, `user_api`, `restricted`), verifying that authorized personas receive the sentinel `251 Verified` status and unauthorized personas receive `404` (or `400`/`401`/`403`/`404` on `/api/*`).

# Schema

| Path | Component | Responsibility |
|------|-----------|----------------|
| `lib/mecha_authorize.rb` | `MechaAuthorize` | Top-level singleton configuration (`configure`, `matcher`, `reload!`, `reset_configuration!`).[^entrypoint] |
| `lib/mecha_authorize/version.rb` | `MechaAuthorize::VERSION` | Gem semantic version (`0.1.0`). |
| `lib/mecha_authorize/configuration.rb` | `MechaAuthorize::Configuration` | Stores `config_path`, `probe_header`, `probe_status`, `debug_colorization`, `on_unauthorized`, role resolvers, and test matrix callbacks. |
| `lib/mecha_authorize/matcher.rb` | `MechaAuthorize::Matcher` | Validates `mecha_authorize.yml` and resolves `(verb, path, route_uri_pattern)` to role permission hashes. |
| `lib/mecha_authorize/controller.rb` | `MechaAuthorize::Controller` | `ActiveSupport::Concern` registering `before_action :authorize_route!` and `HTTP 251` probe short-circuiting. |
| `lib/mecha_authorize/auditor/static.rb` | `MechaAuthorize::Auditor::Static` | Static route parity, dead rule detection, and mounted engine inheritance verification. |
| `lib/mecha_authorize/auditor/prober.rb` | `MechaAuthorize::Auditor::Prober` | Parameter substitution and multi-persona integration probing across application and engine routes. |
| `lib/mecha_authorize/matrix_test.rb` | `MechaAuthorize::MatrixTest` | Dynamic per-route Minitest generator for parallel behavioral verification. |
| `lib/mecha_authorize/railtie.rb` | `MechaAuthorize::Railtie` | Loads Rake tasks (`mecha_authorize`, `mecha_authorize:verify`, `mecha_authorize:verify:static`, `mecha_authorize:verify:behavioral`). |

# Examples

```ruby
MechaAuthorize.configure do |config|
  config.config_path = Rails.root.join("config/mecha_authorize.yml")
  config.define_role(:public)   { |_user, _req| true }
  config.define_role(:admin)    { |user, _req| user&.admin? || false }
  config.define_role(:user_ui)  { |user, _req| user&.user_permission&.user_ui? || false }
  config.define_role(:user_api) { |user, _req| user&.user_permission&.user_api? || false }
  config.on_unauthorized = ->(controller) { controller.head :not_found }
end

ActiveSupport.on_load(:action_controller_base) do
  include MechaAuthorize::Controller
end
```

[^gemspec]: MechaAuthorize Gem Specification
[^entrypoint]: MechaAuthorize Top-Level Module
[^readme]: MechaAuthorize README
