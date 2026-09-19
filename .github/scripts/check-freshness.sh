#!/usr/bin/env bash
# Verify that the committed cards were refreshed recently and have not been
# modified since the last successful update.
#
# Usage: check-freshness.sh <state-file> <stats-svg> <top-langs-svg> <max-age-hours>
set -euo pipefail

state_file="${1:-}"
stats_file="${2:-}"
langs_file="${3:-}"
max_age_hours="${4:-26}"

if [ -z "$state_file" ] || [ -z "$stats_file" ] || [ -z "$langs_file" ] || [ -z "$max_age_hours" ]; then
  echo "usage: $0 <state-file> <stats-svg> <top-langs-svg> <max-age-hours>" >&2
  exit 2
fi

if [ ! -s "$state_file" ]; then
  echo "::error file=$state_file::$state_file is missing; cannot verify when the cards were last updated."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "::error::python3 is required to verify card freshness."
  exit 1
fi

python3 - "$state_file" "$stats_file" "$langs_file" "$max_age_hours" <<'PY'
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

state_file, stats_file, langs_file, max_age_hours = sys.argv[1:5]
max_age = float(max_age_hours)
failed = False


def error(message, path=None):
    global failed
    print(f"::error file={path or state_file}::{message}")
    failed = True


try:
    with open(state_file) as fh:
        state = json.load(fh)
except (OSError, ValueError) as exc:
    print(f"::error file={state_file}::{state_file} is not readable JSON: {exc}")
    sys.exit(1)

updated_at = state.get("updated_at")
if not updated_at:
    error("missing updated_at field")
else:
    try:
        timestamp = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
        if timestamp.tzinfo is None:
            timestamp = timestamp.replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        error(f"updated_at is not a valid timestamp: {updated_at!r}")
    else:
        age_hours = (datetime.now(timezone.utc) - timestamp).total_seconds() / 3600
        limit = int(max_age) if max_age.is_integer() else max_age
        if age_hours > max_age:
            error(f"cards were last updated {age_hours:.1f}h ago (limit {limit}h); the scheduled update seems to be failing")
        else:
            print(f"freshness OK: last updated {age_hours:.1f}h ago (limit {limit}h)")

for key, path in (("stats_sha256", stats_file), ("top_langs_sha256", langs_file)):
    recorded = state.get(key)
    if not recorded:
        error(f"missing {key} field")
        continue
    if not os.path.exists(path):
        error(f"{path} is missing", path)
        continue
    with open(path, "rb") as fh:
        actual = hashlib.sha256(fh.read()).hexdigest()
    if actual != recorded:
        error(f"{path} was modified outside the card pipeline (hash mismatch)", path)
    else:
        print(f"integrity OK: {path}")

sys.exit(1 if failed else 0)
PY
