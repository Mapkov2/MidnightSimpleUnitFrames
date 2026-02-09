-- Auras2: Preview + Edit Mode helper (split from MSUF_A2_Render.lua)
-- Goal: isolate preview/ticker/cleanup logic to reduce Render bloat, with zero feature regression.

local addonName, ns = ...


-- MSUF: Max-perf Auras2: replace protected calls (pcall) with direct calls.
-- NOTE: this removes error-catching; any error will propagate.
local function MSUF_A2_FastCall(fn, ...) 
    return true, fn(...)
end
local API = ns and ns.MSUF_Auras2
if type(API) ~= "table" then  return end

API.Preview = (type(API.Preview) == "table") and API.Preview or {}
local Preview = API.Preview

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function IsEditModeActive() 
    -- MSUF-only Edit Mode (Blizzard Edit Mode intentionally ignored here).
    -- Keep this identical to the helper used in the render module so preview/flush transitions are reliable.
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active == true then
         return true
    end

    -- Legacy global boolean used by older patches
    if rawget(_G, "MSUF_UnitEditModeActive") == true then
         return true
    end

    -- Exported helper from MSUF_EditMode.lua
    local f = rawget(_G, "MSUF_IsInEditMode")
    if type(f) == "function" then
        local ok, v = MSUF_A2_FastCall(f)
        if ok and v == true then
             return true
        end
    end

    -- Compatibility hook name from older experiments (last resort)
    local g = rawget(_G, "MSUF_IsMSUFEditModeActive")
    if type(g) == "function" then
        local ok, v = MSUF_A2_FastCall(g)
        if ok and v == true then
             return true
        end
    end

     return false
end


API.IsEditModeActive = API.IsEditModeActive or IsEditModeActive

local function EnsureDB() 
    local Ensure = API.EnsureDB
    if type(Ensure) ~= "function" and API.DB and type(API.DB.Ensure) == "function" then
        Ensure = API.DB.Ensure
    end
    if type(Ensure) == "function" then
        return Ensure()
    end
     return nil, nil
end

local function GetAurasByUnit() 
    local st = API.state
    if type(st) ~= "table" then  return nil end
    return st.aurasByUnit
end

local function GetCooldownTextMgr() 
    -- Prefer split module API, but keep legacy global aliases.
    local CT = API.CooldownText
    local reg = CT and CT.RegisterIcon
    local unreg = CT and CT.UnregisterIcon

    if type(reg) ~= "function" then
        reg = rawget(_G, "MSUF_A2_CooldownTextMgr_RegisterIcon")
    end
    if type(unreg) ~= "function" then
        unreg = rawget(_G, "MSUF_A2_CooldownTextMgr_UnregisterIcon")
    end

     return reg, unreg
end

-- Phase F: Preview no longer depends on Render helpers.
-- It calls Apply directly so Render can stay orchestration-only.
local function GetApply()
    return (type(API.Apply) == "table") and API.Apply or nil
end

-- ------------------------------------------------------------
-- Preview cleanup (safety): ensure preview icons never block real auras
-- ------------------------------------------------------------

local function ClearPreviewIconsInContainer(container) 
    if not container or not container._msufIcons then  return end

    local _, unreg = GetCooldownTextMgr()

    for _, icon in ipairs(container._msufIcons) do
        if icon and icon._msufA2_isPreview == true then
            -- Ensure preview cooldown text/ticker stops tracking this icon.
            if type(unreg) == "function" then
                MSUF_A2_FastCall(unreg, icon)
            end

            icon._msufA2_isPreview = nil
            icon._msufA2_previewMeta = nil
            icon._msufA2_previewDurationObj = nil
            icon._msufA2_previewStackT = nil
            icon._msufA2_previewCooldownT = nil
            -- Clear render-side caches so preview textures never 'stick' on reused icon frames.
            icon._msufA2_lastVisualAuraInstanceID = nil
            icon._msufA2_lastCooldownAuraInstanceID = nil
            icon._msufA2_lastDurationObject = nil
            icon._msufA2_lastCooldownUsesDurationObject = nil
            icon._msufA2_lastCooldownUsesExpiration = nil
            icon._msufA2_lastCooldownType = nil

            if icon.cooldown then
                -- Clear cooldown visuals so preview never leaves "dark" state.
                if icon.cooldown.Clear then MSUF_A2_FastCall(icon.cooldown.Clear, icon.cooldown) end
                if icon.cooldown.SetCooldown then MSUF_A2_FastCall(icon.cooldown.SetCooldown, icon.cooldown, 0, 0) end
                if icon.cooldown.SetCooldownDuration then MSUF_A2_FastCall(icon.cooldown.SetCooldownDuration, icon.cooldown, 0) end
            end

            icon:Hide()
        end
    end
 end

