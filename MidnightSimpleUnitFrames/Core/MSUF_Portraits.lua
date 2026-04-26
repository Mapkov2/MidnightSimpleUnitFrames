-- Core/MSUF_Portraits.lua — Unified 2D/3D/Class portrait system
-- Merged from MSUF_Portraits.lua + MSUF_3DPortraits.lua (zero feature regression).
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber, rawget = type, tonumber, rawget
local PM = ns.PortraitMedia

-- ── Helpers ──
local function SafeCall(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) == "function" then return fn(obj, ...) end
end

local function SetShown(obj, shown)
    if not obj then return end
    if shown then if obj.Show then obj:Show() end
    else if obj.Hide then obj:Hide() end end
end

local function IsPortraitModeActive(conf)
    if type(conf) ~= "table" then return false end
    local pm = conf.portraitMode
    return (pm == "LEFT" or pm == "RIGHT")
end

-- ── 3D Model creation ──
local function EnsureModel(f)
    if not f then return nil end
    local m = rawget(f, "portraitModel")
    if m and m.SetUnit then return m end
    m = CreateFrame("PlayerModel", nil, f)
    m:Hide()
    m:EnableMouse(false)
    local baseLevel = (f.hpBar and f.hpBar.GetFrameLevel and f.hpBar:GetFrameLevel())
        or (f.GetFrameLevel and f:GetFrameLevel()) or 0
    m:SetFrameLevel(baseLevel + 5)
    SafeCall(m, "SetPortraitZoom", 1)
    SafeCall(m, "SetCamDistanceScale", 1)
    SafeCall(m, "SetRotation", 0)
    f.portraitModel = m
    return m
end

-- ── Layout ──
local function ApplyPortraitLayout(f, conf, widget)
    if not (f and conf and widget) then return end
    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local size = math.max(16, (tonumber(h) or 30) - 4)
    widget:ClearAllPoints()
    widget:SetSize(size, size)
    local anchor = f.hpBar or f
    if f._msufPowerBarReserved then anchor = f end
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

function MSUF_UpdateBossPortraitLayout(f, conf)
    if not f or not f.portrait or not conf then return end
    ApplyPortraitLayout(f, conf, f.portrait)
end

local function ApplyPortraitLayoutIfNeeded(f, conf)
    if not f or not conf or not f.portrait then return end
    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    if ns.Cache.StampChanged(f, "PortraitLayout", mode, h) then
        ApplyPortraitLayout(f, conf, f.portrait)
    end
end

local function ApplyModelLayoutIfNeeded(f, conf)
    local m = rawget(f, "portraitModel")
    if not (m and m.SetUnit) then return end
    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local stamp = tostring(mode) .. "|" .. tostring(h)
    if f._msufPortraitModelLayoutStamp ~= stamp then
        f._msufPortraitModelLayoutStamp = stamp
        ApplyPortraitLayout(f, conf, m)
    end
end

-- ── Budget (one portrait render per frame) ──
local PORTRAIT_MIN_INTERVAL = 0.06
local _budgetUsed = false
local _budgetResetScheduled = false

local function ResetBudgetNextFrame()
    if _budgetResetScheduled then return end
    _budgetResetScheduled = true
    C_Timer.After(0, function()
        _budgetUsed = false
        _budgetResetScheduled = false
    end)
end

