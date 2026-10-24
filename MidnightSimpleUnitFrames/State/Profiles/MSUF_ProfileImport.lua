-- Profile import planning, transaction commit and external import/export API.
local _, MSUF = ...
local Parts = MSUF.ProfilesParts
local ApplyProfileRuntime = Parts.ApplyProfileRuntime
local ExportPublic = Parts.ExportPublic
local InitProfiles = Parts.InitProfiles
local MSUF_AURA_GENERAL_KEYS = Parts.MSUF_AURA_GENERAL_KEYS
local MSUF_ApplyGeneralSubset = Parts.MSUF_ApplyGeneralSubset
local MSUF_CopyProfile = Parts.MSUF_CopyProfile
local MSUF_DeepCopy = Parts.MSUF_DeepCopy
local MSUF_DeleteProfiles = Parts.MSUF_DeleteProfiles
local MSUF_ExportSelectionToString = Parts.MSUF_ExportSelectionToString
local MSUF_GeneralKeysOfKind = Parts.MSUF_GeneralKeysOfKind
local MSUF_GetAllProfiles = Parts.MSUF_GetAllProfiles
local MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA = Parts.MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
local MSUF_ProfileIO_CollectProfileMediaWarnings = Parts.MSUF_ProfileIO_CollectProfileMediaWarnings
local MSUF_ProfileIO_EnsureGroupFramesDB = Parts.MSUF_ProfileIO_EnsureGroupFramesDB
local MSUF_ProfileIO_EnsureProfileMenuDefaults = Parts.MSUF_ProfileIO_EnsureProfileMenuDefaults
local MSUF_ProfileIO_EnsureProfileRoots = Parts.MSUF_ProfileIO_EnsureProfileRoots
local MSUF_ProfileIO_EnsureUnitframeAlphaDB = Parts.MSUF_ProfileIO_EnsureUnitframeAlphaDB
local MSUF_ProfileIO_NormalizeImportedFontSizes = Parts.MSUF_ProfileIO_NormalizeImportedFontSizes
local MSUF_ProfileIO_NotifySuiteLifecycle = Parts.MSUF_ProfileIO_NotifySuiteLifecycle
local MSUF_ProfileIO_NotifySuiteProfileChanged = Parts.MSUF_ProfileIO_NotifySuiteProfileChanged
local MSUF_ProfileIO_ReportImportWarnings = Parts.MSUF_ProfileIO_ReportImportWarnings
local MSUF_ProfileIO_ResetImportWarnings = Parts.MSUF_ProfileIO_ResetImportWarnings
local MSUF_ProfileIO_RunEnsureDB = Parts.MSUF_ProfileIO_RunEnsureDB
local MSUF_ProfileIO_SelectSupportedProfile = Parts.MSUF_ProfileIO_SelectSupportedProfile
local MSUF_ProfileIO_TranslateProfileToCurrent = Parts.MSUF_ProfileIO_TranslateProfileToCurrent
local MSUF_ProfileIO_TranslateProfilesToCurrent = Parts.MSUF_ProfileIO_TranslateProfilesToCurrent
local MSUF_RenameProfile = Parts.MSUF_RenameProfile
local MSUF_ResetProfile = Parts.MSUF_ResetProfile
local MSUF_UNITFRAME_ALPHA_KEYS = Parts.MSUF_UNITFRAME_ALPHA_KEYS
local MSUF_UNITFRAME_UNIT_KEYS = Parts.MSUF_UNITFRAME_UNIT_KEYS
local MSUF_WipeGeneralSubset = Parts.MSUF_WipeGeneralSubset
local MSUF_WipeTable = Parts.MSUF_WipeTable
local Normalize = Parts.Normalize
local PrepareProfileMutation = Parts.PrepareProfileMutation
local ProfileChat = Parts.ProfileChat
local ProfileChatLine = Parts.ProfileChatLine
local ProfileNameTooLong = Parts.ProfileNameTooLong
local ProfileSync = Parts.ProfileSync
local StateHelpers = Parts.StateHelpers
local Translate = Parts.Translate
local UnitSelection = Parts.UnitSelection
local Variants = Parts.Variants
local MSUF_ProfileIO_ImportBlizzardEM = false
local MSUF_ProfileIO_ImportVariants = true
ExportPublic("MSUF_Profiles_SetImportVariants", function(value) MSUF_ProfileIO_ImportVariants=value==true end)
ExportPublic("MSUF_Profiles_SetImportBlizzardEditMode", function(value)
    MSUF_ProfileIO_ImportBlizzardEM = value == true
end)
local function MSUF_ProfileIO_AuraImportScopes(payload)
    if type(payload) ~= "table" then
        return nil, false
    end

    local g = payload.general
    if type(g) == "table" then
        for k in pairs(MSUF_AURA_GENERAL_KEYS) do
            if g[k] ~= nil then
                return nil, true
            end
        end
    end

    local auras = payload.auras3
    if type(auras) ~= "table" then
        return nil, false
    end

    local scopes, seen = {}, {}
    local function AddScope(scope)
        scope = tostring(scope or "")
        if scope ~= "" and not seen[scope] then
            seen[scope] = true
            scopes[#scopes + 1] = scope
        end
    end

    for key, value in pairs(auras) do
        if key == "perUnit" and type(value) == "table" then
            for unit, conf in pairs(value) do
                if type(conf) == "table" then
                    AddScope(unit)
                end
            end
        else
            return nil, true
        end
    end

    if #scopes > 0 then
        return scopes, false
    end
    return nil, true
end
--- After a profile import we must explicitly refresh Auras/Auras3 so the live UI matches without /reload.
--- Keep this scoped (Auras only) to avoid unintended regressions in other modules.
local function MSUF_ProfileIO_PostImportApply_Auras(kind, payload)
    if not payload then  return end
    local scopes, full = MSUF_ProfileIO_AuraImportScopes(payload)
    if not full and not scopes then  return end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if not full and scopes then
        local called = false
        for i = 1, #scopes do
            local scope = scopes[i]
            if a3 and type(a3.ApplyFontsFromGlobal) == "function" then
                a3.ApplyFontsFromGlobal(scope, "MSUF_PROFILE_IMPORT_AURAS")
                called = true
            elseif a3 and type(a3.RequestScope) == "function" then
                a3.RequestScope(scope, "MSUF_PROFILE_IMPORT_AURAS")
                called = true
            elseif a3 and type(a3.RefreshUnit) == "function" then
                a3.RefreshUnit(scope)
                called = true
            else
                full = true
                break
            end
        end
        if called and not full then
            return
        end
    end
    if a3 and type(a3.ApplyFontsFromGlobal) == "function" then
        a3.ApplyFontsFromGlobal(nil, "MSUF_PROFILE_IMPORT_AURAS")
    elseif a3 and type(a3.RefreshAll) == "function" then
        a3.RefreshAll()
    end
end
local function MSUF_ProfileIO_PostImportApply_GroupFrames(kind, payload)
    if type(payload) ~= "table" then  return end
    local touchedKinds, seenKinds = {}, {}
    local function AddKind(groupKind)
        if groupKind and not seenKinds[groupKind] then
            seenKinds[groupKind] = true
            touchedKinds[#touchedKinds + 1] = groupKind
        end
    end
    if type(payload.gf_party) == "table" then AddKind("party") end
    if type(payload.gf_raid) == "table" then AddKind("raid") end
    if type(payload.gf_mythicraid) == "table" then AddKind("mythicraid") end
    if type(payload.gf_priority) == "table" then AddKind("priority") end
    local touched = (kind == "groupframe") or (kind == "groupframes")
    if not touched then
        touched = (#touchedKinds > 0)
    end
    if not touched then  return end
    if #touchedKinds == 0 then
        AddKind("party")
        AddKind("raid")
        AddKind("mythicraid")
        AddKind("priority")
    end
    MSUF_ProfileIO_EnsureGroupFramesDB()
    -- No blacklist hash flush: MSUF_GF_AuraFilter.BuildBlacklistHash re-checks
    -- each group's blacklist signature on every call (and
    -- InvalidateAllBlacklistHashes, called here before, exists nowhere).
    -- Group frames load after this file; Kernel/MSUF_RuntimeContracts.lua
    -- requires this provider once the core TOC has loaded.
    MSUF.Require("MSUF_GF_InvalidateConfCache", "State/MSUF_Profiles.lua")()
    local gf = (type(MSUF) == "table" and MSUF.GF) or (_G.MSUF_NS and _G.MSUF_NS.GF)
    if gf and type(gf.Rebuild) == "function" then
        local rebuilt = false
        for i = 1, #touchedKinds do
            local groupKind = touchedKinds[i]
            gf.Rebuild(groupKind)
            rebuilt = true
        end
        if rebuilt then return end
    elseif gf and type(gf.RefreshGeometry) == "function" then
        local refreshed = false
        for i = 1, #touchedKinds do
            local groupKind = touchedKinds[i]
            gf.RefreshGeometry(groupKind)
            refreshed = true
            if type(gf.RefreshUnitBindings) == "function" then
                gf.RefreshUnitBindings(groupKind)
            end
            if type(gf.RefreshVisuals) == "function" then
                gf.RefreshVisuals(groupKind, gf.DIRTY_ALL or gf.DIRTY_CONFIG or gf.DIRTY_VISUAL)
            end
        end
        if refreshed then return end
    elseif gf and type(gf.RequestAuraRefresh) == "function" then
        gf.RequestAuraRefresh()
    elseif gf and type(gf.MarkAllDirty) == "function" then
        gf.MarkAllDirty(gf.DIRTY_AURAS or gf.DIRTY_ALL or 0x3F)
    end
end
local function MSUF_ProfileIO_PostImportApply_UnitAlphas(kind, payload)
    if type(payload) ~= "table" then  return end
    local full = (kind == "all")
    local touchedUnits, seenUnits = {}, {}
    local function AddUnit(unitKey)
        unitKey = tostring(unitKey or "")
        if unitKey == "tot" then unitKey = "targettarget" end
        if unitKey ~= "" and not seenUnits[unitKey] then
            seenUnits[unitKey] = true
            touchedUnits[#touchedUnits + 1] = unitKey
        end
    end
    for _, unitKey in ipairs(MSUF_UNITFRAME_UNIT_KEYS) do
        local conf = payload[unitKey]
        if type(conf) == "table" then
            for alphaKey in pairs(MSUF_UNITFRAME_ALPHA_KEYS) do
                if conf[alphaKey] ~= nil then
                    AddUnit(unitKey)
                    break
                end
            end
        end
    end
    if type(payload.tot) == "table" then
        for alphaKey in pairs(MSUF_UNITFRAME_ALPHA_KEYS) do
            if payload.tot[alphaKey] ~= nil then
                AddUnit("targettarget")
                break
            end
        end
    end
    if not full and #touchedUnits == 0 then  return end
    MSUF_ProfileIO_EnsureUnitframeAlphaDB()
    local refresh = MSUF.PublicGlobals.MSUF_RefreshAllUnitAlphas or MSUF.PublicGlobals.MSUF_RequestAlphaRefresh
    if type(refresh) == "function" then
        if full then
            refresh()
        else
            for i = 1, #touchedUnits do refresh(touchedUnits[i]) end
        end
    end
end
--- Import failure chat lines. Every fixed reason the import path prints has a
--- full-sentence key in the language packs: the sentence is translated whole,
--- a frame key or value type goes in after, and the chat tag goes in front.
--- Callers keep receiving the English reason. Any other reason keeps the
--- translated-reason route: the profile variant reasons have their own keys,
--- and the parser's byte-position errors are built at runtime and stay English.
local IMPORT_FAILED_SENTENCES = {}
for _, sentence in ipairs({
    "Import failed: could not decode compact profile string (%s).",
    -- the table-literal parser (State/MSUF_ProfileCodec.lua)
    "Import failed: profile import is too large",
    "Import failed: unterminated comment",
    "Import failed: profile table has too many values",
    "Import failed: unterminated string",
    "Import failed: unterminated escape",
    "Import failed: invalid decimal escape",
    "Import failed: unsupported string escape",
    "Import failed: invalid number",
    "Import failed: profile table is too deep",
    "Import failed: unterminated table",
    "Import failed: unsupported table key",
    "Import failed: unsupported value",
    "Import failed: profile import must contain a table",
    -- the schema stamp and the snapshot kind
    "Import failed: MSUF 6.x profile required (schema 600).",
    "Import failed: unknown kind",
    -- the value validator: snapshot, then full profile
    "Import failed: profile has too many values",
    "Profile import failed: profile has too many values",
    "Import failed: profile strings are too large",
    "Profile import failed: profile strings are too large",
    "Import failed: profile contains an invalid number",
    "Profile import failed: profile contains an invalid number",
    "Import failed: profile contains unsupported %s",
    "Profile import failed: profile contains unsupported %s",
    "Import failed: profile is too deep",
    "Profile import failed: profile is too deep",
    "Import failed: profile contains a cyclic or shared table",
    "Profile import failed: profile contains a cyclic or shared table",
    "Import failed: profile contains an unsupported table key",
    "Profile import failed: profile contains an unsupported table key",
    -- UnitSelection.Validate
    "Import failed: unsupported unitframe: %s.",
    "Import failed: invalid unitframe: %s.",
    "Import failed: unexpected selected-frame setting: %s.",
    "Import failed: invalid selected-frame settings: %s.",
    "Import failed: select at least one unitframe.",
    "Import failed: setting outside selected unitframes: %s.",
    "Import failed: aura settings outside selected unitframes: %s.",
    "Import failed: unexpected selected-frame aura setting: %s.",
    -- the live profile's base snapshot (Variants.BaseSnapshot)
    "Import failed: profile contains a value that cannot be saved",
    "Import failed: profile contains a table that refers to itself",
    "Import failed: profile exceeds snapshot limits",
    "Import failed: an add-on part of the profile could not be copied",
}) do IMPORT_FAILED_SENTENCES[sentence] = true end
local function ImportFailedLine(text, reason, template, inserted)
    local sentence = text:format(tostring(template or reason))
    if IMPORT_FAILED_SENTENCES[sentence] then
        return ProfileChatLine("error", sentence, inserted ~= nil and tostring(inserted) or nil)
    end
    return ProfileChatLine("error", text, Translate(tostring(reason)))
end
--- Import transaction, step 1 of 3: decode, select, validate and stage.
--- Runs before anything is written. It performs no SavedVariables writes, no
--- ExportPublic and no prints, so every rejection (including a truncated
--- string pasted into new-profile import) leaves the stored profiles
--- untouched. The codec returns nil for bytes the native decoders reject
--- (native CBOR raises into the Kernel boundary), so a garbled string is an
--- ordinary rejection here. mode is "active" (current or new profile) or
--- "external" (MSUF_ImportExternal). Returns a plan table, or nil plus reason
--- plus (active mode) the exact chat line the pre-transaction entry points
--- printed for that rejection. External reasons keep their old strings too.
local function MSUF_ProfileIO_PrepareImport(str, mode)
    local external = (mode == "external")
    if type(str) ~= "string" or not str:match("%S") then
        return nil, "empty string", ProfileChatLine("error", "Import failed (empty string).")
    end
    local decoded, why
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        decoded = tryDec(str)
    end
    if type(decoded) ~= "table" then
        --- A compact MSUF2/MSUF3/MSUF4 string that failed to decode is NEVER
        --- retried as a table literal.
        local prefix = str:match("^%s*(MSUF%d+):")
        if prefix == "MSUF2" or prefix == "MSUF3" or prefix == "MSUF4" then
            why = "could not decode compact profile string (" .. prefix .. ")"
            return nil, why, ImportFailedLine("Import failed: %s.", why, "could not decode compact profile string (%s)", prefix)
        end
        decoded, why = MSUF.ProfileIOParseTableLiteral(str)
        if type(decoded) ~= "table" then
            if external then return nil, "invalid lua table string" end
            -- Byte-position parse errors ("expected = at byte 12") are built at runtime and stay English.
            return nil, tostring(why), ImportFailedLine("Import failed: %s", why)
        end
    end
    --- Source-client stamp: `decoded` is still the raw decoded envelope here.
    --- A reader of the exporting client's stamp belongs at this point, before
    --- SelectSupportedProfile rebuilds or drops the envelope.
    local selected = MSUF_ProfileIO_SelectSupportedProfile(decoded)
    local schemaWhy = "MSUF 6.x profile required (schema 600)"
    if type(selected) ~= "table" then
        return nil, schemaWhy, ImportFailedLine("Import failed: %s.", schemaWhy)
    end
    local isSnapshot = selected.addon == "MSUF" and tonumber(selected.fmt) == 2
        and type(selected.payload) == "table" and type(selected.kind) == "string"
    --- Rejection order follows the pre-transaction entry points: external
    --- import rejects any snapshot that is not kind "all" before validating,
    --- and an active full profile checks its schema stamp before validating.
    if isSnapshot and external and selected.kind ~= "all" then
        return nil, "external import requires a full profile snapshot"
    end
    if not isSnapshot and not external
        and tonumber(selected._msufProfileSchema) ~= MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA then
        return nil, schemaWhy, ImportFailedLine("Import failed: %s.", schemaWhy)
    end
    local valid, validationError, validationTemplate, validationType = MSUF.ProfileIOValidateImportValue(selected)
    if not valid then
        return nil, validationError, ImportFailedLine(isSnapshot and "Import failed: %s" or "Profile import failed: %s",
            validationError, validationTemplate, validationType)
    end
    local staged = MSUF_DeepCopy(selected)
    local plan = {
        isSnapshot = isSnapshot,
        schema = staged.schema,
    }
    local kind
    if plan.isSnapshot then
        kind = staged.kind
        if kind == "groupframes" then
            kind = "groupframe"
        end
        if kind ~= "unitselection" and kind ~= "unitframe" and kind ~= "groupframe" and kind ~= "castbar"
            and kind ~= "colors" and kind ~= "gameplay" and kind ~= "all" then
            return nil, "unknown kind", ImportFailedLine("Import failed: %s", "unknown kind")
        end
        plan.snapshotKind, plan.payload = staged.kind, staged.payload
    else
        kind = "all"
        plan.payload = staged
    end
    plan.kind = kind
    local payload = plan.payload
    if Normalize.PersistenceRejected(payload) then return nil, "invalid profile data", ImportFailedLine("Import failed: %s", "invalid profile data") end
    if MSUF.ProfileFields and MSUF.ProfileFields.StripExternal then MSUF.ProfileFields.StripExternal(payload) end
    payload.assistant = nil -- retired Assistant history (State/MSUF_RetiredData.lua)
    --- Variants that will not be imported are dropped before validation, so
    --- a string is never rejected for data the import leaves behind.
    if kind~="all" or not MSUF_ProfileIO_ImportVariants then payload.profileVariants=nil end
    if payload.profileVariants~=nil and Variants then
        local clean,variantError=Variants.ValidateForProfile(payload,payload.profileVariants)
        if not clean then
            return nil, variantError, ImportFailedLine("Import failed: %s", variantError)
        end
        payload.profileVariants=clean
    end
    MSUF.ProfileNormalize.PrepareGroupFrameImport(payload, kind)
    if kind == "unitselection" then
        local selectedUnits, selectionError, selectionTemplate, selectionKey = UnitSelection.Validate(payload)
        if not selectedUnits then
            return nil, selectionError, ImportFailedLine("Import failed: %s.", selectionError, selectionTemplate, selectionKey)
        end
        -- Normalize untrusted frame data, then project it back onto its explicit
        -- owners. Normalizers may seed shared defaults; those must never travel.
        -- A selected aura scope is already the current per-unit model. It has no
        -- global model marker, so never feed it to the full-profile aura resetter.
        local selectedAuras = payload.auras3
        payload.auras3 = nil
        MSUF_ProfileIO_TranslateProfileToCurrent(payload, {
            source = "unitselection_import", markProfile = false, createGeneral = false,
        })
        payload.auras3 = selectedAuras
        for _, conf in pairs(selectedAuras and selectedAuras.perUnit or {}) do
            StateHelpers.NormalizeAuraLayoutTable(conf.layout, StateHelpers.ProfileIOSpec)
            StateHelpers.NormalizeAuraLayoutTable(conf.layoutShared, StateHelpers.ProfileIOSpec)
        end
        plan.payload = UnitSelection.Copy(payload, selectedUnits)
        plan.selectedUnits = selectedUnits
        MSUF_ProfileIO_CollectProfileMediaWarnings(plan.payload)
        return plan
    end
    if mode == "external" then
        MSUF_ProfileIO_TranslateProfileToCurrent(payload, {
            source = "external_import",
            markProfile = true,
        })
        -- State/MSUF_Defaults.lua also owns the portrait render and dispel
        -- priority migrations an external import runs after the translator.
        MSUF.Require("MSUF_NormalizePortraitRenderDB", "State/MSUF_Profiles.lua")(payload)
        MSUF.Require("MSUF_MigrateDispelPriorityProfile", "State/MSUF_Profiles.lua")(payload, true)
    elseif not plan.isSnapshot then
        MSUF_ProfileIO_TranslateProfileToCurrent(payload, {
            source = "profile_import",
            markProfile = true,
        })
        if not MSUF_ProfileIO_ImportBlizzardEM and type(payload.general) == "table" then
            payload.general.blizzardEditModeSnapshot = nil
        end
    else
        --- Opt-in gate for imported Blizzard Edit Mode data: stripped before the
        --- merge unless the profiles-page switch is on, so a foreign string can
        --- never silently rearrange the local Blizzard HUD.
        if not MSUF_ProfileIO_ImportBlizzardEM and type(payload.general) == "table" then
            payload.general.blizzardEditModeSnapshot = nil
        end
        if kind == "unitframe" or kind == "groupframe" or kind == "all" then
            MSUF_ProfileIO_TranslateProfileToCurrent(payload, {
                source = "snapshot_import",
                schema = plan.schema,
                markProfile = (kind == "all"),
                createGeneral = (kind == "all") or type(payload.general) == "table",
                normalizePositions = (kind == "unitframe" or kind == "all"),
            })
        else
            MSUF_ProfileIO_NormalizeImportedFontSizes(payload)
        end
    end
    MSUF_ProfileIO_CollectProfileMediaWarnings(payload)
    return plan
end
--- Import transaction, step 2 of 3: stage the complete profile the commit
--- will install and run every normalizer over it: the forced defaults pass,
--- the unit alpha keys, the group-frame repair and the aura model. Nothing
--- live is written here. A payload a normalizer cannot digest raises while
--- every stored profile is still untouched, so a malformed string can never
--- leave a half-written profile behind that fails again at every login.
--- base is the target profile's current content: the active profile's base
--- snapshot, a new profile's factory table, or the stored external target.
--- Partial kinds merge into a private copy of it; full kinds only take its
--- local variants while variant import is off.
local ImportTx = {}
function ImportTx.Merge(kind, payload, db)
    if kind == "unitframe" then
        --- Wipe & replace the same general-key set that Unitframes export.
        local owned = MSUF_GeneralKeysOfKind("unitframe")
        MSUF_WipeGeneralSubset(owned, db)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general, db, owned)
        end
        --- Older Unitframes strings still carry the swing timers, which belong
        --- to Gameplay now: they never overwrite the local ones.
        for k, v in pairs(payload) do
            if k ~= "general" and k ~= "swingTimers" and k ~= "gameplay"
                and k ~= "classColors" and k ~= "npcColors" then
                if type(v) == "table" then
                    if type(db[k]) ~= "table" then
                        db[k] = {}
                    end
                    MSUF_WipeTable(db[k])
                    for kk, vv in pairs(v) do
                        db[k][kk] = MSUF_DeepCopy(vv)
                    end
                else
                    db[k] = v
                end
            end
        end
    elseif kind == "groupframe" then
        for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid", "gf_priority" }) do
            local value = payload[key]
            if type(value) == "table" then
                if type(db[key]) ~= "table" then
                    db[key] = {}
                end
                MSUF_WipeTable(db[key])
                for kk, vv in pairs(value) do
                    db[key][kk] = MSUF_DeepCopy(vv)
                end
            elseif value ~= nil then
                db[key] = MSUF_DeepCopy(value)
            end
        end
    elseif kind == "castbar" then
        local owned = MSUF_GeneralKeysOfKind("castbar")
        MSUF_WipeGeneralSubset(owned, db)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general, db, owned)
        end
    elseif kind == "colors" then
        local owned = MSUF_GeneralKeysOfKind("colors")
        MSUF_WipeGeneralSubset(owned, db)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general, db, owned)
        end
        if type(db.classColors) ~= "table" then db.classColors = {} end
        if type(db.npcColors) ~= "table" then db.npcColors = {} end
        MSUF_WipeTable(db.classColors)
        MSUF_WipeTable(db.npcColors)
        if type(payload.classColors) == "table" then
            for kk, vv in pairs(payload.classColors) do
                db.classColors[kk] = MSUF_DeepCopy(vv)
            end
        end
        if type(payload.npcColors) == "table" then
            for kk, vv in pairs(payload.npcColors) do
                db.npcColors[kk] = MSUF_DeepCopy(vv)
            end
        end
    elseif kind == "gameplay" then
        if type(db.gameplay) ~= "table" then db.gameplay = {} end
        MSUF_WipeTable(db.gameplay)
        if type(payload.gameplay) == "table" then
            for kk, vv in pairs(payload.gameplay) do
                db.gameplay[kk] = MSUF_DeepCopy(vv)
            end
        end
        --- An older Gameplay string has no swing timers: the local ones stay.
        if type(payload.swingTimers) == "table" then UnitSelection.ReplaceTable(db, "swingTimers", payload.swingTimers) end
    end
