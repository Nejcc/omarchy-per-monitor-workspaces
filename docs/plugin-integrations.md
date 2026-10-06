# Proposal: optional plugin integrations

I want Pocket, Motions and per-monitor workspaces to cooperate while keeping
per-monitor fully usable on its own. This adds a small Lua integration API.
The core imports no other plugin, adds no required dependencies or keybindings,
and keeps the upstream plugin ID, install instructions and attribution.

Each consumer owns its adapter. There is no plugin discovery service or module
installation system. The provider exposes capabilities; an installed consumer
can opt in, and falls back to its ordinary behavior when they are absent.

## Contract

`per_monitor_workspaces.integration` provides API version `1`:

* `resolve_workspace(name)` uses the same resolver as `selector(name)`, including
  guest slots and numeric workspace IDs. Like the existing selector, it may
  allocate a block or register a default-name rule. It is not a read-only query.
* `register(id, module)` attaches a module with a `workspaces_remapped(mapping)`
  callback. Registering the same ID replaces the previous callback.
* `unregister(id)` disconnects that module.
* `errors[id]` holds the most recent callback error; a later successful callback
  clears it. A broken consumer does not interrupt other consumers or the core.

Callbacks receive a separate table mapping old workspace names to final names.
The provider sends a single batch after a workspace-set swap, a visible swap,
or a relocation through `relocate` (including the widget's hotplug recovery).
Scratch names are never published. Configured empty slots are included in a
set swap, because a Pocket window may remember a home that is currently empty.
Apply each mapping once; following chained entries would undo a two-way swap.

Notifications describe actions performed through this plugin. Native workspace
renames made outside it do not emit this callback. This first version does not
provide a shared QML workspace snapshot or automatically refresh Motions panels.

```lua
local pmw = per_monitor_workspaces
local api = pmw and pmw.integration
if api and api.version == 1 then
  api.register("my.plugin", {
    workspaces_remapped = function(mapping)
      -- Update the consumer's saved workspace references once per mapping.
    end,
  })
end
```

## Pocket and Motions adapters

The accompanying Pocket change keeps its adapter in
`integrations/per-monitor.lua`. It rewrites saved home tags when a workspace
moves or swaps. Its special workspaces and terminal behavior stay independent.
The accompanying Motions change resolves dispatch targets through the versioned
API, falling back to the older `selector` API or a native name selector.

Load per-monitor before Pocket for automatic attachment. If Pocket loads first,
add this after both plugin loaders in the Hyprland Lua configuration:

```lua
if pocket and pocket.connect_workspaces then pocket.connect_workspaces() end
```

The call is safe when per-monitor is absent or predates this API. Repeat it as
part of config loading on reload: callbacks belong to the current Lua state.
Per-monitor never loads or enables Pocket or Motions itself.

## Verification

```sh
lua tests/names_test.lua
lua tests/integrations_test.lua
lua tests/swap_sets_test.lua
```

Offline checks cover standalone use, registration replacement, removal, callback
failure isolation, final-name batch delivery and hotplug relocation. Consumer
repositories cover Pocket with and without the provider, either load order,
and Motions with the new API, the old API and no provider. A live two-monitor
Hyprland check remains necessary before release.
