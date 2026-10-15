---
type: Architecture
title: Static Route Auditor & Behavioral Persona Prober
description: Static route parity verification, mounted engine bypass detection, and parallel Minitest persona probing.
tags: [architecture, auditor, prober, minitest, rails-engines, rake]
status: stable
generated: { by: antigravity/gemini-4-argon, at: 2026-10-15T23:20:00Z }
verified: { by: process:rake-test, at: 2026-10-15T23:20:00Z }
sources:
  - id: static-rb
    resource: ../../lib/mecha_authorize/auditor/static.rb
    title: MechaAuthorize::Auditor::Static
    author: human:jefflunt
    last_modified: 2026-10-15T23:00:00Z
  - id: prober-rb
    resource: ../../lib/mecha_authorize/auditor/prober.rb
    title: MechaAuthorize::Auditor::Prober
    author: human:jefflunt
    last_modified: 2026-10-15T23:00:00Z
  - id: matrix-test-rb
    resource: ../../lib/mecha_authorize/matrix_test.rb
    title: MechaAuthorize::MatrixTest
    author: human:jefflunt
    last_modified: 2026-10-15T23:00:00Z
  - id: rake-tasks
    resource: ../../lib/tasks/mecha_authorize.rake
    title: MechaAuthorize Rake Tasks
    author: human:jefflunt
    last_modified: 2026-10-15T23:00:00Z
---

# Static Route & Mounted Engine Auditor

`MechaAuthorize::Auditor::Static#audit` inspects `Rails.application.routes` (and all mounted engine route sets) against [the route matcher](/architecture/route-matcher-and-controller.md) without issuing HTTP requests:[^static-rb]

- **Mapped vs. Unmapped Routes**: Wraps each non-internal route in `ActionDispatch::Routing::RouteWrapper`, expanding mounted engines under their mount prefix, and checks `matcher.match_route_spec(verb, path)`. Unmapped routes are reported as defaulting to closed-by-default `404`.
- **Dead / Stale Rule Detection**: Scans `@matcher.all_rules` for any non-wildcard YAML entry that does not match at least one live Rails route (including bidirectional parameterized segment regex matching).
- **Mounted Engine Bypass Detection**: Checks every mounted engine (`r.app.engine?`) by resolving `"#{engine_name}::ApplicationController"` and verifying that it either inherits from `::ApplicationController` or includes `MechaAuthorize::Controller`.
- **Audit Verdict**: `Result#success?` returns `true` only when `dead_rules.empty? && engine_warnings.empty?`.

# Behavioral Persona Matrix Prober

`MechaAuthorize::Auditor::Prober` verifies runtime enforcement by dispatching integration requests across every route for each test persona:[^prober-rb]

1. **Route Collection & Parameter Substitution**: Collects all unique `[verb, path]` pairs from the application and mounted engines, substituting dynamic segments via `DEFAULT_PARAM_SUBSTITUTIONS` (`:id -> "1"`, `:provider -> "google_oauth2"`, `:filename -> "test.png"`, and fallback `:[a-zA-Z_]+ -> "1"`).
2. **Expected Status Matrix (`calculate_expected_status`)**:
   - Unmapped route (`rule.nil?`): expects `404`.
   - Public route (`rule[:public]`): expects `MechaAuthorize.configuration.probe_status` (`251`) for all personas.
   - Non-public routes by persona:
     - `:anonymous`: `[400, 401, 404]` on `/api/*`, `404` otherwise.
     - `:admin`: `251` if `rule[:admin]`, else `[400, 401, 403, 404]` on `/api/*` or `404` on UI routes.
     - `:user_ui`: `251` if `rule[:user_ui] && !is_api`, else `[400, 401, 403, 404]` on `/api/*` or `404` on UI routes.
     - `:user_api`: `251` if `rule[:user_api]`, else `[400, 401, 403, 404]` on `/api/*` or `404` on UI routes.
     - `:restricted`: `[400, 401, 403, 404]` on `/api/*`, `404` otherwise.
3. **Probe Execution**: Dispatches the HTTP request with header `X-Mecha-Authorize-Probe: 1` merged with any persona-supplied headers (such as `Authorization: Bearer ...`) and records any status mismatch as a `ProbeFailure`.

# Parallel Minitest Matrix & Rake Tasks

- **`MechaAuthorize::MatrixTest`**: Subclasses `ActionDispatch::IntegrationTest` and invokes `define_route_matrix_tests!` at class load time to generate an individual test method per `[verb, path]`, allowing Minitest's parallel worker pool to distribute route probing across CPU cores.[^matrix-test-rb]
- **Rake Tasks (`lib/tasks/mecha_authorize.rake`)**:[^rake-tasks]
  - `bin/rails mecha_authorize`: Prints all application and engine routes with colorized `PAUX` (`Public`, `Admin`, `User UI`, `User API`) access indicators via `tiny_color`.
  - `bin/rails mecha_authorize:verify:static`: Runs `MechaAuthorize::Auditor::Static` and aborts on dead rules or engine bypasses.
  - `bin/rails mecha_authorize:verify:behavioral`: Executes `MechaAuthorize::MatrixTest` with `MECHA_MATRIX_STANDALONE=1`.
  - `bin/rails mecha_authorize:verify`: Runs both `verify:static` and `verify:behavioral`.

[^static-rb]: MechaAuthorize::Auditor::Static
[^prober-rb]: MechaAuthorize::Auditor::Prober
[^matrix-test-rb]: MechaAuthorize::MatrixTest
[^rake-tasks]: MechaAuthorize Rake Tasks
