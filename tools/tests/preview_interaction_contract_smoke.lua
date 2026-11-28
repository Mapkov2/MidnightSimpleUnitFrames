-- Real unit/group preview input, storage and history through the shipped menu.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), assert(arg[2])
local cursorX, cursorY, mouseDown = 300, 200, false
local focus, clearFocusCalls, shiftDown, combatLocked = nil, 0, false, false
local bindings = {}
local altDown = false
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local Open = MenuWorld.Open
local mw = Open(root, flavor, { page = "uf_player", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        MenuWorld.InstallNativeUnitInputs(world)
        world.env.InCombatLockdown = function() return combatLocked end
        -- The headless fixture has no native layout engine. Supply measurable
        -- rectangles for hit areas; the render oracle checks actual anchor data.
        local methods = world.widgets.Methods
        methods.GetLeft = function(region) return region.left or 0 end
        methods.GetBottom = function(region) return region.bottom or 0 end
        methods.GetRect = function(region)
            return region:GetLeft(), region:GetBottom(), math.max(1, region:GetWidth()), math.max(1, region:GetHeight())
        end
        world.env.GetCursorPosition = function() return cursorX, cursorY end
        world.env.IsMouseButtonDown = function() return mouseDown end
        world.env.IsShiftKeyDown = function() return shiftDown end
        world.env.IsControlKeyDown = function() return false end
        world.env.IsAltKeyDown = function() return altDown end
        world.env.GetCurrentKeyBoardFocus = function() return focus end
        world.env.SetOverrideBindingClick = function(_, _, key, button) bindings[key] = button end
        world.env.ClearOverrideBindings = function() for key in pairs(bindings) do bindings[key] = nil end end
        local overlay = arg[3]
        if overlay then
            local load = world.LoadFile
            function world:LoadFile(path, addon, ns)
                local relative = path:sub(#root + 1)
                local alternate = overlay .. relative
                local file = io.open(alternate, "rb")
                if file then file:close(); path = alternate end
                return load(self, path, addon, ns)
            end
        end
    end })
local M, U = mw.M, mw.core.UFPreview
local function Settle()
    mw:RunTimers(20000)
    M.Theme.StopAllMenuAnimations()
end
local function Click(widget, button)
    assert(widget and widget:GetScript("OnClick"), "clickable preview control missing")(widget, button or "LeftButton")
    Settle()
end
local function UnitPosition()
    local ok, x, y = U.NudgeHandle("player", "name", 0, 0)
    assert(ok, "unit coordinate read refused")
    return x, y
end
local function UnitAt(x, y, message)
    local actualX, actualY = UnitPosition()
    assert(actualX == x and actualY == y, message .. ": " .. actualX .. "," .. actualY)
end
Settle()
M.ControlSchema.SetUnit("layout", "player", "showName", true, "PREVIEW_INTERACTION_TEST", "toggle")
Settle()
local box, handle = U.active, U.active.handleName
Click(handle)
assert(box._selectedHandle == handle, "unit click did not select name")
local function BindingCount()
    local count = 0
    for _ in pairs(bindings) do count = count + 1 end
    return count
end
assert(BindingCount() == 20, "selected unit handle did not register arrow overrides")
focus = {
    IsObjectType = function(_, kind) return kind == "EditBox" end,
    ClearFocus = function() clearFocusCalls = clearFocusCalls + 1; focus = nil end,
}
for _, shifted in ipairs({ false, true }) do
    shiftDown = shifted
    box:GetScript("OnKeyDown")(box, "TAB")
    assert(box._selectedHandle == handle and clearFocusCalls == 0, "Tab stole text input focus")
end
shiftDown, focus = false, nil
combatLocked = true
box:GetScript("OnKeyDown")(box, "TAB")
assert(box._selectedHandle == handle, "Tab changed selection in combat")
combatLocked = false
M.ControlSchema.SetUnit("layout", "player", "showName", false, "PREVIEW_INTERACTION_TEST", "toggle")
Settle()
assert(not handle:IsShown() and box._selectedHandle == nil, "disabled name retained selection")
assert(BindingCount() == 0 and mw.env.MSUF_UFPreview_ActiveNudgeBox == nil,
    "hidden selected handle retained keyboard overrides")
M.ControlSchema.SetUnit("layout", "player", "showName", true, "PREVIEW_INTERACTION_TEST", "toggle")
Settle()
Click(handle)
assert(BindingCount() == 20, "reselected name did not restore keyboard overrides")

local beforeX, beforeY = UnitPosition()
M.ClearHistory()
assert(U.NudgeHandle("player", "name", 7, -5), "exact unit nudge refused")
Settle()
UnitAt(beforeX + 7, beforeY - 5, "unit exact nudge")
assert(#M.historyUndo == 1, "exact nudge did not create one history entry")
assert(M.Undo(), "unit nudge undo refused") Settle()
UnitAt(beforeX, beforeY, "unit undo")
assert(M.Redo(), "unit nudge redo refused") Settle()
UnitAt(beforeX + 7, beforeY - 5, "unit redo")
local rejected, why = U.NudgeHandle("target", "name", 99, 99)
assert(rejected == false and why == "unit-preview-mismatch", "unit mismatch wrote another preview")
box, handle = U.active, U.active.handleName
local dragX, dragY = UnitPosition()
M.ClearHistory()
mouseDown = true
assert(handle:GetScript("OnMouseDown"))(handle, "LeftButton")
assert(handle._dragging == true and box.dragFrame._handle == handle, "unit drag did not start")
local scale = box._mockEffectiveScale or box._mockScale or 1
local uiScale = box.canvas:GetEffectiveScale()
local snap = assert(box._msufPreviewSnap)
assert(snap.active, "unit drag never armed snapping")
local deltaX, deltaY = 6 * scale * uiScale, -4 * scale * uiScale
snap.x, snap.y = { snap.right + deltaX + 6 }, {}
cursorX, cursorY = cursorX + deltaX, cursorY + deltaY
assert(box.dragFrame:GetScript("OnUpdate"))(box.dragFrame, .016)
assert(snap.vertical:IsShown(), "unit drag did not draw its active snap guide")
altDown = true  -- press Alt and release before another update
mouseDown = false
assert(handle:GetScript("OnDragStop"))(handle)
Settle()
assert(not handle._dragging and not handle._msuf2PreviewHistoryTx and not box.dragFrame._handle, "unit drag did not release")
altDown = false
UnitAt(dragX + 6, dragY - 4, "unit free drag result")
assert(#M.historyUndo == 1, "drag was not one history transaction")
assert(M.Undo(), "unit drag undo refused") Settle()
UnitAt(dragX, dragY, "unit drag undo")
assert(M.Redo(), "unit drag redo refused") Settle()
UnitAt(dragX + 6, dragY - 4, "unit drag redo")
box, handle = U.active, U.active.handleName
local defaultX, defaultY = U.DefaultSelectionOffsets(box, handle)
Click(box._msuf2SelectionBar.resetButton)
UnitAt(defaultX, defaultY, "unit reset")
assert(M.Undo(), "unit reset undo refused") Settle()
UnitAt(dragX + 6, dragY - 4, "unit reset undo")
box, handle = U.active, U.active.handleName
assert(box:GetScript("OnKeyDown"))(box, "TAB")
assert(box._selectedHandle and box._selectedHandle ~= handle, "unit Tab did not cycle selection")
Click(handle)
local keyX, keyY = UnitPosition()
assert(box:GetScript("OnKeyDown"))(box, "RIGHT")
Settle()
UnitAt(keyX + 1, keyY, "unit arrow nudge")

assert(mw:Select("gf_layout") ~= false) Settle()
M.gfScope = "party"
mw.core.GF.EnsureDB()
local group = M.GroupPreview.CreateNative(mw.env.UIParent, { width = 760, key = "gf_layout" })
group:Show()
group._stage:SetSize(600, 220)
group:Refresh("SETTINGS")
local name = assert(group._textHandles.name, "group name handle missing")
Click(name)
assert(group._selectedHandle == name, "group click did not select name")
M.ClearHistory()
local ok, x, y = group:NudgeHandleExact(name._key, 5, -3)
assert(ok, "group exact nudge refused") Settle()
local moved, movedX, movedY = group:NudgeHandleExact(name._key, 0, 0)
assert(moved and movedX == x + 5 and movedY == y - 3, "group exact nudge result")
assert(M.Undo(), "group nudge undo refused") Settle()
local restored, undoX, undoY = group:NudgeHandleExact(name._key, 0, 0)
assert(restored and undoX == x and undoY == y, "group undo result")
assert(M.Redo(), "group nudge redo refused") Settle()
Click(name)
assert(group:GetScript("OnKeyDown"))(group, "RIGHT") Settle()
local arrow, arrowX, arrowY = group:NudgeHandleExact(name._key, 0, 0)
assert(arrow and arrowX == x + 6 and arrowY == y - 3, "group arrow nudge result")
assert(group:GetScript("OnKeyDown"))(group, "TAB")
assert(group._selectedHandle and group._selectedHandle ~= name, "group Tab did not cycle selection")
-- Native keyboard setters can be hooked. Both releases must visit shared
-- handles once per invocation, even when one setter initiates another release.
do
    local calls, nestedCalls = 0, 0
    local handle = { SetPropagateKeyboardInput = function(_, propagate)
        assert(propagate == true)
        calls = calls + 1
    end }
    local nested = { handles = { handle, handle }, SetPropagateKeyboardInput = function()
        nestedCalls = nestedCalls + 1
    end }
    local owner = { handles = { handle }, _handleList = { handle } }
    owner.SetPropagateKeyboardInput = function() M.PreviewHelpers.ReleaseKeyboardCapture(nested) end
    owner._handleList[2] = owner
    for i = 1, 2 do M.PreviewHelpers.ReleaseKeyboardCapture(owner) end
    assert(calls == 4 and nestedCalls == 2, "duplicate or skipped keyboard release")
end
local function SnapFixture(scale)
    local function Region(x, y, w, h)
        local frame = mw.env.CreateFrame("Frame", nil, mw.env.UIParent)
        frame:SetSize(w / scale, h / scale)
        frame.left, frame.bottom = x / scale, y / scale
        frame.GetEffectiveScale = function() return scale end
        return frame
    end
    local helper = M.PreviewHelpers
    local owner, surface = {}, Region(0, 0, 240, 200)
    local moving = Region(10, 10, 10, 10)
    local target = Region(50, 80, 20, 20)
    local hidden = Region(48, 10, 10, 10)
    hidden:Hide()
    helper.BeginPreviewSnap(owner, moving, surface, nil, { moving, target, hidden })
    local x, y = helper.ApplyPreviewSnap(owner, 1, 0)
    assert(x == 1 and y == 0, "a click should not activate snapping")
    x, y = helper.ApplyPreviewSnap(owner, 27, 57)
    assert(x == 30 and y == 60, "snap must line up both edges in cursor units")
    local snap = owner._msufPreviewSnap
    assert(snap.vertical:IsShown() and snap.horizontal:IsShown(), "snap guides were absent")
    altDown = true
    x, y = helper.ApplyPreviewSnap(owner, 27, 57)
    assert(x == 27 and y == 57 and not snap.vertical:IsShown(), "Alt did not bypass snapping")
    altDown = false
    assert(helper.ApplyPreviewSnap(owner, 27, 57) == 30, "snapping did not resume at a stationary cursor")
    helper.EndPreviewSnap(owner)
    assert(not snap.vertical:IsShown() and not snap.horizontal:IsShown(), "guide lingered after release")
    helper.TogglePreviewSnap()
    helper.BeginPreviewSnap(owner, moving, surface, nil, { target })
    assert(helper.ApplyPreviewSnap(owner, 27, 57) == 27, "disabled snapping still moved the element")
    helper.TogglePreviewSnap()
end
SnapFixture(0.5)
SnapFixture(2)

local function ExerciseQuickControls(group)
    local gp, registry = M.GroupPage, mw.core.GF.SpellIndicators
    M.gfScope = "raid"
    local conf = gp.Conf("raid")
    conf.showName, conf.nameFontSize = true, 12
    group:Refresh("SETTINGS")
    assert(group._msuf2SelectionBar.snap, "group preview has no snap toggle")
    local quick = assert(group._msuf2SelectionBar.quick, "group selection bar has no quick controls")
    Click(group._textHandles.name)
    assert(quick:IsShown() and tonumber(quick.size:GetText()) == 12, "Raid Name size did not bind")
    M.ClearHistory()
    Click(quick.plus)
    assert(gp.Num("raid", "nameFontSize", 12) == 13, "Raid Name size was not written")
    assert(#M.historyUndo == 1 and M.Undo(), "Raid Name size did not create one undo step")
    Settle()
    assert(gp.Num("raid", "nameFontSize", 12) == 12, "Raid Name size undo did not restore the setting")
    conf = gp.Conf("raid")
    conf.dispelSymbolEnabled, conf.dispelSymbolSize = true, 14
    group:Refresh("SETTINGS")
    local dispel = assert(group._handles.dispelSymbol)
    dispel:Show()
    Click(dispel)
    assert(quick:IsShown() and tonumber(quick.size:GetText()) == 14, "Dispel Symbol size did not bind")
    Click(quick.plus)
    assert(gp.Num("raid", "dispelSymbolSize", 12) == 15, "Dispel Symbol size was not written")
    local open, chooseAnchor = M.Widgets.OpenDropdown
    M.Widgets.OpenDropdown = function(_, values, current, callback)
        assert(#values == 9 and current == gp.Val("raid", "dispelSymbolAnchor", "TOPRIGHT"))
        chooseAnchor = callback
    end
    Click(quick.anchor)
    M.Widgets.OpenDropdown = open
    assert(chooseAnchor, "Dispel Symbol had no quick anchor action")
    chooseAnchor("CENTER")
    assert(gp.Val("raid", "dispelSymbolAnchor", "TOPRIGHT") == "CENTER", "Dispel Symbol anchor was not written")
    Click(group._textHandles.name)
    chooseAnchor("BOTTOMRIGHT")
    assert(gp.Val("raid", "dispelSymbolAnchor", "TOPRIGHT") == "CENTER", "stale anchor action wrote to an old selection")

    conf = gp.Conf("raid")
    local defaults = registry.SpecDefaults
    defaults.PreviewTest = { PreviewAura = { enabled = true, placed = { type = "bar", size = 11, anchor = "LEFT" } } }
    conf.spellIndicators = { enabled = true, spec = "multi", specs = {} }
    local item = { spellIndicatorSlot = true, visual = "bar", size = 11, anchor = "LEFT",
        display = "PreviewAura", auraName = "PreviewAura", specKey = "PreviewTest" }
    local spell = assert(group:EnsureSpellIndicatorHandle(item, 1))
    spell:Show()
    assert(spell:GetScript("OnClick"))(spell, "LeftButton")
    assert(quick:IsShown() and tonumber(quick.size:GetText()) == 11, "compiled spell size did not bind")
    assert(not conf.spellIndicators.specs.PreviewTest, "reading compiled spell mutated its saved config")
    assert(quick.plus:GetScript("OnClick"))(quick.plus, "LeftButton")
    local placed = conf.spellIndicators.specs.PreviewTest.PreviewAura.placed
    assert(placed.size == 12 and placed.type == "bar", "compiled spell shape or size was not preserved")
    assert(item.size == 11, "spell update wrote into its compiled preview slot")
    defaults.PreviewTest = nil
end
ExerciseQuickControls(group)

local schema = M.EnsureDB()
local marker = schema.player.nameOffsetX
group:Hide()
mw.M.HideSlashMenuAndMinibar(mw.win)
assert(schema.player.nameOffsetX == marker, "closing previews wrote a setting")
-- The native aura addon is deliberately absent from MenuWorld. Its one-time
-- demand-load diagnostic is expected when a real unit is applied; every other
-- report is an error. Aura rendering/lifecycle is covered by the scene tests.
assert(#mw.world.reported <= 1, table.concat(mw.world.reported, "\n"))
for _, report in ipairs(mw.world.reported) do
    assert(report == "MSUF Auras3: Blizzard_AuraContainer is not loaded: MISSING", report)
end
print("PASS preview interaction " .. flavor .. ": click, nudge, drag, snap, quick controls, reset, undo/redo, Tab, close")
