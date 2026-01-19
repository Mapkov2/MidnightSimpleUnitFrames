-- MSUF_3DPortraits.lua
-- Drop-in module: converts MSUF 2D portrait textures into 3D PlayerModel portraits.
--
-- Design goals:
--  - Self-contained: no edits required in core files.
--  - Secret-safe & low overhead: reuses MSUF portrait dirty/budget behavior.
--  - Minimal regression risk: if 3D is disabled, falls back to the original MSUF portrait path.
--
-- Toggle:
--  - Per-unit: conf.portraitRender can be "2D" or "3D" (set by Options Player dropdown).
--  - Global default: MSUF_DB.general.use3DPortraits == true enables 3D for units that don't explicitly request 2D.
--  - If global is nil/false, portraits stay 2D unless a unit explicitly requests 3D.

local ADDON = "MSUF_3DPortraits"

-- ------------------------------------------------------------
-- Toggle / helpers
-- ------------------------------------------------------------
local function DB_Use3D()
    local db = _G.MSUF_DB
    local g = (type(db) == "table") and db.general or nil
    if type(g) ~= "table" then
        -- Default: keep legacy behavior (2D) unless the user opts into 3D.
        return false
    end
    return (g.use3DPortraits == true)
end

_G.MSUF_Use3DPortraits = _G.MSUF_Use3DPortraits or DB_Use3D

local function Want3D(conf)
    if type(conf) == "table" then
        local r = conf.portraitRender
        if r == "2D" then return false end
        if r == "3D" then return true end
    end
    return DB_Use3D()
end


local function SafeCall(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) == "function" then
        return fn(obj, ...)
    end
end

-- ------------------------------------------------------------
-- Model creation + layout
-- ------------------------------------------------------------
local function EnsureModel(f)
    if not f then return nil end
    local m = rawget(f, "portraitModel")
    if m and m.SetUnit then
        return m
    end

    m = CreateFrame("PlayerModel", nil, f)
    m:Hide()
    m:EnableMouse(false)

    -- Keep it above the main bars so it doesn't get hidden behind textures.
    local baseLevel = (f.hpBar and f.hpBar.GetFrameLevel and f.hpBar:GetFrameLevel()) or (f.GetFrameLevel and f:GetFrameLevel()) or 0
    m:SetFrameLevel(baseLevel + 5)

    -- Default camera/zoom tuning (safe-checked).
    -- These are intentionally conservative; users can add UI options later.
    SafeCall(m, "SetPortraitZoom", 1)
    SafeCall(m, "SetCamDistanceScale", 1)
    SafeCall(m, "SetRotation", 0)

    f.portraitModel = m
    return m
end

local function ApplyPortraitLayoutToWidget(f, conf, widget)
    if not f or not conf or not widget then return end

    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local size = math.max(16, (tonumber(h) or 30) - 4)

    widget:ClearAllPoints()
    widget:SetSize(size, size)

    local anchor = f.hpBar or f
    if f._msufPowerBarReserved then
        -- Matches MSUF_UpdateBossPortraitLayout behavior.
        anchor = f
    end

    if mode == "LEFT" then
        widget:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
        widget:Show()
    elseif mode == "RIGHT" then
        widget:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
        widget:Show()
    else
        widget:Hide()
    end
end

-- Layout stamping so we don't repeatedly ClearAllPoints/SetSize.
local function ApplyModelLayoutIfNeeded(f, conf)
    if not f or not conf then return end
    local m = rawget(f, "portraitModel")
    if not (m and m.SetUnit) then return end

    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local stamp = tostring(mode) .. "|" .. tostring(h)

    if f._msufPortraitModelLayoutStamp ~= stamp then
        f._msufPortraitModelLayoutStamp = stamp
        ApplyPortraitLayoutToWidget(f, conf, m)
    end
end

-- ------------------------------------------------------------
-- Budgeted updates (mirrors MSUF behavior)
-- ------------------------------------------------------------
local PORTRAIT_MIN_INTERVAL = 0.06
local BUDGET_USED = false
local BUDGET_RESET_SCHEDULED = false

local function ResetBudgetNextFrame()
    if BUDGET_RESET_SCHEDULED then return end
    BUDGET_RESET_SCHEDULED = true

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            BUDGET_USED = false
            BUDGET_RESET_SCHEDULED = false
        end)
    else
        BUDGET_USED = false
        BUDGET_RESET_SCHEDULED = false
    end
