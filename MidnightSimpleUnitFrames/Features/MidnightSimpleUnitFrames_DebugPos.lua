-- MidnightSimpleUnitFrames_DebugPos.lua
-- Position drift debugger.  Toggle: /msufdbgpos
--
-- ZERO overhead guarantee when OFF:
--   • No function wrappers installed (originals restored on toggle-off)
--   • No event listeners active (combat frame unregistered on toggle-off)
--   • Overlay ticker cancelled on toggle-off
--
-- Hooks are installed lazily on first toggle-on; no PLAYER_LOGIN frame needed.

_G.MSUF_DebugPositions = false

-- ── helpers ──────────────────────────────────────────────────────────────────

local function Dbg(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[MSUF-POS]|r " .. tostring(msg))
    end
end
_G.MSUF_DbgPos = Dbg

local function Fmt(n)
    return type(n) == "number" and string.format("%.1f", n) or tostring(n)
end

local function GetECV()
    return (type(_G.MSUF_GetEffectiveCooldownFrame) == "function"
        and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer"))
        or _G["EssentialCooldownViewer"]
end

local function ECVLine()
    local ecv = GetECV()
    if not ecv then return "ECV:nil" end
    local el = ecv.GetLeft   and ecv:GetLeft()
    local er = ecv.GetRight  and ecv:GetRight()
    local et = ecv.GetTop    and ecv:GetTop()
    local eb = ecv.GetBottom and ecv:GetBottom()
    local ew = (type(el) == "number" and type(er) == "number") and (er - el) or nil
    local eh = (type(et) == "number" and type(eb) == "number") and (et - eb) or nil
    return "ECV=" .. Fmt(ew) .. "x" .. Fmt(eh)
        .. "  L=" .. Fmt(el) .. " T=" .. Fmt(et)
        .. " R=" .. Fmt(er) .. " B=" .. Fmt(eb)
end

-- ── overlay ──────────────────────────────────────────────────────────────────

local _overlay

local function UpdateOverlay()
    -- guard: ticker calls this even after cancel on slow machines; bail instantly
    if not _G.MSUF_DebugPositions then return end
    if not _overlay then return end
    local l   = _overlay.lines
    local ecv = GetECV()
    local g   = MSUF_DB and MSUF_DB.general
    local uf  = UnitFrames or _G.MSUF_UnitFrames or _G.UnitFrames

    l[1]:SetText("|cFFFFFF00MSUF Position Debug|r  Combat: "
        .. (_G.MSUF_InCombat and "|cFFFF4444IN|r" or "|cFF44FF44OUT|r"))

    local ancLabel = (g and g.anchorToCooldown)
        and "|cFFFFAA00CooldownManager|r"
        or  "|cFFAAAAFF" .. tostring(g and g.anchorName or "UIParent") .. "|r"
    l[2]:SetText("Global anchor: " .. ancLabel)

    if ecv then
        local el = ecv.GetLeft   and ecv:GetLeft()
        local er = ecv.GetRight  and ecv:GetRight()
        local et = ecv.GetTop    and ecv:GetTop()
        local eb = ecv.GetBottom and ecv:GetBottom()
        local ew = (type(el)=="number" and type(er)=="number") and (er-el) or nil
        local eh = (type(et)=="number" and type(eb)=="number") and (et-eb) or nil
        l[3]:SetText("ECV: " .. Fmt(ew) .. "x" .. Fmt(eh)
            .. "  L=" .. Fmt(el) .. " T=" .. Fmt(et)
            .. " R=" .. Fmt(er) .. " B=" .. Fmt(eb))
    else
        l[3]:SetText("ECV: |cFFAAAAAAnot found|r")
    end

    local units = { "player", "target", "focus", "targettarget", "pet", "boss1" }
    for i, unit in ipairs(units) do
        local frame = uf and uf[unit]
        local li = l[3 + i]
        if frame then
            local cx, cy = frame:GetCenter()
            local conf = MSUF_DB and MSUF_DB[frame.msufConfigKey or unit]
            local ox = conf and conf.offsetX or "?"
            local oy = conf and conf.offsetY or "?"
            local snapAnchor = "UIParent"
            if frame._msufStableExternalAnchor then
                snapAnchor = (frame._msufStableExternalAnchor.GetName
                    and frame._msufStableExternalAnchor:GetName()) or "ext"
            end
            li:SetText("|cFFAAFFAA" .. unit .. "|r"
                .. "  stored=(" .. tostring(ox) .. "," .. tostring(oy) .. ")"
                .. "  screen=(" .. Fmt(cx) .. "," .. Fmt(cy) .. ")"
                .. "  snap=" .. snapAnchor)
        else
            li:SetText("|cFFAAAAAA" .. unit .. ": no frame|r")
        end
    end
end
_G.MSUF_DbgPos_UpdateOverlay = UpdateOverlay

local function CreateOverlay()
    if _overlay then
        if not _overlay._ticker and C_Timer and C_Timer.NewTicker then
            _overlay._ticker = C_Timer.NewTicker(0.5, UpdateOverlay)
        end
        return
    end
    local f = CreateFrame("Frame", "MSUF_DebugPosOverlay", UIParent)
    f:SetSize(490, 165)
    f:SetPoint("TOP", UIParent, "TOP", 0, -80)
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.82)
    local lines = {}
    for i = 1, 9 do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 17)
        fs:SetJustifyH("LEFT")
        fs:SetWidth(478)
        lines[i] = fs
    end
    f.lines = lines
    _overlay = f
    if C_Timer and C_Timer.NewTicker then
        f._ticker = C_Timer.NewTicker(0.5, UpdateOverlay)
    end
