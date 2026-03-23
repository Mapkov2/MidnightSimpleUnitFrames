-- ============================================================================
-- MSUF_EM2_Ticker.lua — v5 CENTER-native
-- During drag: computes DB offset from cursor, then positions bar with the
-- EXACT same SetPoint("CENTER", anchor, "CENTER", ...) that PositionUnitFrame
-- uses. Zero TOPLEFT. Zero conversion error. One positioning code path.
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Ticker = {}
EM2.Ticker = Ticker

local round = function(n) return n + (2^52 + 2^51) - (2^52 + 2^51) end
local abs   = math.abs
local max, min = math.max, math.min
local format = string.format

local ECV_ANCHORS = {
    player       = { "RIGHT", "LEFT",  -20,   0 },
    target       = { "LEFT",  "RIGHT",  20,   0 },
    focus        = { "TOP",   "LEFT",    0,   0 },
    targettarget = { "TOP",   "RIGHT",   0, -40 },
}

local function PointXY(fr, p)
    if not fr or not p then return nil, nil end
    if p == "CENTER" then return fr:GetCenter() end
    local l, r, t, b = fr:GetLeft(), fr:GetRight(), fr:GetTop(), fr:GetBottom()
    if not (l and r and t and b) then return nil, nil end
    local cx, cy = (l + r) * 0.5, (t + b) * 0.5
    if p == "TOPLEFT" then return l, t end
    if p == "TOP" then return cx, t end
    if p == "TOPRIGHT" then return r, t end
    if p == "LEFT" then return l, cy end
    if p == "RIGHT" then return r, cy end
    if p == "BOTTOMLEFT" then return l, b end
    if p == "BOTTOM" then return cx, b end
    if p == "BOTTOMRIGHT" then return r, b end
    return fr:GetCenter()
end

local function ResolveAnchor(key, conf)
    local anchorFn = _G.MSUF_GetAnchorFrame
    local anchor = (type(anchorFn) == "function" and anchorFn()) or UIParent
    if not conf then return anchor end
    local cn = conf.anchorFrameName
    if type(cn) == "string" and cn ~= "" then
        local ecvFn = _G.MSUF_GetEffectiveCooldownFrame
        local cf = (type(ecvFn) == "function" and cn == "EssentialCooldownViewer") and ecvFn(cn) or _G[cn]
        if cf and cf ~= UIParent and cf ~= WorldFrame then return cf end
    end
    local atv = conf.anchorToUnitframe
    if type(atv) == "string" and atv ~= "" and atv ~= "GLOBAL" and atv ~= "FREE" and atv ~= "global" then
        local uf = _G.MSUF_UnitFrames or _G.UnitFrames
        local rel = uf and uf[atv] or _G["MSUF_" .. atv]
        if rel and rel ~= UIParent and rel ~= WorldFrame then return rel end
    end
    return anchor
end

local function RectPointXY(l, r, t, b, p)
    if p == "CENTER" then return (l + r) * 0.5, (t + b) * 0.5 end
    local cx, cy = (l + r) * 0.5, (t + b) * 0.5
    if p == "TOPLEFT" then return l, t end
    if p == "TOP" then return cx, t end
    if p == "TOPRIGHT" then return r, t end
    if p == "LEFT" then return l, cy end
    if p == "RIGHT" then return r, cy end
    if p == "BOTTOMLEFT" then return l, b end
    if p == "BOTTOM" then return cx, b end
    if p == "BOTTOMRIGHT" then return r, b end
    return (l + r) * 0.5, (t + b) * 0.5
end

local function ApplyGroupDragOffsets(d, moverLeft, moverRight, moverTop, moverBottom, uiScale)
    local conf = d.conf
    local anchor = conf and conf.anchor or nil
    local point = anchor and anchor[1] or "TOPLEFT"
    local relPoint = anchor and anchor[3] or point
    local ax, ay = PointXY(d.anchor or UIParent, relPoint)
    if not (ax and ay) then return end
    local anchorScale = (d.anchor and d.anchor.GetEffectiveScale and d.anchor:GetEffectiveScale()) or 1
    if anchorScale == 0 then anchorScale = 1 end
    local fx, fy = RectPointXY(moverLeft, moverRight, moverTop, moverBottom, point)
    if not (fx and fy) then return end
    local offX = ((fx * uiScale) - (ax * anchorScale)) / anchorScale
    local offY = ((fy * uiScale) - (ay * anchorScale)) / anchorScale
    local setFn = _G.MSUF_Group_SetOffsets
    if type(setFn) == "function" then
        setFn(conf, round(offX), round(offY), d.groupDefaultY)
    else
        conf.anchor = conf.anchor or { point, nil, relPoint, 0, 0 }
        conf.anchor[4], conf.anchor[5] = round(offX), round(offY)
        conf.offsetX, conf.offsetY = conf.anchor[4], conf.anchor[5]
    end
    if d.bar and not InCombatLockdown() then
        d.bar:ClearAllPoints()
        d.bar:SetPoint(point, d.anchor or UIParent, relPoint, conf.anchor[4], conf.anchor[5])
    end
