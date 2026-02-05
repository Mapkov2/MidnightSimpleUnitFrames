--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua"); -- MSUF_3DPortraits.lua
-- Drop-in module: per-frame 2D vs 3D portraits (exclusive) + Portrait OFF.
--
-- Per-frame DB contract:
--   conf.portraitMode   = 'OFF' | 'LEFT' | 'RIGHT'
--   conf.portraitRender = nil | '2D' | '3D'   (nil defaults to 2D)
--
-- Exclusivity:
--   * If 3D is selected => hide 2D texture.
--   * If 2D is selected => hide 3D model.
--   * If OFF => hide both.

local _G = _G

-- Idempotent load guard (this file may be loaded twice in some packagers).
if _G and _G.MSUF_3DPortraits_Loaded then
    Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua"); return
end

local ADDON = 'MSUF_3DPortraits'

-- Capture any existing MSUF portrait updater (may be nil in some builds).
local ORIG_UpdatePortraitIfNeeded = _G and _G.MSUF_UpdatePortraitIfNeeded

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------
local function SafeCall(obj, method, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "SafeCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:28:6");
    local fn = obj and obj[method]
    if type(fn) == 'function' then
        return Perfy_Trace_Passthrough("Leave", "SafeCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:28:6", fn(obj, ...))
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "SafeCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:28:6"); end

local function IsPortraitModeActive(conf) Perfy_Trace(Perfy_GetTime(), "Enter", "IsPortraitModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:35:6");
    if type(conf) ~= 'table' then Perfy_Trace(Perfy_GetTime(), "Leave", "IsPortraitModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:35:6"); return false end
    local pm = conf.portraitMode
    return Perfy_Trace_Passthrough("Leave", "IsPortraitModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:35:6", (pm == 'LEFT' or pm == 'RIGHT'))
end

local function Want3D(conf) Perfy_Trace(Perfy_GetTime(), "Enter", "Want3D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:41:6");
    if type(conf) ~= 'table' then Perfy_Trace(Perfy_GetTime(), "Leave", "Want3D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:41:6"); return false end
    if not IsPortraitModeActive(conf) then Perfy_Trace(Perfy_GetTime(), "Leave", "Want3D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:41:6"); return false end
    return Perfy_Trace_Passthrough("Leave", "Want3D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:41:6", (conf.portraitRender == '3D'))
end

local function Want2D(conf) Perfy_Trace(Perfy_GetTime(), "Enter", "Want2D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:47:6");
    if type(conf) ~= 'table' then Perfy_Trace(Perfy_GetTime(), "Leave", "Want2D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:47:6"); return false end
    if not IsPortraitModeActive(conf) then Perfy_Trace(Perfy_GetTime(), "Leave", "Want2D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:47:6"); return false end
    return Perfy_Trace_Passthrough("Leave", "Want2D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:47:6", (conf.portraitRender ~= '3D'))
end

-- ------------------------------------------------------------
-- Model creation + layout mirroring
-- ------------------------------------------------------------
local function EnsureModel(f) Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureModel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:56:6");
    if not f then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureModel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:56:6"); return nil end
    local m = rawget(f, 'portraitModel')
    if m and m.SetUnit then
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureModel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:56:6"); return m
    end

    m = CreateFrame('PlayerModel', nil, f)
    m:Hide()
    m:EnableMouse(false)

    local baseLevel = (f.hpBar and f.hpBar.GetFrameLevel and f.hpBar:GetFrameLevel())
        or (f.GetFrameLevel and f:GetFrameLevel())
        or 0
    m:SetFrameLevel(baseLevel + 5)

    -- Conservative defaults (can be tuned later)
    SafeCall(m, 'SetPortraitZoom', 1)
    SafeCall(m, 'SetCamDistanceScale', 1)
    SafeCall(m, 'SetRotation', 0)

    f.portraitModel = m
    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureModel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:56:6"); return m
end

