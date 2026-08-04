--- MidnightSimpleUnitFrames_DebugPos.lua
--- Position drift debugger. Toggle: /msufdbgpos
---
--- ZERO overhead guarantee when OFF:
--- • No function wrappers installed (originals restored on toggle-off)
--- • No event listeners active (combat frame unregistered on toggle-off)
--- • Overlay OnUpdate disabled on toggle-off
---
--- Hooks are installed lazily on first toggle-on; no PLAYER_LOGIN frame needed.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

ExportPublic("MSUF_DebugPositions", false)

-- SetOnUpdateMode takes an Enum.OnUpdateMode value, not a name; a string argument leaves the
-- overlay's OnUpdate disabled.
local ONUPDATE_MODE_DISABLED = (_G.Enum and _G.Enum.OnUpdateMode and _G.Enum.OnUpdateMode.Disabled) or 0
local ONUPDATE_MODE_RUN_WHEN_VISIBLE = (_G.Enum and _G.Enum.OnUpdateMode and _G.Enum.OnUpdateMode.RunWhenVisible) or 1

--- ── helpers ──────────────────────────────────────────────────────────────────

local function Dbg(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[MSUF-POS]|r " .. tostring(msg))
    end
end
ExportPublic("MSUF_DbgPos", Dbg)

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

--- ── overlay ──────────────────────────────────────────────────────────────────

local _overlay

local function UpdateOverlay()
    --- guard: scheduled debug updates can run after toggle-off; bail instantly
    if not _G.MSUF_DebugPositions then return end
    if not _overlay then return end
    local l   = _overlay.lines
    local ecv = GetECV()
    local g   = MSUF_DB and MSUF_DB.general
    local UF = MSUF and MSUF.UF
    local frames = UF and UF.frames

    l[1]:SetText("|cFFFFFF00MSUF Position Debug|r  Combat: "
        .. (_G.MSUF_InCombat and "|cFFFF4444IN|r" or "|cFF44FF44OUT|r"))

    local providerGetter = _G.MSUF_GetAutomaticCooldownAnchorProvider
    local automaticProvider
    if type(providerGetter) == "function" then
        local _, providerLabel = providerGetter()
        automaticProvider = providerLabel
    end
    local enabledGetter = _G.MSUF_IsCooldownAnchorEnabled
    local cooldownEnabled = type(enabledGetter) == "function"
        and enabledGetter(g) == true
        or g and g.anchorToCooldown == true
    local ancLabel = cooldownEnabled
        and ("|cFFFFAA00CooldownManager%s|r"):format(automaticProvider and (" (" .. automaticProvider .. ")") or "")
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
        local frame = (UF and type(UF.GetFrame) == "function" and UF.GetFrame(unit))
            or (frames and frames[unit])
            or _G["MSUF_" .. unit]
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
ExportPublic("MSUF_DbgPos_UpdateOverlay", UpdateOverlay)

local function OverlayOnUpdate(frame, elapsed)
    frame._updateAccum = (frame._updateAccum or 0) + (elapsed or 0)
    if frame._updateAccum < 0.5 then return end
    frame._updateAccum = 0
    UpdateOverlay()
end

local function StartOverlayUpdates()
    if not _overlay then return end
    if _overlay._updatesActive then return end
    _overlay._updatesActive = true
    _overlay._updateAccum = 0.5
    if _overlay.SetOnUpdateMode then _overlay:SetOnUpdateMode(ONUPDATE_MODE_RUN_WHEN_VISIBLE) end
    _overlay:SetScript("OnUpdate", OverlayOnUpdate)
end

local function CreateOverlay()
    if _overlay then
        StartOverlayUpdates()
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
    StartOverlayUpdates()
end

local function StopOverlayUpdates()
    if _overlay then
        _overlay._updatesActive = nil
        _overlay._updateAccum = nil
        _overlay:SetScript("OnUpdate", nil)
        if _overlay.SetOnUpdateMode then _overlay:SetOnUpdateMode(ONUPDATE_MODE_DISABLED) end
    end
end

--- ── hooks (installed on demand, removed when debug turns off) ─────────────────

local _hooksInstalled = false
local _origMark, _origFlush, _origSnapshot
local _combatFrame

local function InstallHooks()
    if _hooksInstalled then return end
    _hooksInstalled = true

    --- Combat transitions: log ECV geometry at entry/exit
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

    --- CDMBridge: fires when size/show/point hooks detect a genuine anchor move or first usable anchor
    _origMark = _G.MSUF_MarkExternalAnchorForReanchor
    if _origMark then
        local function DebugMarkExternalAnchorForReanchor(...)
            Dbg("CDMBridge:MarkExternalAnchorForReanchor  " .. ECVLine())
            return _origMark(...)
        end
        ExportPublic("MSUF_MarkExternalAnchorForReanchor", DebugMarkExternalAnchorForReanchor)
    end

    --- Flush: runs out-of-combat after a reanchor was queued
    _origFlush = _G.MSUF_FlushCDMBridgeRefresh
    if _origFlush then
        local function DebugFlushCDMBridgeRefresh(...)
            Dbg("CDMBridge:FlushCDMBridgeRefresh  " .. ECVLine())
            return _origFlush(...)
        end
        ExportPublic("MSUF_FlushCDMBridgeRefresh", DebugFlushCDMBridgeRefresh)
    end

    --- Snapshot: read resulting SetPoint data after the call
    _origSnapshot = _G.MSUF_SnapshotFrameToUIParentCenter
    if _origSnapshot then
        local function DebugSnapshotFrameToUIParentCenter(frame, ...)
            local result = _origSnapshot(frame, ...)
            if result and frame and frame.GetPoint then
                local _, _, _, px, py = frame:GetPoint(1)
                Dbg("Snapshot " .. ((frame.GetName and frame:GetName()) or "?")
                    .. " -> UIParent CENTER (" .. tostring(px) .. "," .. tostring(py) .. ")")
            end
            return result
        end
        ExportPublic("MSUF_SnapshotFrameToUIParentCenter", DebugSnapshotFrameToUIParentCenter)
    end
end

local function RemoveHooks()
    if not _hooksInstalled then return end
    _hooksInstalled = false

    if _combatFrame then
        _combatFrame:UnregisterAllEvents()
    end

    if _origMark     then ExportPublic("MSUF_MarkExternalAnchorForReanchor", _origMark)    ; _origMark     = nil end
    if _origFlush    then ExportPublic("MSUF_FlushCDMBridgeRefresh", _origFlush)            ; _origFlush    = nil end
    if _origSnapshot then ExportPublic("MSUF_SnapshotFrameToUIParentCenter", _origSnapshot) ; _origSnapshot = nil end
end

--- ── toggle ───────────────────────────────────────────────────────────────────

local function DebugPositionsToggle()
    ExportPublic("MSUF_DebugPositions", not _G.MSUF_DebugPositions)
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
        StopOverlayUpdates()
        if _overlay then _overlay:Hide() end
        print("|cFFFF8800[MSUF]|r Position debug |cFFFF4444OFF|r")
    end
end
ExportPublic("MSUF_DebugPositions_Toggle", DebugPositionsToggle)

SLASH_MSUFDBGPOS1 = "/msufdbgpos"
SlashCmdList["MSUFDBGPOS"] = function()
    _G.MSUF_DebugPositions_Toggle()
end
--- This file is excluded from the shipped TOC, so the registration keeps
--- /msuf help honest: the command is listed only where it actually exists.
if MSUF and MSUF.SlashCommands and MSUF.SlashCommands.RegisterExternal then
    MSUF.SlashCommands.RegisterExternal({
        usage = "/msufdbgpos",
        help = "Toggle the position drift debugger.",
        dev = true,
    })
end
