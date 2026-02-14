-- NOTE: This file exists in Core/ for newer layouts. A copy is also shipped at addon root for older .toc layouts.
--
-- Provides:
--   MSUF_UpdateStatusIndicatorForFrame(frame)  (global)
--   MSUF_GetStatusIndicatorDB()               (global)
--   MSUF_GetStatusIconsTestMode()/Set...      (global)
local addonName, ns = ...
ns = ns or {}

-- Hotpath locals (avoid _G lookups)
local _G = _G
local type   = _G.type
local pairs  = _G.pairs
local ipairs = _G.ipairs
local next   = _G.next
local tonumber = _G.tonumber
local tostring = _G.tostring
local select   = _G.select
local IsInInstance = _G.IsInInstance
local issecretvalue = _G.issecretvalue
-- Lua 5.1 (WoW) uses global unpack; some environments expose table.unpack
local unpack = _G.unpack
if not unpack then
    local tbl = _G.table
    unpack = tbl and tbl.unpack
end
-- ------------------------------------------------------------
-- Status text DB (AFK/DND/DEAD/GHOST/OFFLINE)
-- ------------------------------------------------------------
if type(_G.MSUF_GetStatusIndicatorDB) ~= "function" then
    -- PERF: Avoid per-call table allocations. This can be hit during very early load
    -- (before EnsureDB is available), and MSUF_GetStatusIndicatorDB may be called in hot paths.
    local _MSUF_DEFAULT_STATUS_INDICATORS = {
        showAFK = true,
        showDND = true,
        showDead = true,
        showGhost = true,
    }
    local function _MSUF_DefaultStatusIndicators()
        return _MSUF_DEFAULT_STATUS_INDICATORS
    end
    function _G.MSUF_GetStatusIndicatorDB()
        if type(_G.EnsureDB) == "function" then
            _G.EnsureDB()
        end
        local db = _G.MSUF_DB
        local g = (type(db) == "table") and db.general or nil
        if type(g) ~= "table" then
            return _MSUF_DefaultStatusIndicators()
        end
        if type(g.statusIndicators) ~= "table" then
            g.statusIndicators = {}
        end
        local si = g.statusIndicators
        if si.showAFK == nil then si.showAFK = true end
        if si.showDND == nil then si.showDND = true end
        if si.showDead == nil then si.showDead = true end
        if si.showGhost == nil then si.showGhost = true end
         return si
    end