end

-- ------------------------------------------------------------
-- Core override: MSUF_UpdatePortraitIfNeeded
-- ------------------------------------------------------------
local ORIG_UpdatePortraitIfNeeded = _G.MSUF_UpdatePortraitIfNeeded

local function UpdatePortrait3D(f, unit, conf, existsForPortrait)
    if not f or not conf then return end

    local mode = conf.portraitMode or "OFF"
    local tex = f.portrait

    if mode == "OFF" or not existsForPortrait then
        if tex and tex.Hide then tex:Hide() end
        local m = rawget(f, "portraitModel")
        if m and m.Hide then m:Hide() end
        return
    end

    local m = EnsureModel(f)
    ApplyModelLayoutIfNeeded(f, conf)

    if f._msufPortraitDirty then
        local now = (GetTime and GetTime()) or 0
        local nextAt = tonumber(f._msufPortraitNextAt) or 0

        if (now >= nextAt) and (not BUDGET_USED) then
            -- Refresh model
            SafeCall(m, "ClearModel")
            SafeCall(m, "SetUnit", unit)

            -- Apply conservative defaults after SetUnit (some clients reset camera on SetUnit).
            SafeCall(m, "SetPortraitZoom", 1)
            SafeCall(m, "SetCamDistanceScale", 1)
            SafeCall(m, "SetRotation", 0)

            f._msufPortraitDirty = nil
            f._msufPortraitNextAt = now + PORTRAIT_MIN_INTERVAL
            BUDGET_USED = true
            ResetBudgetNextFrame()
        else
            ResetBudgetNextFrame()
        end
    end

    if tex and tex.Hide then tex:Hide() end
    if m and m.Show then m:Show() end
end

local function UpdatePortrait2D_Fallback(f, unit, conf, existsForPortrait)
    -- If MSUF already provides a global implementation, use it.
    if type(ORIG_UpdatePortraitIfNeeded) == "function" and ORIG_UpdatePortraitIfNeeded ~= UpdatePortrait2D_Fallback then
        local r = ORIG_UpdatePortraitIfNeeded(f, unit, conf, existsForPortrait)
        local m = rawget(f, "portraitModel")
        if m and m.Hide then m:Hide() end
        return r
    end

    -- Otherwise: replicate the current MSUF logic (layout stamp + SetPortraitTexture budgeted by dirty flag).
    if not f or not conf then return end
    local tex = f.portrait
    if not tex then return end

    local mode = conf.portraitMode or "OFF"
    if mode == "OFF" or not existsForPortrait then
        if tex.Hide then tex:Hide() end
        local m = rawget(f, "portraitModel")
        if m and m.Hide then m:Hide() end
        return
    end

    -- Layout (use MSUF_UpdateBossPortraitLayout if available; else mirror it).
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local stamp = tostring(mode) .. "|" .. tostring(h)
    if f._msufPortraitLayoutStamp ~= stamp then
        f._msufPortraitLayoutStamp = stamp
        if type(_G.MSUF_UpdateBossPortraitLayout) == "function" then
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

    local m = rawget(f, "portraitModel")
    if m and m.Hide then m:Hide() end

end

_G.MSUF_UpdatePortraitIfNeeded = function(f, unit, conf, existsForPortrait)
    if Want3D(conf) then
        return UpdatePortrait3D(f, unit, conf, existsForPortrait)
    end
    return UpdatePortrait2D_Fallback(f, unit, conf, existsForPortrait)
end

-- ------------------------------------------------------------
-- Layout hook: ensure models stay aligned when MSUF updates portrait layout
-- ------------------------------------------------------------
local ORIG_UpdateBossPortraitLayout = _G.MSUF_UpdateBossPortraitLayout

_G.MSUF_UpdateBossPortraitLayout = function(f, conf)
    if type(ORIG_UpdateBossPortraitLayout) == "function" then
        ORIG_UpdateBossPortraitLayout(f, conf)
    elseif f and conf and f.portrait then
        -- Fallback mirror.
        ApplyPortraitLayoutToWidget(f, conf, f.portrait)
    end

    -- If 3D is wanted for this unit, keep the model aligned too.
    if Want3D(conf) and f and conf then
        local m = rawget(f, "portraitModel")
        if m and m.SetUnit then
            f._msufPortraitModelLayoutStamp = nil
            ApplyModelLayoutIfNeeded(f, conf)
        end
    end
