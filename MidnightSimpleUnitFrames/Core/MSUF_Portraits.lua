-- Core/MSUF_Portraits.lua
-- 2D/Class portrait system.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber = type, tonumber
local PM = ns.PortraitMedia

local function SetShown(obj, shown)
    if not obj then return end
    if shown then
        if obj.Show then obj:Show() end
    else
        if obj.Hide then obj:Hide() end
    end
end

local function NormalizePortraitRender(render)
    if render == "CLASS" then return "CLASS" end
    return "2D"
end

local function IsPortraitModeActive(conf)
    if type(conf) ~= "table" then return false end
    local pm = conf.portraitMode
    return (pm == "LEFT" or pm == "RIGHT")
end

local function ApplyClassPortraitTexture(portrait, unit, conf, existsForPortrait)
    if not portrait then return end

    local u = existsForPortrait and unit or "player"
    local class = (F.UnitClassBase and F.UnitClassBase(u)) or (F.UnitClass and select(2, F.UnitClass(u)))
    local style = conf.portraitClassStyle or "BLIZZARD"
    local visual = PM and PM.ResolveClassPortrait and PM.ResolveClassPortrait(class, style) or nil

    if visual and portrait.SetTexture and portrait.SetTexCoord then
        portrait:SetTexture(visual.texture)
        portrait:SetTexCoord(visual.left or 0, visual.right or 1, visual.top or 0, visual.bottom or 1)
        return
    end

    if portrait.SetTexCoord then portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9) end
    if portrait.SetTexture then portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark") end
end

local function ApplyBossPreviewPortraitTexture(portrait, conf, render)
    if not portrait then return end

    if render == "CLASS" then
        local style = conf.portraitClassStyle or "BLIZZARD"
        local visual = PM and PM.ResolveClassPortrait and PM.ResolveClassPortrait("DEATHKNIGHT", style) or nil
        if visual and portrait.SetTexture and portrait.SetTexCoord then
            portrait:SetTexture(visual.texture)
            portrait:SetTexCoord(visual.left or 0, visual.right or 1, visual.top or 0, visual.bottom or 1)
            return
        end
    end

    if portrait.SetTexCoord then portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    if portrait.SetTexture then portrait:SetTexture("Interface\\ICONS\\Achievement_Boss_LichKing") end
end

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

local function UpdateBossPortraitLayout(f, conf)
    if not f or not f.portrait or not conf then return end
    ApplyPortraitLayout(f, conf, f.portrait)
end
_G.MSUF_UpdateBossPortraitLayout = UpdateBossPortraitLayout

local function ApplyPortraitLayoutIfNeeded(f, conf)
    if not f or not conf or not f.portrait then return end
    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    if ns.Cache.StampChanged(f, "PortraitLayout", mode, h) then
        ApplyPortraitLayout(f, conf, f.portrait)
    end
end

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

local function SchedulePortraitRetry(f, nextAt, now)
    if not f or f._msufPortraitRetryScheduled or not (C_Timer and C_Timer.After) then return end
    f._msufPortraitRetryScheduled = true
    local delay = 0
    if now and nextAt and now < nextAt then
        delay = nextAt - now
        if delay < 0 then delay = 0 end
    end
    C_Timer.After(delay, function()
        if not f then return end
        f._msufPortraitRetryScheduled = nil
        if not f._msufPortraitDirty then return end
        if ns and ns.UF and type(ns.UF.RequestUpdate) == "function" then
            ns.UF.RequestUpdate(f, false, false, "PortraitRetry")
        elseif type(_G.MSUF_QueueUnitframeUpdate) == "function" then
            _G.MSUF_QueueUnitframeUpdate(f, false)
        end
    end)
end

