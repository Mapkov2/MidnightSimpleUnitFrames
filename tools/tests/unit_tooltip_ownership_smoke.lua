-- unit_tooltip_ownership_smoke.lua <repoRoot>
--
-- The unit and group frame OnLeave (Tooltips.HideUnit) may hide GameTooltip
-- only while MSUF still owns it (Runtime/MSUF_UnitTooltips.lua). It used to
-- hide any shown tooltip when no MSUF ownership mark was set (Modifier mode
-- without the key held, or a mark already cleared), and a tooltip another UI
-- took over with SetOwner, without hiding it first, kept MSUF's marks, so the
-- next OnLeave hid that UI's tooltip too (red without the fix).
--
-- Per client, on the real core + Options graph (tools/tests/client_world.lua),
-- with GameTooltip modelled the way the client owns it before the files load:
--   1. a foreign tooltip survives the OnLeave of a frame MSUF never showed;
--   2. a takeover drops the marks and survives the old owner's OnLeave;
--   3. the OnLeave of a frame whose tooltip a second MSUF frame now shows
--      keeps it;
--   4. MSUF still hides its own tooltip on OnLeave, for all three anchors.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Run(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    -- GameTooltip as the client owns it, in place before any file hooks it.
    local gt = env.GameTooltip
    gt.owner, gt.shown = nil, false
    function gt:SetOwner(owner) self.owner = owner end
    function gt:IsOwned(frame) return self.owner == frame end
    function gt:GetOwner() return self.owner end
    function gt:SetUnit(unit) self.unit = unit end
    function gt:IsShown() return self.shown end
    function gt:Show() self.shown = true end
    function gt:Hide()
        if not self.shown then return end
        self.shown = false
        local onHide = self.scripts and self.scripts.OnHide
        if onHide then onHide(self) end
    end
    function gt:IsForbidden() return false end
    function gt:ClearAllPoints() end
    function gt:SetPoint() end
    env.GameTooltip_SetDefaultAnchor = function(tooltip, parent) tooltip:SetOwner(parent, "ANCHOR_NONE") end
    env.UnitExists = function() return true end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local Tooltips = assert(world.core.Tooltips, flavor .. ": no MSUF.Tooltips")

    env.MSUF_EnsureDB()
    local general = env.MSUF_DB.general
    general.unitTooltipProvider = "GAME"
    general.unitTooltipMode = "ALWAYS"

    local unitFrame = env.CreateFrame("Button", nil, env.UIParent)
    local groupFrame = env.CreateFrame("Button", nil, env.UIParent)
    local foreign = env.CreateFrame("Frame", nil, env.UIParent)
    local function ShowForeign()
        gt:SetOwner(foreign, "ANCHOR_RIGHT")
        gt:Show()
    end

    gt:Hide()
    ShowForeign()
    Tooltips.HideUnit(unitFrame)
    Check(gt.shown and gt.owner == foreign, flavor .. ": a frame MSUF never showed hid a foreign tooltip on OnLeave")

    for _, anchor in ipairs({ "EXTERNAL", "CURSOR", "FIXED" }) do
        general.unitTooltipAnchor = anchor
        Tooltips.Refresh()
        gt:Hide()
        Check(Tooltips.ShowUnit(unitFrame, "player") == true and gt.shown, flavor .. " " .. anchor .. ": no unit tooltip")
        Tooltips.ShowUnit(groupFrame, "party1")
        Tooltips.HideUnit(unitFrame)
        Check(gt.shown and gt._msufUnitTooltipOwner == groupFrame,
            flavor .. " " .. anchor .. ": the old frame's OnLeave hid the group frame tooltip")
        -- Another UI takes GameTooltip without hiding it first.
        ShowForeign()
        Check(gt._msufUnitTooltipOwner == nil and gt._msufUnitTooltipUnit == nil and gt._msufUnitTooltipAnchor == nil,
            flavor .. " " .. anchor .. ": a takeover kept MSUF's ownership marks")
        Tooltips.HideUnit(groupFrame)
        Check(gt.shown and gt.owner == foreign, flavor .. " " .. anchor .. ": OnLeave hid a tooltip another UI took over")
        Tooltips.ShowUnit(unitFrame, "player")
        Tooltips.HideUnit(unitFrame)
        Check(not gt.shown and gt._msufUnitTooltipOwner == nil,
            flavor .. " " .. anchor .. ": OnLeave did not release MSUF's own tooltip")
    end
end

local flavors = World.Flavors(root)
for _, flavor in ipairs(flavors) do Run(flavor) end
print("unit_tooltip_ownership_smoke: ok (" .. table.concat(flavors, ", ") .. ")")