end
function ImportTx.Stage(plan, base)
    local kind, payload = plan.kind, plan.payload
    local candidate
    if kind == "unitselection" then
        --- Defaults can migrate unrelated categories. Repair a private
        --- candidate; the commit copies only the selected owners back.
        candidate = MSUF_DeepCopy(base)
        UnitSelection.Commit(payload, plan.selectedUnits, candidate)
        candidate._msufStateSchema = nil
        candidate = MSUF.PublicGlobals.MSUF_NormalizeProfileDefaults(candidate, true)
        MSUF_ProfileIO_EnsureUnitframeAlphaDB(candidate)
        plan.selection = UnitSelection.Copy(candidate, plan.selectedUnits)
        return candidate
    end
    if kind == "all" then
        candidate = MSUF_DeepCopy(payload)
        if not MSUF_ProfileIO_ImportVariants then
            candidate.profileVariants = MSUF_DeepCopy(base.profileVariants)
        end
    else
        candidate = MSUF_DeepCopy(base)
        ImportTx.Merge(kind, payload, candidate)
    end
    if MSUF.ProfileFields and MSUF.ProfileFields.StripExternal then MSUF.ProfileFields.StripExternal(candidate) end
    candidate._msufStateSchema = nil
    candidate = MSUF.PublicGlobals.MSUF_NormalizeProfileDefaults(candidate, true)
    MSUF_ProfileIO_EnsureUnitframeAlphaDB(candidate)
    --- The group-frame and aura modules load after this file; the import
    --- refreshes below treat them as optional the same way.
    local gf, auras = MSUF.GF, MSUF.MSUF_Auras3
    if type(gf) == "table" and type(gf.RepairGroupDB) == "function" then gf.RepairGroupDB(candidate) end
    if MSUF.ProfileMigrations then MSUF.ProfileMigrations.CompleteImportedGroupFontOwnership(candidate) end
    if type(auras) == "table" and type(auras.NormalizeProfileDB) == "function" then auras.NormalizeProfileDB(candidate) end
    --- Local variants kept across a full import are checked against the new
    --- settings they will overlay. They stay stored either way (they are the
    --- user's data); a mismatch is reported once after the commit.
    if kind == "all" and not MSUF_ProfileIO_ImportVariants and candidate.profileVariants ~= nil and Variants then
        local clean, why = Variants.ValidateForProfile(candidate, candidate.profileVariants)
        if clean then candidate.profileVariants = clean else plan.keptVariantsProblem = why end
    end
    plan.candidate = candidate
    return candidate
end
--- Base content of the active profile for staging: the base snapshot (never
--- a live variant overlay). A full import with variant import on needs none.
function ImportTx.LiveBase(plan)
    MSUF_ProfileIO_RunEnsureDB()
    if plan.kind == "all" and MSUF_ProfileIO_ImportVariants then return {} end
    if type(MSUF_DB) ~= "table" then return {} end
    if Variants then return Variants.BaseSnapshot(MSUF_DB, true) end
    return MSUF_DeepCopy(MSUF_DB)
end
--- A new profile starts from the same factory table MSUF_CreateProfile
--- builds, repaired the way the following profile switch repairs it.
function ImportTx.FactoryBase()
    local create = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile)
        or MSUF.PublicGlobals.MSUF_CreateFactoryDefaultProfile
    local profile = type(create) == "function" and create() or nil
    if type(profile) ~= "table" then return nil end
    MSUF_ProfileIO_TranslateProfileToCurrent(profile, {
        source = "profile_create",
        trustNormalizationMarker = true,
    })
    MSUF_ProfileIO_EnsureProfileMenuDefaults(profile)
    MSUF.PublicGlobals.MSUF_NormalizeProfileDefaults(profile, false, true)
    return profile
