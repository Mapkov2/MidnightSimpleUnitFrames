--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua"); -- Auras2: Preview + Edit Mode helper (split from MSUF_A2_Render.lua)
-- Goal: isolate preview/ticker/cleanup logic to reduce Render bloat, with zero feature regression.

local addonName, ns = ...


-- MSUF: Max-perf Auras2: replace protected calls (pcall) with direct calls.
-- NOTE: this removes error-catching; any error will propagate.
local function MSUF_A2_FastCall(fn, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_FastCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:9:6");
    return Perfy_Trace_Passthrough("Leave", "MSUF_A2_FastCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:9:6", true, fn(...))
end
local API = ns and ns.MSUF_Auras2
if type(API) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua"); return end

API.Preview = (type(API.Preview) == "table") and API.Preview or {}
local Preview = API.Preview

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function IsEditModeActive() Perfy_Trace(Perfy_GetTime(), "Enter", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:22:6");
    -- MSUF-only Edit Mode (Blizzard Edit Mode intentionally ignored here).
    -- Keep this identical to the helper used in the render module so preview/flush transitions are reliable.
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active == true then
        Perfy_Trace(Perfy_GetTime(), "Leave", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:22:6"); return true
    end

    -- Legacy global boolean used by older patches
    if rawget(_G, "MSUF_UnitEditModeActive") == true then
        Perfy_Trace(Perfy_GetTime(), "Leave", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:22:6"); return true
    end

    -- Exported helper from MSUF_EditMode.lua
    local f = rawget(_G, "MSUF_IsInEditMode")
    if type(f) == "function" then
        local ok, v = MSUF_A2_FastCall(f)
        if ok and v == true then
            Perfy_Trace(Perfy_GetTime(), "Leave", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:22:6"); return true
        end
    end

    -- Compatibility hook name from older experiments (last resort)
    local g = rawget(_G, "MSUF_IsMSUFEditModeActive")
    if type(g) == "function" then
        local ok, v = MSUF_A2_FastCall(g)
        if ok and v == true then
            Perfy_Trace(Perfy_GetTime(), "Leave", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:22:6"); return true
        end
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:22:6"); return false
end


API.IsEditModeActive = API.IsEditModeActive or IsEditModeActive

local function EnsureDB() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:59:6");
    local Ensure = API.EnsureDB
    if type(Ensure) ~= "function" and API.DB and type(API.DB.Ensure) == "function" then
        Ensure = API.DB.Ensure
    end
    if type(Ensure) == "function" then
        return Perfy_Trace_Passthrough("Leave", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:59:6", Ensure())
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:59:6"); return nil, nil
end

local function GetAurasByUnit() Perfy_Trace(Perfy_GetTime(), "Enter", "GetAurasByUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:70:6");
    local st = API.state
    if type(st) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "GetAurasByUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:70:6"); return nil end
    return Perfy_Trace_Passthrough("Leave", "GetAurasByUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:70:6", st.aurasByUnit)
end

local function GetCooldownTextMgr() Perfy_Trace(Perfy_GetTime(), "Enter", "GetCooldownTextMgr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:76:6");
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

    Perfy_Trace(Perfy_GetTime(), "Leave", "GetCooldownTextMgr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:76:6"); return reg, unreg
end

local function GetRenderHelpers() Perfy_Trace(Perfy_GetTime(), "Enter", "GetRenderHelpers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:92:6");
    return Perfy_Trace_Passthrough("Leave", "GetRenderHelpers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:92:6", (type(API._Render) == "table") and API._Render or nil)
end

-- ------------------------------------------------------------
-- Preview cleanup (safety): ensure preview icons never block real auras
-- ------------------------------------------------------------

local function ClearPreviewIconsInContainer(container) Perfy_Trace(Perfy_GetTime(), "Enter", "ClearPreviewIconsInContainer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:100:6");
    if not container or not container._msufIcons then Perfy_Trace(Perfy_GetTime(), "Leave", "ClearPreviewIconsInContainer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:100:6"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "ClearPreviewIconsInContainer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:100:6"); end

local function ClearPreviewsForEntry(entry) Perfy_Trace(Perfy_GetTime(), "Enter", "ClearPreviewsForEntry file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:137:6");
    if not entry then Perfy_Trace(Perfy_GetTime(), "Leave", "ClearPreviewsForEntry file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:137:6"); return end
    ClearPreviewIconsInContainer(entry.buffs)
    ClearPreviewIconsInContainer(entry.debuffs)
    ClearPreviewIconsInContainer(entry.mixed)
    ClearPreviewIconsInContainer(entry.private)
    entry._msufA2_previewActive = nil
Perfy_Trace(Perfy_GetTime(), "Leave", "ClearPreviewsForEntry file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:137:6"); end

local function ClearAllPreviews() Perfy_Trace(Perfy_GetTime(), "Enter", "ClearAllPreviews file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:146:6");
    local AurasByUnit = GetAurasByUnit()
    if type(AurasByUnit) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "ClearAllPreviews file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:146:6"); return end

    for _, entry in pairs(AurasByUnit) do
        if entry and entry._msufA2_previewActive == true then
            ClearPreviewsForEntry(entry)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ClearAllPreviews file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:146:6"); end

Preview.ClearPreviewsForEntry = ClearPreviewsForEntry
Preview.ClearAllPreviews = ClearAllPreviews

-- Keep existing public exports stable for Options + other modules.
API.ClearPreviewsForEntry = API.ClearPreviewsForEntry or ClearPreviewsForEntry
API.ClearAllPreviews = API.ClearAllPreviews or ClearAllPreviews

if _G and type(_G.MSUF_Auras2_ClearAllPreviews) ~= "function" then
    _G.MSUF_Auras2_ClearAllPreviews = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Auras2_ClearAllPreviews file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:165:38"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Auras2_ClearAllPreviews file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:165:38", API.ClearAllPreviews()) end
end

-- ------------------------------------------------------------
-- Preview tickers (Edit Mode): cycle stacks + cooldowns
-- ------------------------------------------------------------

local PreviewTickers = {
    stacks = nil,
    cooldown = nil,
}

local function ShouldRunPreviewTicker(kind, a2, shared) Perfy_Trace(Perfy_GetTime(), "Enter", "ShouldRunPreviewTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:177:6");
    if not a2 or not a2.enabled then Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldRunPreviewTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:177:6"); return false end
    if not shared or shared.showInEditMode ~= true then Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldRunPreviewTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:177:6"); return false end
    if not API.IsEditModeActive or API.IsEditModeActive() ~= true then Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldRunPreviewTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:177:6"); return false end
    if kind == "stacks" and shared.showStackCount == false then Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldRunPreviewTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:177:6"); return false end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldRunPreviewTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:177:6"); return true
end

local function ForEachPreviewIcon(fn) Perfy_Trace(Perfy_GetTime(), "Enter", "ForEachPreviewIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:185:6");
    local AurasByUnit = GetAurasByUnit()
    if type(AurasByUnit) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "ForEachPreviewIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:185:6"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "ForEachPreviewIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:185:6"); end

local function PreviewTickStacks() Perfy_Trace(Perfy_GetTime(), "Enter", "PreviewTickStacks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:205:6");
    local a2, shared = EnsureDB()
    if not ShouldRunPreviewTicker("stacks", a2, shared) then Perfy_Trace(Perfy_GetTime(), "Leave", "PreviewTickStacks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:205:6"); return end

    local H = GetRenderHelpers()
    local applyAnchorStyle = H and H.ApplyStackCountAnchorStyle
    local applyOffsets = H and H.ApplyStackTextOffsets

    local stackCountAnchor = shared and shared.stackCountAnchor
    local ox = shared and shared.stackTextOffsetX
    local oy = shared and shared.stackTextOffsetY

    ForEachPreviewIcon(function(icon) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:217:23");
        if not icon or not icon.count then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:217:23"); return end

        if type(applyAnchorStyle) == "function" then
            MSUF_A2_FastCall(applyAnchorStyle, icon, stackCountAnchor)
        end
        if type(applyOffsets) == "function" then
            MSUF_A2_FastCall(applyOffsets, icon, ox, oy, stackCountAnchor)
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:217:23"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "PreviewTickStacks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:205:6"); end

local function PreviewTickCooldown() Perfy_Trace(Perfy_GetTime(), "Enter", "PreviewTickCooldown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:245:6");
    local a2, shared = EnsureDB()
    if not ShouldRunPreviewTicker("cooldown", a2, shared) then Perfy_Trace(Perfy_GetTime(), "Leave", "PreviewTickCooldown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:245:6"); return end

    local H = GetRenderHelpers()
    local applyOffsets = H and H.ApplyCooldownTextOffsets

    local anchor = shared and shared.cooldownTextAnchor
    local ox = shared and shared.cooldownTextOffsetX
    local oy = shared and shared.cooldownTextOffsetY

    local reg, unreg = GetCooldownTextMgr()

    ForEachPreviewIcon(function(icon) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:258:23");
        if not icon or not icon.cooldown then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:258:23"); return end

        -- Ensure countdown text is visible (OmniCC removed in Midnight).
        if icon.cooldown.SetHideCountdownNumbers then
            MSUF_A2_FastCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
        end

        if type(applyOffsets) == "function" then
            MSUF_A2_FastCall(applyOffsets, icon, ox, oy, anchor)
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:258:23"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "PreviewTickCooldown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:245:6"); end

local function EnsureTicker(kind, need, interval, fn) Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:289:6");
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
Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:289:6"); end

local function UpdatePreviewStackTicker() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdatePreviewStackTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:303:6");
    local a2, shared = EnsureDB()

    -- If the user disables Edit Mode previews, hard-clear any existing preview icons immediately.
    if shared and shared.showInEditMode ~= true then
        if API.ClearAllPreviews then
            API.ClearAllPreviews()
        end
    end

    local need = ShouldRunPreviewTicker("stacks", a2, shared)
    EnsureTicker("stacks", need, 0.50, PreviewTickStacks)
Perfy_Trace(Perfy_GetTime(), "Leave", "UpdatePreviewStackTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:303:6"); end


local function UpdatePreviewCooldownTicker() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdatePreviewCooldownTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:318:6");
    local a2, shared = EnsureDB()

    -- If the user disables Edit Mode previews, hard-clear any existing preview icons immediately.
    if shared and shared.showInEditMode ~= true then
        if API.ClearAllPreviews then
            API.ClearAllPreviews()
        end
    end

    local need = ShouldRunPreviewTicker("cooldown", a2, shared)
    EnsureTicker("cooldown", need, 0.50, PreviewTickCooldown)
Perfy_Trace(Perfy_GetTime(), "Leave", "UpdatePreviewCooldownTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:318:6"); end


Preview.UpdatePreviewStackTicker = UpdatePreviewStackTicker
Preview.UpdatePreviewCooldownTicker = UpdatePreviewCooldownTicker

API.UpdatePreviewStackTicker = API.UpdatePreviewStackTicker or UpdatePreviewStackTicker
API.UpdatePreviewCooldownTicker = API.UpdatePreviewCooldownTicker or UpdatePreviewCooldownTicker

if _G and type(_G.MSUF_Auras2_UpdatePreviewStackTicker) ~= "function" then
    _G.MSUF_Auras2_UpdatePreviewStackTicker = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Auras2_UpdatePreviewStackTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:340:46");
        if API and API.UpdatePreviewStackTicker then
            return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Auras2_UpdatePreviewStackTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:340:46", API.UpdatePreviewStackTicker())
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_Auras2_UpdatePreviewStackTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:340:46"); end
end

if _G and type(_G.MSUF_Auras2_UpdatePreviewCooldownTicker) ~= "function" then
    _G.MSUF_Auras2_UpdatePreviewCooldownTicker = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Auras2_UpdatePreviewCooldownTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:348:49");
        if API and API.UpdatePreviewCooldownTicker then
            return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Auras2_UpdatePreviewCooldownTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:348:49", API.UpdatePreviewCooldownTicker())
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_Auras2_UpdatePreviewCooldownTicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua:348:49"); end
end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Preview.lua");