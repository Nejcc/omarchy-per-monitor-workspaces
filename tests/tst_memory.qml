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
    return { name: name, monitor: monitor, windows: 1 }
  }

  // What Hyprland hands a screen with nothing else to show: a bare-numbered
  // workspace, new and so empty.
  function placeholder(name, monitor) {
    return { name: name, monitor: monitor, windows: 0 }
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
    var onPlaceholder = snapshot(
      [screen("eDP-1", "BOE", "1", true)],
      [placeholder("1", "eDP-1"), space("BOE:3", "eDP-1")])
    var next = Memory.record(dockedMemory(), onPlaceholder, blocks, session)
    compare(next.focus, [2, 2])
    compare(next.screens["1"], { shown: [1, 3], own: 3 })
  }

  function test_record_starts_over_in_another_session() {
    var next = Memory.record(dockedMemory(), docked(), blocks, "session-b")
    compare(next.session, "session-b")
    compare(next.focus, [2, 2])
  }

  // ------------------------------------------------------- locate, ready

  function test_locate_prefers_the_one_on_screen_when_two_share_a_home() {
    var both = snapshot(
      [screen("eDP-1", "BOE", "BOE:7#2.2", true)],
      [space("BOE:5#2.2", "eDP-1"), space("BOE:7#2.2", "eDP-1")])
    compare(Memory.locate([2, 2], both, blocks).name, "BOE:7#2.2")
    compare(Memory.locate([2, 9], both, blocks), null)
    compare(Memory.locate(null, both, blocks), null)
  }

  function test_ready_waits_for_absorb() {
    var parked = snapshot([screen("eDP-1", "BOE", "BOE:3", true)],
      [space("BOE:3", "eDP-1"), space("U27:2", "eDP-1")])
    verify(!Memory.ready(parked, blocks))

    var absorbed = snapshot([screen("eDP-1", "BOE", "BOE:3", true)],
      [space("BOE:3", "eDP-1"), space("BOE:4#2.2", "eDP-1")])
    verify(Memory.ready(absorbed, blocks))
  }

  function test_ready_waits_for_reclaim() {
    var returning = docked()
    returning.workspaces.push(space("BOE:5#2.3", "DP-6"))
    verify(!Memory.ready(returning, blocks))
  }

  function test_ready_waits_for_adopt() {
    var stranded = docked()
    stranded.workspaces.push(space("U27:3", "eDP-1"))
    verify(!Memory.ready(stranded, blocks))
  }

  function test_ready_ignores_what_nothing_will_move() {
    var odd = docked()
    odd.workspaces.push(placeholder("1", "eDP-1"))
    odd.workspaces.push(space("special:scratchpad", "DP-6"))
    odd.workspaces.push(space("Gone:3", "eDP-1"))
    verify(Memory.ready(odd, blocks))
  }

  // ----------------------------------------------------------------- plan

  function test_plan_is_idle_when_everything_is_in_place() {
    compare(Memory.plan(dockedMemory(), docked(), blocks), {
      moves: [], focus: { monitor: "DP-6", workspace: "U27:2" }, idle: true
    })
  }

  // The dock drops the P2715Q first, and Hyprland moves focus to the laptop.
  function test_plan_dock_unplug_first_drop_puts_focus_back() {
    var after = snapshot(
      [screen("eDP-1", "BOE", "BOE:3", true, 0), screen("DP-6", "U27", "U27:2", false, 1600)],
      [space("BOE:2", "eDP-1"), space("BOE:3", "eDP-1"), space("BOE:4#3.1", "eDP-1"),
       space("U27:1", "DP-6"), space("U27:2", "DP-6")])
    compare(Memory.plan(dockedMemory(), after, blocks), {
      moves: [], focus: { monitor: "DP-6", workspace: "U27:2" }, idle: false
    })
  }

  // Then the U2725QE goes too, and its slot 2 is taken in as laptop slot 6.
  function test_plan_dock_unplug_second_drop_follows_the_workspace() {
    var after = snapshot(
      [screen("eDP-1", "BOE", "BOE:3", true)],
      [space("BOE:2", "eDP-1"), space("BOE:3", "eDP-1"), space("BOE:4#3.1", "eDP-1"),
       space("BOE:5#2.1", "eDP-1"), space("BOE:6#2.2", "eDP-1")])
    compare(Memory.plan(dockedMemory(), after, blocks), {
      moves: [{ monitor: "eDP-1", workspace: "BOE:6#2.2", exists: true }],
      focus: { monitor: "eDP-1", workspace: "BOE:6#2.2" },
      idle: false
    })
  }

  function test_plan_single_unplug_of_the_focused_screen() {
    var before = memory([3, 1], dockedMemory().screens)
    var after = snapshot(
      [screen("eDP-1", "BOE", "BOE:3", true, 0), screen("DP-6", "U27", "U27:2", false, 1600)],
      [space("BOE:2", "eDP-1"), space("BOE:3", "eDP-1"), space("BOE:4#3.1", "eDP-1"),
       space("U27:1", "DP-6"), space("U27:2", "DP-6")])
    compare(Memory.plan(before, after, blocks), {
      moves: [{ monitor: "eDP-1", workspace: "BOE:4#3.1", exists: true }],
      focus: { monitor: "eDP-1", workspace: "BOE:4#3.1" },
      idle: false
    })
  }

  // Undocked on the U2725QE's slot 2, which it was not showing when it left:
  // focus wins over its remembered slot 1, and the laptop goes back to its 3.
  function test_plan_replug_focus_wins() {
    var before = memory([2, 2], {
      "1": { shown: [2, 2], own: 3 },
      "2": { shown: [2, 1], own: 1 },
      "3": { shown: [3, 1], own: 1 }
    })
    var after = snapshot(
      [screen("eDP-1", "BOE", "BOE:2", true, 0),
       screen("DP-6", "U27", "U27:1", false, 1600),
       screen("DP-1", "P27", "1", false, 4160)],
      [space("BOE:2", "eDP-1"), space("BOE:3", "eDP-1"), placeholder("1", "DP-1"),
       space("U27:1", "DP-6"), space("U27:2", "DP-6"), space("P27:1", "DP-1")])
    compare(Memory.plan(before, after, blocks), {
      moves: [{ monitor: "DP-1", workspace: "P27:1", exists: true },
              { monitor: "DP-6", workspace: "U27:2", exists: true },
              { monitor: "eDP-1", workspace: "BOE:3", exists: true }],
      focus: { monitor: "DP-6", workspace: "U27:2" },
      idle: false
    })
  }

  // a2: the laptop's own slots were emptied while undocked, and its last
  // guest has gone home, leaving Hyprland's placeholder.
  function test_plan_replaces_a_placeholder() {
    var before = memory([2, 2], {
      "1": { shown: [2, 2], own: 3 },
      "2": { shown: [2, 2], own: 2 }
    })
    var after = snapshot(
      [screen("eDP-1", "BOE", "1", false, 0), screen("DP-6", "U27", "U27:2", true, 1600)],
      [placeholder("1", "eDP-1"), space("U27:1", "DP-6"), space("U27:2", "DP-6")])
    compare(Memory.plan(before, after, blocks), {
      moves: [{ monitor: "eDP-1", workspace: "BOE:1", exists: false }],
      focus: { monitor: "DP-6", workspace: "U27:2" },
      idle: false
    })
  }

  function test_plan_keeps_a_guest_on_a_screen_the_hotplug_left_alone() {
    var before = memory([3, 1], {
      "1": { shown: [2, 2], own: 3 },
      "3": { shown: [3, 1], own: 1 }
    })
    var after = snapshot(
      [screen("eDP-1", "BOE", "BOE:5#2.2", false, 0), screen("DP-4", "P27", "P27:1", true, 1600)],
      [space("BOE:3", "eDP-1"), space("BOE:5#2.2", "eDP-1"), space("P27:1", "DP-4")])
    compare(Memory.plan(before, after, blocks), {
      moves: [], focus: { monitor: "DP-4", workspace: "P27:1" }, idle: true
    })
  }

  function test_plan_lets_focus_be_when_its_workspace_has_closed() {
    var before = memory([2, 5], dockedMemory().screens)
    compare(Memory.plan(before, docked(), blocks), { moves: [], focus: null, idle: true })
  }

  // b: the guest was sent home to slot 3 because its slot 2 was taken. Its
  // home no longer leads to it; the one now holding slot 2 is focused instead.
  function test_plan_after_nearest_free_focuses_the_slot_holder() {
    var after = docked()
    after.workspaces.push(space("U27:3", "DP-6"))
    compare(Memory.plan(dockedMemory(), after, blocks).focus, { monitor: "DP-6", workspace: "U27:2" })
  }

  // Nothing remembered -- a first start, or a file from another session: no
  // screen is moved off one of its own slots, and a placeholder gets slot 1.
  function test_plan_with_no_memory_keeps_screens_where_they_are() {
    var first = docked()
    first.monitors[2].active = "3"
    first.workspaces.push(placeholder("3", "DP-4"))
    first.workspaces.splice(4, 1)
    compare(Memory.plan(Memory.emptyMemory(session), first, blocks), {
      moves: [{ monitor: "DP-4", workspace: "P27:1", exists: false }],
      focus: null,
      idle: false
    })
  }

  function test_plan_gives_a_screen_with_no_block_its_slot_1() {
    var fresh = docked()
    fresh.monitors.push(screen("HDMI-A-1", "New Panel", "4", false, 5760))
    fresh.workspaces.push(placeholder("4", "HDMI-A-1"))
    compare(Memory.plan(dockedMemory(), fresh, blocks).moves,
      [{ monitor: "HDMI-A-1", workspace: "New Panel:1", exists: false }])
  }

  function test_plan_keys_twin_panels_by_connector() {
    var twinBlocks = { "BOE": 1, "Twin@DP-1": 4, "Twin@DP-2": 5 }
    var twins = snapshot(
      [screen("eDP-1", "BOE", "BOE:1", true, 0),
       screen("DP-1", "Twin", "Twin@DP-1:2", false, 1600),
       screen("DP-2", "Twin", "2", false, 3200)],
      [space("BOE:1", "eDP-1"), space("Twin@DP-1:2", "DP-1"), space("Twin@DP-2:1", "DP-2"),
       placeholder("2", "DP-2")])
    compare(Memory.plan(memory([1, 1], {}), twins, twinBlocks).moves,
      [{ monitor: "DP-2", workspace: "Twin@DP-2:1", exists: true }])
  }

  // --------------------------------------------- outside the scheme, guests

  // A workspace this plugin did not name -- a window rule's "9", a script's --
  // that you are using. Not a placeholder: it holds windows.
  function onNine() {
    var nine = docked()
    nine.monitors[1].active = "9"
    nine.workspaces.push(space("9", "DP-6"))
    return nine
  }

  function test_record_forgets_focus_on_a_workspace_outside_the_scheme() {
    var next = Memory.record(dockedMemory(), onNine(), blocks, session)
    compare(next.focus, null)
    compare(next.screens["2"], { shown: [2, 2], own: 2 })
  }

  function test_plan_restart_on_a_workspace_outside_the_scheme_moves_nothing() {
    var recorded = memory(null, dockedMemory().screens)
    compare(Memory.plan(recorded, onNine(), blocks), { moves: [], focus: null, idle: true })
  }

  function test_plan_keeps_a_workspace_outside_the_scheme_through_a_hotplug() {
    var after = snapshot(
      [screen("eDP-1", "BOE", "9", false, 0), screen("DP-6", "U27", "U27:2", true, 1600)],
      [space("BOE:3", "eDP-1"), space("9", "eDP-1"), space("U27:1", "DP-6"), space("U27:2", "DP-6")])
    compare(Memory.plan(dockedMemory(), after, blocks), {
      moves: [], focus: { monitor: "DP-6", workspace: "U27:2" }, idle: true
    })
  }

  // Nothing remembered, undocked on a guest: the guest is a slot of this
  // screen as much as its own are, and it stays.
  function test_plan_with_no_memory_keeps_a_screen_on_its_guest() {
    var undocked = snapshot(
      [screen("eDP-1", "BOE", "BOE:5#2.2", true)],
      [space("BOE:2", "eDP-1"), space("BOE:3", "eDP-1"), space("BOE:5#2.2", "eDP-1")])
    compare(Memory.plan(Memory.emptyMemory(session), undocked, blocks), { moves: [], focus: null, idle: true })
  }

  // ---------------------------------------------------------------- batch

  function luaString(text) {
    return "\"" + text + "\""
  }

  function luaSelector(name) {
    return "SEL(\"" + name + "\")"
  }

  // Switching to the workspace a screen already shows is, with Hyprland's
  // binds:workspace_back_and_forth, a switch to the previous one. By the end
  // of the batch the remembered workspace is always showing, so the batch has
  // to end on the screen, and never switch to that workspace a second time.
  function test_fixupLua_ends_by_focusing_the_screen() {
    var lua = Memory.fixupLua({
      moves: [{ monitor: "DP-1", workspace: "P27:1", exists: true },
              { monitor: "DP-6", workspace: "U27:2", exists: true }],
      focus: { monitor: "DP-6", workspace: "U27:2" },
      idle: false
    }, luaString, luaSelector)
    verify(/hl\.dispatch\(hl\.dsp\.focus\(\{ monitor = "DP-6" \}\)\);?$/.test(lua.trim()), lua)
    compare(lua.split("workspace = \"name:U27:2\"").length - 1, 1)
  }

  function test_fixupLua_puts_focus_back_without_switching_a_workspace() {
    var lua = Memory.fixupLua({
      moves: [], focus: { monitor: "DP-6", workspace: "U27:2" }, idle: false
    }, luaString, luaSelector)
    compare(lua.indexOf("workspace ="), -1)
    verify(lua.indexOf("monitor = \"DP-6\"") !== -1, lua)
  }

  function test_fixupLua_creates_a_missing_slot_and_hands_focus_back() {
    var lua = Memory.fixupLua({
      moves: [{ monitor: "eDP-1", workspace: "BOE:1", exists: false }], focus: null, idle: false
    }, luaString, luaSelector)
    verify(lua.indexOf("monitor = \"eDP-1\"") < lua.indexOf("workspace = SEL(\"BOE:1\")"), lua)
    verify(/if origin then hl\.dispatch\(hl\.dsp\.focus\(\{ monitor = origin\.name \}\)\) end$/.test(lua), lua)
  }
}