end
function ImportTx.ReportKeptVariants(plan)
    if not plan.keptVariantsProblem then return end
    ProfileChat("note", "Your profile variants were kept, but they do not match the imported settings and stay inactive (%s).",
        Translate(tostring(plan.keptVariantsProblem)))
end
--- Import transaction, step 3 of 3: swap the staged candidate into the active
--- profile. Everything that can reject a string or raise already ran on the
--- private candidate, so this step has no failure return.
local function MSUF_ProfileIO_CommitImportToActiveProfile(plan)
    --- Pending edits reach the other sync members first; the imported
    --- settings themselves stay in this profile (re-based below).
    if ProfileSync then ProfileSync.Flush() end
    PrepareProfileMutation()
    local kind, payload = plan.kind, plan.payload
    --- Always keep the profile-table reference stable (important!).
    --- Do not replace MSUF_DB with a new table here. Runtime modules keep
    --- references into the active profile and are invalidated by the apply hook.
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    if kind == "unitselection" then
        UnitSelection.Commit(plan.selection, plan.selectedUnits, MSUF_DB)
    else
        --- The staged candidate is private and fully normalized: move its
        --- values over without another copy.
        MSUF_WipeTable(MSUF_DB)
        for k, v in pairs(plan.candidate) do
            MSUF_DB[k] = v
        end
    end
    if MSUF.Castbars then MSUF.Castbars.Config.Invalidate() end
    --- Ensure the active profile table in GlobalDB points to MSUF_DB.
    if type(MSUF_GlobalDB) == "table" and type(MSUF_GlobalDB.profiles) == "table" and MSUF_ActiveProfile then
        MSUF_GlobalDB.profiles[MSUF_ActiveProfile] = MSUF_DB
    end
    if kind ~= "unitselection" then
        if MSUF.ProfileMigrations then MSUF.ProfileMigrations.AdoptNormalizedProfile(MSUF_DB) end
    end
    if ProfileSync then ProfileSync.Rebase() end
    if not plan.isSnapshot then
        MSUF.ProfileIOCompleteFirstLoadImport()
        MSUF_ProfileIO_PostImportApply_Auras("all", payload)
        MSUF_ProfileIO_PostImportApply_GroupFrames("all", payload)
        MSUF_ProfileIO_PostImportApply_UnitAlphas("all", payload)
        if MSUF.Client.SupportsBlizzardEditMode and type(payload.general) == "table"
            and type(payload.general.blizzardEditModeSnapshot) == "table" then
            MSUF.PublicGlobals.MSUF_BlizzardEditMode_ApplyProfileSnapshot()
        end
        ApplyProfileRuntime("PROFILE_IMPORT", true)
        MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_IMPORT", MSUF_ActiveProfile)
        ImportTx.ReportKeptVariants(plan)
        return true
    end
    MSUF_ProfileIO_PostImportApply_Auras(plan.snapshotKind, payload)
    MSUF_ProfileIO_PostImportApply_GroupFrames(plan.snapshotKind, payload)
    MSUF_ProfileIO_PostImportApply_UnitAlphas(kind, payload)
    if MSUF.Client.SupportsBlizzardEditMode and type(payload.general) == "table"
        and type(payload.general.blizzardEditModeSnapshot) == "table" then
        MSUF.PublicGlobals.MSUF_BlizzardEditMode_ApplyProfileSnapshot()
    end
    ApplyProfileRuntime("PROFILE_IMPORT", true)
    MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_IMPORT", MSUF_ActiveProfile)
    MSUF.ProfileIOCompleteFirstLoadImport()
    ImportTx.ReportKeptVariants(plan)
    return true
