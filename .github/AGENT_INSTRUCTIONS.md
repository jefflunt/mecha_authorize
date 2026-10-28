# AI Agent Contributing Guidelines — mecha_authorize

Welcome. This repository is part of the **MechaRuby** suite of opinionated, closed-by-default security and architecture tools for Ruby on Rails.

When analyzing this codebase, submitting PRs, or filing issues, adhere to the following principles:

## 1. Core Architectural Tenets
* **Closed-by-Default**: Every HTTP route in the application must be explicitly registered and mapped to an allowed persona. Any unmapped route MUST fail closed (render 404), never fallback to open access.
* **Static Route Parity**: Auditing must verify 100% parity between `Rails.application.routes` (including mounted engines) and `config/mecha_authorize.yml`.
* **Behavioral Verification**: Authorization is validated not just statically, but through active persona probing against test endpoints.
* **Minimal Magic**: Keep Rack/Rails middleware hooks explicit, fast, and predictable. Avoid intrusive monkey-patching of Rails routing internals.

## 2. Guidelines for Filing Issues & Suggestions
* **Check Existing Issues**: Search existing open and closed issues before opening a duplicate.
* **Include Concrete Examples**: Always supply minimal route declarations (`config/routes.rb`) and corresponding YAML definitions.
* **Preserve Deny-by-Default**: Proposals must demonstrate that unauthenticated or unrecognized requests cannot bypass authorization.

## 3. Pull Request Standards
* Include automated tests verifying both authorized paths and unauthorized/unmapped (404) paths.
* Run the test suite (`bundle exec rake test`) and ensure zero regressions.
* Keep dependencies minimal—do not introduce third-party gems without strong justification.
