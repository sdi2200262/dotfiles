# Dell host hook, sourced by setup.sh (uses its link/run/say helpers).
D="$HOSTDIR"

say "Dell: sway session"
link "$D/sway/config"               "$HOME/.config/sway/config"
link "$D/bin/sway-status"           "$HOME/.local/bin/sway-status"
link "$D/bin/sway-autostart"        "$HOME/.local/bin/sway-autostart"
link "$D/bin/sway-next-window"      "$HOME/.local/bin/sway-next-window"
link "$D/bin/keys"                  "$HOME/.local/bin/keys"
link "$D/bin/lock-screen"           "$HOME/.local/bin/lock-screen"
link "$D/gtklock/style.css"         "$HOME/.config/gtklock/style.css"
link "$D/zprofile"                  "$HOME/.zprofile"

# Firefox gruvbox theme, linked into the profile Firefox actually uses
# (Firefox 147+ keeps profiles in ~/.config/mozilla, older ones in ~/.mozilla).
for ffdir in "$HOME/.config/mozilla/firefox" "$HOME/.mozilla/firefox"; do
    [ -f "$ffdir/installs.ini" ] || continue
    prof="$(sed -n 's/^Default=//p' "$ffdir/installs.ini" | head -1)"
    [ -n "$prof" ] && [ -d "$ffdir/$prof" ] || continue
    say "Dell: Firefox theme -> $prof"
    link "$D/firefox/user.js"                  "$ffdir/$prof/user.js"
    link "$D/firefox/chrome/userChrome.css"    "$ffdir/$prof/chrome/userChrome.css"
    link "$D/firefox/chrome/userContent.css"   "$ffdir/$prof/chrome/userContent.css"
    # Theme: packed from theme/manifest.json into the profile's extensions/ folder.
    xpi="$ffdir/$prof/extensions/gruvbox-soft@dotfiles.xpi"
    tmpx="$(mktemp -d)/theme.xpi"
    (cd "$D/firefox/theme" && python3 -m zipfile -c "$tmpx" manifest.json)
    if ! cmp -s "$tmpx" "$xpi" 2>/dev/null; then
        run mkdir -p "$(dirname "$xpi")"
        run cp "$tmpx" "$xpi"
        note "Firefox theme installed: restart Firefox, then enable \"Gruvbox Dark Soft\" once in about:addons > Themes"
    fi
    rm -rf "$(dirname "$tmpx")"
    break
done

if [ -z "$LINKS_ONLY" ]; then
    say "Dell: text console theme (sudo)"
    # Login banner
    cmp -s "$D/system/issue" /etc/issue || { run sudo install -m644 "$D/system/issue" /etc/issue; note "/etc/issue"; }

    # Big Terminus console font
    if ! grep -qs '^FONTFACE="Terminus"' /etc/default/console-setup || ! grep -qs '^FONTSIZE="16x32"' /etc/default/console-setup; then
        run sudo sed -i -e 's/^FONTFACE=.*/FONTFACE="Terminus"/' -e 's/^FONTSIZE=.*/FONTSIZE="16x32"/' /etc/default/console-setup
        note "console font: Terminus 16x32 (applies at next boot)"
    fi

    # 16-colour console palette, generated from the same theme file Ghostty uses,
    # passed to the kernel so it applies from the very first line of boot.
    theme="$DOT/common/ghostty/themes/gruvbox-dark-soft"
    r=; g=; b=
    for i in $(seq 0 15); do
        hex="$(sed -n "s/^palette = $i=#\([0-9a-fA-F]\{6\}\).*/\1/p" "$theme")"
        r="$r,0x${hex:0:2}"; g="$g,0x${hex:2:2}"; b="$b,0x${hex:4:2}"
    done
    cfg="GRUB_CMDLINE_LINUX_DEFAULT=\"\$GRUB_CMDLINE_LINUX_DEFAULT vt.default_red=${r#,} vt.default_grn=${g#,} vt.default_blu=${b#,}\"
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden"
    gfile=/etc/default/grub.d/90-dotfiles-tty.cfg
    if [ "$(cat "$gfile" 2>/dev/null)" != "$cfg" ]; then
        run sudo mkdir -p /etc/default/grub.d
        if [ -z "$DRY" ]; then printf '%s\n' "$cfg" | sudo tee "$gfile" >/dev/null; fi
        run sudo update-grub
        note "boot: no GRUB menu (hold Shift/Esc for it), console palette (next boot)"
    fi

    # Lid: suspend on battery, stay awake on the charger.
    lid=/etc/systemd/logind.conf.d/10-dotfiles-lid.conf
    if ! cmp -s "$D/system/logind-lid.conf" "$lid"; then
        run sudo install -Dm644 "$D/system/logind-lid.conf" "$lid"
        run sudo systemctl kill -s HUP systemd-logind
        note "lid: stays awake on the charger"
    fi
    # Ghostty from source
    want="$(sed -n 's/^GHOSTTY_VERSION=//p' "$D/build-ghostty.sh")"
    if ! "$HOME/.local/bin/ghostty" --version 2>/dev/null | grep -q "Ghostty $want"; then
        say "Dell: building Ghostty $want (takes a few minutes)"
        run bash "$D/build-ghostty.sh"
    fi
fi
