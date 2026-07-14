#!/usr/bin/env python3
"""Normalize the documented Claude Code/Codex skill mirror differences."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


COMMAND_NAMES = ("screenote", "snapshot", "feedback")


def normalize_frontmatter(lines: list[str], platform: str) -> list[str]:
    if not lines or lines[0] != "---":
        return lines

    try:
        end = lines.index("---", 1)
    except ValueError:
        return lines

    frontmatter = lines[1:end]
    if platform == "claude":
        frontmatter = [line for line in frontmatter if line != "user_invocable: true"]
    else:
        normalized: list[str] = []
        for line in frontmatter:
            if line == "metadata:":
                continue
            if line.startswith("  argument:"):
                line = line[2:]
            normalized.append(line)
        frontmatter = normalized

    return ["---", *frontmatter, "---", *lines[end + 1 :]]


def normalize_commands(text: str) -> str:
    names = "|".join(COMMAND_NAMES)
    replacements = (
        (rf"\$screenote:({names})\b", r"@screenote-command:\1"),
        (rf"/screenote:({names})\b", r"@screenote-command:\1"),
        (rf"(?<![A-Za-z0-9_.-])/({names})(?![A-Za-z0-9_:-])", r"@screenote-command:\1"),
    )
    for pattern, replacement in replacements:
        text = re.sub(pattern, replacement, text)
    return text


def normalize(path: Path, platform: str) -> str:
    text = path.read_text(encoding="utf-8")
    trailing_newline = text.endswith("\n")
    lines = normalize_frontmatter(text.splitlines(), platform)
    text = "\n".join(lines)

    text = text.replace("Claude Code", "AGENT_HOST")
    text = text.replace("Codex", "AGENT_HOST")
    text = text.replace("codex-skills/", "SKILL_ROOT/")
    text = text.replace("skills/", "SKILL_ROOT/")
    text = normalize_commands(text)
    text = re.sub(
        r"(`@screenote-command:[a-z]+`) \(or `@screenote-command:\w+`\)",
        r"\1",
        text,
    )

    if trailing_newline:
        text += "\n"
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=("claude", "codex"))
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    print(normalize(args.path, args.platform), end="")


if __name__ == "__main__":
    main()
