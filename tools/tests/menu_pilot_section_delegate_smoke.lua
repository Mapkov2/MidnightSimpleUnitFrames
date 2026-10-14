-- Shared section chrome stays a separate owner; the pilots delegate unchanged.
local root, flavor = assert(arg[1]), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local OwnerAssert = assert(loadfile(root .. "/tools/tests/menu_button_owner_assert.lua"))()
local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true })
local M, env, core = mw.M, mw.env, mw.core
local F = core.ProfileFields
-- Give the real factory memo an explicit alpha value so its Custom marker has
-- a seeded comparison field. Sparse factory fields intentionally have no badge.
local factory = F.CopySnapshot(env.MSUF_DB)
for _, conf in pairs(factory) do
    if type(conf) == "table" and conf.enabled ~= nil then conf.hpBarAlpha = 1 end
end
core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
    if env.MSUF_DB[unit] then env.MSUF_DB[unit].enabled = true end
end
core.ProfileRuntime.Apply = function() end
env.MSUF_UFCore_NotifyConfigChanged = function() end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
local checks = 0
local function Open(entry)
    local button = assert(entry._msuf2SectionActions)
    local popup = button._msuf2GetSectionPopup()
    if popup and popup:IsShown() then button:Click() end
    button:Click()
    popup = assert(button._msuf2GetSectionPopup())
    assert(popup:IsShown(), "pilot section failed to delegate popup open")
    return popup
end
for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
    local page = "uf_" .. unit
    if M.pages[page] then
        assert(mw:Select(page))
        for _, id in ipairs({ "transparency", "range_fade" }) do
            local section = M.cache[page].sections[id]
            if section then
                local entry = section._msuf2CollapsibleEntry
                entry.SetOpenImmediate(true)
                mw:RunTimers()
                if M.ControlSchema then
                    local spec = assert(entry.header._msuf2ControlSchema)
                    OwnerAssert.Button(entry.header, spec)
                end
                if id == "range_fade" then
                    assert(not entry._msuf2SectionActions, "Range Fade acquired unrelated shared section chrome")
                else
                local key = "hpBarAlpha"
                local _, control = M.RuntimeControlCatalog.FindBySettingKey(unit .. "." .. key, page)
                local original = control._msuf2CommandAction.get()
                control._msuf2CommandAction.set(.25)
                assert(env.MSUF_DB[unit][key] == .25, "pilot input failed before testing shared delegation")
                M.Refresh(M.cache[page].ctx)
                local badge = assert(entry._msuf2CustomBadge, "pilot custom marker missing: " .. page .. "." .. id)
                local expanded = entry.open
                MenuWorld.FireScript(badge, "OnMouseUp", "LeftButton")
                assert(entry.open ~= expanded, "custom badge stopped delegating to its header")
                entry.SetOpenImmediate(true)
                local popup = Open(entry)
                local labels, selector, close = {}, nil, nil
                for _, w in ipairs(mw.world.widgets.frames) do
                    if w:GetParent() == popup then
                        local label = w._msuf2Label and w._msuf2Label:GetText()
                        if label then labels[label] = w end
                        if w.SetOnValueChanged and w.SetValues then selector = w end
                    end
                end
                assert(labels["x"] and labels["Reset section"] and labels["Copy section"] and selector,
                    "real shared popup control set incomplete")
                local values = selector.GetValues and selector:GetValues() or selector.values or selector._msuf2Values
                assert(#values > 0, "pilot lost supported section targets")
                for _, value in ipairs(values) do
                    assert(value.value ~= unit and M.pages["uf_" .. value.value], "popup offered unsupported/source target")
                end
                M.ClearHistory()
                local before = F.CopySnapshot(env.MSUF_DB)
                core.Util.InCombat("PLAYER_REGEN_DISABLED")
                labels["Reset section"]:Click()
                assert(F.Equal(before, env.MSUF_DB) and not M.Undo(), "shared reset bypassed combat/history owner")
                core.Util.InCombat("PLAYER_REGEN_ENABLED")
                labels["Reset section"]:Click()
                assert(env.MSUF_DB[unit][key] == factory[unit][key] and not popup:IsShown(),
                    "pilot reset delegated to wrong fields: " .. unit .. ":" .. tostring(env.MSUF_DB[unit][key]))
                assert(M.Undo() and F.Equal(before, env.MSUF_DB), "section reset undo lost pilot fields")
                assert(M.Redo() and env.MSUF_DB[unit][key] == factory[unit][key], "section reset redo lost pilot fields")
                popup = Open(entry)
                labels["x"]:Click()
                assert(not popup:IsShown(), "real section close stopped working")
                assert(Open(entry) == popup, "shared popup lost reuse after reopen")
                labels["x"]:Click()
                -- The actual late callback rejects a disabled or unsupported destination.
                before = F.CopySnapshot(env.MSUF_DB)
                assert(popup._msuf2CopySection("invalid") == false and F.Equal(before, env.MSUF_DB))
                checks = checks + 1
                end
            end
        end
    end
end
print("menu_pilot_section_delegate_smoke " .. flavor .. ": " .. checks .. " real section/badge/popup/reset/undo/refusal routes OK")
