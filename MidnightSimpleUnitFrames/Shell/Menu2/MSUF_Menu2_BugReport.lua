local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local BR = M.BugReport or {}
M.BugReport = BR

local ADDON_NAME = addonName or "MidnightSimpleUnitFrames"
local GITHUB_ISSUE_URL = "https://github.com/Mapkov2/MidnightSimpleUnitFrames/issues/new"
local DISCORD_URL = "https://discord.gg/2Gf9b2Wprz"
local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/midnightsimpleunitframes"
local BUGSACK_URL = "https://www.curseforge.com/wow/addons/bugsack"
local SECRET_TEXT = "<restricted by WoW 12.0 Secret Values>"

local currentReport
local cachedBug
local manualIssueType
local manualDescription

local function Tr(text)
    return M.Tr and M.Tr(text) or tostring(text or "")
end

local function SafePCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function IsSecretValue(value)
    if type(_G.issecretvalue) ~= "function" then return false end
    local ok, result = pcall(_G.issecretvalue, value)
    return ok and result == true
end

local function CanAccessTable(value)
    if type(value) ~= "table" then return false end
    if type(_G.canaccesstable) ~= "function" then return true end
    local ok, result = pcall(_G.canaccesstable, value)
    return ok and result == true
end

local function LimitText(text, maxLen)
    text = tostring(text or "")
    maxLen = tonumber(maxLen) or 12000
    if #text <= maxLen then return text end
    return text:sub(1, maxLen) .. "\n... <truncated " .. tostring(#text - maxLen) .. " chars>"
end

local function OneLine(text, fallback)
    text = tostring(text or fallback or "")
    text = text:gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text ~= "" and text or tostring(fallback or "n/a")
end

local function ValueText(value, fallback)
    if IsSecretValue(value) then return SECRET_TEXT end
    if value == nil then return fallback or "n/a" end
    local t = type(value)
    if t == "string" then return value ~= "" and value or (fallback or "n/a") end
    if t == "number" then return tostring(value) end
    if t == "boolean" then return value and "true" or "false" end
    return tostring(value)
end

local function SafeValue(label, fn, ...)
    local ok, value = SafePCall(fn, ...)
    if not ok then return label and ("error: " .. tostring(value)) or nil end
    return ValueText(value)
end

local function Add(lines, text)
    lines[#lines + 1] = tostring(text or "")
end

local function AddKV(lines, key, value)
    Add(lines, tostring(key or "Value") .. ": " .. ValueText(value))
end

local function AddHeader(lines, title)
    Add(lines, "")
    Add(lines, "=== " .. tostring(title or "Section") .. " ===")
end

local function AddCallKV(lines, key, fn, arg)
    if type(fn) ~= "function" then return end
    AddKV(lines, key, arg ~= nil and SafeValue(nil, fn, arg) or SafeValue(nil, fn))
end

local function AddMethodKV(lines, key, owner, method, arg)
    if owner and type(owner[method]) == "function" then AddCallKV(lines, key, owner[method], arg) end
end

local function SafeTableValue(tbl, key)
    if type(tbl) ~= "table" or not CanAccessTable(tbl) then return nil end
    local ok, value = pcall(function() return tbl[key] end)
    if ok and not IsSecretValue(value) then return value end
    return nil
end

local function TableKeyCount(tbl, limit)
    if type(tbl) ~= "table" or not CanAccessTable(tbl) then return nil end
    local count = 0
    local ok = pcall(function()
        for _ in pairs(tbl) do
            count = count + 1
            if limit and count >= limit then break end
        end
    end)
    if ok then return count end
    return nil
end

local function FrameCall(frame, method)
    if frame == nil then return nil end
    local okMethod, fn = pcall(function() return frame[method] end)
    if not okMethod or type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, frame)
    if ok then return value end
    return nil
end

local function SizeText(w, h)
    if w == nil and h == nil then return nil end
    return ValueText(w) .. " x " .. ValueText(h)
end

local function DateText()
    if type(_G.date) ~= "function" then return "n/a" end
    local ok, value = pcall(_G.date, "%Y-%m-%d %H:%M:%S")
    return ok and tostring(value or "n/a") or "n/a"
end

local function InCombat()
    return ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
end

local function AddOnLoaded(name)
    local C = _G.C_AddOns
    if not (C and type(C.IsAddOnLoaded) == "function") then return false end
    local ok, loadedOrLoading, loaded = pcall(C.IsAddOnLoaded, name)
    return ok and (loadedOrLoading == true or loaded == true) or false
end

local function AddOnMetadata(name, field)
    local C = _G.C_AddOns
    if not (C and type(C.GetAddOnMetadata) == "function") then return nil end
    local ok, value = pcall(C.GetAddOnMetadata, name, field)
    if ok then return value end
end

local function IntegrationStatus()
    return {
        bugGrabberLoaded = AddOnLoaded("BugGrabber"),
        bugSackLoaded = AddOnLoaded("BugSack"),
        bugGrabberVersion = AddOnMetadata("BugGrabber", "Version"),
        bugSackVersion = AddOnMetadata("BugSack", "Version"),
    }
end

local function IsMSUFErrorText(text)
    text = tostring(text or ""):lower()
    return text:find("midnightsimpleunitframes", 1, true)
        or text:find("interface\\addons\\midnightsimpleunitframes", 1, true)
        or text:find("interface/addons/midnightsimpleunitframes", 1, true)
        or text:find("msuf", 1, true)
end

local ERROR_FIELDS = {
    "message", "error", "text", "stack", "stacktrace", "trace", "locals",
    "counter", "count", "session", "time", "addon", "source",
}

local function TableErrorText(value)
    if type(value) ~= "table" or not CanAccessTable(value) then return "" end
    local parts = {}
    for i = 1, #ERROR_FIELDS do
        local key = ERROR_FIELDS[i]
        local ok, field = pcall(function() return value[key] end)
        if ok and field ~= nil and not IsSecretValue(field) then
            parts[#parts + 1] = tostring(key) .. ": " .. LimitText(ValueText(field), 6000)
        end
    end
    local ok, first = pcall(function() return value[1] end)
    if ok and first ~= nil and not IsSecretValue(first) then
        parts[#parts + 1] = "1: " .. LimitText(ValueText(first), 6000)
    end
    return table.concat(parts, "\n")
end

local function AddBugCandidate(candidates, value, path, depth)
    if #candidates >= 40 then return end
    if IsSecretValue(value) then return end
    local valueType = type(value)
    if valueType == "string" then
        if IsMSUFErrorText(value) then
            candidates[#candidates + 1] = { source = path, text = LimitText(value, 16000) }
        end
        return
    end
    if valueType ~= "table" or depth > 3 or not CanAccessTable(value) then return end

    local text = TableErrorText(value)
    if text ~= "" and IsMSUFErrorText(text) then
        candidates[#candidates + 1] = { source = path, text = LimitText(text, 16000) }
    end

    local scanned = 0
    for key, child in pairs(value) do
        scanned = scanned + 1
        if scanned > 100 then break end
        AddBugCandidate(candidates, child, tostring(path or "source") .. "." .. tostring(key), depth + 1)
        if #candidates >= 40 then return end
    end
end

local function TryMethodSource(candidates, sourceName, obj)
    if type(obj) ~= "table" or not CanAccessTable(obj) then return end
    local methodNames = {
        "GetSessionDB", "GetDB", "GetErrors", "GetError", "GetLastError",
        "GetLatestError", "GetCapturedErrors", "GetBugs",
    }
    for i = 1, #methodNames do
        local methodName = methodNames[i]
        local fn = obj[methodName]
        if type(fn) == "function" then
            local ok, value = pcall(fn, obj)
            if not ok then ok, value = pcall(fn) end
            if ok and value ~= nil then
                AddBugCandidate(candidates, value, sourceName .. ":" .. methodName, 0)
            end
        end
    end
end

local function AddLibStubSource(sources)
    if type(_G.LibStub) ~= "function" then return end
    local ok, lib = pcall(_G.LibStub, "BugGrabber-2.0", true)
    if ok and type(lib) == "table" then
        sources[#sources + 1] = { name = "LibStub:BugGrabber-2.0", value = lib }
    end
end

local function FindLatestMSUFError()
    if currentReport then return currentReport end
    if InCombat() then return cachedBug end
    local candidates = {}
    local sources = {}
    AddLibStubSource(sources)
    sources[#sources + 1] = { name = "_G.BugGrabber", value = _G.BugGrabber }
    sources[#sources + 1] = { name = "_G.BugGrabberDB", value = _G.BugGrabberDB }
    sources[#sources + 1] = { name = "_G.BugSackDB", value = _G.BugSackDB }

    for i = 1, #sources do
        local src = sources[i]
        TryMethodSource(candidates, src.name, src.value)
        AddBugCandidate(candidates, src.value, src.name, 0)
    end

    local latest = candidates[#candidates]
    if latest then
        cachedBug = {
            source = latest.source or "BugGrabber",
            errorText = latest.text or "",
            createdAt = DateText(),
        }
        return cachedBug
    end
    return nil
end

local function SpecText()
    local C = _G.C_SpecializationInfo
    if not (C and type(C.GetSpecialization) == "function") then return "n/a" end
    local ok, specIndex = pcall(C.GetSpecialization)
    if not ok or not specIndex then return "n/a" end
    if type(C.GetSpecializationInfo) ~= "function" then return tostring(specIndex) end
    local okInfo, specID, name, _, _, role = pcall(C.GetSpecializationInfo, specIndex)
    if not okInfo then return tostring(specIndex) end
    return OneLine((ValueText(name) .. " (" .. ValueText(specID) .. ", " .. ValueText(role) .. ")"), tostring(specIndex))
end

local function AddClientContext(lines)
    AddHeader(lines, "Client")
    AddKV(lines, "MSUF version", AddOnMetadata(ADDON_NAME, "Version"))
    if type(_G.GetBuildInfo) == "function" then
        local ok, version, build, buildDate, interfaceVersion, localizedVersion, buildInfo = pcall(_G.GetBuildInfo)
        if ok then
            AddKV(lines, "WoW version", version)
            AddKV(lines, "Build", build)
            AddKV(lines, "Build date", buildDate)
            AddKV(lines, "Interface", interfaceVersion)
            AddKV(lines, "Localized version", localizedVersion)
            AddKV(lines, "Build info", buildInfo)
        end
    end
    AddCallKV(lines, "Locale", _G.GetLocale)
    if type(_G.GetCVar) == "function" then
        for _, key in ipairs({ "useUiScale", "uiScale" }) do AddCallKV(lines, key, _G.GetCVar, key) end
    end
end

local function AddPlayerContext(lines)
    AddHeader(lines, "Player")
    if type(_G.UnitClassBase) == "function" then
        local ok, classFile, classID = pcall(_G.UnitClassBase, "player")
        if ok then
            AddKV(lines, "Class", ValueText(classFile) .. " (" .. ValueText(classID) .. ")")
        end
    elseif type(_G.UnitClass) == "function" then
        local ok, _, classFile, classID = pcall(_G.UnitClass, "player")
        if ok then AddKV(lines, "Class", ValueText(classFile) .. " (" .. ValueText(classID) .. ")") end
    end
    AddKV(lines, "Spec", SpecText())
    AddCallKV(lines, "Level", _G.UnitLevel, "player")
    if type(_G.UnitRace) == "function" then
        local ok, _, race, raceID = pcall(_G.UnitRace, "player")
        if ok then AddKV(lines, "Race", ValueText(race) .. " (" .. ValueText(raceID) .. ")") end
    end
    AddCallKV(lines, "Faction", _G.UnitFactionGroup, "player")
    AddCallKV(lines, "Assigned role", _G.UnitGroupRolesAssigned, "player")
end

local function AddSituationContext(lines)
    AddHeader(lines, "Situation")
    AddCallKV(lines, "Zone", _G.GetZoneText)
    AddCallKV(lines, "Subzone", _G.GetSubZoneText)
    AddMethodKV(lines, "Map ID", _G.C_Map, "GetBestMapForUnit", "player")
    if type(_G.IsInInstance) == "function" then
        local ok, inInstance, instanceType = pcall(_G.IsInInstance)
        if ok then
            AddKV(lines, "In instance", inInstance)
            AddKV(lines, "Instance type", instanceType)
        end
    end
    if type(_G.GetInstanceInfo) == "function" then
        local ok, name, instanceType, difficultyID, difficultyName, maxPlayers, _, _, instanceID, instanceGroupSize, lfgDungeonID, hasWorldTier = pcall(_G.GetInstanceInfo)
        if ok then
            AddKV(lines, "Instance name", name)
            AddKV(lines, "Instance info type", instanceType)
            AddKV(lines, "Difficulty", ValueText(difficultyName) .. " (" .. ValueText(difficultyID) .. ")")
            AddKV(lines, "Max players", maxPlayers)
            AddKV(lines, "Instance ID", instanceID)
            AddKV(lines, "Instance group size", instanceGroupSize)
            AddKV(lines, "LFG dungeon ID", lfgDungeonID)
            AddKV(lines, "Has world tier", hasWorldTier)
        end
    end
    AddCallKV(lines, "InCombatLockdown", _G.InCombatLockdown)
    AddCallKV(lines, "Player affecting combat", _G.UnitAffectingCombat, "player")
    AddCallKV(lines, "Mounted", _G.IsMounted)
    AddCallKV(lines, "In vehicle", _G.UnitInVehicle, "player")
    AddCallKV(lines, "Dead or ghost", _G.UnitIsDeadOrGhost, "player")
    AddCallKV(lines, "Resting", _G.IsResting)
    AddCallKV(lines, "In group", _G.IsInGroup)
    AddCallKV(lines, "In raid", _G.IsInRaid)
    AddMethodKV(lines, "War mode desired", _G.C_PvP, "IsWarModeDesired")
    AddMethodKV(lines, "Challenge mode active", _G.C_ChallengeMode, "IsChallengeModeActive")
    AddMethodKV(lines, "Encounter in progress", _G.C_InstanceEncounter, "IsEncounterInProgress")
    AddMethodKV(lines, "Combat log restricted", _G.C_CombatLog, "IsCombatLogRestricted")
end

local function AddRuntimeContext(lines)
    AddHeader(lines, "Runtime / Restrictions")
    AddCallKV(lines, "InCombatLockdown", _G.InCombatLockdown)
    AddCallKV(lines, "Player affecting combat", _G.UnitAffectingCombat, "player")
    AddKV(lines, "issecretvalue API", type(_G.issecretvalue) == "function")
    AddKV(lines, "canaccesstable API", type(_G.canaccesstable) == "function")
    AddKV(lines, "CopyToClipboard API", type(_G.CopyToClipboard) == "function")
    AddMethodKV(lines, "Combat log restricted", _G.C_CombatLog, "IsCombatLogRestricted")
    AddMethodKV(lines, "Chat messaging lockdown", _G.C_ChatInfo, "InChatMessagingLockdown")
    AddMethodKV(lines, "Limited input allowed", _G.C_LimitedInput, "LimitedInputAllowed")
    AddMethodKV(lines, "AddOn restriction active", _G.C_RestrictedActions, "IsAddOnRestrictionActive")
    AddMethodKV(lines, "Secret restrictions active", _G.C_Secrets, "HasSecretRestrictions")
end

local UI_CVARS = {
    "useUiScale", "uiScale", "gxWindow", "gxMaximize", "gxResolution",
    "graphicsQuality", "raidFramesDisplayClassColor", "raidFramesDisplayPowerBars",
    "raidFramesHealthText", "showPartyBackground", "showPartyPets",
    "showTargetOfTarget", "nameplateShowEnemies", "nameplateShowFriends",
    "nameplateShowPersonalCooldowns", "NamePlatePersonalShowAlways",
    "NamePlatePersonalShowInCombat", "nameplateResourceOnTarget",
}

local function AddUIContext(lines)
    AddHeader(lines, "UI")
    local screenW = type(_G.GetScreenWidth) == "function" and SafeValue(nil, _G.GetScreenWidth) or nil
    local screenH = type(_G.GetScreenHeight) == "function" and SafeValue(nil, _G.GetScreenHeight) or nil
    AddKV(lines, "Logical screen", SizeText(screenW, screenH))
    if type(_G.GetPhysicalScreenSize) == "function" then
        local ok, physicalW, physicalH = pcall(_G.GetPhysicalScreenSize)
        if ok then AddKV(lines, "Physical screen", SizeText(physicalW, physicalH)) end
    end

    local parent = _G.UIParent
    AddKV(lines, "UIParent size", SizeText(FrameCall(parent, "GetWidth"), FrameCall(parent, "GetHeight")))
    AddKV(lines, "UIParent scale", FrameCall(parent, "GetScale"))
    AddKV(lines, "UIParent effective scale", FrameCall(parent, "GetEffectiveScale"))

    local menuFrame = M.frame or M.root or M.window
    AddKV(lines, "Menu frame shown", menuFrame and FrameCall(menuFrame, "IsShown") or nil)
    AddKV(lines, "Menu frame size", SizeText(FrameCall(menuFrame, "GetWidth"), FrameCall(menuFrame, "GetHeight")))
    AddKV(lines, "Menu frame scale", FrameCall(menuFrame, "GetScale"))
    AddKV(lines, "Menu frame effective scale", FrameCall(menuFrame, "GetEffectiveScale"))

    if type(_G.GetCVar) ~= "function" then
        Add(lines, "CVar API unavailable.")
        return
    end
    Add(lines, "")
    Add(lines, "CVars:")
    for i = 1, #UI_CVARS do
        local key = UI_CVARS[i]
        AddKV(lines, key, SafeValue(nil, _G.GetCVar, key))
    end
end

local UNIT_TOKENS = {
    "player", "target", "targettarget", "focus", "focustarget", "pet",
    "boss1", "boss2", "boss3", "boss4", "boss5",
    "arena1", "arena2", "arena3", "arena4", "arena5",
    "party1", "party2", "party3", "party4",
    "raid1", "raid2", "raid5", "raid10", "raid20", "raid30", "raid40",
}

local function UnitFlag(fn, unit, fallback)
    if type(fn) ~= "function" then return "n/a" end
    local ok, value = pcall(fn, unit)
    if ok then return ValueText(value, fallback or "false") end
    return "error"
end

local function AddUnitTokenContext(lines)
    AddHeader(lines, "Unit Tokens")
    AddCallKV(lines, "Group members", _G.GetNumGroupMembers)
    AddCallKV(lines, "Party members", _G.GetNumSubgroupMembers)
    if type(_G.UnitExists) ~= "function" then
        Add(lines, "Unit API unavailable.")
        return
    end
    for i = 1, #UNIT_TOKENS do
        local unit = UNIT_TOKENS[i]
        Add(lines, "- " .. unit
            .. ": exists=" .. UnitFlag(_G.UnitExists, unit, "false")
            .. ", visible=" .. UnitFlag(_G.UnitIsVisible, unit, "n/a")
            .. ", connected=" .. UnitFlag(_G.UnitIsConnected, unit, "n/a")
            .. ", dead=" .. UnitFlag(_G.UnitIsDeadOrGhost, unit, "false")
            .. ", vehicle=" .. UnitFlag(_G.UnitInVehicle, unit, "false"))
    end
end

local function AddMSUFContext(lines)
    AddHeader(lines, "MSUF")
    AddKV(lines, "Active profile", _G.MSUF_ActiveProfile or "Default")
    AddKV(lines, "Menu page", M.activeKey or "home")
    AddKV(lines, "Dashboard bug panel open", M.dashboardBugReportOpen == true)
    local edit = _G.MSUF_EditState
    if type(edit) == "table" then
        AddKV(lines, "Edit mode active", edit.active == true)
        AddKV(lines, "Edit popup open", edit.popupOpen == true)
        AddKV(lines, "Edit unit", edit.unitKey)
    end
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) == "table" then
        AddKV(lines, "MSUF frame scale", g.msufUiScale)
        AddKV(lines, "Menu scale", g.slashMenuScale)
        AddKV(lines, "Bar mode", g.barMode)
        AddKV(lines, "Dark mode", g.darkMode == true)
    end
end

local DB_SUMMARY_SECTIONS = {
    "general", "bars", "player", "target", "targettarget", "tot", "focus",
    "focustarget", "pet", "boss", "party", "raid", "mythicraid",
    "gf_party", "gf_raid", "gf_mythicraid", "auras3", "gameplay",
    "classColors", "npcColors",
}

local DB_SUMMARY_FIELDS = {
    "enabled", "show", "visible", "width", "height", "scale", "alpha",
    "x", "y", "point", "relativePoint", "relativeTo", "anchor", "anchorName",
    "offsetX", "offsetY", "barMode", "hpMode", "powerMode", "fontKey",
    "barTexture", "showName", "showHealth", "showPower", "showCastbar",
    "showPlayerPowerBar", "showTargetPowerBar", "showFocusPowerBar",
    "showBossPowerBar", "enablePlayerCastbar", "enableTargetCastbar",
    "enableFocusCastbar", "enableBossCastbar", "castbarGlobalWidth",
    "castbarGlobalHeight", "bossCastbarWidth", "bossCastbarHeight",
    "hideBlizzardPlayer", "hideBlizzardTarget", "hideBlizzardFocus",
    "hideBlizzardBoss", "darkMode", "msufUiScale", "slashMenuScale",
}

local function AddDBSummaryLine(lines, label, tbl)
    if type(tbl) ~= "table" or not CanAccessTable(tbl) then
        Add(lines, "- " .. label .. ": missing")
        return
    end
    local parts = { "keys=" .. ValueText(TableKeyCount(tbl, 1000)) }
    for i = 1, #DB_SUMMARY_FIELDS do
        local key = DB_SUMMARY_FIELDS[i]
        local value = SafeTableValue(tbl, key)
        local valueType = type(value)
        if value ~= nil and valueType ~= "table" and valueType ~= "function" and valueType ~= "userdata" then
            parts[#parts + 1] = key .. "=" .. OneLine(ValueText(value), "n/a")
        end
    end
    Add(lines, "- " .. label .. ": " .. table.concat(parts, ", "))
end

local function AddMSUFDBContext(lines)
    AddHeader(lines, "MSUF DB Summary")
    local db = _G.MSUF_DB
    if type(db) ~= "table" or not CanAccessTable(db) then
        Add(lines, "MSUF_DB unavailable.")
        return
    end
    AddKV(lines, "Top-level keys", TableKeyCount(db, 1000))
    for i = 1, #DB_SUMMARY_SECTIONS do
        local key = DB_SUMMARY_SECTIONS[i]
        AddDBSummaryLine(lines, key, SafeTableValue(db, key))
    end
    local auras = SafeTableValue(db, "auras3")
    if type(auras) == "table" then
        AddDBSummaryLine(lines, "auras3.shared", SafeTableValue(auras, "shared"))
    end
end

local function AddFrameSummaryLine(lines, label, frame)
    if not frame then
        Add(lines, "- " .. tostring(label or "frame") .. ": missing")
        return
    end
    local parts = {
        "shown=" .. ValueText(FrameCall(frame, "IsShown")),
        "visible=" .. ValueText(FrameCall(frame, "IsVisible")),
        "size=" .. ValueText(SizeText(FrameCall(frame, "GetWidth"), FrameCall(frame, "GetHeight"))),
        "scale=" .. ValueText(FrameCall(frame, "GetScale")),
        "effectiveScale=" .. ValueText(FrameCall(frame, "GetEffectiveScale")),
        "points=" .. ValueText(FrameCall(frame, "GetNumPoints")),
    }
    local unit = SafeTableValue(frame, "unit")
    local key = SafeTableValue(frame, "key") or SafeTableValue(frame, "MSUFKey") or SafeTableValue(frame, "unitKey")
    if unit ~= nil then parts[#parts + 1] = "unit=" .. OneLine(ValueText(unit), "n/a") end
    if key ~= nil then parts[#parts + 1] = "key=" .. OneLine(ValueText(key), "n/a") end
    Add(lines, "- " .. tostring(label or "frame") .. ": " .. table.concat(parts, ", "))
end

local function AddMSUFFrameContext(lines)
    AddHeader(lines, "MSUF Frames")
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= "table" or not CanAccessTable(frames) then
        Add(lines, "MSUF_UnitFrames registry unavailable.")
    else
        local rows = {}
        local ok = pcall(function()
            for key, frame in pairs(frames) do
                rows[#rows + 1] = { key = tostring(key), frame = frame }
                if #rows >= 40 then break end
            end
        end)
        if ok and #rows > 0 then
            table.sort(rows, function(a, b) return a.key < b.key end)
            for i = 1, #rows do
                AddFrameSummaryLine(lines, rows[i].key, rows[i].frame)
            end
        else
            Add(lines, "No unit frames registered.")
        end
    end

    Add(lines, "")
    Add(lines, "Castbar globals:")
    AddFrameSummaryLine(lines, "MSUF_PlayerCastbar", _G.MSUF_PlayerCastbar or _G.MSUF_PlayerCastBar)
    AddFrameSummaryLine(lines, "MSUF_TargetCastbar", _G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar)
    AddFrameSummaryLine(lines, "MSUF_FocusCastbar", _G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar)
    AddFrameSummaryLine(lines, "MSUF_BossCastbar1", _G.MSUF_BossCastbar1 or _G.MSUF_Boss1CastBar)
end

local function AddPerformance(lines)
    AddHeader(lines, "Performance")
    local fps = type(_G.GetFramerate) == "function" and SafeValue(nil, _G.GetFramerate) or "n/a"
    AddKV(lines, "FPS", fps)
    if type(_G.GetNetStats) == "function" then
        local ok, bandwidthIn, bandwidthOut, latencyHome, latencyWorld = pcall(_G.GetNetStats)
        if ok then
            AddKV(lines, "Bandwidth in KB/s", bandwidthIn)
            AddKV(lines, "Bandwidth out KB/s", bandwidthOut)
            AddKV(lines, "Latency home ms", latencyHome)
            AddKV(lines, "Latency world ms", latencyWorld)
        end
    end
    if type(_G.UpdateAddOnMemoryUsage) == "function" then pcall(_G.UpdateAddOnMemoryUsage) end
    AddCallKV(lines, "MSUF memory KB", _G.GetAddOnMemoryUsage, ADDON_NAME)
end

local IMPORTANT_ADDONS = {
    "MidnightSimpleUnitFrames", "BugGrabber", "BugSack",
    "WeakAuras", "WeakAurasOptions", "ElvUI", "ElvUI_Libraries",
    "Cell", "VuhDo", "Grid2", "Clique", "Masque", "Plater",
    "Details", "Details_DataStorage", "OmniCD", "Bartender4",
    "ShadowedUnitFrames", "PitBull4", "ZPerl", "HealBot",
    "BigWigs", "DBM-Core", "MRT", "MethodRaidTools",
}

local function AddOnInfoByName(name)
    local C = _G.C_AddOns
    if not (C and type(C.GetAddOnInfo) == "function") then return nil end
    local ok, addonNameValue, title, notes, loadable, reason, security, newVersion = pcall(C.GetAddOnInfo, name)
    if not ok or addonNameValue == nil then return nil end
    return {
        name = addonNameValue,
        title = title,
        notes = notes,
        loadable = loadable,
        reason = reason,
        security = security,
        newVersion = newVersion,
        version = AddOnMetadata(addonNameValue, "Version") or AddOnMetadata(name, "Version"),
        loaded = AddOnLoaded(addonNameValue) or AddOnLoaded(name),
    }
end

local function AddImportantAddOns(lines)
    AddHeader(lines, "Important AddOns")
    local C = _G.C_AddOns
    if not (C and type(C.GetAddOnInfo) == "function") then
        Add(lines, "AddOn API unavailable.")
        return
    end
    for i = 1, #IMPORTANT_ADDONS do
        local wanted = IMPORTANT_ADDONS[i]
        local info = AddOnInfoByName(wanted)
        if info then
            Add(lines, "- " .. wanted
                .. ": installed=true"
                .. ", loaded=" .. ValueText(info.loaded)
                .. ", version=" .. OneLine(info.version, "no version")
                .. ", title=" .. OneLine(info.title, wanted)
                .. ", loadable=" .. ValueText(info.loadable)
                .. ", reason=" .. OneLine(info.reason, "n/a"))
        else
            Add(lines, "- " .. wanted .. ": installed=false")
        end
    end
end

local function AddLoadedAddOns(lines)
    AddHeader(lines, "Loaded AddOns")
    local C = _G.C_AddOns
    if not (C and type(C.GetNumAddOns) == "function" and type(C.GetAddOnInfo) == "function") then
        Add(lines, "AddOn API unavailable.")
        return
    end
    local okCount, count = pcall(C.GetNumAddOns)
    if not okCount then
        Add(lines, "Could not read AddOn list: " .. tostring(count))
        return
    end
    local loaded = {}
    local problems = {}
    for i = 1, tonumber(count) or 0 do
        local okInfo, name, title, _, loadable, reason = pcall(C.GetAddOnInfo, i)
        if okInfo and name then
            local isLoaded = AddOnLoaded(name)
            local version = AddOnMetadata(name, "Version")
            if isLoaded then
                loaded[#loaded + 1] = OneLine(name) .. " | " .. OneLine(title, name) .. " | " .. OneLine(version, "no version")
            elseif loadable == false or reason ~= nil then
                problems[#problems + 1] = OneLine(name) .. " | " .. OneLine(reason, "not loaded")
            end
        end
    end
    table.sort(loaded)
    table.sort(problems)
    AddKV(lines, "Installed count", count)
    AddKV(lines, "Loaded count", #loaded)
    AddKV(lines, "Problem count", #problems)
    for i = 1, #loaded do Add(lines, "- " .. loaded[i]) end
    if #problems > 0 then
        Add(lines, "")
        Add(lines, "Not loaded / problem AddOns:")
        for i = 1, math.min(#problems, 40) do Add(lines, "- " .. problems[i]) end
        if #problems > 40 then Add(lines, "... " .. tostring(#problems - 40) .. " more") end
    end
end

local function AddBugSection(lines, bug)
    AddHeader(lines, "BugSack / BugGrabber")
    local status = IntegrationStatus()
    AddKV(lines, "BugGrabber loaded", status.bugGrabberLoaded)
    AddKV(lines, "BugGrabber version", status.bugGrabberVersion)
    AddKV(lines, "BugSack loaded", status.bugSackLoaded)
    AddKV(lines, "BugSack version", status.bugSackVersion)
    AddKV(lines, "Source", bug and bug.source or "n/a")
    Add(lines, "")
    Add(lines, bug and LimitText(bug.errorText or "", 18000) or "No MSUF error was available through BugGrabber/BugSack.")
end

local function AddUserReportSection(lines, bug)
    AddHeader(lines, "User Report")
    AddKV(lines, "Issue type", manualIssueType or (bug and "Lua error report" or "Manual report"))
    AddKV(lines, "Description", manualDescription or "Not provided")
end

function BR.GetLinks()
    return {
        github = GITHUB_ISSUE_URL,
        discord = DISCORD_URL,
        curseforge = CURSEFORGE_URL,
        bugsack = BUGSACK_URL,
    }
end

function BR.GetStatus()
    if InCombat() then
        if currentReport then return currentReport.dummy and "dummy" or "has_error", {} end
        return "combat_deferred", {}
    end
    if currentReport then
        return currentReport.dummy and "dummy" or "has_error", IntegrationStatus()
    end
    local integration = IntegrationStatus()
    if not (integration.bugGrabberLoaded or integration.bugSackLoaded) then
        return "missing", integration
    end
    if FindLatestMSUFError() then return "has_error", integration end
    return "clean", integration
end

function BR.BuildText(opts)
    opts = opts or {}
    if InCombat() then
        return "MSUF Bug Report\n\nReport generation is deferred while combat lockdown is active.\nOpen the dashboard again after combat to build the full report."
    end
    local bug = currentReport or cachedBug or FindLatestMSUFError()
    local lines = {}
    Add(lines, "MSUF Bug Report")
    AddKV(lines, "Generated", DateText())
    AddKV(lines, "Report kind", bug and (bug.dummy and "dummy" or "buggrabber") or "manual")

    AddUserReportSection(lines, bug)
    AddBugSection(lines, bug)
    AddMSUFContext(lines)
    AddClientContext(lines)
    AddPlayerContext(lines)
    AddSituationContext(lines)
    AddRuntimeContext(lines)
    AddUIContext(lines)
    AddUnitTokenContext(lines)
    AddMSUFDBContext(lines)
    AddMSUFFrameContext(lines)
    AddPerformance(lines)
    AddImportantAddOns(lines)
    if opts.includeLoadedAddons ~= false then AddLoadedAddOns(lines) end
    return table.concat(lines, "\n")
end

function BR.TriggerDummy()
    if InCombat() then return nil, "combat" end
    currentReport = {
        dummy = true,
        source = "MSUF dummy report",
        createdAt = DateText(),
        errorText = [[Message: Dummy MSUF bug report requested by /msuf bugdummy
Stack:
Interface/AddOns/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua:123: attempt to index field 'dummy' (a nil value)
Interface/AddOns/MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_BugReport.lua:1: in function 'MSUF_BugReport_TriggerDummy'

Locals:
unit = "player"
frameKey = "player"
component = "name"
combat = false]],
    }
    cachedBug = currentReport
    M.dashboardBugReportOpen = true
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("dashboardBugReportOpen", true)
    end
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    if type(M.ShowStatusFeedback) == "function" then
        M.ShowStatusFeedback("Dummy bug report created", "info", 1.6)
    end
    return currentReport
end

function BR.OpenManual()
    if InCombat() then return nil, "combat" end
    M.dashboardBugReportOpen = true
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("dashboardBugReportOpen", true)
    end
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    return true
end

function BR.SetManualIssue(issueType, description)
    if InCombat() then return nil, "combat" end
    if issueType ~= nil then manualIssueType = OneLine(issueType, "") end
    if description ~= nil then
        description = tostring(description or "")
        description = description:gsub("\r", " "):gsub("\n", " ")
        description = description:gsub("^%s+", ""):gsub("%s+$", "")
        manualDescription = description ~= "" and LimitText(description, 1200) or nil
    end
    return true
end

function BR.GetManualIssue()
    return manualIssueType, manualDescription
end

function BR.Clear()
    if InCombat() then return nil, "combat" end
    currentReport = nil
    cachedBug = nil
    manualIssueType = nil
    manualDescription = nil
    M.dashboardBugReportOpen = false
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("dashboardBugReportOpen", false)
    end
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
end

function _G.MSUF_BugReport_TriggerDummy()
    return BR.TriggerDummy()
end

function _G.MSUF_BugReport_GetStatus()
    return BR.GetStatus()
end

function _G.MSUF_BugReport_BuildText(opts)
    return BR.BuildText(opts)
end

function _G.MSUF_BugReport_Clear()
    return BR.Clear()
end

function _G.MSUF_BugReport_OpenManual()
    return BR.OpenManual()
end

function _G.MSUF_BugReport_SetManualIssue(issueType, description)
    return BR.SetManualIssue(issueType, description)
end

function _G.MSUF_BugReport_GetManualIssue()
    return BR.GetManualIssue()
end

function BR.IsCombatDeferred()
    return InCombat()
end

function _G.MSUF_BugReport_IsCombatDeferred()
    return BR.IsCombatDeferred()
end