end

-- ------------------------------------------------------------
-- Boss Edit Mode preview compatibility
-- ------------------------------------------------------------
-- MSUF_EditMode's fake boss portrait uses SetPortraitTexture(frame.portrait, "player").
-- We can't edit that local function from here, so we convert those calls on MSUF portraits.
-- This hook is gated hard to MSUF portrait textures and only does work when 3D is enabled.
--
-- We mark MSUF portrait textures the first time we see them in our update function.
local HOOKED_SetPortraitTexture = false

local function MarkPortraitTexture(f)
    local tex = f and f.portrait
    if tex and type(tex) == "table" then
        tex.__MSUF_PortraitTexture = true
        tex.__MSUF_PortraitOwner = f
    end
end

-- Ensure we mark on first update attempts.
local _OrigWrapper = _G.MSUF_UpdatePortraitIfNeeded
_G.MSUF_UpdatePortraitIfNeeded = function(f, unit, conf, existsForPortrait)
    MarkPortraitTexture(f)
    return _OrigWrapper(f, unit, conf, existsForPortrait)
end

local function Hook_SetPortraitTexture()
    if HOOKED_SetPortraitTexture then return end
    if type(hooksecurefunc) ~= "function" then return end
    if type(SetPortraitTexture) ~= "function" then return end

    HOOKED_SetPortraitTexture = true

    hooksecurefunc("SetPortraitTexture", function(tex, unit)
        -- Don't early-return purely on global; BossTestMode may request 3D explicitly per-unit.
        -- We'll decide after we resolve the owning unit's conf.
        if not tex then return end

        -- If not explicitly marked yet (e.g. BossTestMode fake portrait),
        -- try to detect MSUF portraits by parent ownership.
        if not tex.__MSUF_PortraitTexture then
            local p = (tex.GetParent and tex:GetParent()) or nil
            if p and (p.portrait == tex) then
                local nm = (p.GetName and p:GetName()) or ""
                if p.unitKey or p.isBoss or (type(nm) == "string" and nm:find("MSUF_", 1, true) == 1) then
                    tex.__MSUF_PortraitTexture = true
                    tex.__MSUF_PortraitOwner = p
                else
                    return
                end
            else
                return
            end
        end

        local f = tex.__MSUF_PortraitOwner
        if not f then return end
        local conf = nil

        -- Best-effort conf lookup (boss preview uses MSUF_DB.boss).
        local db = _G.MSUF_DB
        if type(db) == "table" then
            if f.isBoss then
                conf = db.boss
            else
                local key = f.unitKey or f.msufConfigKey or f.unit
                if key and type(db[key]) == "table" then
                    conf = db[key]
                end
            end
        end

        local want3d = Want3D(conf)
        if not want3d then
            return
        end

        -- If we can't find conf, still attempt a minimal conversion.
        local m = EnsureModel(f)
        if conf then
            ApplyModelLayoutIfNeeded(f, conf)
        end

        -- Convert the placeholder to a real model.
        SafeCall(m, "ClearModel")
        SafeCall(m, "SetUnit", unit)
        SafeCall(m, "SetPortraitZoom", 1)
        SafeCall(m, "SetCamDistanceScale", 1)
        SafeCall(m, "SetRotation", 0)

        -- Hide the 2D texture, show the model.
        SafeCall(tex, "Hide")
        SafeCall(m, "Show")
    end)
end

Hook_SetPortraitTexture()

-- ------------------------------------------------------------
-- Optional: public helper to force-refresh all portrait models
-- ------------------------------------------------------------
_G.MSUF_3DPortraits_ForceRefresh = function()
    -- Mark all known unitframes dirty so the next UFCore flush rebuilds the model.
    local keys = { "player", "target", "focus", "pet", "targettarget" }
    for _, k in ipairs(keys) do
        local f = _G["MSUF_" .. k]
        if f then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
        end
    end
    for i = 1, 5 do
        local f = _G["MSUF_boss" .. i]
        if f then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
        end
    end
end

-- Module loaded.
_G.MSUF_3DPortraits_Loaded = true
