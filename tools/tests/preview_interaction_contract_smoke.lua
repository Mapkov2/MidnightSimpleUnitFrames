-- Real unit/group preview input, storage and history through the shipped menu.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), assert(arg[2])
local cursorX, cursorY, mouseDown = 300, 200, false
local focus, clearFocusCalls, shiftDown, combatLocked = nil, 0, false, false
local bindings = {}
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
cursorX, cursorY = cursorX + 6 * scale * uiScale, cursorY - 4 * scale * uiScale
assert(box.dragFrame:GetScript("OnUpdate"))(box.dragFrame, .016)
mouseDown = false
assert(handle:GetScript("OnMouseUp"))(handle, "LeftButton")
Settle()
assert(not handle._dragging and not handle._msuf2PreviewHistoryTx and not box.dragFrame._handle, "unit drag did not release")
UnitAt(dragX + 6, dragY - 4, "unit drag result")
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
print("PASS preview interaction " .. flavor .. ": click, exact/arrow nudge, drag, reset, undo/redo, Tab, close")
