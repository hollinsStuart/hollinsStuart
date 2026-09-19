#!/usr/bin/env bash
# Validate a github-readme-stats SVG card before it is allowed to replace a
# committed card.
#
# Usage: check-card.sh <svg-file> <expected-marker>
#
# Exits non-zero unless the file exists, is non-empty, looks like an SVG, does
# not contain the renderer's error-card markup, and contains the expected
# success marker.
set -euo pipefail

file="${1:-}"
marker="${2:-}"

if [ -z "$file" ] || [ -z "$marker" ]; then
  echo "usage: $0 <svg-file> <expected-marker>" >&2
  exit 2
fi

if [ ! -s "$file" ]; then
  echo "::error file=$file::$file was not generated (missing or empty)"
  exit 1
fi

if ! grep -q '<svg' "$file"; then
  echo "::error file=$file::$file is not an SVG file"
  exit 1
fi

# Also require well-formed XML when a parser is available.
if command -v python3 >/dev/null 2>&1; then
  if ! python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$file"; then
    echo "::error file=$file::$file is not well-formed XML"
    exit 1
  fi
fi

# Error cards rendered by github-readme-stats always contain this test id.
if grep -q 'data-testid="message"' "$file"; then
  echo "::error file=$file::$file contains an error card:"
  cat "$file"
  exit 1
fi

if ! grep -q "$marker" "$file"; then
  echo "::error file=$file::$file is missing the expected card content"
  exit 1
fi

echo "$file: valid"
