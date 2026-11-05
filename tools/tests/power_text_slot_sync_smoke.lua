-- Real Options bindings share Player power slot selection, size and history.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { page = "uf_player", beforeCore = function(world)
    for _, name in ipairs({ "AbbreviateNumbers", "AbbreviateLargeNumbers", "BreakUpLargeNumbers" }) do
        world.env[name] = function(value) return tostring(value) end
    end
    if not arg[3] then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        if path:match("MSUF_Menu2_AdvancedClassPower") or path:match("MSUF_Menu2_ClassPowerWorkspace.lua$")
            or path:match("MSUF_Menu2_UnitSectionShared.lua$") or path:match("MSUF_Menu2_UnitText.lua$")
            or path:match("MSUF_Menu2_ClassPowerPreview.lua$") then path = arg[3] .. path:sub(#root + 1) end
        return load(self, path, addon, ns)
    end
end })
local M, env, checks = mw.M, mw.env, 0
-- This binding test records the apply boundary; native-frame application has its own fixtures.
local fontRequests = 0
M.ApplyService.RequestUnit = function(_, _, opts)
    if opts and opts.fonts and opts.text then fontRequests = fontRequests + 1 end
    return true
end
M.ApplyService.RequestClassPower = function(_, _, opts)
    if opts and opts.fonts and opts.text then fontRequests = fontRequests + 1 end
    return true
end
M.ApplyService.RequestGeneral = function() return true end
if mw.core.ApplyService then
    mw.core.ApplyService.RequestUnitDomains = M.ApplyService.RequestUnit
    mw.core.ApplyService.RequestClassPowerDomains = M.ApplyService.RequestClassPower
    mw.core.ApplyService.RequestGeneralDomains = M.ApplyService.RequestGeneral
end
local function Check(ok, message) checks = checks + 1 assert(ok, flavor .. ": " .. message) end
local function Expand()
    for _, section in pairs(M.cache[M.activeKey].sections) do
        local entry = section._msuf2CollapsibleEntry
        if entry then entry.SetOpenImmediate(true) end
    end
    mw:RunTimers()
end
local function Find(id)
    for _, widget in ipairs(mw.world.widgets.frames) do
        local meta = widget._msuf2SearchMeta
        local command = widget._msuf2CommandAction
        if command and (command.controlId == id or (meta and meta.controlId == id)) then return widget end
    end
    error("missing control " .. id)
end
local function Choose(widget, value)
    for _, button in ipairs(widget.buttons or {}) do
        if button._msuf2Value == value then button:Click("LeftButton") mw:RunTimers() return end
    end
    error("missing slot choice " .. value)
end
local function Set(widget, value)
    widget:SetValue(value)
    MW.FireScript(widget, "OnValueChanged", value)
    mw:RunTimers()
end
local unitPrefix = "menu2.uf_player.unit.text.power."
local cpPrefix = "menu2.classpower.advanced.detached.power.text."
local function Player() return env.MSUF_DB.player end
Expand()
local F = mw.core.ProfileFields
local factory = F.CopySnapshot(env.MSUF_DB)
mw.core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
local player = Player()
player.powerBarDetached, player.detachedPowerBarTextOnBar, player.showPowerText = true, true, true
player.showPower = true
player.detachedPowerBarAnchorToClassPower = true
player.powerTextLeft, player.powerTextCenter, player.powerTextRight = "CURRENT", "CURMAX", "PERCENT"
player.powerFontSize = 14
player.powerTextLeftFontSize, player.powerTextCenterFontSize, player.powerTextRightFontSize = 19, 21, 23
local unitSlot, unitSize = Find(unitPrefix .. "slot_selector"), Find(unitPrefix .. "slot.size")
Choose(unitSlot, "left")
mw:Select("classpower")
local ui = M.ClassPowerWorkspace.current
ui:Select("power")
Expand()
local cpSlot, cpSize = Find(cpPrefix .. "slot.selector"), Find(cpPrefix .. "size")
Check(cpSlot._msuf2CommandAction.get() == "left", "Class Resources did not inherit Player's selected slot")
for index, slot in ipairs({ "left", "center", "right" }) do
    local key = M.TextSlotFontSizeKey("power", slot)
    Choose(cpSlot, slot)
    Check(cpSize._msuf2CommandAction.get() == Player()[key], "Class Resources size ignored selected slot")
    local otherKey = M.TextSlotFontSizeKey("power", slot == "left" and "right" or "left")
    local otherSize = Player()[otherKey]
    Set(cpSize, 28 + index)
    Check(Player()[key] == 28 + index and Player()[otherKey] == otherSize, "size write missed slot or changed another slot")
    Check(Player().powerFontSize == 14, "slot size replaced the inherited base size")
    local preview = M.cache.classpower.classPowerPreview
    preview:Refresh()
    local text = preview.detachedPower[slot]
    local _, size = text:GetFont()
    Check(size == 28 + index, "Class Resources preview ignored " .. slot .. " size")
    mw:Select("uf_player") mw:RunTimers()
    Check(unitSlot._msuf2CommandAction.get() == slot and unitSize._msuf2CommandAction.get() == 28 + index,
        "Player page did not reflect Class Resources size/slot")
    Set(unitSize, 34 + index)
    mw:Select("classpower") ui:Select("power") mw:RunTimers()
    Check(cpSize._msuf2CommandAction.get() == 34 + index, "Class Resources did not reflect Player size")
