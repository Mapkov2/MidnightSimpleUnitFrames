-- unit_tooltip_raiderio_smoke.lua <repoRoot> [flavor]
--
-- Raider.IO draws its profile from a Unit tooltip post-call that finds the
-- unit through the tooltip data's GUID and skips the tooltip when that GUID is
-- secret. MSUF builds its unit tooltips as addon code, so under restrictions
-- (a running keystone, combat) the GUID arrives secret and the score was
-- missing on MSUF frames while Blizzard's frames showed it.
-- Tooltips.ShowUnit (Runtime/MSUF_UnitTooltips.lua) therefore adds one post-call
-- that hands Raider.IO the plain unit token MSUF hovered.
--
-- This smoke boots each client's real load graph and pins: a secret GUID draws
-- the profile once for the hovered unit; a readable GUID is left to Raider.IO
-- (never drawn twice); Raider.IO's unit-tooltip, modifier and combat settings
-- hold; non-players, a frame no longer hovered, a hidden tooltip and other
-- tooltips draw nothing; a refresh while hovered draws again; without
-- Raider.IO no post-call is added.
--
-- Plain Lua 5.1, repo root as arg 1; one flavor as arg 2, or Mainline, Forever
-- and Vanilla.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local SECRET = newproxy(false)
local UNIT_TYPE = 2

