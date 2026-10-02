-- combat_regen_edge_smoke.lua <repoRoot>
--
-- The client sends PLAYER_REGEN_DISABLED while InCombatLockdown() still
-- answers false; the lockdown starts after that dispatch. A handler that asks
-- InCombatLockdown() while it runs for that event therefore decides "out of
-- combat" and keeps that answer for the whole fight. Kernel/MSUF_Util.lua
-- InCombat(event) is the one combat-state source for these decisions.
--
-- This smoke boots each client's real load graph through the client contract
-- kit (tools/tests/client_world.lua), enters and leaves combat in the client's
-- order (world:EnterCombat / world:LeaveCombat) and pins:
--   1. the kit itself: REGEN_DISABLED reaches handlers before the lockdown;
--   2. Util.InCombat(event) and the same-frame combat edge;
--   3. group frames: "Hide offline" without "also in combat" turns an offline
--      member from hidden to its offline fade when combat starts, also when the
--      out-of-combat fade pokes the member under a synthetic event after the
--      range driver ran (UnitFrames/Range/MSUF_UF_Group_RangeFade.lua);
--   4. texture layers: COMBAT layers show and OOC layers hide when combat
--      starts (UnitFrames/Effects/MSUF_UF_TextureLayer.lua);
--   5. unit tooltips: "out of combat only" turns hover-inert when combat
--      starts and drops the unit tooltip MSUF owns (Runtime/MSUF_UnitTooltips.lua).
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local OFFLINE_UNIT = "party1"