local function ClearPreviewsForEntry(entry) 
    if not entry then  return end
    ClearPreviewIconsInContainer(entry.buffs)
    ClearPreviewIconsInContainer(entry.debuffs)
    ClearPreviewIconsInContainer(entry.mixed)
    ClearPreviewIconsInContainer(entry.private)
    entry._msufA2_previewActive = nil
 end

local function ClearAllPreviews() 
    local AurasByUnit = GetAurasByUnit()
    if type(AurasByUnit) ~= "table" then  return end

    for _, entry in pairs(AurasByUnit) do
        if entry and entry._msufA2_previewActive == true then
            ClearPreviewsForEntry(entry)
        end
    end
 end

Preview.ClearPreviewsForEntry = ClearPreviewsForEntry
Preview.ClearAllPreviews = ClearAllPreviews

-- Keep existing public exports stable for Options + other modules.
API.ClearPreviewsForEntry = API.ClearPreviewsForEntry or ClearPreviewsForEntry
API.ClearAllPreviews = API.ClearAllPreviews or ClearAllPreviews

if _G and type(_G.MSUF_Auras2_ClearAllPreviews) ~= "function" then
    _G.MSUF_Auras2_ClearAllPreviews = function()  return API.ClearAllPreviews() end
end

-- ------------------------------------------------------------
-- Preview tickers (Edit Mode): cycle stacks + cooldowns
-- ------------------------------------------------------------

local PreviewTickers = {
    stacks = nil,
    cooldown = nil,
}

local function ShouldRunPreviewTicker(kind, a2, shared) 
    if not a2 or not a2.enabled then  return false end
    local DB = API and API.DB
    if DB and DB.AnyUnitEnabledCached and DB.AnyUnitEnabledCached() ~= true then  return false end
    if not shared or shared.showInEditMode ~= true then  return false end
    if not API.IsEditModeActive or API.IsEditModeActive() ~= true then  return false end
    if kind == "stacks" and shared.showStackCount == false then  return false end
     return true
end

local function ForEachPreviewIcon(fn) 
    local AurasByUnit = GetAurasByUnit()
    if type(AurasByUnit) ~= "table" then  return end

    for _, entry in pairs(AurasByUnit) do
        if entry and entry._msufA2_previewActive == true then
            local containers = { entry.buffs, entry.debuffs, entry.mixed, entry.private }
            for _, container in ipairs(containers) do
                if container and container._msufIcons then
                    for _, icon in ipairs(container._msufIcons) do
                        if icon and icon:IsShown() and icon._msufA2_isPreview == true then
                            fn(icon)
                        end
                    end
                end
            end
        end
    end
 end

local function PreviewTickStacks() 
    local a2, shared = EnsureDB()
    if not ShouldRunPreviewTicker("stacks", a2, shared) then  return end

    local A = GetApply()
    local applyAnchorStyle = A and A.ApplyStackCountAnchorStyle
    local applyOffsets = A and A.ApplyStackTextOffsets

    local stackCountAnchor = shared and shared.stackCountAnchor

    ForEachPreviewIcon(function(icon) 
        if not icon or not icon.count then  return end

        if type(applyAnchorStyle) == "function" then
            MSUF_A2_FastCall(applyAnchorStyle, icon, stackCountAnchor)
        end
        if type(applyOffsets) == "function" then
            MSUF_A2_FastCall(applyOffsets, icon, icon._msufUnit, shared, stackCountAnchor)
        end

        icon._msufA2_previewStackT = (icon._msufA2_previewStackT or 0) + 1

        local num = icon._msufA2_previewStackT
        if num > 9 then
            num = 1
            icon._msufA2_previewStackT = 1
        end

        icon.count:SetText(num)

        if shared and shared.showStackCount == false then
            icon.count:Hide()
        else
            icon.count:Show()
        end
     end)
 end