local function ApplyPortraitLayoutToWidget(f, conf, widget) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyPortraitLayoutToWidget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:81:6");
    if not (f and conf and widget) then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyPortraitLayoutToWidget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:81:6"); return end

    local mode = conf.portraitMode or 'OFF'
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local size = math.max(16, (tonumber(h) or 30) - 4)

    widget:ClearAllPoints()
    widget:SetSize(size, size)

    local anchor = f.hpBar or f
    -- Match MSUF_UpdateBossPortraitLayout: if powerbar is reserved, anchor to frame instead of hpBar.
    if f._msufPowerBarReserved then
        anchor = f
    end

    if mode == 'LEFT' then
        widget:SetPoint('RIGHT', anchor, 'LEFT', 0, 0)
        widget:Show()
    elseif mode == 'RIGHT' then
        widget:SetPoint('LEFT', anchor, 'RIGHT', 0, 0)
        widget:Show()
    else
        widget:Hide()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyPortraitLayoutToWidget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:81:6"); end

local function ApplyModelLayoutIfNeeded(f, conf) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyModelLayoutIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:108:6");
    local m = rawget(f, 'portraitModel')
    if not (m and m.SetUnit) then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyModelLayoutIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:108:6"); return end

    local mode = conf.portraitMode or 'OFF'
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local stamp = tostring(mode) .. '|' .. tostring(h)

    if f._msufPortraitModelLayoutStamp ~= stamp then
        f._msufPortraitModelLayoutStamp = stamp
        ApplyPortraitLayoutToWidget(f, conf, m)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyModelLayoutIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:108:6"); end

-- ------------------------------------------------------------
-- Budgeted updates (local, mirrors MSUF logic)
-- ------------------------------------------------------------
local PORTRAIT_MIN_INTERVAL = 0.06
local BUDGET_USED = false
local BUDGET_RESET_SCHEDULED = false

local function ResetBudgetNextFrame() Perfy_Trace(Perfy_GetTime(), "Enter", "ResetBudgetNextFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:129:6");
    if BUDGET_RESET_SCHEDULED then Perfy_Trace(Perfy_GetTime(), "Leave", "ResetBudgetNextFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:129:6"); return end
    BUDGET_RESET_SCHEDULED = true

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:134:25");
            BUDGET_USED = false
            BUDGET_RESET_SCHEDULED = false
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:134:25"); end)
    else
        BUDGET_USED = false
        BUDGET_RESET_SCHEDULED = false
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ResetBudgetNextFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:129:6"); end

-- ------------------------------------------------------------
-- 2D fallback (exclusive)
-- ------------------------------------------------------------
local function UpdatePortrait2D(f, unit, conf, existsForPortrait) Perfy_Trace(Perfy_GetTime(), "Enter", "UpdatePortrait2D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:147:6");
    if not (f and conf) then Perfy_Trace(Perfy_GetTime(), "Leave", "UpdatePortrait2D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:147:6"); return end

    -- Exclusivity: 2D path always hides 3D model.
    local m = rawget(f, 'portraitModel')
    if m and m.Hide then m:Hide() end

    -- Respect OFF
    if not IsPortraitModeActive(conf) or not existsForPortrait then
        if f.portrait and f.portrait.Hide then f.portrait:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "UpdatePortrait2D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:147:6"); return
    end

    if type(ORIG_UpdatePortraitIfNeeded) == 'function' and ORIG_UpdatePortraitIfNeeded ~= _G.MSUF_UpdatePortraitIfNeeded then
        -- Call original if it exists (most builds)
        return Perfy_Trace_Passthrough("Leave", "UpdatePortrait2D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:147:6", ORIG_UpdatePortraitIfNeeded(f, unit, conf, existsForPortrait))
    end

    -- Minimal fallback if no original exists
    local tex = f.portrait
    if not tex then Perfy_Trace(Perfy_GetTime(), "Leave", "UpdatePortrait2D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:147:6"); return end

    -- Layout stamp
    local mode = conf.portraitMode or 'OFF'
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local stamp = tostring(mode) .. '|' .. tostring(h)
    if f._msufPortraitLayoutStamp ~= stamp then
        f._msufPortraitLayoutStamp = stamp
        if type(_G.MSUF_UpdateBossPortraitLayout) == 'function' then
            _G.MSUF_UpdateBossPortraitLayout(f, conf)
        else
            ApplyPortraitLayoutToWidget(f, conf, tex)
        end
    end

    if f._msufPortraitDirty then
        local now = (GetTime and GetTime()) or 0
        local nextAt = tonumber(f._msufPortraitNextAt) or 0
        if (now >= nextAt) and (not BUDGET_USED) then
            if SetPortraitTexture then
                SetPortraitTexture(tex, unit)
            end
            f._msufPortraitDirty = nil
            f._msufPortraitNextAt = now + PORTRAIT_MIN_INTERVAL
            BUDGET_USED = true
            ResetBudgetNextFrame()
        else
            ResetBudgetNextFrame()
        end
    end

    if tex.Show then tex:Show() end