-- The client promises no order between frames that registered the same event.
-- A module must be right when its own handler runs first, before any other
-- handler could have marked the combat edge. Move the frames whose OnEvent
-- handler was defined in `fileName` to the front of the dispatch order.
local function HandlersFirst(world, fileName)
    local frames, first, rest = world.widgets.frames, {}, {}
    for index = 1, #frames do
        local frame = frames[index]
        local scripts = rawget(frame, "scripts")
        local handler = scripts and scripts.OnEvent
        local source = handler and debug.getinfo(handler, "S").source or ""
        if source:find(fileName, 1, true) then first[#first + 1] = frame else rest[#rest + 1] = frame end
    end
    for index = 1, #first do frames[index] = first[index] end
    for index = 1, #rest do frames[#first + index] = rest[index] end
    return #first
end

local function Boot(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    -- Unit APIs the engine captures at load.
    env.UnitIsConnected = function(unit) return unit ~= OFFLINE_UNIT end
    env.UnitExists = function(unit) return unit == "player" or unit == OFFLINE_UNIT end
    env.UnitIsPlayer = function(unit) return unit == "player" or unit == OFFLINE_UNIT end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    env.MSUF_EnsureDB()
    return world, env
end

-- 1 + 2: the kit and the combat-state source -------------------------------
local function KitAndSource(flavor, world, env)
    local InCombat = assert(world.core.Util and world.core.Util.InCombat, flavor .. ": no MSUF.Util.InCombat")
    local seen = {}
    local probe = env.CreateFrame("Frame")
    probe:RegisterEvent("PLAYER_REGEN_DISABLED")
    probe:RegisterEvent("PLAYER_REGEN_ENABLED")
    probe:SetScript("OnEvent", function(_, event)
        seen[event] = {
            lockdown = env.InCombatLockdown() == true,
            withEvent = InCombat(event) == true,
            synthetic = InCombat("MSUF_APPLY") == true,
        }
    end)
    Check(InCombat() == false, flavor .. ": InCombat() is true before combat")
    world:EnterCombat()
    local entering = seen.PLAYER_REGEN_DISABLED
    Check(entering ~= nil, flavor .. ": the kit did not deliver PLAYER_REGEN_DISABLED")
    Check(entering.lockdown == false, flavor .. ": the kit locked down before PLAYER_REGEN_DISABLED")
    Check(entering.withEvent == true, flavor .. ": InCombat(PLAYER_REGEN_DISABLED) is false")
    Check(entering.synthetic == true,
        flavor .. ": work started inside the PLAYER_REGEN_DISABLED dispatch does not see combat")
    Check(InCombat() == true, flavor .. ": InCombat() is false in combat")
    world:LeaveCombat()
    local leaving = seen.PLAYER_REGEN_ENABLED
    Check(leaving ~= nil and leaving.lockdown == false and leaving.withEvent == false,
        flavor .. ": PLAYER_REGEN_ENABLED must read out of combat")
    Check(InCombat() == false, flavor .. ": InCombat() still true after combat")
    -- A combat that ends within its own frame leaves no edge behind.
    InCombat("PLAYER_REGEN_DISABLED")
    InCombat("PLAYER_REGEN_ENABLED")
    Check(InCombat() == false, flavor .. ": PLAYER_REGEN_ENABLED did not end the combat edge")
    -- The edge memory ends with its frame even when no handler saw the end.
    InCombat("PLAYER_REGEN_DISABLED")
    env.InCombatLockdown()
    world.widgets:AdvanceTime(1 / 60)
    Check(InCombat() == false, flavor .. ": the combat edge outlived its frame")
    probe:UnregisterAllEvents()
end

-- 3: group offline hide -----------------------------------------------------
local function GroupMember(env, GF, opts)
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame.MSUFUnitKey = OFFLINE_UNIT
    frame.MSUFSpec = {
        scope = "group",
        group = {
            hideOfflineEnabled = true,
            hideOfflineInCombat = opts.alsoInCombat == true,
            offlineAlpha = 0.5,
            hideOfflineDelay = 0,
        },
        alpha = opts.oocFade and { oocFade = true, oocAlpha = 0.8 } or nil,
    }
    GF.frames = GF.frames or {}
    GF.frames[frame] = true
    return frame
end

local function GroupOffline(flavor, world, env)
    local UF, GF = world.core.UF, world.core.GF
    local element = assert(UF.elements and UF.elements.GroupRangeFade, flavor .. ": GroupRangeFade not registered")
    -- Created in this order on purpose: the range driver exists before the
    -- out-of-combat fade driver, so at combat start the fade pokes its member
    -- ("MSUF_OOC") after the range driver already re-applied it.
    local plain = GroupMember(env, GF, {})
    local both = GroupMember(env, GF, { alsoInCombat = true })
    element.Apply(plain)
    element.Apply(both)
    local faded = GroupMember(env, GF, { oocFade = true })
    element.Apply(faded)
    Check(plain:GetAlpha() == 0 and both:GetAlpha() == 0 and faded:GetAlpha() == 0,
        flavor .. ": an offline member with Hide offline is not hidden out of combat")

    -- The range driver runs first; the out-of-combat fade pokes after it.
    Check(HandlersFirst(world, "MSUF_UF_Group_RangeFade.lua") > 0, flavor .. ": no group range driver listens")
    world:EnterCombat()
    Check(plain:GetAlpha() == 0.5, flavor .. ": combat start left the offline member at alpha "
        .. tostring(plain:GetAlpha()) .. " (hidden for the whole fight) instead of its offline fade 0.5")
    Check(faded:GetAlpha() == 0.5, flavor .. ": the out-of-combat fade re-hid the offline member at combat start"
        .. " (alpha " .. tostring(faded:GetAlpha()) .. ")")
    Check(both:GetAlpha() == 0, flavor .. ": 'also in combat' no longer hides the offline member in combat")

    world:LeaveCombat()
    Check(plain:GetAlpha() == 0 and faded:GetAlpha() == 0 and both:GetAlpha() == 0,
        flavor .. ": the offline member is not hidden again after combat")
    for _, frame in ipairs({ plain, both, faded }) do
        element.Disable(frame)
        GF.frames[frame] = nil
    end
end

-- 4: texture layers ---------------------------------------------------------
local function TextureLayers(flavor, world, env)
    local TextureLayer = assert(world.core.TextureLayer, flavor .. ": no MSUF.TextureLayer")
    local UF = world.core.UF
    local conf = env.MSUF_DB.player
    conf.texLayerEnabled, conf.texLayerVisibility = true, "COMBAT"
    conf.texLayer2Enabled, conf.texLayer2Visibility = true, "OOC"
    conf.texLayer3Enabled = false
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame.MSUFUnitKey = "player"
    UF.frames = UF.frames or {}
    UF.frames.player = frame
    TextureLayer.Refresh("player")

    local function Shown(slot)
        local holder = frame._msufTexLayers and frame._msufTexLayers[slot]
        return holder ~= nil and holder:IsShown() == true
    end
    Check(not Shown(1) and Shown(2), flavor .. ": out of combat the COMBAT layer must hide and the OOC layer show")
    Check(HandlersFirst(world, "MSUF_UF_TextureLayer.lua") > 0, flavor .. ": no texture layer driver listens")
    world:EnterCombat()
    Check(Shown(1), flavor .. ": the COMBAT texture layer stays hidden after combat starts")
    Check(not Shown(2), flavor .. ": the OOC texture layer stays visible after combat starts")
    world:LeaveCombat()
    Check(not Shown(1) and Shown(2), flavor .. ": the layers did not return to their out-of-combat state")
    UF.frames.player = nil
    conf.texLayerEnabled, conf.texLayer2Enabled = false, false
    TextureLayer.Refresh("player")
end

-- 5: unit tooltips ----------------------------------------------------------
local function Tooltips(flavor, world, env)
    local Tooltips = assert(world.core.Tooltips, flavor .. ": no MSUF.Tooltips")
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

    local general = env.MSUF_DB.general
    general.unitTooltipProvider = "GAME"
    general.unitTooltipAnchor = "EXTERNAL"
    general.unitTooltipMode = "OOC"
    Tooltips.Refresh()
    Check(Tooltips.hoverInert == false, flavor .. ": out of combat an OOC-only tooltip config is hover-inert")
    local owner = env.CreateFrame("Button", nil, env.UIParent)
    Check(Tooltips.ShowUnit(owner, OFFLINE_UNIT) == true and gt.shown == true,
        flavor .. ": out of combat the unit tooltip does not show")

    Check(HandlersFirst(world, "MSUF_UnitTooltips.lua") > 0, flavor .. ": no tooltip combat watcher listens")
    world:EnterCombat()
    Check(Tooltips.hoverInert == true,
        flavor .. ": combat started but the OOC-only tooltip fast path stays off for the whole fight")
    Check(gt.shown == false, flavor .. ": the unit tooltip MSUF owns lingers into combat")
    world:LeaveCombat()
    Check(Tooltips.hoverInert == false, flavor .. ": the tooltip fast path did not turn off after combat")
    general.unitTooltipMode = "ALWAYS"
    Tooltips.Refresh()
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world, env = Boot(flavor)
    KitAndSource(flavor, world, env)
    GroupOffline(flavor, world, env)
    TextureLayers(flavor, world, env)
    Tooltips(flavor, world, env)
    print("combat_regen_edge_smoke: ok (" .. flavor .. ")")
end
