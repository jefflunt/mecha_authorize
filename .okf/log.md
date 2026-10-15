# Directory Update Log

## 2026-10-15
* **Update**: Bumped `MechaAuthorize::VERSION` to `0.1.1` in `lib/mecha_authorize/version.rb` and updated [MechaAuthorize Overview](/overview.md).
* **Update**: Aligned `.okf/` bundle strictly with the OKF v0.2 specification (§3.1 reserved filenames, §4.1 required `type` frontmatter, §5 provenance `sources` with footnote attributions and `generated`/`verified` actors, §8 frontmatter-free subdirectory `index.md`, and §12 root `okf_version: "0.2"`).
* **Creation**: Added [MechaAuthorize Overview](/overview.md), [Route Matcher & Runtime Controller Gate](/architecture/route-matcher-and-controller.md), and [Static Route Auditor & Behavioral Persona Prober](/architecture/static-auditor-and-behavioral-prober.md).
* **Update**: Added repository `.gitignore` covering built `.gem` packages, `/pkg/`, `/tmp/`, Bundler and rbenv files, coverage/docs, REPL history, `.env*` files, and macOS/editor temporary files.
