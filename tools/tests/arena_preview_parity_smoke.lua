-- arena_preview_parity_smoke.lua <repo root>
--
-- The arena unit-frame preview in MSUF_UF_Elements_LoadConditions.lua is a
-- Classic hunk modelled on the boss preview. Three behaviours drifted from the
-- boss copy and are pinned here against the real file:
--   * leaving the preview (menu off, or combat) hands every frame back at
--     range multiplier 1, so the range runtime must evaluate the real
--     opponents again, exactly like the boss preview does;
--   * "Show only below 100% health" must not hide the synthetic opponents
--     while they are previewed, and must apply again once the preview ends;
--   * the preview level is the client's max player level, not one
--     expansion's cap (TBC 70, Mists and Midnight 90).
-- Plain Lua 5.1, the repository root as the only argument.
local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local loadfile = assert(loadfile(root .. "/tools/tests/preview_namespace_fixture.lua"))().Loader(loadfile, root)
local FILE = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Region(name)
    local region = { name = name, shown = true, alpha = 1 }
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetShown(shown) self.shown = shown == true end
    function region:IsShown() return self.shown end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:EnableMouse(enabled) self.mouse = enabled end
    function region:SetText(text) self.text = text end
    function region:SetMinMaxValues(low, high) self.low, self.high = low, high end
    function region:SetValue(value) self.value = value end
    function region:SetStatusBarColor(r, g, b, a) self.color = { r, g, b, a } end
    function region:GetStatusBarTexture()
        self.fill = self.fill or Region(name .. ".fill")
        return self.fill
    end
    return region
end

local function NewArenaFrame(index)
    local unit = "arena" .. index
    local frame = Region(unit)
    frame.MSUFUnitKey = unit
    frame.hpBar = Region(unit .. ".health")
    frame.powerBar = Region(unit .. ".power")
    frame.nameText = Region(unit .. ".name")
    frame.levelText = Region(unit .. ".level")
    frame._msufHealthVisualRoot = Region(unit .. ".visualRoot")
    frame._msufUnitState = {}
    frame.MSUFSpec = { unit = unit, health = { mode = "class" }, load = { showWhenInjured = true } }
    return frame
end

local function Load(client)
    -- Globals the file reads at load time.
    _G.UnitExists = function() return false end
    _G.issecretvalue = function() return false end
    _G.InCombatLockdown = function() return client.combat end
    _G.UnitAffectingCombat = function() return false end
    _G.IsInInstance = function() return false end
    _G.RegisterStateDriver = function() end
    _G.UnregisterStateDriver = function() end
    _G.RegisterUnitWatch = function() end
    _G.UnregisterUnitWatch = function() end
    _G.UnitWatchRegistered = function() return false end
    _G.SecureCmdOptionParse = nil
    _G.C_Housing = nil
    -- The native HP gate: the curve maps a full-health (or missing) unit to 0.
    _G.UnitHealthPercent = function() return 0 end
    _G.C_CurveUtil = { CreateCurve = function()
        return { SetType = function() end, AddPoint = function() end }
    end }
    _G.Enum = { LuaCurveType = { Step = 1 } }
    _G.GetMaxPlayerLevel = client.maxPlayerLevel
    _G.GetMaxLevelForPlayerExpansion = client.maxExpansionLevel
    _G.MSUF_MAX_ARENA_FRAMES = client.slots
    _G.MSUF2_ArenaUnitframePreviewActive, _G.MSUF_ArenaTestMode = nil, nil
    _G.MSUF_PreviewTestMode, _G.MSUF_UnitEditModeActive, _G.MSUF_InCombat = nil, nil, nil

    local refreshes = { range = 0, elements = 0, trinkets = 0 }
    local frames = {}
    for i = 1, client.slots do frames["arena" .. i] = NewArenaFrame(i) end
    local UF = {
        frames = frames,
        Config = { dirty = false },
        Range = { Refresh = function() refreshes.range = refreshes.range + 1 end },
        ApplyRangeModifier = function(frame, mul) frame._msufRangeMul = mul end,
        RegisterElement = function(name, element) if name == "LoadConditions" then refreshes.element = element end end,
        RefreshElements = function() refreshes.elements = refreshes.elements + 1; return true end,
        UpdateRuntime = function() end,
        MarkDirty = function() end,
    }
    local namespace = {
        UF = UF,
        -- The client model publishes the fixed supported slot count before the elements load.
        Client = { MaxArenaOpponents = client.slots },
        Translate = function(text) return text end,
        ExportPublic = function(name, value) _G[name] = value end,
        Secrets = { UnitExistsPlain = function() return false end },
        -- Auras3/MSUF_Auras3_Core.lua defines RequestScope on every client.
        MSUF_Auras3 = { RequestScope = function() end },
    }
    -- The real MSUF.Require / MSUF.Optional (Kernel/MSUF_Require.lua), as in every core TOC.
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))("MidnightSimpleUnitFrames", namespace)
    -- The castbar previews and the PvP trinket holders follow a unit preview;
    -- this harness has neither castbars nor trinkets.
    _G.MSUF_UpdateArenaCastbarPreview = function() end
    namespace.ArenaTrinkets = { SyncPreview = function() refreshes.trinkets = refreshes.trinkets + 1 end }
    _G.MSUF_ArenaTrinkets_SyncPreview = function() error("legacy trinket preview lookup", 0) end
    _G.MSUF_UpdateBossCastbarPreview = function() end
    -- The preview families bind the health element's colour refresh when they load; this harness has no health element.
    _G.MSUF_UFCore_RefreshHealthBarColor = function() end
    -- The load conditions bind the event bus when they load; this harness lifecycle needs no subscriptions.
    _G.MSUF_EventBus_Register = function() return true end
    _G.MSUF_EventBus_Unregister = function() end
    assert(loadfile(FILE))("MidnightSimpleUnitFrames", namespace)
    Check(type(UF.ApplyArenaPreviewState) == "function" and type(UF.ClearArenaPreviewFramesForCombat) == "function",
        "the arena preview owner is missing")
    return UF, refreshes, frames, namespace