end
--- The end every import into the active profile shares: commit, then report.
function ImportTx.Finish(plan)
    MSUF_ProfileIO_CommitImportToActiveProfile(plan)
    if plan.isSnapshot then
        ProfileChat("ok", "Imported %s settings into the active profile.", tostring(plan.snapshotKind))
    else
        ProfileChat("ok", "Profile imported into the active profile.")
    end
    MSUF_ProfileIO_ReportImportWarnings()
    return true
end
local function MSUF_ImportFromString(str)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    MSUF_ProfileIO_ResetImportWarnings()
    local plan, why, chatLine = MSUF_ProfileIO_PrepareImport(str, "active")
    if not plan then
        print(chatLine)
        return false, why
    end
    local base, baseWhy = ImportTx.LiveBase(plan)
    if not base then
        chatLine = ImportFailedLine("Import failed: %s", baseWhy)
        print(chatLine)
        return false, baseWhy
    end
    ImportTx.Stage(plan, base)
    return ImportTx.Finish(plan)
end
--- Imports a string into a new profile and switches to it. The string is
--- decoded, validated, staged and normalized BEFORE the profile is created or
--- switched, so a rejected string creates nothing, switches nothing and
--- leaves SavedVariables untouched. A failed create stops there; a failed
--- switch switches back and removes the created profile, from Suite too.
--- Returns true, or false plus reason plus stage ("name", "exists", "decode",
--- "create" or "switch").
local function MSUF_ImportIntoNewProfile(name, str)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    MSUF_ProfileIO_ResetImportWarnings()
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then
        return false, "enter a new profile name", "name"
    end
    if ProfileNameTooLong(name) then return false, "profile name too long", "name" end
    --- Read-only existence check: the profile roots are not created before
    --- the string has been accepted.
    local profiles = type(MSUF_GlobalDB) == "table" and MSUF_GlobalDB.profiles or nil
    if type(profiles) == "table" and profiles[name] ~= nil then
        return false, "profile already exists", "exists"
    end
    local plan, why, chatLine = MSUF_ProfileIO_PrepareImport(str, "active")
    if not plan then
        print(chatLine)
        return false, why, "decode"
    end
    local base = {}
    if plan.kind ~= "all" then
        base = ImportTx.FactoryBase()
        if not base then
            ProfileChat("error", "Factory defaults are not available; profile was not created.")
            return false, "factory defaults unavailable", "create"
        end
    end
    ImportTx.Stage(plan, base)
    local previous = MSUF_ActiveProfile or "Default"
    local created = MSUF_CreateProfile(name)
    profiles = type(MSUF_GlobalDB) == "table" and MSUF_GlobalDB.profiles or nil
    if created ~= true or type(profiles) ~= "table" or type(profiles[name]) ~= "table" then
        return false, "could not create profile", "create"
    end
    local previousExists = type(profiles[previous]) == "table"
    MSUF_SwitchProfile(name)
    if MSUF_ActiveProfile ~= name then
        if previousExists then MSUF_SwitchProfile(previous) end
        profiles[name] = nil
        MSUF_ProfileIO_NotifySuiteLifecycle("delete", name)
        return false, "could not switch profile", "switch"
    end
    return ImportTx.Finish(plan)