-- ── Core update function (2D / 3D / CLASS / OFF) ──
local function UpdatePortraitIfNeeded(f, unit, conf, existsForPortrait)
    if not f or not f.portrait or not conf then return end

    local mode = conf.portraitMode or "OFF"
    local render = conf.portraitRender
    if render ~= "3D" and render ~= "CLASS" then render = "2D" end

    local portrait = f.portrait
    local model = rawget(f, "portraitModel")

    -- Track render/mode changes
    local classStyle = conf.portraitClassStyle or "BLIZZARD"
    if f._msufPortraitClassStyleStamp ~= classStyle then
        f._msufPortraitClassStyleStamp = classStyle
        if mode ~= "OFF" then f._msufPortraitDirty = true; f._msufPortraitNextAt = 0 end
    end
    if f._msufPortraitRenderStamp ~= render then
        f._msufPortraitRenderStamp = render
        if mode ~= "OFF" then f._msufPortraitDirty = true; f._msufPortraitNextAt = 0 end
    end
    if f._msufPortraitModeStamp ~= mode then
        f._msufPortraitModeStamp = mode
        if mode ~= "OFF" then f._msufPortraitDirty = true; f._msufPortraitNextAt = 0 end
    end

    -- OFF: hide everything
    if mode == "OFF" then
        SetShown(portrait, false)
        SetShown(model, false)
        return
    end

    -- Preview support (Edit Mode / Boss Test)
    local allowPreview = false
    if not existsForPortrait then
        local inCombat = (F.InCombatLockdown and F.InCombatLockdown()) and true or false
        if not inCombat and (MSUF_UnitEditModeActive or (f.isBoss and MSUF_BossTestMode)) then
            allowPreview = true
        end
    end
    if not existsForPortrait and not allowPreview then
        SetShown(portrait, false)
        SetShown(model, false)
        return
    end

    -- Layout
    ApplyPortraitLayoutIfNeeded(f, conf)

    -- ── 3D path ──
    if render == "3D" then
        -- Hide 2D texture
        if portrait then
            if portrait.SetTexture then portrait:SetTexture(nil) end
            SetShown(portrait, false)
        end
        local m = EnsureModel(f)
        ApplyModelLayoutIfNeeded(f, conf)
        if f._msufPortraitDirty then
            local now = (F.GetTime and F.GetTime()) or 0
            local nextAt = tonumber(f._msufPortraitNextAt) or 0
            if (now >= nextAt) and not _budgetUsed then
                SafeCall(m, "ClearModel")
                local u = existsForPortrait and unit or "player"
                SafeCall(m, "SetUnit", u)
                SafeCall(m, "SetPortraitZoom", 1)
                SafeCall(m, "SetCamDistanceScale", 1)
                SafeCall(m, "SetRotation", 0)
                f._msufPortraitDirty = nil
                f._msufPortraitNextAt = now + PORTRAIT_MIN_INTERVAL
                _budgetUsed = true
                ResetBudgetNextFrame()
            else
                ResetBudgetNextFrame()
            end
        end
        SetShown(m, true)
        return
    end

    -- ── 2D / CLASS path ──
    -- Hide 3D model
    SetShown(model, false)

    if f._msufPortraitDirty then
        local now = (F.GetTime and F.GetTime()) or 0
        local nextAt = tonumber(f._msufPortraitNextAt) or 0
        if (now >= nextAt) and not _budgetUsed then
            if render == "CLASS" then
                local useClassIcon = false
                if not existsForPortrait then
                    useClassIcon = true
                elseif F.UnitIsPlayer and (F.UnitIsPlayer(unit) == true) then
                    useClassIcon = true
                end
                if useClassIcon then
                    local u = existsForPortrait and unit or "player"
                    local class = (F.UnitClassBase and F.UnitClassBase(u)) or (F.UnitClass and select(2, F.UnitClass(u)))
                    local style = conf.portraitClassStyle or "BLIZZARD"
                    local visual = PM and PM.ResolveClassPortrait and PM.ResolveClassPortrait(class, style) or nil
                    if visual and portrait.SetTexture and portrait.SetTexCoord then
                        portrait:SetTexture(visual.texture)
                        portrait:SetTexCoord(visual.left or 0, visual.right or 1, visual.top or 0, visual.bottom or 1)
                    else
                        if portrait.SetTexCoord then portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9) end
                        if existsForPortrait and SetPortraitTexture then
                            SetPortraitTexture(portrait, unit)
                        elseif portrait.SetTexture then
                            portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                        end
                    end
                else
                    if portrait.SetTexCoord then portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9) end
                    if existsForPortrait and SetPortraitTexture then
                        SetPortraitTexture(portrait, unit)
                    elseif portrait.SetTexture then
                        portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                    end
                end
            else
                -- 2D: standard portrait texture
                if portrait.SetTexCoord then portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9) end
                if existsForPortrait and SetPortraitTexture then
                    SetPortraitTexture(portrait, unit)
                elseif portrait.SetTexture then
                    portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                end
            end
            f._msufPortraitDirty = nil
            f._msufPortraitNextAt = now + PORTRAIT_MIN_INTERVAL
            _budgetUsed = true
            ResetBudgetNextFrame()
        else
            if not f._msufPortraitRetryScheduled and C_Timer and C_Timer.After then
                f._msufPortraitRetryScheduled = true
                local delay = 0
                if now < nextAt then delay = nextAt - now; if delay < 0 then delay = 0 end end
                C_Timer.After(delay, function()
                    if not f then return end
                    f._msufPortraitRetryScheduled = nil
                    if not f._msufPortraitDirty then return end
                    ns.UF.RequestUpdate(f, false, false, "PortraitRetry")
                end)
            end
            ResetBudgetNextFrame()
        end
    end
    portrait:Show()
