#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${NONO_SWIFT_BUILD_ROOT:-$REPO_ROOT/.build/nono-source-build}"
CARGO_HOME="${CARGO_HOME:-$BUILD_ROOT/cargo-home}"
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$BUILD_ROOT/cargo-target}"
SOURCE_URL="${NONO_SOURCE_URL:-https://github.com/always-further/nono.git}"
NONO_REF="${NONO_REF:-main}"
NONO_SRC=""
TARGET="aarch64-apple-darwin"

export CARGO_HOME
export CARGO_TARGET_DIR

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nono-src)
            NONO_SRC="$2"
            shift 2
            ;;
        --nono-ref)
            NONO_REF="$2"
            shift 2
            ;;
        --arch)
            case "$2" in
                arm64|aarch64|aarch64-apple-darwin)
                    shift 2
                    ;;
                *)
                    echo "error: unsupported arch '$2' (only arm64 is supported)" >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo is required to build nono-ffi from source" >&2
    echo "Install Rust, then run: rustup target add $TARGET" >&2
    exit 127
fi

if command -v rustup >/dev/null 2>&1; then
    installed_targets="$(rustup target list --installed)"
    if ! grep -qx "$TARGET" <<< "$installed_targets"; then
        echo "error: missing Rust target: $TARGET" >&2
        echo "Install with: rustup target add $TARGET" >&2
        exit 1
    fi
fi

if [[ -z "$NONO_SRC" ]]; then
    NONO_SRC="$BUILD_ROOT/nono"
    if [[ ! -d "$NONO_SRC/.git" ]]; then
        mkdir -p "$BUILD_ROOT"
        git clone "$SOURCE_URL" "$NONO_SRC"
    fi
    git -C "$NONO_SRC" fetch --tags --quiet
    git -C "$NONO_SRC" checkout --quiet "$NONO_REF"
else
    NONO_SRC="$(cd "$NONO_SRC" && pwd)"
fi

OUT_DIR="$BUILD_ROOT/out"
DEST_DIR="$OUT_DIR/darwin_arm64"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/include" "$DEST_DIR"

cp "$NONO_SRC/bindings/c/include/nono.h" "$OUT_DIR/include/nono.h"
cargo build --release --manifest-path "$NONO_SRC/Cargo.toml" -p nono-ffi --target "$TARGET"
cp "$CARGO_TARGET_DIR/$TARGET/release/libnono_ffi.a" "$DEST_DIR/libnono_ffi.a"

NONO_COMMIT="$(git -C "$NONO_SRC" rev-parse HEAD)"

{
    printf "NONO_SOURCE_URL=%q\n" "$SOURCE_URL"
    printf "NONO_SOURCE_DIR=%q\n" "$NONO_SRC"
    printf "NONO_COMMIT=%q\n" "$NONO_COMMIT"
    printf "NONO_CARGO_HOME=%q\n" "$CARGO_HOME"
    printf "NONO_CARGO_TARGET_DIR=%q\n" "$CARGO_TARGET_DIR"
    printf "NONO_HEADER=%q\n" "$OUT_DIR/include/nono.h"
    printf "NONO_BUILT_ARCHS=%q\n" "arm64"
    printf "NONO_DARWIN_ARM64_LIB=%q\n" "$DEST_DIR/libnono_ffi.a"
} > "$OUT_DIR/metadata.env"

echo "Built nono-ffi artifact in $OUT_DIR"