end
---
--- External Wago UI Packs API (stateless by profileKey)
--- Goals:
--- - Allow tools to export/import a SPECIFIC profile by key without switching MSUF_ActiveProfile.
--- - Keep DB table references stable (important for runtime caches) when overwriting the ACTIVE profile.
--- - Zero regression: existing import/export code paths remain unchanged.
--- API:
--- ok, strOrErr = MSUF_ExportExternal(profileKey)
--- ok, errOrNil = MSUF_ImportExternal(profileString, profileKey)
---

local function MSUF_ProfileIO_EnsureProfileSystemInitialized()
    MSUF_ProfileIO_RunEnsureDB()
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    local active = MSUF_ActiveProfile
    local needsInit = type(active) ~= "string"
        or active == ""
        or type(MSUF_DB) ~= "table"
        or type(profiles[active]) ~= "table"
    if needsInit then
        InitProfiles = InitProfiles or MSUF.Require("MSUF_InitProfiles", "State/MSUF_Profiles.lua")
        InitProfiles()
    end
end
local function MSUF_ProfileIO_GetProfileTable(profileKey)
    if type(profileKey) ~= "string" or profileKey == "" then
         return nil
    end
    MSUF_ProfileIO_EnsureProfileSystemInitialized()
    return MSUF_GlobalDB.profiles[profileKey]
