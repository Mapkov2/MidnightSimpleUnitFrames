-- Chat/Slash commands (/msuf) + small tooltip helpers + Blizzard Edit Mode bridge
-- Thinking about just scrapping this if this causes more erros
local addonName, ns = ...
ns = ns or {}
local MSUF_RESET_DEFAULTS = {
    player = { width=275, height=40, offsetX=-260, offsetY=80, showName=true, showHP=true, showPower=true },
    target = { width=275, height=40, offsetX= 260, offsetY=80, showName=true, showHP=true, showPower=true },
    focus  = { width=220, height=30, offsetX= 260, offsetY=135, showName=true, showHP=false, showPower=false },
    pet    = { width=220, height=30, offsetX=-260, offsetY=135, showName=true, showHP=false, showPower=false },
    targettarget = { width=220, height=30, offsetX=260, offsetY=225, showName=true, showHP=true, showPower=false },
}
local MSUF_FullResetPending = false
local function MSUF_DoFullReset(opts)
    opts = opts or {}
    local skipReload = (opts.skipReload == true)
    if InCombatLockdown and InCombatLockdown() then
        print("|cffff0000MSUF:|r Cannot do FULL reset while in combat.")
         return
    end
    MSUF_DB = nil
    MSUF_GlobalDB = nil
    MSUF_ActiveProfile = nil
    print("|cffff0000MSUF:|r FULL RESET executed  all MSUF profiles & settings deleted for this account.")
    if skipReload then
        print("|cffffff00MSUF:|r Reset staged. Please type |cff00ff00/reload|r OR use: MSUF Menu  Advanced  Factory Reset.")
         return
    end
    print("|cffffff00MSUF:|r Reloading UI to rebuild clean defaults...")
	-- NOTE: C_UI.Reload() is protected; addons may get ADDON_ACTION_BLOCKED.
	-- ReloadUI() is the safe public API for addons.
	if type(ReloadUI) == "function" then
		ReloadUI()
	end
 end
-- Expose for the Slash Menu (button click = hardware event, safe for ReloadUI)
_G.MSUF_DoFullReset = MSUF_DoFullReset
local function MSUF_PrintHelp()
    print("|cff00ff00MSUF commands:|r")
    print("  /msuf help      - Show this help.")
    print("  /msuf reset     - Reset all MSUF frame positions and visibility to defaults.")
    print("  /msuf fullreset - FULL factory reset (all profiles/settings).")
    print("                   Confirm stages the reset; reload via /reload or MSUF Menu  Advanced  Factory Reset.")
    print("  /msuf absorb    - Toggle showing total absorb amount in HP text.")
    print("  !msuf help      - Print this help via chat (from your own character).")
 end
-- Optional chat trigger: "!msuf help" (only from yourself)
-- Midnight/Beta secret-safe: chat event args can become "secret" in combat.
-- Never boolean-test/compare them directly and never call string methods via ':'.
local NotSecretValue = _G.NotSecretValue
local function MSUF__Chat_IsSafeString(v)
    -- Secret-safe: never call string methods on secret strings (Midnight 12.0).
    if type(v) ~= "string" then
        return false
    end

    local isv = _G.issecretvalue
        or (C_Secrets and type(C_Secrets.IsSecret) == "function" and C_Secrets.IsSecret)
        or nil

    if isv and isv(v) then
        return false
    end

    local NotSecretValue = _G.NotSecretValue
    if NotSecretValue then
        return NotSecretValue(v)
    end

    -- If we cannot detect secret values, be conservative in combat.
    if InCombatLockdown and InCombatLockdown() then
        return false
    end

    return true
end
local function MSUF__Chat_IsFromSelf(author, ...)
    -- Prefer GUID-based self-check to avoid comparing author strings.
    local senderGUID = select(10, ...)
    local myGUID = UnitGUID and UnitGUID("player")
    if MSUF__Chat_IsSafeString(senderGUID) and MSUF__Chat_IsSafeString(myGUID) then
        return senderGUID == myGUID
    end
    -- Fallback: compare short author name (strip realm) only if strings are safe.
    local myName = UnitName and UnitName("player")
    if not MSUF__Chat_IsSafeString(myName) or not MSUF__Chat_IsSafeString(author) then
         return false
    end
    local shortAuthor = author
    local dash = string.find(author, "-", 1, true)
    if dash and dash > 1 then
        shortAuthor = string.sub(author, 1, dash - 1)
    end
    return (shortAuthor == myName)
