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

  // ---------------------------------------------------------------- homes

  function test_homeOf_follows_a_workspace_through_the_round_trip() {
    compare(Memory.homeOf("U27:2", blocks), [2, 2])
    compare(Memory.homeOf("BOE:5#2.2", blocks), [2, 2])
  }

  function test_homeOf_is_null_for_anything_not_ours() {
    compare(Memory.homeOf("1", blocks), null)
    compare(Memory.homeOf("special:scratchpad", blocks), null)
    compare(Memory.homeOf("Unknown:3", blocks), null)
    compare(Memory.homeOf("BOE:5#0.2", blocks), null)
  }

  function test_layoutSignature_sees_screens_come_go_and_move() {
    var screens = docked().monitors
    var reordered = [screens[2], screens[0], screens[1]]
    compare(Memory.layoutSignature(reordered), Memory.layoutSignature(screens))

    var moved = docked().monitors
    moved[2].x = 0
    verify(Memory.layoutSignature(moved) !== Memory.layoutSignature(screens))
    verify(Memory.layoutSignature(screens.slice(0, 2)) !== Memory.layoutSignature(screens))
  }

  // --------------------------------------------------------------- freeze

  function freezeState(layout, frozen, fixupDone, waits) {
    return { layout: layout, frozen: frozen, fixupDone: fixupDone, waits: waits }
  }

  function test_freeze_starts_frozen_and_stays_so_until_the_fixup_has_run() {
    var first = Memory.freezeStep(freezeState("", true, false, 0), "A")
    compare(first, freezeState("A", true, false, 0))
    compare(Memory.freezeStep(first, "A"), freezeState("A", true, false, 0))
    compare(Memory.freezeStep(freezeState("A", true, true, 3), "A"), freezeState("A", false, true, 3))
  }

  function test_freeze_on_any_change_of_screens() {
    compare(Memory.freezeStep(freezeState("A", false, true, 0), "B"), freezeState("B", true, false, 0))
    compare(Memory.freezeStep(freezeState("A", true, true, 4), "B"), freezeState("B", true, false, 0))
  }

  function test_freeze_lets_stable_snapshots_through() {
    compare(Memory.freezeStep(freezeState("A", false, true, 0), "A"), freezeState("A", false, true, 0))
  }

  // ---------------------------------------------------------- memory file

  function test_parse_reads_back_what_serialize_writes() {
    var text = Memory.serialize(dockedMemory())
    compare(Memory.parse(text, session), dockedMemory())
    compare(Memory.serialize(Memory.parse(text, session)), text)
  }

  function test_serialize_does_not_depend_on_insertion_order() {
    var forwards = memory(null, { "2": { shown: null, own: 1 }, "10": { shown: null, own: 2 } })
    var backwards = memory(null, { "10": { shown: null, own: 2 }, "2": { shown: null, own: 1 } })
    compare(Memory.serialize(forwards), Memory.serialize(backwards))
  }

  function test_parse_ignores_another_session() {
    var text = Memory.serialize(dockedMemory())
    compare(Memory.parse(text, "session-b"), Memory.emptyMemory("session-b"))
  }

  function test_parse_survives_garbage() {
    compare(Memory.parse("", session), Memory.emptyMemory(session))
    compare(Memory.parse("not json", session), Memory.emptyMemory(session))
    compare(Memory.parse("null", session), Memory.emptyMemory(session))
    compare(Memory.parse("[]", session), Memory.emptyMemory(session))
  }

  function test_parse_drops_fields_of_the_wrong_type() {
    var text = JSON.stringify({
      session: session,
      focus: "2,2",
      screens: { "x": { shown: [1, 1], own: 1 }, "2": { shown: [2, "2"], own: -1 }, "3": "junk" }
    })
    compare(Memory.parse(text, session), memory(null, {
      "2": { shown: null, own: null },
      "3": { shown: null, own: null }
    }))
  }

  // --------------------------------------------------------------- record

  function test_record_takes_focus_and_every_screen() {
    compare(Memory.record(Memory.emptyMemory(session), docked(), blocks, session), dockedMemory())
  }

  function test_record_does_not_change_its_input() {
    var before = dockedMemory()
    var text = Memory.serialize(before)
    var undocked = snapshot([screen("eDP-1", "BOE", "BOE:2", true)], [space("BOE:2", "eDP-1")])
    Memory.record(before, undocked, blocks, session)
    compare(Memory.serialize(before), text)
  }

  function test_record_keeps_own_while_a_guest_is_shown() {
    var undocked = snapshot(
      [screen("eDP-1", "BOE", "BOE:5#2.2", true)],
      [space("BOE:3", "eDP-1"), space("BOE:4#2.1", "eDP-1"), space("BOE:5#2.2", "eDP-1"),
       space("BOE:6#3.1", "eDP-1")])
    compare(Memory.record(dockedMemory(), undocked, blocks, session), memory([2, 2], {
      "1": { shown: [2, 2], own: 3 },
      "2": { shown: [2, 2], own: 2 },
      "3": { shown: [3, 1], own: 1 }
    }))
  }

  function test_record_leaves_focus_alone_on_a_placeholder() {
    var placeholder = snapshot(
      [screen("eDP-1", "BOE", "1", true)],
      [space("1", "eDP-1"), space("BOE:3", "eDP-1")])
    var next = Memory.record(dockedMemory(), placeholder, blocks, session)
    compare(next.focus, [2, 2])
    compare(next.screens["1"], { shown: [1, 3], own: 3 })
  }

  function test_record_starts_over_in_another_session() {
    var next = Memory.record(dockedMemory(), docked(), blocks, "session-b")
    compare(next.session, "session-b")
    compare(next.focus, [2, 2])
  }
}
