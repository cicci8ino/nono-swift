#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/Artifacts/MANIFEST.json"

if [[ ! -f "$MANIFEST" ]]; then
    echo "error: Artifacts/MANIFEST.json does not exist; run make artifacts" >&2
    exit 1
fi

python3 - "$REPO_ROOT" <<'PY'
import hashlib
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
manifest = json.loads((repo_root / "Artifacts" / "MANIFEST.json").read_text(encoding="utf-8"))

def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

checked = 0
platforms = set()
for section in ("headers", "libraries"):
    for item in manifest.get(section, []):
        path = repo_root / item["path"]
        if not path.exists():
            raise SystemExit(f"missing artifact file: {item['path']}")
        actual = sha256(path)
        expected = item["sha256"]
        if actual != expected:
            raise SystemExit(f"checksum mismatch for {item['path']}: got {actual}, expected {expected}")
        if section == "libraries":
            platforms.add(item.get("platform"))
        checked += 1

missing = {"darwin_arm64"} - platforms
if missing:
    raise SystemExit(f"missing required library platform(s): {', '.join(sorted(missing))}")

unexpected = platforms - {"darwin_arm64"}
if unexpected:
    raise SystemExit(f"unexpected library platform(s): {', '.join(sorted(unexpected))}")

print(f"Verified {checked} artifact files")
PY
