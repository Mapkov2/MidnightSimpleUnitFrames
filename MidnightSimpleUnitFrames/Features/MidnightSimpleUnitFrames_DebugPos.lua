-- MidnightSimpleUnitFrames_DebugPos.lua
-- Position drift debugger.  Toggle: /msufdbgpos
--
-- What it shows:
--   Chat log  — combat transitions (ECV size at entry/exit), CDMBridge events,
--               FlushCDMBridgeRefresh, Snapshot results, MarkExternalAnchorForReanchor
--   Overlay   — live ECV geometry, global anchor, per-unit stored offset + screen pos
--
-- Zero runtime cost when disabled.  All state is local to this file.

local addonName = ...

_G.MSUF_DebugPositions = false

-- ── helpers ──────────────────────────────────────────────────────────────────

local function Dbg(msg)
    if not _G.MSUF_DebugPositions then return end
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
    if not ecv then return "ECV: |cFFAAAAAAnot found|r" end
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
    if not _overlay then return end
    local l = _overlay.lines
    local ecv   = GetECV()
    local g     = MSUF_DB and MSUF_DB.general
    local uf    = UnitFrames or _G.MSUF_UnitFrames or _G.UnitFrames
    local inC   = _G.MSUF_InCombat

    l[1]:SetText("|cFFFFFF00MSUF Position Debug|r  Combat: "
        .. (inC and "|cFFFF4444IN|r" or "|cFF44FF44OUT|r"))

    local ancLabel = (g and g.anchorToCooldown)
        and "|cFFFFAA00CooldownManager|r"
        or "|cFFAAAAFF" .. tostring(g and g.anchorName or "UIParent") .. "|r"
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
    if _overlay then return end
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

-- ── toggle ───────────────────────────────────────────────────────────────────

function _G.MSUF_DebugPositions_Toggle()
    _G.MSUF_DebugPositions = not _G.MSUF_DebugPositions
    if _G.MSUF_DebugPositions then
        CreateOverlay()
        if _overlay then _overlay:Show() end
        UpdateOverlay()
        print("|cFFFF8800[MSUF]|r Position debug |cFF44FF44ON|r"
            .. "  — overlay shown, chat log active")
        print("|cFFFF8800[MSUF]|r /msufdbgpos to toggle off")
    else
        if _overlay then _overlay:Hide() end
        print("|cFFFF8800[MSUF]|r Position debug |cFFFF4444OFF|r")
    end
end

SLASH_MSUFDBGPOS1 = "/msufdbgpos"
SlashCmdList["MSUFDBGPOS"] = function()
    _G.MSUF_DebugPositions_Toggle()
end

-- ── hooks (applied after all addon files have loaded) ────────────────────────

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Combat transitions: log ECV geometry at entry and exit.
    local combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatFrame:SetScript("OnEvent", function(_, ev)
        if not _G.MSUF_DebugPositions then return end
        local prefix = ev == "PLAYER_REGEN_DISABLED"
            and "|cFFFF4444COMBAT START|r"
            or  "|cFF44FF44COMBAT END|r"
        Dbg(prefix .. "  " .. ECVLine())
    end)

    -- CDMBridge: fires every time OnSizeChanged / OnShow / OnHide decides a
    -- reanchor is needed.  With the uniform-shift fix this should ONLY fire on
    -- genuine ECV moves, not on icon-driven resizes.
    if _G.MSUF_MarkExternalAnchorForReanchor then
        local orig = _G.MSUF_MarkExternalAnchorForReanchor
        _G.MSUF_MarkExternalAnchorForReanchor = function(...)
            Dbg("CDMBridge:MarkExternalAnchorForReanchor  " .. ECVLine())
            return orig(...)
        end
    end

    -- Flush: runs out-of-combat after a reanchor was queued.
    if _G.MSUF_FlushCDMBridgeRefresh then
        local orig = _G.MSUF_FlushCDMBridgeRefresh
        _G.MSUF_FlushCDMBridgeRefresh = function(...)
            Dbg("CDMBridge:FlushCDMBridgeRefresh  " .. ECVLine())
            return orig(...)
        end
    end

    -- Snapshot: read the resulting SetPoint data from the frame after the call.
    if _G.MSUF_SnapshotFrameToUIParentCenter then
        local orig = _G.MSUF_SnapshotFrameToUIParentCenter
        _G.MSUF_SnapshotFrameToUIParentCenter = function(frame, ...)
            local result = orig(frame, ...)
            if _G.MSUF_DebugPositions and result and frame and frame.GetPoint then
                local _, _, _, px, py = frame:GetPoint(1)
                Dbg("Snapshot " .. ((frame.GetName and frame:GetName()) or "?")
                    .. " -> UIParent CENTER (" .. tostring(px) .. "," .. tostring(py) .. ")")
            end
            return result
        end
    end
end)
