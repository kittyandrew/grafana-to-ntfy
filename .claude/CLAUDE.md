# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Rust webhook server bridging Grafana alerting and Prometheus Alertmanager to [ntfy.sh](https://ntfy.sh) push notifications. Uses the Rocket web framework.

## Build & Development

This is a NixOS-managed project with a `flake.nix`. Enter the dev shell before working:

```bash
nix develop
```

Standard Cargo commands inside the dev shell:

```bash
cargo build
cargo run          # starts server on 0.0.0.0:8080 (configured in Rocket.toml)
cargo clippy
cargo fmt --check
```

### Linting & Formatting

Run these before committing — they must pass (CI enforces them via `lint.yml`):

```bash
cargo fmt --check                            # Rust formatting (max_width = 131, see rustfmt.toml)
cargo clippy -- -D warnings                  # Rust lints (warnings are errors)
alejandra --check .                          # Nix formatting
deadnix --fail --no-lambda-pattern-names .   # unused Nix code
```

### Integration Tests

There are no unit tests. All testing is NixOS VM-based integration tests that spin up real Grafana/Prometheus/Alertmanager + ntfy.sh instances:

```bash
nix flake check -L              # run all checks (stops at first failure)
nix flake check -L --show-trace # with full trace on failure
```

To run a single check (useful when debugging a specific version):

```bash
nix build .#checks.x86_64-linux.grafana-base-test-unstable -L --show-trace
```

To run all checks in parallel (continues past failures, unlike `nix flake check`):

```bash
nix build --keep-going --rebuild -L \
  $(nix flake show --json 2>/dev/null | jq -r '.checks["x86_64-linux"] | keys[] | ".#checks.x86_64-linux.\(.)"') \
  > test-results.log 2>&1
```

Add `--show-trace` for full Nix stack traces on evaluation errors. The `--rebuild` flag forces re-execution even when results are cached.

**Analyzing test results:** The log file can be several MB. Don't read it into the main context. Dispatch a subagent to analyze it — it can afford to grep for errors, read the last few hundred lines, read sections around failures, and extract per-check pass/fail status. It should return a concise summary with version numbers, pass/fail per check, and relevant error snippets for any failures.

**Pitfalls:**
- New files in `tests/` must be `git add`ed before `nix build` can see them — flakes only read tracked files.
- `nix flake check` stops at the first evaluation error — use `nix build --keep-going` (above) to see all failures at once.

Tests are defined in `tests/` using NixOS test framework. The check matrix is defined in the `checks` attribute of `flake.nix` — check there for the current list of tested nixpkgs versions and their corresponding Grafana/Prometheus versions. The test client (`tests/lib/tester.py`) connects to ntfy via WebSocket and verifies that alerts flow end-to-end.

### Docker

The Docker image is built with Nix (`pkgs.dockerTools.buildLayeredImage`), not a Dockerfile:

```bash
nix build .#docker          # produces ./result (image tarball for the current system)
docker load < result         # loads into local Docker daemon
```

The flake produces Docker images for both x86_64-linux and aarch64-linux. `nix build .#docker` builds for the current system; to target a specific architecture: `nix build .#packages.aarch64-linux.docker`.

The image is a minimal Nix-built image with only the binary, CA certificates, curl, and a healthcheck script. Rocket config is set via env vars in the image (`ROCKET_PORT`, `ROCKET_ADDRESS`).

## Architecture

Three source files in `src/`:

