-- ============================================================================
-- MSUF_EM2_Elements.lua
-- Registers all existing MSUF elements with the EM2 Registry.
-- Deferred to PLAYER_LOGIN so unit frames exist.
-- ============================================================================
local addonName, ns = ...

local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.Registry then return end

local Reg = EM2.Registry

-- ---------------------------------------------------------------------------
-- Frame resolvers (always live, no cached refs)
-- ---------------------------------------------------------------------------
local function GetUF(key)
    local uf = _G.MSUF_UnitFrames
    if uf and uf[key] then return uf[key] end
    return _G["MSUF_" .. key]
end

local function GetBossUF(i)
    return _G["MSUF_boss" .. i]
end

local function GetConf(key)
    local db = _G.MSUF_DB
    return db and db[key]
end

-- ---------------------------------------------------------------------------
-- isEnabled: true when the unit frame exists and unit tracking is on
-- ---------------------------------------------------------------------------
local function UnitEnabled(key)
    return function()
        local f = GetUF(key)
        if not f then return false end
        local db = _G.MSUF_DB
        if not db or not db[key] then return true end
        if db[key].enabled == false then return false end
        return true
    end
end

local function BossEnabled(i)
    return function()
        local f = GetBossUF(i)
        if not f then return false end
        local db = _G.MSUF_DB
        if not db or not db.boss then return true end
        if db.boss.enabled == false then return false end
        return true
    end
end

-- ---------------------------------------------------------------------------
-- Registration (deferred)
-- ---------------------------------------------------------------------------
local function RegisterAll()
    -- Core unit frames
    local units = {
        { key = "player",       label = "Player",           order = 10 },
        { key = "target",       label = "Target",           order = 20 },
        { key = "focus",        label = "Focus",            order = 30 },
        { key = "targettarget", label = "Target of Target", order = 40 },
        { key = "pet",          label = "Pet",              order = 50 },
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

    -- Boss: only boss1 gets a mover. All boss frames share one config ("boss").
    -- Moving boss1 writes offsetX/Y → ApplySettingsForKey("boss") repositions all.
    -- Boss2-5 auto-position via (index-1)*spacing in PositionUnitFrame.
    Reg.Register({
        key       = "boss",
        label     = "Boss",
        order     = 61,
        popupType = "unit",
        canResize = true,
        canNudge  = true,
        getFrame  = function() return GetBossUF(1) end,
        getConf   = function() return GetConf("boss") end,
        isEnabled = BossEnabled(1),
    })

    -- Future Phase 2 registrations:
    -- Castbar elements (per-unit)
    -- Auras2 groups (per-unit)
    -- Class Power bar
    -- These will register when their respective modules load.
end

-- ---------------------------------------------------------------------------
-- Deferred init: register once frames are ready
-- ---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Delay one frame to ensure all unit frames are created
    C_Timer.After(0, function()
        RegisterAll()
    end)
end)
