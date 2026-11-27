// Ctrl+Cmd+F full screen for Herdr, whose menus lack macOS's "Enter Full Screen"
// item (the thing that shortcut normally triggers). Bound in keys.json as
// "fullscreen.toggle"; lives in a hidden floating block of each personal layout.
// macOS asks once for Accessibility permission for Herdr.

import { View, div } from "gpui-kit";
import { exec, nextCommand, notify, checking } from "herdr";

const TOGGLE = `tell application "System Events" to tell process "Herdr"
  set w to window 1
  set value of attribute "AXFullScreen" of w to not (value of attribute "AXFullScreen" of w)
end tell`;

export default class Fullscreen extends View {
  init(_props, cx) {
    if (checking()) return;
    cx.spawn(async () => {
      for (;;) {
        const c = await nextCommand();
        if (c !== "toggle") continue;
        try {
          const r = await exec("osascript", ["-e", TOGGLE], { timeout: 10000 });
          if (r.code !== 0) throw new Error(r.stderr.trim() || `osascript exited ${r.code}`);
        } catch (e) {
          notify({ title: "Full screen failed", body: String(e.message ?? e) + "\nAllow Herdr in System Settings → Privacy & Security → Accessibility.", level: "error" });
        }
      }
    });
  }

  render() {
    return div(); // nothing to show
  }
}