- **`main.rs`** — Rocket server with two routes: `GET /health` (health check) and `POST /` (webhook handler). Loads config from env vars via `LazyLock`. Both routes return 503 when `NTFY_URL` is unset (server stays running but reports unhealthy). The webhook handler deserializes the incoming alert, maps status to emoji tags, extracts priority from labels, and POSTs to ntfy.sh via `reqwest`. Auth is optional — when `BAUTH_USER`/`BAUTH_PASS` are unset, the endpoint is open.
- **`data.rs`** — `Notification` and `Labels` structs for deserializing Grafana/Alertmanager webhook payloads. Handles both Grafana (`status`) and legacy (`state`) fields, with `title` defaulting to `"Alertmanager"` for Prometheus payloads.
- **`bauth.rs`** — Rocket request guard implementing Basic Auth. Decodes the `Authorization` header and extracts credentials. Forwards when the header is missing or the auth scheme is non-Basic; returns Error (400) for malformed credentials (bad base64, invalid UTF-8, missing colon). The `Option<BAuth>` wrapper in the handler collapses both outcomes into `None`.

### Data Flow

```
Grafana/Alertmanager → POST / → Optional BAuth guard → Deserialize Notification
  → Map status to emoji (alerting/firing → ⚠️, ok/resolved → ✅)
  → Extract priority from labels
  → POST to NTFY_URL with X-Tags, X-Title, X-Priority, X-Markdown headers
```

### Environment Variables

Configured via `.env` file. See `.env.sample` for the canonical list with descriptions — keep it up to date when adding or removing environment variables.

## CI

- **`lint.yml`** — Runs `cargo fmt --check`, `cargo clippy -- -D warnings`, `alejandra --check`, and `deadnix --fail` on push/PR. Fast — no VMs or heavy builds.
- **`flake-checks.yml`** — Dynamically discovers all flake checks via `nix flake show --json` and runs each as a separate GitHub Actions matrix job on push/PR. Uses `fail-fast: false` so all checks run independently — adding a new check to `flake.nix` automatically adds it to CI. Both jobs use `DeterminateSystems/magic-nix-cache-action` to cache the Nix store between runs.
- **`build.yml`** — Multi-arch Docker image push to Docker Hub. Three-job pipeline: `verify` (confirms both lint and flake-checks succeeded for the triggering commit, extracts version) → `push-arch` (matrix of amd64/arm64, builds natively on `ubuntu-latest` and `ubuntu-24.04-arm` via `nix build .#packages.<system>.docker`, pushes arch-specific tags) → `manifest` (creates multi-arch manifests for `latest`, version, and git SHA tags). Gated on both upstream workflows via `workflow_run`. Only runs on master.

### Local CI Testing

The dev shell includes `act` for testing GitHub Actions workflows locally:

```bash
act -j discover push > ci-test.log 2>&1
```

This validates the workflow YAML syntax, runs `nix flake show --json | jq` inside an act container, and confirms all flake checks are discovered correctly. The dynamic matrix (`fromJson`) and `workflow_run` trigger are not supported by `act` — those are validated by the underlying commands already documented above (nix build for checks, nix build .#docker for the image).

## Nixpkgs

This project is packaged in [nixpkgs](https://github.com/NixOS/nixpkgs) and maintained upstream by kittyandrew. A shallow clone of nixpkgs should live at `~/dev/nixos/nixpkgs/` — if it doesn't exist, clone it with `git clone --depth 1 https://github.com/NixOS/nixpkgs.git ~/dev/nixos/nixpkgs`. Relevant files:

- **Package:** `pkgs/by-name/gr/grafana-to-ntfy/package.nix`
- **NixOS module:** `nixos/modules/services/monitoring/grafana-to-ntfy.nix`
- **NixOS test:** `nixos/tests/grafana-to-ntfy.nix` (wired in `nixos/tests/all-tests.nix`)
- **Contributor guides:** `CONTRIBUTING.md`, `pkgs/README.md`, `doc/languages-frameworks/rust.section.md`

Routine version bumps (new `tag`, `hash`, `cargoHash`) are handled automatically by `nix-update-script` — the nixpkgs bot infrastructure creates PRs for these, so they just need kittyandrew's review and approval upstream. Manual nixpkgs work is only needed when something significant changes: new env vars that should become module options, module bug fixes, test updates, or structural changes. Remind kittyandrew to check for and approve pending automated PRs after releases.
