-- Profile export snapshots, selected-frame ownership and export preferences.
local _, MSUF = ...
local Parts = MSUF.ProfilesParts
local ExportPublic = Parts.ExportPublic
local MSUF_CopyGeneralSubset = Parts.MSUF_CopyGeneralSubset
local MSUF_CopyGroupFramePayload = Parts.MSUF_CopyGroupFramePayload
local MSUF_DeepCopy = Parts.MSUF_DeepCopy
local MSUF_GeneralKeysOfKind = Parts.MSUF_GeneralKeysOfKind
local MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA = Parts.MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
local MSUF_PROFILEIO_UNIT_KEYS = Parts.MSUF_PROFILEIO_UNIT_KEYS
local MSUF_ProfileIO_EnsureCompleteProfileDB = Parts.MSUF_ProfileIO_EnsureCompleteProfileDB
local MSUF_ProfileIO_MakeWagoSnapshot = Parts.MSUF_ProfileIO_MakeWagoSnapshot
local MSUF_ProfileIO_NormalizeGroupFramePayloadForExport = Parts.MSUF_ProfileIO_NormalizeGroupFramePayloadForExport
local MSUF_WipeTable = Parts.MSUF_WipeTable
local Variants = Parts.Variants
local MSUF_ProfileIO_GetProfileTable
local MSUF_ProfileIO_MaterializeProfileCopyForExport
--- direction: exports never carry general.blizzardEditModeSnapshot and
--- imports never apply it unless the profiles-page switch is on. Both flags
--- are session-transient by design — the user decides per session.
local MSUF_ProfileIO_ExportBlizzardEM = false
local MSUF_ProfileIO_ExportVariants = true
ExportPublic("MSUF_Profiles_SetExportVariants", function(value) MSUF_ProfileIO_ExportVariants=value==true end)
ExportPublic("MSUF_Profiles_SetExportBlizzardEditMode", function(value)
    MSUF_ProfileIO_ExportBlizzardEM = value == true
end)

-- Add a coordinate reference to export copies only. Older imports without the
-- explicit mode retain their saved offsets instead of being silently moved.
local function MSUF_ProfileIO_StampScreenReference(payload)
    local height = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(height) == true then return end
    if type(height) ~= "number" or height < 400 or height > 10000 then return end
    local function Stamp(conf)
        if type(conf) ~= "table" or (conf.offsetX == nil and conf.offsetY == nil
            and conf.x == nil and conf.y == nil) then return end
        if conf.screenPositionMode ~= nil and conf.screenPositionMode ~= "relativeHeight" then return end
        conf.screenPositionHeight = height
        conf.screenPositionMode = "relativeHeight"
    end
    for i = 1, #MSUF_PROFILEIO_UNIT_KEYS do
        Stamp(payload[MSUF_PROFILEIO_UNIT_KEYS[i]])
    end
    for i = 1, 5 do Stamp(payload["boss" .. i]) end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do Stamp(payload[key]) end
end

-- Selected-frame snapshots have a separate kind so older importers reject them
-- instead of treating them as the broad Unitframes category (which resets globals).
-- Only explicitly owned settings cross this boundary; shared appearance stays local.
local UnitSelection = {
    units = { player = true, target = true, targettarget = true, focustarget = true,
        focus = true, pet = true, pettarget = true, boss = true, arena = true },
    auraFlags = { showPlayer = "player", showPet = "pet", showTarget = "target", showFocus = "focus",
        showBoss = "boss", showArena = "arena" },
    barKeys = { showPlayerPowerBar = "player", showTargetPowerBar = "target",
        showFocusPowerBar = "focus", showBossPowerBar = "boss", showArenaPowerBar = "arena" },
    -- The Colors page's Cast Target Name Color reads like a Target key but tints
    -- every castbar: it stays local, and older strings that carry it still import.
    sharedGeneral = { castbarTargetNameR = true, castbarTargetNameG = true, castbarTargetNameB = true },
}
function UnitSelection.Supported(unit)
    return UnitSelection.units[unit] == true
        and MSUF.Client.SupportsUnit(unit)