Perfy_Trace(Perfy_GetTime(), "Leave", "UpdatePortrait2D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:147:6"); end

-- ------------------------------------------------------------
-- 3D updater (exclusive)
-- ------------------------------------------------------------
local function UpdatePortrait3D(f, unit, conf, existsForPortrait) Perfy_Trace(Perfy_GetTime(), "Enter", "UpdatePortrait3D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:204:6");
    if not (f and conf) then Perfy_Trace(Perfy_GetTime(), "Leave", "UpdatePortrait3D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:204:6"); return end

    local tex = f.portrait

    -- Respect OFF
    if not IsPortraitModeActive(conf) or not existsForPortrait then
        if tex and tex.Hide then tex:Hide() end
        local m = rawget(f, 'portraitModel')
        if m and m.Hide then m:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "UpdatePortrait3D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:204:6"); return
    end

    -- Exclusivity: 3D path always hides 2D texture.
    if tex and tex.Hide then tex:Hide() end

    local m = EnsureModel(f)
    ApplyModelLayoutIfNeeded(f, conf)

    if f._msufPortraitDirty then
        local now = (GetTime and GetTime()) or 0
        local nextAt = tonumber(f._msufPortraitNextAt) or 0

        if (now >= nextAt) and (not BUDGET_USED) then
            SafeCall(m, 'ClearModel')
            SafeCall(m, 'SetUnit', unit)
            -- Some clients reset cam on SetUnit; re-apply conservative defaults.
            SafeCall(m, 'SetPortraitZoom', 1)
            SafeCall(m, 'SetCamDistanceScale', 1)
            SafeCall(m, 'SetRotation', 0)

            f._msufPortraitDirty = nil
            f._msufPortraitNextAt = now + PORTRAIT_MIN_INTERVAL
            BUDGET_USED = true
            ResetBudgetNextFrame()
        else
            ResetBudgetNextFrame()
        end
    end

    if m and m.Show then m:Show() end
Perfy_Trace(Perfy_GetTime(), "Leave", "UpdatePortrait3D file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:204:6"); end

-- ------------------------------------------------------------
-- Global entrypoint used by UFCore (must exist)
-- ------------------------------------------------------------
_G.MSUF_UpdatePortraitIfNeeded = function(f, unit, conf, existsForPortrait) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_UpdatePortraitIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:250:33");
    -- Mark portrait textures for SetPortraitTexture hook (boss edit mode placeholders)
    local tex = f and f.portrait
    if tex and type(tex) == 'table' then
        tex.__MSUF_PortraitTexture = true
        tex.__MSUF_PortraitOwner = f
    end

    if Want3D(conf) then
        return Perfy_Trace_Passthrough("Leave", "_G.MSUF_UpdatePortraitIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:250:33", UpdatePortrait3D(f, unit, conf, existsForPortrait))
    end
    return Perfy_Trace_Passthrough("Leave", "_G.MSUF_UpdatePortraitIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:250:33", UpdatePortrait2D(f, unit, conf, existsForPortrait))