end
local function MSUF__Chat_GetLowerTrimmed(text)
    if not MSUF__Chat_IsSafeString(text) then  return nil end
    local lower = string.lower(text)
    lower = string.gsub(lower, "^%s+", "")
     return lower
end
local function MSUF_ChatCommand_OnChatMsg(_, text, author, ...)
    local msgLower = MSUF__Chat_GetLowerTrimmed(text)
    if not msgLower then  return end
    -- Fast reject: only care about "!msuf help" (allow extra whitespace)
    if string.sub(msgLower, 1, 5) ~= "!msuf" then  return end
    local rest = string.sub(msgLower, 6)
    rest = string.gsub(rest, "^%s+", "")
    rest = string.gsub(rest, "%s+$", "")
    if rest ~= "help" then  return end
    if not MSUF__Chat_IsFromSelf(author, ...) then  return end
    MSUF_PrintHelp()
 end
if type(MSUF_EventBus_Register) == "function" then
    local evs = {
        "CHAT_MSG_SAY","CHAT_MSG_YELL","CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID","CHAT_MSG_RAID_LEADER","CHAT_MSG_RAID_WARNING",
        "CHAT_MSG_INSTANCE_CHAT","CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_GUILD","CHAT_MSG_OFFICER","CHAT_MSG_WHISPER",
    }
    for _, e in ipairs(evs) do
        MSUF_EventBus_Register(e, "MSUF_CHATCMD", MSUF_ChatCommand_OnChatMsg)
    end
end
SLASH_MIDNIGHTSUF1 = "/msuf"
SlashCmdList["MIDNIGHTSUF"] = function(msg)
    msg = msg and msg:lower() or ""
    msg = msg:gsub("^%s+", "")
    local cmd = msg:match("^(%S+)") or ""
    if cmd == "" or cmd == "help" then
        MSUF_PrintHelp()
         return
    end
-- Should clean this up since we have now a button for full reset.
    if cmd == "fullreset" then
        if not MSUF_FullResetPending then
            MSUF_FullResetPending = true
            print("|cffff0000MSUF WARNING:|r This will delete |cffff0000ALL|r MSUF profiles & settings for this account.")
            print("|cffffcc00MSUF:|r Type |cffffff00/msuf fullreset confirm|r to stage the reset.")
            print("|cffffcc00MSUF:|r Then click: MSUF Menu  Advanced  Factory Reset (or type /reload).")
             return
        end
        if msg ~= "fullreset confirm" then
            MSUF_FullResetPending = false
            print("|cffffcc00MSUF:|r Full reset cancelled. If you still want it, type:")
            print("  /msuf fullreset")
            print("  /msuf fullreset confirm")
            print("  (then /reload OR MSUF Menu  Advanced  Factory Reset)")
             return
        end
        MSUF_FullResetPending = false
        MSUF_DoFullReset({ skipReload = true })
         return
    end
    if cmd == "reset" then
        if InCombatLockdown and InCombatLockdown() then
            print("|cffff0000MSUF:|r Cannot reset while in combat.")
             return
        end
        if type(EnsureDB) == "function" then
            EnsureDB()
        end
        if type(MSUF_DB) == "table" then
            for unit, defaults in pairs(MSUF_RESET_DEFAULTS) do
                MSUF_DB[unit] = MSUF_DB[unit] or {}
                local t = MSUF_DB[unit]
                for k, v in pairs(defaults) do
                    t[k] = v
                end
                if t.enabled == nil then
                    t.enabled = true
                end
            end
        end
        if type(ApplyAllSettings) == "function" then
            ApplyAllSettings()
        end
        if type(UpdateAllFonts) == "function" then
            UpdateAllFonts()
        end
        print("|cff00ff00MSUF:|r Positions and visibility reset to defaults.")
         return
    end
    if cmd == "absorb" then
        if type(EnsureDB) == "function" then
            EnsureDB()
        end
        local g = (type(MSUF_DB) == "table" and type(MSUF_DB.general) == "table") and MSUF_DB.general or nil
        if not g then
            print("|cffff0000MSUF:|r DB not initialized.")
             return
        end
        g.showTotalAbsorbAmount = not g.showTotalAbsorbAmount
        if type(ApplyAllSettings) == "function" then
            ApplyAllSettings()
        end
        if g.showTotalAbsorbAmount then
            print("|cff00ff00MSUF:|r Total absorb amount in HP text ENABLED.")
        else
            print("|cff00ff00MSUF:|r Total absorb amount in HP text DISABLED.")
        end
         return
    end
    -- Unknown
    MSUF_PrintHelp()
 end
