# Changelog

## [1.7.0] - 2026-07-13

### Added

- A Screenote CLI contract smoke test covering the pinned binary identity, manifest preflight, partial-upload resume, attached-byte skipping, terminal review events, and the machine-readable error surface through a localhost fixture.
- Deterministic manifest sharding for full-app snapshots above the CLI's 100-image limit.
- Behavioral parity checks for Claude Code and Codex skill mirrors, including their installed snapshot resources.

### Changed

- `/screenote` and `/snapshot` now upload captured images with `screenote snapshot --manifest` instead of allocating signed upload URLs through MCP and invoking `curl`.
- Upload retries reuse the exact manifest and files so the CLI resumes the same content-bound snapshot graph.
- Screenote MCP remains responsible for project discovery/creation and feedback; CLI uploads use their own OAuth login.
- Full-app snapshots upload and compact each deterministic shard as it fills, bounding temporary disk use without splitting viewport groups.

### Fixed

- Treat only the terminal `snapshot_ready` CLI event as upload success and derive the review URL from that event.
- Keep capture and upload status pending until the CLI outcome is final, preserving exactly one route/viewport ledger record.
- Refresh cached project names from the live project ID before enforcing MCP/CLI alignment.
- Reject an upload CLI at runtime unless its Go module metadata matches the reviewed revision.

## [1.6.0] - 2026-07-13

### Added

- A pinned Browser Use adapter with exact viewport sizing, numeric-only page metrics, exact scrolling, bounded screenshot-to-file capture, and ephemeral browser profiles.
- Runtime MCP smoke coverage for desktop, tablet, and mobile dimensions plus file-backed PNG output.
- Structural lint coverage and negative drift tests for both Claude Code and Codex skill mirrors.

### Changed

- `/screenote` and `/snapshot` now use Browser Use instead of a host-provided Playwright MCP server.
- Full-page capture scrolls lazy-loaded pages with a 10-scroll traversal budget and caps output at 5000 px.

### Fixed

- Preflight browser capabilities before allocating remote Screenote upload records.
- Finalize exactly one route/viewport ledger row after capture and upload finish.
- Keep one batch ledger across all snapshot routes and close authenticated browser sessions on every exit path.
- Treat page-derived browser output as untrusted data and avoid page text during normal capture settling.
