# Knowledge Base Update Log

## 2026-10-15
* **Creation**: Initialized the Open Knowledge Format (`.okf`) knowledge base for `mecha_authorize` v0.1.0 ([index.md](index.md), [README.md](README.md), [architecture/index.md](architecture/index.md)).
* **Update**: Documented the three-pillar route authorization architecture: YAML route registry & matcher (`MechaAuthorize::Matcher`), controller concern with `HTTP 251` probe short-circuiting (`MechaAuthorize::Controller`), static route parity & mounted engine auditor (`MechaAuthorize::Auditor::Static`), and behavioral persona matrix prober (`MechaAuthorize::Auditor::Prober`, `MechaAuthorize::MatrixTest`).
* **Update**: Added repository [`.gitignore`](../.gitignore) covering built `.gem` artifacts, `/pkg/`, `/tmp/`, Bundler directories, coverage/docs, REPL history, `.env*` files, and macOS/editor temporary files.
