#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

say() {
  printf '%s\n' "$1"
}

check_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    say "[ok] command available: $name"
  else
    say "[warn] command missing: $name"
  fi
}

check_env() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    say "[ok] env set: $name"
  else
    say "[warn] env missing: $name"
  fi
}

check_file() {
  local path="$1"
  if [[ -e "$path" ]]; then
    say "[ok] file exists: $path"
  else
    say "[warn] file missing: $path"
  fi
}

say "PaperDaily preflight"
say "workspace: $ROOT_DIR"
say ""

say "Commands"
check_command uv
check_command python3
check_command xcodebuild
if [[ ! -x "$ROOT_DIR/.venv/bin/python" ]]; then
  say "[warn] local virtualenv missing: .venv/bin/python"
else
  say "[ok] local virtualenv available: .venv/bin/python"
fi
say ""

say "Repository files"
check_file "config/paperdaily.example.yaml"
check_file "scripts/run_app_feed.py"
check_file ".github/workflows/daily-app-feed.yml"
check_file "ios/PaperDaily/PaperDaily.xcodeproj"
if [[ -e ".git" ]]; then
  say "[ok] git metadata found: .git"
else
  say "[warn] git metadata missing: .git"
fi
say ""

say "Environment"
check_env ZOTERO_ID
check_env ZOTERO_KEY
check_env OPENAI_API_KEY
check_env OPENAI_API_BASE
check_env OPENAI_MODEL
check_env CUSTOM_CONFIG
say ""

say "Recommended GitHub Actions variable values"
say "OPENAI_API_BASE=https://api.openai.com/v1"
say "OPENAI_MODEL=gpt-5.4-mini"
say "CUSTOM_CONFIG=config/paperdaily.example.yaml"
say ""

say "Local generation command"
say "uv sync"
say "uv run python scripts/run_app_feed.py --config config/paperdaily.example.yaml --output-dir public/data --timezone Asia/Taipei --language zh-Hans"
if [[ ! -x "$ROOT_DIR/.venv/bin/python" ]]; then
  say "If uv is unavailable locally, you can still rely on GitHub Actions to install it during the workflow."
fi
say ""

say "Manual steps you still need to do"
say "1. Connect this folder to your GitHub repository and push to the dev branch."
say "2. In GitHub, add Secrets: ZOTERO_ID, ZOTERO_KEY, OPENAI_API_KEY."
say "3. In GitHub, add Variables: OPENAI_API_BASE, OPENAI_MODEL, CUSTOM_CONFIG."
say "4. In GitHub Settings > Pages, set Source to GitHub Actions."
say "5. In Xcode, open ios/PaperDaily/PaperDaily.xcodeproj and set your Team and Bundle Identifier."
