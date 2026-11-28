#!/usr/bin/env bash
# setup.sh: install packages and link dotfiles on this machine.
# Safe to re-run: links already in place are skipped, and anything it would
# replace is moved to ~/.dotfiles-backup/<timestamp>/ first.
#
#   ./setup.sh             do it
#   ./setup.sh --dry-run   print what would happen, change nothing
#   ./setup.sh --links     only (re)link configs, skip packages
#   ./setup.sh --host X    act as host X (default: short hostname)
set -euo pipefail

DOT="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${DOTFILES_HOST:-}" ] && [ -r "$HOME/.config/dotfiles/host" ]; then
    IFS= read -r DOTFILES_HOST < "$HOME/.config/dotfiles/host" || true
fi
HOST="${DOTFILES_HOST:-$(hostname -s | tr "[:upper:]" "[:lower:]")}"
DRY=; LINKS_ONLY=
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        --links)   LINKS_ONLY=1 ;;
        --host)    HOST="$2"; shift ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

case "$(uname -s)" in
    Darwin) OS=mac ;;
    Linux)  OS=linux; . /etc/os-release; DISTRO="$ID" ;;
    *) echo "unsupported OS" >&2; exit 1 ;;
esac
HOSTDIR="$DOT/hosts/$HOST"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

say()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
run()  { if [ -n "$DRY" ]; then printf '    [dry] %s\n' "$*"; else "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }
# User-level installs land in ~/.local/bin; find them on a fresh machine too.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# Move an existing file out of the way (keeps its path under $BACKUP).
backup() {
    local dest="$1" rel="${1#$HOME/}"
    run mkdir -p "$BACKUP/$(dirname "$rel")"
    run mv "$dest" "$BACKUP/$rel"
    note "backed up ~/$rel"
}

# link SRC DEST: symlink DEST -> SRC, backing up whatever was there.
link() {
    local src="$1" dest="$2"
    [ -e "$src" ] || { note "missing in repo: $src"; return; }
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then return; fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then backup "$dest"; fi
    run mkdir -p "$(dirname "$dest")"
    run ln -s "$src" "$dest"
    note "linked ~/${dest#$HOME/}"
}

# render TEMPLATE DEST: copy with @HOME@ replaced (for files needing absolute paths).
render() {
    local tmpl="$1" dest="$2" out
    out="$(sed "s|@HOME@|$HOME|g" "$tmpl")"
    if [ -f "$dest" ] && [ ! -L "$dest" ] && [ "$(cat "$dest")" = "$out" ]; then return; fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then backup "$dest"; fi
    run mkdir -p "$(dirname "$dest")"
    if [ -z "$DRY" ]; then printf '%s\n' "$out" > "$dest"; else note "[dry] write $dest"; fi
    note "rendered ~/${dest#$HOME/}"
}

# seed SRC DEST: copy SRC once if DEST is missing, for files an app rewrites
# itself (zoom levels, window sizes) that shouldn't dirty the repo.
seed() {
    [ -e "$2" ] && return 0
    run mkdir -p "$(dirname "$2")"
    run cp "$1" "$2"
    note "seeded ~/${2#$HOME/}"
}

# Package names from a list file (comments and blanks stripped).
pkglist() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$1"; }

# Latest GitHub release asset matching a regex -> download URL.
gh_asset() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
        | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 | grep -E "$2" | head -1
}