end
-- Backwards alias used by older call sites
MSUF_GetStatusIndicatorDB = _G.MSUF_GetStatusIndicatorDB
-- ------------------------------------------------------------
-- Midnight/Beta (12.0+): AFK/DND can return secret booleans in combat/encounters.
-- Cache suppression state via events to avoid per-frame InCombatLockdown/IsEncounter calls.
-- ------------------------------------------------------------
if ns._msufAwaySuppressed == nil then
    local function _MSUF_AwaySuppressedNow()
        if InCombatLockdown and InCombatLockdown() then
            return true
        end

        -- Midnight/Beta (12.0+): chat messaging lockdown causes UnitIsAFK/UnitIsDND to return secret values.
        local CCI = _G.C_ChatInfo
        if CCI and CCI.InChatMessagingLockdown and CCI.InChatMessagingLockdown() then
            return true
        end
        -- Instances: AFK/DND status is non-essential; avoid secret values entirely.
        if IsInInstance then
            local inInst = IsInInstance()
            if inInst then
                return true
            end
        end
        local CIE = _G.C_InstanceEncounter
        if CIE and CIE.IsEncounterInProgress and CIE.IsEncounterInProgress() then
            return true
        end
        return false
    end

    ns._msufAwaySuppressed = _MSUF_AwaySuppressedNow()

    local f = CreateFrame and CreateFrame("Frame") or nil
    if f then
        f:RegisterEvent("PLAYER_REGEN_DISABLED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:RegisterEvent("ENCOUNTER_START")
        f:RegisterEvent("ENCOUNTER_END")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("ZONE_CHANGED_NEW_AREA")

        local function _MSUF_AwayState_OnEvent()
            ns._msufAwaySuppressed = _MSUF_AwaySuppressedNow()
        end
        f:SetScript("OnEvent", _MSUF_AwayState_OnEvent)
    end
end

-- ------------------------------------------------------------
-- Helpers (read config with global fallback)
-- ------------------------------------------------------------
local function _MSUF_ReadBool(conf, g, k, defaultVal, legacyKey)
    local v
    if type(conf) == "table" then
        v = conf[k]
        if v == nil and legacyKey then v = conf[legacyKey] end
    end
    if v == nil and type(g) == "table" then
        v = g[k]
        if v == nil and legacyKey then v = g[legacyKey] end
    end
    if v == nil then v = defaultVal end
    return (v ~= false)
end
local function _MSUF_ReadNumber(conf, g, k, defaultVal, legacyKey)
    local v
    if type(conf) == "table" then
        v = conf[k]
        if v == nil and legacyKey then v = conf[legacyKey] end
    end
    if v == nil and type(g) == "table" then
        v = g[k]
        if v == nil and legacyKey then v = g[legacyKey] end
    end
    v = tonumber(v)
    if v == nil then v = defaultVal end
     return v
end
local function _MSUF_ReadStr(conf, g, k, defaultVal, legacyKey)
    local v
    if type(conf) == "table" then
        v = conf[k]
        if v == nil and legacyKey then v = conf[legacyKey] end
    end
    if v == nil and type(g) == "table" then
        v = g[k]
        if v == nil and legacyKey then v = g[legacyKey] end
    end
    if v == nil then v = defaultVal end
     return v
end
-- ------------------------------------------------------------
-- Status Icon Symbol Textures (Classic vs Midnight)
-- ------------------------------------------------------------
local function _MSUF_GetStatusIconsUseMidnight(conf, g)
    -- Global by design; allow per-frame legacy if ever present.
    if type(conf) == "table" and conf.statusIconsUseMidnightStyle ~= nil then
        return (conf.statusIconsUseMidnightStyle == true)
    end
    if type(g) == "table" and g.statusIconsUseMidnightStyle ~= nil then
        return (g.statusIconsUseMidnightStyle == true)
    end
     return false
end
-- ------------------------------------------------------------
-- Status Icon Symbol Textures (Classic vs Midnight)
-- Supports different symbol families:
--   weapon_*         -> Media/Symbols/Combat         (128_clean)
--   rested_*         -> Media/Symbols/Rested         (64)
--   resurrection_*   -> Media/Symbols/Ress           (64)
--   classification_* -> Media/Symbols/Classification (64)
-- ------------------------------------------------------------
local function _MSUF_BuildStatusIconSymbolTexturePath(symbolKey, useMidnight)
    if type(symbolKey) ~= "string" or symbolKey == "" or symbolKey == "DEFAULT" then
         return nil
    end
    local folder = "Combat"
    local suffix = (useMidnight == true) and "_midnight_128_clean.tga" or "_classic_128_clean.tga"
    -- Rested icons use a different folder + size/suffix convention.
    if string.find(symbolKey, "^rested_") then
        folder = "Rested"
        suffix = (useMidnight == true) and "_midnight_64.tga" or "_classic_64.tga"
    -- Resurrection icons use a different folder + size/suffix convention.
    elseif string.find(symbolKey, "^resurrection_") then
        folder = "Ress"
        suffix = (useMidnight == true) and "_midnight_64.tga" or "_classic_64.tga"
    -- Target classification icons (Boss/Elite/Rare) use 64px symbols.
    elseif string.find(symbolKey, "^classification_") then
        folder = "Classification"
        suffix = (useMidnight == true) and "_midnight_64.tga" or "_classic_64.tga"
    end
    return "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Symbols\\" .. folder .. "\\" .. symbolKey .. suffix
end
local function _MSUF_EnsurePulseAnim(tex)
    if not tex or not tex.CreateAnimationGroup then  return nil end
    if tex._msufPulseAnim then return tex._msufPulseAnim end
    local ag = tex:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0.45)
    a1:SetToAlpha(1.0)
    a1:SetDuration(0.85)
    a1:SetOrder(1)
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(1.0)
    a2:SetToAlpha(0.45)
    a2:SetDuration(0.85)
    a2:SetOrder(2)
    tex._msufPulseAnim = ag
     return ag