end
local before = Player().powerTextRightFontSize
Set(cpSize, 45)
Check(M.Undo() and Player().powerTextRightFontSize == before, "size Undo did not restore selected slot")
Check(M.Redo() and Player().powerTextRightFontSize == 45, "size Redo did not restore selected slot")
ui = M.ClassPowerWorkspace.current
Check(ui:Copy("class", { text = true }), "copy selected power text size failed")
Check(env.MSUF_DB.bars.classPowerFontSize == 32, "copy used stale base font size instead of selected slot (32 cap)")
ui:Select("class")
env.MSUF_DB.bars.classPowerFontSize = 26
Check(ui:Copy("power", { text = true }) and Player().powerTextRightFontSize == 26, "copy into power was masked by slot override")
ui:Select("power")
Choose(cpSlot, "center")
Player().powerTextCenterFontSize, Player().powerFontSize = nil, nil
env.MSUF_DB.general.powerFontSize = 17
Check(cpSize._msuf2CommandAction.get() == 17, "base font inheritance failed")
env.MSUF_DB.general.powerTextCenterFontSize = 24
Check(cpSize._msuf2CommandAction.get() == 24, "inherited per-slot size ignored")
mw:Select("uf_player") mw:RunTimers()
Check(unitSize._msuf2CommandAction.get() == 24, "Player page disagrees on inherited slot size")
mw:Select("classpower") ui:Select("power") mw:RunTimers()
local target = { controlId = cpPrefix .. "size", settingKey = "player.powerTextLeftFontSize",
    sectionId = "classpower_detached_power_text", prepareKind = "classPowerWorkspace", prepareValue = "power" }
local selected, found, exact = M.Search._RoutingAPI.OpenSearchTarget("classpower", "", "", nil, nil, target)
Check(selected and found and exact and cpSlot._msuf2CommandAction.get() == "left", "exact slot-size search edits another slot")
for _, slot in ipairs({ "Left", "Center", "Right" }) do
    Check(ui.keys.power["player.powerText" .. slot .. "FontSize"], "resource Reset omits " .. slot .. " font size")
end
Check(fontRequests >= 6, "size edits did not request text and font application")
local showPrompt = M.ShowPrompt
M.ShowPrompt = function(_, opts) opts.onAccept() end
Check(ui:Reset(), "resource Reset refused")
M.ShowPrompt = showPrompt
for _, slot in ipairs({ "Left", "Center", "Right" }) do
    local key = "powerText" .. slot .. "FontSize"
    Check(Player()[key] == factory.player[key], "Reset did not restore " .. slot .. " size")
end
Check(M.Undo() and Player().powerTextRightFontSize == 26, "Reset Undo lost the selected slot size")
local beforeCombat = F.CopySnapshot(env.MSUF_DB)
mw.world:EnterCombat()
Set(cpSize, 47)
Check(F.Equal(beforeCombat, env.MSUF_DB), "slot size write bypassed combat refusal")
mw.world:LeaveCombat()
print("power_text_slot_sync_smoke " .. flavor .. ": " .. checks .. " checks passed")
