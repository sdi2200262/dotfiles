# macOS hook, sourced by setup.sh.
# Ghostty also reads ~/Library/Application Support/com.mitchellh.ghostty/config,
# after ~/.config/ghostty/config, so a leftover one there would override the
# shared settings. Its useful bits now live in os/mac/ghostty.conf.
lib="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
if [ -f "$lib" ] && [ ! -L "$lib" ]; then
    say "macOS: retiring the old Ghostty config in ~/Library"
    backup "$lib"
fi