local MSUF_PlayerInfoFrame
local function MSUF_GetPlayerInfoFrame()
    if MSUF_PlayerInfoFrame then
         return MSUF_PlayerInfoFrame
    end
    local f = CreateFrame("Frame", "MSUF_PlayerInfoFrame", UIParent, "BackdropTemplate")
    f:SetSize(260, 90)
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16, 180)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.9)
    end
    local nameFS = f:CreateFontString(nil, "OVERLAY", "GameTooltipHeaderText")
    nameFS:SetPoint("TOPLEFT", 8, -8)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetText("")
    nameFS:SetTextColor(1, 1, 1) -- Wei wie normaler Tooltip-Text
    local line2FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line2FS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -2)
    line2FS:SetJustifyH("LEFT")
    local line3FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line3FS:SetPoint("TOPLEFT", line2FS, "BOTTOMLEFT", 0, -2)
    line3FS:SetJustifyH("LEFT")
    local line4FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line4FS:SetPoint("TOPLEFT", line3FS, "BOTTOMLEFT", 0, -2)
    line4FS:SetJustifyH("LEFT")
    local line5FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line5FS:SetPoint("TOPLEFT", line4FS, "BOTTOMLEFT", 0, -2)
    line5FS:SetJustifyH("LEFT")
    line5FS:SetTextColor(0.8, 0.8, 0.8) -- leicht ausgegraut wie Location-Zeile
    f.name  = nameFS
    f.line2 = line2FS
    f.line3 = line3FS
    f.line4 = line4FS
    f.line5 = line5FS
    f:Hide()
    MSUF_PlayerInfoFrame = f
     return f
end
local function MSUF_PositionPlayerInfoFrame(frame)
    EnsureDB()
    local g = MSUF_DB.general or {}

    -- Custom position from Edit Mode drag takes priority over style-based positioning.
    local cx = g.tooltipPosX
    local cy = g.tooltipPosY
    if type(cx) == "number" and type(cy) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx, cy)
        return
    end

    local style = g.unitInfoTooltipStyle or "classic"
    frame:ClearAllPoints()
    if style == "modern" and GetCursorPosition and UIParent then
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        x, y = x / scale, y / scale
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 130, y - 150)
    else
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16, 180)
    end
 end
-- Tooltip helpers (unified; keeps behavior, reduces copy/paste)
local function MSUF_UnitInfo_GetLocationText()
    local zone = GetZoneText and GetZoneText() or nil
    local subzone = GetSubZoneText and GetSubZoneText() or nil
    if subzone and subzone ~= "" and zone and zone ~= "" then
        -- Only compare strings if they're safe; otherwise just prefer subzone when present.
        if (not NotSecretValue) or (NotSecretValue(subzone) and NotSecretValue(zone)) then
            if subzone ~= zone then
                 return subzone
            end
        end
    end
    return (subzone and subzone ~= "") and subzone or zone
end
local function MSUF_UnitInfo_BuildNameLine(unit, fallbackName, isPlayer)
    local nameLine = UnitName(unit) or fallbackName
    if isPlayer then
        if UnitIsAFK(unit) then
            nameLine = nameLine .. " <AFK>"
        elseif UnitIsDND(unit) then
            nameLine = nameLine .. " <DND>"
        end
    end
     return nameLine
end
local function MSUF_UnitInfo_BuildLine4(faction, isPVP)
    if (not faction or faction == "") and not isPVP then
         return ""
    end
    local text = faction or ""
    if isPVP then
        if text ~= "" then
            text = text .. "  PvP"
        else
            text = "PvP"
        end
    end
     return text