end

local function MSUF_ProfileIO_MaterializeProfileCopyForExport(profile, profileKey)
    if type(profile) ~= "table" then return nil, "not a table" end
    profile = MSUF_ProfileIO_TranslateProfileToCurrent(profile, {
        source = "external_export", markProfile = true, trustNormalizationMarker = true,
    })
    if MSUF.DefaultsSchema.IsQuarantinedProfile(profile) then return profile end
    MSUF.PublicGlobals.MSUF_NormalizePortraitRenderDB(profile)
    profile = MSUF.PublicGlobals.MSUF_NormalizeProfileDefaults(profile, false, true)
    MSUF_ProfileIO_EnsureUnitframeAlphaDB(profile)
    MSUF.GF.RepairGroupDB(profile)
    MSUF.MSUF_Auras3.NormalizeProfileDB(profile)
    return profile
end
local function MSUF_ProfileIO_OverwriteProfile(profileKey, plan)
    if type(profileKey) ~= "string" or profileKey == "" then
         return false, "invalid profileKey"
    end
    if type(plan) ~= "table" or type(plan.payload) ~= "table" then
         return false, "not a table"
    end
    --- plan is an accepted MSUF_ProfileIO_PrepareImport plan: its payload is
    --- already validated, translated and media-checked. The stored or active
    --- table only changes after the staged candidate survived every normalizer,
    --- so a stored profile is always the normalized one.
    MSUF_ProfileIO_EnsureProfileSystemInitialized()
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    local existing = MSUF_GlobalDB.profiles[profileKey]
    if existing == nil and ProfileNameTooLong(profileKey, true) then return false, "invalid profileKey" end
    local isActive = (profileKey == MSUF_ActiveProfile)
    local base = {}
    if not MSUF_ProfileIO_ImportVariants and type(existing) == "table" then
        base = existing
        if isActive and Variants and type(MSUF_DB) == "table" then
            local why
            base, why = Variants.BaseSnapshot(MSUF_DB, true)
            if not base then return false, why end
        end
    end
    local newTable = ImportTx.Stage(plan, base)
    if isActive then
        --- As for any import into the active profile: pending edits reach
        --- the sync members first, the imported settings stay local.
        if ProfileSync then ProfileSync.Flush() end
        PrepareProfileMutation()
    end
    if isActive and type(MSUF_DB) ~= "table" and type(existing) == "table" then
        MSUF_DB = existing
    end
    --- Keep references stable for ACTIVE profile (and if someone holds a ref to the existing table).
    if isActive and type(MSUF_DB) == "table" then
        --- Prefer wiping the active table ref (MSUF_DB) to avoid cache/reference drift.
        local target = MSUF_DB
        MSUF_WipeTable(target)
        for k, v in pairs(newTable) do
            target[k] = v
        end
        if MSUF.Castbars then MSUF.Castbars.Config.Invalidate() end
        MSUF_GlobalDB.profiles[profileKey] = target
        if MSUF.ProfileMigrations then MSUF.ProfileMigrations.AdoptNormalizedProfile(target) end
        if ProfileSync then ProfileSync.Rebase() end
        MSUF.ProfileIOCompleteFirstLoadImport()
        MSUF_ProfileIO_EnsureUnitframeAlphaDB()
        MSUF_ProfileIO_PostImportApply_Auras("all", target)
        MSUF_ProfileIO_PostImportApply_GroupFrames("all", target)
        MSUF_ProfileIO_PostImportApply_UnitAlphas("all", target)
        ApplyProfileRuntime("PROFILE_EXTERNAL_IMPORT", true)
        MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_EXTERNAL_IMPORT", profileKey)
        MSUF_ProfileIO_ReportImportWarnings()
        ImportTx.ReportKeptVariants(plan)
        return true
    end
    if type(existing) == "table" and not MSUF.DefaultsSchema.IsQuarantinedProfile(existing) then
        --- For non-active profiles we can still preserve reference stability if something else points at it.
        MSUF_WipeTable(existing)
        for k, v in pairs(newTable) do
            existing[k] = v
        end
        MSUF_GlobalDB.profiles[profileKey] = existing
        MSUF_ProfileIO_ReportImportWarnings()
        ImportTx.ReportKeptVariants(plan)
        MSUF.ProfileIOCompleteFirstLoadImport()
        return true
    end
    MSUF_GlobalDB.profiles[profileKey] = newTable
    MSUF_ProfileIO_ReportImportWarnings()
    MSUF.ProfileIOCompleteFirstLoadImport()
    return true