end

local CLIENTS = {
    { name = "TBC", slots = 5, maxPlayerLevel = function() return 70 end,
        maxExpansionLevel = function() return 70 end, expected = "70" },
    { name = "Mists", slots = 5, maxPlayerLevel = function() return 90 end, expected = "90" },
    { name = "Midnight", slots = 3, maxExpansionLevel = function() return 90 end, expected = "90" },
    -- A capped player level (a Classic pre-patch) wins over the expansion cap.
    { name = "TBC pre-patch", slots = 5, maxPlayerLevel = function() return 60 end,
        maxExpansionLevel = function() return 70 end, expected = "60" },
}

for _, client in ipairs(CLIENTS) do
    local UF, refreshes, frames = Load(client)
    local element = refreshes.element
    Check(element and type(element.Apply) == "function", client.name .. ": the LoadConditions element was not registered")

    -- "Show only below 100% health": the HP gate hides a full-health frame.
    for i = 1, client.slots do
        local frame = frames["arena" .. i]
        element.Apply(frame, frame.MSUFSpec)
        Check(frame._msufHealthVisualRoot.alpha == 0, client.name .. ": harness: the HP gate did not hide arena" .. i)
    end

    -- Preview on: synthetic opponents at the client's level, visible through the HP gate.
    UF.Preview.SetArenaPage(true)
    Check(UF.ApplyArenaPreviewState(true, "MSUF_ARENA_PREVIEW") == true, client.name .. ": the preview did not apply")
    Check(refreshes.trinkets > 0, client.name .. ": the preview did not call its trinket namespace owner")
    for i = 1, client.slots do
        local frame = frames["arena" .. i]
        Check(frame._msufArenaPreviewForced == true, client.name .. ": arena" .. i .. " is not previewed")
        Check(frame.levelText.text == client.expected, client.name .. ": arena" .. i .. " preview level is "
            .. tostring(frame.levelText.text) .. ", not the client's max level " .. client.expected)
        Check(frame._msufHealthVisualRoot.alpha == 1, client.name .. ": the HP gate hides the arena" .. i .. " preview")
    end

    -- Preview off from the menu: real HP gate again, and a range re-evaluation.
    UF.Preview.SetArenaPage(nil)
    local before = refreshes.range
    UF.ApplyArenaPreviewState(false, "MSUF_ARENA_PREVIEW_OFF")
    Check(refreshes.range > before, client.name .. ": leaving the arena preview did not refresh the range fade")
    for i = 1, client.slots do
        local frame = frames["arena" .. i]
        Check(frame._msufArenaPreviewForced == nil and frame._msufRangeMul == 1,
            client.name .. ": arena" .. i .. " kept the preview state")
        Check(frame._msufHealthVisualRoot.alpha == 0, client.name .. ": arena" .. i .. " lost its HP gate after the preview")
    end
    -- Nothing to hand back: no range work.
    before = refreshes.range
    UF.ApplyArenaPreviewState(false, "MSUF_ARENA_PREVIEW_OFF")
    Check(refreshes.range == before, client.name .. ": an inactive preview refreshed the range fade")

    -- Combat while previewed: the combat cleanup hands back and re-evaluates too.
    UF.Preview.SetArenaPage(true)
    UF.ApplyArenaPreviewState(true, "MSUF_ARENA_PREVIEW")
    client.combat = true
    before = refreshes.range
    Check(UF.ApplyArenaPreviewState(true, "MSUF_ARENA_PREVIEW") == false, client.name .. ": the preview applied in combat")
    Check(refreshes.range > before, client.name .. ": the combat cleanup did not refresh the range fade")
    Check(frames.arena1._msufArenaPreviewForced == nil, client.name .. ": combat left arena1 previewed")
    client.combat = false
