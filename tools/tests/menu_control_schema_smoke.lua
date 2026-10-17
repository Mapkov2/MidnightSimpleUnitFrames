-- Real pilot controls: central input bindings, exact navigation and diff history.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local priorSchemaPath = arg[3]
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local OwnerAssert = assert(loadfile(root .. "/tools/tests/menu_button_owner_assert.lua"))()
local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, beforeCore = function(world)
    world.env.GetSpecialization = function() return 1 end
    world.env.GetSpecializationInfo = function() return 62 end
    world.env.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end, GetSpecializationInfo = function() return 62 end,
    }
    -- Optional authentic prior schema is used only for the callback-contract red probe.
    if priorSchemaPath then
        local load = world.LoadFile
        world.LoadFile = function(self, path, ...)
            if path:sub(-#"MSUF_Menu2_ControlSchema.lua") == "MSUF_Menu2_ControlSchema.lua" then path = priorSchemaPath end
            return load(self, path, ...)
        end
    end
    -- Spell tiles use native FlipBook setters; retain their actual assigned state.
    for _, name in ipairs({ "Rows", "Columns", "Frames", "FrameWidth", "FrameHeight" }) do
        local field = "flipBook" .. name
        world.widgets.Methods["SetFlipBook" .. name] = function(frame, value) frame[field] = value end
    end
    world.widgets.Methods.GetCenter = function(frame)
        return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
            (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
    end
end })
local M, env, core = mw.M, mw.env, mw.core
local function Check(value, message) assert(value, flavor .. ": " .. message) return value end
Check(M.ControlSchema, "schema did not load")
local F = core.ProfileFields
local factory = F.CopySnapshot(env.MSUF_DB)
core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
core.ProfileRuntime.Apply = function() end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
-- This smoke proves menu-to-apply requests; native UF rendering has its own fixture.
env.MSUF_UFCore_NotifyConfigChanged = function() end
local function Expand(page)
    for _, section in pairs(M.cache[page].sections) do
        local entry = section._msuf2CollapsibleEntry
        if entry then entry.SetOpenImmediate(true) end
    end
    mw:RunTimers()
    M.Refresh(M.cache[page].ctx)
end
local function Control(key, page)
    local record, widget = M.RuntimeControlCatalog.FindBySettingKey(key, page)
    Check(record and widget, "missing real control " .. key)
    Check(widget._msuf2ControlSchema, "control escaped reviewed declarations: " .. key)
    return widget, record
end
local function Visible(widget)
    while widget do
        if not widget:IsShown() then return false end
        widget = widget:GetParent()
    end
    return true
end
local function Input(widget, value)
    local kind = widget._msuf2ControlSchema.kind
    if kind == "toggle" then
        widget:SetChecked(value)
        widget:Click("LeftButton")
    elseif kind == "slider" then
        widget:SetValue(value)
        MenuWorld.FireScript(widget, "OnValueChanged", value)
    elseif kind == "dropdown" then widget._msuf2OnValueChanged(value)
    elseif kind == "textinput" then widget._msuf2OnCommit(value)
    else error("input kind not covered " .. kind) end
    mw:RunTimers()
end
local unitRequests, gameplayApplies, refreshes = 0, 0, 0
local request, requestDomains, refresh = M.ApplyService.RequestUnit, M.ApplyService.RequestUnitDomains, M.Refresh
-- Menu setters request typed unit domains; the historical signature stays a counted compatibility entry.
M.ApplyService.RequestUnit = function(...)
    unitRequests = unitRequests + 1
    return request(...)
end
M.ApplyService.RequestUnitDomains = function(...)
    unitRequests = unitRequests + 1
    return requestDomains(...)
end
M.Refresh = function(...)
    refreshes = refreshes + 1
    return refresh(...)
end
core.MSUF_RequestGameplayApply = function() gameplayApplies = gameplayApplies + 1 return true end

-- Cold exact search must build a lazy section and reveal the OOC tab without a DB write.
local target = { controlId = "menu2.uf_target.unit.transparency.ooc_fade_alpha",
    settingKey = "target.oocFadeAlpha", sectionId = "transparency", prepareKind = "unitAlphaTab", prepareValue = "ooc" }
local beforeSearch = F.CopySnapshot(env.MSUF_DB)
local selected, found, exact = M.Search._RoutingAPI.OpenSearchTarget("uf_target", "unrelated", "", nil, nil, target)
Check(selected and found and exact, "cold exact OOC search failed")
mw:RunTimers()
-- Base 9c29a35a also initializes adjacent Classic aura fields on a cold unit page
-- (.checks/cold-navigation-Vanilla-baseline.log). Pin every pilot-owned root here.
for _, scope in ipairs({ "target", "bars", "gameplay", "swingTimers" }) do
    Check(F.Equal(beforeSearch[scope], env.MSUF_DB[scope]), "navigation wrote pilot profile fields: " .. scope)
