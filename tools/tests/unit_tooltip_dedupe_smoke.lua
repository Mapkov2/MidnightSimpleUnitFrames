-- unit_tooltip_dedupe_smoke.lua <repoRoot>
--
-- Tooltips.ShowUnit (Runtime/MSUF_UnitTooltips.lua) skips rebuilding a unit
-- tooltip MSUF already shows for the same frame and unit. It used to confirm
-- that with GameTooltip:GetUnit(), which on Mainline clients resolves the shown
-- unit through UnitTokenFromGUID (SecretWhenUnitIdentityRestricted): re-showing
-- the tooltip of an enemy player in an arena or battleground (a held modifier
-- in Modifier mode, a repeated OnEnter) compared that secret and raised.
--
-- This smoke boots each client's real load graph, models GameTooltip the way
-- the client owns it (SetOwner, IsOwned, OnHide) and pins: the displayed unit
-- is never read back; the dedupe still holds for all three anchors; a tooltip
-- another owner took is rebuilt; a hidden tooltip is rebuilt.
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
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local Tooltips = assert(world.core.Tooltips, flavor .. ": no MSUF.Tooltips")

    -- GameTooltip as the client owns it. SetOwner here does not hide the
    -- tooltip, the harder case: only the owner can tell a taken tooltip apart.
    local gt = env.GameTooltip
    local log = { setUnit = 0, getUnit = 0 }
    gt.owner, gt.shown = nil, false
    function gt:SetOwner(owner) self.owner = owner end
    function gt:IsOwned(frame) return self.owner == frame end
    function gt:GetOwner() return self.owner end
    function gt:SetUnit(unit) self.unit = unit; log.setUnit = log.setUnit + 1 end
    function gt:GetUnit()
        -- UnitTokenFromGUID answers a secret for an identity-restricted unit.
        log.getUnit = log.getUnit + 1
        return "Secret", newproxy(false)
    end
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
    env.UnitExists = function(unit) return unit == "arena1" or unit == "target" end

    env.MSUF_EnsureDB()
    local general = env.MSUF_DB.general
    general.unitTooltipProvider = "GAME"
    general.unitTooltipMode = "ALWAYS"

    local frame = env.CreateFrame("Button", nil, env.UIParent)
    local other = env.CreateFrame("Frame", nil, env.UIParent)
    for _, anchor in ipairs({ "EXTERNAL", "CURSOR", "FIXED" }) do
        general.unitTooltipAnchor = anchor
        if Tooltips.Refresh then Tooltips.Refresh() end
        gt:Hide()
        gt.owner = nil
        log.setUnit, log.getUnit = 0, 0

        Check(Tooltips.ShowUnit(frame, "arena1") == true and log.setUnit == 1 and gt.shown == true,
            flavor .. " " .. anchor .. ": the first hover must build the unit tooltip")
        -- The modifier watcher and a repeated OnEnter re-show the same tooltip.
        Check(Tooltips.ShowUnit(frame, "arena1") == true, flavor .. " " .. anchor .. ": the re-show failed")
        Check(log.getUnit == 0, flavor .. " " .. anchor
            .. ": the dedupe read the displayed unit back (a secret on identity-restricted units)")
        Check(log.setUnit == 1, flavor .. " " .. anchor .. ": the re-show rebuilt a tooltip MSUF already shows")

        -- Another owner takes GameTooltip: the next hover rebuilds ours.
        gt:SetOwner(other, "ANCHOR_RIGHT")
        Tooltips.ShowUnit(frame, "arena1")
        Check(log.setUnit == 2, flavor .. " " .. anchor .. ": a tooltip another owner took was not rebuilt")

        -- A hidden tooltip is rebuilt, and another unit on the same frame too.
        gt:Hide()
        Tooltips.ShowUnit(frame, "arena1")
        Check(log.setUnit == 3, flavor .. " " .. anchor .. ": a hidden tooltip was not rebuilt")
        Tooltips.ShowUnit(frame, "target")
        Check(log.setUnit == 4 and gt.unit == "target", flavor .. " " .. anchor .. ": another unit was not shown")
        Check(log.getUnit == 0, flavor .. " " .. anchor .. ": the displayed unit was read back")
    end
    print("unit_tooltip_dedupe_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla" }) do Run(flavor) end