end

local tickerFrame
local activeDrag
local idleSyncAcc = 0

local function OnUpdate(self, elapsed)
    if activeDrag then
        local d = activeDrag
        local sc = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        mx = mx / sc; my = my / sc

        -- Mover center = cursor + offset
        local rawCX = mx + d.offX
        local rawCY = my + d.offY

        -- Snap
        local snapCX, snapCY = rawCX, rawCY
        if EM2.Snap and EM2.Snap.IsEnabled() then
            snapCX, snapCY = EM2.Snap.Apply(rawCX, rawCY, d.halfW, d.halfH, d.key)
        end

        -- Clamp
        snapCX = max(d.halfW, min(d.screenW - d.halfW, snapCX))
        snapCY = max(d.halfH, min(d.screenH - d.halfH, snapCY))

        -- Position mover (TOPLEFT UIParent — mover only)
        d.mover:ClearAllPoints()
        d.mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
            snapCX - d.halfW,
            snapCY + d.halfH - d.screenH)

        -- Coord display
        if d.mover._coordFS then
            d.mover._coordFS:SetText(format("%.0f, %.0f",
                round(snapCX - d.screenW * 0.5),
                round(snapCY - d.screenH * 0.5)))
        end

        local bar = d.bar
        if d.isGroup then
            local moverLeft = snapCX - d.halfW
            local moverRight = snapCX + d.halfW
            local moverTop = snapCY + d.halfH
            local moverBottom = snapCY - d.halfH
            ApplyGroupDragOffsets(d, moverLeft, moverRight, moverTop, moverBottom, sc)
        elseif bar and not InCombatLockdown() then
            local anchor = d.anchor
            local conf = d.conf
            local ax, ay = anchor:GetCenter()
            if ax and ay then
                local as = anchor:GetEffectiveScale() or 1
                local fs = bar:GetEffectiveScale() or 1
                if as == 0 then as = 1 end; if fs == 0 then fs = 1 end

                local barScreenCX = snapCX * sc
                local barScreenCY = snapCY * sc
                local ancScreenCX = ax * as
                local ancScreenCY = ay * as
                local offX = (barScreenCX - ancScreenCX) / as
                local offY = (barScreenCY - ancScreenCY) / as

                if d.bossAdj then offY = offY - d.bossAdj end

                conf.offsetX = round(offX)
                conf.offsetY = round(offY)

                local db = _G.MSUF_DB
                local _g = db and db.general
                local ecvFn = _G.MSUF_GetEffectiveCooldownFrame
                local ecv = (type(ecvFn) == "function" and ecvFn("EssentialCooldownViewer"))
                    or _G["EssentialCooldownViewer"]
                local ecvRule = d.ecvRule

                if _g and _g.anchorToCooldown and ecv and anchor == ecv and ecvRule then
                    local point, relPoint, baseX, extraY = ecvRule[1], ecvRule[2], ecvRule[3] or 0, ecvRule[4] or 0
                    local ax2, ay2 = PointXY(ecv, relPoint)
                    local fx2, fy2 = PointXY(bar, point)
                    pcall(function()
                        bar._msufDragActive = false
                        bar:ClearAllPoints()
                        bar:SetPoint("CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
                    end)
                    bar._msufDragActive = true
                    fx2, fy2 = PointXY(bar, point)
                    if ax2 and ay2 and fx2 and fy2 then
                        conf.offsetX = round((fx2 * fs - ax2 * as) / as - baseX)
                        conf.offsetY = round((fy2 * fs - ay2 * as) / as - extraY)
                    end
                    pcall(function()
                        bar:ClearAllPoints()
                        bar:SetPoint(point, ecv, relPoint, baseX + conf.offsetX, conf.offsetY + extraY)
                    end)
                else
                    pcall(function()
                        bar._msufDragActive = false
                        bar:ClearAllPoints()
                        bar:SetPoint("CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
                    end)
                    bar._msufDragActive = true
                end
            end
        end

        if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
    else
        idleSyncAcc = idleSyncAcc + elapsed
        if idleSyncAcc >= 0.2 then
            idleSyncAcc = 0
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            if EM2.HUD and EM2.HUD.RefreshControls then EM2.HUD.RefreshControls() end
        end
    end
end

function Ticker.BeginDrag(mover, key, cfg)
    local bar = cfg.getFrame and cfg.getFrame()
    if bar then bar._msufDragActive = true end

    local conf = cfg.getConf and cfg.getConf()

    local sc = UIParent:GetEffectiveScale()
    local curX, curY = GetCursorPosition()
    curX = curX / sc; curY = curY / sc

    local mL = mover:GetLeft() or 0; local mR = mover:GetRight() or 0
    local mT = mover:GetTop() or 0; local mB = mover:GetBottom() or 0
    local mCX = (mL + mR) * 0.5
    local mCY = (mT + mB) * 0.5

    local anchor = ResolveAnchor(key, conf)

    local bossAdj
    if bar and conf and key and key:sub(1,4) == "boss" and bar.unit then
        local gbi = _G.MSUF_GetBossIndexFromToken
        local idx = (type(gbi) == "function" and gbi(bar.unit)) or 1
        local spacing = conf.spacing or -36
        if conf.invertBossOrder then spacing = -spacing end
        bossAdj = (idx - 1) * spacing
    end

    activeDrag = {
        mover   = mover,
        key     = key,
        cfg     = cfg,
        bar     = bar,
        conf    = conf,
        anchor  = anchor,
        ecvRule = ECV_ANCHORS[key],
        offX    = mCX - curX,
        offY    = mCY - curY,
        startCX = mCX,
        startCY = mCY,
        halfW   = (mR - mL) * 0.5,
        halfH   = (mT - mB) * 0.5,
        screenW = UIParent:GetWidth(),
        screenH = UIParent:GetHeight(),
        bossAdj = bossAdj,
        isGroup = cfg and cfg.popupType == "group",
        groupDefaultY = (key == "group_raid") and -400 or -200,
    }
end

function Ticker.EndDrag()
    if not activeDrag then return false end
    local d = activeDrag
    activeDrag = nil

    if d.bar then d.bar._msufDragActive = false end
    if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end

    local mover = d.mover
    local mL = mover:GetLeft() or 0; local mR = mover:GetRight() or 0
    local mT = mover:GetTop() or 0; local mB = mover:GetBottom() or 0
    local cx = (mL + mR) * 0.5; local cy = (mT + mB) * 0.5
    local moved = abs(cx - d.startCX) > 0.5 or abs(cy - d.startCY) > 0.5

    if moved then
        if d.isGroup then
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
            if type(_G.MSUF_LayoutGroupFrames) == "function" then _G.MSUF_LayoutGroupFrames() end
            if type(_G.MSUF_Group_RefreshAll) == "function" then _G.MSUF_Group_RefreshAll() end
=======
=======
>>>>>>> theirs
=======
>>>>>>> theirs
            if type(_G.MSUF_Group_SyncPreview) == "function" then
                _G.MSUF_Group_SyncPreview()
            else
                if type(_G.MSUF_LayoutGroupFrames) == "function" then _G.MSUF_LayoutGroupFrames() end
                if type(_G.MSUF_Group_RefreshAll) == "function" then _G.MSUF_Group_RefreshAll() end
            end
<<<<<<< ours
<<<<<<< ours
>>>>>>> theirs
=======
>>>>>>> theirs
=======
>>>>>>> theirs
            if EM2.GroupPopup and EM2.GroupPopup.IsOpen() then EM2.GroupPopup.Sync() end
        else
            if type(ApplySettingsForKey) == "function" then
                ApplySettingsForKey(d.key)
            end
            if _G.MSUF_SyncUnitPositionPopup then _G.MSUF_SyncUnitPositionPopup() end
            if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
        end
        C_Timer.After(0.06, function()
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        end)
    end

    return moved
end

function Ticker.IsDragging() return activeDrag ~= nil end

function Ticker.Start()
    if not tickerFrame then
        tickerFrame = CreateFrame("Frame", "MSUF_EM2_TickerFrame", UIParent)
        tickerFrame:Hide()
    end
    idleSyncAcc = 0; activeDrag = nil
    tickerFrame:SetScript("OnUpdate", OnUpdate)
    tickerFrame:Show()
end

function Ticker.Stop()
    activeDrag = nil
    if tickerFrame then
        tickerFrame:SetScript("OnUpdate", nil)
        tickerFrame:Hide()
    end
end