end
local ooc = Control("target.oocFadeAlpha", "uf_target")
Check(Visible(ooc), "exact OOC result is on a hidden tab")
local fade = Control("target.oocFadeEnabled", "uf_target")
Input(fade, true)
Check(env.MSUF_DB.target.oocFadeEnabled == true, "OOC toggle wrote another setting")
Check(ooc:IsEnabled(), "OOC toggle did not refresh its slider")
M.ClearHistory()
local original, requests = env.MSUF_DB.target.oocFadeAlpha, unitRequests
Input(ooc, 0.25)
Check(env.MSUF_DB.target.oocFadeAlpha == 0.25 and unitRequests > requests, "OOC setter did not reach DB/apply")
Check(M.Undo() and env.MSUF_DB.target.oocFadeAlpha == original, "slider undo did not restore original")
Check(M.Redo() and env.MSUF_DB.target.oocFadeAlpha == 0.25, "slider redo lost value")

-- Every supported unit scope owns the same alpha routes; Power uses its explicit adapter.
for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
    local page = "uf_" .. unit
    if M.pages[page] then
        mw:Select(page)
        Expand(page)
        local slider = Control(unit .. ".hpBarAlpha", page)
        requests = unitRequests
        Input(slider, 0.65)
        Check(env.MSUF_DB[unit].hpBarAlpha == 0.65 and unitRequests > requests, unit .. " alpha setting route drift")
        local power = Control(unit .. ".powerBarAlpha", page)
        Input(power, 0.55)
        Check(env.MSUF_DB[unit].powerBarAlpha == 0.55, unit .. " resource alpha setting route drift")
        if unit ~= "player" then
            local enabled = Control(unit .. ".rangeFadeEnabled", page)
            local range = Control(unit .. ".rangeFadeAlpha", page)
            Input(enabled, false)
            Check(env.MSUF_DB[unit].rangeFadeEnabled == false and not range:IsEnabled(), "range gate lost refresh")
            Input(enabled, true)
            Input(range, 0.35)
            Check(env.MSUF_DB[unit].rangeFadeAlpha == 0.35, "range setter route drift")
        end
    end
end

mw:Select("uf_player")
selected, found, exact = M.Search._RoutingAPI.OpenSearchTarget("uf_target", "unrelated", "", nil, nil, target)
Check(selected and found and exact, "warm exact OOC search failed")
mw:RunTimers()
Check(Visible(Control("target.oocFadeAlpha", "uf_target")), "warm exact result stayed on a hidden tab")

mw:Select("gameplay")
Expand("gameplay")
for _, name in ipairs({ "preview", "reset.layout" }) do
    local record = Check(M.RuntimeControlCatalog.Get("menu2.gameplay.advanced.totem.frame." .. name),
        "Totem action missing: " .. name)
    local widget = record.widget
    local declaration = Check(widget._msuf2ControlSchema, "control_declaration missing: Totem " .. name)
    Check(declaration.id == record.controlId and declaration.kind == "button" and declaration.labelKey == record.label,
        "Totem action identity/label drift")
    Check(declaration.scope == "gameplay" and declaration.applyDomain and declaration.gate,
        "Totem action scope/apply/gate missing")
    OwnerAssert.Button(widget, declaration)
    if name == "reset.layout" then
        Check(declaration.actionKey == "reset_player_totems_layout", "Totem reset action key lost")
    end
end
local timer = Control("gameplay.enableCombatTimer", "gameplay")
local size = Control("gameplay.combatFontSize", "gameplay")
Input(timer, true)
Check(size:IsEnabled(), "Gameplay master toggle lost gating")
local applies = gameplayApplies
Input(size, 31)
Check(env.MSUF_DB.gameplay.combatFontSize == 31 and gameplayApplies > applies, "Gameplay DB/apply route drift")
Check(size:GetValue() == 31, "Gameplay refresh did not repaint value")
local enter = Control("gameplay.combatStateEnterText", "gameplay")
Input(enter, "Ready")
Check(env.MSUF_DB.gameplay.combatStateEnterText == "Ready", "Gameplay text input route drift")

-- Combat refusal belongs to the existing input/history path, including the pre-lockdown event edge.
M.ClearHistory()
local combatBefore = F.CopySnapshot(env.MSUF_DB)
core.Util.InCombat("PLAYER_REGEN_DISABLED")
env.InCombatLockdown = function() return false end
Input(size, 32)
Check(F.Equal(combatBefore, env.MSUF_DB), "input wrote during pre-lockdown combat")
Check(not M.Undo(), "refused combat input created a history entry")
fade._msuf2CommandAction.set(false)
Check(env.MSUF_DB.target.oocFadeEnabled == true and ooc:IsEnabled(),
    "refused custom OOC setter changed its enabled-state projection")