end
local function MSUF_UnitInfo_BuildLine2_Player(level, race, classLoc)
    local n = tonumber(level)
    if n and n > 0 then
        if race and classLoc then
            return string.format("Level %d %s %s", n, race, classLoc)
        elseif classLoc then
            return string.format("Level %d %s", n, classLoc)
        else
            return string.format("Level %d", n)
        end
    end
    return classLoc or ""
end
local function MSUF_UnitInfo_ClassificationText(classification)
    if classification == "elite" then
         return "Elite"
    elseif classification == "rare" then
         return "Rare"
    elseif classification == "rareelite" then
         return "Rare Elite"
    elseif classification == "worldboss" then
         return "Boss"
    end
     return nil
end
local function MSUF_UnitInfo_BuildLine2_NPC(level, classification)
    local n = tonumber(level)
    if not (n and n > 0) then
         return ""
    end
    local line2 = string.format("Level %d", n)
    local clsText = MSUF_UnitInfo_ClassificationText(classification)
    if clsText then
        line2 = line2 .. string.format(" (%s)", clsText)
    end
     return line2
end
local function MSUF_UnitInfo_ShowFrame(f, nameLine, line2, line3, line4, loc)
    f.name:SetText(nameLine or "")
    f.line2:SetText(line2 or "")
    f.line3:SetText(line3 or "")
    f.line4:SetText(line4 or "")
    f.line5:SetText(loc or "")
    MSUF_PositionPlayerInfoFrame(f)
    f:Show()
 end
local function MSUF_UnitInfo_ShowTargetLike(unit, fallbackName)
    local f = MSUF_GetPlayerInfoFrame()
    if not UnitExists(unit) then
        f:Hide()
         return
    end
    local level      = UnitLevel(unit)
    local isPlayer   = UnitIsPlayer(unit)
    local race, classLoc, faction, isPVP
    if isPlayer then
        race     = UnitRace(unit)
        classLoc = select(1, UnitClass(unit))
        faction  = UnitFactionGroup(unit)
        isPVP    = UnitIsPVP(unit)
    end
    local nameLine = MSUF_UnitInfo_BuildNameLine(unit, fallbackName, isPlayer)
    local line2 = isPlayer and MSUF_UnitInfo_BuildLine2_Player(level, race, classLoc)
                    or MSUF_UnitInfo_BuildLine2_NPC(level, UnitClassification(unit))
    local line3 = isPlayer and (classLoc or "") or (UnitCreatureType(unit) or "")
    local line4 = isPlayer and MSUF_UnitInfo_BuildLine4(faction, isPVP) or ""
    local loc   = MSUF_UnitInfo_GetLocationText()
    MSUF_UnitInfo_ShowFrame(f, nameLine, line2, line3, line4, loc)
 end
function MSUF_ShowPlayerInfoTooltip()
    local f = MSUF_GetPlayerInfoFrame()
    if not UnitExists("player") then
        f:Hide()
         return
    end
    local level    = UnitLevel("player")
    local race     = UnitRace("player")
    local classLoc = select(1, UnitClass("player"))
    local faction  = UnitFactionGroup("player")
    local isPVP    = UnitIsPVP("player")
    local specName
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local _, sName = GetSpecializationInfo(specIndex, nil, nil, nil, UnitSex("player"))
            specName = sName
        end
    end
    local nameLine = MSUF_UnitInfo_BuildNameLine("player", "Player", true)
    local line2    = MSUF_UnitInfo_BuildLine2_Player(level, race, classLoc)
    local line3 = ""
    if specName and classLoc then
        line3 = string.format("%s %s", specName, classLoc)
    elseif specName then
        line3 = specName
    end
    local line4 = MSUF_UnitInfo_BuildLine4(faction, isPVP)
    local loc   = MSUF_UnitInfo_GetLocationText()
    MSUF_UnitInfo_ShowFrame(f, nameLine, line2, line3, line4, loc)
 end
function MSUF_ShowTargetInfoTooltip()
    MSUF_UnitInfo_ShowTargetLike("target", "Target")
 end
function MSUF_ShowFocusInfoTooltip()
    MSUF_UnitInfo_ShowTargetLike("focus", "Focus")
 end
function MSUF_ShowTargetTargetInfoTooltip()
    MSUF_UnitInfo_ShowTargetLike("targettarget", "Target of Target")
 end