local function Boot(flavor, withRaiderIO)
    local world = World.New(root, flavor)
    local env = world.env
    -- MSUF_UnitTooltips captures issecretvalue while it loads.
    env.issecretvalue = function(value) return value == SECRET end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local Tooltips = assert(world.core.Tooltips, flavor .. ": no MSUF.Tooltips")

    local state = { postCalls = {}, drawn = {}, guid = SECRET, players = { party1 = true }, modifier = false }
    -- The world's Enum is a stub that drops writes; layer the tooltip type on it.
    env.Enum = setmetatable({ TooltipDataType = { Unit = UNIT_TYPE } }, { __index = env.Enum })
    env.TooltipDataProcessor = {
        AddTooltipPostCall = function(kind, callback)
            state.postCalls[#state.postCalls + 1] = { kind = kind, callback = callback }
        end,
    }
    env.UnitExists = function(unit) return unit == "party1" or unit == "target" end
    env.UnitIsPlayer = function(unit) return state.players[unit] == true end
    env.IsModifierKeyDown = function() return state.modifier end
    -- The world answers unknown globals with a stub table; false reads as absent.
    env.RaiderIO, env.RaiderIO_Config = false, false
    if withRaiderIO then
        env.RaiderIO_Config = {}
        env.RaiderIO = {
            ShowProfile = function(tooltip, unit)
                state.drawn[#state.drawn + 1] = { tooltip = tooltip, unit = unit }
                return true
            end,
        }
    end

    -- GameTooltip as the client owns it; SetUnit runs the Unit post-calls the
    -- way TooltipDataHandlerMixin:ProcessInfo does.
    local gt = env.GameTooltip
    gt.owner, gt.shown = nil, false
    function gt:SetOwner(owner) self.owner = owner end
    function gt:IsOwned(frame) return self.owner == frame end
    function gt:GetOwner() return self.owner end
    function gt:GetPrimaryTooltipData() return self.data end
    function gt:RunPostCalls()
        for _, entry in ipairs(state.postCalls) do
            if entry.kind == UNIT_TYPE then entry.callback(self, self.data) end
        end
    end
    function gt:SetUnit(unit)
        self.unit = unit
        self.data = { type = UNIT_TYPE, guid = state.guid }
        self:RunPostCalls()
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

    -- 7.0 keeps namespace exports off the global table.
    local ensureDB = env.MSUF_EnsureDB or world.core.PublicGlobals.MSUF_EnsureDB
    ensureDB()
    local general = env.MSUF_DB.general
    general.unitTooltipProvider = "GAME"
    general.unitTooltipMode = "ALWAYS"
    general.unitTooltipAnchor = "EXTERNAL"
    if Tooltips.Refresh then Tooltips.Refresh() end

    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame.mouseOver = true
    return world, env, Tooltips, gt, frame, state
end

local function RunWithRaiderIO(flavor)
    local world, env, Tooltips, gt, frame, state = Boot(flavor, true)
    local function Hover(unit)
        gt:Hide()
        local before = #state.drawn
        Check(Tooltips.ShowUnit(frame, unit or "party1") == true, flavor .. ": the hover built no tooltip")
        return #state.drawn - before
    end

    Check(Hover() == 1, flavor .. ": a secret GUID must draw the Raider.IO profile once")
    Check(#state.postCalls == 1 and state.postCalls[1].kind == UNIT_TYPE,
        flavor .. ": exactly one Unit post-call must be added")
    local last = state.drawn[#state.drawn]
    Check(last.tooltip == gt and last.unit == "party1", flavor .. ": the profile went to the wrong tooltip or unit")
    Check(Hover() == 1 and #state.postCalls == 1, flavor .. ": a second hover added another post-call")

    -- A readable GUID is Raider.IO's own post-call; drawing it here doubles it.
    state.guid = "Player-1-0000001"
    Check(Hover() == 0, flavor .. ": a readable GUID was drawn a second time")
    state.guid = SECRET

    state.players.party1 = nil
    Check(Hover() == 0, flavor .. ": a non-player got a Raider.IO profile")
    state.players.party1 = true

    -- Raider.IO's own unit-tooltip settings.
    env.RaiderIO_Config.enableUnitTooltips = false
    Check(Hover() == 0, flavor .. ": disabled Raider.IO unit tooltips were drawn")
    env.RaiderIO_Config.enableUnitTooltips = nil
    env.RaiderIO_Config.showScoreModifier = true
    Check(Hover() == 0, flavor .. ": the modifier-only score was drawn without a modifier")
    state.modifier = true
    Check(Hover() == 1, flavor .. ": the modifier-only score was not drawn with a modifier")
    state.modifier = false
    env.RaiderIO_Config.showScoreModifier = nil
    env.RaiderIO_Config.showScoreInCombat = false
    world:EnterCombat()
    Check(Hover() == 0, flavor .. ": the out-of-combat-only score was drawn in combat")
    world:LeaveCombat()
    Check(Hover() == 1, flavor .. ": the out-of-combat-only score was not drawn out of combat")
    env.RaiderIO_Config.showScoreInCombat = nil

    -- A data refresh while hovered draws again; a frame no longer hovered (a
    -- marker another UI left behind) and a hidden tooltip draw nothing.
    Hover()
    local count = #state.drawn
    gt:RunPostCalls()
    Check(#state.drawn == count + 1, flavor .. ": a refresh while hovered lost the profile")
    frame.mouseOver = false
    gt:RunPostCalls()
    Check(#state.drawn == count + 1, flavor .. ": a frame no longer hovered drew a profile")
    frame.mouseOver = true
    gt:Hide()
    gt:RunPostCalls()
    Check(#state.drawn == count + 1, flavor .. ": a hidden tooltip drew a profile")

    local other = env.CreateFrame("GameTooltip", nil, env.UIParent)
    other._msufUnitTooltipOwner, other._msufUnitTooltipUnit = frame, "party1"
    other.data = { type = UNIT_TYPE, guid = SECRET }
    function other:GetPrimaryTooltipData() return self.data end
    state.postCalls[1].callback(other, other.data)
    Check(#state.drawn == count + 1, flavor .. ": another tooltip got a profile")
end

local function RunWithoutRaiderIO(flavor)
    local _, _, Tooltips, _, frame, state = Boot(flavor, false)
    Check(Tooltips.ShowUnit(frame, "party1") == true, flavor .. ": the hover built no tooltip")
    Check(#state.postCalls == 0, flavor .. ": a post-call was added without Raider.IO")
end

for _, flavor in ipairs(arg[2] and { arg[2] } or { "Mainline", "Forever", "Vanilla" }) do
    RunWithRaiderIO(flavor)
    RunWithoutRaiderIO(flavor)
    print("unit_tooltip_raiderio_smoke: ok (" .. flavor .. ")")
end