end

local function CancelOverlayTicker()
    if _overlay and _overlay._ticker then
        _overlay._ticker:Cancel()
        _overlay._ticker = nil
    end
end

-- ── hooks (installed on demand, removed when debug turns off) ─────────────────

local _hooksInstalled = false
local _origMark, _origFlush, _origSnapshot
local _combatFrame

local function InstallHooks()
    if _hooksInstalled then return end
    _hooksInstalled = true

    -- Combat transitions: log ECV geometry at entry/exit
    if not _combatFrame then
        _combatFrame = CreateFrame("Frame")
    end
    _combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    _combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _combatFrame:SetScript("OnEvent", function(_, ev)
        local prefix = ev == "PLAYER_REGEN_DISABLED"
            and "|cFFFF4444COMBAT START|r"
            or  "|cFF44FF44COMBAT END|r"
        Dbg(prefix .. "  " .. ECVLine())
    end)

    -- CDMBridge: fires when size/show/point hooks detect a genuine anchor move or first usable anchor
    _origMark = _G.MSUF_MarkExternalAnchorForReanchor
    if _origMark then
        _G.MSUF_MarkExternalAnchorForReanchor = function(...)
            Dbg("CDMBridge:MarkExternalAnchorForReanchor  " .. ECVLine())
            return _origMark(...)
        end
    end

    -- Flush: runs out-of-combat after a reanchor was queued
    _origFlush = _G.MSUF_FlushCDMBridgeRefresh
    if _origFlush then
        _G.MSUF_FlushCDMBridgeRefresh = function(...)
            Dbg("CDMBridge:FlushCDMBridgeRefresh  " .. ECVLine())
            return _origFlush(...)
        end
    end

    -- Snapshot: read resulting SetPoint data after the call
    _origSnapshot = _G.MSUF_SnapshotFrameToUIParentCenter
    if _origSnapshot then
        _G.MSUF_SnapshotFrameToUIParentCenter = function(frame, ...)
            local result = _origSnapshot(frame, ...)
            if result and frame and frame.GetPoint then
                local _, _, _, px, py = frame:GetPoint(1)
                Dbg("Snapshot " .. ((frame.GetName and frame:GetName()) or "?")
                    .. " -> UIParent CENTER (" .. tostring(px) .. "," .. tostring(py) .. ")")
            end
            return result
        end
    end
end

local function RemoveHooks()
    if not _hooksInstalled then return end
    _hooksInstalled = false

    if _combatFrame then
        _combatFrame:UnregisterAllEvents()
    end

    if _origMark     then _G.MSUF_MarkExternalAnchorForReanchor    = _origMark     ; _origMark     = nil end
    if _origFlush    then _G.MSUF_FlushCDMBridgeRefresh            = _origFlush    ; _origFlush    = nil end
    if _origSnapshot then _G.MSUF_SnapshotFrameToUIParentCenter    = _origSnapshot ; _origSnapshot = nil end
end

-- ── toggle ───────────────────────────────────────────────────────────────────

function _G.MSUF_DebugPositions_Toggle()
    _G.MSUF_DebugPositions = not _G.MSUF_DebugPositions
    if _G.MSUF_DebugPositions then
        InstallHooks()
        CreateOverlay()
        if _overlay then _overlay:Show() end
        UpdateOverlay()
        print("|cFFFF8800[MSUF]|r Position debug |cFF44FF44ON|r"
            .. "  — overlay shown, chat log active")
        print("|cFFFF8800[MSUF]|r /msufdbgpos to toggle off")
    else
        RemoveHooks()
        CancelOverlayTicker()
        if _overlay then _overlay:Hide() end
        print("|cFFFF8800[MSUF]|r Position debug |cFFFF4444OFF|r")
    end
end

SLASH_MSUFDBGPOS1 = "/msufdbgpos"
SlashCmdList["MSUFDBGPOS"] = function()
    _G.MSUF_DebugPositions_Toggle()
end
