#!/bin/bash
# Regression test: Browser Use or Screenote CLI surface drift must make lint fail.

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d /tmp/screenote-lint-test-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

make_case() {
  local destination=$1
  mkdir -p "$destination/evals" "$destination/mcp"
  cp -R "$ROOT_DIR/skills" "$ROOT_DIR/codex-skills" "$destination/"
  cp "$ROOT_DIR/.mcp.json" "$destination/.mcp.json"
  cp "$ROOT_DIR/README.md" "$destination/README.md"
  cp "$ROOT_DIR/evals/lint-skills.sh" "$destination/evals/lint-skills.sh"
  cp "$ROOT_DIR/evals/normalize-skill-mirror.py" "$destination/evals/normalize-skill-mirror.py"
  cp "$ROOT_DIR/evals/browser-use-mcp-smoke.sh" "$destination/evals/browser-use-mcp-smoke.sh"
  cp "$ROOT_DIR/evals/screenote-cli-smoke.sh" "$destination/evals/screenote-cli-smoke.sh"
  chmod +x "$destination/evals/screenote-cli-smoke.sh"
  cp "$ROOT_DIR/mcp/screenote_browser_use_mcp.py" "$destination/mcp/screenote_browser_use_mcp.py"
}

expect_lint_failure() {
  local case_dir=$1
  local failure_message=$2
  if (cd "$case_dir" && bash evals/lint-skills.sh >/dev/null 2>&1); then
    echo "FAIL: $failure_message" >&2
    exit 1
  fi
}

for root in skills codex-skills; do
  case_dir="$TMP_DIR/$root-browser"
  make_case "$case_dir"
  target="$case_dir/$root/screenote/SKILL.md"
  awk '{gsub(/browser_screenshot_to_file/, "browser_screenshot_file_missing"); print}' \
    "$target" > "$target.tmp"
  mv "$target.tmp" "$target"

  expect_lint_failure "$case_dir" "lint accepted missing browser_screenshot_to_file in $root"
  echo "PASS: lint rejects Browser Use drift in $root"

  case_dir="$TMP_DIR/$root-cli"
  make_case "$case_dir"
  target="$case_dir/$root/screenote/SKILL.md"
  awk '{gsub(/screenote --project/, "screenote project contract missing"); print}' \
    "$target" > "$target.tmp"
  mv "$target.tmp" "$target"

  expect_lint_failure "$case_dir" "lint accepted missing Screenote CLI project invocation in $root"
  echo "PASS: lint rejects Screenote CLI drift in $root"
done

case_dir="$TMP_DIR/mirror-retry-semantics"
make_case "$case_dir"
target="$case_dir/codex-skills/screenote/SKILL.md"
sed 's/retry \*\*once\*\* with the exact same manifest/retry **twice** with the exact same manifest/' \
  "$target" > "$target.tmp"
mv "$target.tmp" "$target"

expect_lint_failure "$case_dir" "lint accepted retry semantic drift in one skill mirror"
echo "PASS: lint rejects retry semantic drift in one skill mirror"

case_dir="$TMP_DIR/reference-retry-semantics"
make_case "$case_dir"
target="$case_dir/codex-skills/snapshot/references/capture-upload-contract.md"
sed 's/On failure, retry once with the exact same manifest bytes/On failure, retry twice with the exact same manifest bytes/' \
  "$target" > "$target.tmp"
mv "$target.tmp" "$target"

expect_lint_failure "$case_dir" "lint accepted retry semantic drift in one snapshot reference mirror"
echo "PASS: lint rejects retry semantic drift in one snapshot reference mirror"

case_dir="$TMP_DIR/terminal-state-semantics"
make_case "$case_dir"
for target in \
  "$case_dir/skills/screenote/SKILL.md" \
  "$case_dir/codex-skills/screenote/SKILL.md"; do
  sed 's/state="ready"/state="prepared"/' "$target" > "$target.tmp"
  mv "$target.tmp" "$target"
done

expect_lint_failure "$case_dir" "lint accepted terminal state semantic drift in both skill mirrors"
echo "PASS: lint rejects terminal state semantic drift in both skill mirrors"

case_dir="$TMP_DIR/runtime-module-version"
make_case "$case_dir"
target="$case_dir/codex-skills/screenote/SKILL.md"
sed 's/v0\.0\.0-20260713190415-e960bf5cd404/v0.0.0-20260713190415-000000000000/' \
  "$target" > "$target.tmp"
mv "$target.tmp" "$target"

expect_lint_failure "$case_dir" "lint accepted mismatched Screenote CLI runtime module version"
echo "PASS: lint rejects mismatched Screenote CLI runtime module version"
