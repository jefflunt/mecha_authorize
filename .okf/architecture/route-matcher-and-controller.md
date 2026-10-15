---
type: Architecture
title: Route Matcher & Runtime Controller Gate
description: YAML schema validation, route matching precedence, role resolution, and HTTP 251 probe short-circuiting.
tags: [architecture, matcher, controller, yaml, authorization]
status: stable
generated: { by: antigravity/gemini-4-argon, at: 2026-10-15T23:20:00Z }
verified: { by: process:rake-test, at: 2026-10-15T23:20:00Z }
sources:
  - id: configuration-rb
    resource: ../../lib/mecha_authorize/configuration.rb
    title: MechaAuthorize::Configuration
    author: human:jefflunt
    last_modified: 2026-10-15T23:00:00Z
  - id: matcher-rb
    resource: ../../lib/mecha_authorize/matcher.rb
    title: MechaAuthorize::Matcher
    author: human:jefflunt
    last_modified: 2026-10-15T23:00:00Z
  - id: controller-rb
    resource: ../../lib/mecha_authorize/controller.rb
    title: MechaAuthorize::Controller
    author: human:jefflunt
    last_modified: 2026-10-15T23:00:00Z
---

# Configuration & Role Resolution

`MechaAuthorize::Configuration` manages runtime settings and role resolvers (`(user, request) -> Boolean`):[^configuration-rb]

- `config_path`: Defaults to `Rails.root.join("config/mecha_authorize.yml")` in Rails or `"config/mecha_authorize.yml"`. Also accepts an in-memory Hash for unit testing.
- `probe_header`: Defaults to `"X-Mecha-Authorize-Probe"`.
- `probe_status`: Defaults to `251` (`251 Verified`).
- `on_unauthorized`: Lambda invoked with the controller instance when authorization fails (defaults to `->(controller) { controller.send(:render_404) }`).
- `define_role(name, &block)`: Registers a role symbol and its predicate block.

# Schema

Every entry in `config/mecha_authorize.yml` under `routes:` is validated strictly on load by `MechaAuthorize::Matcher`:[^matcher-rb]

| Field | Type | Constraints |
|-------|------|-------------|
| `route_pattern` | `String` | Non-empty string beginning with `/`. |
| `verb` / `verbs` | `String` / `Array<String>` | Must be in `GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS, *`. |
| `<role_name>` | `Boolean` | Explicit `true` or `false` required for every configured role (`public`, `admin`, `user_ui`, `user_api`, etc.). |

# Route Matching Precedence

`MechaAuthorize::Matcher#match(verb, path, route_uri_pattern)` evaluates incoming requests in deterministic order, stripping trailing `(.:format)` suffixes:[^matcher-rb]

1. **Exact `[verb, clean_path]`** in `@indexed_routes` (with automatic `HEAD -> GET` fallback).
2. **Wildcard verb `["*", clean_path]`** in `@indexed_routes`.
3. **Path wildcards** in `@wildcard_routes` using `File.fnmatch(pattern, clean_path)` and prefix matching when `pattern` ends with `/*`.
4. **Rails dynamic route URI pattern** (`request.route_uri_pattern`, e.g., `/emails/:id/thread`).
5. **Parameterized regex fallback** (`match_by_pattern_regex`), converting `:param` segments into `[^/]+` and `*` into `.*`.
6. **Closed-by-default**: Returns `nil` when no rule matches.

# Runtime Controller Gate

`MechaAuthorize::Controller` is an `ActiveSupport::Concern` that installs `before_action :authorize_route!`:[^controller-rb]

1. **Rule Lookup**: Resolves the matching rule from controller-specific `authorization_routes` (if overridden in isolated controller tests) or `MechaAuthorize.matcher`.
2. **Closed-by-Default Denial**: If `rule.nil?`, calls `render_unauthorized` and halts.
3. **Public Route Bypass**: If `rule[:public]` is `true`, halts with `head probe_status` (`251`) on probe requests or allows the request through.
4. **Authentication Gate**: Requires `logged_in?` (`!current_user.nil?`); otherwise calls `render_unauthorized`.
5. **Role Evaluation**: Iterates through `MechaAuthorize.configuration.roles` (excluding `:public`) and checks whether any role enabled on `rule` returns truthy for `resolver.call(current_user, request)`.
6. **Sentinel Probe Short-Circuit**: When `X-Mecha-Authorize-Probe` is `"1"` or `"true"`, responds immediately with `head MechaAuthorize.configuration.probe_status` (`251`) before executing the controller action body.

See [Static Route Auditor & Behavioral Persona Prober](/architecture/static-auditor-and-behavioral-prober.md) for how static and behavioral verification exercise this gate.

[^configuration-rb]: MechaAuthorize::Configuration
[^matcher-rb]: MechaAuthorize::Matcher
[^controller-rb]: MechaAuthorize::Controller
