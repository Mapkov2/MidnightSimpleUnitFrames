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

        -- ═══════════════════════════════════════════════════════════════
        -- Position bar with CENTER — same code path as PositionUnitFrame
        -- ═══════════════════════════════════════════════════════════════
        -- snapCX/snapCY = desired bar center in UIParent screen coords.
        -- Convert to anchor-relative offset (same math as _UpdateDBFromFrame).
        -- Then SetPoint("CENTER", anchor, "CENTER", ...) — identical to pipeline.

        local bar = d.bar
        if bar and not InCombatLockdown() then
            local anchor = d.anchor
            local conf = d.conf

            -- Compute where bar center IS in screen pixels after hypothetical move
            -- snapCX/snapCY are in UIParent coords.
            -- Bar center in screen pixels = snapCX * uiScale
            -- We need: offset = (barCenter * barScale - anchorCenter * anchorScale) / anchorScale
            -- Since we WANT barCenter at snapCX (UIParent coords), and UIParent coords = screen / uiScale:
            -- barCenter_local = snapCX * (uiScale / barScale)
            -- But simpler: just write offset then SetPoint with CENTER.

            local ax, ay = anchor:GetCenter()
            if ax and ay then
                local as = anchor:GetEffectiveScale() or 1
                local fs = bar:GetEffectiveScale() or 1
                if as == 0 then as = 1 end; if fs == 0 then fs = 1 end

                -- Desired bar center in absolute screen pixels
                local barScreenCX = snapCX * sc  -- sc = UIParent:GetEffectiveScale()
                local barScreenCY = snapCY * sc
                -- Anchor center in absolute screen pixels
                local ancScreenCX = ax * as
                local ancScreenCY = ay * as
                -- Offset in anchor's coord space
                local offX = (barScreenCX - ancScreenCX) / as
                local offY = (barScreenCY - ancScreenCY) / as

                -- Boss spacing adjustment
                if d.bossAdj then offY = offY - d.bossAdj end

                conf.offsetX = round(offX)
                conf.offsetY = round(offY)

                -- Check ECV path
                local db = _G.MSUF_DB
                local _g = db and db.general
                local ecvFn = _G.MSUF_GetEffectiveCooldownFrame
                local ecv = (type(ecvFn) == "function" and ecvFn("EssentialCooldownViewer"))
                    or _G["EssentialCooldownViewer"]
                local ecvRule = d.ecvRule

                if _g and _g.anchorToCooldown and ecv and anchor == ecv and ecvRule then
                    -- ECV path: PositionUnitFrame uses point-to-point
                    -- We wrote center-to-center offset above, need to convert for ECV
                    local point, relPoint, baseX, extraY = ecvRule[1], ecvRule[2], ecvRule[3] or 0, ecvRule[4] or 0
                    -- For ECV: gapY = offsetY, x = baseX + offsetX
                    -- PositionUnitFrame: MSUF_ApplyPoint(f, point, ecv, relPoint, baseX + offsetX, offsetY + extraY)
                    -- So we need to recompute offsetX/offsetY for ECV path
                    local ax2, ay2 = PointXY(ecv, relPoint)
                    -- Desired bar point position
                    local fx2, fy2 = PointXY(bar, point)
                    -- But bar hasn't moved yet... use target position instead
                    -- Actually, just temporarily position with CENTER, read PointXY, then fix
                    pcall(function()
                        bar._msufDragActive = false
                        bar:ClearAllPoints()
                        bar:SetPoint("CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
                    end)
                    bar._msufDragActive = true
                    -- Now read the ECV offsets
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
                    -- Normal path: CENTER-to-CENTER (same as PositionUnitFrame line 2429)
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
        -- Offsets already written by OnUpdate. Just finalize pipeline.
        if type(ApplySettingsForKey) == "function" then
            ApplySettingsForKey(d.key)
        end
        C_Timer.After(0.06, function()
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        end)
        if _G.MSUF_SyncUnitPositionPopup then _G.MSUF_SyncUnitPositionPopup() end
        if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
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
