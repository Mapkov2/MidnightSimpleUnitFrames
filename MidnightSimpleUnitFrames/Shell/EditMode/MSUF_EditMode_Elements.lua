--- EditMode/MSUF_EditMode_Elements.lua - registers the MSUF elements with the Edit Mode registry
--- Deferred to PLAYER_LOGIN so unit frames exist.
local _, MSUF = ...
-- Functions other modules publish are resolved where they are called
-- (most load after Edit Mode): MSUF.Require raises naming this file when
-- one is missing, and a hook installed on the global still applies.
local CALLER = "Shell/EditMode/MSUF_EditMode_Elements.lua"
local ExportPublic = MSUF.ExportPublic
local EM2 = MSUF.Optional("MSUF_EM2")
if not EM2 then return end
if not EM2.Registry then return end

local max, min = math.max, math.min
local U = EM2.Util or {}
local ApplySettingsForKeySafe = U.ApplySettingsForKeySafe
local FrameRectToUI = MSUF.Require("MSUF_UF_FrameRectToUI", CALLER)
local UnitVisualBounds = EM2.Movers.GetUnitVisualBounds

local Reg = EM2.Registry

--- Frame resolvers (always live, no cached refs)
local function GetUF(key)
    local UF = MSUF and MSUF.UF
    if UF and type(UF.GetFrame) == "function" then
        local frame = UF.GetFrame(key)
        if frame then return frame end
    end
    local uf = UF and UF.frames
    if uf and uf[key] then return uf[key] end
    return MSUF.Optional("MSUF_" .. key)
end

local function GetBossUF(i)
    return GetUF("boss" .. i)
end

local function GetBossCastbarFrame(index)
    if index == 1 then
        return MSUF.Castbars.Frames.Get("bossPreview") or MSUF.Optional("MSUF_BossCastbar1")
    end
    return MSUF.Optional("MSUF_BossCastbarPreview" .. index) or MSUF.Optional("MSUF_BossCastbar" .. index)
end

