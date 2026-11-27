// Keeps at least one space on this computer and every connected machine, like the herdr TUI,
// which opens a fresh workspace as soon as the last one closes. Closing the shown space
// keeps you on the same machine: its nearest space, or a fresh one if that was its last.
// Lives in an invisible floating block of each personal layout.

import { View, div } from "gpui-kit";
import { spaces, machines, run, checking, home, exec } from "herdr";

const RETRY_MS = 15000; // don't re-create while a new space is still appearing
// Another machine's spaces are first that machine's own Herdr's job (it reacts within
// a second); step in only if it stays empty this long, so two apps don't both add one.
const REMOTE_GRACE_MS = 5000;
// This computer: a short wait too, in case the app you're using elsewhere (which
// closed our last space on screen) is already adding its replacement.
const LOCAL_GRACE_MS = 1500;

// Every machine's home folder, asked once over herdr-core. New spaces need it spelled
// out: with no folder they inherit the shown space's, or the app's or core's own
// working folder, which is "/" on a Mac (started from Finder/launchd).
const homes = {}; // machine name -> home path
async function homeOf(machine) {
  if (!machine) return home();
  if (homes[machine]) return homes[machine];
  try {
    const r = await exec("sh", ["-c", "echo $HOME"], { on: machine, timeout: 5000 });
    const h = r.stdout.trim();
    if (r.code === 0 && h.startsWith("/")) return (homes[machine] = h);
  } catch (_) {}
  return null;
}

// A new space at home on `machine` (null: this computer).
async function fresh(machine, focus) {
  const folder = await homeOf(machine);
  const args = { focus, machine: machine ?? "" };
  if (folder) args.folder = folder; // unknown: leave it to the machine
  run("space.new", args);
}

export default class KeepSpace extends View {
  init(_props, cx) {
    this.pending = {}; // machine key -> time a space.new was sent
    this.empty = {}; // machine key -> since when it has had no space
    this.shown = null; // { id, machine, index } of the space on screen
    if (checking()) return;
    cx.timer.every(1000, (cx) => this.ensure(cx));
    cx.timer.every(250, (cx) => this.follow(cx));
  }

  ensure(cx) {
    const all = spaces();
    // This computer is always reachable; include it even if machines() omits it.
    const list = machines();
    if (!list.some((m) => m.name === null)) list.push({ name: null, layout: "ready" });
    for (const m of list) {
      if (m.layout !== "ready") continue; // offline or loading: never guess
      if (m.name && !homes[m.name]) homeOf(m.name); // learn its home ahead of time
      const key = m.name ?? "";
      if (all.some((s) => (s.machine ?? "") === key)) {
        delete this.pending[key];
        delete this.empty[key];
        continue;
      }
      this.empty[key] ??= Date.now();
      if (Date.now() - this.empty[key] < (key ? REMOTE_GRACE_MS : LOCAL_GRACE_MS)) continue;
      if (this.pending[key] && Date.now() - this.pending[key] < RETRY_MS) continue;
      this.pending[key] = Date.now();
      fresh(m.name, false);
    }
  }

  // The shown space vanished (closed): stay on its machine instead of wherever the app jumped.
  follow(cx) {
    const all = spaces();
    const cur = all.find((s) => s.active);
    const prev = this.shown;
    if (prev && !all.some((s) => s.id === prev.id)) {
      this.shown = null;
      const key = prev.machine ?? "";
      if ((cur?.machine ?? "") === key) return; // already on the same machine
      const same = all.filter((s) => (s.machine ?? "") === key);
      if (same.length) {
        const before = same.filter((s) => s.index < prev.index);
        run("space.select", { id: (before.length ? before[before.length - 1] : same[0]).id });
      } else {
        this.pending[key] = Date.now(); // ensure() mustn't add a second one
        fresh(prev.machine, true);
      }
      return;
    }
    if (cur) this.shown = { id: cur.id, machine: cur.machine, index: cur.index };
  }

  render() {
    return div(); // nothing to show; an empty floating block stays hidden
  }
}