end

_G.MSUF_UpdatePortraitIfNeeded = UpdatePortraitIfNeeded

-- ── Stamp-gated wrapper (hot-path gate) ──
local function MaybeUpdatePortrait(f, unit, conf, existsForPortrait)
    if not f or not f.portrait or not conf then return end

    local mode = conf.portraitMode or "OFF"
    local render = conf.portraitRender
    if render ~= "3D" and render ~= "CLASS" then render = "2D" end

    -- Fast OFF gate
    if mode == "OFF" and f._msufPortraitModeStamp == "OFF" and not f._msufPortraitDirty then
        SetShown(f.portrait, false)
        SetShown(rawget(f, "portraitModel"), false)
        return
    end

    local need = false
    if f._msufPortraitModeStamp ~= mode or f._msufPortraitRenderStamp ~= render then need = true end

    local h = tonumber(conf.height) or (f.GetHeight and f:GetHeight()) or 0
    if f._msufPortraitLayoutModeStamp ~= mode or f._msufPortraitLayoutHStamp ~= h then
        f._msufPortraitLayoutModeStamp = mode
        f._msufPortraitLayoutHStamp = h
        need = true
    end

    -- GUID-based gate for target/focus/boss (only re-render on unit swap)
    local doGuidGate = (unit == "target" or unit == "focus" or unit == "targettarget")
        or (unit ~= "player" and type(unit) == "string" and unit:sub(1, 4) == "boss")
    if existsForPortrait and doGuidGate then
        local guid = (F.UnitGUID and F.UnitGUID(unit)) or nil
        if guid ~= f._msufPortraitLastGuid then
            f._msufPortraitLastGuid = guid
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
            need = true
        end
    end

    if f._msufPortraitDirty then need = true end
    if not need then return end

    -- Call via GLOBAL so hooksecurefunc from PortraitDecoration.lua fires.
    -- The local call bypassed the hook, preventing decoration (offsets, borders,
    -- size override) from ever being applied on normal portrait renders.
    local fnGlobal = _G.MSUF_UpdatePortraitIfNeeded
    if fnGlobal then
        fnGlobal(f, unit, conf, existsForPortrait)
    else
        UpdatePortraitIfNeeded(f, unit, conf, existsForPortrait)
    end
    f._msufPortraitModeStamp = mode
    f._msufPortraitRenderStamp = render
end

_G.MSUF_MaybeUpdatePortrait = MaybeUpdatePortrait