end
function UnitSelection.GeneralOwner(key)
    if type(key) ~= "string" or UnitSelection.sharedGeneral[key] then return nil end
    for _, unit in ipairs({ "player", "target", "focus", "boss", "arena" }) do
        local title = unit:sub(1, 1):upper() .. unit:sub(2)
        if key:sub(1, #unit + 7) == "castbar" .. title
            or key:sub(1, #unit + 7) == unit .. "Castbar"
            or key:sub(1, #unit + 8) == "show" .. title .. "Cast"
            or key == "enable" .. title .. "Castbar"
            or ((unit == "boss" or unit == "arena") and key:sub(1, #unit + 4) == unit .. "Cast") then
            return unit
        end
    end
    if key == "castbarOpositeDirectionTarget" then return "target" end
    if key == "_msufBossCastbarPhysicalEdgeAnchor_v1" then return "boss" end
end
function UnitSelection.AuraOwner(key)
    if key == "player" or key == "pet" or key == "target" or key == "focus" then return key end
    if type(key) == "string" then
        if key:match("^boss[1-5]$") then return "boss" end
        if key:match("^arena[1-5]$") then return "arena" end
    end
end
function UnitSelection.ReplaceTable(parent, key, source)
    if type(parent[key]) ~= "table" then parent[key] = {} end
    MSUF_WipeTable(parent[key])
    for k, v in pairs(source) do parent[key][k] = MSUF_DeepCopy(v) end
end
function UnitSelection.Copy(profile, selected)
    local payload = {}
    for unit in pairs(UnitSelection.units) do
        if selected[unit] == true then
            payload[unit] = MSUF_DeepCopy(profile[unit] or {})
        end
    end
    for _, spec in ipairs({ { "general", UnitSelection.GeneralOwner },
        { "bars", function(key) return UnitSelection.barKeys[key] end } }) do
        local out = {}
        for key, value in pairs(profile[spec[1]] or {}) do
            local owner = spec[2](key)
            if owner and selected[owner] then out[key] = MSUF_DeepCopy(value) end
        end
        payload[spec[1]] = out
    end
    local auras = profile.auras3 or {}
    local out = { perUnit = {} }
    for flag, unit in pairs(UnitSelection.auraFlags) do
        if selected[unit] then
            out[flag] = auras[flag] == true or (flag == "showPet" and auras[flag] == nil)
            local count = (unit == "boss" or unit == "arena") and 5 or 1
            for i = 1, count do
                local key = count == 1 and unit or unit .. i
                out.perUnit[key] = MSUF_DeepCopy(auras.perUnit and auras.perUnit[key] or {})
            end
        end
    end
    if next(out.perUnit) then payload.auras3 = out end
    return payload
end
--- A rejection returns the English reason plus its template and the inserted
--- key, so the import chat line can translate the whole sentence first.
function UnitSelection.Reject(template, key)
    key = tostring(key)
    return nil, template:format(key), template, key
end
function UnitSelection.Validate(payload)
    local selected = {}
    for key, value in pairs(payload) do
        if UnitSelection.units[key] then
            if not UnitSelection.Supported(key) then return UnitSelection.Reject("unsupported unitframe: %s", key) end
            if type(value) ~= "table" then return UnitSelection.Reject("invalid unitframe: %s", key) end
            selected[key] = true
        elseif key ~= "general" and key ~= "bars" and key ~= "auras3" then
            return UnitSelection.Reject("unexpected selected-frame setting: %s", key)
        elseif type(value) ~= "table" then
            return UnitSelection.Reject("invalid selected-frame settings: %s", key)
        end
    end
    if not next(selected) then return nil, "select at least one unitframe" end
    for _, spec in ipairs({ { "general", UnitSelection.GeneralOwner },
        { "bars", function(key) return UnitSelection.barKeys[key] end } }) do
        for key in pairs(payload[spec[1]] or {}) do
            local owner = spec[2](key)
            if (not owner or not selected[owner]) and not UnitSelection.sharedGeneral[key] then
                return UnitSelection.Reject("setting outside selected unitframes: %s", key)
            end
        end
    end
    for key, value in pairs(payload.auras3 or {}) do
        if key == "perUnit" and type(value) == "table" then
            for unit, conf in pairs(value) do
                local owner = UnitSelection.AuraOwner(unit)
                if not owner or not selected[owner] or type(conf) ~= "table" then
                    return UnitSelection.Reject("aura settings outside selected unitframes: %s", unit)
                end
            end
        elseif not UnitSelection.auraFlags[key] or not selected[UnitSelection.auraFlags[key]]
            or type(value) ~= "boolean" then
            return UnitSelection.Reject("unexpected selected-frame aura setting: %s", key)
        end
    end
    return selected
end
function UnitSelection.Commit(payload, selected, db)
    for unit in pairs(selected) do UnitSelection.ReplaceTable(db, unit, payload[unit]) end
    for _, spec in ipairs({ { "general", UnitSelection.GeneralOwner },
        { "bars", function(key) return UnitSelection.barKeys[key] end } }) do
        local root = spec[1]
        if type(db[root]) ~= "table" then db[root] = {} end
        for key in pairs(db[root]) do
            local owner = spec[2](key)
            if owner and selected[owner] then db[root][key] = nil end
        end
        for key, value in pairs(payload[root] or {}) do db[root][key] = MSUF_DeepCopy(value) end
    end
    if payload.auras3 then
        if type(db.auras3) ~= "table" then db.auras3 = {} end
        local auras = db.auras3
        if type(auras.perUnit) ~= "table" then auras.perUnit = {} end
        for key, value in pairs(payload.auras3) do
            if key == "perUnit" then
                for unit, conf in pairs(value) do UnitSelection.ReplaceTable(auras.perUnit, unit, conf) end
            else
                auras[key] = value
            end
        end
    end
end

local function MSUF_SnapshotForKind(kind, selectedUnits)
    if Variants and Variants.IsRecording() then return nil end
    MSUF_ProfileIO_EnsureCompleteProfileDB()
    local MSUF_DB
    if Variants then MSUF_DB=Variants.BaseSnapshot(_G.MSUF_DB,true) else MSUF_DB=_G.MSUF_DB end
    if type(MSUF_DB)~="table" then return nil end
    local payload = {}
    if kind == "unitselection" then
        if type(selectedUnits) ~= "table" then return nil end
        local selected = {}
        for unit, enabled in pairs(selectedUnits) do
            if enabled == true then
                if not UnitSelection.Supported(unit) then return nil end
                selected[unit] = true
            end
        end
        if not next(selected) then return nil end
        payload = UnitSelection.Copy(MSUF_DB, selected)
    elseif kind == "unitframe" then
        --- Everything EXCEPT: gameplay (with the swing timers), colors, castbars
        for k, v in pairs(MSUF_DB or {}) do
            if k == "general" then
                payload.general = MSUF_CopyGeneralSubset(MSUF_GeneralKeysOfKind("unitframe"), MSUF_DB)
            elseif k == "classColors" or k == "npcColors" or k == "gameplay" or k == "swingTimers" then
                --- exclude
            else
                payload[k] = MSUF_DeepCopy(v)
            end
        end
        MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload)
    elseif kind == "castbar" then
        payload.general = MSUF_CopyGeneralSubset(MSUF_GeneralKeysOfKind("castbar"), MSUF_DB)
    elseif kind == "colors" then
        payload.general = MSUF_CopyGeneralSubset(MSUF_GeneralKeysOfKind("colors"), MSUF_DB)
        payload.classColors = MSUF_DeepCopy((MSUF_DB and MSUF_DB.classColors) or {})
        payload.npcColors   = MSUF_DeepCopy((MSUF_DB and MSUF_DB.npcColors) or {})
    elseif kind == "gameplay" then
        payload.gameplay = MSUF_DeepCopy((MSUF_DB and MSUF_DB.gameplay) or {})
        --- The swing timers belong to Gameplay (State/MSUF_ProfileFields.lua).
        payload.swingTimers = MSUF_DeepCopy(MSUF_DB.swingTimers)
    elseif kind == "groupframe" or kind == "groupframes" then
        payload = MSUF_CopyGroupFramePayload(MSUF_DB)
    elseif kind == "all" then
        payload = MSUF_DeepCopy(MSUF_DB or {})
        MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload)
    else
         return nil
    end
    if MSUF.ProfileFields and MSUF.ProfileFields.StripExternal then MSUF.ProfileFields.StripExternal(payload) end
    payload.assistant = nil -- retired Assistant history (State/MSUF_RetiredData.lua)
    if kind~="all" or not MSUF_ProfileIO_ExportVariants then payload.profileVariants=nil end
    if type(payload.general) == "table" then
        payload.general.blizzardEditModeSnapshot = nil
    end
    --- The snapshot holds committed layout values only: Micro Menu and Bags
    --- values still pending a Reload are not exported (MSUF_EditMode_Blizzard.lua).
    if kind == "all" and MSUF_ProfileIO_ExportBlizzardEM then
        local blizzSnapshot = type(MSUF_DB) == "table" and type(MSUF_DB.general) == "table"
            and MSUF_DB.general.blizzardEditModeSnapshot or nil
        if type(blizzSnapshot) == "table" then
            if type(payload.general) ~= "table" then payload.general = {} end
            payload.general.blizzardEditModeSnapshot = MSUF_DeepCopy(blizzSnapshot)
        end
    end
    if kind == "unitselection" or kind == "unitframe" or kind == "groupframe"
        or kind == "groupframes" or kind == "all" then
        MSUF_ProfileIO_StampScreenReference(payload)
    end
    return {
        addon   = "MSUF",
        fmt     = 2,
        schema  = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
        kind    = kind,
        profile = MSUF_ActiveProfile or "Default",
        payload = payload,
    }
end

local function MSUF_ExportSelectionToString(kind, selectedUnits)
    local snap = MSUF_SnapshotForKind(kind, selectedUnits)
    if not snap then return nil end
    local exportSnap, wagoExport = MSUF_ProfileIO_MakeWagoSnapshot(snap)
    if wagoExport then
        return MSUF.PublicGlobals.MSUF_EncodeCompactTableMSUF3(exportSnap)
    end
    return _G.MSUF_EncodeCompactTable(snap)
end

--- Imports schema-600 MSUF2/MSUF3/MSUF4 strings or safe text snapshots into
--- the active profile. Returns true, or false plus the rejection reason.
function MSUF.PublicGlobals.MSUF_ExportExternal(profileKey)
    if Variants and Variants.IsRecording() then return false,"finish editing the variant first" end
    local profileTbl = MSUF_ProfileIO_GetProfileTable(profileKey)
    if type(profileTbl) ~= "table" then
         return false, "unknown profileKey"
    end
    local payload
    if profileKey == MSUF_ActiveProfile then
        MSUF_ProfileIO_EnsureCompleteProfileDB()
        profileTbl = MSUF_DB
        local snapshotWhy
        if Variants then payload,snapshotWhy=Variants.BaseSnapshot(profileTbl,true) else payload=MSUF_DeepCopy(profileTbl) end
        if not payload then return false,snapshotWhy or "profile exceeds snapshot limits" end
    else
        payload = MSUF_DeepCopy(profileTbl)
        local materialized, why = MSUF_ProfileIO_MaterializeProfileCopyForExport(payload, profileKey)
        if type(materialized) ~= "table" then
            return false, tostring(why or "profile materialization failed")
        end
        payload = materialized
    end
    if MSUF.ProfileFields and MSUF.ProfileFields.StripExternal then MSUF.ProfileFields.StripExternal(payload) end
    payload.assistant = nil -- retired Assistant history (State/MSUF_RetiredData.lua)
    if not MSUF_ProfileIO_ExportVariants then payload.profileVariants=nil end
    local snap = {
        addon   = "MSUF",
        fmt     = 2,
        schema  = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
        kind    = "all",
        profile = profileKey,
        payload = MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload),
    }
    if profileKey == MSUF_ActiveProfile then
        MSUF_ProfileIO_StampScreenReference(snap.payload)
    end
    local exportSnap = MSUF_ProfileIO_MakeWagoSnapshot(snap)
    return true, MSUF.PublicGlobals.MSUF_EncodeCompactTableMSUF3(exportSnap)
end
ExportPublic("MSUF_ExportExternal", MSUF.PublicGlobals.MSUF_ExportExternal)

Parts.MSUF_ExportSelectionToString = MSUF_ExportSelectionToString
Parts.UnitSelection = UnitSelection
function Parts.Bind3()
    MSUF_ProfileIO_GetProfileTable = Parts.MSUF_ProfileIO_GetProfileTable
    MSUF_ProfileIO_MaterializeProfileCopyForExport = Parts.MSUF_ProfileIO_MaterializeProfileCopyForExport
end
