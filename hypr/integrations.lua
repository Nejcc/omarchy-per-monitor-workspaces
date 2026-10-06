-- Optional consumers own their adapters; the core never imports another plugin.
return function(resolve_workspace)
  local modules = {}
  local api = { version = 1, resolve_workspace = resolve_workspace, errors = {} }

  function api.register(id, module)
    assert(type(id) == "string" and id ~= "", "integration id must be a nonempty string")
    assert(type(module) == "table" and type(module.workspaces_remapped) == "function",
      "integration needs a workspaces_remapped callback")
    modules[id] = module -- Reloading an adapter replaces its old callback.
  end

  function api.unregister(id)
    modules[id], api.errors[id] = nil, nil
  end

  function api.notify_remap(mapping)
    if not next(mapping) then return end
    local pending = {}
    for id, module in pairs(modules) do pending[id] = module end
    for id, module in pairs(pending) do
      local copy = {}
      for from, to in pairs(mapping) do copy[from] = to end
      local ok, err = pcall(module.workspaces_remapped, copy)
      api.errors[id] = not ok and tostring(err) or nil
    end
  end

  return api
end