local function PreviewTickCooldown() 
    local a2, shared = EnsureDB()
    if not ShouldRunPreviewTicker("cooldown", a2, shared) then  return end

    local A = GetApply()
    local applyOffsets = A and A.ApplyCooldownTextOffsets

    local reg, unreg = GetCooldownTextMgr()

    ForEachPreviewIcon(function(icon) 
        if not icon or not icon.cooldown then  return end

        -- Ensure countdown text is visible (OmniCC removed in Midnight).
        if icon.cooldown.SetHideCountdownNumbers then
            MSUF_A2_FastCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
        end

        if type(applyOffsets) == "function" then
            MSUF_A2_FastCall(applyOffsets, icon, icon._msufUnit, shared)
        end

        -- Update cooldown visuals (duration object preferred; fallback to SetCooldown).
        if icon._msufA2_previewDurationObj and icon.cooldown.SetCooldownFromDurationObject then
            MSUF_A2_FastCall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, icon._msufA2_previewDurationObj)
        elseif icon.cooldown.SetCooldown then
            local start = (icon._msufA2_previewCooldownT or 0) + (GetTime() - 10)
            local dur = 10
            MSUF_A2_FastCall(icon.cooldown.SetCooldown, icon.cooldown, start, dur)
        end

        if type(reg) == "function" then
            MSUF_A2_FastCall(reg, icon)
        end
        if type(unreg) == "function" then
            -- RegisterIcon may already manage its own registry; we only unregister when ticker stops/clears.
            -- Leave unreg here unused during active ticking.
        end
     end)
 end

local function EnsureTicker(kind, need, interval, fn) 
    local t = PreviewTickers[kind]
    if need then
        if not t then
            PreviewTickers[kind] = C_Timer.NewTicker(interval, fn)
        end
    else
        if t then
            t:Cancel()
            PreviewTickers[kind] = nil
        end
    end
 end

local function UpdatePreviewStackTicker() 
    local a2, shared = EnsureDB()

    -- If the user disables Edit Mode previews, hard-clear any existing preview icons immediately.
    if shared and shared.showInEditMode ~= true then
        if API.ClearAllPreviews then
            API.ClearAllPreviews()
        end
    end

    local need = ShouldRunPreviewTicker("stacks", a2, shared)
    EnsureTicker("stacks", need, 0.50, PreviewTickStacks)
 end


local function UpdatePreviewCooldownTicker() 
    local a2, shared = EnsureDB()

    -- If the user disables Edit Mode previews, hard-clear any existing preview icons immediately.
    if shared and shared.showInEditMode ~= true then
        if API.ClearAllPreviews then
            API.ClearAllPreviews()
        end
    end

    local need = ShouldRunPreviewTicker("cooldown", a2, shared)
    EnsureTicker("cooldown", need, 0.50, PreviewTickCooldown)
 end


Preview.UpdatePreviewStackTicker = UpdatePreviewStackTicker
Preview.UpdatePreviewCooldownTicker = UpdatePreviewCooldownTicker

API.UpdatePreviewStackTicker = API.UpdatePreviewStackTicker or UpdatePreviewStackTicker
API.UpdatePreviewCooldownTicker = API.UpdatePreviewCooldownTicker or UpdatePreviewCooldownTicker

if _G and type(_G.MSUF_Auras2_UpdatePreviewStackTicker) ~= "function" then
    _G.MSUF_Auras2_UpdatePreviewStackTicker = function() 
        if API and API.UpdatePreviewStackTicker then
            return API.UpdatePreviewStackTicker()
        end
     end
end

if _G and type(_G.MSUF_Auras2_UpdatePreviewCooldownTicker) ~= "function" then
    _G.MSUF_Auras2_UpdatePreviewCooldownTicker = function() 
        if API and API.UpdatePreviewCooldownTicker then
            return API.UpdatePreviewCooldownTicker()
        end
     end
end

