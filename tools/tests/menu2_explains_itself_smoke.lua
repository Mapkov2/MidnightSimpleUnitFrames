-- menu2_explains_itself_smoke.lua <repoRoot> <flavor>
--
-- The options menu explains itself: a greyed-out control says on hover what
-- unlocks it, help written for search becomes a hover tooltip, a section whose
-- settings differ from what Reset section restores carries a "Custom" text
-- badge, and a scope chip whose scope holds its own settings is marked with
-- " *" and says so on hover.
--
-- It boots the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua and drives the real widgets and pages:
--   1. Cast Bars > Name Shortening: the two sliders keep the mouse while
--      disabled, hovering shows the page tooltip plus exactly one reason line,
--      and the reason disappears once Spell name shortening is on.
--   2. M.BindGateGroup: the first (most general) disabling entry names the
--      reason, a later one takes over once the first is on, all clear when on.
--   3. Gates: a registered gate reason beats the control's own reason while
--      the gate holds it; an unregistered gate shows nothing; text inputs
--      never keep the mouse.
--   4. A toggle's label hit frame keeps the mouse and shows the reason while
--      disabled, and a click there does not toggle it.
--   5. RegisterSearchWidget wires help as a tooltip only past the quality gate,
--      honours helpTooltip = false and ephemeral chrome, never doubles a page
--      tooltip, and yields to a later explicit one.
--   6. The Custom badge: field comparison rules, the Player page's Frame Basics
--      header turning it on and off with the setting, and a narrow header
--      dropping it.
--   7. The Fonts page scope chips: " *" plus "Has its own settings" for a scope
--      with a font override, "Follows shared settings" otherwise.
--
-- Plain Lua 5.1 with the repo root and a flavor (a client matrix Suffix).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "menu2_explains_itself_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "menu2_explains_itself_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

-- Native widget methods the pages call that the shared stubs do not model.
local Methods = world.widgets.Methods
local function Store(field) return function(self, value) self[field] = value end end
local function Fetch(field) return function(self) return self[field] end end
local extraMethods = {
    SetChecked = Store("checked"), GetChecked = Fetch("checked"),
    SetCheckedTexture = Store("checkedTexture"), GetCheckedTexture = Fetch("checkedTexture"),
    SetDisabledCheckedTexture = Store("disabledCheckedTexture"), GetDisabledCheckedTexture = Fetch("disabledCheckedTexture"),
    GetDisabledTexture = Fetch("disabledTexture"), GetHighlightTexture = Fetch("highlightTexture"),
    GetNormalTexture = Fetch("normalTexture"), GetPushedTexture = Fetch("pushedTexture"),
    SetThumbTexture = function(self, value)
        if type(value) == "string" or type(value) == "number" then
            self.thumbTexture = self.thumbTexture or self:CreateTexture(nil, "OVERLAY")
            self.thumbTexture:SetTexture(value)
        else
            self.thumbTexture = value
        end
    end,
    GetThumbTexture = Fetch("thumbTexture"),
    SetValueStep = Store("valueStep"), SetObeyStepOnDrag = Store("obeyStepOnDrag"), SetStepsPerPage = Store("stepsPerPage"),
    SetAutoFocus = Store("autoFocus"), SetNumeric = Store("numeric"), SetMaxLetters = Store("maxLetters"),
    SetPropagateMouseWheel = Store("propagateMouseWheel"),
    SetGradientAlpha = function(self, ...) self.gradientAlpha = { ... } end,
    SetMotionScriptsWhileDisabled = Store("motionScriptsWhileDisabled"),
    SetTextInsets = function() end, ClearFocus = function() end, HasFocus = function() return false end,
    SetCursorPosition = function() end, HighlightText = function() end,
}
for name, method in pairs(extraMethods) do
    if Methods[name] == nil then Methods[name] = method end
end
local StubGetValue = Methods.GetValue
Methods.GetValue = function(self)
    local value = StubGetValue(self)
    if value == nil then value = self.minimum or 0 end
    return value
end

local env = world.env
local M = world.options.MSUF2
local W = M and M.Widgets
local Shared = M and M.UnitSectionsShared
Check(type(M) == "table" and type(W) == "table" and type(Shared) == "table", "Menu2 modules missing")
for _, name in ipairs({ "SetControlDisabledReason", "SetControlsDisabledReason", "SetGateDisabledReason",
    "DisabledReasonText", "TurnOnReason", "TurnOffReason", "SetCollapsibleCustomBadge", "ScopeOverrideTooltipBody" }) do
    Check(type(W[name]) == "function", "W." .. name .. " is missing")
end
Check(type(M.WireSearchHelpTooltip) == "function" and type(Shared.SectionIsCustom) == "function",
    "search help wiring or the section Custom check is missing")