local function GetBossSupplementalMoverBounds()
    local bounds = {}
    for i = 2, 5 do
        local l, r, t, b = UnitVisualBounds(GetBossUF(i))
        if l then
            bounds[#bounds + 1] = { l = l, r = r, t = t, b = b }
        end
    end
    return bounds
end

local function GetArenaUF(i)
    return GetUF("arena" .. i)
end

local function GetArenaCastbarFrame(index)
    return MSUF.Optional("MSUF_ArenaCastbarPreview" .. index) or MSUF.Optional("MSUF_ArenaCastbar" .. index)
end

local function GetArenaSupplementalMoverBounds()
    local bounds = {}
    for i = 2, tonumber(MSUF_MAX_ARENA_FRAMES) or 3 do
        local l, r, t, b = UnitVisualBounds(GetArenaUF(i))
        if l then
            bounds[#bounds + 1] = { l = l, r = r, t = t, b = b }
        end
    end
    return bounds
end

local function GetArenaCastbarSupplementalMoverBounds()
    local bounds = {}
    for i = 2, tonumber(MSUF_MAX_ARENA_FRAMES) or 3 do
        local l, r, t, b = FrameRectToUI(GetArenaCastbarFrame(i))
        if l then
            bounds[#bounds + 1] = { l = l, r = r, t = t, b = b }
        end
    end
    return bounds
end

local function GetConf(key)
    local db = MSUF_DB
    return db and db[key]
end

--- isEnabled: true when the frame exists and its unit section is not disabled
local function SectionEnabled(frame, section)
    if not frame then return false end
    local conf = GetConf(section)
    return not (conf and conf.enabled == false)
end

local function UnitEnabled(key)
    return function() return SectionEnabled(GetUF(key), key) end
end

local function BossEnabled(i)
    return function() return SectionEnabled(GetBossUF(i), "boss") end
end

local function ArenaEnabled(i)
    return function() return SectionEnabled(GetArenaUF(i), "arena") end
end

local function GetCastbarFrame(unit)
    local frame
    if unit == "player" then
        frame = MSUF.Castbars.Frames.Get("playerPreview") or MSUF.Castbars.Frames.Get("player")
    elseif unit == "target" then
        frame = MSUF.Castbars.Frames.Get("targetPreview") or MSUF.Castbars.Frames.Get("target")
    elseif unit == "focus" then
        frame = MSUF.Castbars.Frames.Get("focusPreview") or MSUF.Castbars.Frames.Get("focus")
    elseif unit == "boss" then
        frame = GetBossCastbarFrame(1)
    elseif unit == "arena" then
        frame = GetArenaCastbarFrame(1)
    end
    if frame and frame.IsShown and not frame:IsShown() then return nil end
    return frame
end


local function GetBossCastbarSupplementalMoverBounds()
    local bounds = {}
    for i = 2, 5 do
        local l, r, t, b = FrameRectToUI(GetBossCastbarFrame(i))
        if l then
            bounds[#bounds + 1] = { l = l, r = r, t = t, b = b }
        end
    end
    return bounds
end

local function GetCastbarConf()
    MSUF.Require("MSUF_EnsureDB", CALLER)()
    local db = MSUF_DB
    if type(db) ~= "table" then
        db = ExportPublic("MSUF_DB", {})
    end
    db.general = db.general or {}
    return db.general
end

local function CastbarEnabled(unit)
    return function()
        local g = GetConf("general")
        if not g or g.castbarPlayerPreviewEnabled == false then return false end
        if not MSUF.Require("MSUF_ShouldUseMSUFCastbar", CALLER)(unit, g) then return false end
        return GetCastbarFrame(unit) ~= nil
    end
end

local function GetClassResourceFrame()
    local frame = MSUF.Optional("MSUF_ClassPowerContainer")
    if MSUF_UnitEditModeActive == true
        and (not frame or (frame.IsShown and not frame:IsShown()
            and frame._msufAnchorOnly ~= true)) then
        MSUF.Require("MSUF_ClassPower_EnsureEditModeAnchor", CALLER)()
        frame = MSUF.Optional("MSUF_ClassPowerContainer")
    end
    if frame and frame.GetCenter and frame:GetCenter()
        and ((frame.IsShown and frame:IsShown())
            or (MSUF_UnitEditModeActive == true and frame._msufAnchorOnly == true))
    then return frame end
end

local function GetDetachedPowerFrame(unit)
    local conf = GetConf(unit)
    if not (conf and conf.powerBarDetached == true) then return nil end
    local owner = GetUF(unit)
    local bar = owner and (owner.targetPowerBar or owner.powerBar or owner.Power)
    if bar and bar._msufDetached == true and bar.GetCenter and bar:GetCenter()
        and ((bar.IsShown and bar:IsShown()) or MSUF_UnitEditModeActive == true)
    then return bar end
end

local function ResourceMoverBounds(frame, above)
    if not frame then return nil end
    local l, r, t, b = FrameRectToUI(frame)
    if not l then return nil end
    local extra = max(0, 16 - (t - b))
    if above then t = t + extra else b = b - extra end
    return l, r, t, b
end

local function CommitDetachedPowerPosition(unit)
    if ApplySettingsForKeySafe(unit) then return true end
    return MSUF.Require("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", CALLER)(unit, true) or false
end

local function CommitClassResourcePosition()
    local refresh = MSUF.Optional("MSUF_ClassPower_RefreshLayout")
    return type(refresh) == "function" and refresh() or false
end

local function RegisterResourceMovers()
    Reg.Register({
        key = "classpower", label = "Class Resources", order = 101,
        popupType = "resource", resourceKind = "classpower", canNudge = true,
        historyCategory = "classpower", historyKey = "bars",
        subframeOffsetXKey = "classPowerOffsetX", subframeOffsetYKey = "classPowerOffsetY",
        getFrame = GetClassResourceFrame,
        getMoverBounds = function() return ResourceMoverBounds(GetClassResourceFrame(), true) end,
        getConf = function() return GetConf("bars") end,
        commitSubframePosition = CommitClassResourcePosition,
    })
    local units = { "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget" }
    for _, unit in ipairs(units) do
        Reg.Register({
            key = "power_" .. unit, label = "Detached power bar", order = 102,
            popupType = "resource", resourceKind = "power", resourceUnit = unit,
            canNudge = true, historyCategory = "power", historyKey = unit,
            subframeOffsetXKey = "detachedPowerBarOffsetX",
            subframeOffsetYKey = "detachedPowerBarOffsetY",
            getFrame = function() return GetDetachedPowerFrame(unit) end,
            getMoverBounds = function() return ResourceMoverBounds(GetDetachedPowerFrame(unit), false) end,
            getConf = function() return GetConf(unit) end,
            commitSubframePosition = function() return CommitDetachedPowerPosition(unit) end,
        })
    end
end

--- The arena PvP trinket follows its arena frame the way a detached power bar
--- follows its unit frame: a sub-element whose X/Y offset from its anchor side
--- drags and nudges in place (popupType "resource"). Arena 1's icon carries the
--- mover, the other slots add mouse regions, and its card lives in the arena
--- frame popup. Clients without arena frames have no holders, so no mover.
local function GetTrinketHolder(index)
    local holder = MSUF.ArenaTrinkets.Holder(index)
    if holder and holder:IsShown() then return holder end
end

local function TrinketMoverBounds(holder)
    if not holder then return nil end
    local l, r, t, b = FrameRectToUI(holder)
    if not l then return nil end
    -- A 10 px icon still gets an 18 px grab area.
    local padX, padY = max(0, (18 - (r - l)) * 0.5), max(0, (18 - (t - b)) * 0.5)
    return l - padX, r + padX, t + padY, b - padY
end

local function GetTrinketSupplementalMoverBounds()
    local bounds = {}
    -- The runtime builds holders for the client's arena slots only.
    for i = 2, 5 do
        local l, r, t, b = TrinketMoverBounds(GetTrinketHolder(i))
        if l then bounds[#bounds + 1] = { l = l, r = r, t = t, b = b } end
    end
    return bounds
end

--- Keeps the saved offset inside the runtime's range (what the icon can show),
--- then applies the arena scope, which re-places every trinket holder. A nudge
--- past the edge therefore reads back changed and is rolled back.
local function CommitTrinketPosition()
    local conf = GetConf("arena")
    if type(conf) ~= "table" then return false end
    local trinkets = MSUF.ArenaTrinkets
    local limit, defaults = trinkets.LIMITS.offset, trinkets.DEFAULTS
    conf.trinketOffsetX = max(-limit, min(limit, tonumber(conf.trinketOffsetX) or defaults.x))
    conf.trinketOffsetY = max(-limit, min(limit, tonumber(conf.trinketOffsetY) or defaults.y))
    local applied = ApplySettingsForKeySafe("arena") and true or false
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    return applied
end

local function RegisterTrinketMover()
    Reg.Register({
        key = "arena_trinket", label = "PvP Trinket", order = 63,
        popupType = "resource", resourceKind = "trinket", resourceUnit = "arena",
        canNudge = true, historyCategory = "unit", historyKey = "arena",
        subframeOffsetXKey = "trinketOffsetX", subframeOffsetYKey = "trinketOffsetY",
        getFrame = function() return GetTrinketHolder(1) end,
        getMoverBounds = function() return TrinketMoverBounds(GetTrinketHolder(1)) end,
        getSupplementalMoverBounds = GetTrinketSupplementalMoverBounds,
        getConf = function() return GetConf("arena") end,
        commitSubframePosition = CommitTrinketPosition,
    })
end

local function RegisterCastbarMover(unit, label, order)
    Reg.Register({
        key         = "castbar_" .. unit,
        label       = label,
        order       = order,
        popupType   = "castbar",
        canResize   = false,
        canNudge    = true,
        castbarUnit = unit,
        getFrame    = function() return GetCastbarFrame(unit) end,
        getSupplementalMoverBounds = (unit == "boss" and GetBossCastbarSupplementalMoverBounds)
            or (unit == "arena" and GetArenaCastbarSupplementalMoverBounds)
            or nil,
        getConf     = GetCastbarConf,
        isEnabled   = CastbarEnabled(unit),
    })
end

--- Registration (deferred)
local function RegisterAll()
    --- Core unit frames
    local units = {
        { key = "player",       label = "Player",           order = 10 },
        { key = "target",       label = "Target",           order = 20 },
        { key = "focus",        label = "Focus",            order = 30 },
        { key = "targettarget", label = "Target of Target", order = 40 },
        { key = "focustarget",  label = "Focus Target",     order = 45 },
        { key = "pet",          label = "Pet",              order = 50 },
        { key = "pettarget",    label = "Pet Target",       order = 55 },
    }

    for _, u in ipairs(units) do
        Reg.Register({
            key       = u.key,
            label     = u.label,
            order     = u.order,
            popupType = "unit",
            canResize = true,
            canNudge  = true,
            getFrame  = function() return GetUF(u.key) end,
            getConf   = function() return GetConf(u.key) end,
            isEnabled = UnitEnabled(u.key),
        })
    end

    --- Boss 1-5 share one mover/config, but use one mouse region per frame.
    --- This keeps the gaps and independently editable boss castbars clickable
    --- while dragging any boss unitframe still moves the complete boss group.
    Reg.Register({
        key       = "boss",
        label     = "Boss",
        order     = 61,
        popupType = "unit",
        canResize = true,
        canNudge  = true,
        getFrame  = function() return GetBossUF(1) end,
        getSupplementalMoverBounds = GetBossSupplementalMoverBounds,
        getConf   = function() return GetConf("boss") end,
        isEnabled = BossEnabled(1),
    })

    --- Arena 1-N mirror the boss cluster: one mover/config, one mouse region
    --- per frame, dragging any arena frame moves the whole group. N is the
    --- client arena slot fact (MSUF_MAX_ARENA_FRAMES: 3 Mainline, 5 TBC/Mists).
    Reg.Register({
        key       = "arena",
        label     = "Arena",
        order     = 62,
        popupType = "unit",
        canResize = true,
        canNudge  = true,
        getFrame  = function() return GetArenaUF(1) end,
        getSupplementalMoverBounds = GetArenaSupplementalMoverBounds,
        getConf   = function() return GetConf("arena") end,
        isEnabled = ArenaEnabled(1),
    })

    RegisterCastbarMover("player", "Player Castbar", 110)
    RegisterCastbarMover("target", "Target Castbar", 111)
    RegisterCastbarMover("focus", "Focus Castbar", 112)
    RegisterCastbarMover("boss", "Boss Castbar", 113)
    RegisterCastbarMover("arena", "Arena Castbar", 114)

    RegisterResourceMovers()
    -- Same gate as the trinket runtime: Classic Era and WoW Forever have no arena.
    local client = MSUF.Client
    if not (client and client.SupportsUnit and client.SupportsUnit("arena1") == false) then RegisterTrinketMover() end

    --- Future Phase 2 registrations:
    --- Auras3 groups (per-unit)
    --- These will register when their respective modules load.
end

RegisterAll()