local function UpdatePortraitIfNeeded(f, unit, conf, existsForPortrait)
    if not f or not f.portrait or not conf then return end

    local mode = conf.portraitMode or "OFF"
    local render = NormalizePortraitRender(conf.portraitRender)
    local portrait = f.portrait

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

    if mode == "OFF" then
        SetShown(portrait, false)
        f._msufPortraitDirty = nil
        f._msufPortraitNextAt = 0
        return
    end

    local allowPreview = false
    if not existsForPortrait then
        local inCombat = (F.InCombatLockdown and F.InCombatLockdown()) and true or false
        if not inCombat and (MSUF_UnitEditModeActive or (f.isBoss and MSUF_BossTestMode)) then
            allowPreview = true
        end
    end
    if not existsForPortrait and not allowPreview then
        SetShown(portrait, false)
        f._msufPortraitDirty = nil
        f._msufPortraitNextAt = 0
        f._msufPortraitLastGuid = nil
        return
    end

    ApplyPortraitLayoutIfNeeded(f, conf)

    if f._msufPortraitDirty then
        local now = (F.GetTime and F.GetTime()) or 0
        local nextAt = tonumber(f._msufPortraitNextAt) or 0
        local bossPreview = f.isBoss and MSUF_BossTestMode and not _G.MSUF_InCombat and not existsForPortrait
        if not bossPreview then
            f._msufBossPreviewPortraitMode = nil
            f._msufBossPreviewPortraitRender = nil
            f._msufBossPreviewPortraitStyle = nil
        end
        if bossPreview or ((now >= nextAt) and not _budgetUsed) then
            if bossPreview then
                ApplyBossPreviewPortraitTexture(portrait, conf, render)
                f._msufPortraitLastGuid = nil
            elseif render == "CLASS" then
                ApplyClassPortraitTexture(portrait, unit, conf, existsForPortrait)
            else
                if portrait.SetTexCoord then portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9) end
                if existsForPortrait and SetPortraitTexture then
                    SetPortraitTexture(portrait, unit)
                elseif portrait.SetTexture then
                    portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                end
            end
            f._msufPortraitDirty = nil
            f._msufPortraitNextAt = now + PORTRAIT_MIN_INTERVAL
            if not bossPreview then
                _budgetUsed = true
                ResetBudgetNextFrame()
            end
        else
            SchedulePortraitRetry(f, nextAt, now)
            ResetBudgetNextFrame()
        end
    end
    portrait:Show()
end

_G.MSUF_UpdatePortraitIfNeeded = UpdatePortraitIfNeeded

local function MaybeUpdatePortrait(f, unit, conf, existsForPortrait)
    if not f or not f.portrait or not conf then return end

    local mode = conf.portraitMode or "OFF"
    local render = NormalizePortraitRender(conf.portraitRender)

    if mode == "OFF" and f._msufPortraitModeStamp == "OFF" and not f._msufPortraitDirty then
        SetShown(f.portrait, false)
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

    local doGuidGate = (unit == "target" or unit == "focus" or unit == "focustarget" or unit == "targettarget")
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

local function SyncPortraitUnit(unitKey)
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
            else
                UpdatePortraitIfNeeded(f, f.unit or unitKey, conf, UnitExists and UnitExists(f.unit or unitKey) or true)
            end
        end
    end
end
_G.MSUF_Portraits_SyncUnit = SyncPortraitUnit

local function SyncPortraitVisibility(f)
    if not f then return end
    local db = _G.MSUF_DB
    local conf = db and (f.isBoss and db.boss or db[f.unitKey or f.msufConfigKey or f.unit])
    if not conf then return end
    SetShown(f.portrait, IsPortraitModeActive(conf))
end
_G.MSUF_Portraits_SyncVisibility = SyncPortraitVisibility

local function ForcePortraitRefresh()
    local keys = { "player", "target", "focus", "focustarget", "pet", "targettarget" }
    for _, k in ipairs(keys) do
        local f = _G["MSUF_" .. k]
        if f then f._msufPortraitDirty = true; f._msufPortraitNextAt = 0 end
    end
    for i = 1, 5 do
        local f = _G["MSUF_boss" .. i]
        if f then f._msufPortraitDirty = true; f._msufPortraitNextAt = 0 end
    end
end
_G.MSUF_Portraits_ForceRefresh = ForcePortraitRefresh