end

-- ------------------------------------------------------------
-- Keep 3D models aligned when MSUF updates portrait layout
-- ------------------------------------------------------------
if type(hooksecurefunc) == 'function' and type(_G.MSUF_UpdateBossPortraitLayout) == 'function' then
    hooksecurefunc('MSUF_UpdateBossPortraitLayout', function(f, conf) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:268:52");
        if not (f and conf) then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:268:52"); return end
        if Want3D(conf) then
            local m = rawget(f, 'portraitModel')
            if m and m.SetUnit then
                f._msufPortraitModelLayoutStamp = nil
                ApplyModelLayoutIfNeeded(f, conf)
            end
        else
            local m = rawget(f, 'portraitModel')
            if m and m.Hide then m:Hide() end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:268:52"); end)
end

-- ------------------------------------------------------------
-- Boss Edit Mode placeholder compatibility
-- ------------------------------------------------------------
-- MSUF_EditMode may call SetPortraitTexture(frame.portrait, 'player') for boss previews.
-- We convert THAT call into a 3D model only when that frame is actually configured for 3D
-- AND portraitMode is not OFF.

local HOOKED_SetPortraitTexture = false

local function LookupConfForFrame(f) Perfy_Trace(Perfy_GetTime(), "Enter", "LookupConfForFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:292:6");
    local db = _G.MSUF_DB
    if type(db) ~= 'table' then Perfy_Trace(Perfy_GetTime(), "Leave", "LookupConfForFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:292:6"); return nil end

    if f.isBoss then
        return Perfy_Trace_Passthrough("Leave", "LookupConfForFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:292:6", db.boss)
    end

    local key = f.unitKey or f.msufConfigKey or f.unit
    if key and type(db[key]) == 'table' then
        return Perfy_Trace_Passthrough("Leave", "LookupConfForFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:292:6", db[key])
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "LookupConfForFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:292:6"); return nil
end

