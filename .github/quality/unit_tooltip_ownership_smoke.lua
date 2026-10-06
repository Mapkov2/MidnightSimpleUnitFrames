-- Run with Lua 5.1: unit_tooltip_ownership_smoke.lua <repository root>
local root = assert(arg[1], "repository root required")
local combat, ctrl, watcher = false, false
UIParent = {}
MSUF_DB = { general = { unitTooltipProvider = "GAME", unitTooltipAnchor = "FIXED",
    unitTooltipMode = "ALWAYS", unitTooltipModifier = "CTRL" } }
InCombatLockdown = function() return combat end
IsControlKeyDown = function() return ctrl end
UnitExists = function() return true end
CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    watcher = frame
    return frame
end
local tooltip = { shown = false, scripts = {}, builds = 0 }
GameTooltip = tooltip
function tooltip:IsForbidden() return false end
function tooltip:IsShown() return self.shown end
function tooltip:HookScript(event, callback) self.scripts[event] = callback end
function tooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
function tooltip:SetUnit(unit) self.unit = unit; self.builds = self.builds + 1 end
function tooltip:GetUnit() return "Player", self.unit end
function tooltip:ClearAllPoints() end
function tooltip:SetPoint() end
function tooltip:Show() self.shown = true end
function tooltip:Hide()
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
GameTooltip_SetDefaultAnchor = function(tip, owner) tip:SetOwner(owner, "ANCHOR_NONE") end
hooksecurefunc = function(object, key, callback)
    local original = object[key]
    object[key] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end
local ns = {
    Translate = function(value) return value end,
    ExportPublic = function(key, value) _G[key] = value; return value end,
    Require = function(key) assert(key == "MSUF_EnsureDB"); return function() end end,
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_UnitTooltips.lua"))("MSUF", ns)
local unitOwner = { IsMouseOver = function() return true end }
local groupOwner, foreignOwner = {}, {}
local function ShowForeign()
    tooltip:SetOwner(foreignOwner, "ANCHOR_RIGHT")
    tooltip:Show()
end
ShowForeign()
ns.Tooltips.HideUnit(unitOwner)
assert(tooltip.shown, "unitframe OnLeave hid an unrelated tooltip")
for _, anchor in ipairs({ "FIXED", "CURSOR", "EXTERNAL" }) do
    MSUF_DB.general.unitTooltipAnchor = anchor
    ns.Tooltips.Refresh()
    assert(ns.Tooltips.ShowUnit(unitOwner, "player"))
    assert(tooltip.shown and tooltip._msufUnitTooltipOwner == unitOwner)
    local builds = tooltip.builds
    ns.Tooltips.ShowUnit(unitOwner, "player")
    assert(tooltip.builds == builds, "identical hover rebuilt the tooltip")
    ns.Tooltips.ShowUnit(groupOwner, "party1")
    ns.Tooltips.HideUnit(unitOwner)
    assert(tooltip.shown and tooltip._msufUnitTooltipOwner == groupOwner,
        "old unitframe OnLeave hid the group frame tooltip")
    -- Another UI can take GameTooltip without a preceding OnHide.
    ShowForeign()
    assert(tooltip._msufUnitTooltipOwner == nil and tooltip._msufUnitTooltipUnit == nil
        and tooltip._msufUnitTooltipAnchor == nil, "tooltip takeover retained stale MSUF ownership")
    ns.Tooltips.HideUnit(groupOwner)
    assert(tooltip.shown, "group OnLeave hid a tooltip after its owner changed")
    ns.Tooltips.ShowUnit(unitOwner, "player")
    ns.Tooltips.HideUnit(unitOwner)
    assert(not tooltip.shown and tooltip._msufUnitTooltipOwner == nil,
        "unitframe OnLeave failed to release its own tooltip")
end
MSUF_DB.general.unitTooltipMode = "MODIFIER"
ns.Tooltips.Refresh()
assert(not ns.Tooltips.ShowUnit(unitOwner, "player"))
assert(watcher.events.MODIFIER_STATE_CHANGED, "modifier hover did not register its event")
ctrl = true
watcher.scripts.OnEvent(watcher, "MODIFIER_STATE_CHANGED")
assert(tooltip.shown and tooltip._msufUnitTooltipOwner == unitOwner, "Ctrl did not show the unit tooltip")
ShowForeign()
ctrl = false
watcher.scripts.OnEvent(watcher, "MODIFIER_STATE_CHANGED")
assert(tooltip.shown, "modifier release hid a foreign tooltip")
ns.Tooltips.HideUnit(unitOwner)
assert(not watcher.events.MODIFIER_STATE_CHANGED, "modifier listener survived OnLeave")
MSUF_DB.general.unitTooltipMode = "OOC"
ns.Tooltips.Refresh()
ns.Tooltips.ShowUnit(unitOwner, "player")
combat = true
watcher.scripts.OnEvent(watcher, "PLAYER_REGEN_DISABLED")
assert(not tooltip.shown, "MSUF OOC mode did not hide its own tooltip on combat entry")
combat = false
watcher.scripts.OnEvent(watcher, "PLAYER_REGEN_ENABLED")
ns.Tooltips.ShowUnit(unitOwner, "player")
ShowForeign()
combat = true
watcher.scripts.OnEvent(watcher, "PLAYER_REGEN_DISABLED")
assert(tooltip.shown, "combat entry hid a tooltip that MSUF no longer owns")
MSUF_DB.general.unitTooltipMode = "NEVER"
ns.Tooltips.Refresh()
local builds = tooltip.builds
assert(not ns.Tooltips.ShowUnit(unitOwner, "player") and tooltip.builds == builds,
    "Never mode reached the tooltip builder")
-- The aura reminder's own OnLeave must also respect a subsequent owner.
combat = false
CreateFrame = function()
    local button = { scripts = {} }
    function button:SetScript(event, callback) self.scripts[event] = callback end
    function button:RegisterForClicks() end
    function button:ClearAllPoints() end
    function button:SetSize() end
    function button:SetPoint() end
    function button:SetFrameLevel() end
    function button:SetAttribute() end
    function button:Show() end
    return button
end
function tooltip:IsOwned(owner) return self.owner == owner end
function tooltip:SetSpellByID(id) self.spellID = id end
ns.MSUF_Auras3 = { SpellIndicators = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators_Effects.lua"))("MSUF", ns)
ns.MSUF_Auras3.SpellIndicatorModules.Effects({
    SyncFrameStrata = function() end, ResolveFrameStrata = function() end,
    SpellIconBaseOffset = function() return 0 end,
})
local parent = { GetFrameLevel = function() return 1 end }
ns.MSUF_Auras3.SpellIndicators.SyncReminderCastButtons(parent, {
    slots = { { slotKey = "test", castSpellID = 123, showTooltip = true } },
})
local reminder = parent._msufA3ReminderCastButtons.test
reminder.scripts.OnEnter(reminder)
assert(tooltip.shown and tooltip.owner == reminder and tooltip.spellID == 123)
reminder.scripts.OnLeave(reminder)
assert(not tooltip.shown, "aura reminder failed to hide its own tooltip")
reminder.scripts.OnEnter(reminder)
ShowForeign()
reminder.scripts.OnLeave(reminder)
assert(tooltip.shown, "aura reminder OnLeave hid a foreign tooltip")
print("unit_tooltip_ownership_smoke: OK")