-- ── SetPortraitTexture hook (boss edit mode 3D compat) ──
if type(hooksecurefunc) == "function" and type(SetPortraitTexture) == "function" then
    local function LookupConfForFrame(f)
        local db = _G.MSUF_DB
        if type(db) ~= "table" then return nil end
        if f.isBoss then return db.boss end
        local key = f.unitKey or f.msufConfigKey or f.unit
        return key and db[key] or nil
    end

    hooksecurefunc("SetPortraitTexture", function(tex, unit)
        if not tex then return end
        local f = tex.__MSUF_PortraitOwner
        if not f and tex.GetParent then
            local p = tex:GetParent()
            if p and (p.portrait == tex) then f = p; tex.__MSUF_PortraitOwner = p end
        end
        if not f then return end
        local conf = LookupConfForFrame(f)
        if not conf or conf.portraitRender ~= "3D" or not IsPortraitModeActive(conf) then return end
        local m = EnsureModel(f)
        ApplyModelLayoutIfNeeded(f, conf)
        SafeCall(m, "ClearModel")
        SafeCall(m, "SetUnit", unit)
        SafeCall(m, "SetPortraitZoom", 1)
        SafeCall(m, "SetCamDistanceScale", 1)
        SafeCall(m, "SetRotation", 0)
        SetShown(tex, false)
        SetShown(m, true)
    end)
end

-- ── Boss layout hook (keep 3D model in sync) ──
if type(hooksecurefunc) == "function" then
    hooksecurefunc("MSUF_UpdateBossPortraitLayout", function(f, conf)
        if not (f and conf) then return end
        if conf.portraitRender == "3D" and IsPortraitModeActive(conf) then
            local m = rawget(f, "portraitModel")
            if m and m.SetUnit then
                f._msufPortraitModelLayoutStamp = nil
                ApplyModelLayoutIfNeeded(f, conf)
            end
        else
            SetShown(rawget(f, "portraitModel"), false)
        end
    end)
end

-- ── Sync helpers (called from Options) ──
local function GetFramesForUnitKey(key)
    if key == "tot" then key = "targettarget" end
    if key == "boss" then
        local t = {}
        for i = 1, 5 do
            local f = _G["MSUF_boss" .. i]
            if f then t[#t + 1] = f end
        end
        return t
    end
    local f = _G["MSUF_" .. tostring(key)]
    if not f and key == "targettarget" then f = _G.MSUF_targettarget or _G.MSUF_tot end
    return f and { f } or {}
end

function _G.MSUF_3DPortraits_SyncUnit(unitKey)
    if type(unitKey) ~= "string" or unitKey == "" then return end
    local db = _G.MSUF_DB
    if not db then return end
    local conf = (unitKey == "boss") and db.boss or db[unitKey]
    if unitKey == "tot" then conf = db.targettarget or db.tot end
    if not conf then return end
    local frames = GetFramesForUnitKey(unitKey)
    for i = 1, #frames do
        local f = frames[i]
        if f then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
            if not IsPortraitModeActive(conf) then
                SetShown(f.portrait, false)
                SetShown(rawget(f, "portraitModel"), false)
            else
                UpdatePortraitIfNeeded(f, f.unit or unitKey, conf, UnitExists and UnitExists(f.unit or unitKey) or true)
            end
        end
    end
end

-- Visibility sync (called from visual apply path)
function _G.MSUF_3DPortraits_SyncVisibility(f)
    if not f then return end
    local db = _G.MSUF_DB
    local conf = db and (f.isBoss and db.boss or db[f.unitKey or f.msufConfigKey or f.unit])
    if not conf then return end
    if IsPortraitModeActive(conf) then
        if conf.portraitRender == "3D" then
            SetShown(f.portrait, false)
            SetShown(rawget(f, "portraitModel"), true)
        else
            SetShown(rawget(f, "portraitModel"), false)
        end
    else
        SetShown(f.portrait, false)
        SetShown(rawget(f, "portraitModel"), false)
    end
end

_G.MSUF_3DPortraits_ForceRefresh = function()
    local keys = { "player", "target", "focus", "pet", "targettarget" }
    for _, k in ipairs(keys) do
        local f = _G["MSUF_" .. k]
        if f then f._msufPortraitDirty = true; f._msufPortraitNextAt = 0 end
    end
    for i = 1, 5 do
        local f = _G["MSUF_boss" .. i]
        if f then f._msufPortraitDirty = true; f._msufPortraitNextAt = 0 end
    end
end

_G.MSUF_3DPortraits_Loaded = true
