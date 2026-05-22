-- MSUF_GF_StatusOffline.lua - Group frame status text and offline-hide lifecycle
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown
local UnitExists = _G.UnitExists
local UnitIsConnected = _G.UnitIsConnected
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsGhost = _G.UnitIsGhost
local UnitIsAFK = _G.UnitIsAFK
local UnitIsDND = _G.UnitIsDND
local UnitHealth = _G.UnitHealth
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetTime = _G.GetTime
local math_floor = math.floor
local math_max = math.max

local function _MSUF_ScheduleDelayOnce(key, delay, fn)
    local sched = _G.MSUF_ScheduleDelayOnce
    if sched then return sched(key, delay, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(delay or 0, fn) end
    if type(fn) == "function" then return fn() end
end

local function _RuntimeEnabledForFrame(f)
    local fn = GF._RuntimeEnabledForFrame
    if type(fn) == "function" then return fn(f) end
    return f ~= nil
end
------------------------------------------------------------------------
-- Status text helpers (module-level Ã¢â‚¬â€ zero closure allocation)
------------------------------------------------------------------------
local function _GF_HideHealthText(f)
    if f.textLeftFS then f.textLeftFS:SetText(""); f.textLeftFS:Hide() end
    if f.textCenterFS then f.textCenterFS:SetText(""); f.textCenterFS:Hide() end
    if f.textRightFS then f.textRightFS:SetText(""); f.textRightFS:Hide() end
    f._msufGFCachedTL, f._msufGFCachedTC, f._msufGFCachedTR = nil, nil, nil
    if f.powerTextLeftFS then f.powerTextLeftFS:Hide() end
    if f.powerTextCenterFS then f.powerTextCenterFS:Hide() end
    if f.powerTextRightFS then f.powerTextRightFS:Hide() end
    f._msufGFCachedPTL, f._msufGFCachedPTC, f._msufGFCachedPTR = nil, nil, nil
end

local function _GF_RestoreHealthText(f, conf)
    local hpTextOn = conf.showHPText ~= false
    local tl = hpTextOn and (conf.textLeft  or "NONE") or "NONE"
    local tc = hpTextOn and (conf.textCenter or "NONE") or "NONE"
    local tr = hpTextOn and (conf.textRight or "NONE") or "NONE"
    if f.textLeftFS  and tl ~= "NONE" then f.textLeftFS:Show() end
    if f.textCenterFS and tc ~= "NONE" then f.textCenterFS:Show() end
    if f.textRightFS and tr ~= "NONE" then f.textRightFS:Show() end
    if (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(f._msufGFKind or "party", conf)) then
        local ptl = conf.powerTextLeft   or "NONE"
        local ptc = conf.powerTextCenter  or "NONE"
        local ptr = conf.powerTextRight   or "NONE"
        if f.powerTextLeftFS  and ptl ~= "NONE" then f.powerTextLeftFS:Show() end
        if f.powerTextCenterFS and ptc ~= "NONE" then f.powerTextCenterFS:Show() end
        if f.powerTextRightFS and ptr ~= "NONE" then f.powerTextRightFS:Show() end
    end
end

------------------------------------------------------------------------
-- Status text: AFK / DND (red, GF-owned pipeline)
-- Status state encoding: 0=normal, 1=offline, 2=dead, 3=ghost, 4=afk, 5=dnd
------------------------------------------------------------------------
function GF.GetStatusIndicatorFlags()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local db = gen and gen.statusIndicators
    if type(db) ~= "table" then
        local getDB = _G.MSUF_GetStatusIndicatorDB
        db = (type(getDB) == "function") and getDB() or nil
    end
    if type(db) ~= "table" then
        return false, false, true, true
    end
    return db.showAFK == true, db.showDND == true, db.showDead == true, db.showGhost == true
end

local STATUS_TEXT_LAYOUTS = {
    [1] = { enKey = "statusText",      sizeKey = "statusTextSize",      anchorKey = "statusTextAnchor",      xKey = "statusOffsetX",      yKey = "statusOffsetY",      layerKey = "statusTextLayer",      defAnchor = "CENTER", defSize = 14, defLayer = 7 },
    [2] = { enKey = "statusText",      sizeKey = "statusTextSize",      anchorKey = "statusTextAnchor",      xKey = "statusOffsetX",      yKey = "statusOffsetY",      layerKey = "statusTextLayer",      defAnchor = "CENTER", defSize = 14, defLayer = 7 },
    [3] = { enKey = "statusGhostText", sizeKey = "statusGhostTextSize", anchorKey = "statusGhostTextAnchor", xKey = "statusGhostOffsetX", yKey = "statusGhostOffsetY", layerKey = "statusGhostTextLayer", defAnchor = "CENTER", defSize = 14, defLayer = 7 },
    [4] = { enKey = "statusAFKText",   sizeKey = "statusAFKTextSize",   anchorKey = "statusAFKTextAnchor",   xKey = "statusAFKOffsetX",   yKey = "statusAFKOffsetY",   layerKey = "statusAFKTextLayer",   defAnchor = "CENTER", defSize = 14, defLayer = 7 },
    [5] = { enKey = "statusAFKText",   sizeKey = "statusAFKTextSize",   anchorKey = "statusAFKTextAnchor",   xKey = "statusAFKOffsetX",   yKey = "statusAFKOffsetY",   layerKey = "statusAFKTextLayer",   defAnchor = "CENTER", defSize = 14, defLayer = 7 },
}

function GF.EnsureStatusTextLayer(f, conf, state)
    local s = STATUS_TEXT_LAYOUTS[state]
    local layer = tonumber(s and conf and conf[s.layerKey]) or (s and s.defLayer) or 7
    if layer < 0 then layer = 0 elseif layer > 30 then layer = 30 end

    local st = f and (f._msufGFStatusText or f.statusIndicatorText)
    if not st then return nil, layer end

    local parent = f.barGroup or f.health or f
    local layerFrame = f.statusTextLayer
    if not layerFrame and _G.CreateFrame and not (InCombatLockdown and InCombatLockdown()) then
        layerFrame = _G.CreateFrame("Frame", nil, parent)
        layerFrame:EnableMouse(false)
        if layerFrame.SetClipsChildren then layerFrame:SetClipsChildren(false) end
        f.statusTextLayer = layerFrame
    end

    if layerFrame then
        if layerFrame.GetParent and layerFrame:GetParent() ~= parent
            and layerFrame.SetParent and not (InCombatLockdown and InCombatLockdown())
        then
            layerFrame:SetParent(parent)
        end
        if layerFrame.ClearAllPoints then
            layerFrame:ClearAllPoints()
            layerFrame:SetAllPoints(parent)
        end
        if layerFrame.SetFrameLevel then
            if GF.SetFrameLayerLevel then
                GF.SetFrameLayerLevel(layerFrame, f, layer, 7)
            else
                local base = f.health or f.barGroup or f
                local baseLvl = base.GetFrameLevel and base:GetFrameLevel() or 0
                layerFrame:SetFrameLevel(baseLvl + layer)
            end
        end
        if st.SetParent and st.GetParent and st:GetParent() ~= layerFrame then
            st:SetParent(layerFrame)
        end
    end

    return layerFrame, layer
end

local function IsStatusTextStateEnabled(conf, state)
    local s = STATUS_TEXT_LAYOUTS[state]
    return s and conf and conf[s.enKey] ~= false
end

local function JustifyForStatusAnchor(anchor)
    if anchor == "TOPLEFT" or anchor == "BOTTOMLEFT" or anchor == "LEFT" then
        return "LEFT"
    end
    if anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" or anchor == "RIGHT" then
        return "RIGHT"
    end
    return "CENTER"
end

local function ApplyStatusTextStateLayout(f, conf, state)
    local st = f and (f._msufGFStatusText or f.statusIndicatorText)
    local s = STATUS_TEXT_LAYOUTS[state]
    if not (st and conf and s) then return end
    local _, frameLayer = GF.EnsureStatusTextLayer(f, conf, state)

    local kind = f._msufGFKind or "party"
    local fScale = conf._resolvedFrameScale or 1
    local size = tonumber(conf[s.sizeKey]) or s.defSize
    if fScale ~= 1 then
        size = math_max(6, math_floor(size * fScale + 0.5))
    else
        size = math_floor(size + 0.5)
    end
    local fontPath = GF.ResolveFontPath and GF.ResolveFontPath(kind)
    local fontFlags = GF.ResolveFontFlags and GF.ResolveFontFlags(kind)
    if fontPath and st.SetFont then
        local db = _G.MSUF_DB
        local fontKey = db and db.general and db.general.fontKey
        if type(_G.MSUF_SetFontSafe) == "function" then
            _G.MSUF_SetFontSafe(st, fontPath, size, fontFlags or "", fontKey)
        else
            st:SetFont(fontPath, size, fontFlags or "")
        end
    end

    local anchor = conf[s.anchorKey] or s.defAnchor
    local ox = tonumber(conf[s.xKey]) or 0
    local oy = tonumber(conf[s.yKey]) or 0
    if fScale ~= 1 and GF.ScaleValue then
        ox = GF.ScaleValue(ox, fScale)
        oy = GF.ScaleValue(oy, fScale)
    end

    local parent = f.health or f.barGroup or f
    st:ClearAllPoints()
    st:SetPoint(anchor, parent, anchor, ox, oy)
    if st.SetJustifyH then st:SetJustifyH(JustifyForStatusAnchor(anchor)) end
    if st.SetJustifyV then st:SetJustifyV("MIDDLE") end
    if st.SetDrawLayer then
        local sub = frameLayer or s.defLayer
        if sub < 0 then sub = 0 elseif sub > 7 then sub = 7 end
        st:SetDrawLayer("OVERLAY", sub)
    end
end
GF.ApplyStatusTextStateLayout = ApplyStatusTextStateLayout

function GF.ShouldHideNameForStatusState(f, conf, state)
    if state ~= 1 and state ~= 2 and state ~= 3 then return false end
    local c = f and f._c
    if c then return c.hideNameOnDeadOffline == true end
    return conf and conf.hideNameOnDeadOffline == true
end

function GF.ApplyNameStatusVisibility(f, conf, state)
    if not (f and f.nameText) then return end
    local hideName = GF.ShouldHideNameForStatusState(f, conf, state)
    f._msufGFNameHiddenForStatus = hideName or nil
    if GF.ShouldShowNameText and GF.ShouldShowNameText(f, conf) then
        f.nameText:Show()
    else
        f.nameText:Hide()
    end
end

local function UpdateStatusText(f, unit, forceAway)
    local st = f._msufGFStatusText or f.statusIndicatorText
    if not st then return end

    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local c = f._c
    if c and not c.statusTextEn then
        if f._msufGFStatusState ~= 0 then
            f._msufGFStatusState = 0
            f._msufGFStatusLayoutState = nil
            st:SetText("")
            st:Hide()
            _GF_RestoreHealthText(f, conf)
            GF.ApplyNameStatusVisibility(f, conf, 0)
        end
        return
    end
    local showAFK, showDND, showDead, showGhost
    local deadTextEnabled, ghostTextEnabled, awayTextEnabled
    if c then
        showAFK, showDND = c.statusShowAFK, c.statusShowDND
        showDead, showGhost = c.statusShowDead, c.statusShowGhost
        deadTextEnabled = c.statusDeadTextEn
        ghostTextEnabled = c.statusGhostTextEn
        awayTextEnabled = c.statusAwayTextEn
    else
        showAFK, showDND, showDead, showGhost = GF.GetStatusIndicatorFlags()
        deadTextEnabled = IsStatusTextStateEnabled(conf, 2)
        ghostTextEnabled = IsStatusTextStateEnabled(conf, 3)
        awayTextEnabled = IsStatusTextStateEnabled(conf, 4)
    end

    if not unit or not UnitExists(unit) then
        if f._msufGFStatusState ~= 0 then
            f._msufGFStatusState = 0
            f._msufGFStatusLayoutState = nil
            st:SetText("")
            st:Hide()
            _GF_RestoreHealthText(f, conf)
            GF.ApplyNameStatusVisibility(f, conf, 0)
        end
        return
    end

    -- Determine new status state
    local newState = 0
    local connected = UnitIsConnected(unit)
    if issecretvalue and issecretvalue(connected) then connected = true end

    if connected == false and showDead and deadTextEnabled then
        newState = 1
    else
        -- Secret-safe (12.0): UnitIsDeadOrGhost can return secret booleans for
        -- non-self units. Prefer the more specific APIs and use HP==0 as a
        -- final non-secret fallback so dead group members do not look alive
        -- after both players are dead and range data starts updating again.
        local ghost = false
        if UnitIsGhost then
            local g = UnitIsGhost(unit)
            if not (issecretvalue and issecretvalue(g)) and g then ghost = true end
        end

        local isDead = false
        local unitIsDead = _G.UnitIsDead
        if unitIsDead then
            local d = unitIsDead(unit)
            if not (issecretvalue and issecretvalue(d)) and d then isDead = true end
        end
        if not isDead and UnitIsDeadOrGhost then
            local dog = UnitIsDeadOrGhost(unit)
            if not (issecretvalue and issecretvalue(dog)) and dog then isDead = true end
        end
        if not isDead and UnitHealth then
            local hp = UnitHealth(unit)
            if not (issecretvalue and issecretvalue(hp)) and hp == 0 then isDead = true end
        end

        if ghost then
            if showGhost and ghostTextEnabled then
                newState = 3
            elseif not showGhost and showDead and deadTextEnabled then
                newState = 2
            end
        elseif isDead and showDead and deadTextEnabled then
            newState = 2
        else
            if awayTextEnabled and (showAFK or showDND) then
                local getAway = _G.MSUF_GetCachedAwayStatus
                if getAway then
                    local force = forceAway == true
                    local rev = ns and ns._msufAwayRevision or 0
                    local away
                    if not force
                        and f._msufGFAwayStatusUnit == unit
                        and f._msufGFAwayStatusRev == rev
                        and f._msufGFAwayStatusAFK == showAFK
                        and f._msufGFAwayStatusDND == showDND
                    then
                        away = f._msufGFAwayStatusFlags or 0
                    end
                    if away == nil then
                        away = getAway(unit, showAFK, showDND, force)
                        f._msufGFAwayStatusUnit = unit
                        f._msufGFAwayStatusRev = rev
                        f._msufGFAwayStatusAFK = showAFK
                        f._msufGFAwayStatusDND = showDND
                        f._msufGFAwayStatusFlags = away or 0
                    end
                    if showAFK and (away == 1 or away == 3) then
                        newState = 4
                    elseif showDND and (away == 2 or away == 3) then
                        newState = 5
                    end
                else
                    if showAFK and UnitIsAFK then
                        local afk = UnitIsAFK(unit)
                        if not (issecretvalue and issecretvalue(afk)) and afk == true then
                            newState = 4
                        end
                    end
                    if newState == 0 and showDND and UnitIsDND then
                        local dnd = UnitIsDND(unit)
                        if not (issecretvalue and issecretvalue(dnd)) and dnd == true then
                            newState = 5
                        end
                    end
                end
            end
        end
    end

    if newState ~= 0 and f._msufGFStatusLayoutState ~= newState then
        ApplyStatusTextStateLayout(f, conf, newState)
        f._msufGFStatusLayoutState = newState
    end

    -- Diff-gate: only update text/colors when state actually changes
    if newState == f._msufGFStatusState then
        GF.ApplyNameStatusVisibility(f, conf, newState)
        return
    end
    f._msufGFStatusState = newState

    if newState == 0 then
        f._msufGFStatusLayoutState = nil
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(false) end
        st:SetText("")
        st:Hide()
        _GF_RestoreHealthText(f, conf)
    elseif newState == 1 then
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(true) end
        st:SetText("OFFLINE")
        st:SetTextColor(0.6, 0.6, 0.6, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 2 then
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(true) end
        st:SetText("DEAD")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 3 then
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(true) end
        st:SetText("GHOST")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 4 then
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(false) end
        st:SetText("AFK")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 5 then
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(false) end
        st:SetText("DND")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        _GF_HideHealthText(f)
    end
    GF.ApplyNameStatusVisibility(f, conf, newState)
end
GF.UpdateStatusText = UpdateStatusText

------------------------------------------------------------------------
-- Offline box hiding
-- hideOfflineEnabled gates the feature completely. When enabled, keep the
-- normal offline state visible for N seconds, then hide the visual box until
-- the unit reconnects. The secure click button remains owned by
-- SecureGroupHeader; only non-secure visual children are hidden.
------------------------------------------------------------------------
do
local function _GF_BumpOfflineToken(f)
    local token = (f._msufGFOfflineHideToken or 0) + 1
    f._msufGFOfflineHideToken = token
    return token
end

local function _GF_CancelOfflineHideTimer(f)
    local timer = f and f._msufGFOfflineHideTimer
    if timer and timer.Cancel then
        timer:Cancel()
    end
    if f then
        f._msufGFOfflineHideTimer = nil
        f._msufGFOfflineHideDueAt = nil
    end
end

local function _GF_SetOfflineHidden(f, hidden)
    if not f then return end
    hidden = hidden and true or false
    if f._msufGFOfflineHidden == hidden then return end
    f._msufGFOfflineHidden = hidden or nil

    if hidden then
        GF._offlineHideRuntimeActive = true
        if f.barGroup then f.barGroup:Hide() end
        if f._msufGFHoverBorder then f._msufGFHoverBorder:Hide() end
        if f._msufGFHighlightBorders then
            for _, border in pairs(f._msufGFHighlightBorders) do
                if border then border:Hide() end
            end
        elseif f._msufGFHighlightBorder then
            f._msufGFHighlightBorder:Hide()
        end
        if f._msufGFDispelOverlays then
            for _, overlay in pairs(f._msufGFDispelOverlays) do
                if overlay then overlay:Hide() end
            end
        elseif f._msufGFDispelOverlay then
            f._msufGFDispelOverlay:Hide()
        end
        if f._msufGFDebuffStripe then f._msufGFDebuffStripe:Hide() end
        if GF.HideFrameAuras then GF.HideFrameAuras(f) end
        if GF.HideSpellIndicators then GF.HideSpellIndicators(f) end
        if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
    else
        if f.barGroup then f.barGroup:Show() end
    end
end

local function _GF_ClearOfflineHiddenFrame(f)
    if not f then return end
    if not f._msufGFOfflineHidden and not f._msufGFOfflineKey
        and not f._msufGFOfflineSince and not f._msufGFOfflineHideDueAt
        and not f._msufGFOfflineHideTimer
    then
        return
    end
    _GF_CancelOfflineHideTimer(f)
    _GF_BumpOfflineToken(f)
    f._msufGFOfflineKey = nil
    f._msufGFOfflineSince = nil
    f._msufGFOfflineHideDueAt = nil
    _GF_SetOfflineHidden(f, false)
    if GF.RefreshOfflineHideRuntimeFlag then GF.RefreshOfflineHideRuntimeFlag() end
end

local function _GF_GetOfflineDelay(f, kind)
    local c = f and f._c
    local delay = c and c.hideOfflineDelay
    if delay == nil and GF.GetConf then
        local conf = GF.GetConf(kind or (f and f._msufGFKind) or "party")
        delay = (conf and conf.hideOfflineEnabled == true) and conf.hideOfflineDelay or 0
    end
    delay = tonumber(delay) or 0
    if delay < 0 then delay = 0 elseif delay > 120 then delay = 120 end
    return delay
end

local function _GF_CanRunOfflineHideNow(f, kind)
    if f and not _RuntimeEnabledForFrame(f) then return false end
    if not (InCombatLockdown and InCombatLockdown()) then return true end
    local c = f and f._c
    if c then return c.hideOfflineCombat == true end
    if GF.GetConf then
        local conf = GF.GetConf(kind or (f and f._msufGFKind) or "party")
        return conf and conf.hideOfflineEnabled == true and conf.hideOfflineInCombat == true or false
    end
    return false
end

local function _GF_ScheduleOfflineHide(f, unit, dueAt, remaining)
    if not (f and dueAt) then return end
    if not _GF_CanRunOfflineHideNow(f) then return end
    if f._msufGFOfflineHideDueAt == dueAt then return end
    _GF_CancelOfflineHideTimer(f)
    local token = _GF_BumpOfflineToken(f)
    f._msufGFOfflineHideDueAt = dueAt
    remaining = tonumber(remaining) or 0
    if remaining < 0 then remaining = 0 end
    local function run()
        if not f or f._msufGFOfflineHideToken ~= token then return end
        f._msufGFOfflineHideTimer = nil
        if not _GF_CanRunOfflineHideNow(f) then return end
        if GF.UpdateOfflineHiddenFrame then GF.UpdateOfflineHiddenFrame(f, f.unit or unit, true) end
    end
    if C_Timer and C_Timer.NewTimer then
        GF._offlineHideRuntimeActive = true
        f._msufGFOfflineHideTimer = C_Timer.NewTimer(remaining, run)
    else
        GF._offlineHideRuntimeActive = true
        _MSUF_ScheduleDelayOnce("GF_OFFLINE_HIDE:" .. tostring(f) .. ":" .. tostring(token), remaining, run)
    end
end

function GF.UpdateOfflineHiddenFrame(f, unit, force)
    if not f then return false end
    if not _RuntimeEnabledForFrame(f) then
        _GF_ClearOfflineHiddenFrame(f)
        return false
    end
    local kind = f._msufGFKind or "party"
    if not _GF_CanRunOfflineHideNow(f, kind) then return false end
    if f._msufGFPreviewActive then
        _GF_ClearOfflineHiddenFrame(f)
        return false
    end

    unit = unit or f.unit
    local delay = _GF_GetOfflineDelay(f, kind)
    if delay <= 0 or not unit or not UnitExists(unit) then
        _GF_ClearOfflineHiddenFrame(f)
        return false
    end

    local connected = UnitIsConnected and UnitIsConnected(unit)
    if issecretvalue and connected ~= nil and issecretvalue(connected) then connected = true end
    if connected ~= false then
        _GF_ClearOfflineHiddenFrame(f)
        return false
    end

    local guidFn = _G.UnitGUID
    local key = unit
    if guidFn then
        local guid = guidFn(unit)
        if guid and not (issecretvalue and issecretvalue(guid)) then key = guid end
    end

    local now = (GetTime and GetTime()) or 0
    if f._msufGFOfflineKey ~= key then
        _GF_BumpOfflineToken(f)
        f._msufGFOfflineKey = key
        f._msufGFOfflineSince = now
        f._msufGFOfflineHideDueAt = nil
        _GF_SetOfflineHidden(f, false)
    elseif not f._msufGFOfflineSince then
        f._msufGFOfflineSince = now
    end

    local dueAt = (f._msufGFOfflineSince or now) + delay
    if force == true or now >= dueAt then
        f._msufGFOfflineHideDueAt = dueAt
        _GF_SetOfflineHidden(f, true)
        return true
    end

    _GF_SetOfflineHidden(f, false)
    _GF_ScheduleOfflineHide(f, unit, dueAt, dueAt - now)
    return false
end

GF.ResetOfflineHiddenFrame = _GF_ClearOfflineHiddenFrame

function GF.RefreshOfflineHideEnabledFlag()
    if not GF.GetConf then
        GF._offlineHideAnyEnabled = false
        return false
    end
    local party = GF.GetConf("party")
    local raid = GF.GetConf("raid")
    local mythic = GF.GetConf("mythicraid")
    local enabled = (party and party.enabled == true and party.hideOfflineEnabled == true)
        or (raid and raid.enabled == true and raid.hideOfflineEnabled == true)
        or (mythic and mythic.enabled == true and mythic.hideOfflineEnabled == true)
    GF._offlineHideCombatAnyEnabled = ((party and party.enabled == true and party.hideOfflineEnabled == true and party.hideOfflineInCombat == true)
        or (raid and raid.enabled == true and raid.hideOfflineEnabled == true and raid.hideOfflineInCombat == true)
        or (mythic and mythic.enabled == true and mythic.hideOfflineEnabled == true and mythic.hideOfflineInCombat == true)) or false
    GF._offlineHideAnyEnabled = enabled or false
    return GF._offlineHideAnyEnabled
end

local function _GF_ForEachOfflineFrame(fn)
    if type(fn) ~= "function" then return end
    local list = GF.frameList
    if list then
        for i = 1, #list do
            local f = list[i]
            if f and _RuntimeEnabledForFrame(f) then fn(f) end
        end
    elseif GF.frames then
        for f in pairs(GF.frames) do
            if _RuntimeEnabledForFrame(f) then fn(f) end
        end
    end
end

function GF.RefreshOfflineHideRuntimeFlag()
    local active = false
    _GF_ForEachOfflineFrame(function(f)
        if f and (f._msufGFOfflineHidden or f._msufGFOfflineHideTimer or f._msufGFOfflineHideDueAt) then
            active = true
        end
    end)
    GF._offlineHideRuntimeActive = active or nil
    return active
end

function GF.SuspendOfflineHideForCombat()
    if not GF._offlineHideRuntimeActive then return end
    _GF_ForEachOfflineFrame(function(f)
        if f and not f._msufGFOfflineCombatAllowed
            and (f._msufGFOfflineConfigured or f._msufGFOfflineHidden or f._msufGFOfflineHideTimer)
        then
            _GF_CancelOfflineHideTimer(f)
            _GF_BumpOfflineToken(f)
            _GF_SetOfflineHidden(f, false)
            f._msufGFOfflineActive = nil
        end
    end)
    if GF.RefreshOfflineHideRuntimeFlag then GF.RefreshOfflineHideRuntimeFlag() end
end

function GF.RefreshOfflineHiddenFrames()
    if InCombatLockdown and InCombatLockdown() then return end
    if not (GF.RefreshOfflineHideEnabledFlag and GF.RefreshOfflineHideEnabledFlag()) then return end
    _GF_ForEachOfflineFrame(function(f)
        if f and f.unit and UnitExists(f.unit) then
            if GF.BuildFrameCache then GF.BuildFrameCache(f) end
            if f._msufGFOfflineActive and GF.UpdateOfflineHiddenFrame then
                GF.UpdateOfflineHiddenFrame(f, f.unit)
            end
        end
    end)
end
end

