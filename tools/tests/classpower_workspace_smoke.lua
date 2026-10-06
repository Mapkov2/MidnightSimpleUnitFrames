-- The real Options graph owns selection, lazy sections, preview navigation and scoped history.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Forever"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, {
    page = "home",
    beforeCore = function(world)
        -- The shared fixture does not resolve the short native anchor overload.
        -- Geometry has a separate Edit Mode/auto-fit smoke; keep centers numeric here.
        world.widgets.Methods.GetCenter = function(frame)
            return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
                (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
        end
    end,
})
local M, env, F = mw.M, mw.env, mw.core.ProfileFields
local function Check(value, message) assert(value, flavor .. ": " .. message) return value end
local factory = F.CopySnapshot(env.MSUF_DB)
-- The fixture cannot decode the compressed export; current defaults are its factory boundary.
mw.core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end
local before = F.CopySnapshot(env.MSUF_DB)
local target = { controlId = "menu2.classpower.advanced.detached.power.text.size",
    settingKey = "player.powerFontSize", sectionId = "classpower_detached_power_text",
    prepareKind = "classPowerWorkspace", prepareValue = "power" }
local selected, found, exact = M.Search._RoutingAPI.OpenSearchTarget("classpower", "unrelated", "", nil, nil, target)
Check(selected and found and exact, "cold exact search did not materialize Player Power Text")
mw:RunTimers()
Check(F.Equal(before, env.MSUF_DB), "search wrote settings")
local ui = Check(M.ClassPowerWorkspace.current, "workspace missing")
Check(ui.selected == "power", "cold search selected another resource")
Check(ui.selector.buttons and #ui.selector.buttons == 5, "resource top strip missing")
Check(ui.selector._msuf2SearchMeta.kind == "segment", "Editing is still a dropdown")
local header, previewSelector = ui.selector:GetParent(), nil
for _, widget in ipairs(mw.world.widgets.frames) do
    if widget._msuf2StableSearchLabel == "Preview resource" and widget:GetParent() == header then previewSelector = widget end
end
Check(previewSelector, "preview resource selector missing from fixed header")
local _, _, _, _, previewY = previewSelector:GetPoint()
Check(-previewY + previewSelector:GetHeight() <= header:GetHeight(), "preview dropdown exceeds fixed header bounds")
for _, button in ipairs(ui.selector.buttons) do
    local _, _, _, x, y = button:GetPoint()
    Check(x >= 0 and x + button:GetWidth() <= header:GetWidth(), "resource choice exceeds header width")
    Check(-y + button:GetHeight() / 2 < -previewY - 24, "resource choices overlap preview row")
    Check(button._msuf2Label:GetStringWidth() + 24 <= button:GetWidth(), "translated resource choice is clipped")
end
local function CheckSelectedStrip(kind)
    for _, button in ipairs(ui.selector.buttons) do
        Check(button._msuf2Active == (button._msuf2Value == kind), "top strip highlight lost selection")
    end
end
local selectionBefore = F.CopySnapshot(env.MSUF_DB)
for _, button in ipairs(ui.selector.buttons) do
    button:Click("LeftButton")
    Check(ui.selected == button._msuf2Value, "top strip click selects another resource")
    CheckSelectedStrip(ui.selected)
end
Check(F.Equal(selectionBefore, env.MSUF_DB), "top strip navigation wrote settings")
local _,extraSettings=M.ResourceExtrasPage.ClientOnlySettings()
local count = { class = 4, power = 3, hp = 3, mana = 2, extras = extraSettings["bars.showIgnorePain"] and 5 or 2 }
for kind, expected in pairs(count) do
    ui:Select(kind)
    mw:RunTimers()
    Check(#ui.page.b.layoutEntries == expected, kind .. " accordion count")
    Check(ui.selector:GetValue() == kind, "selector lost state")
    CheckSelectedStrip(kind)
    for owner, entries in pairs(ui.entries) do
        for _, entry in ipairs(entries) do Check(entry.outer:IsShown() == (kind == owner), "hidden resource has a visible accordion") end
    end
    Check(ui.copyButton:IsShown() == (kind ~= "extras"), "Copy offered an unsupported resource")
    for _, entry in ipairs(ui.entries[kind]) do entry.SetOpenImmediate(true) end
end
for kind, paths in pairs(ui.keys) do
    for path in pairs(paths) do Check(path:match("^bars%.") or path:match("^player%."), "reset owns a preview/global field") end
end
Check(ui.keys.power["player.powerTextRightOffsetY"], "reset omits per-slot power offsets")
local powerSize
for _, widget in ipairs(mw.world.widgets.frames) do
    local command = widget._msuf2CommandAction
    if command and command.settingKey == "player.powerFontSize" and widget._msuf2PrepareExactSearchTarget then powerSize = widget end
end
Check(powerSize, "power text exact callback missing")
for _, widget in ipairs(mw.world.widgets.frames) do
    local meta = widget._msuf2SearchMeta
    if meta and meta.searchPrepareKind == "classPowerWorkspace" and meta.kind == "dropdown" then
        Check(widget._msuf2StableSearchLabel and meta.label == widget._msuf2StableSearchLabel, "dropdown search label became its selected value: " .. tostring(meta.controlId) .. " " .. tostring(meta.label))
    end
end
ui:Select("hp")
powerSize:_msuf2PrepareExactSearchTarget(target)
Check(ui.selected == "power", "warm exact callback keeps a hidden resource selected")
CheckSelectedStrip("power")
local markSelector
for _, widget in ipairs(mw.world.widgets.frames) do
    local meta = widget._msuf2SearchMeta
    if meta and meta.controlId == "menu2.classpower.advanced.resource.extras.marks.select" then markSelector = widget end
end
Check(markSelector and markSelector._msuf2PrepareExactSearchTarget, "ordinary dropdown exact callback missing")
markSelector:_msuf2PrepareExactSearchTarget()
Check(ui.selected == "extras", "ordinary dropdown exact search keeps another resource selected")
local cached, frames = M.cache.classpower, mw:Frames()
for i = 1, 3 do
    ui:Select("class")
    local shown, anchored, matched = M.Search._RoutingAPI.OpenSearchTarget("classpower", "unrelated", "", nil, nil, target)
    Check(shown and anchored and matched and M.cache.classpower == cached, "warm search rebuilt the resource page")
end
Check(mw:Frames() == frames, "warm search leaked frames")
local db, bars, player = env.MSUF_DB, env.MSUF_DB.bars, env.MSUF_DB.player
bars.showClassPower, bars.classPowerShowText = true, true
bars.playerHPBarEnabled, bars.showAltMana = true, true
player.powerBarDetached, player.detachedPowerBarAnchorToClassPower = true, true
player.showPower, player.showPowerText = true, true
player.detachedPowerBarTextOnBar = true
local box = ui.page.ctx.entry.classPowerPreview
db.general.classPowerPreviewGuidesEnabled = false
box.layerVisibility.guides = false
box:Refresh()
Check(#box.playerRef.regions == 0 and #box.playerRef.children == 0, "player reference artwork remains")
Check(not box.bounds.reference and box.layerVisibility.reference == nil, "player reference participates in bounds/layers")
Check(box.altMana and box.altMana:IsShown() and box.handleMana:IsShown(), "alternative mana sample/hit target missing")
local routes = { { box.handleHP, "hp", "classpower_player_hp" },
    { box.handleHPText, "hp", "classpower_player_hp_text" },
    { box.handlePower, "power", "classpower_detached_power" },
    { box.handlePowerText, "power", "classpower_detached_power_text" },
    { box.handleMana, "mana", "classpower_alt_mana" } }
local previewBefore = F.CopySnapshot(db)
for _, spec in ipairs(routes) do
    Check(spec[1]:IsShown(), "click target requires guides")
    Check(not spec[1]:GetScript("OnDragStart") and not spec[1]:GetScript("OnDragStop"), "preview owns movement")
    spec[1]:Click("LeftButton")
    Check(M.ClassPowerWorkspace.current.selected == spec[2], "preview click selects wrong resource")
    CheckSelectedStrip(spec[2])
    Check(M.cache.classpower.sections[spec[3]]._msuf2CollapsibleEntry.open, "preview click did not open exact section")
end
ui:Select("class")
Check(box.handleHP._msuf2CommandAction.set(), "preview command did not run")
Check(M.ClassPowerWorkspace.current.selected == "hp", "preview command differs from actual click")
Check(F.Equal(previewBefore, env.MSUF_DB), "preview clicks moved or changed resources")
ui = M.ClassPowerWorkspace.current
ui:Select("hp")
bars.playerHPBarWidthMode, bars.playerHPBarWidth, bars.playerHPBarHeight, bars.playerHPBarTextSize = "custom", 1200, 80, 48
bars.classPowerWidth, bars.classPowerHeight, bars.classPowerFontSize = 301, 7, 14
bars.classPowerOffsetX, bars.classPowerOffsetY, bars.showClassPower = 71, -61, false
bars.classPowerTexture = "KEEP"
box:Refresh()
M.SyncExternalHistoryState()
Check(ui:Copy("class", { size = true, text = true }), "copy did not run")
Check(bars.classPowerWidth == 800 and bars.classPowerHeight == 40 and bars.classPowerFontSize == 32, "copy exceeds destination limits")
Check(bars.classPowerWidthMode == "custom", "copied width still follows another source")
Check(bars.classPowerOffsetX == 71 and bars.classPowerOffsetY == -61 and not bars.showClassPower, "copy moved/enabled destination")
Check(bars.classPowerTexture == "KEEP", "unchecked appearance category changed")
M.Undo()
db, bars, player = env.MSUF_DB, env.MSUF_DB.bars, env.MSUF_DB.player
Check(bars.classPowerWidth == 301 and bars.classPowerFontSize == 14, "copy cannot be undone")
ui = M.ClassPowerWorkspace.current
ui:Select("hp")
ui.copyButton:Click("LeftButton")
local popup = Check(ui.copyPopup.GetPopup(), "copy popup missing")
Check(not popup._targetBtns.hp:IsShown(), "copy offers itself")
ui:Select("mana")
Check(not popup:IsShown(), "changing resource leaves stale copy dialog")
Check(not ui:Copy("class", {}), "empty copy changed settings")
local prompt, oldPrompt = nil, M.ShowPrompt
M.ShowPrompt = function(_, spec) prompt = spec end
ui:Select("power")
player.powerTextRightOffsetY, player.nameOffsetX = 123, 456
bars.playerHPBarWidth, bars.altManaWidth = 789, 555
M.SyncExternalHistoryState()
ui:Reset()
Check(prompt and prompt.onAccept, "scoped reset has no confirmation")
prompt.onAccept()
db, bars, player = env.MSUF_DB, env.MSUF_DB.bars, env.MSUF_DB.player
Check(player.powerTextRightOffsetY == factory.player.powerTextRightOffsetY, "power reset skipped slot offset")
Check(player.nameOffsetX == 456 and bars.playerHPBarWidth == 789 and bars.altManaWidth == 555, "reset changed unrelated scope")
Check(db.menu == nil, "reset persisted preview selection")
M.Undo()
Check(env.MSUF_DB.player.powerTextRightOffsetY == 123, "scoped reset cannot be undone")
ui = M.ClassPowerWorkspace.current
local quick
for _, widget in ipairs(mw.world.widgets.frames) do
    if widget._msuf2SearchMeta and widget._msuf2SearchMeta.controlId == "menu2.classpower.advanced.quick.setup.class.bar" then quick = widget end
end
if not quick then
    for _, widget in ipairs(mw.world.widgets.frames) do
        local action = widget._msuf2CommandAction
        if action and action.controlId == "menu2.classpower.advanced.quick.setup.class.bar" then quick = widget end
    end
end
Check(quick, "Quick Setup button missing")
prompt = nil
before = F.CopySnapshot(env.MSUF_DB)
quick:Click("LeftButton")
Check(prompt and prompt.onAccept and prompt.text:find("positions", 1, true), "Quick Setup effects are not confirmed")
Check(F.Equal(before, env.MSUF_DB), "Quick Setup applied before accepting")
M.ShowPrompt = oldPrompt
M.BlockCombatAction = function() return true end
Check(not ui:Copy("class", { size = true }) and not ui:Reset(), "copy/reset bypass combat guard")
Check(F.Equal(before, env.MSUF_DB), "blocked action changed settings")
-- Use an actual cold static result, whose serialized preparation contract
-- is plural metadata, before its lazy workspace/control has been constructed.
local cold = MenuWorld.Open(root, flavor, { page = "home" })
local CM, CF = cold.M, cold.core.ProfileFields
local saved = CF.CopySnapshot(cold.env.MSUF_DB)
local manaResult
for _, row in ipairs(CM.Search._CoreAPI.SearchPages("Mana spend preview")) do
    if row.static and row.key == "classpower" and row.exactTarget
        and row.exactTarget.settingKey == "bars.manaUpcomingCost" then manaResult = row break end
end
Check(manaResult and manaResult.exactTarget.prepareContracts, "static resource contract missing")
local function NavigateStaticMana()
    local ok, anchor, matched = CM.Search._RoutingAPI.OpenSearchTarget(manaResult.key, "unrelated", "", nil,
        manaResult.route, manaResult.exactTarget)
    Check(ok and anchor and matched, "cold static resource contract did not materialize its control")
    Check(CM.ClassPowerWorkspace.current.selected == "extras", "static search selected another resource")
    Check(CF.Equal(saved, cold.env.MSUF_DB), "static search wrote settings")
end
NavigateStaticMana()
cold:RunTimers()
CM.ClassPowerWorkspace.Select("hp")
cold:RunTimers()
NavigateStaticMana()
cold:RunTimers()
local cached, frameCount = CM.cache.classpower, #cold.world.widgets.frames
for _ = 1, 3 do
    CM.ClassPowerWorkspace.Select("hp")
    cold:RunTimers()
    NavigateStaticMana()
    cold:RunTimers()
    Check(CM.cache.classpower == cached and #cold.world.widgets.frames == frameCount, "static warm search rebuilt the page")
end
print("classpower_workspace_smoke: OK (" .. flavor .. ")")
