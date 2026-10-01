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

// ------------------------------------------------------------------ homes
//
// Where a workspace belongs: [block, slot] of the screen it is a slot of.
// Names and ids change as a workspace is taken in and sent home; this does
// not. U2725QE:2, then the guest BOE:5#2.2, then U2725QE:2 again are all
// [2, 2]. Null for anything that is not one of ours: a placeholder Hyprland
// made up, a special workspace, a key with no block yet.
function homeOf(name, blocks) {
  var text = String(name)
  if (text.indexOf("special:") === 0) return null
  var parts = splitSlot(text)
  if (!parts) return null
  var origin = guestOrigin(text)
  if (origin) return origin.block > 0 && origin.slot > 0 ? [origin.block, origin.slot] : null
  var block = Number(blocks[parts.key])
  return block > 0 ? [block, parts.slot] : null
}

function sameHome(left, right) {
  return !!left && !!right && left[0] === right[0] && left[1] === right[1]
}

// ----------------------------------------------------------------- layout

// Which screens are connected, where, and how big. Two snapshots with the same
// signature saw the same screens in the same places; anything else means a
// screen came, went or moved, and focus may have moved with it.
function layoutSignature(monitors) {
  var lines = []
  for (var i = 0; i < monitors.length; i++) {
    var monitor = monitors[i]
    lines.push([monitor.name, monitor.description, monitor.x, monitor.y, monitor.width, monitor.height].join("|"))
  }
  return lines.sort().join("\n")
}

// The memory's freeze, one snapshot at a time. `state` is { layout, frozen,
// fixupDone, waits }: the previous snapshot's layout signature ("" before the
// first), whether the memory is frozen, whether the fix-up has run since it
// froze, and how often the fix-up has waited. A snapshot of other screens than
// the last one -- or the first, which has nothing to compare with -- freezes
// the memory and starts the fix-up over; a snapshot of the same screens thaws
// it, but only once the fix-up has run. While frozen, nothing is recorded.
function freezeStep(state, layout) {
  var stable = state.layout !== "" && layout === state.layout
  var next = { layout: layout, frozen: state.frozen, fixupDone: state.fixupDone, waits: state.waits }
  if (!stable) {
    next.frozen = true
    next.fixupDone = false
    next.waits = 0
  } else if (next.frozen && next.fixupDone) {
    next.frozen = false
  }
  return next
}

// ----------------------------------------------------------------- memory
//
// { session, focus: [block, slot] | null,
//   screens: { "<block>": { shown: [block, slot] | null, own: slot | null } } }
//
// `focus` is the home of the workspace you are on. Per screen, by block,
// `shown` is the home of what it shows, guests included, and `own` the last of
// its own native slots it showed. `session` is Hyprland's instance signature:
// the memory belongs to one session, and a file from another reads as empty.

function emptyMemory(session) {
  return { session: String(session), focus: null, screens: {} }
}

function positive(value) {
  return typeof value === "number" && value > 0 && Math.floor(value) === value
}

function validHome(value) {
  return Array.isArray(value) && value.length === 2 && positive(value[0]) && positive(value[1])
}

// The memory file's text, back into a memory. Anything other than what
// serialize() writes -- no file, a file from another session, one that no
// longer parses, fields of the wrong type -- reads as empty, or loses the
// fields that are wrong: the fix-up then falls back to each screen's own
// slots, as before there was any memory at all.
function parse(text, session) {
  var data
  try {
    data = JSON.parse(String(text))
  } catch (error) {
    return emptyMemory(session)
  }
  if (!data || typeof data !== "object" || data.session !== String(session)) return emptyMemory(session)

  var memory = emptyMemory(session)
  if (validHome(data.focus)) memory.focus = [data.focus[0], data.focus[1]]
  var screens = data.screens && typeof data.screens === "object" ? data.screens : {}
  for (var block in screens) {
    if (!positive(Number(block))) continue
    var entry = screens[block] && typeof screens[block] === "object" ? screens[block] : {}
    memory.screens[String(Number(block))] = {
      shown: validHome(entry.shown) ? [entry.shown[0], entry.shown[1]] : null,
      own: positive(entry.own) ? entry.own : null
    }
  }
  return memory
}

// The same memory always gives the same text, so an unchanged memory is never
// rewritten.
function serialize(memory) {
  var blocks = Object.keys(memory.screens).map(Number).sort(function(left, right) { return left - right })
  var screens = {}
  for (var i = 0; i < blocks.length; i++) {
    var entry = memory.screens[String(blocks[i])]
    screens[String(blocks[i])] = { shown: entry.shown, own: entry.own }
  }
  return JSON.stringify({ session: memory.session, focus: memory.focus, screens: screens }, null, 2) + "\n"
}

// What a stable snapshot says to remember. Stable is the caller's call, by
// layout signature: a snapshot taken as a screen comes or goes shows where
// Hyprland put focus, not where you did.
//
// A snapshot is { monitors: [{ name, description, focused, active, x, y,
// width, height }], workspaces: [{ name, monitor }] }, `active` being the name
// of the workspace the screen shows.
//
// `focus` becomes the home of the focused screen's workspace, and is left as
// it was when that is not one of ours. Each connected screen with a block gets
// `shown`, and `own` when it shows one of its own native slots. A screen that
// is not connected keeps its entry: that is what a replug restores from.
function record(memory, snapshot, blocks, session) {
  var next = memory && memory.session === String(session)
    ? parse(serialize(memory), session) : emptyMemory(session)

  for (var i = 0; i < snapshot.monitors.length; i++) {
    var monitor = snapshot.monitors[i]
    var home = homeOf(monitor.active, blocks)
    if (monitor.focused && home) next.focus = home

    var block = Number(blocks[monitorKey(monitor, snapshot.monitors)])
    if (!(block > 0)) continue
    var entry = next.screens[String(block)] || { shown: null, own: null }
    if (home) entry.shown = home
    if (home && home[0] === block && !guestOrigin(monitor.active)) entry.own = home[1]
    next.screens[String(block)] = entry
  }
  return next
}