core.Util.InCombat("PLAYER_REGEN_ENABLED")

mw:Select("classpower")
M.ClassPowerWorkspace.current:Select("extras")
Expand("classpower")
local mana = Control("bars.manaUpcomingCost", "classpower")
Input(mana, true)
Check(env.MSUF_DB.bars.manaUpcomingCost == true, "resource extras wrote another setting")
local _, extrasBuilt = M.ResourceExtrasPage.ClientOnlySettings()
if extrasBuilt["bars.showIgnorePain"] then
    local master = Control("bars.showIgnorePain", "classpower")
    local stored = env.MSUF_DB.bars.showIgnorePain
    env.MSUF_DB.bars.showIgnorePain = 1
    Check(master._msuf2CommandAction.get() == false, "custom header getter lost its strict boolean policy")
    env.MSUF_DB.bars.showIgnorePain = stored
    local selectedEffect = 0
    local selectEffect = M.ResourceExtrasPreview.Select
    M.ResourceExtrasPreview.Select = function(...) selectedEffect = selectedEffect + 1 return selectEffect(...) end
    env.MSUF_DB.bars.showIgnorePain = false
    master._msuf2CommandAction.set(false)
    Check(selectedEffect > 0, "same-value custom header setter skipped its original preview/apply path")
    M.ResourceExtrasPreview.Select = selectEffect
    env.MSUF_DB.bars.showIgnorePain = stored
end
local add = Check(M.RuntimeControlCatalog.Get("menu2.classpower.advanced.resource.extras.marks.add"), "mark action missing").widget
OwnerAssert.Button(add, assert(add._msuf2ControlSchema))
add:Click("LeftButton")
mw:RunTimers()
local mark = M.RuntimeControlCatalog.Get("menu2.classpower.advanced.resource.extras.marks.width").widget
Input(mark, 7)
Check(env.MSUF_DB.bars.resourceMarks[1].width == 7, "custom selected-rule setter drift")
local mode = M.RuntimeControlCatalog.Get("menu2.classpower.advanced.resource.extras.marks.mode").widget
Input(mode, "ABSOLUTE")
Check(env.MSUF_DB.bars.resourceMarks[1].mode == "ABSOLUTE", "selected-rule dropdown drift")
Check(M.Undo() and env.MSUF_DB.bars.resourceMarks[1].mode == "PERCENT", "custom-rule undo drift")
Check(M.Redo() and env.MSUF_DB.bars.resourceMarks[1].mode == "ABSOLUTE", "custom-rule redo drift")

-- Existing reset ownership and factory copy remain intact after declarations are built.
mw:Select("uf_target")
M.ClearHistory()
local resetBefore = F.CopySnapshot(env.MSUF_DB)
Check(M.ResetPageToDefaults("uf_target"), "unit reset failed")
Check(env.MSUF_DB.target.hpBarAlpha == factory.target.hpBarAlpha, "unit reset omitted alpha schema setting")
Check(M.Undo() and F.Equal(resetBefore, env.MSUF_DB), "unit reset undo changed ownership")
Check(refreshes > 0, "no central refresh was exercised")
-- Group record rows resolve the current scope at input time, even on an existing widget.
M.SetMenuStateValue("gfScope", "party")
local GP = M.GroupPage
for _, scope in ipairs({ "party", "raid" }) do
    GP.Set(scope, "enabled", true, "visual")
    local spells = GP.SpellIndicators(scope)
    spells.enabled = true
    if type(spells.style) ~= "table" then spells.style = {} end