end
function MSUF.PublicGlobals.MSUF_ImportExternal(profileString, profileKey)
    MSUF_ProfileIO_ResetImportWarnings()
    if type(profileString) ~= "string" or not profileString:match("%S") then
         return false, "empty profileString"
    end
    if type(profileKey) ~= "string" or profileKey == "" then
         return false, "invalid profileKey"
    end
    local plan, why = MSUF_ProfileIO_PrepareImport(profileString, "external")
    if not plan then
        return false, why
    end
    return MSUF_ProfileIO_OverwriteProfile(profileKey, plan)
end
ExportPublic("MSUF_ImportExternal", MSUF.PublicGlobals.MSUF_ImportExternal)
--- Deprecated compatibility aliases (MSUF_Profiles_*) of the profile string API,
--- once used by load-order proxies; MSUF itself calls the canonical names.
ExportPublic("MSUF_Profiles_ExportExternal", MSUF.Require("MSUF_ExportExternal", "State/MSUF_Profiles.lua"))
ExportPublic("MSUF_Profiles_ImportExternal", MSUF.Require("MSUF_ImportExternal", "State/MSUF_Profiles.lua"))
--- Globals for the Options module.
ExportPublic("MSUF_ExportSelectionToString", MSUF_ExportSelectionToString)
ExportPublic("MSUF_ImportFromString", MSUF_ImportFromString)
--- Always expose the real implementations under stable, explicit names.
--- This lets other modules (or load-order proxies) call the correct logic even if _G.MSUF_ImportFromString was set earlier.
ExportPublic("MSUF_Profiles_ExportSelectionToString", MSUF_ExportSelectionToString)
ExportPublic("MSUF_Profiles_ImportFromString", MSUF_ImportFromString)
ExportPublic("MSUF_ImportIntoNewProfile", MSUF_ImportIntoNewProfile)
ExportPublic("MSUF_Profiles_ImportIntoNewProfile", MSUF_ImportIntoNewProfile)
MSUF.Compat = MSUF.Compat or {}
MSUF.Compat.DeprecatedAliases = MSUF.Compat.DeprecatedAliases or {}
MSUF.Compat.DeprecatedAliases.MSUF_Profiles_ExportExternal = "MSUF_ExportExternal"
MSUF.Compat.DeprecatedAliases.MSUF_Profiles_ImportExternal = "MSUF_ImportExternal"
MSUF.Compat.DeprecatedAliases.MSUF_Profiles_ExportSelectionToString = "MSUF_ExportSelectionToString"
MSUF.Compat.DeprecatedAliases.MSUF_Profiles_ImportFromString = "MSUF_ImportFromString"
MSUF.Compat.DeprecatedAliases.MSUF_Profiles_ImportIntoNewProfile = "MSUF_ImportIntoNewProfile"
ExportPublic("MSUF_ProfileIO_TranslateProfileToCurrent", MSUF_ProfileIO_TranslateProfileToCurrent)
ExportPublic("MSUF_ProfileIO_TranslateProfilesToCurrent", MSUF_ProfileIO_TranslateProfilesToCurrent)
ExportPublic("MSUF_CreateProfile", MSUF_CreateProfile)
ExportPublic("MSUF_SwitchProfile", MSUF_SwitchProfile)
ExportPublic("MSUF_ResetProfile", MSUF_ResetProfile)
ExportPublic("MSUF_DeleteProfile", MSUF_DeleteProfile)
ExportPublic("MSUF_DeleteProfiles", MSUF_DeleteProfiles)
ExportPublic("MSUF_CopyProfile", MSUF_CopyProfile)
ExportPublic("MSUF_RenameProfile", MSUF_RenameProfile)
ExportPublic("MSUF_GetAllProfiles", MSUF_GetAllProfiles)
if type(MSUF) == "table" then
    MSUF.MSUF_ExportSelectionToString = MSUF_ExportSelectionToString
    MSUF.MSUF_ImportFromString        = MSUF_ImportFromString
    MSUF.MSUF_ImportIntoNewProfile    = MSUF_ImportIntoNewProfile
    MSUF.MSUF_ProfileIO_TranslateProfileToCurrent = MSUF_ProfileIO_TranslateProfileToCurrent
    MSUF.MSUF_ProfileIO_TranslateProfilesToCurrent = MSUF_ProfileIO_TranslateProfilesToCurrent
end

Parts.MSUF_ProfileIO_GetProfileTable = MSUF_ProfileIO_GetProfileTable
Parts.MSUF_ProfileIO_MaterializeProfileCopyForExport = MSUF_ProfileIO_MaterializeProfileCopyForExport

-- Complete forward bindings once; gameplay closures keep direct local calls.
Parts.Bind1()
Parts.Bind3()
MSUF.ProfilesParts = nil
