-- focus_kick_preview_combat_keyboard_smoke.lua <repoRoot>
--
-- The Focus Interrupt Tracker's on-screen preview takes the keyboard for
-- arrow-key nudges (Castbars/MSUF_FocusKickIcon.lua). SetPropagateKeyboardInput
-- is HasRestrictions (SimpleFrameAPIDocumentation): addon code cannot call it
-- in combat lockdown. The preview called it from OnKeyDown for every key, so a
-- preview left on into combat raised a blocked action per key press, and an
-- arrow-key nudge just before the pull left propagation off: keybinds were
-- swallowed in combat (red without the fix, step 2).
--
-- Pinned, with the real Kernel/MSUF_Util.lua combat helper:
--   1. out of combat the preview nudges on arrow keys (behaviour kept);
--   2. PLAYER_REGEN_DISABLED (InCombatLockdown() still false) turns propagation
--      back on and releases the keyboard; in combat every key reaches the
--      bindings and nothing calls the restricted API;
--   3. PLAYER_REGEN_ENABLED takes the keyboard again and nudges work;
--   4. a preview hidden in combat calls no restricted API;
--   5. a preview built in combat takes the keyboard only after combat;
--   6. a preview built at the combat edge (after PLAYER_REGEN_DISABLED, before
--      the lockdown) neither nudges nor calls the restricted API on a key.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local lockdown, now = false, 100
local blocked = {}
_G.InCombatLockdown = function() return lockdown end
_G.GetTime = function() return now end

local function NoOp() end
local WIDGET_MT = { __index = function(_, key)
    if type(key) == "string" and key:match("^%u%l") then return NoOp end
    return nil
end }
local function Widget(name)
    local widget = setmetatable({ shown = false, name = name, scripts = {}, events = {},
        keyboard = false, propagate = false }, WIDGET_MT)
    function widget:SetScript(script, handler) self.scripts[script] = handler end
    function widget:HookScript() end
    function widget:RegisterEvent(event) self.events[event] = true end
    function widget:UnregisterEvent(event) self.events[event] = nil end
    function widget:Show() self.shown = true end
    function widget:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function widget:IsShown() return self.shown end
    function widget:GetCenter() return 500, 400 end
    -- EnableKeyboard is protected only on protected frames; the preview is not.
    function widget:EnableKeyboard(enabled) self.keyboard = enabled == true end
    function widget:SetPropagateKeyboardInput(propagate)
        if lockdown then
            blocked[#blocked + 1] = "SetPropagateKeyboardInput(" .. tostring(propagate) .. ")"
            return
        end
        self.propagate = propagate == true
    end
    function widget:CreateTexture() return Widget() end
    function widget:CreateFontString() return Widget() end
    function widget:CreateAnimationGroup() return Widget() end
    function widget:CreateAnimation() return Widget() end
    if name then _G[name] = widget end
    return widget
end

local function Load()
    _G.MSUF_FocusKickPreviewFrame = nil
    _G.UIParent = Widget("UIParent")
    _G.CreateFrame = function(_, name) return Widget(name) end
    _G.C_Timer = { After = NoOp }
    _G.MSUF_SetFontChecked = function() return true end
    _G.MSUF_DB = { general = { enableFocusKickIcon = true, focusKickIconOffsetX = 0, focusKickIconOffsetY = 0 },
        focus = {} }
    -- The providers the preview calls; each loads before the icon in every TOC.
    _G.MSUF_GetFontPath = function() return "Fonts\\FRIZQT__.TTF" end
    _G.MSUF_GetFontFlags = function() return "OUTLINE" end
    _G.MSUF_GetConfiguredFontColor = function() return 1, 1, 1 end
    _G.MSUF_MarkFontApplyFailed = NoOp
    _G.MSUF_FocusKickDriver_ForceUpdate = NoOp
    local ns = { ExportPublic = function(name, value) _G[name] = value return value end }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua"))("MidnightSimpleUnitFrames", ns)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_FocusKickIcon.lua"))("MidnightSimpleUnitFrames", ns)
    return ns
end

-- The client: a key reaches OnKeyDown only while the shown frame takes the
-- keyboard; it reaches the bindings when the frame does not take it or lets
-- it propagate (the state after OnKeyDown ran).
local function PressKey(frame, key)
    if frame.shown and frame.keyboard then
        frame.scripts.OnKeyDown(frame, key)
        return frame.propagate
    end
    return true
