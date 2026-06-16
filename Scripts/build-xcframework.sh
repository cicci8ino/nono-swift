#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${NONO_SWIFT_BUILD_ROOT:-$REPO_ROOT/.build/nono-source-build}"
OUT_DIR="$BUILD_ROOT/out"
ARTIFACTS_DIR="$REPO_ROOT/Artifacts"
XCFRAMEWORK="$ARTIFACTS_DIR/CNono.xcframework"
HEADERS_DIR="$BUILD_ROOT/CNonoHeaders"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild is required to create CNono.xcframework" >&2
    exit 127
fi

"$SCRIPT_DIR/build-nono.sh" "$@"

# shellcheck source=/dev/null
source "$OUT_DIR/metadata.env"

rm -rf "$HEADERS_DIR" "$XCFRAMEWORK"
mkdir -p "$HEADERS_DIR" "$ARTIFACTS_DIR"
cp "$NONO_HEADER" "$HEADERS_DIR/nono.h"
cat > "$HEADERS_DIR/module.modulemap" <<'EOF'
module CNono {
  header "nono.h"
  export *
}
EOF

XCFRAMEWORK_ARGS=()
for arch in $NONO_BUILT_ARCHS; do
    case "$arch" in
        arm64)
            XCFRAMEWORK_ARGS+=("-library" "${NONO_DARWIN_ARM64_LIB:?}" "-headers" "$HEADERS_DIR")
            ;;
        *)
            echo "error: unsupported built arch '$arch'" >&2
            exit 1
            ;;
    esac
done

xcodebuild -create-xcframework "${XCFRAMEWORK_ARGS[@]}" -output "$XCFRAMEWORK"

python3 - "$REPO_ROOT" "$XCFRAMEWORK" "$NONO_SOURCE_URL" "$NONO_COMMIT" <<'PY'
import hashlib
import json
import pathlib
import plistlib
import sys

repo_root = pathlib.Path(sys.argv[1])
xcframework = pathlib.Path(sys.argv[2])
source_url = sys.argv[3]
commit = sys.argv[4]
info = plistlib.loads((xcframework / "Info.plist").read_bytes())

def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

libraries = []
headers = []
for library in info["AvailableLibraries"]:
    identifier = library["LibraryIdentifier"]
    lib_path = xcframework / identifier / library["LibraryPath"]
    header_path = xcframework / identifier / library["HeadersPath"] / "nono.h"
    archs = library.get("SupportedArchitectures", [])
    if archs == ["arm64"]:
        target = "aarch64-apple-darwin"
        platform = "darwin_arm64"
    else:
        target = "unknown"
        platform = identifier

    libraries.append({
        "platform": platform,
        "target": target,
        "path": str(lib_path.relative_to(repo_root)),
        "sha256": sha256(lib_path),
    })
    headers.append({
        "platform": platform,
        "path": str(header_path.relative_to(repo_root)),
        "sha256": sha256(header_path),
    })

manifest = {
    "schema": 1,
    "source": {
        "url": source_url,
        "commit": commit,
    },
    "headers": sorted(headers, key=lambda item: item["path"]),
    "libraries": sorted(libraries, key=lambda item: item["path"]),
}
(repo_root / "Artifacts" / "MANIFEST.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "Created $XCFRAMEWORK"
echo "Wrote $ARTIFACTS_DIR/MANIFEST.json"
