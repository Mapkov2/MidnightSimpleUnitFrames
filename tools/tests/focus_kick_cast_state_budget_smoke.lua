-- focus_kick_cast_state_budget_smoke.lua <repoRoot> [print]
--
-- The Focus Interrupt Tracker icon receives every focus cast state the castbar
-- engine publishes (MSUF_FocusKick_StateDriver.lua -> ApplyCastState). Its
-- geometry and time-text font are owned by the option, font, drag and shake
-- paths; a cast state only re-lays the icon out when that geometry changed
-- underneath it. Pinned:
--   * budget: one active cast state, Lua VM instructions and bytes with the
--     collector stopped (frozen 2026-10-02 from the cost before the change,
--     plus 2 %);
--   * a cast state re-anchors the icon after a profile changes its size or
--     position without the options path, and during a drag or the interrupt
--     shake, exactly as before;
--   * an unchanged cast state does not re-anchor the icon or its edges;
--   * the aura icon shapes: a circle masks the backdrop and the spell icon of
--     the live icon and the on-screen preview and swaps the square edges for
--     the shape ring, which the ready colour keeps tinting; Follow Portrait
--     and Rectangle bring the edges back, and a never-shaped icon is left as
--     it was.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local loadfile = assert(loadfile(root .. "/tools/tests/castbar_namespace_fixture.lua"))().Loader(loadfile)
local printOnly = arg[2] == "print"

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local anchors = 0
local function NoOp() end
local WIDGET_MT = { __index = function(_, key)
    if type(key) == "string" and key:match("^%u%l") then return NoOp end
    return nil
end }
local function Widget(name)
    local widget = setmetatable({ shown = false, name = name, scripts = {} }, WIDGET_MT)
    function widget:SetScript(script, handler) self.scripts[script] = handler end
    function widget:HookScript() end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:IsShown() return self.shown end
    function widget:SetPoint() anchors = anchors + 1 end
    function widget:GetCenter() return 500, 400 end
    function widget:CreateTexture() return Widget() end
    function widget:CreateFontString() return Widget() end
    function widget:CreateAnimationGroup() return Widget() end
    function widget:CreateAnimation() return Widget() end
    if name then _G[name] = widget end
    return widget
end
_G.UIParent = Widget("UIParent")
_G.CreateFrame = function(_, name) return Widget(name) end
local pending = {}
_G.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
_G.InCombatLockdown = function() return false end
_G.MSUF_SetFontChecked = function() return true end
_G.MSUF_DB = { general = { enableFocusKickIcon = true }, focus = {} }
if _G.MSUF and _G.MSUF.Castbars and _G.MSUF.Castbars.Config.ready then _G.MSUF.Castbars.Config.Compile() end
-- The providers the icon calls; each loads before it in every TOC (Kernel
-- Util and Libs, Runtime/MSUF_FontRegistry.lua, Castbars_Core, the castbar
-- manager, the state driver, the interrupt-ready indicator).
_G.MSUF_GetFontPath = function() return "Fonts\\FRIZQT__.TTF" end
_G.MSUF_GetFontFlags = function() return "OUTLINE" end
_G.MSUF_GetConfiguredFontColor = function() return 1, 1, 1 end
_G.MSUF_MarkFontApplyFailed = NoOp
-- Runtime/MSUF_FontRegistry.lua and MSUF_Fonts.lua, which the icon requires: the
-- budget pins the icon's own cost, so the font owners answer through the checked
-- font setter above (the path this pin was frozen on).
_G.MSUF_ResolveSafeFontPath = function(fontPath) return fontPath end
_G.MSUF_ApplyResolvedFont = function(fontString, fontPath, fontSize, fontFlags)
    return _G.MSUF_SetFontChecked(fontString, fontPath, fontSize, fontFlags)
end
_G.MSUF_GetCastbarTimeFormat = function() return "CURRENT" end
_G.MSUF_RegisterCastbar = NoOp
_G.MSUF_SetIconTexture = function(texture, icon) texture:SetTexture(icon) end
_G.MSUF_KickReady_Init = NoOp
_G.MSUF_KickReady_IsReady = function() return true end
_G.MSUF_KickReady_EvaluateRGBA = function() return 0.2, 1, 0.2, 1 end
_G.MSUF_FocusKickDriver_ForceUpdate = NoOp

local ns = { ExportPublic = function(name, value) _G[name] = value return value end }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_FocusKickIcon.lua"))("MidnightSimpleUnitFrames", ns)
local apply = assert(_G.MSUF.Castbars.FocusKick.FocusKick_ApplyCastState, "MSUF_FocusKick_ApplyCastState missing")

local state = { active = true, icon = 136243, isNotInterruptible = false }
apply(state)
local icon = assert(_G.MSUF.Castbars.Frames.focusKick, "focus kick icon not built")

-- Budget ----------------------------------------------------------------------
-- Before the change: 871 instructions and 200 bytes (a font closure per call).
local BUDGET = { 888, 8 }
local WARMUP, INSTRUCTION_REPS, ALLOCATION_REPS = 50, 200, 2000
for _ = 1, WARMUP do apply(state) end
local ticks = 0
debug.sethook(function() ticks = ticks + 1 end, "", 1)
for _ = 1, INSTRUCTION_REPS do apply(state) end
debug.sethook()
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, ALLOCATION_REPS do apply(state) end
local bytes = (collectgarbage("count") - before) * 1024 / ALLOCATION_REPS
collectgarbage("restart")
local instructions = ticks / INSTRUCTION_REPS
local line = string.format("focus kick cast state %8.1f instructions %8.1f bytes  (budget %d / %d)",
    instructions, bytes, BUDGET[1], BUDGET[2])
