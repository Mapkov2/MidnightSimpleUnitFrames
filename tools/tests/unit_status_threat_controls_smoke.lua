-- unit_status_threat_controls_smoke.lua <repoRoot> <flavor>
--
-- Every client loads the Retail-named Pages/MSUF_Menu2_UnitStatusSection.lua.
-- Its Threat % controls (Color by threat, Background) and their part of Reset
-- selected are hunks of this repo that Retail does not have, in a file that
-- also carries IS_CLASSIC_FAMILY hunks and is rebased at every Retail sync.
-- They exist only where MSUF.Client.SupportsThreatText is true (Classic Era,
-- TBC and WoW Forever); Mists and Midnight must not build them.
--
-- This smoke boots the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua, builds the real Target status section through
-- the Menu2 page builder and drives it as the menu does: select Threat %,
-- click each toggle, select another indicator, turn Threat % off, and press
-- Reset selected. The unit compile must follow each click.
--
-- Plain Lua 5.1 with the repo root and a flavor (a client matrix Suffix or
-- Forever) as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "unit_status_threat_controls_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "unit_status_threat_controls_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

local SECTION = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua"
local loaded = {}
for _, path in ipairs(world.loaded) do loaded[path] = true end
Check(loaded[SECTION], "does not load the Retail-named unit status section")

-- Widget calls the page widgets make that the shared stubs do not model. Added
-- after the boot, so the load itself runs on the same surface client_boot_smoke uses.
local Methods = world.widgets.Methods
local function Store(field) return function(self, value) self[field] = value end end
local function Fetch(field) return function(self) return self[field] end end
local extraMethods = {
    SetChecked = Store("checked"), GetChecked = Fetch("checked"),
    SetCheckedTexture = Store("checkedTexture"), GetCheckedTexture = Fetch("checkedTexture"),
    SetDisabledCheckedTexture = Store("disabledCheckedTexture"), GetDisabledCheckedTexture = Fetch("disabledCheckedTexture"),
    GetDisabledTexture = Fetch("disabledTexture"), GetHighlightTexture = Fetch("highlightTexture"),
    GetNormalTexture = Fetch("normalTexture"), GetPushedTexture = Fetch("pushedTexture"),
    -- Native setters materialize a Texture when passed a file path.
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
}
for name, method in pairs(extraMethods) do
    if Methods[name] == nil then Methods[name] = method end
end
-- A native slider starts at its minimum; the stub leaves the value unset.
local StubGetValue = Methods.GetValue
Methods.GetValue = function(self)
    local value = StubGetValue(self)
    if value == nil then value = self.minimum or 0 end
    return value
end

local env, MSUF = world.env, world.core
local M = world.options.MSUF2
local W = M and M.Widgets
Check(type(M) == "table" and type(M.BuildUnitStatusSection) == "function" and type(W) == "table"
    and type(W.PageBuilder) == "function" and type(M.CreateContext) == "function", "the Menu2 status section builder is missing")
env.MSUF_EnsureDB(true)
local supportsThreat = MSUF.Client.SupportsThreatText == true

-- Record what the status section itself builds: toggles and buttons by label,
-- tooltips by control, and its refresh body. Only calls made from the section
-- file count, so a widget helper's own calls cannot stand in for them.
local function FromSection()
    local info = debug.getinfo(3, "S")
    return info ~= nil and info.source:gsub("\\", "/"):find(SECTION, 1, true) ~= nil
end
local toggles, buttons, tooltips, sectionRefresh = {}, {}, {}, nil
local THREAT_TOGGLES = { ["Color by threat"] = true, Background = true }
local ToggleAt, Button, AddTooltip, TrackCollapsibleRefresh = W.ToggleAt, W.Button, M.AddTooltip, M.TrackCollapsibleRefresh
W.ToggleAt = function(parent, label, ...)
    local control = ToggleAt(parent, label, ...)
    if FromSection() and THREAT_TOGGLES[label] then
        Check(toggles[label] == nil, "the status section builds two toggles labelled " .. label)
        toggles[label] = control
    end
    return control
end
W.Button = function(parent, label, ...)
    local control = Button(parent, label, ...)
    if FromSection() and buttons[label] == nil then buttons[label] = control end
    return control
end
M.AddTooltip = function(control, title, text, ...)
    if FromSection() then tooltips[control] = { title = title, text = text } end
    if AddTooltip then return AddTooltip(control, title, text, ...) end
end
M.TrackCollapsibleRefresh = function(ctx, section, refresh, ...)
    if FromSection() then sectionRefresh = refresh end
    return TrackCollapsibleRefresh(ctx, section, refresh, ...)
end

