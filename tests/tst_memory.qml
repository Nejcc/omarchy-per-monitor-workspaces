import QtQuick
import QtTest
import "../memory.js" as Memory

// The hotplug memory's decisions, on snapshots shaped like the ones logged
// while testing on a laptop (eDP-1, "BOE", block 1) with a U2725QE ("U27",
// block 2) and a P2715Q ("P27", block 3) on a dock. Run with
//
//   QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -platform offscreen -input tests/tst_memory.qml
TestCase {
  name: "Memory"

  readonly property var blocks: ({ "BOE": 1, "U27": 2, "P27": 3 })
  readonly property string session: "session-a"

  function screen(name, description, active, focused, x) {
    return { name: name, description: description, active: active, focused: !!focused,
             x: x || 0, y: 0, width: 1600, height: 900 }
  }

  function space(name, monitor) {
    return { name: name, monitor: monitor }
  }

  function snapshot(monitors, workspaces) {
    return { monitors: monitors, workspaces: workspaces }
  }

  function memory(focus, screens) {
    return { session: session, focus: focus, screens: screens }
  }

  // Docked, focus on the U2725QE's slot 2.
  function docked() {
    return snapshot(
      [screen("eDP-1", "BOE", "BOE:3", false, 0),
       screen("DP-6", "U27", "U27:2", true, 1600),
       screen("DP-4", "P27", "P27:1", false, 4160)],
      [space("BOE:2", "eDP-1"), space("BOE:3", "eDP-1"),
       space("U27:1", "DP-6"), space("U27:2", "DP-6"),
       space("P27:1", "DP-4")])
  }

  // What recording docked() gives.
  function dockedMemory() {
    return memory([2, 2], {
      "1": { shown: [1, 3], own: 3 },
      "2": { shown: [2, 2], own: 2 },
      "3": { shown: [3, 1], own: 1 }
    })
  }

  // ---------------------------------------------------------------- names

  function test_baseName_strips_only_the_trailer() {
    compare(Memory.baseName("BOE:5#2.2"), "BOE:5")
    compare(Memory.baseName("BOE:5"), "BOE:5")
    compare(Memory.baseName("a#b:5"), "a#b:5")
  }

  function test_guestOrigin_reads_the_trailer() {
    compare(Memory.guestOrigin("BOE:5#2.2"), { block: 2, slot: 2 })
    compare(Memory.guestOrigin("BOE:5"), null)
  }

  function test_parseSlot_takes_plain_integers_below_100_only() {
    compare(Memory.parseSlot("3"), 3)
    compare(Memory.parseSlot("99"), 99)
    compare(Memory.parseSlot("100"), 0)
    compare(Memory.parseSlot("0"), 0)
    compare(Memory.parseSlot("+3"), 0)
    compare(Memory.parseSlot("0x10"), 0)
    compare(Memory.parseSlot("3.0"), 0)
    compare(Memory.parseSlot("Infinity"), 0)
  }

  function test_splitSlot_finds_key_and_slot() {
    compare(Memory.splitSlot("U27:2"), { key: "U27", slot: 2 })
    compare(Memory.splitSlot("BOE:5#2.2"), { key: "BOE", slot: 5 })
    compare(Memory.splitSlot("a:b:3"), { key: "a:b", slot: 3 })
    compare(Memory.splitSlot("1"), null)
    compare(Memory.splitSlot(":3"), null)
    compare(Memory.splitSlot("special:scratchpad"), null)
  }

  function test_monitorKey_is_the_description_unless_twinned() {
    var alone = [{ name: "DP-1", description: "U27" }, { name: "eDP-1", description: "BOE" }]
    compare(Memory.monitorKey(alone[0], alone), "U27")

    var twins = [{ name: "DP-1", description: "Twin" }, { name: "DP-2", description: "Twin" }]
    compare(Memory.monitorKey(twins[0], twins), "Twin@DP-1")
    compare(Memory.monitorKey(twins[1], twins), "Twin@DP-2")

    var blank = [{ name: "HDMI-A-1", description: "" }]
    compare(Memory.monitorKey(blank[0], blank), "HDMI-A-1")
  }
}