function MSUF_ShowPetInfoTooltip()
    local f = MSUF_GetPlayerInfoFrame()
    if not UnitExists("pet") then
        f:Hide()
         return
    end
    local name         = UnitName("pet") or "Pet"
    local level        = UnitLevel("pet")
    local creatureType = UnitCreatureType("pet")
    local loc          = MSUF_UnitInfo_GetLocationText()
    local line2 = ""
    local n = tonumber(level)
    if n and n > 0 then
        line2 = string.format("Level %d", n)
    end
    MSUF_UnitInfo_ShowFrame(f, name, line2, creatureType or "", "", loc)
 end
function MSUF_HidePlayerInfoTooltip()
    if MSUF_PlayerInfoFrame then
        MSUF_PlayerInfoFrame:Hide()
    end
 end
-- [8c6] Removed legacy Options UI relayout functions (Player/Bars).
-- These were dead/duplicate layout builders superseded by MSUF_Options_Core.lua.
if not _G.MSUF_SetBlizzardEditModeFromMSUF then
    function _G.MSUF_SetBlizzardEditModeFromMSUF(active)
        if InCombatLockdown and InCombatLockdown() then
             return
        end
        if type(EnsureDB) == "function" then EnsureDB() end
        if MSUF_DB and MSUF_DB.general and MSUF_DB.general.linkEditModes == false then
             return
        end
        local emf = _G.EditModeManagerFrame
        if not emf then
             return
        end
        if active then
            if not _G.MSUF_BlizzEditModeStartedByMSUF then
                _G.MSUF_BlizzEditModeStartedByMSUF = true
            end
            local ok = pcall(function()
                if type(securecallfunction) == "function" and type(_G.ShowUIPanel) == "function" then
                    securecallfunction(_G.ShowUIPanel, emf) -- this will show the edit mode panel and enter edit mode
                elseif emf.Show then
                    emf:Show()
                elseif emf.EnterEditMode then
                    emf:EnterEditMode()
                end
             end)
            if not ok then
                _G.MSUF_BlizzEditModeStartedByMSUF = nil
            end
        else
            if not _G.MSUF_BlizzEditModeStartedByMSUF then
                 return
            end
            _G.MSUF_BlizzEditModeStartedByMSUF = nil
            pcall(function()
                if type(securecallfunction) == "function" and type(emf.ExitEditMode) == "function" then
                    securecallfunction(emf.ExitEditMode, emf)
                elseif emf.ExitEditMode then
                    emf:ExitEditMode()
                end
                if type(securecallfunction) == "function" and type(_G.HideUIPanel) == "function" and emf.IsShown and emf:IsShown() then
                    securecallfunction(_G.HideUIPanel, emf)
                elseif emf.Hide and emf.IsShown and emf:IsShown() then
                    emf:Hide()
                end
             end)
        end
     end
end
-- [8c6] Removed PLAYER_LOGIN Options relayout hook (Bars).
ns.MSUF_UpdateAllFonts = ns.MSUF_UpdateAllFonts or UpdateAllFonts