-- The status refresh the section requests for Threat % (the spec's refresh bridge).
local threatRefreshes = {}
local ThreatRefresh = env.MSUF_RequestThreatIndicatorRefresh
Check((type(ThreatRefresh) == "function") == supportsThreat,
    "the threat refresh bridge " .. (supportsThreat and "is missing" or "exists on a client without the threat text"))
env.MSUF_RequestThreatIndicatorRefresh = function(unit, ...)
    threatRefreshes[#threatRefreshes + 1] = unit
    return ThreatRefresh(unit, ...)
end

M.cache = M.cache or {}
M.scrollChild = M.scrollChild or env.CreateFrame("Frame", nil, env.UIParent)
local wrapper = env.CreateFrame("Frame", nil, M.scrollChild)
local entry = { key = "uf_target", wrapper = wrapper, refreshers = {}, fontStrings = {}, searchWidgets = {}, hiddenBuild = true }
local ctx = M.CreateContext("uf_target", wrapper, entry)
M.BuildUnitStatusSection(ctx, W.PageBuilder(ctx), "target")
Check(type(sectionRefresh) == "function", "the status section tracks no refresh")
local reset = buttons["Reset selected"]
Check(reset ~= nil and type(reset:GetScript("OnClick")) == "function", "the status section has no Reset selected button")

local curve, background = toggles["Color by threat"], toggles.Background
if not supportsThreat then
    Check(curve == nil and background == nil, "a client without the threat text builds the Threat % toggles")
    print(string.format("unit_status_threat_controls_smoke: ok (%s, no Threat %% controls)", flavor))
    return
end
Check(curve ~= nil and background ~= nil, "the Target status section lost its Color by threat or Background toggle")

local DB = env.MSUF_DB
local target = DB.target
local function Select(value)
    M.unitStatusSelection = M.unitStatusSelection or {}
    M.unitStatusSelection.target = value
    sectionRefresh()
end
-- Checked states come from the page refreshers, as when the page is shown.
local function RefreshPage()
    for _, refresher in ipairs(entry.refreshers) do refresher() end
end
local function Shown(control) return control:IsShown() == true end
local function Enabled(control) return control._msuf2AppliedEnabled ~= false end
local function Click(control) control:GetScript("OnClick")(control) end
local function Compiled()
    MSUF.UF.Config.Refresh()
    return MSUF.UF.Config.GetSpec("target").status.threat
end

-- 1. Threat % selected: both toggles shown and enabled, on by default.
Select("statusThreat")
RefreshPage()
for label, control in pairs({ ["Color by threat"] = curve, Background = background }) do
    Check(Shown(control) and Enabled(control), label .. " is not shown and enabled while Threat % is selected")
    Check(control:GetChecked() == true, label .. " does not show its default (on)")
end
local help = tooltips[background]
Check(help and help.title == "Background" and type(help.text) == "string" and help.text:find("dark plate", 1, true),
    "the Background toggle lost its tooltip")

-- 2. Each click writes the Target key, requests the threat refresh for Target,
-- and reaches the unit compile.
local compiled = Compiled()
Check(compiled and compiled.background == true and compiled.colorCurve == true, "harness: the default compile has no plate or curve")
for _, case in ipairs({
    { label = "Background", control = background, key = "threatIndicatorBackground", field = "background" },
    { label = "Color by threat", control = curve, key = "threatIndicatorColorCurve", field = "colorCurve" },
}) do
    local before = #threatRefreshes
    Click(case.control)
    Check(target[case.key] == false, case.label .. " off does not write target." .. case.key .. " (" .. tostring(target[case.key]) .. ")")
    Check(#threatRefreshes == before + 1 and threatRefreshes[#threatRefreshes] == "target",
        case.label .. " off does not refresh the Target threat text")
    Check(case.control:GetChecked() == false, case.label .. " still shows on after it was turned off")
    Check(Compiled()[case.field] == false, case.label .. " off does not reach the unit compile")
end

-- 3. Another indicator selected: both toggles hidden.
Select("level")
Check(not Shown(curve) and not Shown(background), "the Threat % toggles stay visible with Level Text selected")

-- 4. Threat % selected but off: both toggles shown and disabled.
target.showThreatIndicator = false
Select("statusThreat")
Check(Shown(curve) and Shown(background) and not Enabled(curve) and not Enabled(background),
    "the Threat % toggles stay enabled with Threat % off")
target.showThreatIndicator = nil
Select("statusThreat")
Check(Enabled(curve) and Enabled(background), "the Threat % toggles stay disabled with Threat % on")

-- 5. Reset selected returns Threat % to its defaults, both toggles included.
target.threatIndicatorSize, target.threatIndicatorAnchor = 15, "TOP"
Click(reset)
for _, key in ipairs({ "threatIndicatorColorCurve", "threatIndicatorBackground", "threatIndicatorSize", "threatIndicatorAnchor" }) do
    Check(target[key] == nil, "Reset selected leaves target." .. key .. " = " .. tostring(target[key]))
end
compiled = Compiled()
Check(compiled.background == true and compiled.colorCurve == true, "Reset selected does not bring back the plate and the curve")
RefreshPage()
Check(background:GetChecked() == true and curve:GetChecked() == true, "the Threat % toggles do not show on after Reset selected")

print(string.format("unit_status_threat_controls_smoke: ok (%s, Threat %% controls built and driven)", flavor))
