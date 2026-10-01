.pragma library

// The naming grammar and the hotplug memory, as pure functions: plain objects
// in, plain objects out, nothing that talks to Hyprland, files or timers.
// Workspaces.qml does the talking. The tests run these on their own:
//
//   QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -platform offscreen -input tests/tst_memory.qml

// ------------------------------------------------------------------ names
//
// Mirrors hypr/names.lua. The two runtimes cannot share code, so they share a
// contract instead -- as they already do for monitor_key and for <key>:<slot>.
// If they disagree, the dots and the keys address different workspaces.

function baseName(name) {
  return String(name).replace(/#\d+\.\d+$/, "")
}

function guestOrigin(name) {
  var match = String(name).match(/#(\d+)\.(\d+)$/)
  return match ? { block: Number(match[1]), slot: Number(match[2]) } : null
}

// A valid slot number: a plain positive integer below the id ceiling,
// matching names.id's own range. `Number` alone is looser than the Lua
// side's `%d+` pattern -- it accepts "+3", "0x10", "1e2", "3.0" and
// "Infinity" -- and an unbounded or infinite result would size
// effectiveCount and buildEntries' own loop off a name nothing sane would
// produce. Returns 0 for anything that does not qualify.
function parseSlot(text) {
  var str = String(text)
  if (!/^[0-9]+$/.test(str)) return 0
  var slot = Number(str)
  return slot > 0 && slot < 100 ? slot : 0
}

// Where a workspace lives, `<key>:<slot>`, as { key, slot }, or null for a
// name that is not a slot. The trailer is ignored: this is where it lives,
// not where it came from.
function splitSlot(name) {
  var base = baseName(name)
  var cut = base.lastIndexOf(":")
  if (cut <= 0) return null
  var slot = parseSlot(base.substring(cut + 1))
  return slot > 0 ? { key: base.substring(0, cut), slot: slot } : null
}

// The key the Lua half builds for a screen. Description rather than connector,
// because the description follows the physical panel while connector names can
// swap on replug; the connector is appended only to break a tie between two
// panels that describe themselves alike. `monitor` and `monitors` need only
// `name` and `description`, so Quickshell's monitors and hyprctl's both do.
function monitorKey(monitor, monitors) {
  var description = String(monitor.description || "")
  if (description === "") return String(monitor.name || "")
  for (var i = 0; i < monitors.length; i++) {
    var other = monitors[i]
    if (String(other.name) !== String(monitor.name) && String(other.description || "") === description)
      return description + "@" + String(monitor.name || "")
  }
  return description
}
