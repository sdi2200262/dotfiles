#!/usr/bin/env bash
# Build Ghostty from the signed release tarball into ~/.local.
# Re-running with the same versions reuses the downloads.
set -euo pipefail

GHOSTTY_VERSION=1.4.0
ZIG_VERSION=0.17.1
ZIG_SHA256=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a
# Ghostty's release signing key (https://ghostty.org/docs/install/build)
GHOSTTY_MINISIGN_KEY=RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV

CACHE="$HOME/.cache/dotfiles-build"
mkdir -p "$CACHE"; cd "$CACHE"

# Zig toolchain (checksum-verified)
zig_dir="zig-x86_64-linux-$ZIG_VERSION"
if [ ! -x "$zig_dir/zig" ]; then
    curl -fsSLO "https://ziglang.org/download/$ZIG_VERSION/$zig_dir.tar.xz"
    echo "$ZIG_SHA256  $zig_dir.tar.xz" | sha256sum -c -
    tar -xJf "$zig_dir.tar.xz"
fi
ZIG="$CACHE/$zig_dir/zig"

# Ghostty source (signature-verified)
src="ghostty-$GHOSTTY_VERSION"
if [ ! -d "$src" ]; then
    curl -fsSLO "https://release.files.ghostty.org/$GHOSTTY_VERSION/$src.tar.gz"
    curl -fsSLO "https://release.files.ghostty.org/$GHOSTTY_VERSION/$src.tar.gz.minisig"
    minisign -Vm "$src.tar.gz" -P "$GHOSTTY_MINISIGN_KEY"
    tar -xzf "$src.tar.gz"
fi

# Refuse a Zig whose major.minor doesn't match what this Ghostty asks for.
need="$(sed -n 's/.*minimum_zig_version *= *"\([0-9.]*\)".*/\1/p' "$src/build.zig.zon" | head -1)"
if [ -n "$need" ] && [ "${need%.*}" != "${ZIG_VERSION%.*}" ]; then
    echo "Ghostty $GHOSTTY_VERSION wants Zig $need, but ZIG_VERSION=$ZIG_VERSION. Update build-ghostty.sh." >&2
    exit 1
fi

cd "$src"
"$ZIG" build -p "$HOME/.local" -Doptimize=ReleaseFast
"$HOME/.local/bin/ghostty" --version | head -1