end

-- Real lifecycle consumers resolve the current namespace member on both
-- populated and unsupported (zero-slot) families, even with a valid registry.
local function OwnedTrinketBoundary(slots)
    local uf, refreshes, frames, ns = Load({ name = "owner boundary", slots = slots })
    local owner = ns.ArenaTrinkets
    local provider = owner.SyncPreview
    local publicGlobals, compat = ns.PublicGlobals, ns.Compat
    local legacyGlobals = compat.LegacyGlobals
    local previousProvider = publicGlobals.MSUF_ArenaTrinkets_SyncPreview
    local previousLegacy = legacyGlobals.MSUF_ArenaTrinkets_SyncPreview
    publicGlobals.MSUF_ArenaTrinkets_SyncPreview = provider
    legacyGlobals.MSUF_ArenaTrinkets_SyncPreview = nil
    local function Mirrors(expected)
        Check(ns.PublicGlobals == publicGlobals and ns.Compat == compat and compat.LegacyGlobals == legacyGlobals,
            "owner boundary replaced a captured publication table")
        Check(_G.MSUF2_ArenaUnitframePreviewActive == expected
            and ns.Public.MSUF2_ArenaUnitframePreviewActive == expected
            and publicGlobals.MSUF2_ArenaUnitframePreviewActive == expected,
            "arena preview publication mirrors disagree")
        Check(legacyGlobals.MSUF2_ArenaUnitframePreviewActive == true, "arena preview lost its legacy publication bit")
    end
    uf.Preview.SetArenaPage(true)
    Mirrors(true)
    local before = refreshes.trinkets
    Check(uf.ApplyArenaPreviewState(true, "MSUF_ARENA_PREVIEW") == true, "owner boundary preview refused")
    Check(refreshes.trinkets > before, "owner boundary skipped the current provider")
    if slots == 0 then Check(next(frames) == nil, "unsupported preview created an arena frame") end
    local replacements = 0
    owner.SyncPreview = function() replacements = replacements + 1 end
    uf.ApplyArenaPreviewState(true, "MSUF_ARENA_PREVIEW")
    Check(replacements > 0, "preview cached its old trinket provider")
    local function Missing()
        local ok, message = pcall(uf.ApplyArenaPreviewState, true, "MSUF_ARENA_PREVIEW")
        Check(not ok and tostring(message):find("missing required dependency 'SyncPreview'", 1, true),
            "missing trinket owner used a legacy global or registry fallback")
        Check(tostring(message):find("MSUF_UF_PreviewFamilies.lua", 1, true), "dependency lost its caller context")
    end
    owner.SyncPreview = nil
    Missing()
    for _, invalid in ipairs({ false, 0, "wrong" }) do
        owner.SyncPreview = invalid
        Missing()
    end
    owner.SyncPreview = provider
    ns.ArenaTrinkets = nil
    Missing()
    ns.ArenaTrinkets = owner
    before = refreshes.trinkets
    Check(uf.ApplyArenaPreviewState(false, "MSUF_ARENA_PREVIEW_OFF") == true, "restored trinket owner did not recover")
    Check(refreshes.trinkets > before, "restored owner was not called")
    Mirrors(true)
    uf.Preview.SetArenaPage(nil)
    Mirrors(nil)
    publicGlobals.MSUF_ArenaTrinkets_SyncPreview = previousProvider
    legacyGlobals.MSUF_ArenaTrinkets_SyncPreview = previousLegacy
    Mirrors(nil)
end
OwnedTrinketBoundary(3)
OwnedTrinketBoundary(0)

-- No level API at all: never a hard-coded expansion cap.
local UF = Load({ name = "none", slots = 3 })
UF.Preview.SetArenaPage(true)
UF.ApplyArenaPreviewState(true, "MSUF_ARENA_PREVIEW")
Check(UF.frames.arena1.levelText.text == "??", "without a level API the preview must not invent a level")
UF.Preview.SetArenaPage(nil)
print("arena_preview_parity_smoke: OK (TBC, Mists, Midnight, TBC pre-patch)")