end
Check(mw:Select("gf_auras"), "group aura page missing")
Expand("gf_auras")
local function GroupControl(suffix)
    local found
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        if record.pageKey == "gf_auras" and record.controlId:sub(-#suffix) == suffix then
            Check(not found, "ambiguous group control: " .. suffix)
            found = M.RuntimeControlCatalog.Get(record.controlId).widget
        end
    end
    return Check(found, "group control missing: " .. suffix)
end
-- Real master inputs must refresh the retained Style collector's dependants.
for _, pair in ipairs({
    { "showcooldownswipe", "cooldownswipereverse" },
    { "showcooldowntext", "cooldownsize" },
    { "showstacks", "stacksize" },
    { "showdurationbar", "durationbarheight" },
}) do
    local master = GroupControl("spell.style." .. pair[1])
    local dependant = GroupControl("spell.style." .. pair[2])
    if not master._msuf2CommandAction.get() then Input(master, true) end
    Check(master._msuf2CommandAction.get() == true, "Style master on preparation failed: " .. pair[1])
    Input(master, false)
    Check(master._msuf2CommandAction.get() == false, "Style master off input failed: " .. pair[1])
    Check(not dependant:IsEnabled(), "Style master left dependant enabled: " .. pair[2])
    Input(master, true)
    Check(master._msuf2CommandAction.get() == true, "Style master on input failed: " .. pair[1])
    Check(dependant:IsEnabled(), "Style master left dependant disabled: " .. pair[2])
end
local tooltip = GroupControl("spell.style.showtooltip")
local offset = GroupControl("spell.style.cooldownx")
GP.SpellIndicators("party").style.showTooltip = 0
GP.SpellIndicators("party").style.cooldownX = false
M.Refresh(M.cache.gf_auras.ctx)
Check(tooltip:IsEnabled() and offset:IsEnabled(), "group controls unexpectedly disabled")
Check(tooltip._msuf2CommandAction.get() == false, "strict group toggle treated numeric zero as true")
Check(offset._msuf2CommandAction.get() == 0, "legacy false number did not use the UI fallback")
Check(GP.SpellIndicators("party").style.showTooltip == 0
    and GP.SpellIndicators("party").style.cooldownX == false, "group read materialized legacy field values")
M.ClearHistory()
Input(tooltip, true)
Check(GP.SpellIndicators("party").style.showTooltip == true, "group toggle write drift")
Check(M.Undo() and GP.SpellIndicators("party").style.showTooltip == 0, "group toggle undo erased original numeric zero")
GP.SpellIndicators("party").style.cooldownX = 2
GP.SpellIndicators("raid").style.cooldownX = 9
M.SetMenuStateValue("gfScope", "raid")
M.Refresh(M.cache.gf_auras.ctx)
M.ClearHistory()
Input(offset, 13)
Check(GP.SpellIndicators("raid").style.cooldownX == 13
    and GP.SpellIndicators("party").style.cooldownX == 2, "group input wrote the widget's former scope")
Check(M.Undo() and GP.SpellIndicators("raid").style.cooldownX == 9
    and GP.SpellIndicators("party").style.cooldownX == 2, "group scope undo drift")
Check(M.Redo() and GP.SpellIndicators("raid").style.cooldownX == 13, "group scope redo drift")
M.ClearHistory()
core.Util.InCombat("PLAYER_REGEN_DISABLED")
env.InCombatLockdown = function() return true end
Input(offset, 17)
Check(GP.SpellIndicators("raid").style.cooldownX == 13
    and GP.SpellIndicators("party").style.cooldownX == 2, "combat refusal allowed a group record write")
core.Util.InCombat("PLAYER_REGEN_ENABLED")
env.InCombatLockdown = function() return false end
mw:Fire("PLAYER_REGEN_ENABLED")
mw:RunTimers()

-- Replacing-row callback API: all three owners invoke afterSet with zero arguments.
-- Only the central bind boundary is stubbed here; the real adapter setters run.
local Schema, callbacks = M.ControlSchema, 0
local oldBool = M.BindBoolWidget
M.BindBoolWidget = function(_, widget, get, set) widget.probeSet = set end
local function Meta() return { controlId = "menu2.schema.callback.probe" } end
local function AfterSet(...)
    Check(select("#", ...) == 0, "afterSet received owner-specific arguments")
    callbacks = callbacks + 1
end
local function Probe(options, key, binding)
    local widget = {}
    options.bind(M.cache.gf_auras.ctx, widget, {
        "toggle", key, false, { "Callback probe" }, afterSet = AfterSet, binding = binding,
    }, "toggle")
    Check(widget.probeSet, "callback owner did not bind its setter")(true)
end
local values = { flag = false }
Probe(Schema.GroupRecordOptions({ config = function() return values end,
    scope = function() return "party" end, changed = function() end,
    path = "probe.", meta = Meta, stepMeta = Meta }), "flag")
Check(values.flag == true, "record callback did not follow its write")
values.flag = false
Probe(Schema.GroupSelectedOptions({ selected = function() return { enabled = "flag" } end,
    scope = function() return "party" end, default = function(_, value) return value end,
    bool = function(_, key) return values[key] end, number = function(_, key) return values[key] end,
    value = function(_, key) return values[key] end,
    write = function(_, key, value) values[key] = value end,
    path = "probe.", meta = Meta, stepMeta = Meta }), "enabled")
Check(values.flag == true, "selected callback did not follow its write")
Probe(Schema.GroupOptions(), "ciEnabled", "scopeValue")
M.BindBoolWidget = oldBool
Check(callbacks == 3, "not every replacing callback owner ran")

print("menu_control_schema_smoke " .. flavor .. ": input/DB/apply/refresh/combat/history/reset/exact navigation OK")