env.MSUF_EnsureDB(true)
-- Pages may rebind the profile table, so always read the live one.
local function DB() return env.MSUF_DB end

-- GameTooltip that records what a hover shows.
local tip = env.GameTooltip
tip.lines = {}
function tip:SetOwner(owner) self.owner, self.lines, self.shown = owner, {}, false end
function tip:SetText(text) self.lines = { text } end
function tip:AddLine(text) self.lines[#self.lines + 1] = text end
function tip:Show() self.shown = true end
function tip:Hide() self.shown, self.owner = false, nil end
function tip:IsShown() return self.shown == true end
function tip:IsOwned(frame) return self.owner == frame end
local function Hover(frame)
    tip:Hide()
    tip.lines = {}
    local enter = frame:GetScript("OnEnter")
    if enter then enter(frame) end
    return tip.lines
end
local function Count(lines, text)
    local n = 0
    for i = 1, #lines do if lines[i] == text then n = n + 1 end end
    return n
end
local function Has(lines, text) return Count(lines, text) > 0 end

M.scrollChild = M.scrollChild or env.CreateFrame("Frame", nil, env.UIParent)
M.GetContentMetrics = function() return 900, 800 end
local function Drain()
    for _ = 1, 2000 do
        if M.UnitPage and M.UnitPage.PumpBackgroundSections then M.UnitPage.PumpBackgroundSections() end
        local timers = world.widgets.timers
        if #timers == 0 then return end
        local timer = table.remove(timers, 1)
        if not timer.cancelled then timer.callback() end
    end
    error(flavor .. ": the deferred page work never drained")
end
local function Build(key, visible)
    M.BuildPageEntry(key, not visible)
    Drain()
    local entry = M.cache and M.cache[key]
    Check(type(entry) == "table", "page " .. key .. " did not build")
    return entry
end
local function RefreshPage(entry)
    for _, refresh in ipairs(entry.refreshers or {}) do refresh() end
end
local function TurnOnText(label) return M.Format("Turn on \"%s\" to change this.", M.Tr(label)) end

-- Capture page controls by setting key, and scope bars as they are built.
local bySetting = {}
for _, name in ipairs({ "BindNumberWidget", "BindBoolWidget", "BindDropdownWidget" }) do
    local original = M[name]
    M[name] = function(ctx, widget, get, set, a, b)
        local meta = type(a) == "table" and a or (type(b) == "table" and b) or nil
        if meta and meta.settingKey then bySetting[meta.settingKey] = widget end
        return original(ctx, widget, get, set, a, b)
    end
end
local scopeBars = {}
local ScopeOverrideBar = W.ScopeOverrideBar
W.ScopeOverrideBar = function(ctx, section, opts)
    local bar = ScopeOverrideBar(ctx, section, opts)
    scopeBars[#scopeBars + 1] = { bar = bar, opts = opts, page = ctx and ctx.key }
    return bar
end

-- 1. Cast Bars > Name Shortening ------------------------------------------
local castbars = Build("opt_castbar")
local maxLen = bySetting["general.castbarSpellNameMaxLen"]
local reserved = bySetting["general.castbarSpellNameReservedSpace"]
Check(maxLen and reserved, "the Cast Bars name-shortening sliders were not built")
DB().general.castbarSpellNameShortening = 0
RefreshPage(castbars)
local reason = TurnOnText("Spell name shortening")
for label, slider in pairs({ ["Max name length"] = maxLen, ["Reserved space"] = reserved }) do
    Check(slider._msuf2AppliedEnabled == false, label .. " stays enabled with Spell name shortening off")
    Check(slider:IsMouseEnabled() == true, label .. " lost the mouse while disabled, so its reason can never show")
    Check(W.DisabledReasonText(slider) == reason, label .. " names no reason: " .. tostring(W.DisabledReasonText(slider)))
    local lines = Hover(slider)
    Check(Count(lines, reason) == 1, label .. " hover shows the reason " .. Count(lines, reason) .. " times")
    Check(#lines >= 3, label .. " hover lost its page tooltip body")
end
DB().general.castbarSpellNameShortening = 1
RefreshPage(castbars)
Check(maxLen._msuf2AppliedEnabled == true and W.DisabledReasonText(maxLen) == nil,
    "Max name length still names a reason with Spell name shortening on")
Check(not Has(Hover(maxLen), reason), "the enabled slider's hover still carries the reason")

-- 2. BindGateGroup reasons -------------------------------------------------
local ctx = { key = "smoke", refreshers = {} }
local function NewControl(kind, frameType)
    local control = env.CreateFrame(frameType or "Button", nil, env.UIParent)
    control._msuf2ControlKind = kind
    return control
end
local gated = NewControl("slider", "Slider")
local flags = { master = false, sub = false }
local refresh = M.BindGateGroup(ctx, nil, {
    { controls = { gated }, on = function() return flags.master end, reason = "Master reason" },
    { controls = gated, on = function() return flags.master and flags.sub end, reason = function() return "Sub reason" end },
}, { noTrack = true })
refresh()
Check(gated._msuf2AppliedEnabled == false and gated:IsMouseEnabled() == true, "a gated control lost the mouse")
Check(W.DisabledReasonText(gated) == "Master reason", "the first disabling entry must name the reason, got " .. tostring(W.DisabledReasonText(gated)))
flags.master = true
refresh()
Check(W.DisabledReasonText(gated) == "Sub reason", "the later entry does not take over once the master is on")
flags.sub = true
refresh()
Check(gated._msuf2AppliedEnabled == true and gated._msuf2DisabledReason == nil, "an enabled control keeps a reason")
Check(W.DisabledReasonText(gated) == nil, "an enabled control still reports a reason")

-- 3. Gate reasons ------------------------------------------------------------
local gatedButton = NewControl("button")
W.SetControlDisabledReason(gatedButton, "Own reason")
Check(gatedButton.motionScriptsWhileDisabled == true, "a disabled button would swallow the hover that shows its reason")
W.SetControlEnabled(gatedButton, false)
Check(W.DisabledReasonText(gatedButton) == "Own reason", "the control's own reason is missing")
W.SetGateDisabledReason("smoke:frame", "Frame reason")
W.SetControlGateEnabled(gatedButton, "smoke:frame", false)
Check(W.DisabledReasonText(gatedButton) == "Frame reason", "a registered gate reason must win while the gate holds the control")
W.SetControlGateEnabled(gatedButton, "smoke:frame", true)
Check(W.DisabledReasonText(gatedButton) == "Own reason", "clearing the gate does not restore the control's own reason")
W.SetControlGateEnabled(gatedButton, "smoke:silent", false)
Check(W.DisabledReasonText(gatedButton) == nil, "an unregistered gate must not show a toggle the user cannot reach")
local edit = NewControl("textinput", "EditBox")
W.SetControlDisabledReason(edit, "Edit reason")
W.SetControlEnabled(edit, false)
Check(edit._msuf2DisabledReasonWired ~= true and edit:IsMouseEnabled() ~= true, "a disabled text input kept the mouse")

-- 4. Toggle label hit frame ---------------------------------------------------
local card = env.CreateFrame("Frame", nil, env.UIParent)
card._msuf2Width = 400
local toggle = W.ToggleAt(card, "Smoke toggle", 16, -40, 300)
toggle:SetChecked(false)
W.SetControlDisabledReason(toggle, "Toggle reason")
W.SetControlEnabled(toggle, false)
local hit = toggle._msuf2LabelHit
Check(hit and hit:IsMouseEnabled() == true, "the toggle's label hit frame lost the mouse while disabled")
Check(Has(Hover(hit), "Toggle reason"), "hovering the toggle label does not show its reason")
local click = hit:GetScript("OnClick")
if click then click(hit) end
Check(toggle:GetChecked() == false, "clicking a disabled toggle's label toggled it")

-- 5. Search help as tooltip ---------------------------------------------------
local HELP = "Adds a bright rim around every frame so it stands out in crowded fights."
local function HelpWidget(label, meta)
    local widget = W.ToggleAt(card, label, 16, -80, 300)
    meta.pageKey, meta.label = "opt_castbar", label
    M.RegisterSearchWidget(widget, meta)
    return widget
end
local wired = HelpWidget("Smoke rim", { classification = "setting", help = HELP })
Check(wired._msuf2TooltipWired == "auto", "setting help did not become a tooltip")
Check(Has(Hover(wired._msuf2LabelHit), HELP), "the automatic tooltip does not show the help text")
local restating = HelpWidget("Smoke glow", { classification = "setting", help = "Enables the smoke glow for this option." })
Check(restating._msuf2TooltipWired == nil, "help that only restates the label became a tooltip")
local optedOut = HelpWidget("Smoke shade", { classification = "setting", help = HELP, helpTooltip = false })
Check(optedOut._msuf2TooltipWired == nil, "helpTooltip = false did not opt out")
local chrome = HelpWidget("Smoke chrome", { classification = "ephemeral", help = HELP })
Check(chrome._msuf2TooltipWired == nil, "ephemeral chrome got an automatic tooltip")
local pageFirst = W.ToggleAt(card, "Smoke page first", 16, -120, 300)
M.AddTooltip(pageFirst, "Smoke page first", "Page text.", { hook = true, labelHit = true })
M.RegisterSearchWidget(pageFirst, { pageKey = "opt_castbar", label = "Smoke page first", classification = "setting", help = HELP })
local pageLines = Hover(pageFirst._msuf2LabelHit)
Check(pageFirst._msuf2TooltipWired == "manual" and not Has(pageLines, HELP), "the automatic tooltip doubled a page tooltip")
M.AddTooltip(wired, "Smoke rim", "Page text wins.", { hook = true, labelHit = true })
local laterLines = Hover(wired._msuf2LabelHit)
Check(Has(laterLines, "Page text wins.") and not Has(laterLines, HELP), "a later page tooltip did not silence the automatic one")

-- 6. Custom badge ------------------------------------------------------------
local spec = { fields = "alpha beta", prefixes = "gamma" }
local defaults = { alpha = 1, beta = { 1, 2 }, gammaOne = "x", delta = 5 }
local function Custom(conf) return Shared.SectionIsCustom(spec, conf, defaults, {}) end
Check(not Custom({ alpha = 1, beta = { 1, 2 }, gammaOne = "x" }), "values equal to the defaults count as custom")
Check(not Custom({}), "unset values count as custom")
Check(not Custom({ alpha = 1 + 1e-9 }), "float noise counts as custom")
Check(Custom({ alpha = 2 }), "a changed field is not custom")
Check(Custom({ beta = { 1, 3 } }), "a changed table field is not custom")
Check(Custom({ gammaOne = "y" }), "a changed prefixed field is not custom")
Check(not Custom({ delta = 6, epsilon = 1 }), "a field outside the section counts")
Check(not Custom({ gammaTwo = "z" }), "a field the defaults do not carry counts")

local unitDefaults
local function FactoryProfile() return { player = unitDefaults } end
world.options.MSUF_CreateFactoryDefaultProfile = FactoryProfile
env.MSUF_CreateFactoryDefaultProfile = FactoryProfile
DB().player.smoothFill = false
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end
unitDefaults = Copy(DB().player)
-- A visible build: hidden (search-index) builds skip the Custom check.
local player = Build("uf_player", true)
local basics = player.sections and player.sections.frame_basics
local basicsEntry = basics and basics._msuf2CollapsibleEntry
Check(basicsEntry and basicsEntry.header and basicsEntry._msuf2UXSummary, "the Player page has no Frame Basics summary header")
basicsEntry.header:SetWidth(720)
RefreshPage(player)
Check(basicsEntry._msuf2CustomBadgeWanted ~= true, "a profile equal to its defaults shows the Custom badge")
DB().player.smoothFill = true
RefreshPage(player)
local badge = basicsEntry._msuf2CustomBadge
Check(basicsEntry._msuf2CustomBadgeWanted == true and badge and badge:IsShown() == true,
    "a changed Frame Basics field does not show the Custom badge")
Check(badge.text and badge.text:GetText() == M.Tr("Custom"), "the badge is not a text badge")
Check(Has(Hover(badge), "Some settings in this section differ from their defaults. Reset section restores them."),
    "the Custom badge does not explain itself on hover")
basicsEntry.header:SetWidth(240)
basicsEntry._msuf2RefreshLayout()
Check(badge:IsShown() ~= true and basicsEntry._msuf2CustomBadgeWanted == true, "a narrow header keeps the Custom badge")
basicsEntry.header:SetWidth(720)
DB().player.smoothFill = false
RefreshPage(player)
Check(badge:IsShown() ~= true and basicsEntry._msuf2CustomBadgeWanted == false, "the Custom badge stays after the field returned to its default")

-- 7. Fonts scope chips -------------------------------------------------------
Build("opt_fonts")
local fontsBar
for _, item in ipairs(scopeBars) do
    if item.page == "opt_fonts" and type(item.opts.hasOverride) == "function" then fontsBar = item.bar end
end
Check(fontsBar and fontsBar.buttons, "the Fonts page built no override scope bar")
local targetButton, sharedButton
for _, button in ipairs(fontsBar.buttons) do
    if button._msuf2Value == "target" then targetButton = button end
    if button._msuf2Value == "shared" then sharedButton = button end
end
Check(targetButton and sharedButton, "the Fonts scope bar lost its Shared or Target chip")
DB().target.fontOverride = true
fontsBar:Refresh()
local marked = targetButton._msuf2Label:GetText()
Check(type(marked) == "string" and marked:sub(-2) == " *", "a scope with its own settings shows no text marker: " .. tostring(marked))
Check(Has(Hover(targetButton), "Has its own settings"), "a scope with its own settings does not say so on hover")
DB().target.fontOverride = false
fontsBar:Refresh()
Check(targetButton._msuf2Label:GetText():sub(-2) ~= " *", "the marker stays after the override is off")
Check(Has(Hover(targetButton), "Follows shared settings"), "a following scope does not say so on hover")
Check(sharedButton._msuf2ScopeText == nil, "the Shared chip carries an override marker")

print(string.format("menu2_explains_itself_smoke: ok (%s: disabled reasons, gate precedence, help tooltips, Custom badge, scope chips)", flavor))