end
local function _MSUF_StopPulseAnim(tex)
    local ag = tex and tex._msufPulseAnim
    if ag and ag.Stop then ag:Stop() end
    if tex and tex.SetAlpha then tex:SetAlpha(1) end
 end
local function _MSUF_ApplyStatusIconSymbolTexture(tex, symbolKey, useMidnight, wantsPulse)
    if not tex or not tex.SetTexture then  return end
    -- Capture default texture/atlas so selecting DEFAULT later restores the original icon.
    if tex._msufDefaultTexture == nil and tex.GetTexture then
        tex._msufDefaultTexture = tex:GetTexture()
    end
    if tex._msufDefaultAtlas == nil and tex.GetAtlas then
        local a = tex:GetAtlas()
        if a then tex._msufDefaultAtlas = a end
    end
    -- Capture default texcoords so we can restore them when the user selects DEFAULT again.
    if tex._msufDefaultTexCoord == nil and tex.GetTexCoord then
        local ulx, uly, llx, lly, urx, ury, lrx, lry = tex:GetTexCoord()
        tex._msufDefaultTexCoord = { ulx, uly, llx, lly, urx, ury, lrx, lry }
    end
    local path = _MSUF_BuildStatusIconSymbolTexturePath(symbolKey, useMidnight)
    if not path then
        tex._msufSymbolStamp = nil
        -- Restore original texture/atlas when returning to DEFAULT.
        if tex._msufDefaultAtlas and tex.SetAtlas then
            tex:SetAtlas(tex._msufDefaultAtlas)
        elseif tex._msufDefaultTexture then
            tex:SetTexture(tex._msufDefaultTexture)
        end
        -- Restore original texcoords when returning to DEFAULT.
        local tc = tex._msufDefaultTexCoord
        if tc and tex.SetTexCoord then
            tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8])
        end
        _MSUF_StopPulseAnim(tex)
         return
    end
    local stamp = path
    if tex._msufSymbolStamp ~= stamp then
        tex:SetTexture(path)
        tex._msufSymbolStamp = stamp
        -- Ensure the symbol TGAs are not cropped.
        if tex.SetTexCoord then
            tex:SetTexCoord(0, 1, 0, 1)
        end
    end
    if wantsPulse then
        local ag = _MSUF_EnsurePulseAnim(tex)
        if ag and ag.Play and (not ag:IsPlaying()) then
            ag:Play()
        end
    else
        _MSUF_StopPulseAnim(tex)
    end
 end
local function _MSUF_AnchorCorner(tex, frame, corner, xOff, yOff)
    if not tex or not frame then  return end
    corner = corner or "TOPLEFT"
    xOff = xOff or 0
    yOff = yOff or 0
    tex:ClearAllPoints()
    if corner == "CENTER" then
        tex:SetPoint("CENTER", frame, "CENTER", 0 + xOff, 0 + yOff)
         return
    end
    if corner == "TOPRIGHT" then
        tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2 + xOff, -2 + yOff)
         return
    elseif corner == "BOTTOMLEFT" then
        tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2 + xOff, 2 + yOff)
         return
    elseif corner == "BOTTOMRIGHT" then
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2 + xOff, 2 + yOff)
         return
    end
    -- TOPLEFT default
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 2 + xOff, -2 + yOff)
 end
-- ------------------------------------------------------------
-- Target classification state (Boss / Elite / Rare)
-- ------------------------------------------------------------
local function _MSUF_GetClassificationState(unit)
    if not unit or not UnitExists or not UnitExists(unit) then
         return nil
    end
    local c = UnitClassification and UnitClassification(unit) or nil
    if c == "worldboss" then
         return "BOSS"
    end
    -- Boss fallback: level -1 (common for bosses / many dungeon bosses)
    local lvl = UnitLevel and UnitLevel(unit) or nil
    if lvl == -1 then
         return "BOSS"
    end
    if c == "rareelite" then  return "RAREELITE" end
    if c == "rare"     then  return "RARE"     end
    if c == "elite"    then  return "ELITE"    end
     return nil