if printOnly then print(line) return end
Check(instructions <= BUDGET[1] and bytes <= BUDGET[2], "focus kick cast state over budget: " .. line)

-- Behaviour ---------------------------------------------------------------
local general = _G.MSUF_DB.general
local function Anchors(fn)
    local before = anchors
    fn()
    return anchors - before
end

Check(Anchors(function() apply(state) end) == 0, "an unchanged cast state re-anchored the icon")

-- A profile switch rewrites the settings without the options path.
general.focusKickIconWidth = 52
Check(Anchors(function() apply(state) end) > 0, "a cast state kept the icon at the old profile's width")
Check(Anchors(function() apply(state) end) == 0, "the re-anchored icon was anchored again")
general.focusKickIconOffsetX = 120
Check(Anchors(function() apply(state) end) > 0, "a changed X offset was not applied")
general.focusKickIconOffsetY = -40
Check(Anchors(function() apply(state) end) > 0, "a changed Y offset was not applied")
general.focusKickIconHeight = 48
Check(Anchors(function() apply(state) end) > 0, "a changed height was not applied")

-- During a drag the next cast state snaps the icon back, as before.
icon.scripts.OnDragStart(icon)
Check(Anchors(function() apply(state) end) > 0, "a cast state during a drag kept the dragged position")

-- The interrupt shake moves the icon itself; a cast state in between
-- re-anchors it, and the shake's last step restores the layout.
_G.MSUF.Castbars.FocusKick.FocusKick_PlayInterruptFeedback()
Check(Anchors(function() apply(state) end) > 0, "a cast state during the interrupt shake kept the shaken position")
for _ = 1, 20 do
    local queued = pending
    pending = {}
    for index = 1, #queued do queued[index]() end
end
Check(Anchors(function() apply(state) end) == 0, "the layout after the shake was not remembered")

-- Icon shape ------------------------------------------------------------------
ns.MSUF_Auras3 = {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_IconShape.lua"))("MidnightSimpleUnitFrames", ns)
local function Track(region)
    function region:AddMaskTexture(mask) self.mask = mask end
    function region:RemoveMaskTexture() self.mask = nil end
    function region:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function region:GetVertexColor() local c = self.color or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
    function region:SetShown(shown) self.visible = shown and true or false end
    return region
end
local function Owner(frame)
    function frame:CreateMaskTexture() return Widget() end
    function frame:CreateTexture() return Track(Widget()) end
    return frame
end
Owner(icon)
Track(icon.bg)
Track(icon.icon)
for index = 1, #icon.edges do Track(icon.edges[index]) end

general.focusKickIconWidth = 44
apply(state)
Check(icon._msufA3AuraShapeMask == nil and icon.edges[1].visible == nil, "a rectangular icon was reshaped")

general.focusKickIconShape = "CIRCLE"
Check(Anchors(function() apply(state) end) > 0, "a changed icon shape was not applied")
local mask = icon._msufA3AuraShapeMask
Check(mask ~= nil and icon.bg.mask == mask and icon.icon.mask == mask, "a circle did not mask the backdrop and the icon")
for index = 1, #icon.edges do Check(icon.edges[index].visible == false, "a circular icon kept its square edges") end
local rings = icon._msufA3ShapedStyleBorders or {}
Check(#rings == 2 and rings[1].shown and rings[2].shown, "the ring is not the 2 px of the square edges")
Check(rings[1].color and rings[1].color[1] == 0.2 and rings[1].color[2] == 1, "the ring is not in the ready colour")
apply({ active = true, icon = 136243, isNotInterruptible = true })
Check(rings[2].color[1] == 0.6 and icon.edges[1].color[1] == 0.6, "the not-interruptible grey did not tint the ring")

local createFrame = _G.CreateFrame
_G.CreateFrame = function(_, name) return Owner(Widget(name)) end
_G.MSUF.Castbars.FocusKick.FocusKick_SetPreviewEnabled(true)
_G.CreateFrame = createFrame
local preview = assert(_G.MSUF_FocusKickPreviewFrame, "focus kick preview not built")
Check(preview.icon.mask ~= nil and preview.icon.mask == preview._msufA3AuraShapeMask, "the preview icon is not a circle")
_G.MSUF.Castbars.FocusKick.FocusKick_SetPreviewEnabled(false)

general.focusKickIconShape = "FOLLOW_PORTRAIT"
apply(state)
Check(icon.bg.mask == nil and icon.icon.mask == nil, "Follow Portrait kept the circle mask")
for index = 1, #icon.edges do Check(icon.edges[index].visible == true, "Follow Portrait did not bring the edges back") end
Check(not (rings[1].shown or rings[2].shown), "Follow Portrait kept the ring")
general.focusKickIconShape = nil
Check(Anchors(function() apply(state) end) > 0, "clearing the icon shape was not applied")
Check(Anchors(function() apply(state) end) == 0, "the rectangular icon was anchored again")

print("focus_kick_cast_state_budget_smoke: ok (" .. line .. ")")
