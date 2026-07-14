# Evaluations

## Structural Linting

Deterministic checks on both Claude Code and Codex SKILL.md mirrors — no API calls, runs instantly.

    ./evals/lint-skills.sh
    ./evals/lint-skills-test.sh

Validates:
- All skill directories exist with SKILL.md files
- Platform-appropriate frontmatter fields
- Cross-references between skills point to existing files
- Viewport values (1280x800 desktop, 768x1024 tablet, 390x844 mobile) are consistent
- Screenote and Browser Use tool names, ledger fields, caps, and trust-boundary wording are present on both surfaces
- CLI snapshot manifest, exact binary identity, unchanged-resume, terminal event, and 100-image sharding contracts are present on both surfaces
- Claude Code and Codex skill bodies plus bundled snapshot references remain behaviorally identical after documented platform syntax is normalized
- The Browser Use and MCP dependency pins match the shipped `.mcp.json`
- Removing a required Browser Use or Screenote CLI contract from either mirror makes lint fail

Run on every PR that touches `skills/**/*.md`, `codex-skills/**/*.md`, `.mcp.json`, or the adapter.

## Browser Use MCP Smoke

Live smoke test for the bundled Browser Use MCP server:

    bash evals/browser-use-mcp-smoke.sh

Validates the exact command, arguments, working directory, and environment from `.mcp.json`, then checks:

- Browser Use `0.13.4` plus the expected direct-control tools start
- The adapter exposes exact schemas for viewport sizing, numeric page metrics, exact scrolling, and 5000 px bounded file capture
- Desktop, tablet, and mobile dimensions are applied and verified at runtime
- A PNG is written through `browser_screenshot_to_file`
- Browser sessions are closed after the smoke

The smoke runs in CI and should also be run locally before changing browser-use capture behavior. It starts a local MCP subprocess and may install Python packages through `uv`.

## Screenote CLI Contract Smoke

Hermetic contract test for the separately installed upload CLI:

    bash evals/screenote-cli-smoke.sh

Validates the installed Go module revision, manifest/wait flags, local manifest preflight, and stable JSON errors. A bounded localhost fixture then forces a partial image-upload failure and proves an unchanged rerun resumes the same manifest identity, skips an attached image, and emits exactly one terminal `snapshot_ready` event with a review URL. The smoke never contacts Screenote.

## Trigger Eval Dataset

`trigger-eval-set.json` contains 14 test queries mapping to expected skill triggers. This dataset is ready for use when Claude Code provides proper skill trigger testing support (e.g., a `--dry-run` flag, skill match metadata in output, or `cc-plugin-eval` maturity).

### Why trigger evals are deferred

Tested `claude -p --output-format json` on 2025-03-10. Findings:
- Output is a flat result object — no message-level tool_use events exposed
- `--allowedTools "Skill"` does not restrict tool usage as expected
- Single query cost ~$0.38 (Opus), not viable for a 14-query eval suite
- Skills don't trigger as discrete `Skill` tool calls in headless mode

## CI Notes

- Lint evals: run on every PR (free, instant)
- Screenote CLI contract smoke: run on every PR after installing the pinned CLI revision
- Browser Use adapter smoke: run on every PR with a pinned uv runtime
- Trigger evals: revisit when tooling improves
