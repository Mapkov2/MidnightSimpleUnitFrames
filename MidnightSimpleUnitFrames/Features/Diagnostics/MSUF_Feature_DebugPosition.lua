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
local ExportPublic, Require = MSUF.ExportPublic, MSUF.Require
local FILE = "Features/Diagnostics/MSUF_Feature_DebugPosition.lua"
-- The flag is a namespace export (no published global), so it is read back
-- from the same mirror ExportPublic writes.
local PublicGlobals = MSUF.PublicGlobals

ExportPublic("MSUF_DebugPositions", false)

-- SetOnUpdateMode takes an Enum.OnUpdateMode value, not a name; a string argument leaves the
-- overlay's OnUpdate disabled.
local ONUPDATE_MODE_DISABLED = (Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.Disabled) or 0
local ONUPDATE_MODE_RUN_WHEN_VISIBLE = (Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.RunWhenVisible) or 1

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

--- Cooldown-anchor providers, bound on the first overlay tick or log line so
--- the overlay OnUpdate never repeats the lookup.
local GetCooldownFrame, GetAnchorSize, GetAutomaticProvider, IsAnchorEnabled

local function BindAnchorProviders()
    GetCooldownFrame = Require("MSUF_GetEffectiveCooldownFrame", FILE)
    GetAnchorSize = Require("MSUF_GetUsableCooldownAnchorSize", FILE)
    GetAutomaticProvider = Require("MSUF_GetAutomaticCooldownAnchorProvider", FILE)
    IsAnchorEnabled = Require("MSUF_IsCooldownAnchorEnabled", FILE)
end

local function GetECV()
    if not GetCooldownFrame then BindAnchorProviders() end
    local frame = GetCooldownFrame("EssentialCooldownViewer") or EssentialCooldownViewer
    return GetAnchorSize(frame) ~= nil and frame or nil
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
    if not PublicGlobals.MSUF_DebugPositions then return end
    if not _overlay then return end
    local l   = _overlay.lines
    local ecv = GetECV()
    local db  = MSUF_DB
    local g   = db and db.general
    local UF = MSUF and MSUF.UF
    local frames = UF and UF.frames

    l[1]:SetText("|cFFFFFF00MSUF Position Debug|r  Combat: "
        .. (MSUF.PublicGlobals.MSUF_InCombat and "|cFFFF4444IN|r" or "|cFF44FF44OUT|r"))

    local _, automaticProvider = GetAutomaticProvider()
    local cooldownEnabled = IsAnchorEnabled(g) == true
        or (type(C_CooldownViewer) == "table" and g and g.anchorToCooldown == true)
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
            local conf = db and db[frame.msufConfigKey or unit]
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
local _origSnapshot
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

    --- Snapshot: read resulting SetPoint data after the call
    _origSnapshot = Require("MSUF_SnapshotFrameToUIParentCenter", FILE)
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

local function RemoveHooks()
    if not _hooksInstalled then return end
    _hooksInstalled = false

    if _combatFrame then
        _combatFrame:UnregisterAllEvents()
    end

    if _origSnapshot then
        ExportPublic("MSUF_SnapshotFrameToUIParentCenter", _origSnapshot)
        _origSnapshot = nil
    end
end

--- ── toggle ───────────────────────────────────────────────────────────────────

local function DebugPositionsToggle()
    ExportPublic("MSUF_DebugPositions", not PublicGlobals.MSUF_DebugPositions)
    if PublicGlobals.MSUF_DebugPositions then
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
    DebugPositionsToggle()
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