# ── 1. packages ───────────────────────────────────────────────────
install_apt() {
    local want=() missing=() p
    for f in "$DOT/packages/apt.txt" "$HOSTDIR/apt.txt"; do
        [ -f "$f" ] || continue
        while read -r p; do
            if apt-cache show "$p" >/dev/null 2>&1; then want+=("$p"); else missing+=("$p"); fi
        done < <(pkglist "$f")
    done
    say "apt: ${#want[@]} packages (sudo)"
    [ ${#missing[@]} -eq 0 ] || note "not packaged on $DISTRO $VERSION_ID: ${missing[*]} (GitHub fallback below)"
    run sudo apt-get update -qq
    run sudo apt-get install -y --no-install-recommends "${want[@]}"
}

# Tools Debian/Ubuntu don't ship (or ship too old): user-level, into ~/.local.
install_extras_linux() {
    local bin="$HOME/.local/bin" tmp url
    run mkdir -p "$bin"
    # Debian names bat/fd differently.
    have batcat && ! have bat && link "$(command -v batcat)" "$bin/bat"
    have fdfind && ! have fd  && link "$(command -v fdfind)" "$bin/fd"
    # helix: the release tarball, since Debian's `hx` lags behind macOS and Ubuntu.
    if ! [ -x "$bin/hx" ]; then
        say "helix (GitHub release)"
        url="$(gh_asset helix-editor/helix 'x86_64-linux\.tar\.xz$')"
        tmp="$(mktemp -d)"
        run curl -fsSL "$url" -o "$tmp/hx.tar.xz"
        run tar -xJf "$tmp/hx.tar.xz" -C "$tmp"
        run rm -rf "$HOME/.local/helix"
        run mv "$tmp"/helix-*-x86_64-linux "$HOME/.local/helix"
        link "$HOME/.local/helix/hx" "$bin/hx"
    fi
    # Helix language servers (see common/helix/languages.toml.tmpl).
    if ! have texlab; then
        say "texlab (GitHub release)"
        url="$(gh_asset latex-lsp/texlab 'texlab-x86_64-linux\.tar\.gz$')"
        run sh -c "curl -fsSL '$url' | tar -xz -C '$bin' texlab"
    fi
    if ! have markdown-oxide; then
        say "markdown-oxide (GitHub release)"
        url="$(gh_asset Feel-ix-343/markdown-oxide 'x86_64-unknown-linux-gnu$')"
        run curl -fsSL "$url" -o "$bin/markdown-oxide"
        run chmod +x "$bin/markdown-oxide"
    fi
    if ! have marksman; then
        say "marksman (GitHub release)"
        url="$(gh_asset artempyanykh/marksman 'marksman-linux-x64$')"
        run curl -fsSL "$url" -o "$bin/marksman"
        run chmod +x "$bin/marksman"
    fi
    if ! have uv; then
        say "uv (official installer)"
        run sh -c "curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh"
    fi
    if ! have starship; then
        say "starship (official installer)"
        run sh -c "curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b '$bin'"
    fi
    # lazygit: the shared config needs a recent release, newer than Debian's.
    if ! [ -x "$bin/lazygit" ]; then
        say "lazygit (GitHub release)"
        url="$(gh_asset jesseduffield/lazygit 'linux_x86_64\.tar\.gz$')"
        run sh -c "curl -fsSL '$url' | tar -xz -C '$bin' lazygit"
    fi
    if ! have yazi; then
        say "yazi (GitHub release)"
        url="$(gh_asset sxyazi/yazi 'yazi-x86_64-unknown-linux-gnu\.zip$')"
        tmp="$(mktemp -d)"
        run curl -fsSL "$url" -o "$tmp/yazi.zip"
        run unzip -q "$tmp/yazi.zip" -d "$tmp"
        run install -m755 "$tmp"/yazi-*/yazi "$tmp"/yazi-*/ya "$bin/"
    fi
    if ! have hc && ! [ -x "$bin/herdr-core" ]; then
        say "herdr-core (official installer)"
        run sh -c "curl -fsSL https://releases.herdr.dev/core/install.sh | sh"
    fi
    if [ "$HOST" = dell ] && [ ! -x "$bin/herdr-app" ]; then
        say "herdr-app (official installer)"
        run sh -c "curl -fsSL https://releases.herdr.dev/app/install.sh | sh"
    fi
}

install_brew() {
    have brew || { echo "Install Homebrew first: https://brew.sh" >&2; exit 1; }
    say "brew bundle"
    run brew bundle --file "$DOT/packages/Brewfile"
}

# ── 2. configs ────────────────────────────────────────────────────
link_common() {
    local C="$DOT/common" X="$HOME/.config"
    say "linking shared configs"
    link "$C/zsh/zshrc"                     "$HOME/.zshrc"
    link "$C/zsh/zshenv"                    "$HOME/.zshenv"
    link "$C/helix/config.toml"             "$X/helix/config.toml"
    link "$C/helix/ignore"                  "$X/helix/ignore"
    render "$C/helix/languages.toml.tmpl"   "$X/helix/languages.toml"
    link "$C/starship.toml"                 "$X/starship.toml"
    link "$C/git/gitconfig"                 "$HOME/.gitconfig"
    link "$C/bat/config"                    "$X/bat/config"
    link "$C/lazygit/config.yml"            "$X/lazygit/config.yml"
    if have bookokrat; then
        seed "$C/bookokrat/config.yaml"      "$X/bookokrat/config.yaml"
    fi
    link "$C/yazi/theme.toml"               "$X/yazi/theme.toml"
    link "$C/yazi/gruvbox-dark-soft.tmTheme" "$X/yazi/gruvbox-dark-soft.tmTheme"
    link "$C/ghostty/config"                "$X/ghostty/config"
    link "$C/ghostty/themes/gruvbox-dark-soft" "$X/ghostty/themes/gruvbox-dark-soft"
    link "$C/bin/oscopy"                    "$HOME/.local/bin/oscopy"
    # Retire the old shared shortcut in existing installations.
    if [ -L "$HOME/.local/bin/keys" ] && [ "$(readlink "$HOME/.local/bin/keys")" = "$C/bin/keys" ]; then
        run rm "$HOME/.local/bin/keys"
    fi
    # Herdr app (where it's installed): settings, theme, layout, mods, keys per OS
    if [ -x "$HOME/.local/bin/herdr-app" ] || [ -d /Applications/Herdr.app ]; then
        local H="$C/herdr-app" HA="$X/herdr-app" m
        link "$H/settings.json"                  "$HA/settings.json"
        link "$H/themes/gruvbox-dark-soft.json"  "$HA/themes/gruvbox-dark-soft.json"
        link "$H/layouts/main-gruvbox.json"      "$HA/layouts/main-gruvbox.json"
        for m in "$H"/mods/*/; do link "${m%/}" "$HA/mods/$(basename "$m")"; done
        link "$DOT/os/$OS/herdr-keys.json"       "$HA/keys.json"
    fi
    [ -f "$DOT/os/$OS/ghostty.conf" ] && link "$DOT/os/$OS/ghostty.conf" "$X/ghostty/os.conf"
    [ -f "$HOSTDIR/ghostty.conf" ]    && link "$HOSTDIR/ghostty.conf"    "$X/ghostty/host.conf"
    return 0
}

# Machine-local files that stay out of the repo.
local_files() {
    say "machine-local settings"
    # git credentials: gh if available (per machine, in ~/.gitconfig.local).
    if have gh && gh auth status >/dev/null 2>&1 && ! git config --file "$HOME/.gitconfig.local" --get-all credential.https://github.com.helper >/dev/null 2>&1; then
        run git config --file "$HOME/.gitconfig.local" --add credential.https://github.com.helper ''
        run git config --file "$HOME/.gitconfig.local" --add credential.https://github.com.helper '!gh auth git-credential'
        note "git uses gh for GitHub credentials (~/.gitconfig.local)"
    fi
    # Honor an existing local credential store.
    if [ -f "$HOME/.git-credentials" ] && ! git config --file "$HOME/.gitconfig.local" --get credential.helper >/dev/null 2>&1; then
        run git config --file "$HOME/.gitconfig.local" credential.helper store
        note "git keeps using ~/.git-credentials (~/.gitconfig.local)"
    fi
    local dictionary="$HOME/.config/harper-ls/dict.txt"
    if have harper-ls && [ ! -e "$dictionary" ] && [ ! -L "$dictionary" ]; then
        run mkdir -p "$(dirname "$dictionary")"
        run touch "$dictionary"
    fi
}

set_shell() {
    local zsh; zsh="$(command -v zsh || true)"
    [ -n "$zsh" ] || return 0
    case "$SHELL" in */zsh) return 0 ;; esac
    say "default shell -> zsh (asks your password)"
    run chsh -s "$zsh"
}

# ── main ──────────────────────────────────────────────────────────
say "host=$HOST os=$OS${DISTRO:+ ($DISTRO)}${DRY:+ (dry run)}"

if [ -z "$LINKS_ONLY" ]; then
    case "$OS" in
        linux) install_apt; install_extras_linux ;;
        mac)   install_brew ;;
    esac
    # harper-ls: the release binary on every OS (Homebrew builds it from source on Intel Macs).
    if ! have harper-ls; then
        say "harper-ls (GitHub release)"
        case "$OS" in linux) target=x86_64-unknown-linux-gnu ;; mac) target=x86_64-apple-darwin ;; esac
        url="$(gh_asset automattic/harper "harper-ls-$target\\.tar\\.gz$")"
        run sh -c "curl -fsSL '$url' | tar -xz -C '$HOME/.local/bin' harper-ls"
    fi
    # Python language servers, as uv tools on every OS.
    for tool in ruff pyright; do
        have "$tool" || { say "$tool (uv tool)"; run uv tool install "$tool"; }
    done
fi
link_common
local_files
# OS and host hooks: extra links and tweaks for this OS / machine only.
[ -f "$DOT/os/$OS/setup.sh" ] && . "$DOT/os/$OS/setup.sh"
# Host hook: extra links and system tweaks for this machine only.
[ -f "$HOSTDIR/setup.sh" ] && . "$HOSTDIR/setup.sh"
[ -n "$LINKS_ONLY" ] || set_shell

[ -d "$BACKUP" ] && say "replaced files saved in $BACKUP"
say "done${DRY:+ (dry run, nothing changed)}"
