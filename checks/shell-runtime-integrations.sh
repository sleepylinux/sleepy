#!/usr/bin/env bash
set -euo pipefail

registry="${1:?direct integration registry is required}"
document="${2:?runtime integration document is required}"

python3 - "$registry" "$document" <<'PY'
import json
import pathlib
import re
import sys

providers = json.loads(pathlib.Path(sys.argv[1]).read_text()).get("providers", [])
document = pathlib.Path(sys.argv[2]).read_text()
ids = [provider["id"] for provider in providers]
if len(ids) != len(set(ids)):
    raise SystemExit("duplicate provider IDs in registry")
for provider in providers:
    marker = f"<!-- provider:{provider['id']} -->"
    if document.count(marker) != 1:
        raise SystemExit(f"provider {provider['id']} must appear exactly once")
    section = document.split(marker, 1)[1].split("<!-- provider:", 1)[0]
    for field in ("owner", "stateSource", "mutationSource", "secretPolicy", "reconciliation"):
        if provider[field] not in section:
            raise SystemExit(f"provider {provider['id']} is missing exact {field} text")
    for command in provider["commands"]:
        if not re.search(rf"(?<![A-Za-z0-9_-]){re.escape(command)}(?![A-Za-z0-9_-])", section):
            raise SystemExit(f"provider {provider['id']} is missing command {command}")
markers = re.findall(r"<!-- provider:([a-z0-9-]+) -->", document)
if markers != ids:
    raise SystemExit("provider order must match the executable registry")

session_operations = [
    "set-idle-inhibited",
    "start-recording",
    "pause-recording",
    "stop-recording",
    "delete-recording",
    "set-game-mode",
    "lock",
    "suspend",
    "logout",
    "reboot",
    "power-off",
]
for operation in session_operations:
    marker = f"<!-- session-operation:{operation} -->"
    if document.count(marker) != 1:
        raise SystemExit(f"session operation {operation} must appear exactly once")
session_markers = re.findall(r"<!-- session-operation:([a-z0-9-]+) -->", document)
if session_markers != session_operations:
    raise SystemExit("session operation order must match the typed protocol")

print(
    f"PASS: runtime ownership document covers {len(ids)} direct providers and "
    f"{len(session_operations)} protected session operations exactly once"
)
PY