end

local function Fire(frame, event)
    if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event) end
end

local general

-- 1. Out of combat: arrow keys nudge the selected preview.
Load()
general = _G.MSUF_DB.general
_G.MSUF_FocusKick_SetPreviewEnabled(true)
local preview = assert(_G.MSUF_FocusKickPreviewFrame, "preview frame missing")
Check(preview.shown and preview.keyboard and preview.propagate, "1: the preview must take the keyboard out of combat")
preview.scripts.OnMouseDown(preview, "LeftButton")
Check(PressKey(preview, "1") == true, "1: a non-arrow key must reach the bindings")
Check(PressKey(preview, "LEFT") == false and general.focusKickIconOffsetX == -1, "1: an arrow key must nudge the preview")
Check(preview.propagate == false, "harness: a nudge leaves propagation off until the next key")

-- 2. The combat edge releases the keyboard while that is still allowed.
Fire(preview, "PLAYER_REGEN_DISABLED")
Check(#blocked == 0, "2: the combat edge called a restricted API: " .. table.concat(blocked, ", "))
Check(preview.propagate == true, "2: propagation must be back on before the lockdown (keybinds swallowed in combat)")
Check(not preview.keyboard, "2: the preview must release the keyboard for the combat")
lockdown = true
for _, key in ipairs({ "1", "LEFT", "UP", "SPACE" }) do
    Check(PressKey(preview, key) == true, "2: " .. key .. " did not reach the bindings in combat")
end
Check(#blocked == 0, "2: a key press in combat called a restricted API: " .. table.concat(blocked, ", "))
Check(general.focusKickIconOffsetX == -1 and general.focusKickIconOffsetY == 0, "2: a key moved the preview in combat")

-- 3. After combat the keyboard comes back and nudges work.
lockdown = false
Fire(preview, "PLAYER_REGEN_ENABLED")
Check(preview.keyboard and preview.propagate, "3: the preview must take the keyboard again after combat")
Check(PressKey(preview, "RIGHT") == false and general.focusKickIconOffsetX == 0, "3: nudges must work after combat")
Check(PressKey(preview, "1") == true, "3: a non-arrow key must reach the bindings after combat")

-- 4. Hiding the preview in combat.
Fire(preview, "PLAYER_REGEN_DISABLED")
lockdown = true
_G.MSUF_FocusKick_SetPreviewEnabled(false)
Check(not preview.shown, "4: the preview did not hide")
Check(#blocked == 0, "4: hiding the preview in combat called a restricted API: " .. table.concat(blocked, ", "))
lockdown = false
Fire(preview, "PLAYER_REGEN_ENABLED")

-- 5. A preview built in combat waits for the end of combat.
Load()
lockdown = true
_G.MSUF_FocusKick_SetPreviewEnabled(true)
preview = assert(_G.MSUF_FocusKickPreviewFrame, "5: preview frame missing")
Check(#blocked == 0, "5: building the preview in combat called a restricted API: " .. table.concat(blocked, ", "))
Check(not preview.keyboard and PressKey(preview, "1") == true, "5: a preview built in combat took the keyboard")
lockdown = false
Fire(preview, "PLAYER_REGEN_ENABLED")
Check(preview.keyboard and preview.propagate, "5: the preview built in combat never took the keyboard")

-- 6. Built at the combat edge: PLAYER_REGEN_DISABLED went out before the frame
-- existed, the lockdown has not started, the edge is remembered this frame.
local ns = Load()
ns.Util.InCombat("PLAYER_REGEN_DISABLED")
_G.MSUF_FocusKick_SetPreviewEnabled(true)
preview = assert(_G.MSUF_FocusKickPreviewFrame, "6: preview frame missing")
general = _G.MSUF_DB.general
preview.scripts.OnMouseDown(preview, "LeftButton")
Check(PressKey(preview, "LEFT") == true and general.focusKickIconOffsetX == 0, "6: an arrow key nudged at the combat edge")
lockdown = true
Check(PressKey(preview, "LEFT") == true and PressKey(preview, "1") == true and general.focusKickIconOffsetX == 0,
    "6: a key in combat did not reach the bindings or nudged")
Check(#blocked == 0, "6: a key at the combat edge called a restricted API: " .. table.concat(blocked, ", "))

print("focus_kick_preview_combat_keyboard_smoke: ok")
