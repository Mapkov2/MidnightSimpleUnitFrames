-- Exercise the real lazy pages and bindings: a closed feature must be editable
-- before its detail controls exist, and opening it must reuse the same switch.
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end
-- The shared catalog stub does not model native parent->child traversal.
-- Add it before loading modules that capture CreateFrame locally.
local stubs = Read("tools/AssistantTraining/wow_stubs.lua")
stubs = stubs:gsub("frame%._parent = parent or G%.UIParent", [[frame._parent = parent or G.UIParent
    if frame._parent and frame._parent._children then
        table.insert(frame._parent._children, frame)
    end]])
local nativeTimerStub = [[
function C_Timer.NewTimer(delay, callback)
    local timer = { active = true }
    function timer:Cancel() self.active = false end
    C_Timer.After(delay, function()
        if timer.active then timer.active = false; callback(timer) end
    end)
    return timer
end
]]
stubs = stubs:gsub("\nreturn {", nativeTimerStub .. "\nreturn {", 1)
package.preload["wow_stubs"] = assert(loadstring(stubs))
local harness = Read("tools/assistant_v1_catalog_crosswalk.lua")
local cut = assert(harness:find("\nlocal pageBuildFailures = {}", 1, true))
local M = assert(loadstring(harness:sub(1, cut - 1) .. "\nreturn M"))()
local createFrame = _G.CreateFrame
_G.CreateFrame = function(kind, ...)
    local frame = createFrame(kind, ...)
    function frame:SetParent(nextParent)
        local previous = self:GetParent()
        if previous and type(previous._children) == "table" then
            for i = #previous._children, 1, -1 do
                if previous._children[i] == self then table.remove(previous._children, i) end
            end
        end
        self._parent = nextParent
        if nextParent and type(nextParent._children) == "table" then
            nextParent._children[#nextParent._children + 1] = self
        end
    end
    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown ~= false end
    function frame:SetFrameStrata(value) self._strata = value end
    function frame:GetFrameStrata() return self._strata or "MEDIUM" end
    function frame:SetFrameLevel(value) self._level = value end
    function frame:GetFrameLevel() return self._level or 0 end
    function frame:GetScript(event) return self._scripts[event] end
    function frame:Enable() self._enabled = true end
    function frame:Disable() self._enabled = false end
    function frame:SetEnabled(value) self._enabled = value == true end
    function frame:IsEnabled() return self._enabled ~= false end
    function frame:SetAlpha(value) self._alpha = value end
    function frame:GetAlpha() return self._alpha or 1 end
    frame._msuf2UnitFrameGateAlwaysEnabled = false
    frame._msuf2GroupFrameGateAlwaysEnabled = false
    if kind == "CheckButton" then
        function frame:SetChecked(value) self._checked = value and true or false end
        function frame:GetChecked() return self._checked == true end
    end
    return frame
end
M.accordionState = {}
M.gfScope = "party"
local group = M.BuildPageEntry("gf_layout", false)
local function CheckMaster(page, id)
    local entry = assert(page.sections[id]._msuf2CollapsibleEntry)
    local main = assert(entry.featureSwitch, "master switch missing")
    local click = assert(main:GetScript("OnClick"))
    if not main:GetChecked() then click(main) end
    click(main)
    assert(not main:GetChecked() and main:IsEnabled(), "master must remain available when off")
    assert(page._msuf2FrameGate and page._msuf2FrameGate.enabled == false, "global gate not applied")
    local portrait = page.sections.portrait._msuf2CollapsibleEntry
    assert(portrait.header:GetAlpha() < 1, "closed accordion not greyed out")
    portrait.SetOpenImmediate(true)
    local feature = portrait.featureSwitch
    assert(not feature:IsEnabled(), "lazy feature header escaped the disabled gate")
    assert(not rawget(feature, "_msuf2ContentSwitch"), "duplicate feature switch created lazily")
    entry.SetOpenImmediate(true)
    assert(not rawget(main, "_msuf2ContentSwitch"), "duplicate master switch created lazily")
    assert(main:IsEnabled() and main:GetParent() == entry.header, "master not reachable while open")
    click(main)
    assert(main:GetChecked() and feature:IsEnabled(), "header master failed to re-enable the feature")
    assert(portrait.header:GetAlpha() == 1, "accordion stayed grey after enabling")
    portrait.SetOpenImmediate(false)
    entry.SetOpenImmediate(false)
end
CheckMaster(group, "general")
local partyEnabled = M.GroupPage.Conf("party").enabled
for _, scope in ipairs({ "raid", "mythicraid" }) do
    M.gfScope = scope
    M.Refresh({ entry = group, key = "gf_layout", refreshers = group.refreshers })
    CheckMaster(group, "general")
    assert(M.GroupPage.Conf("party").enabled == partyEnabled, "group toggle changed another scope")
end
M.gfScope = "party"
M.Refresh({ entry = group, key = "gf_layout", refreshers = group.refreshers })
local function CheckSection(page, id)
    local section = assert(page.sections[id], "section missing: " .. id)
    local entry = assert(section._msuf2CollapsibleEntry)
    local switch = assert(entry.featureSwitch, "closed section has no switch: " .. id)
    assert(not entry.open, "cold section unexpectedly opened: " .. id)
    assert(switch:GetParent() == entry.header, "switch is hidden inside section body")
    local before = switch:GetChecked() and true or false
    local click = assert(switch:GetScript("OnClick"), "switch has no real binding")
    click(switch)
    assert((switch:GetChecked() and true or false) ~= before, "closed switch did not toggle")
    assert(not entry.open, "toggling a feature expanded its section")
    click(switch)
    assert((switch:GetChecked() and true or false) == before, "toggle did not restore state")
    entry.SetOpenImmediate(true)
    assert(entry.featureSwitch == switch, "lazy build replaced the bound header switch")
    assert(not rawget(switch, "_msuf2ContentSwitch"), "duplicate switch in section body: " .. id)
    assert(switch:GetParent() == entry.header, "open section lost its header switch")
    click(switch)
    assert(switch:GetChecked() ~= before, "open header switch did not toggle")
    assert(entry.open, "switch click collapsed its section")
    click(switch)
    assert(switch:GetChecked() == before, "open header switch did not restore state")
    entry.SetOpenImmediate(false)
    assert(switch:GetParent() == entry.header, "closing section hid its switch")
end
CheckSection(group, "portrait")
CheckSection(group, "power")
CheckSection(group, "range")
local unit = M.BuildPageEntry("uf_player", false)
CheckMaster(unit, "frame_basics")
local unitMaster = unit.sections.frame_basics._msuf2CollapsibleEntry.featureSwitch
unitMaster:GetScript("OnClick")(unitMaster)
for _, id in ipairs({ "power_bar", "castbar", "unit_dispel_overlay", "unit_dispel_symbol" }) do
    local entry = unit.sections[id]._msuf2CollapsibleEntry
    assert(not entry.featureSwitch:IsEnabled(), "cold header escaped master gate: " .. id)
    entry.SetOpenImmediate(true)
    assert(not entry.featureSwitch:IsEnabled(), "built header escaped master gate: " .. id)
    assert(not rawget(entry.featureSwitch, "_msuf2ContentSwitch"), "duplicate switch escaped lazy gate: " .. id)
    entry.SetOpenImmediate(false)
end
unitMaster:GetScript("OnClick")(unitMaster)
CheckSection(unit, "portrait")
CheckSection(unit, "power_bar")
CheckSection(unit, "castbar")
CheckSection(unit, "unit_dispel_overlay")
CheckSection(unit, "unit_dispel_symbol")
local bars = M.BuildPageEntry("gf_bars", false)
CheckSection(bars, "dispel")
CheckSection(bars, "dispelSymbol")
CheckSection(bars, "dstripe")
local auras = M.BuildPageEntry("gf_auras", false)
M.Refresh({ entry = auras, key = "gf_auras", refreshers = auras.refreshers })
CheckSection(auras, "auras")
local playerEnabled = _G.MSUF_DB.player.enabled
local target = M.BuildPageEntry("uf_target", false)
CheckMaster(target, "frame_basics")
assert(_G.MSUF_DB.player.enabled == playerEnabled, "target master changed player enabled state")
assert(M.Theme.colors.glassShell[4] < 1, "glass transparency lost")
assert(M.Theme.colors.panel[4] < 1, "panel transparency lost")
assert(not M.Theme.flatSurfaces, "flat renderer replaced the authored glass")
-- Build every registered menu using the native UI stubs: page ownership must
-- not determine whether an accordion receives the shared visual treatment.
local accordionCount, pageCount = 0, 0
for key in pairs(M.pages) do
    local page = assert(M.BuildPageEntry(key, false), "menu failed to build: " .. key)
    pageCount = pageCount + 1
    for id, section in pairs(page.sections or {}) do
        local entry = section._msuf2CollapsibleEntry
        if entry then
            assert(entry.header._msuf2AccordionBorder and #entry.header._msuf2AccordionBorder == 4,
                "missing shared border: " .. key .. "/" .. id)
            assert(entry.openHighlightEnabled == true, "missing open highlight: " .. key .. "/" .. id)
            accordionCount = accordionCount + 1
        end
    end
end
local buildFailure = {}
local builds = 0
M.pages.test_error_recovery = { build = function()
    builds = builds + 1
    if builds == 1 then error(buildFailure) end
    return 100
end }
local builtOK, buildError = pcall(M.BuildPageEntry, "test_error_recovery", false)
assert(not builtOK and buildError == buildFailure, "page builder hid its original error")
local incomplete = M.cache.test_error_recovery
assert(incomplete and incomplete._msuf2BuildIncomplete, "failed page was cached as complete")
local recovered = M.BuildPageEntry("test_error_recovery", false)
assert(recovered ~= incomplete and not recovered._msuf2BuildIncomplete and builds == 2, "failed page could not reopen")
M.InvalidatePage("test_error_recovery")
M.pages.test_error_recovery = nil
assert(accordionCount > 30, "insufficient cross-menu accordion coverage")
print("accordion parity: " .. accordionCount .. " accordions across " .. pageCount .. " menus")
print("menu2_single_switch_smoke: one header switch, open/closed actions and master gating passed")
