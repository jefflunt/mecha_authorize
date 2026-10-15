---
type: Architecture
title: MechaAuthorize Architecture & Three-Pillar Verification
description: Detailed architecture of the YAML matcher, controller concern, static route auditor, and behavioral persona prober.
tags: [architecture, rails, security, authorization, auditing, probing]
status: stable
last_modified: "2026-10-15"
---

# MechaAuthorize Architecture

## 1. Configuration & Role Resolution (`MechaAuthorize::Configuration`)

`MechaAuthorize.configure` initializes `MechaAuthorize::Configuration` and builds `MechaAuthorize.matcher`:
- **`config_path`**: Defaults to `Rails.root.join("config/mecha_authorize.yml")` when Rails is present, or `"config/mecha_authorize.yml"`. Can also accept an in-memory Hash for isolated testing.
- **`define_role(name, &block)`**: Registers a named role symbol (e.g., `:public`, `:admin`, `:user_ui`, `:user_api`) with a block `(user, request) -> Boolean`.
- **`probe_header` & `probe_status`**: Defaults to `"X-Mecha-Authorize-Probe"` and HTTP status `251` (`251 Verified`). When a request includes `X-Mecha-Authorize-Probe: 1` (or `"true"`) and passes authorization, the controller concern halts before executing the controller action body and responds with `head 251`.
- **`on_unauthorized`**: Lambda invoked with the controller instance when a request is denied (defaults to `->(controller) { controller.send(:render_404) }`).

## 2. Route Registry & Matching Precedence (`MechaAuthorize::Matcher`)

`MechaAuthorize::Matcher` loads and validates the YAML schema on initialization:
- Every route entry must be a Hash with a non-empty `route_pattern` starting with `/`, an explicit `verb` (or `verbs` array) from `GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS, *`, and explicit `true`/`false` booleans for every registered role.
- Routes are indexed into frozen structures (`@indexed_routes` and `@wildcard_routes`).
- Incoming requests are matched in strict precedence order via `Matcher#match(verb, path, route_uri_pattern)`:
  1. **Exact `[verb, clean_path]`** (with automatic `HEAD -> GET` fallback).
  2. **Wildcard verb `["*", clean_path]`**.
  3. **Wildcard path patterns** (`@wildcard_routes` via `File.fnmatch` and prefix matching for `/*`).
  4. **Rails dynamic route URI pattern** (`request.route_uri_pattern` stripped of `(.:format)`).
  5. **Parameterized regex fallback** (converts `:param` segments to `[^/]+` and `*` to `.*`).
  6. **Default**: Returns `nil`, triggering closed-by-default rejection in the controller.

## 3. Runtime Controller Gate (`MechaAuthorize::Controller`)

Included into `ActionController::Base` (typically via `ActiveSupport.on_load(:action_controller_base)`), `MechaAuthorize::Controller` registers `before_action :authorize_route!`:
1. Extracts the request HTTP verb, path, and optional `route_uri_pattern`.
2. Evaluates against custom controller-level `authorization_routes` (if overridden in unit tests) or `MechaAuthorize.matcher`.
3. **Closed-by-default**: If no rule matches (`rule.nil?`), calls `render_unauthorized` and returns.
4. **Public bypass**: If `rule[:public]` is true, returns immediately (or renders `head probe_status` if `probe_request?`).
5. **Authentication check**: Requires `logged_in?` (`!current_user.nil?`); otherwise calls `render_unauthorized`.
6. **Role check**: Evaluates `MechaAuthorize.configuration.roles` to verify at least one non-public role permitted on `rule` resolves truthy for `(current_user, request)`.
7. **Probe short-circuit**: If `probe_request?` is true, responds with `head MechaAuthorize.configuration.probe_status` (`251`) so behavioral tests verify authorization gates without triggering database mutations or view rendering side effects.

## 4. Static Route & Engine Auditor (`MechaAuthorize::Auditor::Static`)

`MechaAuthorize::Auditor::Static#audit` inspects `Rails.application.routes` (including mounted engines) without making HTTP requests:
- **Mapped vs. Unmapped Routes**: Categorizes every non-internal Rails route and mounted engine route by checking `matcher.match_route_spec(verb, path)`.
- **Dead / Stale Rules**: Flags any non-wildcard rule in `config/mecha_authorize.yml` that does not match any existing route in the Rails application.
- **Mounted Engine Bypass Detection**: Inspects mounted engines (`r.app.engine?`) and checks whether `"#{engine_name}::ApplicationController"` either inherits from `::ApplicationController` or includes `MechaAuthorize::Controller`.
- `Result#success?` is true only when `dead_rules.empty? && engine_warnings.empty?`.

## 5. Behavioral Persona Matrix Prober (`MechaAuthorize::Auditor::Prober` & `MatrixTest`)

- `MechaAuthorize::Auditor::Prober` collects all non-internal application and engine routes, substitutes dynamic parameters (`:id -> "1"`, `:provider -> "google_oauth2"`, etc.), and iterates through each configured persona (`:anonymous`, `:admin`, `:user_ui`, `:user_api`, `:restricted`).
- Each probe dispatches the route's HTTP verb with `X-Mecha-Authorize-Probe: 1` and compares the response status against `calculate_expected_status`:
  - Authorized persona: expects sentinel `251`.
  - Unauthorized persona on UI route: expects `404`.
  - Unauthorized persona on `/api/*` route: expects `[400, 401, 403, 404]`.
- `MechaAuthorize::MatrixTest` dynamically defines a separate Minitest `test "behavioral persona matrix probe for #{verb} #{raw_path}"` per route so Minitest parallel workers distribute route probes across cores.