-- ==========================================================================
-- Edit Mode: Tooltip Position Drag Handle
-- Shows a preview of the MSUF tooltip and makes it draggable to set a custom
-- position. Persists to MSUF_DB.general.tooltipPosX / .tooltipPosY.
-- Only active while MSUF Edit Mode is on; zero OnUpdate cost outside of drag.
-- ==========================================================================
do
    local tooltipDragHandle          -- overlay frame (lazy-created)
    local tooltipEditPreviewActive = false

    -- ---- persistence -------------------------------------------------------
    local function MSUF_Tooltip_SavePosition(frame)
        if not frame then return end
        if type(EnsureDB) == "function" then EnsureDB() end
        local g = type(MSUF_DB) == "table" and MSUF_DB.general
        if type(g) ~= "table" then return end
        local left   = frame.GetLeft   and frame:GetLeft()
        local bottom = frame.GetBottom and frame:GetBottom()
        if type(left) == "number" and type(bottom) == "number" then
            g.tooltipPosX = math.floor(left + 0.5)
            g.tooltipPosY = math.floor(bottom + 0.5)
        end
    end

    -- ---- reset helper (called from Options / slash) ------------------------
    local function MSUF_Tooltip_ResetPosition()
        if type(EnsureDB) == "function" then EnsureDB() end
        local g = type(MSUF_DB) == "table" and MSUF_DB.general
        if type(g) ~= "table" then return end
        g.tooltipPosX = nil
        g.tooltipPosY = nil
    end
    _G.MSUF_Tooltip_ResetPosition = MSUF_Tooltip_ResetPosition

    -- ---- drag handle (lazy) ------------------------------------------------
    local function MSUF_Tooltip_EnsureDragHandle(parent)
        if tooltipDragHandle then
            -- Re-parent in case tooltip was re-created (shouldn't happen, but safe).
            if tooltipDragHandle:GetParent() ~= parent then
                tooltipDragHandle:SetParent(parent)
            end
            tooltipDragHandle:SetAllPoints(parent)
            return tooltipDragHandle
        end

        local dh = CreateFrame("Frame", "MSUF_TooltipDragHandle", parent)
        dh:SetAllPoints(parent)
        dh:EnableMouse(true)
        dh:RegisterForDrag("LeftButton")
        dh:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 10)

        -- Subtle visual overlay so the user knows it's draggable
        local bg = dh:CreateTexture(nil, "OVERLAY")
        bg:SetAllPoints()
        bg:SetColorTexture(0.2, 0.6, 1.0, 0.12)
        dh._bg = bg

        local label = dh:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", dh, "TOP", 0, -2)
        label:SetText("Drag to reposition")
        label:SetTextColor(0.4, 0.8, 1.0, 0.9)
        dh._label = label

        dh:SetScript("OnDragStart", function(self)
            if InCombatLockdown and InCombatLockdown() then return end
            local p = self:GetParent()
            if p then
                p:SetMovable(true)
                p:SetClampedToScreen(true)
                p:StartMoving()
            end
        end)

        dh:SetScript("OnDragStop", function(self)
            local p = self:GetParent()
            if not p then return end
            p:StopMovingOrSizing()
            p:SetMovable(false)
            MSUF_Tooltip_SavePosition(p)
        end)

        dh:Hide()
        tooltipDragHandle = dh
        return dh
    end

    -- ---- Edit Mode enter/exit ----------------------------------------------
    local function MSUF_Tooltip_ShowEditPreview()
        local f = MSUF_GetPlayerInfoFrame()
        if not f then return end

        -- Fill with placeholder content so the user sees size/layout
        if f.name  then f.name:SetText("Player Name")           end
        if f.line2 then f.line2:SetText("Level 80 Human Paladin") end
        if f.line3 then f.line3:SetText("Protection Paladin")     end
        if f.line4 then f.line4:SetText("Alliance")               end
        if f.line5 then f.line5:SetText("Stormwind City")         end

        -- Position (uses saved pos if available, else style default)
        MSUF_PositionPlayerInfoFrame(f)
        f:Show()

        -- Enable drag
        local dh = MSUF_Tooltip_EnsureDragHandle(f)
        dh:Show()
        tooltipEditPreviewActive = true
    end

    local function MSUF_Tooltip_HideEditPreview()
        if tooltipDragHandle then
            tooltipDragHandle:Hide()
        end
        tooltipEditPreviewActive = false
        -- Hide the tooltip preview (but not if a real tooltip is being shown outside edit mode).
        -- The preview uses placeholder text, so we can safely hide it.
        if MSUF_PlayerInfoFrame then
            MSUF_PlayerInfoFrame:SetMovable(false)
            MSUF_PlayerInfoFrame:Hide()
        end
    end

    -- Expose for CloseAllPositionPopups and external callers
    _G.MSUF_Tooltip_HideEditPreview = MSUF_Tooltip_HideEditPreview
    _G.MSUF_Tooltip_ShowEditPreview = MSUF_Tooltip_ShowEditPreview

    -- Register as AnyEditMode listener (fires on MSUF and/or Blizzard Edit Mode transitions).
    if type(_G.MSUF_RegisterAnyEditModeListener) == "function" then
        _G.MSUF_RegisterAnyEditModeListener(function(active)
            if active then
                MSUF_Tooltip_ShowEditPreview()
            else
                MSUF_Tooltip_HideEditPreview()
            end
        end)
    end
end