local function Hook_SetPortraitTexture() Perfy_Trace(Perfy_GetTime(), "Enter", "Hook_SetPortraitTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:308:6");
    if HOOKED_SetPortraitTexture then Perfy_Trace(Perfy_GetTime(), "Leave", "Hook_SetPortraitTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:308:6"); return end
    if type(hooksecurefunc) ~= 'function' then Perfy_Trace(Perfy_GetTime(), "Leave", "Hook_SetPortraitTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:308:6"); return end
    if type(SetPortraitTexture) ~= 'function' then Perfy_Trace(Perfy_GetTime(), "Leave", "Hook_SetPortraitTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:308:6"); return end

    HOOKED_SetPortraitTexture = true

    hooksecurefunc('SetPortraitTexture', function(tex, unit) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:315:41");
        if not tex then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:315:41"); return end

        local f = tex.__MSUF_PortraitOwner
        if not f and tex.GetParent then
            local p = tex:GetParent()
            if p and (p.portrait == tex) then
                f = p
                tex.__MSUF_PortraitOwner = p
                tex.__MSUF_PortraitTexture = true
            end
        end

        if not f then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:315:41"); return end

        local conf = LookupConfForFrame(f)
        if not Want3D(conf) then
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:315:41"); return
        end

        -- If portraitMode is active and 3D is selected: convert.
        local m = EnsureModel(f)
        ApplyModelLayoutIfNeeded(f, conf)

        SafeCall(m, 'ClearModel')
        SafeCall(m, 'SetUnit', unit)
        SafeCall(m, 'SetPortraitZoom', 1)
        SafeCall(m, 'SetCamDistanceScale', 1)
        SafeCall(m, 'SetRotation', 0)

        SafeCall(tex, 'Hide')
        SafeCall(m, 'Show')
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:315:41"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "Hook_SetPortraitTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:308:6"); end

Hook_SetPortraitTexture()

-- ------------------------------------------------------------
-- Immediate sync helper (called from Options dropdown)
-- ------------------------------------------------------------
local function GetFramesForUnitKey(key) Perfy_Trace(Perfy_GetTime(), "Enter", "GetFramesForUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:355:6");
    if key == "tot" then key = "targettarget" end
    if key == "boss" then
        local t = {}
        for i = 1, 5 do
            local f = _G["MSUF_boss" .. i]
            if f then t[#t+1] = f end
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetFramesForUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:355:6"); return t
    end

    local f = _G["MSUF_" .. tostring(key)]
    if not f and key == "targettarget" then
        f = _G.MSUF_targettarget or _G.MSUF_tot
    end
    return Perfy_Trace_Passthrough("Leave", "GetFramesForUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:355:6", f and { f } or {})
end

function _G.MSUF_3DPortraits_SyncUnit(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_3DPortraits_SyncUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:373:0");
    if type(unitKey) ~= "string" or unitKey == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_3DPortraits_SyncUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:373:0"); return end
    local db = _G.MSUF_DB
    if type(db) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_3DPortraits_SyncUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:373:0"); return end

    local conf = (unitKey == "boss") and db.boss or db[unitKey]
    if unitKey == "tot" then conf = db.targettarget or db.tot end
    if type(conf) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_3DPortraits_SyncUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:373:0"); return end

    local frames = GetFramesForUnitKey(unitKey)
    for i = 1, #frames do
        local f = frames[i]
        local unit = (f and f.unit) or unitKey
        local exists = (UnitExists and UnitExists(unit)) or true

        -- Force a clean re-evaluation.
        if f then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
        end

        -- If the core skips portrait updates for OFF, we still hard-hide here.
        if not IsPortraitModeActive(conf) then
            if f and f.portrait and f.portrait.Hide then f.portrait:Hide() end
            local m = f and rawget(f, "portraitModel")
            if m and m.Hide then m:Hide() end
        else
            _G.MSUF_UpdatePortraitIfNeeded(f, unit, conf, exists)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_3DPortraits_SyncUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:373:0"); end

-- ------------------------------------------------------------
-- Safety net: if portraitMode is OFF, ensure a previously-visible 3D model
-- doesn't linger even if the core doesn't call MSUF_UpdatePortraitIfNeeded.
-- ------------------------------------------------------------
if type(hooksecurefunc) == "function" and type(_G.UpdateSimpleUnitFrame) == "function" then
    hooksecurefunc("UpdateSimpleUnitFrame", function(f) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:410:44");
        local conf = LookupConfForFrame(f)
        if type(conf) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:410:44"); return end
        if IsPortraitModeActive(conf) then
            if Want3D(conf) then
                local tex = f and f.portrait
                if tex and tex.Hide then tex:Hide() end
                local m = f and rawget(f, "portraitModel")
                if m and m.Show then m:Show() end
            else
                local m = f and rawget(f, "portraitModel")
                if m and m.Hide then m:Hide() end
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:410:44"); return
        end
        -- OFF: hard hide both.
        if f and f.portrait and f.portrait.Hide then f.portrait:Hide() end
        local m = f and rawget(f, "portraitModel")
        if m and m.Hide then m:Hide() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:410:44"); end)
end

-- ------------------------------------------------------------
-- Optional debug helper
-- ------------------------------------------------------------
_G.MSUF_3DPortraits_ForceRefresh = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_3DPortraits_ForceRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:435:35");
    local keys = { 'player', 'target', 'focus', 'pet', 'targettarget' }
    for _, k in ipairs(keys) do
        local f = _G['MSUF_' .. k]
        if f then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
        end
    end
    for i = 1, 5 do
        local f = _G['MSUF_boss' .. i]
        if f then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_3DPortraits_ForceRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua:435:35"); end

_G.MSUF_3DPortraits_Loaded = true

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_3DPortraits.lua");