end
local function _MSUF_GetDefaultClassificationSymbolKey(state)
    -- Default symbol keys for the new classification family.
    -- Step 5 will provide the actual Media/Symbols/Classification/*.tga assets.
    if state == "BOSS" then
         return "classification_boss"
    end
    if state == "RAREELITE" then
         return "classification_rareelite"
    end
    if state == "RARE" then
         return "classification_rare"
    end
    if state == "ELITE" then
         return "classification_elite"
    end
     return nil
end
local function _MSUF_NormalizeClassificationSymbolKey(symbolKey, state)
    if type(symbolKey) ~= "string" or symbolKey == "" or symbolKey == "DEFAULT" then
        return _MSUF_GetDefaultClassificationSymbolKey(state)
    end
     return symbolKey
end
local function _MSUF_GetClassificationLabel(state)
    if state == "BOSS" then
         return "BOSS"
    end
    if state == "RAREELITE" then
         return "RARE+"
    end
    if state == "RARE" then
         return "RARE"
    end
    if state == "ELITE" then
         return "ELITE"
    end
     return ""
end
-- Ensure a FontString has a font before calling :SetText().
-- Some FontStrings may be created without a template; in that case SetText() can throw "Font not set".
local function _MSUF_EnsureFontStringHasFont(fs)
    if not fs then  return false end
    if fs.GetFont then
        local p = fs:GetFont()
        if p then  return true end
    end
    -- Prefer a known-good UI FontObject.
    if fs.SetFontObject and _G.GameFontHighlightLarge then
        fs:SetFontObject(_G.GameFontHighlightLarge)
         return true
    end
    -- Fallback: raw font file (should exist everywhere).
    if fs.SetFont and _G.STANDARD_TEXT_FONT then
        fs:SetFont(_G.STANDARD_TEXT_FONT, 12, "")
         return true
    end
     return false
end
-- ------------------------------------------------------------
-- Status icons update (Combat / Resting / Incoming Res)
-- Summon was removed intentionally (user request)
-- ------------------------------------------------------------
local function _MSUF_UpdateStatusIcons(frame)
    if not frame or not frame.unit then  return end
    local unit = frame.unit
    local db = _G.MSUF_DB
    if type(db) ~= "table" then  return end
    local g = db.general or {}
    local conf
    if frame._msufIsPlayer then
        conf = db.player
    elseif frame._msufIsTarget then
        conf = db.target
    else
         return
    end
    if type(conf) ~= "table" then  return end
    -- Test mode is global (sync across frames) but we accept per-frame legacy keys if present.
    local testMode = ((type(g) == "table" and g.stateIconsTestMode == true) or (type(conf) == "table" and conf.stateIconsTestMode == true)) and true or false
    local showCombat = _MSUF_ReadBool(conf, g, "showCombatStateIndicator", false)
    local showRest = false
    if frame._msufIsPlayer then
        showRest = _MSUF_ReadBool(conf, g, "showRestingIndicator", false, "showRestedStateIndicator")
    end
    local showRez = _MSUF_ReadBool(conf, g, "showIncomingResIndicator", false)
    local combatIcon = frame.combatStateIndicatorIcon
    local restIcon = frame.restingIndicatorIcon
    local rezIcon = frame.incomingResIndicatorIcon
    local classIcon = frame.classificationIndicatorIcon
    local classText = frame.classificationIndicatorText
        -- Safety: Summon was removed; if any leftover texture exists, hard-hide it.
    local summonIcon = frame.summonIndicatorIcon
    if summonIcon and summonIcon.Hide then
        summonIcon:Hide()
    end
    -- Symbol textures (selected via Options -> Status icons)
    local useMidnight = _MSUF_GetStatusIconsUseMidnight(conf, g)
    local combatSymbol = _MSUF_ReadStr(conf, g, "combatStateIndicatorSymbol", "DEFAULT")
    local restSymbol   = _MSUF_ReadStr(conf, g, "restedStateIndicatorSymbol", "DEFAULT", "restingStateIndicatorSymbol")
    local rezSymbol    = _MSUF_ReadStr(conf, g, "incomingResIndicatorSymbol", "DEFAULT")
    -- Rested custom symbols get a gentle pulse to mimic Blizzard's feel.
    _MSUF_ApplyStatusIconSymbolTexture(combatIcon, combatSymbol, useMidnight, false)
    _MSUF_ApplyStatusIconSymbolTexture(restIcon,   restSymbol,   useMidnight, (type(restSymbol) == "string" and string.find(restSymbol, "^rested_") ~= nil))
    _MSUF_ApplyStatusIconSymbolTexture(rezIcon,    rezSymbol,    useMidnight, false)
local combatOn = (showCombat and (testMode or ((UnitAffectingCombat and UnitAffectingCombat(unit)) and true or false)))
    local restOn = (showRest and (testMode or ((IsResting and IsResting()) and true or false)))
    local rezOn = (showRez and (testMode or ((UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)) and true or false)))
    -- Target classification (Boss/Elite/Rare)
    local showClass = false
    if frame._msufIsTarget then
        showClass = _MSUF_ReadBool(conf, g, "showClassificationIndicator", false)
    end
    local classState = nil
    if showClass then
        classState = testMode and "BOSS" or _MSUF_GetClassificationState(unit)
    end
    local classOn = (showClass and classState ~= nil)
    local iconAlpha = _MSUF_ReadNumber(conf, g, "stateIconsAlpha", 1)
    -- Combat layout
    local combatCorner = _MSUF_ReadStr(conf, g, "combatStateIndicatorAnchor", (type(g) == "table" and g.combatStateIndicatorPos) or "TOPLEFT", "combatStateIndicatorPos")
    local combatX = _MSUF_ReadNumber(conf, g, "combatStateIndicatorOffsetX", 0)
    local combatY = _MSUF_ReadNumber(conf, g, "combatStateIndicatorOffsetY", 0)
    local combatSize = _MSUF_ReadNumber(conf, g, "combatStateIndicatorSize", 18)
    if combatIcon then
        if combatOn then
            if combatIcon._msufSizeStamp ~= combatSize then
                combatIcon:SetSize(combatSize, combatSize)
                combatIcon._msufSizeStamp = combatSize
            end
            _MSUF_AnchorCorner(combatIcon, frame, combatCorner, combatX, combatY)
            combatIcon:SetAlpha(iconAlpha)
            combatIcon:Show()
        else
            combatIcon:Hide()
        end
    end
    if restIcon then
        if restOn then
            local restCorner = _MSUF_ReadStr(conf, g, "restedStateIndicatorAnchor", combatCorner)
            -- NOTE: Rested icon offsets are intentionally independent from combat offsets (no implicit inheritance).
            local restX = _MSUF_ReadNumber(conf, g, "restedStateIndicatorOffsetX", 0)
            local restY = _MSUF_ReadNumber(conf, g, "restedStateIndicatorOffsetY", 0)
            local restSize = _MSUF_ReadNumber(conf, g, "restedStateIndicatorSize", 18)
            if restIcon._msufSizeStamp ~= restSize then
                restIcon:SetSize(restSize, restSize)
                restIcon._msufSizeStamp = restSize
            end
	            -- NOTE: Do NOT auto-stack Rested under Combat.
	            -- Old profiles (pre-status-icons) don't have explicit Rested positioning keys yet;
	            -- auto-stacking caused the Rested icon to *shift* when Combat toggled on/off.
	            -- We always anchor Rested using its own configured corner + offsets.
	            _MSUF_AnchorCorner(restIcon, frame, restCorner, restX, restY)
            restIcon:SetAlpha(iconAlpha)
            restIcon:Show()
        else
            _MSUF_StopPulseAnim(restIcon)
            restIcon:Hide()
        end
    end
    if rezIcon then
        if rezOn then
            local rezCorner = _MSUF_ReadStr(conf, g, "incomingResIndicatorAnchor", (type(g) == "table" and g.incomingResIndicatorPos) or "TOPRIGHT", "incomingResIndicatorPos")
            local rezX = _MSUF_ReadNumber(conf, g, "incomingResIndicatorOffsetX", 0)
            local rezY = _MSUF_ReadNumber(conf, g, "incomingResIndicatorOffsetY", 0)
            local rezSize = _MSUF_ReadNumber(conf, g, "incomingResIndicatorSize", 18)
            if rezIcon._msufSizeStamp ~= rezSize then
                rezIcon:SetSize(rezSize, rezSize)
                rezIcon._msufSizeStamp = rezSize
            end
            _MSUF_AnchorCorner(rezIcon, frame, rezCorner, rezX, rezY)
            rezIcon:SetAlpha(iconAlpha)
            rezIcon:Show()
        else
            rezIcon:Hide()
        end
    end
    -- Classification indicator: always render as TEXT (reliable even without Media assets)
    -- Keep the texture slot hidden for future icon assets.
    if classIcon and classIcon.Hide then
        classIcon:Hide()
    end
    if classText then
        if classOn then
            local classCorner = _MSUF_ReadStr(conf, g, "classificationIndicatorAnchor", "TOPLEFT")
            local classX = _MSUF_ReadNumber(conf, g, "classificationIndicatorOffsetX", 0)
            local classY = _MSUF_ReadNumber(conf, g, "classificationIndicatorOffsetY", 0)
            local classSize = _MSUF_ReadNumber(conf, g, "classificationIndicatorSize", 18)
            if type(classSize) ~= "number" then classSize = 18 end
            if classSize < 8 then classSize = 8 end
            if classSize > 64 then classSize = 64 end
            classSize = math.floor(classSize + 0.5)
            -- Size is now a FONT size; trigger the shared font pipeline when it changes.
            if classText._msufClassSizeStamp ~= classSize then
                classText._msufClassSizeStamp = classSize
                if type(_G.MSUF_UpdateAllFonts_Immediate) == "function" then
                    _G.MSUF_UpdateAllFonts_Immediate()
                elseif type(_G.MSUF_UpdateAllFonts) == "function" then
                    _G.MSUF_UpdateAllFonts()
                elseif type(_G.UpdateAllFonts) == "function" then
                    _G.UpdateAllFonts()
                end
            end
            _MSUF_AnchorCorner(classText, frame, classCorner, classX, classY)
            classText:SetAlpha(iconAlpha)
            -- Justification (avoids looking off on right anchors)
            if classText.SetJustifyH then
                local j = "LEFT"
                if classCorner == "CENTER" then
                    j = "CENTER"
                elseif classCorner == "TOPRIGHT" or classCorner == "BOTTOMRIGHT" then
                    j = "RIGHT"
                end
                if classText._msufJustifyStamp ~= j then
                    classText:SetJustifyH(j)
                    classText._msufJustifyStamp = j
                end
            end
            local txt = _MSUF_GetClassificationLabel(classState)
            if type(_G.MSUF_SetTextIfChanged) == "function" then
                _G.MSUF_SetTextIfChanged(classText, txt)
            else
                classText:SetText(txt)
            end
            classText:Show()
        else
            if type(_G.MSUF_SetTextIfChanged) == "function" then
                _G.MSUF_SetTextIfChanged(classText, "")
            else
                classText:SetText("")
            end
            classText:Hide()
        end
    end
 end
-- ------------------------------------------------------------
-- Status text update (calls status icons update at the end)
-- ------------------------------------------------------------
function MSUF_UpdateStatusIndicatorForFrame(frame)
    if not frame or not frame.statusIndicatorText then
         return
    end
    local unit = frame.unit
    local db = _G.MSUF_GetStatusIndicatorDB and _G.MSUF_GetStatusIndicatorDB() or nil
    db = (type(db) == "table") and db or {}
    local showAFK   = (db.showAFK == true)
    local showDND   = (db.showDND == true)
    local showDead  = (db.showDead == true)   -- also covers OFFLINE
    local showGhost = (db.showGhost == true)
    local txt = ""
    if unit and UnitExists and UnitExists(unit) then
        if showDead and UnitIsConnected and (UnitIsConnected(unit) == false) then
            txt = "OFFLINE"
        elseif showGhost and UnitIsGhost and UnitIsGhost(unit) then
            txt = "GHOST"
        elseif showDead then
            local isDead = false
            if UnitIsDead and UnitIsDead(unit) then
                isDead = true
            elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
                isDead = true
            end
            if isDead and (not (UnitIsGhost and UnitIsGhost(unit))) then
                txt = "DEAD"
            end
        end
	    if txt == "" and (showAFK or showDND) then
	        -- Midnight/Beta (12.0+): UnitIsAFK/UnitIsDND can return *secret booleans*
	        -- during combat/encounters, which hard-error on boolean tests.
	        -- We suppress AFK/DND checks while locked down (cached via events; see file top).
	        if ns._msufAwaySuppressed ~= true then
	            if showAFK and UnitIsAFK then
	                local afk = UnitIsAFK(unit)
                    if issecretvalue and issecretvalue(afk) then
                        afk = nil
                    end
                    if afk then
	                    txt = "AFK"
	                end
	            end
	            if txt == "" and showDND and UnitIsDND then
	                local dnd = UnitIsDND(unit)
                    if issecretvalue and issecretvalue(dnd) then
                        dnd = nil
                    end
                    if dnd then
	                    txt = "DND"
	                end
	            end
	        end
	    end
    end
    local fs = frame.statusIndicatorText
    local ovText = frame.statusIndicatorOverlayText
    local ovFrame = frame.statusIndicatorOverlayFrame
    if ovText and ovFrame then
        if type(_G.MSUF_SetTextIfChanged) == "function" then
            _G.MSUF_SetTextIfChanged(ovText, "")
        else
            ovText:SetText("")
        end
        ovText:Hide()
        ovFrame:Hide()
    end
    if txt ~= "" then
        if type(_G.MSUF_SetTextIfChanged) == "function" then
            _G.MSUF_SetTextIfChanged(fs, txt)
        else
            fs:SetText(txt)
        end
        if fs.SetIgnoreParentAlpha then
            fs:SetIgnoreParentAlpha((txt == "OFFLINE" or txt == "DEAD"))
        end
        fs:SetAlpha(1)
        fs:Show()
    else
        if fs.SetIgnoreParentAlpha then
            fs:SetIgnoreParentAlpha(false)
        end
        fs:SetAlpha(1)
        if type(_G.MSUF_SetTextIfChanged) == "function" then
            _G.MSUF_SetTextIfChanged(fs, "")
        else
            fs:SetText("")
        end
        fs:Hide()
    end
    _MSUF_UpdateStatusIcons(frame)
 end
-- Public refresh helper
_G.MSUF_RefreshStatusIndicators = function()
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= "table" then
         return
    end
    for _, f in pairs(frames) do
        MSUF_UpdateStatusIndicatorForFrame(f)
    end
 end
-- Keep a compatibility stub because older code may call this helper.
do
    local function _MSUF_StopStatusIndicatorTicker()
        local t = _G.MSUF_StatusIndicatorTicker
        if t and t.Cancel then
            t:Cancel()
        end
        _G.MSUF_StatusIndicatorTicker = nil
     end
    _G.MSUF_EnsureStatusIndicatorTicker = function()
        _MSUF_StopStatusIndicatorTicker()
     end
    _MSUF_StopStatusIndicatorTicker()
end
-- ------------------------------------------------------------
-- Shared API: Status Icons Test Mode
-- Used by Frames menus (Player/Target) and the MSUF Edit Mode panel.
-- ------------------------------------------------------------
do
    local function _MSUF_RequestUFUpdate(key, reason)
        local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
        local fr = (uf and key) and uf[key] or nil
        if fr then
            if type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                _G.MSUF_RequestUnitframeUpdate(fr, true, true, reason or "StatusIconsTestMode")
            elseif type(_G.UpdateSimpleUnitFrame) == "function" then
                _G.UpdateSimpleUnitFrame(fr)
            end
        end
     end
    function _G.MSUF_GetStatusIconsTestMode()
        if type(_G.EnsureDB) == "function" then _G.EnsureDB() end
        local db = _G.MSUF_DB
        local g = (type(db) == "table") and db.general or nil
        return (type(g) == "table" and g.stateIconsTestMode == true) or false
    end
    function _G.MSUF_SetStatusIconsTestMode(enabled, reason)
        if type(_G.EnsureDB) == "function" then _G.EnsureDB() end
        local db = _G.MSUF_DB
        if type(db) ~= "table" then  return end
        db.general = (type(db.general) == "table") and db.general or {}
        db.general.stateIconsTestMode = (enabled and true) or false
        if type(_G.MSUF_RefreshStatusIconsOptionsUI) == "function" then
            _G.MSUF_RefreshStatusIconsOptionsUI()
        end
        _MSUF_RequestUFUpdate("player", reason or "StatusIconsTestMode")
        _MSUF_RequestUFUpdate("target", reason or "StatusIconsTestMode")
     end
end
