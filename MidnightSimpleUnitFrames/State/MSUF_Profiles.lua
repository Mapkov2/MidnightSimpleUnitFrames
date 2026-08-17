--- State/MSUF_Profiles.lua
--- Profile storage, import/export, and active-profile state.
---
--- This file is the cold boundary between SavedVariables and the live addon.
--- It is allowed to copy tables, normalize old schemas, and fan out profile
--- changes to runtime modules, but gameplay event handlers should never call
--- into the expensive import/export paths directly.
---
--- Mental model:
--- * MSUF_GlobalDB.profiles stores named profile tables.
--- * MSUF_GlobalDB.char[charKey] stores the active profile and spec bindings.
--- * MSUF_DB always points at the active profile table for legacy callers.
--- Keep the MSUF_DB table reference stable during imports where possible:
--- several modules cache table references and only invalidate on the explicit
--- post-profile apply hook below.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF
MSUF.Public = MSUF.Public or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local MSUF_PROFILE_IMPORT_LIMITS = {
    encodedBytes = 8 * 1024 * 1024,
    decodedBytes = 32 * 1024 * 1024,
    depth = 64,
    nodes = 250000,
}

--- Parse the narrow Lua-table syntax emitted by the legacy serializer without
--- compiling or executing user input. Supported values are tables, finite
--- numbers, quoted strings, booleans, and nil. Functions, expressions,
--- metatables, long strings, and arbitrary identifiers are rejected.
local function MSUF_ProfileIO_ParseLegacyTable(str)
    if type(str) ~= "string" then return nil, "legacy import must be text" end
    if #str > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil, "legacy import is too large" end

    local state = { text = str, pos = 1, len = #str, nodes = 0, stringBytes = 0 }
    local parseValue
    local function Fail(message)
        return nil, tostring(message or "invalid legacy table") .. " at byte " .. tostring(state.pos)
    end
    local function SkipSpace()
        while state.pos <= state.len do
            local ch = state.text:sub(state.pos, state.pos)
            if ch:match("%s") then
                state.pos = state.pos + 1
            elseif state.text:sub(state.pos, state.pos + 1) == "--" then
                if state.text:sub(state.pos + 2, state.pos + 3) == "[[" then
                    local close = state.text:find("]]", state.pos + 4, true)
                    if not close then return false, "unterminated comment" end
                    state.pos = close + 2
                else
                    local newline = state.text:find("\n", state.pos + 2, true)
                    state.pos = newline and (newline + 1) or (state.len + 1)
                end
            else
                break
            end
        end
        return true
    end
    local function CountNode()
        state.nodes = state.nodes + 1
        if state.nodes > MSUF_PROFILE_IMPORT_LIMITS.nodes then return false, "legacy table has too many values" end
        return true
    end
    local function ParseIdentifier()
        local start = state.pos
        local first = state.text:sub(state.pos, state.pos)
        if not first:match("[_%a]") then return nil end
        state.pos = state.pos + 1
        while state.pos <= state.len and state.text:sub(state.pos, state.pos):match("[_%w]") do
            state.pos = state.pos + 1
        end
        return state.text:sub(start, state.pos - 1)
    end
    local function ParseString()
        local quote = state.text:sub(state.pos, state.pos)
        state.pos = state.pos + 1
        local out, count = {}, 0
        while state.pos <= state.len do
            local ch = state.text:sub(state.pos, state.pos)
            state.pos = state.pos + 1
            if ch == quote then
                local value = table.concat(out)
                state.stringBytes = state.stringBytes + #value
                if state.stringBytes > MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then
                    return nil, "legacy table strings are too large"
                end
                return value
            end
            if ch == "\n" or ch == "\r" then return nil, "unterminated string" end
            if ch == "\\" then
                if state.pos > state.len then return nil, "unterminated escape" end
                local esc = state.text:sub(state.pos, state.pos)
                state.pos = state.pos + 1
                local mapped = ({ a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" })[esc]
                if mapped then
                    ch = mapped
                elseif esc:match("%d") then
                    local digits = esc
                    for _ = 1, 2 do
                        local digit = state.text:sub(state.pos, state.pos)
                        if not digit:match("%d") then break end
                        digits = digits .. digit
                        state.pos = state.pos + 1
                    end
                    local byte = tonumber(digits)
                    if not byte or byte > 255 then return nil, "invalid decimal escape" end
                    ch = string.char(byte)
                elseif esc == "\n" then
                    ch = "\n"
                else
                    return nil, "unsupported string escape"
                end
            end
            count = count + 1
            out[count] = ch
        end
        return nil, "unterminated string"
    end
    local function ParseNumber()
        local rest = state.text:sub(state.pos)
        local token = rest:match("^[+-]?0[xX][%da-fA-F]+")
            or rest:match("^[+-]?%d+%.?%d*[eE][+-]?%d+")
            or rest:match("^[+-]?%d*%.%d+[eE][+-]?%d+")
            or rest:match("^[+-]?%d+%.?%d*")
            or rest:match("^[+-]?%d*%.%d+")
        if not token or token == "" or token == "+" or token == "-" then return nil, "invalid number" end
        local value = tonumber(token)
        if not value or value ~= value or value == math.huge or value == -math.huge then return nil, "invalid number" end
        state.pos = state.pos + #token
        return value
    end
    local function ParseTable(depth)
        if depth > MSUF_PROFILE_IMPORT_LIMITS.depth then return nil, "legacy table is too deep" end
        state.pos = state.pos + 1
        local tbl, arrayIndex = {}, 1
        while true do
            local ok, why = SkipSpace()
            if not ok then return nil, why end
            local ch = state.text:sub(state.pos, state.pos)
            if ch == "}" then state.pos = state.pos + 1; return tbl end
            if ch == "" then return nil, "unterminated table" end

            local key, value
            if ch == "[" then
                state.pos = state.pos + 1
                key, why = parseValue(depth + 1)
                if why then return nil, why end
                ok, why = SkipSpace()
                if not ok then return nil, why end
                if state.text:sub(state.pos, state.pos) ~= "]" then return Fail("expected ]") end
                state.pos = state.pos + 1
                ok, why = SkipSpace()
                if not ok then return nil, why end
                if state.text:sub(state.pos, state.pos) ~= "=" then return Fail("expected =") end
                state.pos = state.pos + 1
                value, why = parseValue(depth + 1)
            else
                local saved = state.pos
                local identifier = ParseIdentifier()
                if identifier then
                    ok, why = SkipSpace()
                    if not ok then return nil, why end
                end
                if identifier and state.text:sub(state.pos, state.pos) == "=" then
                    key = identifier
                    state.pos = state.pos + 1
                    value, why = parseValue(depth + 1)
                else
                    state.pos = saved
                    key = arrayIndex
                    arrayIndex = arrayIndex + 1
                    value, why = parseValue(depth + 1)
                end
            end
            if why then return nil, why end
            if type(key) ~= "string" and type(key) ~= "number" then return nil, "unsupported table key" end
            if value ~= nil then tbl[key] = value end
            ok, why = SkipSpace()
            if not ok then return nil, why end
            ch = state.text:sub(state.pos, state.pos)
            if ch == "," or ch == ";" then
                state.pos = state.pos + 1
            elseif ch ~= "}" then
                return Fail("expected table separator")
            end
        end
    end
    parseValue = function(depth)
        local ok, why = SkipSpace()
        if not ok then return nil, why end
        ok, why = CountNode()
        if not ok then return nil, why end
        local ch = state.text:sub(state.pos, state.pos)
        if ch == "{" then return ParseTable(depth) end
        if ch == '"' or ch == "'" then return ParseString() end
        if ch:match("[+%-%d%.]") then return ParseNumber() end
        local identifier = ParseIdentifier()
        if identifier == "true" then return true end
        if identifier == "false" then return false end
        if identifier == "nil" then return nil end
        return nil, "unsupported value"
    end

    local ok, why = SkipSpace()
    if not ok then return nil, why end
    if state.text:sub(state.pos, state.pos + 5) == "return"
        and not state.text:sub(state.pos + 6, state.pos + 6):match("[_%w]") then
        state.pos = state.pos + 6
    end
    local value
    value, why = parseValue(1)
    if why then return nil, why end
    if type(value) ~= "table" then return nil, "legacy import must contain a table" end
    ok, why = SkipSpace()
    if not ok then return nil, why end
    if state.pos <= state.len then return Fail("unexpected trailing input") end
    return value
end
local function MSUF_ProfileIO_LoadLegacyChunk(str)
    local tbl, err = MSUF_ProfileIO_ParseLegacyTable(str)
    if not tbl then return nil, err end
    -- Preserve the old internal callable contract without compiling input.
    return function() return tbl end
end

--- Small runtime bridge helpers. Profile code owns the DB mutation, then asks
--- each subsystem to rebuild whatever cached view it keeps. These wrappers keep
--- the rest of the file readable and make missing optional modules harmless.
local function MSUF_ProfileIO_RunEnsureDB(force, allowPersistedFastPath, temporaryProfile)
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) == "function" then
        ensureDB(force == true, allowPersistedFastPath == true, temporaryProfile == true)
        return true
    end
    return false
end
local function MSUF_ProfileIO_ReportBoundaryError(label, err)
    local message = "MSUF ProfileIO " .. tostring(label or "callback") .. ": " .. tostring(err)
    ExportPublic("MSUF_ProfileIO_LastRuntimeApplyError", message)
    local handler = _G.geterrorhandler and _G.geterrorhandler()
    if type(handler) == "function" then
        local reported = pcall(handler, message)
        if reported then return end
    end
    if type(_G.print) == "function" then
        _G.print("|cffffd700MSUF ProfileIO:|r", message)
    end
end
local function MSUF_ProfileIO_RunProtected(label, fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, r1, r2, r3, r4 = pcall(fn, ...)
    if not ok then
        MSUF_ProfileIO_ReportBoundaryError(label, r1)
        return false, r1
    end
    return true, r1, r2, r3, r4
end

-- Profile imports can enter through Menu2, legacy globals, or the external
-- Wago API. Complete first-load at the shared mutation boundary so every
-- successful path records the same durable lifecycle result.
function MSUF.ProfileIOCompleteFirstLoadImport()
    local firstLoad = MSUF and MSUF.FirstLoad6
    if type(firstLoad) ~= "table" or type(firstLoad.CompleteProfileImport) ~= "function" then
        return false
    end
    local called, completed = MSUF_ProfileIO_RunProtected(
        "FirstLoad.CompleteProfileImport",
        firstLoad.CompleteProfileImport,
        firstLoad,
        "import"
    )
    if not called then return false end
    if completed == true then
        local menu = MSUF and MSUF.MSUF2
        if type(menu) == "table" and type(menu.InvalidatePage) == "function" then
            menu.InvalidatePage("home")
        end
    end
    return completed == true
end
local function MSUF_ProfileIO_RunApplyAllSettings(applyMask)
    local UF = MSUF and MSUF.UF
    if UF and UF.Apply then
        return MSUF_ProfileIO_RunProtected("UF.Apply", UF.Apply, nil, applyMask)
    end
    return false
end
local function MSUF_ProfileIO_RunDisableBlizzardFrames()
    local UF = MSUF and MSUF.UF
    if UF and type(UF.DisableBlizzardFrames) == "function" then
        return MSUF_ProfileIO_RunProtected("UF.DisableBlizzardFrames", UF.DisableBlizzardFrames)
    end
    return false
end
local function MSUF_ProfileIO_SafeMSUFScale()
    local g = type(MSUF_DB) == "table" and type(MSUF_DB.general) == "table" and MSUF_DB.general or nil
    local scale = tonumber(g and g.msufUiScale) or 1
    if scale < 0.25 then
        scale = 1
    elseif scale > 2.0 then
        scale = 2.0
    end
    return scale
end
local function MSUF_ProfileIO_RunFrameScaleApply()
    local scale = MSUF_ProfileIO_SafeMSUFScale()
    if type(_G.MSUF_ApplyMsufScale) == "function" then
        _G.MSUF_ApplyMsufScale(scale)
        return true
    end
    local UF = MSUF and MSUF.UF
    local frames = UF and UF.frames
    if type(frames) == "table" then
        for _, frame in pairs(frames) do
            if frame and type(frame.SetScale) == "function" then
                frame:SetScale(scale)
            end
        end
        return true
    end
    return false
end
local MSUF_ProfileIO_CallGlobal

MSUF_ProfileIO_CallGlobal = function(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then
        return false
    end
    return MSUF_ProfileIO_RunProtected(name, fn, ...)
end

local function MSUF_ProfileIO_ApplyCastbarRuntime(reason)
    MSUF_ProfileIO_CallGlobal("MSUF_Castbars_OnSettingsChanged", reason)
    local applyAll = _G.MSUF_ApplyAllCastbarsAndSync
    if type(applyAll) == "function" then
        return MSUF_ProfileIO_RunProtected("MSUF_ApplyAllCastbarsAndSync", applyAll)
    end

    local units = { "player", "target", "focus", "boss" }
    local applied = false
    for i = 1, #units do
        local unit = units[i]
        if MSUF_ProfileIO_CallGlobal("MSUF_ApplyCastbarUnitAndSync", unit) then
            applied = true
        elseif MSUF_ProfileIO_CallGlobal("MSUF_ApplyCastbarVisualsForUnit", unit) then
            applied = true
        end
    end
    if applied then
        return true
    end
    MSUF_ProfileIO_CallGlobal("MSUF_ReanchorPlayerCastBar")
    MSUF_ProfileIO_CallGlobal("MSUF_ReanchorTargetCastBar")
    MSUF_ProfileIO_CallGlobal("MSUF_ReanchorFocusCastBar")
    MSUF_ProfileIO_CallGlobal("MSUF_ReanchorBossCastBar")
    return MSUF_ProfileIO_CallGlobal("MSUF_UpdateCastbarVisuals")
end

--- The coordinated UF apply already owns unit-frame text, while the explicit
--- class-power/castbar passes below own their fonts. Keep one font-runtime pass
--- for external consumers and Auras3. Imports refresh their aura payload before
--- this hook, so they skip the otherwise required profile-switch aura refresh.
local function MSUF_ProfileIO_ApplyExternalFontFollowers(skipAuras)
    local applyFonts = _G.MSUF_UpdateAllFonts_Immediate
    if type(applyFonts) == "function" then
        return MSUF_ProfileIO_RunProtected(
            "MSUF_UpdateAllFonts_Immediate",
            applyFonts,
            nil,
            true,
            true,
            true,
            skipAuras == true
        )
    end

    if skipAuras == true then return false end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.ApplyFontsFromGlobal) == "function" then
        return MSUF_ProfileIO_RunProtected(
            "Auras3.ApplyFontsFromGlobal",
            a3.ApplyFontsFromGlobal,
            nil,
            "MSUF_PROFILE_FONT_FOLLOWERS"
        )
    end
    if a3 and type(a3.RefreshAll) == "function" then
        return MSUF_ProfileIO_RunProtected("Auras3.RefreshAll", a3.RefreshAll)
    end
    return false
end

local MSUF_ProfileIO_PostProfileRuntimeApply
local function MSUF_ProfileIO_CheckLocaleReload()
    local namespace = _G.MSUF_NS or _G.MSUF
    if not (namespace and type(namespace.SetLocale) == "function") then return false end
    local configured = type(namespace.ResolveConfiguredLocale) == "function"
        and namespace.ResolveConfiguredLocale(_G.MSUF_DB)
        or (_G.GetLocale and _G.GetLocale())
    local _, reloadRequired = namespace.SetLocale(configured)
    if reloadRequired ~= true then return false end

    local menu = namespace.MSUF2 or _G.MSUF2
    if menu and type(menu.ShowLocaleReloadRequired) == "function" then
        menu.ShowLocaleReloadRequired()
    elseif _G.print then
        _G.print("|cffffd700MSUF:|r Menu language changed with the profile. Reload the UI to apply it.")
    end
    return true
end
local function MSUF_ProfileIO_InCombatLockdown()
    return (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false
end

--- One fanout point after profile mutations. If protected frame work is unsafe
--- in combat, the expensive/restricted part is deferred but cheap visual state
--- such as scale and Blizzard-frame ownership is still nudged immediately.
local function MSUF_ProfileIO_DeferPostProfileRuntimeApply(reason, applyAll)
    if not MSUF_ProfileIO_InCombatLockdown() then
        return false
    end
    ExportPublic("MSUF_ProfileIO_PendingPostProfileRuntimeApply", {
        reason = reason or "PROFILE_APPLY",
        applyAll = applyAll == true,
    })
    local f = _G.MSUF_ProfileIO_PostProfileDeferFrame
    if not f and type(_G.CreateFrame) == "function" then
        f = _G.CreateFrame("Frame")
        ExportPublic("MSUF_ProfileIO_PostProfileDeferFrame", f)
        f:SetScript("OnEvent", function(self, event)
            if event ~= "PLAYER_REGEN_ENABLED" then return end
            if MSUF_ProfileIO_InCombatLockdown() then return end
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local pending = _G.MSUF_ProfileIO_PendingPostProfileRuntimeApply
            ExportPublic("MSUF_ProfileIO_PendingPostProfileRuntimeApply", nil)
            if pending and MSUF_ProfileIO_PostProfileRuntimeApply then
                MSUF_ProfileIO_PostProfileRuntimeApply(pending.reason or "PROFILE_APPLY_AFTER_COMBAT", pending.applyAll == true)
            end
        end)
    end
    if f and f.RegisterEvent then
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    MSUF_ProfileIO_RunDisableBlizzardFrames()
    MSUF_ProfileIO_RunFrameScaleApply()
    return true
end
MSUF_ProfileIO_PostProfileRuntimeApply = function(reason, applyAll)
    reason = reason or "PROFILE_APPLY"
    if MSUF_ProfileIO_DeferPostProfileRuntimeApply(reason, applyAll) then
        return
    end
    MSUF_ProfileIO_RunDisableBlizzardFrames()
    MSUF_ProfileIO_RunFrameScaleApply()
    MSUF_ProfileIO_CallGlobal("MSUF_TargetSoundDriver_ApplySetting")
    MSUF_ProfileIO_CallGlobal("MSUF_NSRTNicknames_ApplySetting")
    local activeGeneral = _G.MSUF_DB and _G.MSUF_DB.general
    MSUF_ProfileIO_CallGlobal("MSUF_EllesmereEditMode_SetEnabled",
        not (type(activeGeneral) == "table" and activeGeneral.ellesmereEditModeIntegration == false))
    MSUF_ProfileIO_CallGlobal("MSUF_Grid2EditMode_SetEnabled",
        not (type(activeGeneral) == "table" and activeGeneral.grid2EditModeIntegration == false))
    MSUF_ProfileIO_CallGlobal("MSUF_DetailsEditMode_SetEnabled",
        not (type(activeGeneral) == "table" and activeGeneral.detailsEditModeIntegration == false))
    MSUF_ProfileIO_CallGlobal("MSUF_DominosEditMode_SetEnabled",
        not (type(activeGeneral) == "table" and activeGeneral.dominosEditModeIntegration == false))
    MSUF_ProfileIO_CallGlobal("MSUF_DandersEditMode_SetEnabled",
        not (type(activeGeneral) == "table" and activeGeneral.dandersEditModeIntegration == false))
    MSUF_ProfileIO_CallGlobal("MSUF_BlizzardEditMode_SetEnabled",
        not (type(activeGeneral) == "table" and activeGeneral.blizzardEditModeIntegration == false))
    --- The profile carries the last committed Blizzard Edit Mode arrangement
    --- (general.blizzardEditModeSnapshot); re-apply it for the new profile.
    MSUF_ProfileIO_CallGlobal("MSUF_BlizzardEditMode_ApplyProfileSnapshot")
    --- Group-frame config tables are cached by identity. Drop those references
    --- before the runtime rebuild reads the newly active profile root.
    MSUF_ProfileIO_CallGlobal("MSUF_GF_InvalidateConfCache")

    --- The number-abbreviation style is held as an upvalue in every text
    --- consumer, so it must be re-resolved from the new profile before the
    --- rebuild below formats anything.
    local numberFormat = MSUF and MSUF.NumberFormat
    if numberFormat and type(numberFormat.Refresh) == "function" then
        MSUF_ProfileIO_RunProtected("MSUF.NumberFormat.Refresh", numberFormat.Refresh)
    end

    local nsGlobal = _G.MSUF_NS
    local core = nsGlobal and nsGlobal.MSUF_UnitframeCore
    if core and type(core.InvalidateAllFrameConfigs) == "function" then
        core.InvalidateAllFrameConfigs()
    end
    local UF = MSUF and MSUF.UF
    local metadata = UF and UF.Metadata
    local coordinatedApplyMask = metadata and metadata.coordinatedApplyMask
    local notifyCalled, notifyApplied = MSUF_ProfileIO_CallGlobal(
        "MSUF_UFCore_NotifyConfigChanged",
        nil,
        true,
        true,
        reason,
        coordinatedApplyMask
    )
    -- A load-order proxy or a deferred/failed core apply can be callable while
    -- still returning nil/false. Treat only an explicit true result as a
    -- completed apply; the direct UF.Apply fallback is idempotent and ensures
    -- newly re-enabled frames are actually spawned and registered.
    if notifyCalled ~= true or notifyApplied ~= true then
        MSUF_ProfileIO_RunApplyAllSettings(coordinatedApplyMask)
    end
    MSUF_ProfileIO_CallGlobal("MSUF_ApplyModules")
    MSUF_ProfileIO_CallGlobal("MSUF_GF_RebuildAll")
    if not MSUF_ProfileIO_CallGlobal("MSUF_ClassPower_Apply", { full = true, cdm = true }) then
        MSUF_ProfileIO_CallGlobal("MSUF_ClassPower_Refresh")
        MSUF_ProfileIO_CallGlobal("MSUF_ClassPower_RefreshTextures")
        MSUF_ProfileIO_CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true)
    end
    MSUF_ProfileIO_CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
    MSUF_ProfileIO_ApplyCastbarRuntime(reason)
    MSUF_ProfileIO_ApplyExternalFontFollowers(applyAll == true)
    MSUF_ProfileIO_CheckLocaleReload()
end
--- Compact codec (backward compatible)
--- New export format (preferred):
--- MSUF4: base64(CBOR(table)) using Blizzard C_EncodingUtil
--- Legacy import formats supported:
--- MSUF3: base64(CBOR(table)) using Blizzard C_EncodingUtil
--- MSUF2: LibDeflate 'print-safe' encoding of deflate-compressed payload (common Wago/WA style)
--- MSUF2: base64(deflate(CBOR(table))) from earlier internal experiments
--- Design goals:
--- * Export always uses Blizzard (MSUF4) when available.
--- * Import accepts MSUF4 + MSUF3 + legacy MSUF2 variants automatically.
--- * For MSUF2 print-safe, we decode the print alphabet ourselves and then use Blizzard
--- DecompressString when available (no bundled LibDeflate needed).
--- * Never fall back to legacy loadstring() for MSUF2/MSUF3/MSUF4 prefixes.
do
    local function GetEncodingUtil()
        local E = _G.C_EncodingUtil
        if not E then  return nil end
        if type(E.SerializeCBOR) ~= "function" then  return nil end
        if type(E.DeserializeCBOR) ~= "function" then  return nil end
        if type(E.EncodeBase64) ~= "function" then  return nil end
        if type(E.DecodeBase64) ~= "function" then  return nil end
        --- Compress/Decompress are optional depending on branch/client.
         return E
    end
    local function GetDeflateEnum()
        local Enum = _G.Enum
        if Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate then
            return Enum.CompressionMethod.Deflate
        end
         return nil
    end
    local function StripWS(s)
        return (s:gsub("%s+", ""))
    end
    local function CleanBase64(s)
        s = StripWS(s or "")
        local rem = #s % 4
        if rem == 1 then
            return nil
        elseif rem == 2 then
            s = s .. "=="
        elseif rem == 3 then
            s = s .. "="
        end
        return s
    end
    --- LibDeflate's print-safe alphabet is 64 chars:
    --- 0-9, A-Z, a-z, (, )
    local _PRINT_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz()"
    local _PRINT_MAP
    local function EnsurePrintMap()
        if _PRINT_MAP then  return _PRINT_MAP end
        local t = {}
        for i = 1, #_PRINT_ALPHABET do
            t[_PRINT_ALPHABET:sub(i, i)] = i - 1
        end
        _PRINT_MAP = t
         return t
    end
    --- Decode LibDeflate:EncodeForPrint output into raw bytes.
    --- LibDeflate's print codec has existed in multiple implementations; to be robust,
    --- we try BOTH bit-order variants (LSB-first and MSB-first) and accept whichever
    --- yields a payload that successfully decompresses/deserializes.
    local function DecodeForPrint_Variants(data)
        if type(data) ~= "string" or data == "" then  return nil, nil end
        data = StripWS(data)
        local map = EnsurePrintMap()
        --- Variant A: LSB-first packing
        local function decode_lsb()
            local out, outLen = {}, 0
            local acc, bits = 0, 0
            for i = 1, #data do
                local v = map[data:sub(i,i)]
                if v == nil then  return nil end
                acc = acc + v * (2 ^ bits)
                bits = bits + 6
                while bits >= 8 do
                    local b = acc % 256
                    acc = (acc - b) / 256
                    bits = bits - 8
                    outLen = outLen + 1
                    out[outLen] = string.char(b)
                end
            end
            return table.concat(out)
        end
        --- Variant B: MSB-first packing
        local function decode_msb()
            local out, outLen = {}, 0
            local acc, bits = 0, 0
            for i = 1, #data do
                local v = map[data:sub(i,i)]
                if v == nil then  return nil end
                acc = acc * 64 + v
                bits = bits + 6
                while bits >= 8 do
                    local shift = bits - 8
                    local b = math.floor(acc / (2 ^ shift)) % 256
                    --- keep only the remaining low bits
                    acc = acc % (2 ^ shift)
                    bits = shift
                    outLen = outLen + 1
                    out[outLen] = string.char(b)
                end
            end
            return table.concat(out)
        end
        return decode_lsb(), decode_msb()
    end
    local TryDeserialize
    -- Import codecs and optional serializer libraries consume user-provided
    -- bytes. Rejection may raise, so these boundaries intentionally convert an
    -- exception into a normal decode miss; callers show the user-facing error.
    local function TryCodecCall(fn, ...)
        if type(fn) ~= "function" then return false end
        return pcall(fn, ...)
    end
    local function TryBlizzardDecompress(E, compressed)
        if not E or type(compressed) ~= "string" then  return nil end
        if #compressed > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        if type(E.DecompressString) ~= "function" then  return nil end
        local method = GetDeflateEnum()
        local ok, res
        if method ~= nil then
            ok, res = TryCodecCall(E.DecompressString, compressed, method)
            if ok and type(res) == "string" and #res <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return res end
        end
        ok, res = TryCodecCall(E.DecompressString, compressed)
        if ok and type(res) == "string" and #res <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return res end
         return nil
    end
    local function GetLibDeflate()
        if _G.LibDeflate and type(_G.LibDeflate.DecompressDeflate) == "function" then
            return _G.LibDeflate
        end
        local libStub = _G.LibStub
        if libStub and type(libStub.GetLibrary) == "function" then
            -- silent=true: GetLibrary returns nil for missing libs, no throw.
            local lib = libStub:GetLibrary("LibDeflate", true)
            if lib and type(lib.DecompressDeflate) == "function" then
                return lib
            end
        end
        return nil
    end
    local function TryLibDeflateDecompress(compressed)
        local lib = GetLibDeflate()
        if not lib or type(compressed) ~= "string" then return nil end
        if #compressed > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        local ok, plain = TryCodecCall(lib.DecompressDeflate, lib, compressed)
        if ok and type(plain) == "string" and #plain <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return plain end
        return nil
    end
    --- Prefer the matching decompressor, while retaining the raw legacy path.
    --- Every codec attempt is protected because malformed user input is an
    --- expected decode miss, not an addon runtime error.
    local function TryDeserializeMaybeCompressed(E, payload)
        if type(payload) ~= "string" then return nil end
        if #payload > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        local plain = TryBlizzardDecompress(E, payload)
        local result = TryDeserialize(E, plain or payload)
        if result then return result end
        local libPlain = TryLibDeflateDecompress(payload)
        if libPlain and libPlain ~= plain then
            result = TryDeserialize(E, libPlain)
            if result then return result end
        end
        if plain then return TryDeserialize(E, payload) end
        return nil
    end
    local function TryBlizzardCompress(E, plain)
        if not E or type(plain) ~= "string" then  return nil end
        if type(E.CompressString) ~= "function" then
             return nil
        end
        -- Deterministic form selection: the Deflate enum's presence is the
        -- capability signal for the method-taking arity.
        local method = GetDeflateEnum()
        local ok, res
        if method ~= nil then
            ok, res = TryCodecCall(E.CompressString, plain, method, 9)
            if ok and type(res) == "string" then return res end
            ok, res = TryCodecCall(E.CompressString, plain, method)
            if ok and type(res) == "string" then return res end
        end
        ok, res = TryCodecCall(E.CompressString, plain)
        if ok and type(res) == "string" then return res end
         return nil
    end
    --- Container routing avoids a blind try/catch chain: the three
    --- supported wire formats are self-identifying. AceSerializer strings start
    --- with "^1", very old MSUF exports are a Lua table literal "{...}", and
    --- everything else is MSUF's own CBOR envelope. Each chosen decoder still
    --- fails closed on malformed bytes.
    TryDeserialize = function(E, payload)
        if not E or type(payload) ~= "string" then  return nil end
        if #payload > MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return nil end
        if payload:sub(1, 2) == "^1" then
            local libStub = _G.LibStub
            local Ace = libStub and type(libStub.GetLibrary) == "function"
                and libStub:GetLibrary("AceSerializer-3.0", true) or nil
            if not (Ace and type(Ace.Deserialize) == "function") then return nil end
            local ok, success, t = TryCodecCall(Ace.Deserialize, Ace, payload)
            if ok and success and type(t) == "table" then return t end
            return nil
        end
        local trimmed = payload:match("^%s*(.-)%s*$")
        if trimmed and trimmed:sub(1, 1) == "{" and trimmed:sub(-1) == "}" then
            local fn = MSUF_ProfileIO_LoadLegacyChunk(trimmed)
            if not fn then return nil end
            local t = fn()
            if type(t) == "table" then return t end
            return nil
        end
        if type(E.DeserializeCBOR) ~= "function" then return nil end
        local ok, tbl = TryCodecCall(E.DeserializeCBOR, payload)
        if ok and type(tbl) == "table" then return tbl end
        return nil
    end
    local function IsSecretRuntimeValue(value)
        local isSecret = _G.issecretvalue
        if type(isSecret) ~= "function" then
            return false
        end
        return isSecret(value) == true
    end
    local function CompactSerializableCopy(value, seen)
        if IsSecretRuntimeValue(value) then
            return nil
        end
        local tv = type(value)
        if tv == "nil" or tv == "number" or tv == "string" or tv == "boolean" then
            return value
        end
        if tv ~= "table" then
            return nil
        end
        seen = seen or {}
        if seen[value] then
            return nil
        end
        seen[value] = true
        local out = {}
        for k, v in pairs(value) do
            local kt = type(k)
            if kt == "number" or kt == "string" or kt == "boolean" then
                local safeValue = CompactSerializableCopy(v, seen)
                if safeValue ~= nil then
                    out[k] = safeValue
                end
            end
        end
        seen[value] = nil
        return out
    end
    local function TryEncodeCompactPayload(E, tbl, prefix)
        local encoded, bin = TryCodecCall(E.SerializeCBOR, tbl)
        if not encoded or type(bin) ~= "string" then return nil end
        --- Prefer smaller strings when compression exists.
        local payload = TryBlizzardCompress(E, bin) or bin
        local base64OK, b64 = TryCodecCall(E.EncodeBase64, payload)
        if not base64OK or type(b64) ~= "string" then return nil end
        return tostring(prefix or "MSUF4") .. ":" .. b64
    end
    local function EncodeCompactTable(tbl, prefix)
        local E = GetEncodingUtil()
        if not E then  return nil end
        local compact = TryEncodeCompactPayload(E, tbl, prefix)
        if compact then  return compact end
        --- Some dirty runtime profiles can contain transient values that cannot
        --- be CBOR-encoded. Drop those the same way the Lua fallback would.
        local safe = CompactSerializableCopy(tbl)
        if safe then
            return TryEncodeCompactPayload(E, safe, prefix)
        end
        return nil
    end
    local function EncodeCompactTableMSUF3(tbl)
        return EncodeCompactTable(tbl, "MSUF3")
    end
    local function TryDecodeCompactString(str)
        if type(str) ~= "string" then  return nil end
        if #str > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        local E = GetEncodingUtil()
        if not E then  return nil end
        local s = str:match("^%s*(.-)%s*$")
        if not s then  return nil end
        --- MSUF4/MSUF3: base64(CBOR) [optionally compressed]
        do
            local b64 = s:match("^MSUF[34]:%s*(.+)$")
            if b64 then
                b64 = CleanBase64(b64)
                if not b64 then  return nil end
                local decoded, blob = TryCodecCall(E.DecodeBase64, b64)
                if decoded and type(blob) == "string" then
                    local t = TryDeserializeMaybeCompressed(E, blob)
                    if t then  return t end
                end
                  return nil
            end
        end
        --- MSUF2: legacy variants
        do
            local payload = s:match("^MSUF2:%s*(.+)$")
            if not payload then  return nil end
            payload = payload:gsub("^%s+", ""):gsub("%s+$", "")
            --- 1) Try Blizzard base64 first (older internal MSUF2 variant)
            local b64 = CleanBase64(payload)
            if b64 then
                local decoded, blob = TryCodecCall(E.DecodeBase64, b64)
                if decoded and type(blob) == "string" then
                    local t = TryDeserializeMaybeCompressed(E, blob)
                    if t then  return t end
                end
            end
            --- 2) Try LibDeflate print-safe (Wago/WA style)
            local raw_lsb, raw_msb = DecodeForPrint_Variants(payload)
            if raw_lsb then
                local t = TryDeserializeMaybeCompressed(E, raw_lsb)
                if t then  return t end
            end
            if raw_msb then
                local t = TryDeserializeMaybeCompressed(E, raw_msb)
                if t then  return t end
            end
            --- 3) LibDeflate (from another addon): print-decode then deflate;
            --- Wago-style payloads are always compressed on this route.
            local ld = _G.LibDeflate
            if ld and type(ld.DecodeForPrint) == "function" and type(ld.DecompressDeflate) == "function" then
                local decodeOK, raw = TryCodecCall(ld.DecodeForPrint, ld, payload)
                if decodeOK and type(raw) == "string" and #raw <= MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then
                    local decompressOK, plain = TryCodecCall(ld.DecompressDeflate, ld, raw)
                    if decompressOK and type(plain) == "string" and #plain <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then
                        local t = TryDeserialize(E, plain)
                        if t then  return t end
                    end
                end
            end
             return nil
        end
     end
    ExportPublic("MSUF_EncodeCompactTable", _G.MSUF_EncodeCompactTable or EncodeCompactTable)
    ExportPublic("MSUF_EncodeCompactTableMSUF3", EncodeCompactTableMSUF3)
    ExportPublic("MSUF_TryDecodeCompactString", _G.MSUF_TryDecodeCompactString or TryDecodeCompactString)
end

--- Profile lifecycle API. These globals are used by Menu2, assistant actions,
--- slash handlers, and legacy callers, so the public surface stays global even
--- though the implementation is isolated in this State module.
function MSUF_GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end
local function MSUF_ProfileIO_EnsureProfileRoots()
    if type(MSUF_GlobalDB) ~= "table" then
        MSUF_GlobalDB = {}
    end
    if type(MSUF_GlobalDB.profiles) ~= "table" then
        MSUF_GlobalDB.profiles = {}
    end
    if type(MSUF_GlobalDB.char) ~= "table" then
        MSUF_GlobalDB.char = {}
    end
    return MSUF_GlobalDB.profiles, MSUF_GlobalDB.char
end
--- Account-wide preferences that must survive a profile switch live beside the
--- other `MSUF_GlobalDB.global` state (first-load, guided tour). Keeping this
--- out of the profile tables is deliberate: switching, resetting, or importing
--- a profile must never rewrite which profile future characters start on.
local function MSUF_ProfileIO_EnsureGlobalMeta()
    if type(MSUF_GlobalDB) ~= "table" then
        MSUF_GlobalDB = {}
    end
    if type(MSUF_GlobalDB.global) ~= "table" then
        MSUF_GlobalDB.global = {}
    end
    return MSUF_GlobalDB.global
end
--- Starting profile for characters that have never picked one. `nil` keeps the
--- historical behaviour (new characters land on "Default").
function MSUF_GetDefaultProfileForNewCharacters()
    local name = MSUF_ProfileIO_EnsureGlobalMeta().defaultProfileForNewChars
    if type(name) ~= "string" or name == "" then return nil end
    return name
end
function MSUF_SetDefaultProfileForNewCharacters(name)
    --- Ensure the profile roots first: both helpers rebuild `MSUF_GlobalDB`
    --- when it is missing, and capturing `meta` before that could hand back a
    --- table that is about to be replaced.
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    local meta = MSUF_ProfileIO_EnsureGlobalMeta()
    --- "None" is the shared dropdown sentinel for "no selection" (same contract
    --- as MSUF_SetSpecProfile), so it clears unless a real profile owns the name.
    if type(name) ~= "string" or name == ""
        or (name == "None" and type(profiles["None"]) ~= "table") then
        meta.defaultProfileForNewChars = nil
        return true
    end
    if type(profiles[name]) ~= "table" then
        print("|cffff0000MSUF:|r Unknown profile: " .. tostring(name))
        return false, "unknown profile"
    end
    meta.defaultProfileForNewChars = name
    return true
end
--- A stale configured name must fall through to "Default" instead of being
--- honoured: the init path clones a donor into any missing profile name, so an
--- unvalidated value here would resurrect a deleted profile as a ghost copy.
--- Reads the stored field directly rather than through the public getter, so a
--- third party replacing that global cannot steer login profile selection.
local function MSUF_ProfileIO_NewCharacterProfile(profiles)
    local configured = MSUF_ProfileIO_EnsureGlobalMeta().defaultProfileForNewChars
    if type(configured) ~= "string" or configured == "" then return nil end
    if type(profiles) == "table" and type(profiles[configured]) == "table" then
        return configured
    end
    return nil
end
--- Pick the donor profile for a repair without depending on `pairs()` order.
--- Two characters hitting this same path must clone the same source, otherwise
--- an account silently grows divergent copies of an arbitrary profile. Only
--- string keys are eligible because `MSUF_GetAllProfiles` never lists any other
--- kind, so a numeric-keyed leftover must not become somebody's live settings.
local function MSUF_ProfileIO_FallbackProfileTable(profiles)
    if type(profiles) ~= "table" then return nil, nil end
    if type(profiles["Default"]) == "table" then
        return profiles["Default"], "Default"
    end
    local names
    for name, tbl in pairs(profiles) do
        if type(name) == "string" and name ~= "" and type(tbl) == "table" then
            names = names or {}
            names[#names + 1] = name
        end
    end
    if not names then return nil, nil end
    table.sort(names)
    return profiles[names[1]], names[1]
end
local function MSUF_ProfileIO_EnsureProfileMenuDefaults(profile)
    if type(profile) ~= "table" then return end
    if type(profile.general) ~= "table" then
        profile.general = {}
    end
    if profile.general.showGameMenuButton == nil then
        profile.general.showGameMenuButton = true
    end
    if profile.general.previewDragHintAnimationEnabled == nil then
        profile.general.previewDragHintAnimationEnabled = true
    end
    -- Factory-created profiles explicitly start at false. Profiles predating
    -- the drag cue have already taught their owners the preview workflow, so a
    -- missing marker is migrated to the experienced cadence.
    if profile.general._msufPreviewDragHintExperienced == nil then
        profile.general._msufPreviewDragHintExperienced = true
    end
end
local MSUF_ProfileIO_TranslateProfileToCurrent
local MSUF_ProfileIO_TranslateProfilesToCurrent
function MSUF_InitProfiles()
    local profiles, chars = MSUF_ProfileIO_EnsureProfileRoots()
    local charKey = MSUF_GetCharKey()
    local char = type(chars[charKey]) == "table" and chars[charKey] or {}
    chars[charKey] = char
    local active = char.activeProfile
    if type(active) ~= "string" or active == "" then
        active = nil
    end
    if not next(profiles) then
        local base = MSUF_DB or {}
        profiles["Default"] = CopyTable(type(base) == "table" and base or {})
        if not active then
            active = "Default"
        end
    end
    if not active then
        --- A character that has never chosen a profile follows the account-wide
        --- preference when it still names a live profile. Everything else keeps
        --- landing on "Default" exactly as before, and a character that already
        --- has `activeProfile` set never reaches this branch at all.
        active = MSUF_ProfileIO_NewCharacterProfile(profiles) or "Default"
    end
    if type(profiles[active]) ~= "table" then
        local fallback = MSUF_ProfileIO_FallbackProfileTable(profiles)
        profiles[active] = CopyTable(fallback or {})
    end
    if MSUF_ProfileIO_TranslateProfilesToCurrent then
        MSUF_ProfileIO_TranslateProfilesToCurrent(profiles, "init")
    end
    char.activeProfile = active
    MSUF_ActiveProfile = active
    MSUF_DB = profiles[active]
    MSUF_ProfileIO_CallGlobal("MSUF_GF_InvalidateConfCache")
    --- After DB swap: seed missing defaults so per-unit conf tables exist.
    --- Without this, CreateSimpleUnitFrame sees conf=nil/{} for pet/targettarget
    --- when the profile was saved from an older version missing those keys,
    --- and UpdateSimpleUnitFrame defaults showPowerText=true since conf.showPower is nil.
    --- The Defaults module persists its completed repair revision on the
    --- profile. A non-forced ensure still repairs a new/legacy profile, while
    --- avoiding a second complete pass when this exact profile was already
    --- repaired earlier in the startup chain.
    MSUF_ProfileIO_RunEnsureDB(false, true)
 end
function MSUF_CreateProfile(name)
    if type(name) ~= "string" or name == "" then return false, "invalid profile name" end
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    if profiles[name] then
        print("|cffff0000MSUF:|r Profile '"..name.."' already exists.")
        return false, "profile already exists"
    end
    local createFactoryProfile = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile)
        or _G.MSUF_CreateFactoryDefaultProfile
    local called, profile = MSUF_ProfileIO_RunProtected("create factory profile", createFactoryProfile)
    if not called or type(profile) ~= "table" then
        print("|cffff0000MSUF:|r Factory defaults are not available; profile was not created.")
        return false, "factory defaults unavailable"
    end
    profiles[name] = profile
    if MSUF_ProfileIO_TranslateProfileToCurrent then
        MSUF_ProfileIO_TranslateProfileToCurrent(profiles[name], {
            source = "profile_create",
            trustNormalizationMarker = true,
        })
    end
    MSUF_ProfileIO_EnsureProfileMenuDefaults(profiles[name])
    print("|cff00ff00MSUF:|r Created new profile '"..name.."'.")
    return true
 end
function MSUF_SwitchProfile(name)
    local profiles, chars = MSUF_ProfileIO_EnsureProfileRoots()
    if not name or type(profiles[name]) ~= "table" then
        print("|cffff0000MSUF:|r Unknown profile: "..tostring(name))
        return false, "unknown profile"
    end
    local charKey = MSUF_GetCharKey()
    local char = type(chars[charKey]) == "table" and chars[charKey] or {}
    chars[charKey] = char
    if MSUF_ProfileIO_TranslateProfileToCurrent then
        MSUF_ProfileIO_TranslateProfileToCurrent(profiles[name], {
            source = "profile_switch",
            trustNormalizationMarker = true,
        })
    end
    char.activeProfile = name
    MSUF_ActiveProfile = name
    MSUF_DB = profiles[name]
    MSUF_ProfileIO_CallGlobal("MSUF_GF_InvalidateConfCache")
    --- Invalidate cached config references (UFCore caches per-frame config table refs).
    do
        local MSUF = _G.MSUF_NS
        local core = (MSUF and MSUF.MSUF_UnitframeCore) or nil
        if core and type(core.InvalidateAllFrameConfigs) == "function" then
            core.InvalidateAllFrameConfigs()
        end
    end
    --- Stored profiles carry the Defaults completion revision. Imports and
    --- resets clear/bypass it, so a valid profile can switch without paying a
    --- second broad default-fill pass while stale/malformed tables still repair.
    MSUF_ProfileIO_RunEnsureDB(false, true)
    MSUF_ProfileIO_PostProfileRuntimeApply("PROFILE_SWITCH", false)
    print("|cff00ff00MSUF:|r Switched to profile '"..name.."'.")
    return true
 end
function MSUF_ResetProfile(name)
    name = name or MSUF_ActiveProfile
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    if not name or not profiles[name] then return false, "unknown profile" end
    profiles[name] = {}
    if name == MSUF_ActiveProfile then
        MSUF_DB = profiles[name]
        MSUF_ProfileIO_CallGlobal("MSUF_GF_InvalidateConfCache")
        --- Phase 3: invalidate settings cache immediately after DB swap
        if _G.MSUF_UFCore_InvalidateSettingsCache then
            _G.MSUF_UFCore_InvalidateSettingsCache()
        end
        MSUF_ProfileIO_RunEnsureDB(true)
        MSUF_ProfileIO_PostProfileRuntimeApply("PROFILE_RESET", false)
    end
    print("|cffffd700MSUF:|r Profile '"..name.."' reset to defaults.")
    return true
 end
function MSUF_DeleteProfile(name)
    name = name or MSUF_ActiveProfile
    local profiles, chars = MSUF_ProfileIO_EnsureProfileRoots()
    if not name or not profiles[name] then return false, "unknown profile" end
    if name == "Default" then
        print("|cffff0000MSUF:|r You cannot delete the 'Default' profile. Use Reset instead.")
        return false, "default profile is protected"
    end
    local fallbackName
    for profileName, tbl in pairs(profiles) do
        if profileName ~= name and type(tbl) == "table" then
            fallbackName = fallbackName or profileName
        end
    end
    if not fallbackName then
        print("|cffff0000MSUF:|r Cannot delete the last remaining profile.")
        return false, "cannot delete last profile"
    end
    if chars then
        for _, char in pairs(chars) do
            if type(char) == "table" then
                if char.activeProfile == name then char.activeProfile = fallbackName end
                if type(char.specProfileMap) == "table" then
                    for specID, profileName in pairs(char.specProfileMap) do
                        if profileName == name then char.specProfileMap[specID] = nil end
                    end
                end
            end
        end
    end
    --- Clear rather than retarget: the account chose this specific profile as
    --- the starting point for new characters, and silently pointing that at an
    --- arbitrary survivor would change what the setting means. New characters
    --- fall back to "Default" until the account picks a replacement.
    local globalMeta = MSUF_ProfileIO_EnsureGlobalMeta()
    if globalMeta.defaultProfileForNewChars == name then
        globalMeta.defaultProfileForNewChars = nil
    end
    profiles[name] = nil
    if MSUF_ActiveProfile == name then
        MSUF_SwitchProfile(fallbackName)
    end
    print("|cffffd700MSUF:|r Profile '"..name.."' deleted.")
    return true
 end
function MSUF_CopyProfile(sourceName, destName)
    if not sourceName or sourceName == "" then
        print("|cffff0000MSUF:|r No source profile specified.")
        return false
    end
    if not destName or destName == "" then
        print("|cffff0000MSUF:|r No destination name specified.")
        return false
    end
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    local src = profiles[sourceName]
    if type(src) ~= "table" then
        print("|cffff0000MSUF:|r Source profile '"..sourceName.."' not found.")
        return false
    end
    if profiles[destName] then
        print("|cffff0000MSUF:|r Profile '"..destName.."' already exists.")
        return false
    end
    profiles[destName] = CopyTable(src)
    if MSUF_ProfileIO_TranslateProfileToCurrent then
        MSUF_ProfileIO_TranslateProfileToCurrent(profiles[destName], {
            source = "profile_copy",
            trustNormalizationMarker = true,
        })
    end
    MSUF_ProfileIO_EnsureProfileMenuDefaults(profiles[destName])
    print("|cff00ff00MSUF:|r Copied '"..sourceName.."' -> '"..destName.."'.")
    return true
end
function MSUF_RenameProfile(sourceName, destName)
    if not sourceName or sourceName == "" then
        print("|cffff0000MSUF:|r No source profile specified.")
        return false
    end
    if not destName or destName == "" then
        print("|cffff0000MSUF:|r No destination name specified.")
        return false
    end
    if sourceName == destName then
        print("|cffffd700MSUF:|r Profile is already named '"..sourceName.."'.")
        return true
    end
    if sourceName == "Default" then
        print("|cffff0000MSUF:|r You cannot rename the 'Default' profile. Copy it instead.")
        return false
    end

    local profiles, chars = MSUF_ProfileIO_EnsureProfileRoots()
    local src = profiles[sourceName]
    if type(src) ~= "table" then
        print("|cffff0000MSUF:|r Source profile '"..sourceName.."' not found.")
        return false
    end
    if profiles[destName] then
        print("|cffff0000MSUF:|r Profile '"..destName.."' already exists.")
        return false
    end

    profiles[destName] = src
    profiles[sourceName] = nil
    if chars then
        for _, char in pairs(chars) do
            if type(char) == "table" then
                if char.activeProfile == sourceName then
                    char.activeProfile = destName
                end
                local map = char.specProfileMap
                if type(map) == "table" then
                    for specID, profileName in pairs(map) do
                        if profileName == sourceName then
                            map[specID] = destName
                        end
                    end
                end
            end
        end
    end
    --- The profile itself survives a rename, so the new-character preference
    --- follows it instead of being cleared.
    local globalMeta = MSUF_ProfileIO_EnsureGlobalMeta()
    if globalMeta.defaultProfileForNewChars == sourceName then
        globalMeta.defaultProfileForNewChars = destName
    end
    if MSUF_ActiveProfile == sourceName then
        MSUF_SwitchProfile(destName)
    end
    print("|cff00ff00MSUF:|r Renamed '"..sourceName.."' -> '"..destName.."'.")
    return true
end
function MSUF_GetAllProfiles()
    local list = {}
    if MSUF_GlobalDB and type(MSUF_GlobalDB.profiles) == "table" then
        for name, tbl in pairs(MSUF_GlobalDB.profiles) do
            if type(name) == "string" and type(tbl) == "table" then
                table.insert(list, name)
            end
        end
        table.sort(list)
    end
     return list
end
---
--- Spec-based profile auto-switch (per-character)
--- Stored in:
--- MSUF_GlobalDB.char[charKey].specAutoSwitch (boolean)
--- MSUF_GlobalDB.char[charKey].specProfileMap (table: specID -> profileName)
--- This is intentionally not profile-local: a profile switch must not rewrite
--- the player's "which spec should load which profile" preference.
--- Design goals:
--- - Very small, fully optional (off by default).
--- - Combat-safe: if spec changes in combat, we defer the switch.
--- - Works with existing global profiles (no DB migration needed).
---
local function MSUF_GetCharMeta()
    local _, chars = MSUF_ProfileIO_EnsureProfileRoots()
    local charKey = (type(_G.MSUF_GetCharKey) == "function") and _G.MSUF_GetCharKey() or (UnitName("player") .. "-" .. GetRealmName())
    local char = chars[charKey]
    if type(char) ~= "table" then
        char = {}
        chars[charKey] = char
    end
    if char.specAutoSwitch == nil then
        char.specAutoSwitch = false
    end
    if type(char.specProfileMap) ~= "table" then
        char.specProfileMap = {}
    end
     return char
end
function MSUF_IsSpecAutoSwitchEnabled()
    local char = MSUF_GetCharMeta()
    return (char.specAutoSwitch == true)
end
function MSUF_SetSpecAutoSwitchEnabled(enabled)
    local char = MSUF_GetCharMeta()
    char.specAutoSwitch = (enabled == true)
    if char.specAutoSwitch then
        if _G.MSUF_ApplySpecProfileIfEnabled then
            _G.MSUF_ApplySpecProfileIfEnabled("TOGGLE_ON")
        end
    end
 end
function MSUF_GetSpecProfile(specID)
    local char = MSUF_GetCharMeta()
    if type(specID) ~= "number" then  return nil end
    local v = char.specProfileMap[specID]
    if type(v) ~= "string" or v == "" then
         return nil
    end
     return v
end
function MSUF_SetSpecProfile(specID, profileName)
    local char = MSUF_GetCharMeta()
    if type(specID) ~= "number" then  return end
    if type(profileName) ~= "string" or profileName == "" or profileName == "None" then
        char.specProfileMap[specID] = nil
    else
        char.specProfileMap[specID] = profileName
    end
    if char.specAutoSwitch == true then
        local cur = _G.MSUF_GetPlayerSpecID and _G.MSUF_GetPlayerSpecID() or nil
        if cur == specID then
            if _G.MSUF_ApplySpecProfileIfEnabled then
                _G.MSUF_ApplySpecProfileIfEnabled("MAP_CHANGED")
            end
        end
    end
 end
function MSUF_GetPlayerSpecID()
    if type(_G.GetSpecialization) ~= "function" or type(_G.GetSpecializationInfo) ~= "function" then
         return nil
    end
    local idx = _G.GetSpecialization()
    if not idx then  return nil end
    local specID = _G.GetSpecializationInfo(idx)
    if type(specID) ~= "number" then
         return nil
    end
     return specID
end
--- Combat-safe deferrer (shared)
local function MSUF_RunAfterCombat_SpecProfile(fn)
    if type(fn) ~= "function" then  return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        ExportPublic("MSUF_PendingSpecProfileSwitch", fn)
        local f = _G.MSUF_SpecProfileDeferFrame
        if not f and type(_G.CreateFrame) == "function" then
            f = _G.CreateFrame("Frame")
            ExportPublic("MSUF_SpecProfileDeferFrame", f)
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function()
                local pending = _G.MSUF_PendingSpecProfileSwitch
                if pending then
                    ExportPublic("MSUF_PendingSpecProfileSwitch", nil)
                    pending()
                end
             end)
        end
         return
    end
    fn()
 end
function MSUF_ApplySpecProfileIfEnabled(reason)
    local char = MSUF_GetCharMeta()
    if char.specAutoSwitch ~= true then  return end
    local specID = MSUF_GetPlayerSpecID()
    if type(specID) ~= "number" then  return end
    local profileName = char.specProfileMap[specID]
    if type(profileName) ~= "string" or profileName == "" then  return end
    --- Only switch to existing profiles.
    if not (type(_G.MSUF_GlobalDB) == "table"
        and type(_G.MSUF_GlobalDB.profiles) == "table"
        and type(_G.MSUF_GlobalDB.profiles[profileName]) == "table") then return end
    if _G.MSUF_ActiveProfile == profileName then
         return
    end
    MSUF_RunAfterCombat_SpecProfile(function()
        --- Re-check after combat (spec could have changed again).
        if not MSUF_IsSpecAutoSwitchEnabled() then  return end
        local cur = MSUF_GetPlayerSpecID()
        if cur ~= specID then  return end
        local mapped = MSUF_GetSpecProfile(specID)
        if mapped ~= profileName then  return end
        if _G.MSUF_ActiveProfile == profileName then  return end
        if _G.MSUF_SwitchProfile then
            _G.MSUF_SwitchProfile(profileName)
        end
     end)
 end
--- Event driver (very small; only does work when enabled)
do
    local f
    local function EnsureFrame()
        if f then  return end
        if type(_G.CreateFrame) ~= "function" then  return end
        f = _G.CreateFrame("Frame")
        ExportPublic("MSUF_SpecProfileEventFrame", f)
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_LOGIN")
        f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        f:SetScript("OnEvent", function(_, event, arg1)
            if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
                 return
            end
            if not MSUF_IsSpecAutoSwitchEnabled() then return end
            MSUF_ApplySpecProfileIfEnabled(event)
         end)
     end
    EnsureFrame()
end
---
--- Profile Export / Import (Selection-based, with legacy import button)
--- New snapshot format (Lua table):
--- return {
--- addon = "MSUF",
--- fmt = 2,
--- schema = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
--- kind = "unitframe" | "castbar" | "colors" | "gameplay" | "groupframe" | "all",
--- profile = "<active profile name>",
--- payload = { ...selected settings... },
--- }
--- Import behavior:
--- - If the snapshot matches the format above: apply only the selected category into the
--- CURRENT ACTIVE profile (keeps everything else unchanged).
--- - Legacy import (old "return { ... }" profile dump) remains available via
--- MSUF_ImportLegacyFromString(str).
---
local function MSUF_WipeTable(t)
    if not t then  return end
    for k in pairs(t) do
        t[k] = nil
    end
 end
local function MSUF_DeepCopy(v, seen, depth)
    if not v then  return v end
    if type(v) ~= "table" then
        return v
    end
    depth = (depth or 0) + 1
    if depth > MSUF_PROFILE_IMPORT_LIMITS.depth then error("profile table is too deep") end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, vv in pairs(v) do
        out[MSUF_DeepCopy(k, seen, depth)] = MSUF_DeepCopy(vv, seen, depth)
    end
     return out
end

MSUF.ProfileIOValidateImportValue = function(root)
    local seen, nodes, stringBytes = {}, 0, 0
    local function Walk(value, depth)
        nodes = nodes + 1
        if nodes > MSUF_PROFILE_IMPORT_LIMITS.nodes then return false, "profile has too many values" end
        local valueType = type(value)
        if valueType == "string" then
            stringBytes = stringBytes + #value
            if stringBytes > MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return false, "profile strings are too large" end
            return true
        end
        if valueType == "number" then
            if value ~= value or value == math.huge or value == -math.huge then return false, "profile contains an invalid number" end
            return true
        end
        if valueType == "nil" or valueType == "boolean" then return true end
        if valueType ~= "table" then return false, "profile contains unsupported " .. valueType end
        if depth > MSUF_PROFILE_IMPORT_LIMITS.depth then return false, "profile is too deep" end
        if seen[value] then return false, "profile contains a cyclic or shared table" end
        seen[value] = true
        for key, child in pairs(value) do
            local keyType = type(key)
            if keyType ~= "string" and keyType ~= "number" then return false, "profile contains an unsupported table key" end
            local ok, why = Walk(key, depth + 1)
            if not ok then return false, why end
            ok, why = Walk(child, depth + 1)
            if not ok then return false, why end
        end
        return true
    end
    if type(root) ~= "table" then return false, "profile is not a table" end
    return Walk(root, 1)
end

local MSUF_ProfileIO_ImportWarningMap = {}
local MSUF_ProfileIO_ImportWarnings = {}

local function MSUF_ProfileIO_ResetImportWarnings()
    for key in pairs(MSUF_ProfileIO_ImportWarningMap) do
        MSUF_ProfileIO_ImportWarningMap[key] = nil
    end
    for i = #MSUF_ProfileIO_ImportWarnings, 1, -1 do
        MSUF_ProfileIO_ImportWarnings[i] = nil
    end
    ExportPublic("MSUF_ProfileIO_LastImportWarnings", nil)
end

local function MSUF_ProfileIO_AddImportWarning(kind, label, value)
    if type(value) ~= "string" or value == "" then return end
    kind = tostring(kind or "media")
    label = tostring(label or "profile")
    local id = kind .. "\001" .. label .. "\001" .. value
    if MSUF_ProfileIO_ImportWarningMap[id] then return end
    MSUF_ProfileIO_ImportWarningMap[id] = true
    MSUF_ProfileIO_ImportWarnings[#MSUF_ProfileIO_ImportWarnings + 1] = {
        kind = kind,
        label = label,
        value = value,
    }
end

local function MSUF_ProfileIO_PublishImportWarnings()
    if #MSUF_ProfileIO_ImportWarnings == 0 then
        ExportPublic("MSUF_ProfileIO_LastImportWarnings", nil)
        return nil
    end
    local copy = {}
    for i = 1, #MSUF_ProfileIO_ImportWarnings do
        copy[i] = MSUF_DeepCopy(MSUF_ProfileIO_ImportWarnings[i])
    end
    ExportPublic("MSUF_ProfileIO_LastImportWarnings", copy)
    return copy
end

local function MSUF_ProfileIO_ReportImportWarnings()
    local warnings = MSUF_ProfileIO_PublishImportWarnings()
    if not warnings then return end
    local count = #warnings
    local maxLines = count > 5 and 5 or count
    for i = 1, maxLines do
        local w = warnings[i]
        local noun = (w.kind == "font") and "font" or "texture"
        local fallback = (w.kind == "font") and "fallback font" or "fallback texture"
        print("|cffffd700MSUF:|r Import warning: missing " .. noun .. " '" .. tostring(w.value) .. "' in " .. tostring(w.label) .. ". Using " .. fallback .. ".")
    end
    if count > maxLines then
        print("|cffffd700MSUF:|r Import warning: " .. tostring(count - maxLines) .. " more missing media item(s).")
    end
end

local function MSUF_ProfileIO_GetLSM()
    return (MSUF and MSUF.LSM) or _G.MSUF_LSM or (_G.LibStub and _G.LibStub("LibSharedMedia-3.0", true))
end

local function MSUF_ProfileIO_LooksLikeMediaPath(value)
    if type(value) ~= "string" or value == "" then return false end
    local lower = value:lower()
    return value:find("\\", 1, true) ~= nil
        or value:find("/", 1, true) ~= nil
        or lower:match("%.ttf$") ~= nil
        or lower:match("%.otf$") ~= nil
        or lower:match("%.tga$") ~= nil
        or lower:match("%.blp$") ~= nil
        or lower:match("%.png$") ~= nil
end

local function MSUF_ProfileIO_FontPathAvailable(path)
    if type(path) ~= "string" or path == "" then return false end
    local isLoadable = _G.MSUF_FontPathIsLoadable
    if type(isLoadable) == "function" then
        return isLoadable(path, 14, "") == true
    end
    local isKnown = _G.MSUF_IsKnownFileAsset
    if type(isKnown) == "function" and isKnown(path) == false then return false end
    return true
end

local function MSUF_ProfileIO_FontKeyAvailable(key)
    if type(key) ~= "string" or key == "" then return true end
    local normalize = _G.MSUF_NormalizeFontKey or function(value) return value end
    local normalized = normalize(key)
    local internal = _G.MSUF_GetInternalFontPathByKey
    if type(internal) == "function" then
        local path = internal(normalized) or internal(key)
        if MSUF_ProfileIO_FontPathAvailable(path) then return true end
    end
    if MSUF_ProfileIO_LooksLikeMediaPath(key) then
        return MSUF_ProfileIO_FontPathAvailable(key)
    end
    local lsm = MSUF_ProfileIO_GetLSM()
    if lsm and type(lsm.HashTable) == "function" then
        local fonts = lsm:HashTable("font")
        local path = fonts and (fonts[normalized] or fonts[key])
        if MSUF_ProfileIO_FontPathAvailable(path) then return true end
    end
    if lsm and type(lsm.Fetch) == "function" then
        local path = lsm:Fetch("font", normalized, true)
        if (not path) and normalized ~= key then path = lsm:Fetch("font", key, true) end
        if MSUF_ProfileIO_FontPathAvailable(path) then return true end
    end
    return false
end

local MSUF_ProfileIO_TextureProbeHost
local MSUF_ProfileIO_TextureProbe
local MSUF_ProfileIO_TextureProbeReliable
local MSUF_ProfileIO_TexturePathCache = {}

local function MSUF_ProfileIO_NormalizeTexturePath(path)
    if type(path) ~= "string" or path == "" then return nil end
    path = path:gsub("/", "\\")
    return path ~= "" and path or nil
end

local function MSUF_ProfileIO_TextureProbeRaw(path)
    path = MSUF_ProfileIO_NormalizeTexturePath(path)
    if not path or type(_G.CreateFrame) ~= "function" then return nil end
    if not MSUF_ProfileIO_TextureProbe then
        MSUF_ProfileIO_TextureProbeHost = _G.CreateFrame("Frame")
        if MSUF_ProfileIO_TextureProbeHost.Hide then MSUF_ProfileIO_TextureProbeHost:Hide() end
        MSUF_ProfileIO_TextureProbe = MSUF_ProfileIO_TextureProbeHost:CreateTexture(nil, "ARTWORK")
    end
    local probe = MSUF_ProfileIO_TextureProbe
    if not (probe and type(probe.SetTexture) == "function") then return nil end
    probe:SetTexture(nil)
    -- SetTexture reports an unloadable path via its documented success return.
    local applied = probe:SetTexture(path)
    if applied == false then
        probe:SetTexture(nil)
        return false
    end
    if type(probe.GetTexture) == "function" then
        local tex = probe:GetTexture()
        probe:SetTexture(nil)
        return tex ~= nil and tex ~= ""
    end
    probe:SetTexture(nil)
    return true
end

local function MSUF_ProfileIO_TextureProbeIsReliable()
    if MSUF_ProfileIO_TextureProbeReliable ~= nil then return MSUF_ProfileIO_TextureProbeReliable end
    local result = MSUF_ProfileIO_TextureProbeRaw("Interface\\AddOns\\MidnightSimpleUnitFrames\\__msuf_missing_texture_probe__")
    MSUF_ProfileIO_TextureProbeReliable = (result == false)
    return MSUF_ProfileIO_TextureProbeReliable
end

local function MSUF_ProfileIO_TexturePathLoadable(path)
    path = MSUF_ProfileIO_NormalizeTexturePath(path)
    if not path then return false end
    local cached = MSUF_ProfileIO_TexturePathCache[path]
    if cached ~= nil then return cached end
    local isKnown = _G.MSUF_IsKnownFileAsset
    if type(isKnown) == "function" and isKnown(path) == false then
        MSUF_ProfileIO_TexturePathCache[path] = false
        return false
    end
    if not MSUF_ProfileIO_TextureProbeIsReliable() then
        MSUF_ProfileIO_TexturePathCache[path] = true
        return true
    end
    local lower = path:lower()
    local exists = MSUF_ProfileIO_TextureProbeRaw(path) == true
    if not exists and not (lower:match("%.tga$") or lower:match("%.blp$") or lower:match("%.png$")) then
        exists = MSUF_ProfileIO_TextureProbeRaw(path .. ".tga") == true
            or MSUF_ProfileIO_TextureProbeRaw(path .. ".blp") == true
            or MSUF_ProfileIO_TextureProbeRaw(path .. ".png") == true
    end
    MSUF_ProfileIO_TexturePathCache[path] = exists and true or false
    return MSUF_ProfileIO_TexturePathCache[path]
end

local function MSUF_ProfileIO_StatusbarTextureAvailable(key)
    if type(key) ~= "string" or key == "" then return true end
    local builtins = _G.MSUF_BUILTIN_BAR_TEXTURES
    if type(builtins) == "table" and MSUF_ProfileIO_TexturePathLoadable(builtins[key]) then
        return true
    end
    if key == "Solid" or key == "Blizzard" or key == "Flat" or key == "RaidHP" or key == "RaidPower" then
        return true
    end
    if MSUF_ProfileIO_LooksLikeMediaPath(key) then
        return MSUF_ProfileIO_TexturePathLoadable(key)
    end
    local lsm = MSUF_ProfileIO_GetLSM()
    if lsm and type(lsm.HashTable) == "function" then
        local bars = lsm:HashTable("statusbar")
        local path = bars and bars[key]
        if MSUF_ProfileIO_TexturePathLoadable(path) then return true end
    end
    if lsm and type(lsm.Fetch) == "function" then
        local path = lsm:Fetch("statusbar", key, true)
        if MSUF_ProfileIO_TexturePathLoadable(path) then return true end
    end
    return false
end

local function MSUF_ProfileIO_CollectStatusbarTextureWarnings(scope, labelPrefix, keys)
    if type(scope) ~= "table" then return end
    for _, key in ipairs(keys) do
        local value = scope[key]
        if type(value) == "string" and value ~= "" and not MSUF_ProfileIO_StatusbarTextureAvailable(value) then
            MSUF_ProfileIO_AddImportWarning("texture", labelPrefix .. "." .. key, value)
        end
    end
end

local MSUF_PROFILEIO_GENERAL_TEXTURE_WARNING_KEYS = {
    "barTexture",
    "barBackgroundTexture",
    "castbarTexture",
    "castbarBackgroundTexture",
    "absorbBarTexture",
    "healAbsorbBarTexture",
}

local MSUF_PROFILEIO_BARS_TEXTURE_WARNING_KEYS = {
    "classPowerTexture",
    "classPowerBgTexture",
    "powerBarTexture",
    "powerBarBgTexture",
    "playerHPBarTexture",
    "playerHPBarBgTexture",
}

local MSUF_PROFILEIO_UNIT_TEXTURE_WARNING_KEYS = {
    "barTexture",
    "barBackgroundTexture",
    "powerBarTexture",
    "powerBarBgTexture",
    "absorbBarTexture",
    "healAbsorbBarTexture",
}

local MSUF_PROFILEIO_MEDIA_UNIT_SCOPE_KEYS = {
    "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss",
}

local MSUF_PROFILEIO_GROUP_TEXTURE_WARNING_KEYS = {
    "barTexture",
    "barBackgroundTexture",
    "barBgTexture",
    "absorbBarTexture",
    "healAbsorbBarTexture",
}

local function MSUF_ProfileIO_CollectProfileMediaWarnings(profile)
    if type(profile) ~= "table" then return end
    local g = profile.general
    if type(g) == "table" then
        if type(g.fontKey) == "string" and g.fontKey ~= "" and not MSUF_ProfileIO_FontKeyAvailable(g.fontKey) then
            MSUF_ProfileIO_AddImportWarning("font", "general.fontKey", g.fontKey)
        end
        MSUF_ProfileIO_CollectStatusbarTextureWarnings(g, "general", MSUF_PROFILEIO_GENERAL_TEXTURE_WARNING_KEYS)
    end
    local bars = profile.bars
    if type(bars) == "table" then
        MSUF_ProfileIO_CollectStatusbarTextureWarnings(bars, "bars", MSUF_PROFILEIO_BARS_TEXTURE_WARNING_KEYS)
    end
    for _, scopeKey in ipairs(MSUF_PROFILEIO_MEDIA_UNIT_SCOPE_KEYS) do
        local scope = profile[scopeKey]
        if type(scope) == "table" then
            MSUF_ProfileIO_CollectStatusbarTextureWarnings(scope, scopeKey, MSUF_PROFILEIO_UNIT_TEXTURE_WARNING_KEYS)
        end
    end
    for _, scopeKey in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        local scope = profile[scopeKey]
        if type(scope) == "table" then
            MSUF_ProfileIO_CollectStatusbarTextureWarnings(scope, scopeKey, MSUF_PROFILEIO_GROUP_TEXTURE_WARNING_KEYS)
        end
    end
end

ExportPublic("MSUF_ProfileIO_GetLastImportWarnings", function()
    return MSUF_ProfileIO_PublishImportWarnings()
end)

local MSUF_PROFILEIO_POSITIVE_FONT_SIZE_KEYS = {
    fontSize = 14,
    nameFontSize = 14,
    hpFontSize = 14,
    powerFontSize = 14,
    auraFontSize = 25,
    levelIndicatorSize = 12,
    bossNumberIndicatorSize = 14,
    classificationIndicatorSize = 12,
    statusIndicatorSize = 14,
    statusTextSize = 14,
    statusGhostTextSize = 14,
    statusAFKTextSize = 14,
    statusAFKTimerSize = 12,
    statusAFKTimerTextSize = 10,
    statusDNDTextSize = 14,
    playerHPBarTextSize = 14,
    combatFontSize = 24,
    combatStateFontSize = 24,
    focusKickTextSize = 12,
    stackTextSize = 14,
    cooldownTextSize = 14,
    buffStackTextSize = 14,
    buffCooldownTextSize = 14,
    debuffStackTextSize = 14,
    debuffCooldownTextSize = 14,
}
local function MSUF_ProfileIO_ClampPositiveFontSize(tbl, key, fallback)
    if type(tbl) ~= "table" or tbl[key] == nil then
        return
    end
    local n = tonumber(tbl[key])
    if n == nil then
        return
    end
    fallback = tonumber(fallback) or 14
    if n <= 0 then
        n = fallback
    elseif n < 6 then
        n = 6
    elseif n > 128 then
        n = 128
    end
    tbl[key] = n
end
local function MSUF_ProfileIO_NormalizeImportedFontSizes(profile)
    if type(profile) ~= "table" then
        return profile
    end
    local seen = {}
    local function Walk(tbl, depth)
        if type(tbl) ~= "table" or seen[tbl] or depth > 8 then
            return
        end
        seen[tbl] = true
        for key, fallback in pairs(MSUF_PROFILEIO_POSITIVE_FONT_SIZE_KEYS) do
            MSUF_ProfileIO_ClampPositiveFontSize(tbl, key, fallback)
        end
        for _, value in pairs(tbl) do
            if type(value) == "table" then
                Walk(value, depth + 1)
            end
        end
    end
    Walk(profile, 0)
    return profile
end

local MSUF_PROFILEIO_UNIT_KEYS = { "player", "target", "targettarget", "focustarget", "focus", "pet", "boss" }
local MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES = {
    { canonical = "targettarget", aliases = { "tot", "targetoftarget", "target_of_target" } },
    { canonical = "focustarget", aliases = { "focus_target", "focustargettarget" } },
}
local function MSUF_ProfileIO_NormalizeUnitFramePositionDB(profile, preferLegacyAliases)
    if type(profile) ~= "table" then return profile end
    local changed = false

    local function SelectAlias(container, aliases)
        local best
        for i = 1, #aliases do
            local alias = container[aliases[i]]
            if type(alias) == "table" and (best == nil or (alias.enabled == true and best.enabled ~= true)) then
                best = alias
            end
        end
        return best
    end

    local function SelectUnitSource(container, def)
        local current = container[def.canonical]
        local alias = SelectAlias(container, def.aliases)
        if type(current) ~= "table"
            or (preferLegacyAliases == true and type(alias) == "table"
                and alias.enabled == true and current.enabled ~= true) then
            return alias
        end
        return current
    end

    local nested = (type(profile.unitframes) == "table" and profile.unitframes)
        or (type(profile.unitFrames) == "table" and profile.unitFrames)
        or nil
    if nested and (type(nested.player) == "table" or type(nested.target) == "table") then
        for i = 1, #MSUF_PROFILEIO_UNIT_KEYS do
            local key = MSUF_PROFILEIO_UNIT_KEYS[i]
            if key ~= "targettarget" and key ~= "focustarget"
                and type(profile[key]) ~= "table" and type(nested[key]) == "table" then
                profile[key] = MSUF_DeepCopy(nested[key])
                changed = true
            end
        end
        for i = 1, #MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES do
            local def = MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES[i]
            if type(profile[def.canonical]) ~= "table" then
                local source = SelectUnitSource(nested, def)
                if type(source) == "table" then
                    profile[def.canonical] = MSUF_DeepCopy(source)
                    changed = true
                end
            end
        end
    end

    --- Aliases are accepted only as migration input. Once a canonical scope has
    --- been selected, retire every alias so future edits and reloads cannot
    --- create two independently serialized owners for the same unit frame.
    for i = 1, #MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES do
        local def = MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES[i]
        local source = SelectUnitSource(profile, def)
        if type(source) == "table" and source ~= profile[def.canonical] then
            profile[def.canonical] = MSUF_DeepCopy(source)
            changed = true
        end
        for j = 1, #def.aliases do
            local aliasKey = def.aliases[j]
            if profile[aliasKey] ~= nil then
                profile[aliasKey] = nil
                changed = true
            end
        end
    end
    if type(profile.boss) ~= "table" then
        for i = 1, 5 do
            local boss = profile["boss" .. i]
            if type(boss) == "table" then
                profile.boss = MSUF_DeepCopy(boss)
                changed = true
                break
            end
        end
    end

    local function NormalizeAnchorTo(conf)
        local anchor = conf.anchorToUnitframe
        if type(anchor) ~= "string" or anchor == "" then return end
        if anchor == "global" then
            conf.anchorToUnitframe = "GLOBAL"
        elseif anchor == "free" then
            conf.anchorToUnitframe = "FREE"
        elseif anchor == "tot" or anchor == "targetoftarget" then
            conf.anchorToUnitframe = "targettarget"
        elseif anchor == "focus_target" or anchor == "focustargettarget" then
            conf.anchorToUnitframe = "focustarget"
        elseif anchor:match("^boss%d+$") then
            conf.anchorToUnitframe = "boss"
        end
    end

    local function NormalizeNumber(conf, key, minValue, maxValue)
        local n = tonumber(conf[key])
        if n == nil then return end
        if minValue ~= nil and n < minValue then
            n = minValue
        elseif maxValue ~= nil and n > maxValue then
            n = maxValue
        end
        conf[key] = n
    end

    local function NormalizeUnit(conf)
        if type(conf) ~= "table" then return end
        if conf.anchorFrameName == "UI_Parent" then conf.anchorFrameName = "UIParent" end
        if conf.point == nil and conf.anchorMyPoint ~= nil then conf.point = conf.anchorMyPoint end
        if conf.relativePoint == nil and conf.anchorRelPoint ~= nil then conf.relativePoint = conf.anchorRelPoint end
        if conf.offsetX == nil and conf.x ~= nil then conf.offsetX = conf.x end
        if conf.offsetY == nil and conf.y ~= nil then conf.offsetY = conf.y end
        if conf.width == nil and conf.frameWidth ~= nil then conf.width = conf.frameWidth end
        if conf.height == nil and conf.frameHeight ~= nil then conf.height = conf.frameHeight end
        NormalizeNumber(conf, "offsetX", -4096, 4096)
        NormalizeNumber(conf, "offsetY", -4096, 4096)
        NormalizeNumber(conf, "x", -4096, 4096)
        NormalizeNumber(conf, "y", -4096, 4096)
        NormalizeNumber(conf, "width", 1, 4096)
        NormalizeNumber(conf, "height", 1, 4096)
        NormalizeNumber(conf, "frameWidth", 1, 4096)
        NormalizeNumber(conf, "frameHeight", 1, 4096)
        NormalizeNumber(conf, "spacing", -4096, 4096)
        if conf.point == "" then conf.point = nil end
        if conf.relativePoint == "" then conf.relativePoint = nil end
        if type(conf.point) == "string" then conf.point = string.upper(conf.point) end
        if type(conf.relativePoint) == "string" then conf.relativePoint = string.upper(conf.relativePoint) end
        NormalizeAnchorTo(conf)
    end

    for i = 1, #MSUF_PROFILEIO_UNIT_KEYS do
        NormalizeUnit(profile[MSUF_PROFILEIO_UNIT_KEYS[i]])
    end
    for i = 1, 5 do
        NormalizeUnit(profile["boss" .. i])
    end
    if type(profile.general) == "table" and profile.general.anchorName == "UI_Parent" then
        profile.general.anchorName = "UIParent"
    end
    return profile, changed
end

local MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA = 600
local MSUF_PROFILEIO_LEGACY_PROFILE_SCHEMA_56 = 560
--- This revision describes the normalization performed by
--- MSUF_ProfileIO_TranslateProfileToCurrent, independently from the broad
--- default-fill revision owned by MSUF_Defaults.lua. Bump it whenever that
--- translation pipeline gains a new mandatory repair.
local MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION = 21
local MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY = "profileModelRevision"
--- RC17's destructive hard cut established revision 1 as the canonical Unit
--- Aura baseline. Later revisions may migrate ownership or storage in place;
--- they must never make an already-canonical profile eligible for this reset.
local MSUF_PROFILEIO_UNIT_AURA_RESET_BASELINE_REVISION = 1
local MSUF_PROFILEIO_GROUP_AURA_MODEL_REVISION = 1
local MSUF_PROFILEIO_GROUP_AURA_SCOPES = { "gf_party", "gf_raid", "gf_mythicraid" }
local MSUF_PROFILEIO_GROUP_AURA_FILTER_LANES = { "buff", "debuff" }
local MSUF_PROFILEIO_GF_CURRENT_FILTER_TOKENS = {
    buff = {
        ALL = "ALL",
        PLAYER = "Player",
        BIGDEFENSIVE = "BigDefensive",
        BIGDEFENSIVEPLAYER = "BigDefensivePlayer",
        EXTERNALDEFENSIVE = "ExternalDefensive",
        EXTERNALDEFENSIVEPLAYER = "ExternalDefensivePlayer",
        RAIDINCOMBAT = "RaidInCombat",
        RAID = "Raid",
        RAIDPLAYER = "RaidPlayer",
    },
    debuff = {
        ALL = "ALL",
        PLAYER = "Player",
        RAID = "Raid",
        RAIDINCOMBAT = "RaidInCombat",
        RAIDPLAYERDISPELLABLE = "RAID_PLAYER_DISPELLABLE",
        DISPELLABLE = "DISPELLABLE",
        CROWDCONTROL = "CROWD_CONTROL",
        NONPLAYER = "NonPlayer",
    },
}

local function MSUF_ProfileIO_HasCanonicalUnitAuraBaseline(auras)
    return type(auras) == "table"
        and (tonumber(auras[MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY]) or 0)
            >= MSUF_PROFILEIO_UNIT_AURA_RESET_BASELINE_REVISION
end
local function MSUF_ProfileIO_NormalizeGFAuraFilterToken(lane, token)
    if lane ~= "buff" and lane ~= "debuff" then return token end
    local auraFilter = (type(MSUF) == "table" and type(MSUF.GF) == "table" and MSUF.GF.AuraFilter)
        or _G.MSUF_GF_AuraFilter
    local normalize = auraFilter and auraFilter.NormalizeFilterToken
    if type(normalize) == "function" then
        return normalize(lane, token)
    end
    local key = tostring(token or "ALL"):upper():gsub("[^A-Z0-9]", "")
    return MSUF_PROFILEIO_GF_CURRENT_FILTER_TOKENS[lane][key] or "ALL"
end
local function MSUF_ProfileIO_NormalizeGFAuraFilterTokens(profile, apply)
    if type(profile) ~= "table" then return false end
    local changed = false
    for i = 1, #MSUF_PROFILEIO_GROUP_AURA_SCOPES do
        local conf = profile[MSUF_PROFILEIO_GROUP_AURA_SCOPES[i]]
        local auras = type(conf) == "table" and conf.auras or nil
        if type(auras) == "table" then
            for j = 1, #MSUF_PROFILEIO_GROUP_AURA_FILTER_LANES do
                local lane = MSUF_PROFILEIO_GROUP_AURA_FILTER_LANES[j]
                local group = auras[lane]
                if type(group) == "table" and group.filterToken ~= nil then
                    local normalized = MSUF_ProfileIO_NormalizeGFAuraFilterToken(lane, group.filterToken)
                    if normalized ~= group.filterToken then
                        changed = true
                        if apply then group.filterToken = normalized end
                    end
                end
            end
        end
    end
    return changed
end
function MSUF.ProfileIOGroupHasRetiredAuraFields(conf)
    return type(conf) == "table" and (
        conf.aurasEnabled ~= nil or conf.auraMaxIcons ~= nil or conf.auraIconSize ~= nil
        or conf.auraAnchor ~= nil or conf.auraGrowthX ~= nil or conf.auraGrowthY ~= nil
        or conf.auraSpacing ~= nil or conf.auraPerRow ~= nil
        or conf.privateAurasEnabled ~= nil or conf.privateAuraMax ~= nil
        or conf.privateAuraSize ~= nil or conf.privateAuraAnchor ~= nil
        or conf.privateAuraX ~= nil or conf.privateAuraY ~= nil
        or conf.privateAuraCountdown ~= nil or conf._auraMigV2 ~= nil)
end
function MSUF.ProfileIOGroupHasAuraPayload(conf)
    return type(conf) == "table" and (
        type(conf.auras) == "table" or type(conf.privateAuras) == "table"
        or type(conf.spellIndicators) == "table"
        or MSUF.ProfileIOGroupHasRetiredAuraFields(conf))
end
local MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS = {
    "player", "target", "focus",
    "boss1", "boss2", "boss3", "boss4", "boss5",
}
local MSUF_PROFILEIO_LEGACY_UNIT_NAME_ANCHORS = {
    LEFT = "TOPLEFT",
    CENTER = "TOP",
    RIGHT = "TOPRIGHT",
}
local MSUF_PROFILEIO_TEXT_SCOPE_KEYS = {
    "general",
    "player", "target", "targettarget",
    "focus", "focustarget",
    "pet", "boss", "boss1", "boss2", "boss3", "boss4", "boss5",
    "gf_party", "gf_raid", "gf_mythicraid",
}
local MSUF_PROFILEIO_TEXT_NUMERIC_KEYS = {
    nameOffsetX = { -500, 500 },
    nameOffsetY = { -500, 500 },
    nameTextOffsetX = { -500, 500 },
    nameTextOffsetY = { -500, 500 },
    hpOffsetX = { -500, 500 },
    hpOffsetY = { -500, 500 },
    hpTextOffsetX = { -500, 500 },
    hpTextOffsetY = { -500, 500 },
    powerOffsetX = { -500, 500 },
    powerOffsetY = { -500, 500 },
    powerTextOffsetX = { -500, 500 },
    powerTextOffsetY = { -500, 500 },
    nameFontSize = { 6, 128 },
    hpFontSize = { 6, 128 },
    powerFontSize = { 6, 128 },
    fontBaselineOffset = { -4, 4 },
    nameMaxChars = { 0, 256 },
    shortenNameMaxChars = { 0, 256 },
    shortenNameFrontMaskPx = { 0, 128 },
    nameTextLayer = { 0, 30 },
    hpTextLayer = { 0, 30 },
    textLayer = { 0, 30 },
    powerTextLayer = { 0, 30 },
}
local MSUF_PROFILEIO_TEXT_SIDE_PREFIXES = {
    "hpTextLeft", "hpTextCenter", "hpTextRight",
    "hpLeft", "hpCenter", "hpRight",
    "powerTextLeft", "powerTextCenter", "powerTextRight",
    "powerLeft", "powerCenter", "powerRight",
}
local MSUF_PROFILEIO_DIRECT_TEXT_SUFFIXES = {
    "Name",
    "HealthLeft", "HealthCenter", "HealthRight",
    "PowerLeft", "PowerCenter", "PowerRight",
}
local MSUF_PROFILEIO_TEXT_MODE_KEYS = {
    "textLeft", "textCenter", "textRight",
    "hpTextLeft", "hpTextCenter", "hpTextRight",
    "hpTextMode",
    "powerTextLeft", "powerTextCenter", "powerTextRight",
    "powerTextMode",
}
local MSUF_PROFILEIO_STATUS_PREFIXES = {
    "leaderIcon",
    "raidMarker",
    "levelIndicator",
    "bossNumberIndicator",
    "eliteIcon",
    "statusText",
    "statusGhostText",
    "statusAFKText",
    "statusAFKTimer",
    "statusDNDText",
    "combatStateIndicator",
    "restedStateIndicator",
    "restingStateIndicator",
    "incomingResIndicator",
    "pvpIndicator",
    "stanceIndicator",
    "raidGroupName",
}
local MSUF_PROFILEIO_GROUP_STATUS_NUMERIC_KEYS = {
    roleIconSize = { 1, 256 },
    roleIconX = { -500, 500 },
    roleIconY = { -500, 500 },
    roleIconLayer = { 0, 30 },
    raidMarkerSize = { 1, 256 },
    raidMarkerX = { -500, 500 },
    raidMarkerY = { -500, 500 },
    raidMarkerLayer = { 0, 30 },
    leaderIconSize = { 1, 256 },
    leaderIconX = { -500, 500 },
    leaderIconY = { -500, 500 },
    leaderIconLayer = { 0, 30 },
    assistIconSize = { 1, 256 },
    assistIconX = { -500, 500 },
    assistIconY = { -500, 500 },
    assistIconLayer = { 0, 30 },
    statusTextSize = { 1, 256 },
    statusOffsetX = { -500, 500 },
    statusOffsetY = { -500, 500 },
    statusTextLayer = { 0, 30 },
    statusGhostTextSize = { 1, 256 },
    statusGhostOffsetX = { -500, 500 },
    statusGhostOffsetY = { -500, 500 },
    statusGhostTextLayer = { 0, 30 },
    statusAFKTextSize = { 1, 256 },
    statusAFKOffsetX = { -500, 500 },
    statusAFKOffsetY = { -500, 500 },
    statusAFKTextLayer = { 0, 30 },
    statusAFKTimerTextSize = { 1, 256 },
    statusAFKTimerOffsetX = { -500, 500 },
    statusAFKTimerOffsetY = { -500, 500 },
    statusAFKTimerTextLayer = { 0, 30 },
    statusDNDTextSize = { 1, 256 },
    statusDNDOffsetX = { -500, 500 },
    statusDNDOffsetY = { -500, 500 },
    statusDNDTextLayer = { 0, 30 },
    groupNumberSize = { 1, 256 },
    groupNumberX = { -500, 500 },
    groupNumberY = { -500, 500 },
    groupNumberLayer = { 0, 30 },
}
local MSUF_PROFILEIO_GROUP_STATUS_ANCHOR_KEYS = {
    "roleIconAnchor",
    "raidMarkerAnchor",
    "leaderIconAnchor",
    "assistIconAnchor",
    "statusTextAnchor",
    "statusGhostTextAnchor",
    "statusAFKTextAnchor",
    "statusAFKTimerTextAnchor",
    "statusDNDTextAnchor",
    "groupNumberAnchor",
}
local MSUF_PROFILEIO_UNIT_STATUS_BOOL_ALIASES = {
    { "showLeaderIcon", "leaderIcon" },
    { "showRaidMarker", "raidMarker" },
    { "showLevelIndicator", "levelIndicator" },
    { "showEliteIcon", "eliteIcon" },
    { "statusTextEnabled", "statusText" },
    { "showCombatStateIndicator", "combatStateIndicator" },
    { "showRestingIndicator", "restedStateIndicator" },
    { "showRestingIndicator", "restingStateIndicator" },
    { "showIncomingResIndicator", "incomingResIndicator" },
    { "showPvpIndicator", "pvpIndicator" },
    { "showRaidGroupInName", "raidGroupName" },
}
local MSUF_PROFILEIO_UNIT_STATUS_OFFSET_ALIASES = {
    { "leaderIconOffsetX", "leaderIconX" },
    { "leaderIconOffsetY", "leaderIconY" },
    { "raidMarkerOffsetX", "raidMarkerX" },
    { "raidMarkerOffsetY", "raidMarkerY" },
    { "statusTextOffsetX", "statusOffsetX" },
    { "statusTextOffsetY", "statusOffsetY" },
    { "raidGroupNameOffsetX", "groupNumberX" },
    { "raidGroupNameOffsetY", "groupNumberY" },
    { "raidGroupNameLayer", "groupNumberLayer" },
}
local MSUF_PROFILEIO_GROUP_STATUS_BOOL_ALIASES = {
    { "roleIcon", "showRoleIcon" },
    { "leaderIcon", "showLeaderIcon" },
    { "assistIcon", "showAssistIcon" },
    { "raidMarker", "showRaidMarker" },
    { "statusText", "statusTextEnabled" },
    { "statusGhostText", "statusGhostTextEnabled" },
    { "statusAFKText", "statusAFKTextEnabled" },
    { "statusDNDText", "statusDNDTextEnabled" },
    { "showGroupNumber", "showRaidGroupInName" },
}
local MSUF_PROFILEIO_GROUP_STATUS_OFFSET_ALIASES = {
    { "roleIconX", "roleIconOffsetX" },
    { "roleIconY", "roleIconOffsetY" },
    { "leaderIconX", "leaderIconOffsetX" },
    { "leaderIconY", "leaderIconOffsetY" },
    { "assistIconX", "assistIconOffsetX" },
    { "assistIconY", "assistIconOffsetY" },
    { "raidMarkerX", "raidMarkerOffsetX" },
    { "raidMarkerY", "raidMarkerOffsetY" },
    { "statusOffsetX", "statusTextOffsetX" },
    { "statusOffsetY", "statusTextOffsetY" },
    { "statusGhostOffsetX", "statusGhostTextOffsetX" },
    { "statusGhostOffsetY", "statusGhostTextOffsetY" },
    { "statusAFKOffsetX", "statusAFKTextOffsetX" },
    { "statusAFKOffsetY", "statusAFKTextOffsetY" },
    { "statusDNDOffsetX", "statusDNDTextOffsetX" },
    { "statusDNDOffsetY", "statusDNDTextOffsetY" },
    { "groupNumberX", "raidGroupNameOffsetX" },
    { "groupNumberY", "raidGroupNameOffsetY" },
    { "groupNumberLayer", "raidGroupNameLayer" },
}
local MSUF_PROFILEIO_LEGACY_SIGNAL_UNIT_KEYS = {
    "player", "target", "targettarget", "tot", "targetoftarget",
    "focus", "focustarget", "focus_target", "focustargettarget",
    "pet", "boss", "boss1", "boss2", "boss3", "boss4", "boss5",
}
local MSUF_PROFILEIO_AURA_NUMERIC_KEYS = {
    offsetX = { -4096, 4096 },
    offsetY = { -4096, 4096 },
    buffOffsetX = { -4096, 4096 },
    buffOffsetY = { -4096, 4096 },
    debuffOffsetX = { -4096, 4096 },
    debuffOffsetY = { -4096, 4096 },
    buffGroupOffsetX = { -4096, 4096 },
    buffGroupOffsetY = { -4096, 4096 },
    debuffGroupOffsetX = { -4096, 4096 },
    debuffGroupOffsetY = { -4096, 4096 },
    iconSize = { 1, 256 },
    buffIconSize = { 1, 256 },
    debuffIconSize = { 1, 256 },
    iconZoom = { 100, 200 },
    buffIconZoom = { 100, 200 },
    debuffIconZoom = { 100, 200 },
    buffGroupIconSize = { 1, 256 },
    debuffGroupIconSize = { 1, 256 },
    privateSize = { 1, 256 },
    spacing = { 0, 128 },
    splitSpacing = { 0, 256 },
    buffSpacing = { 0, 128 },
    debuffSpacing = { 0, 128 },
    perRow = { 1, 80 },
    buffPerRow = { 1, 80 },
    debuffPerRow = { 1, 80 },
    maxIcons = { 0, 80 },
    maxBuffs = { 0, 80 },
    maxDebuffs = { 0, 80 },
    stackTextSize = { 1, 128 },
    cooldownTextSize = { 1, 128 },
    stackTextOffsetX = { -2000, 2000 },
    stackTextOffsetY = { -2000, 2000 },
    cooldownTextOffsetX = { -2000, 2000 },
    cooldownTextOffsetY = { -2000, 2000 },
    cooldownDecimalSeconds = { 0, 30 },
    buffLayer = { 0, 30 },
    debuffLayer = { 0, 30 },
    buffStackTextSize = { 1, 128 },
    debuffStackTextSize = { 1, 128 },
    buffCooldownTextSize = { 1, 128 },
    debuffCooldownTextSize = { 1, 128 },
    buffStackTextOffsetX = { -2000, 2000 },
    buffStackTextOffsetY = { -2000, 2000 },
    debuffStackTextOffsetX = { -2000, 2000 },
    debuffStackTextOffsetY = { -2000, 2000 },
    buffCooldownTextOffsetX = { -2000, 2000 },
    buffCooldownTextOffsetY = { -2000, 2000 },
    debuffCooldownTextOffsetX = { -2000, 2000 },
    debuffCooldownTextOffsetY = { -2000, 2000 },
    buffCooldownDecimalSeconds = { 0, 30 },
    debuffCooldownDecimalSeconds = { 0, 30 },
}
local MSUF_PROFILEIO_AURA_STRING_KEYS = {
    "growth", "rowWrap", "buffGrowth", "debuffGrowth", "privateGrowth",
    "buffGrowthX", "buffGrowthY", "debuffGrowthX", "debuffGrowthY",
    "buffRowWrap", "debuffRowWrap", "layoutMode", "buffDebuffAnchor",
    "stackCountAnchor", "cooldownTextAnchor", "buffAnchor", "debuffAnchor",
    "buffStackCountAnchor", "debuffStackCountAnchor",
    "buffCooldownTextAnchor", "debuffCooldownTextAnchor",
    "buffStrata", "debuffStrata",
    "debuffTypeBorderMode", "dispelBorderMode", "pandemicMode",
}

local function MSUF_ProfileIO_ToNumber(value)
    local n = tonumber(value)
    if n == nil then return nil end
    return n
end

local function MSUF_ProfileIO_NormalizeNumberField(tbl, key, minValue, maxValue)
    if type(tbl) ~= "table" or tbl[key] == nil then return false end
    local n = MSUF_ProfileIO_ToNumber(tbl[key])
    if n == nil then return false end
    if minValue ~= nil and n < minValue then
        n = minValue
    elseif maxValue ~= nil and n > maxValue then
        n = maxValue
    end
    if tbl[key] ~= n then
        tbl[key] = n
        return true
    end
    return false
end

local function MSUF_ProfileIO_CopyIfMissing(tbl, toKey, fromKey)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil or tbl[fromKey] == nil then
        return false
    end
    tbl[toKey] = tbl[fromKey]
    return true
end

local function MSUF_ProfileIO_CopyInverseBoolIfMissing(tbl, toKey, fromKey)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil or tbl[fromKey] == nil then
        return false
    end
    tbl[toKey] = not (tbl[fromKey] == true)
    return true
end

local function MSUF_ProfileIO_UpperStringField(tbl, key)
    if type(tbl) ~= "table" or type(tbl[key]) ~= "string" then return false end
    local value = tbl[key]
    if value == "" then
        tbl[key] = nil
        return true
    end
    local upper = string.upper(value)
    if value ~= upper then
        tbl[key] = upper
        return true
    end
    return false
end

local function MSUF_ProfileIO_TableHasAnyValue(tbl)
    return type(tbl) == "table" and next(tbl) ~= nil
end

local MSUF_PROFILEIO_AURA_GROWTH_PARTS = {
    RIGHTDOWN = { "RIGHT", "DOWN" },
    LEFTDOWN = { "LEFT", "DOWN" },
    RIGHTUP = { "RIGHT", "UP" },
    LEFTUP = { "LEFT", "UP" },
    RIGHT = { "RIGHT", nil },
    LEFT = { "LEFT", nil },
    UP = { "UP", "UP" },
    DOWN = { "DOWN", "DOWN" },
}

local function MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, toKey, fromKey)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil or tbl[fromKey] == nil then return false end
    local n = MSUF_ProfileIO_ToNumber(tbl[fromKey])
    if n == nil then return false end
    tbl[toKey] = n
    return true
end

local function MSUF_ProfileIO_CopyAuraGrowthAlias(tbl, fromKey, toGrowthKey, toWrapKey)
    if type(tbl) ~= "table" or tbl[fromKey] == nil then return false end
    local value = tostring(tbl[fromKey] or ""):upper()
    local parts = MSUF_PROFILEIO_AURA_GROWTH_PARTS[value]
    if not parts then return false end
    local changed = false
    if tbl[toGrowthKey] == nil then
        tbl[toGrowthKey] = parts[1]
        changed = true
    end
    if parts[2] ~= nil and tbl[toWrapKey] == nil then
        tbl[toWrapKey] = parts[2]
        changed = true
    end
    return changed
end

local function MSUF_ProfileIO_HasScopedFontOverrideValue(scope)
    if type(scope) ~= "table" then return false end
    if scope.fontOutline ~= nil or scope.noOutline ~= nil or scope.boldText ~= nil then return true end
    if scope.fontMonochrome ~= nil or scope.fontSlug ~= nil or scope.fontTextAlpha ~= nil or scope.fontBaselineOffset ~= nil then return true end
    if scope.textBackdrop ~= nil or scope.fontShadowStrength ~= nil or scope.fontShadowOpacity ~= nil or scope.fontShadowDistance ~= nil then return true end
    if scope.colorPowerTextByHealth ~= nil then return true end
    if scope.colorPowerTextByType ~= nil or scope.colorHealthTextByHealth ~= nil then return true end
    if scope.nameClassColor ~= nil or scope.npcNameRed ~= nil or scope.nameNpcClassColor ~= nil then return true end
    if scope.useGlobalFontColor == false then return true end
    if scope.fontR ~= nil or scope.fontG ~= nil or scope.fontB ~= nil then return true end
    local mode = scope.nameColorMode
    if mode ~= nil and mode ~= "" and mode ~= "DEFAULT" then return true end
    if scope.nameShortenEnabled ~= nil or scope.shortenNames ~= nil then return true end
    if (tonumber(scope.nameMaxChars) or 0) > 0 then return true end
    if scope.shortenNameMaxChars ~= nil or scope.nameClipSide ~= nil or scope.shortenNameClipSide ~= nil then return true end
    if scope.nameNoEllipsis ~= nil or scope.shortenNameShowDots ~= nil or scope.shortenNameFrontMaskPx ~= nil then return true end
    return false
end

local function MSUF_ProfileIO_NormalizeNameShorteningScope(scope, allowFontOverride, isGroupScope)
    if type(scope) ~= "table" then return false end
    local changed = false
    if isGroupScope then
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "nameShortenEnabled", "shortenNames") or changed
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "nameMaxChars", "shortenNameMaxChars") or changed
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "nameClipSide", "shortenNameClipSide") or changed
        changed = MSUF_ProfileIO_CopyInverseBoolIfMissing(scope, "nameNoEllipsis", "shortenNameShowDots") or changed
    else
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "shortenNames", "nameShortenEnabled") or changed
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "shortenNameMaxChars", "nameMaxChars") or changed
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "shortenNameClipSide", "nameClipSide") or changed
        changed = MSUF_ProfileIO_CopyInverseBoolIfMissing(scope, "shortenNameShowDots", "nameNoEllipsis") or changed
    end
    changed = MSUF_ProfileIO_NormalizeNumberField(scope, "shortenNameMaxChars", 0, 256) or changed
    changed = MSUF_ProfileIO_NormalizeNumberField(scope, "nameMaxChars", 0, 256) or changed
    changed = MSUF_ProfileIO_NormalizeNumberField(scope, "shortenNameFrontMaskPx", 0, 128) or changed
    changed = MSUF_ProfileIO_UpperStringField(scope, "shortenNameClipSide") or changed
    changed = MSUF_ProfileIO_UpperStringField(scope, "nameClipSide") or changed
    if allowFontOverride and scope.fontOverride == nil and MSUF_ProfileIO_HasScopedFontOverrideValue(scope) then
        scope.fontOverride = true
        changed = true
    end
    return changed
end

local function MSUF_ProfileIO_NormalizeTextScope(scope, isGroupScope, allowFontOverride)
    if type(scope) ~= "table" then return false end
    local changed = false
    if isGroupScope then
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "nameAnchor", "nameTextAnchor") or changed
    else
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "nameTextAnchor", "nameAnchor") or changed
    end
    changed = MSUF_ProfileIO_CopyIfMissing(scope, "nameOffsetX", "nameTextOffsetX") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(scope, "nameOffsetY", "nameTextOffsetY") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(scope, "hpOffsetX", "hpTextOffsetX") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(scope, "hpOffsetY", "hpTextOffsetY") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(scope, "powerOffsetX", "powerTextOffsetX") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(scope, "powerOffsetY", "powerTextOffsetY") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(scope, "textLeft", "hpTextLeft") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(scope, "textCenter", "hpTextCenter") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(scope, "textRight", "hpTextRight") or changed
    if isGroupScope then
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "textDelimiter", "hpTextSeparator") or changed
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "powerTextDelimiter", "powerTextSeparator") or changed
    else
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "hpTextSeparator", "textDelimiter") or changed
        changed = MSUF_ProfileIO_CopyIfMissing(scope, "powerTextSeparator", "powerTextDelimiter") or changed
    end

    for key, limits in pairs(MSUF_PROFILEIO_TEXT_NUMERIC_KEYS) do
        changed = MSUF_ProfileIO_NormalizeNumberField(scope, key, limits[1], limits[2]) or changed
    end
    for i = 1, #MSUF_PROFILEIO_TEXT_SIDE_PREFIXES do
        local prefix = MSUF_PROFILEIO_TEXT_SIDE_PREFIXES[i]
        changed = MSUF_ProfileIO_NormalizeNumberField(scope, prefix .. "OffsetX", -500, 500) or changed
        changed = MSUF_ProfileIO_NormalizeNumberField(scope, prefix .. "OffsetY", -500, 500) or changed
    end
    for i = 1, #MSUF_PROFILEIO_DIRECT_TEXT_SUFFIXES do
        local key = "direct" .. MSUF_PROFILEIO_DIRECT_TEXT_SUFFIXES[i]
        changed = MSUF_ProfileIO_CopyIfMissing(scope, key .. "OffsetX", key .. "X") or changed
        changed = MSUF_ProfileIO_CopyIfMissing(scope, key .. "OffsetY", key .. "Y") or changed
        changed = MSUF_ProfileIO_NormalizeNumberField(scope, key .. "OffsetX", -500, 500) or changed
        changed = MSUF_ProfileIO_NormalizeNumberField(scope, key .. "OffsetY", -500, 500) or changed
        changed = MSUF_ProfileIO_UpperStringField(scope, key .. "Point") or changed
        changed = MSUF_ProfileIO_UpperStringField(scope, key .. "RelativePoint") or changed
    end
    for i = 1, #MSUF_PROFILEIO_TEXT_MODE_KEYS do
        changed = MSUF_ProfileIO_UpperStringField(scope, MSUF_PROFILEIO_TEXT_MODE_KEYS[i]) or changed
    end
    changed = MSUF_ProfileIO_UpperStringField(scope, "nameTextAnchor") or changed
    changed = MSUF_ProfileIO_UpperStringField(scope, "nameAnchor") or changed
    if not isGroupScope then
        local legacyAnchor = MSUF_PROFILEIO_LEGACY_UNIT_NAME_ANCHORS[scope.nameTextAnchor]
        if legacyAnchor then
            scope.nameTextAnchor = legacyAnchor
            changed = true
        end
    end
    changed = MSUF_ProfileIO_NormalizeNameShorteningScope(scope, allowFontOverride == true, isGroupScope == true) or changed
    return changed
end

local function MSUF_ProfileIO_NormalizeStatusScope(scope, isGroupScope)
    if type(scope) ~= "table" then return false end
    local changed = false
    local boolAliases = isGroupScope and MSUF_PROFILEIO_GROUP_STATUS_BOOL_ALIASES or MSUF_PROFILEIO_UNIT_STATUS_BOOL_ALIASES
    for i = 1, #boolAliases do
        changed = MSUF_ProfileIO_CopyIfMissing(scope, boolAliases[i][1], boolAliases[i][2]) or changed
    end
    local offsetAliases = isGroupScope and MSUF_PROFILEIO_GROUP_STATUS_OFFSET_ALIASES or MSUF_PROFILEIO_UNIT_STATUS_OFFSET_ALIASES
    for i = 1, #offsetAliases do
        changed = MSUF_ProfileIO_CopyIfMissing(scope, offsetAliases[i][1], offsetAliases[i][2]) or changed
    end
    for i = 1, #MSUF_PROFILEIO_STATUS_PREFIXES do
        local prefix = MSUF_PROFILEIO_STATUS_PREFIXES[i]
        changed = MSUF_ProfileIO_NormalizeNumberField(scope, prefix .. "Size", 1, 256) or changed
        changed = MSUF_ProfileIO_NormalizeNumberField(scope, prefix .. "OffsetX", -500, 500) or changed
        changed = MSUF_ProfileIO_NormalizeNumberField(scope, prefix .. "OffsetY", -500, 500) or changed
        changed = MSUF_ProfileIO_NormalizeNumberField(scope, prefix .. "Layer", 0, 30) or changed
        changed = MSUF_ProfileIO_UpperStringField(scope, prefix .. "Anchor") or changed
    end
    if isGroupScope then
        for key, limits in pairs(MSUF_PROFILEIO_GROUP_STATUS_NUMERIC_KEYS) do
            changed = MSUF_ProfileIO_NormalizeNumberField(scope, key, limits[1], limits[2]) or changed
        end
        for i = 1, #MSUF_PROFILEIO_GROUP_STATUS_ANCHOR_KEYS do
            changed = MSUF_ProfileIO_UpperStringField(scope, MSUF_PROFILEIO_GROUP_STATUS_ANCHOR_KEYS[i]) or changed
        end
    end
    return changed
end

local MSUF_PROFILEIO_GROUP_STATUS_SCOPES = { gf_party = true, gf_raid = true, gf_mythicraid = true }
local MSUF_PROFILEIO_UNIT_STATUS_SPLIT = {
    { "statusDeadTextEnabled", "showDead", true, nil },
    { "statusGhostTextEnabled", "showGhost", true, "statusGhostText" },
    { "statusAFKTextEnabled", "showAFK", false, "statusAFKText" },
    { "statusDNDTextEnabled", "showDND", false, "statusDNDText" },
}
local MSUF_PROFILEIO_STATUS_LAYOUT_SUFFIXES = { "Size", "Anchor", "OffsetX", "OffsetY", "Layer" }
local function MSUF_ProfileIO_MigrateSplitStatusText(profile)
    if type(profile) ~= "table" then return false end
    local changed = false
    local general = type(profile.general) == "table" and profile.general or {}
    local states = type(general.statusIndicators) == "table" and general.statusIndicators or {}
    for i = 1, #MSUF_PROFILEIO_TEXT_SCOPE_KEYS do
        local scopeKey = MSUF_PROFILEIO_TEXT_SCOPE_KEYS[i]
        local scope = profile[scopeKey]
        if type(scope) == "table" and MSUF_PROFILEIO_GROUP_STATUS_SCOPES[scopeKey] then
            if scope.statusDNDText == nil and scope.statusAFKText ~= nil then
                scope.statusDNDText = scope.statusAFKText
                scope.statusDNDTextSize = scope.statusAFKTextSize
                scope.statusDNDTextAnchor = scope.statusAFKTextAnchor
                scope.statusDNDTextLayer = scope.statusAFKTextLayer
                scope.statusDNDOffsetX = scope.statusAFKOffsetX
                scope.statusDNDOffsetY = scope.statusAFKOffsetY
                changed = true
            end
        elseif type(scope) == "table" and scopeKey ~= "general" then
            local master = scope.statusTextEnabled
            if master == nil then master = general.statusTextEnabled end
            if master == nil then master = true end
            for j = 1, #MSUF_PROFILEIO_UNIT_STATUS_SPLIT do
                local def = MSUF_PROFILEIO_UNIT_STATUS_SPLIT[j]
                if scope[def[1]] == nil then
                    local state = states[def[2]]
                    if state == nil then state = def[3] end
                    scope[def[1]] = master == true and state == true
                    changed = true
                end
                local prefix = def[4]
                if prefix then
                    for k = 1, #MSUF_PROFILEIO_STATUS_LAYOUT_SUFFIXES do
                        local suffix = MSUF_PROFILEIO_STATUS_LAYOUT_SUFFIXES[k]
                        local key, legacyKey = prefix .. suffix, "statusText" .. suffix
                        if scope[key] == nil then
                            local value = scope[legacyKey]
                            if value == nil then value = general[legacyKey] end
                            if value ~= nil then scope[key], changed = value, true end
                        end
                    end
                end
            end
        end
    end
    return changed
end

local function MSUF_ProfileIO_ProfileHasLegacySignals(profile)
    if type(profile) ~= "table" then return false end
    if type(profile.auras2) == "table" then return true end
    for i = 1, #MSUF_PROFILEIO_LEGACY_SIGNAL_UNIT_KEYS do
        local scope = profile[MSUF_PROFILEIO_LEGACY_SIGNAL_UNIT_KEYS[i]]
        if type(scope) == "table" and (scope.anchorMyPoint ~= nil or scope.anchorRelPoint ~= nil) then
            return true
        end
    end
    return false
end

local function MSUF_ProfileIO_AuraOverridesNeedRepair(profile)
    local auras = type(profile) == "table" and profile.auras3 or nil
    local perUnit = type(auras) == "table" and auras.perUnit or nil
    if type(perUnit) ~= "table" then return false end
    for _, unitCfg in pairs(perUnit) do
        if type(unitCfg) == "table" then
            if MSUF_ProfileIO_TableHasAnyValue(unitCfg.layout) and unitCfg.overrideLayout == nil then return true end
            if MSUF_ProfileIO_TableHasAnyValue(unitCfg.layoutShared) and unitCfg.overrideSharedLayout == nil then return true end
        end
    end
    return false
end

local function MSUF_ProfileIO_ProfileHasDeprecatedUnitAliases(profile)
    if type(profile) ~= "table" then return false end
    for i = 1, #MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES do
        local aliases = MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES[i].aliases
        for j = 1, #aliases do
            if profile[aliases[j]] ~= nil then
                return true
            end
        end
    end
    return false
end

local function MSUF_ProfileIO_ProfileNeedsLegacyRepair(profile)
    if type(profile) ~= "table" then return false end
    if MSUF_ProfileIO_NormalizeGFAuraFilterTokens(profile, false) then return true end
    if profile.auras ~= nil or type(profile.auras2) == "table" then return true end
    local auras = type(profile.auras3) == "table" and profile.auras3 or nil
    if auras and not MSUF_ProfileIO_HasCanonicalUnitAuraBaseline(auras) then
        return true
    end
    for i = 1, #MSUF_PROFILEIO_GROUP_AURA_SCOPES do
        local conf = profile[MSUF_PROFILEIO_GROUP_AURA_SCOPES[i]]
        if type(conf) == "table" then
            local groupAuras = type(conf.auras) == "table" and conf.auras or nil
            local hasAuraPayload = MSUF.ProfileIOGroupHasAuraPayload(conf)
            if hasAuraPayload and (not groupAuras
                or tonumber(groupAuras[MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY]) ~= MSUF_PROFILEIO_GROUP_AURA_MODEL_REVISION
                or MSUF.ProfileIOGroupHasRetiredAuraFields(conf)) then
                return true
            end
        end
    end
    local translatedAuras = auras
        and auras._msufAuras3TranslatedFromLegacyAuras2 == true
    local legacyVisualProfile = translatedAuras
        or profile._msufLegacy55FrameOutlineBackground_v1 == true
    if translatedAuras
        and profile._msufLegacy55FrameOutlineBackground_v1 ~= true then return true end
    if legacyVisualProfile and profile._msufLegacy55PowerTextVisibility_v1 ~= true then return true end
    if legacyVisualProfile and profile._msufLegacy55UnitTextSlots_v1 ~= true then return true end
    if legacyVisualProfile and profile._msufLegacy55GroupTextGeometry_v1 ~= true then return true end
    if legacyVisualProfile and profile._msufLegacy55GroupNameAnchorRoot_v1 ~= true then return true end
    if MSUF_ProfileIO_AuraOverridesNeedRepair(profile) then return true end
    if MSUF_ProfileIO_ProfileHasDeprecatedUnitAliases(profile) then return true end
    for i = 1, #MSUF_PROFILEIO_LEGACY_SIGNAL_UNIT_KEYS do
        local scope = profile[MSUF_PROFILEIO_LEGACY_SIGNAL_UNIT_KEYS[i]]
        if type(scope) == "table"
            and ((scope.anchorMyPoint ~= nil and scope.point == nil)
                or (scope.anchorRelPoint ~= nil and scope.relativePoint == nil)) then
            return true
        end
    end
    return false
end

MSUF.ProfileIOMaterializeLegacy55UnitTextSlots = function(profile)
    if type(profile) ~= "table" or profile._msufLegacy55UnitTextSlots_v1 == true then return false end

    local changed = false
    local general = type(profile.general) == "table" and profile.general or nil
    local function MigrateHealthMode(value)
        if value == "FULL_ONLY" then return "CURRENT" end
        if value == "PERCENT_ONLY" then return "PERCENT" end
        if value == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
        if value == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
        return value
    end
    local function MigratePowerMode(value)
        if value == "FULL_SLASH_MAX" then return "CURMAX" end
        if value == "FULL_ONLY" then return "CURRENT" end
        if value == "PERCENT_ONLY" then return "PERCENT" end
        if value == "FULL_PLUS_PERCENT" or value == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
        return value
    end
    local hpMode = MigrateHealthMode(general and general.hpTextMode) or "CURPERCENT"
    local powerMode = MigratePowerMode(general and general.powerTextMode) or "CURPERCENT"
    if general then
        if general.hpTextMode ~= hpMode then
            general.hpTextMode = hpMode
            changed = true
        end
        if general.powerTextMode ~= powerMode then
            general.powerTextMode = powerMode
            changed = true
        end
    end

    -- These are the exact values the 5.57 loader materialized when an older
    -- exported profile still only carried hpTextMode/powerTextMode. Do this in
    -- the import pipeline before 6.0 defaults can assign a different slot.
    local defaults = {
        hpTextMode = hpMode,
        hpTextReverse = general and general.hpTextReverse == true or false,
        powerTextMode = powerMode,
        hpTextLeftOffsetX = 0,
        hpTextLeftOffsetY = 0,
        hpTextCenterOffsetX = 0,
        hpTextCenterOffsetY = 0,
        hpTextRightOffsetX = 0,
        hpTextRightOffsetY = 0,
        powerTextLeftOffsetX = 0,
        powerTextLeftOffsetY = 0,
        powerTextCenterOffsetX = 0,
        powerTextCenterOffsetY = 0,
        powerTextRightOffsetX = 0,
        powerTextRightOffsetY = 0,
        hpTextSeparator = general and general.hpTextSeparator ~= nil and general.hpTextSeparator or "-",
        powerTextSeparator = general and general.powerTextSeparator ~= nil and general.powerTextSeparator
            or (general and general.hpTextSeparator ~= nil and general.hpTextSeparator or "-"),
        nameTextLayer = tonumber(general and general.nameTextLayer) or 5,
        hpTextLayer = tonumber(general and (general.hpTextLayer or general.textLayer)) or 5,
        powerTextLayer = tonumber(general and general.powerTextLayer) or 2,
    }
    local units = {
        "player", "target", "focus", "targettarget", "focustarget", "pet", "boss",
        "boss1", "boss2", "boss3", "boss4", "boss5",
    }
    for i = 1, #units do
        local conf = profile[units[i]]
        if type(conf) == "table" then
            for field, fallback in pairs(defaults) do
                if conf[field] == nil then
                    conf[field] = fallback
                    changed = true
                end
            end
            local unitHpMode = MigrateHealthMode(conf.hpTextMode) or hpMode
            local unitPowerMode = MigratePowerMode(conf.powerTextMode) or powerMode
            if conf.hpTextMode ~= unitHpMode then
                conf.hpTextMode = unitHpMode
                changed = true
            end
            if conf.powerTextMode ~= unitPowerMode then
                conf.powerTextMode = unitPowerMode
                changed = true
            end
            if conf.textLeft == nil and conf.textCenter == nil and conf.textRight == nil then
                conf.textLeft, conf.textCenter, conf.textRight = "NONE", "NONE", unitHpMode
                changed = true
            else
                if conf.textLeft == nil then conf.textLeft = "NONE"; changed = true end
                if conf.textCenter == nil then conf.textCenter = "NONE"; changed = true end
                if conf.textRight == nil then conf.textRight = hpMode; changed = true end
            end
            if conf.powerTextLeft == nil and conf.powerTextCenter == nil and conf.powerTextRight == nil then
                conf.powerTextLeft, conf.powerTextCenter, conf.powerTextRight = "NONE", "NONE", unitPowerMode
                changed = true
            else
                if conf.powerTextLeft == nil then conf.powerTextLeft = "NONE"; changed = true end
                if conf.powerTextCenter == nil then conf.powerTextCenter = "NONE"; changed = true end
                if conf.powerTextRight == nil then conf.powerTextRight = powerMode; changed = true end
            end
            if conf.hpPowerTextOverride ~= nil then
                conf.hpPowerTextOverride = nil
                changed = true
            end
        end
    end
    if general and general._msufUFTextPerUnitMigrated_v4325 ~= true then
        general._msufUFTextPerUnitMigrated_v4325 = true
        changed = true
    end
    profile._msufLegacy55UnitTextSlots_v1 = true
    changed = true
    return changed
end

MSUF.ProfileIOMaterializeLegacy55GroupTextGeometry = function(profile)
    if type(profile) ~= "table" or profile._msufLegacy55GroupTextGeometry_v1 == true then return false end

    local changed = false
    -- 5.57 resolved every missing Group Frame text coordinate against these
    -- values. In 6.0 the Name X factory default is intentionally 28 to reserve
    -- the status-icon lane, so letting the new defaults fill an omitted legacy
    -- field visibly moves imported names. Materialize the old coordinate set
    -- before EnsureDB runs while preserving every explicit profile value.
    local defaults = {
        nameAnchor = "LEFT",
        nameOffsetX = 0,
        nameOffsetY = 0,
        hpOffsetX = 0,
        hpOffsetY = 0,
        hpTextLeftOffsetX = 0,
        hpTextLeftOffsetY = 0,
        hpTextCenterOffsetX = 0,
        hpTextCenterOffsetY = 0,
        hpTextRightOffsetX = 0,
        hpTextRightOffsetY = 0,
        powerOffsetX = 0,
        powerOffsetY = 0,
        powerTextLeftOffsetX = 0,
        powerTextLeftOffsetY = 0,
        powerTextCenterOffsetX = 0,
        powerTextCenterOffsetY = 0,
        powerTextRightOffsetX = 0,
        powerTextRightOffsetY = 0,
    }
    local scopes = { "gf_party", "gf_raid", "gf_mythicraid" }
    for i = 1, #scopes do
        local conf = profile[scopes[i]]
        if type(conf) == "table" then
            for field, fallback in pairs(defaults) do
                if conf[field] == nil then
                    conf[field] = fallback
                    changed = true
                end
            end
        end
    end
    profile._msufLegacy55GroupTextGeometry_v1 = true
    return true
end

MSUF.ProfileIOMaterializeLegacy55GroupNameAnchorRoot = function(profile)
    if type(profile) ~= "table" or profile._msufLegacy55GroupNameAnchorRoot_v1 == true then return false end

    -- 5.73 positioned Group names against barGroup, the complete visual slot.
    -- The native 6.0 text element normally uses the Health bar instead, whose
    -- bottom edge is raised by an embedded Power bar. Keep the legacy anchor
    -- root explicit so identical saved offsets remain visually identical while
    -- native 6.0 profiles retain their current Health-relative semantics.
    local scopes = { "gf_party", "gf_raid", "gf_mythicraid" }
    for i = 1, #scopes do
        local conf = profile[scopes[i]]
        if type(conf) == "table" and conf._msufLegacyNameAnchorToFrame ~= true then
            conf._msufLegacyNameAnchorToFrame = true
        end
    end
    profile._msufLegacy55GroupNameAnchorRoot_v1 = true
    return true
end

local function MSUF_ProfileIO_DetectProfileSchema(profile, context)
    local schema = tonumber(profile and profile._msufProfileSchema)
    if schema and schema < MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA then return schema end
    --- A stored 6.x profile may need a newer normalization revision without
    --- becoming a 5.x profile again. Keep schema identity separate from the
    --- repair fast path so stale aliases cannot trigger broad legacy rewrites.
    if schema and type(context) == "table" and context.trustNormalizationMarker == true then return schema end
    if schema and not MSUF_ProfileIO_ProfileNeedsLegacyRepair(profile) then return schema end
    if MSUF_ProfileIO_ProfileHasLegacySignals(profile) then
        return MSUF_PROFILEIO_LEGACY_PROFILE_SCHEMA_56
    end
    local contextSchema = type(context) == "table" and tonumber(context.schema) or nil
    -- MSUF 5.57 snapshots used the outer snapshot schema `1`, including
    -- category-only exports that do not carry an Aura2 root or other full-
    -- profile legacy signals. Treat every positive pre-6.0 snapshot schema as
    -- legacy so partial Unit/Group imports receive the same compatibility pass
    -- as a complete 5.57 profile.
    if contextSchema and contextSchema > 0 and contextSchema < MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA then
        return MSUF_PROFILEIO_LEGACY_PROFILE_SCHEMA_56
    end
    if contextSchema and contextSchema >= MSUF_PROFILEIO_LEGACY_PROFILE_SCHEMA_56 then
        return contextSchema
    end
    return MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
end

local function MSUF_ProfileIO_NormalizeLegacyRootNameShortening(profile, createGeneral)
    if type(profile) ~= "table" then return false end
    local changed = false
    changed = MSUF_ProfileIO_CopyIfMissing(profile, "shortenNames", "nameShortenEnabled") or changed
    local general = profile.general
    if type(general) ~= "table" then
        if createGeneral == false then
            return changed
        end
        general = {}
        profile.general = general
        changed = true
    end
    if profile.shortenNames == nil and general.shortenNames ~= nil then
        profile.shortenNames = general.shortenNames
        changed = true
    elseif profile.shortenNames == nil and general.nameShortenEnabled ~= nil then
        profile.shortenNames = general.nameShortenEnabled
        changed = true
    end
    if general.shortenNameMaxChars == nil and profile.shortenNameMaxChars ~= nil then
        general.shortenNameMaxChars = profile.shortenNameMaxChars
        changed = true
    end
    if general.shortenNameClipSide == nil and profile.shortenNameClipSide ~= nil then
        general.shortenNameClipSide = profile.shortenNameClipSide
        changed = true
    end
    if general.shortenNameShowDots == nil and profile.shortenNameShowDots ~= nil then
        general.shortenNameShowDots = profile.shortenNameShowDots
        changed = true
    end
    if general.shortenNameFrontMaskPx == nil and profile.shortenNameFrontMaskPx ~= nil then
        general.shortenNameFrontMaskPx = profile.shortenNameFrontMaskPx
        changed = true
    end
    changed = MSUF_ProfileIO_NormalizeNumberField(general, "shortenNameMaxChars", 0, 256) or changed
    changed = MSUF_ProfileIO_NormalizeNumberField(general, "shortenNameFrontMaskPx", 0, 128) or changed
    changed = MSUF_ProfileIO_UpperStringField(general, "shortenNameClipSide") or changed
    return changed
end

local function MSUF_ProfileIO_NormalizeAuraLayoutTable(tbl)
    if type(tbl) ~= "table" then return false end
    local changed = false
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "maxBuffs", "maxIcons") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "maxDebuffs", "maxIcons") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "buffGroupIconSize", "buffIconSize") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "debuffGroupIconSize", "debuffIconSize") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "buffGroupIconSize", "iconSize") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "debuffGroupIconSize", "iconSize") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "buffGroupOffsetX", "buffOffsetX") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "buffGroupOffsetY", "buffOffsetY") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetX", "debuffOffsetX") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetY", "debuffOffsetY") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "buffGroupOffsetX", "offsetX") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "buffGroupOffsetY", "offsetY") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetX", "offsetX") or changed
    changed = MSUF_ProfileIO_CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetY", "offsetY") or changed
    changed = MSUF_ProfileIO_CopyAuraGrowthAlias(tbl, "buffGrowth", "buffGrowthX", "buffGrowthY") or changed
    changed = MSUF_ProfileIO_CopyAuraGrowthAlias(tbl, "debuffGrowth", "debuffGrowthX", "debuffGrowthY") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(tbl, "buffGrowthY", "buffRowWrap") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(tbl, "debuffGrowthY", "debuffRowWrap") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(tbl, "buffGrowthY", "rowWrap") or changed
    changed = MSUF_ProfileIO_CopyIfMissing(tbl, "debuffGrowthY", "rowWrap") or changed
    for key, limits in pairs(MSUF_PROFILEIO_AURA_NUMERIC_KEYS) do
        changed = MSUF_ProfileIO_NormalizeNumberField(tbl, key, limits[1], limits[2]) or changed
    end
    for i = 1, #MSUF_PROFILEIO_AURA_STRING_KEYS do
        changed = MSUF_ProfileIO_UpperStringField(tbl, MSUF_PROFILEIO_AURA_STRING_KEYS[i]) or changed
    end
    return changed
end

MSUF.ProfileIONormalizeLegacy55VisualCompatibility = function(profile, legacyProfile, context)
    if type(profile) ~= "table" then return false end

    local translatedAuras = type(profile.auras3) == "table"
        and profile.auras3._msufAuras3TranslatedFromLegacyAuras2 == true
    local storedLegacyVisualProfile = profile._msufLegacy55FrameOutlineBackground_v1 == true
    if legacyProfile ~= true and translatedAuras ~= true and storedLegacyVisualProfile ~= true then return false end

    local changed = false
    local general = type(profile.general) == "table" and profile.general or nil
    local legacyRangeFadePortrait = general and general.rangeFadePortrait
    local units = {
        "player", "target", "focus", "targettarget", "focustarget", "pet", "boss",
        "boss1", "boss2", "boss3", "boss4", "boss5",
    }
    local powerTextDefaults60 = {
        player = true, target = true, focus = false,
        targettarget = false, focustarget = false, pet = true,
        boss = true, boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
    }
    local repairPreviouslySeededPowerText = profile._msufLegacy55PowerTextVisibility_v1 ~= true
        and (translatedAuras == true or storedLegacyVisualProfile == true)
    for i = 1, #units do
        local unit = units[i]
        local conf = profile[unit]
        if type(conf) == "table" and legacyRangeFadePortrait ~= nil and conf.rangeFadeLayerMode == nil then
            -- 5.57 could keep the portrait opaque while its other range-faded
            -- frame layers dimmed. 6.0 has two supported ownership modes; map
            -- the old toggle to the closest loss-minimizing equivalent instead
            -- of silently falling back to whole-frame fade.
            conf.rangeFadeLayerMode = legacyRangeFadePortrait == true and "frame" or "health"
            changed = true
        end
        if type(conf) == "table" and conf.showPower ~= nil then
            local legacyShown = conf.showPower ~= false
            local currentShown = conf.showPowerText ~= false
            if conf.showPowerText == nil
                or (repairPreviouslySeededPowerText
                    and currentShown == powerTextDefaults60[unit]
                    and currentShown ~= legacyShown) then
                -- Native 5.5 owned Power Text visibility through showPower.
                -- 6.0 split that state into showPowerText, then its nil-only
                -- defaults could seed the opposite value before compilation.
                conf.showPowerText = legacyShown
                changed = true
            end
        end
        if type(conf) == "table" and conf.detachedPowerBarAnchorMode == nil
            and (conf.powerBarDetached ~= nil
                or conf.detachedPowerBarOffsetX ~= nil or conf.detachedPowerBarOffsetY ~= nil
                or conf.detachedPowerBarWidth ~= nil or conf.detachedPowerBarHeight ~= nil) then
            -- 5.5 interpreted detached offsets from the unit frame's left
            -- edge. 6.0 defaults to a centered TOP/BOTTOM relationship.
            conf.detachedPowerBarAnchorMode = "LEGACY_TOPLEFT"
            changed = true
        end
    end
    if profile._msufLegacy55PowerTextVisibility_v1 ~= true then
        profile._msufLegacy55PowerTextVisibility_v1 = true
        changed = true
    end
    changed = MSUF.ProfileIOMaterializeLegacy55UnitTextSlots(profile) or changed
    changed = MSUF.ProfileIOMaterializeLegacy55GroupTextGeometry(profile) or changed
    changed = MSUF.ProfileIOMaterializeLegacy55GroupNameAnchorRoot(profile) or changed

    local bars = profile.bars
    if type(bars) ~= "table" then
        bars = {}
        profile.bars = bars
        changed = true
    end
    if bars.barOutlineStrata ~= "BACKGROUND" then
        bars.barOutlineStrata = "BACKGROUND"
        changed = true
    end
    -- Scope overrides win over bars.barOutlineStrata when Highlight Override
    -- is active. Pin existing legacy scopes too, so no migrated page can fall
    -- back to AUTO after the global value has been corrected.
    local outlineScopes = {
        "player", "target", "focus", "targettarget", "focustarget", "pet", "boss",
        "boss1", "boss2", "boss3", "boss4", "boss5",
        "gf_party", "gf_raid", "gf_mythicraid",
    }
    for i = 1, #outlineScopes do
        local conf = profile[outlineScopes[i]]
        if type(conf) == "table" and conf.barOutlineStrata ~= "BACKGROUND" then
            conf.barOutlineStrata = "BACKGROUND"
            changed = true
        end
    end
    if profile._msufLegacy55FrameOutlineBackground_v1 ~= true then
        profile._msufLegacy55FrameOutlineBackground_v1 = true
        changed = true
    end
    return changed
end

local MSUF_PROFILEIO_AURA_RESETTERS = {}
do
local MSUF_PROFILEIO_UNIT_AURA_RESET_LANES = {
    buff = {
        sizeKey = "buffGroupIconSize",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        anchorKey = "buffAnchor",
        spacingKey = "buffSpacing",
        perRowKey = "buffPerRow",
        maxKey = "maxBuffs",
        growthKey = "buffGrowthX",
        wrapKey = "buffGrowthY",
        legacyGrowthKey = "buffGrowth",
        defaultX = 0,
        defaultY = 36,
        defaultAnchor = "BOTTOMRIGHT",
    },
    debuff = {
        sizeKey = "debuffGroupIconSize",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        anchorKey = "debuffAnchor",
        spacingKey = "debuffSpacing",
        perRowKey = "debuffPerRow",
        maxKey = "maxDebuffs",
        growthKey = "debuffGrowthX",
        wrapKey = "debuffGrowthY",
        legacyGrowthKey = "debuffGrowth",
        defaultX = 0,
        defaultY = 6,
        defaultAnchor = "TOPLEFT",
    },
}
local MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER = { "buff", "debuff" }
local MSUF_PROFILEIO_UNIT_AURA_RESET_ANCHORS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local function MSUF_ProfileIO_AuraResetNumber(value, fallback, minValue, maxValue)
    value = tonumber(value)
    if value == nil or value ~= value then value = tonumber(fallback) or 0 end
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function MSUF_ProfileIO_AuraResetRound(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function MSUF_ProfileIO_AuraResetReadRaw(primary, secondary, key)
    local value = type(primary) == "table" and primary[key] or nil
    if value ~= nil then return value end
    return type(secondary) == "table" and secondary[key] or nil
end

local function MSUF_ProfileIO_AuraResetGrowthParts(growth, rowWrap)
    growth = tostring(growth or "RIGHT")
    rowWrap = tostring(rowWrap or "DOWN")
    if growth == "LEFTUP" then return -1, 1, false end
    if growth == "LEFTDOWN" then return -1, -1, false end
    if growth == "RIGHTUP" then return 1, 1, false end
    if growth == "RIGHTDOWN" then return 1, -1, false end
    if growth == "LEFT" then return -1, rowWrap == "UP" and 1 or -1, false end
    if growth == "UP" then return 1, 1, true end
    if growth == "DOWN" then return 1, -1, true end
    return 1, rowWrap == "UP" and 1 or -1, false
end

local function MSUF_ProfileIO_AuraResetGridShape(maxCount, perRow, verticalGrowth)
    maxCount = MSUF_ProfileIO_AuraResetRound(maxCount)
    perRow = math.max(MSUF_ProfileIO_AuraResetRound(perRow), 1)
    if maxCount <= 0 then return 1, 1 end
    if verticalGrowth then return 1, maxCount end
    return math.min(perRow, maxCount), math.floor((maxCount + perRow - 1) / perRow)
end

local function MSUF_ProfileIO_AuraResetAnchor(value, fallback)
    if type(value) == "string" and MSUF_PROFILEIO_UNIT_AURA_RESET_ANCHORS[value] then
        return value
    end
    return fallback
end

--- Reproduce the current Auras3 compiler's effective layout on the profile
--- translation cold path. No runtime module is loaded or called here: this is
--- only used once to preserve the visible first icon while the rest of the old
--- Aura tree is discarded.
local function MSUF_ProfileIO_AuraResetA3LaneMetrics(auras, unit, kind, sizeOverride)
    local spec = MSUF_PROFILEIO_UNIT_AURA_RESET_LANES[kind]
    local rootShared = type(auras) == "table" and type(auras.shared) == "table" and auras.shared or {}
    local perUnit = type(auras) == "table" and type(auras.perUnit) == "table" and auras.perUnit or nil
    local unitCfg = perUnit and type(perUnit[unit]) == "table" and perUnit[unit] or nil
    local layout = unitCfg and unitCfg.overrideLayout == true and type(unitCfg.layout) == "table"
        and unitCfg.layout or nil
    local layoutShared = unitCfg and unitCfg.overrideSharedLayout == true
        and type(unitCfg.layoutShared) == "table" and unitCfg.layoutShared or nil

    local function LayoutRaw(key)
        return MSUF_ProfileIO_AuraResetReadRaw(layout, rootShared, key)
    end
    local function SharedRaw(key)
        return MSUF_ProfileIO_AuraResetReadRaw(layoutShared, rootShared, key)
    end

    local sizeRaw = LayoutRaw(spec.sizeKey)
    if sizeRaw == nil then sizeRaw = LayoutRaw("iconSize") end
    local size = MSUF_ProfileIO_AuraResetNumber(
        sizeOverride ~= nil and sizeOverride or sizeRaw, 26, 1, 128)
    local genericSpacing = MSUF_ProfileIO_AuraResetNumber(LayoutRaw("spacing"), 2, 0, 64)
    local spacing = MSUF_ProfileIO_AuraResetNumber(LayoutRaw(spec.spacingKey), genericSpacing, 0, 64)
    local perRowFallback = SharedRaw("perRow")
    if perRowFallback == nil then perRowFallback = 12 end
    local perRow = MSUF_ProfileIO_AuraResetNumber(SharedRaw(spec.perRowKey), perRowFallback, 1, 40)
    local maxCount = MSUF_ProfileIO_AuraResetNumber(SharedRaw(spec.maxKey), 12, 0, 80)
    local growth = SharedRaw(spec.growthKey)
    if growth == nil then growth = SharedRaw("growth") end
    if growth == nil then growth = "RIGHT" end
    local rowWrap = SharedRaw(spec.wrapKey)
    if rowWrap == nil then rowWrap = SharedRaw("rowWrap") end
    if rowWrap == nil then rowWrap = "DOWN" end
    local xSign, ySign, verticalGrowth = MSUF_ProfileIO_AuraResetGrowthParts(growth, rowWrap)
    local cols, rows = MSUF_ProfileIO_AuraResetGridShape(maxCount, perRow, verticalGrowth)

    local styleActive = false
    if unitCfg then
        if unitCfg.overrideStyle ~= nil then
            styleActive = unitCfg.overrideStyle == true
        elseif layout and layout.stylePadding ~= nil then
            -- stylePadding itself is a Style-layout key, so its presence is
            -- sufficient to activate legacy nil-gate style ownership.
            styleActive = true
        end
    end
    local paddingRaw = styleActive and layout and layout.stylePadding or rootShared.stylePadding
    local padding = MSUF_ProfileIO_AuraResetRound(
        MSUF_ProfileIO_AuraResetNumber(paddingRaw, 0, 0, 16))
    local width = math.max(1, cols * size + math.max(cols - 1, 0) * spacing + 2 * padding)
    local height = math.max(1, rows * size + math.max(rows - 1, 0) * spacing + 2 * padding)
    local x = MSUF_ProfileIO_AuraResetRound(
        MSUF_ProfileIO_AuraResetNumber(LayoutRaw(spec.xKey), spec.defaultX, -4096, 4096))
    local y = MSUF_ProfileIO_AuraResetRound(
        MSUF_ProfileIO_AuraResetNumber(LayoutRaw(spec.yKey), spec.defaultY, -4096, 4096))
    local anchor = MSUF_ProfileIO_AuraResetAnchor(LayoutRaw(spec.anchorKey), spec.defaultAnchor)
    return {
        size = size,
        spacing = spacing,
        width = width,
        height = height,
        padding = padding,
        xSign = xSign,
        ySign = ySign,
        x = x,
        y = y,
        anchor = anchor,
    }
end

local function MSUF_ProfileIO_AuraResetFirstOffset(metrics, anchor)
    local anchorParts = MSUF_PROFILEIO_UNIT_AURA_RESET_ANCHORS[anchor]
        or MSUF_PROFILEIO_UNIT_AURA_RESET_ANCHORS.CENTER
    local ax, ay = anchorParts[1], anchorParts[2]
    local ix = metrics.xSign < 0 and 1 or 0
    local iy = metrics.ySign > 0 and 0 or 1
    local dx = (ix - ax) * metrics.width + metrics.padding * metrics.xSign - ix * metrics.size
    local dy = (iy - ay) * metrics.height + metrics.padding * metrics.ySign - iy * metrics.size
    return dx, dy
end

local function MSUF_ProfileIO_AuraResetSnapshotA3(auras)
    local snapshots = {}
    for i = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS do
        local unit = MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS[i]
        local unitSnapshot = {}
        snapshots[unit] = unitSnapshot
        for j = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER do
            local kind = MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER[j]
            local metrics = MSUF_ProfileIO_AuraResetA3LaneMetrics(auras, unit, kind)
            local dx, dy = MSUF_ProfileIO_AuraResetFirstOffset(metrics, metrics.anchor)
            unitSnapshot[kind] = {
                size = metrics.size,
                anchor = metrics.anchor,
                firstX = metrics.x + dx,
                firstY = metrics.y + dy,
            }
        end
    end
    return snapshots
end

local MSUF_PROFILEIO_A2_VALID_GROWTH = { RIGHT = true, LEFT = true, UP = true, DOWN = true }
local function MSUF_ProfileIO_AuraResetSnapshotA2(auras)
    local snapshots = {}
    local shared = type(auras) == "table" and type(auras.shared) == "table" and auras.shared or {}
    local perUnit = type(auras) == "table" and type(auras.perUnit) == "table" and auras.perUnit or nil
    for i = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS do
        local unit = MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS[i]
        local unitCfg = perUnit and type(perUnit[unit]) == "table" and perUnit[unit] or nil
        local layout = unitCfg and unitCfg.overrideLayout == true and type(unitCfg.layout) == "table"
            and unitCfg.layout or nil
        local layoutShared = unitCfg and unitCfg.overrideSharedLayout == true
            and type(unitCfg.layoutShared) == "table" and unitCfg.layoutShared or nil
        local baseX = type(shared.offsetX) == "number" and shared.offsetX or 0
        local baseY = type(shared.offsetY) == "number" and shared.offsetY or 6
        if layout and type(layout.offsetX) == "number" then baseX = layout.offsetX end
        if layout and type(layout.offsetY) == "number" then baseY = layout.offsetY end

        local function GroupOffset(key)
            local value = layout and layout[key] ~= nil and layout[key] or shared[key]
            return MSUF_ProfileIO_AuraResetRound(
                MSUF_ProfileIO_AuraResetNumber(value, 0, -2000, 2000))
        end
        local function ValidGrowth(tbl, key)
            local value = type(tbl) == "table" and tbl[key] or nil
            return MSUF_PROFILEIO_A2_VALID_GROWTH[value] and value or nil
        end
        local sharedGenericGrowth = ValidGrowth(shared, "growth") or "RIGHT"
        local localGenericGrowth = ValidGrowth(layoutShared, "growth")
        local unitSnapshot = {}
        snapshots[unit] = unitSnapshot
        for j = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER do
            local kind = MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER[j]
            local spec = MSUF_PROFILEIO_UNIT_AURA_RESET_LANES[kind]
            local size = type(shared.iconSize) == "number" and shared.iconSize or 26
            if layout and type(layout.iconSize) == "number" and layout.iconSize > 1 then
                size = layout.iconSize
            end
            if type(shared[spec.sizeKey]) == "number" and shared[spec.sizeKey] > 1 then
                size = shared[spec.sizeKey]
            end
            if layout and type(layout[spec.sizeKey]) == "number" and layout[spec.sizeKey] > 1 then
                size = layout[spec.sizeKey]
            end
            size = MSUF_ProfileIO_AuraResetNumber(size, 26, 1, 128)
            local growth = ValidGrowth(layoutShared, spec.legacyGrowthKey)
                or ValidGrowth(shared, spec.legacyGrowthKey)
                or localGenericGrowth
                or sharedGenericGrowth
            local rx = baseX + GroupOffset(spec.xKey)
            local ry = baseY + GroupOffset(spec.yKey)
            local ix = growth == "LEFT" and 1 or 0
            local iy = growth == "DOWN" and 1 or 0
            unitSnapshot[kind] = {
                size = size,
                anchor = "TOPLEFT",
                firstX = rx + ix * (1 - size),
                firstY = ry + iy * (1 - size),
            }
        end
    end
    return snapshots
end

local function MSUF_ProfileIO_AuraResetRebaseLane(cleanAuras, unit, kind, snapshot)
    local target = MSUF_ProfileIO_AuraResetA3LaneMetrics(cleanAuras, unit, kind, snapshot.size)
    local dx, dy = MSUF_ProfileIO_AuraResetFirstOffset(target, snapshot.anchor)
    return {
        size = snapshot.size,
        anchor = snapshot.anchor,
        x = math.max(-4096, math.min(4096,
            MSUF_ProfileIO_AuraResetRound(snapshot.firstX - dx))),
        y = math.max(-4096, math.min(4096,
            MSUF_ProfileIO_AuraResetRound(snapshot.firstY - dy))),
    }
end

local function MSUF_ProfileIO_AuraResetWriteLane(layout, kind, geometry)
    local spec = MSUF_PROFILEIO_UNIT_AURA_RESET_LANES[kind]
    layout[spec.sizeKey] = geometry.size
    layout[spec.anchorKey] = geometry.anchor
    layout[spec.xKey] = geometry.x
    layout[spec.yKey] = geometry.y
end

local function MSUF_ProfileIO_AuraResetSnapshotMatches(cleanAuras, unit, kind, desired)
    local metrics = MSUF_ProfileIO_AuraResetA3LaneMetrics(cleanAuras, unit, kind)
    local dx, dy = MSUF_ProfileIO_AuraResetFirstOffset(metrics, metrics.anchor)
    return math.abs(metrics.size - desired.size) < 0.0001
        and metrics.anchor == desired.anchor
        and math.abs((metrics.x + dx) - desired.firstX) <= 0.51
        and math.abs((metrics.y + dy) - desired.firstY) <= 0.51
end

local function MSUF_ProfileIO_ResetUnitAuras(profile)
    if type(profile) ~= "table" then return false end
    local sourceA3 = type(profile.auras3) == "table" and profile.auras3 or nil
    if sourceA3 and next(sourceA3) == nil and type(profile.auras2) == "table" then
        -- A few hybrid beta/import payloads carried an empty Auras3 placeholder
        -- beside the still-live Aura2 tree. Match the old EnsureDB fallback so
        -- its position/size source is not discarded merely by that placeholder.
        sourceA3 = nil
    end
    if MSUF_ProfileIO_HasCanonicalUnitAuraBaseline(sourceA3) then
        local changed = false
        if profile.auras ~= nil then profile.auras, changed = nil, true end
        if profile.auras2 ~= nil then profile.auras2, changed = nil, true end
        return changed
    end
    local sourceA2 = not sourceA3 and type(profile.auras2) == "table" and profile.auras2 or nil
    if not sourceA3 and not sourceA2 and profile.auras == nil then return false end

    local snapshots = sourceA3 and MSUF_ProfileIO_AuraResetSnapshotA3(sourceA3)
        or sourceA2 and MSUF_ProfileIO_AuraResetSnapshotA2(sourceA2) or nil
    local createCanonical = (type(MSUF) == "table" and MSUF.MSUF_CreateCanonicalUnitAuras)
        or _G.MSUF_CreateCanonicalUnitAuras
    local ok, cleanAuras = MSUF_ProfileIO_RunProtected(
        "canonical Unit Aura reset", createCanonical)
    if not ok or type(cleanAuras) ~= "table" then
        -- Never destroy the old data if the Defaults-owned factory is missing.
        -- The absent revision keeps this profile eligible for a retry.
        return false
    end
    cleanAuras[MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY] = MSUF_PROFILEIO_UNIT_AURA_RESET_BASELINE_REVISION

    if snapshots then
        local shared = type(cleanAuras.shared) == "table" and cleanAuras.shared or {}
        cleanAuras.shared = shared
        local playerSnapshot = snapshots.player
        if playerSnapshot then
            for j = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER do
                local kind = MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER[j]
                MSUF_ProfileIO_AuraResetWriteLane(shared, kind,
                    MSUF_ProfileIO_AuraResetRebaseLane(cleanAuras, "player", kind, playerSnapshot[kind]))
            end
        end

        local perUnit = type(cleanAuras.perUnit) == "table" and cleanAuras.perUnit or {}
        cleanAuras.perUnit = perUnit
        for i = 2, #MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS do
            local unit = MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS[i]
            local desired = snapshots[unit]
            if desired then
                local unitCfg = type(perUnit[unit]) == "table" and perUnit[unit] or {}
                perUnit[unit] = unitCfg
                local needsLocal = unitCfg.overrideLayout == true
                for j = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER do
                    local kind = MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER[j]
                    needsLocal = needsLocal
                        or not MSUF_ProfileIO_AuraResetSnapshotMatches(cleanAuras, unit, kind, desired[kind])
                end
                if needsLocal then
                    if unitCfg.overrideLayout ~= true then unitCfg.layout = {} end
                    local layout = type(unitCfg.layout) == "table" and unitCfg.layout or {}
                    unitCfg.layout = layout
                    unitCfg.overrideLayout = true
                    for j = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER do
                        local kind = MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER[j]
                        MSUF_ProfileIO_AuraResetWriteLane(layout, kind,
                            MSUF_ProfileIO_AuraResetRebaseLane(cleanAuras, unit, kind, desired[kind]))
                    end
                end
            end
        end
    end

    profile.auras3 = cleanAuras
    profile.auras = nil
    profile.auras2 = nil
    return true
end

local MSUF_PROFILEIO_GROUP_AURA_RESET_LANES = {
    buff = {
        groupKey = "buff", defaultSizeParty = 22, defaultSizeRaid = 16,
        defaultMax = 4, defaultPerRow = 4, defaultGrowth = "LEFTUP", defaultAnchor = "BOTTOMRIGHT",
    },
    debuff = {
        groupKey = "debuff", defaultSizeParty = 20, defaultSizeRaid = 16,
        defaultMax = 4, defaultPerRow = 3, defaultGrowth = "RIGHTDOWN", defaultAnchor = "TOPLEFT",
    },
    externals = {
        groupKey = "externals", defaultSizeParty = 28, defaultSizeRaid = 22,
        defaultMax = 2, defaultPerRow = 3, defaultGrowth = "RIGHTDOWN", defaultAnchor = "CENTER",
    },
}
local MSUF_PROFILEIO_GROUP_AURA_RESET_LANE_ORDER = { "buff", "debuff", "externals" }
local MSUF_PROFILEIO_GROUP_AURA_RETIRED_FLAT_KEYS = {
    "aurasEnabled", "auraMaxIcons", "auraIconSize", "auraAnchor",
    "auraGrowthX", "auraGrowthY", "auraSpacing", "auraPerRow",
    "privateAurasEnabled", "privateAuraMax", "privateAuraSize",
    "privateAuraAnchor", "privateAuraX", "privateAuraY", "privateAuraCountdown",
}

local function MSUF_ProfileIO_ClearRetiredGroupAuraFields(conf)
    local changed = false
    for i = 1, #MSUF_PROFILEIO_GROUP_AURA_RETIRED_FLAT_KEYS do
        local key = MSUF_PROFILEIO_GROUP_AURA_RETIRED_FLAT_KEYS[i]
        if conf[key] ~= nil then conf[key], changed = nil, true end
    end
    if conf._auraMigV2 ~= nil then conf._auraMigV2, changed = nil, true end
    return changed
end

local function MSUF_ProfileIO_AuraResetGroupRound(value)
    value = tonumber(value) or 0
    if value >= 0 then return math.floor(value + 0.5) end
    return -math.floor((-value) + 0.5)
end

--- Dynamic Group Aura scaling never persisted the roster count that selected
--- its 1.00/0.85/0.70 factor. Capture the live count once on this cold
--- translation path, using the same API and thresholds as both 5.57 and the
--- current Group compiler. Missing/invalid API data deliberately resolves to
--- zero: both runtimes select 1.00 for every count <= 15.
local function MSUF_ProfileIO_AuraResetCurrentGroupCount()
    local getter = _G.GetNumGroupMembers
    if type(getter) ~= "function" then return 0 end
    local ok, value = pcall(getter)
    if not ok then return 0 end
    value = tonumber(value)
    if value == nil or value ~= value then return 0 end
    value = math.floor(value + 0.5)
    if value < 0 then return 0 end
    if value > 40 then return 40 end
    return value
end

local function MSUF_ProfileIO_AuraResetGroupDynamicScale(root, groupCount)
    if not (type(root) == "table" and root.dynamicScale == true) then return 1 end
    groupCount = MSUF_ProfileIO_AuraResetNumber(groupCount, 0, 0, 40)
    if groupCount <= 15 then return 1 end
    if groupCount <= 25 then return 0.85 end
    return 0.70
end

--- Matches Group Config's SplitAuraGrowth exactly. Values such as a bare
--- LEFT were never a distinct Group mode and therefore rendered RIGHT/DOWN.
local function MSUF_ProfileIO_AuraResetGroupGrowth(value, fallback)
    value = value or fallback or "RIGHTDOWN"
    if value == "LEFTUP" then return "LEFTUP" end
    if value == "LEFTDOWN" then return "LEFTDOWN" end
    if value == "RIGHTUP" then return "RIGHTUP" end
    if value == "UP" then return "UP" end
    if value == "DOWN" then return "DOWN" end
    return "RIGHTDOWN"
end

local function MSUF_ProfileIO_AuraResetGroupLaneMetrics(
    conf, laneName, sizeOverride, groupCount, legacyGeometry)
    local spec = MSUF_PROFILEIO_GROUP_AURA_RESET_LANES[laneName]
    local root = type(conf) == "table" and type(conf.auras) == "table" and conf.auras or {}
    local group = type(root[spec.groupKey]) == "table" and root[spec.groupKey] or {}
    local isRaid = conf and conf._msufAuraResetScope ~= "gf_party"
    local defaultSize = isRaid and spec.defaultSizeRaid or spec.defaultSizeParty
    local dynamicScale = MSUF_ProfileIO_AuraResetGroupDynamicScale(root, groupCount)
    -- 5.57's custom renderer scaled icon size only; its spacing and container
    -- offsets used frameScale alone. The current compiler applies dynamicScale
    -- to size, spacing, x, and y. Preserve each source model exactly.
    local layoutScale = legacyGeometry == true and 1 or dynamicScale
    local iconScale = MSUF_ProfileIO_AuraResetNumber(group.iconScale, 100, 20, 300) / 100
    local rawSize = sizeOverride ~= nil and sizeOverride
        or (MSUF_ProfileIO_AuraResetNumber(group.size, defaultSize) * iconScale)
    rawSize = rawSize * dynamicScale
    local size = MSUF_ProfileIO_AuraResetNumber(
        MSUF_ProfileIO_AuraResetGroupRound(rawSize), defaultSize,
        legacyGeometry == true and 8 or 1, 256)
    local spacing = MSUF_ProfileIO_AuraResetNumber(group.spacing, 1, 0, 64)
    spacing = MSUF_ProfileIO_AuraResetNumber(
        MSUF_ProfileIO_AuraResetGroupRound(spacing * layoutScale), 1, 0, 64)
    local maxCount = MSUF_ProfileIO_AuraResetNumber(group.max,
        laneName == "externals" and 2 or MSUF_ProfileIO_AuraResetNumber(conf and conf.auraMaxIcons, spec.defaultMax),
        0, 80)
    local perRow = MSUF_ProfileIO_AuraResetNumber(group.perRow, spec.defaultPerRow, 1, 40)
    local growth = MSUF_ProfileIO_AuraResetGroupGrowth(group.growth, spec.defaultGrowth)
    local xSign, ySign, verticalGrowth = MSUF_ProfileIO_AuraResetGrowthParts(growth, "DOWN")
    local cols, rows = MSUF_ProfileIO_AuraResetGridShape(maxCount, perRow, verticalGrowth)
    local anchor = MSUF_ProfileIO_AuraResetAnchor(group.anchor, spec.defaultAnchor)
    return {
        size = size,
        spacing = spacing,
        width = math.max(1, cols * size + math.max(cols - 1, 0) * spacing),
        height = math.max(1, rows * size + math.max(rows - 1, 0) * spacing),
        padding = 0,
        xSign = xSign,
        ySign = ySign,
        x = MSUF_ProfileIO_AuraResetGroupRound((tonumber(group.x) or 0) * layoutScale),
        y = MSUF_ProfileIO_AuraResetGroupRound((tonumber(group.y) or 0) * layoutScale),
        anchor = anchor,
    }
end

local function MSUF_ProfileIO_AuraResetSnapshotGroup(conf, scope, legacyProfile, groupCount)
    if type(conf) ~= "table" then return nil end
    if type(conf.auras) ~= "table" then
        if legacyProfile ~= true then return nil end
        -- Flat 5.x Group settings were Blizzard-owned by default. Blizzard did
        -- not persist a movable lane position, so preserve only the effective
        -- visible sizes and let the new native factory own every position.
        return {
            -- Aura2's flat auraIconSize fed only dormant custom tables. The
            -- default BLIZZARD owner rendered Buffs/Debuffs at its own 20 px.
            buff = { size = 20, sizeOnly = true },
            debuff = { size = 20, sizeOnly = true },
            externals = {
                size = conf.aurasEnabled ~= nil and 28 or (scope == "gf_party" and 28 or 24),
                sizeOnly = true,
            },
        }
    end
    local proxy = { auras = conf.auras, auraMaxIcons = conf.auraMaxIcons, _msufAuraResetScope = scope }
    local snapshot = {}
    local legacyRenderer = tostring(conf.auras.renderer or "BLIZZARD"):upper()
    local legacyCustom = legacyProfile == true
        and legacyRenderer ~= "BLIZZARD"
        and legacyRenderer ~= "MIXED"
        and legacyRenderer ~= "BOTH"
        and legacyRenderer ~= "CUSTOM_BLIZZARD"
        and legacyRenderer ~= "CUSTOM+BLIZZARD"
    local legacyTypes = type(conf.auras.blizzardTypes) == "table" and conf.auras.blizzardTypes or nil
    local legacyBlizzardSize = MSUF_ProfileIO_AuraResetNumber(conf.auras.blizzardIconSize,
        20, legacyProfile == true and 8 or 1, 256)
    local dynamicScale = MSUF_ProfileIO_AuraResetGroupDynamicScale(conf.auras, groupCount)
    for i = 1, #MSUF_PROFILEIO_GROUP_AURA_RESET_LANE_ORDER do
        local laneName = MSUF_PROFILEIO_GROUP_AURA_RESET_LANE_ORDER[i]
        local legacyTypeKey = laneName == "buff" and "buffs"
            or laneName == "debuff" and "debuffs" or "externals"
        local laneWasCustom = legacyProfile ~= true or legacyCustom
            or (legacyTypes and legacyTypes[legacyTypeKey] ~= nil
                and legacyTypes[legacyTypeKey] ~= true)
        if not laneWasCustom then
            local nativeSize = legacyBlizzardSize
            if laneName == "externals" then
                local group = type(conf.auras.externals) == "table" and conf.auras.externals or nil
                nativeSize = MSUF_ProfileIO_AuraResetNumber(group and group.size, 28, 8, 256)
            end
            -- 5.57 passed the same dynamic factor into its Blizzard-owned
            -- container sizing; frameScale remains outside the Aura tree and
            -- therefore survives this profile-only cut independently.
            nativeSize = MSUF_ProfileIO_AuraResetNumber(
                MSUF_ProfileIO_AuraResetGroupRound(nativeSize * dynamicScale),
                nativeSize, legacyProfile == true and 8 or 1, 256)
            snapshot[laneName] = { size = nativeSize, sizeOnly = true }
        else
            local legacySize
            local legacyGroup
            if legacyProfile == true then
                local spec = MSUF_PROFILEIO_GROUP_AURA_RESET_LANES[laneName]
                legacyGroup = type(conf.auras[spec.groupKey]) == "table" and conf.auras[spec.groupKey] or nil
                local legacyFallback = laneName == "buff" and 22
                    or laneName == "debuff" and 20 or 28
                legacySize = legacyGroup and legacyGroup.size
                    or legacyFallback
                legacySize = MSUF_ProfileIO_AuraResetNumber(legacySize,
                    legacyFallback, 8, 256)
            end
            local metrics = MSUF_ProfileIO_AuraResetGroupLaneMetrics(
                proxy, laneName, legacySize, groupCount, legacyProfile)
            local dx, dy
            if legacyProfile == true then
                local growth = tostring(legacyGroup and legacyGroup.growth or ""):upper()
                if growth == "CENTER_H" or growth == "CENTER_V" then
                    metrics.anchor = "CENTER"
                end
                local parts = MSUF_PROFILEIO_UNIT_AURA_RESET_ANCHORS[metrics.anchor]
                    or MSUF_PROFILEIO_UNIT_AURA_RESET_ANCHORS.CENTER
                dx, dy = -parts[1] * metrics.size, -parts[2] * metrics.size
            else
                dx, dy = MSUF_ProfileIO_AuraResetFirstOffset(metrics, metrics.anchor)
            end
            snapshot[laneName] = {
                size = metrics.size,
                anchor = metrics.anchor,
                firstX = metrics.x + dx,
                firstY = metrics.y + dy,
            }
        end
    end
    return snapshot
end

local function MSUF_ProfileIO_AuraResetRebaseGroupLane(state, scope, laneName, snapshot)
    local proxy = { auras = state.auras, _msufAuraResetScope = scope }
    local target = MSUF_ProfileIO_AuraResetGroupLaneMetrics(proxy, laneName, snapshot.size)
    local dx, dy = MSUF_ProfileIO_AuraResetFirstOffset(target, snapshot.anchor)
    return {
        size = snapshot.size,
        anchor = snapshot.anchor,
        x = math.max(-4096, math.min(4096,
            MSUF_ProfileIO_AuraResetGroupRound(snapshot.firstX - dx))),
        y = math.max(-4096, math.min(4096,
            MSUF_ProfileIO_AuraResetGroupRound(snapshot.firstY - dy))),
    }
end

local function MSUF_ProfileIO_ResetGroupAuras(profile, legacyProfile, groupCount)
    if type(profile) ~= "table" then return false end
    local createCanonical = (type(MSUF) == "table" and MSUF.MSUF_CreateCanonicalGroupAuraState)
        or _G.MSUF_CreateCanonicalGroupAuraState
    local canonical
    local changed = false
    for i = 1, #MSUF_PROFILEIO_GROUP_AURA_SCOPES do
        local scope = MSUF_PROFILEIO_GROUP_AURA_SCOPES[i]
        local conf = profile[scope]
        if type(conf) == "table" then
            local sourceAuras = type(conf.auras) == "table" and conf.auras or nil
            local hasAuraPayload = MSUF.ProfileIOGroupHasAuraPayload(conf)
            if hasAuraPayload and (not sourceAuras
                or tonumber(sourceAuras[MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY]) ~= MSUF_PROFILEIO_GROUP_AURA_MODEL_REVISION) then
                if groupCount == nil and sourceAuras and sourceAuras.dynamicScale == true then
                    groupCount = MSUF_ProfileIO_AuraResetCurrentGroupCount()
                end
                local snapshot = MSUF_ProfileIO_AuraResetSnapshotGroup(
                    conf, scope, legacyProfile, groupCount)
                if canonical == nil then
                    local ok, value = MSUF_ProfileIO_RunProtected(
                        "canonical Group Aura reset", createCanonical)
                    if ok and type(value) == "table" then canonical = value else canonical = false end
                end
                local state = canonical and canonical[scope]
                if type(state) == "table" and type(state.auras) == "table" then
                    if snapshot then
                        for j = 1, #MSUF_PROFILEIO_GROUP_AURA_RESET_LANE_ORDER do
                            local laneName = MSUF_PROFILEIO_GROUP_AURA_RESET_LANE_ORDER[j]
                            local laneSnapshot = snapshot[laneName]
                            if laneSnapshot then
                                local group = type(state.auras[laneName]) == "table" and state.auras[laneName] or {}
                                state.auras[laneName] = group
                                if laneSnapshot.sizeOnly == true then
                                    group.size = laneSnapshot.size
                                else
                                    local geometry = MSUF_ProfileIO_AuraResetRebaseGroupLane(
                                        state, scope, laneName, laneSnapshot)
                                    group.size = geometry.size
                                    group.anchor = geometry.anchor
                                    group.x = geometry.x
                                    group.y = geometry.y
                                end
                            end
                        end
                    end
                    conf.auras = MSUF_DeepCopy(state.auras)
                    conf.privateAuras = type(state.privateAuras) == "table"
                        and MSUF_DeepCopy(state.privateAuras) or nil
                    conf.spellIndicators = type(state.spellIndicators) == "table"
                        and MSUF_DeepCopy(state.spellIndicators) or nil
                    MSUF_ProfileIO_ClearRetiredGroupAuraFields(conf)
                    changed = true
                end
            elseif sourceAuras
                and tonumber(sourceAuras[MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY]) == MSUF_PROFILEIO_GROUP_AURA_MODEL_REVISION then
                changed = MSUF_ProfileIO_ClearRetiredGroupAuraFields(conf) or changed
            end
        end
    end
    return changed
end

MSUF_PROFILEIO_AURA_RESETTERS.ResetUnit = MSUF_ProfileIO_ResetUnitAuras
MSUF_PROFILEIO_AURA_RESETTERS.ResetGroup = MSUF_ProfileIO_ResetGroupAuras
end

local function MSUF_ProfileIO_NormalizeLegacyAuras(profile, legacyProfile, forceScopeRepair)
    if type(profile) ~= "table" then return false end
    -- A 6.0 beta profile can still carry a translated-from-5.x marker, which
    -- makes the broad compatibility classifier return `legacyProfile=true`.
    -- Its Group Aura geometry was nevertheless rendered by the 6.0 host-grid
    -- compiler. Only a genuinely pre-600 declared profile uses the 5.x direct
    -- 1x1-container formula.
    local hadAuras3 = type(profile.auras3) == "table" and next(profile.auras3) ~= nil
    local legacyGroupGeometry = legacyProfile == true
        and (tonumber(profile._msufProfileSchema) or 0) < MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
        and not hadAuras3
    local changed = MSUF_PROFILEIO_AURA_RESETTERS.ResetUnit(profile)
    changed = MSUF_PROFILEIO_AURA_RESETTERS.ResetGroup(profile, legacyGroupGeometry) or changed
    local auras = profile.auras3
    if type(auras) ~= "table" then return changed end
    local repairAuraOverrides = legacyProfile == true or MSUF_ProfileIO_AuraOverridesNeedRepair(profile)
    changed = MSUF_ProfileIO_NormalizeAuraLayoutTable(auras.shared) or changed
    if type(auras.perUnit) == "table" then
        for _, unitCfg in pairs(auras.perUnit) do
            if type(unitCfg) == "table" then
                changed = MSUF_ProfileIO_NormalizeAuraLayoutTable(unitCfg.layout) or changed
                changed = MSUF_ProfileIO_NormalizeAuraLayoutTable(unitCfg.layoutShared) or changed
                if repairAuraOverrides then
                    if MSUF_ProfileIO_TableHasAnyValue(unitCfg.layout) and unitCfg.overrideLayout == nil then
                        unitCfg.overrideLayout = true
                        changed = true
                    end
                    if MSUF_ProfileIO_TableHasAnyValue(unitCfg.layoutShared) and unitCfg.overrideSharedLayout == nil then
                        unitCfg.overrideSharedLayout = true
                        changed = true
                    end
                end
            end
        end
    end
    return changed
end

MSUF_ProfileIO_TranslateProfileToCurrent = function(profile, context)
    if type(profile) ~= "table" then return profile, false end
    context = type(context) == "table" and context or {}
    --- Only internal callers operating on an already-stored profile may trust
    --- the persisted marker. Import payloads are deliberately never trusted:
    --- an external table can contain copied/spoofed internal metadata and must
    --- still receive the complete validation and legacy-repair pass.
    if context.trustNormalizationMarker == true
        and tonumber(profile._msufProfileSchema) == MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
        and tonumber(profile._msufProfileNormalizationRevision) == MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION
        and type(profile.general) == "table"
        and not MSUF_ProfileIO_ProfileNeedsLegacyRepair(profile) then
        return profile, false
    end
    local changed = false
    if context.trustNormalizationMarker ~= true then
        --- Defaults migrations have their own fast-path markers. Drop them on
        --- untrusted payloads so a later EnsureDB cannot be tricked into
        --- skipping validation by metadata copied from an exported profile.
        if profile._msufDefaultsRevision ~= nil then
            profile._msufDefaultsRevision = nil
            changed = true
        end
        if profile._msufDispelPriorityMigration ~= nil then
            profile._msufDispelPriorityMigration = nil
            changed = true
        end
        --- Navigation icons are the supported Menu2 baseline for imports.
        --- Normalize the payload itself so full and Unit Frame imports cannot
        --- restore an older explicit false value before the final EnsureDB.
        if type(profile.general) == "table" and profile.general.showNavigationIcons ~= true then
            profile.general.showNavigationIcons = true
            changed = true
        end
    end
    local schema = MSUF_ProfileIO_DetectProfileSchema(profile, context)
    local legacyProfile = schema < MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
    local declaredSchema = tonumber(profile._msufProfileSchema)
    local preferLegacyAliases = legacyProfile
        and (declaredSchema == nil or declaredSchema < MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA)
    MSUF_ProfileIO_NormalizeImportedFontSizes(profile)
    if context.normalizePositions ~= false then
        local _, aliasesChanged = MSUF_ProfileIO_NormalizeUnitFramePositionDB(profile, preferLegacyAliases)
        changed = aliasesChanged or changed
    end
    changed = MSUF_ProfileIO_NormalizeLegacyRootNameShortening(profile, context.createGeneral ~= false) or changed
    if type(profile.general) == "table" and profile.general.fontBaselineOffset == nil then
        profile.general.fontBaselineOffset = 0
        changed = true
    end
    for i = 1, #MSUF_PROFILEIO_TEXT_SCOPE_KEYS do
        local key = MSUF_PROFILEIO_TEXT_SCOPE_KEYS[i]
        local scope = profile[key]
        if type(scope) == "table" then
            local isGroupScope = key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid"
            local inferFontOverride = key ~= "general"
            if legacyProfile and isGroupScope and scope.fontOverride == nil then
                -- 5.57 always stored local Group name-shortening values, but
                -- they only owned runtime behavior when fontOverride was
                -- explicitly true. Inferring the override from those dormant
                -- fields switches imported names from the global 5.57 layout
                -- to 6.0's local clipping layout and changes their position.
                -- Persist false inside the selected Group scope. A group-only
                -- import does not copy root migration markers into MSUF_DB, so
                -- leaving this nil would let a later current-schema defaults
                -- pass infer true again from nameMaxChars/nameNoEllipsis.
                scope.fontOverride = false
                inferFontOverride = false
                changed = true
            end
            changed = MSUF_ProfileIO_NormalizeTextScope(scope, isGroupScope, inferFontOverride) or changed
            changed = MSUF_ProfileIO_NormalizeStatusScope(scope, isGroupScope) or changed
        end
    end
    changed = MSUF_ProfileIO_MigrateSplitStatusText(profile) or changed
    changed = MSUF.ProfileIONormalizeLegacy55VisualCompatibility(profile, legacyProfile, context) or changed
    changed = MSUF_ProfileIO_NormalizeLegacyAuras(
        profile, legacyProfile, context.trustNormalizationMarker ~= true) or changed
    changed = MSUF_ProfileIO_NormalizeGFAuraFilterTokens(profile, true) or changed
    local normalizeLayers = _G.MSUF_NormalizeNumericLayers
    if type(normalizeLayers) ~= "function" and type(MSUF) == "table" then
        normalizeLayers = MSUF.MSUF_NormalizeNumericLayers
    end
    if type(normalizeLayers) == "function" then
        changed = normalizeLayers(profile) or changed
    end
    if context.markProfile ~= false then
        if profile._msufProfileSchema ~= MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA then
            profile._msufProfileSchema = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
            changed = true
        end
        if profile._msufProfileNormalizationRevision ~= MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION then
            profile._msufProfileNormalizationRevision = MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION
            changed = true
        end
        if schema < MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA then
            profile._msufLegacyProfileSchema = nil
        end
    end
    return profile, changed
end

MSUF_ProfileIO_TranslateProfilesToCurrent = function(profiles, source)
    if type(profiles) ~= "table" then return false end
    local changed = false
    for _, profile in pairs(profiles) do
        if type(profile) == "table" then
            local _, profileChanged = MSUF_ProfileIO_TranslateProfileToCurrent(profile, {
                source = source or "profiles",
                markProfile = true,
                trustNormalizationMarker = true,
            })
            changed = profileChanged or changed
            MSUF_ProfileIO_EnsureProfileMenuDefaults(profile)
        end
    end
    return changed
end

--- Deterministic-ish Lua serializer (good enough for UI copy/paste strings).
local function MSUF_SerializeLuaTable(root)
    local function valToStr(v)
        local tv = type(v)
        if tv == "number" then
            return tostring(v)
        elseif tv == "boolean" then
            return v and "true" or "false"
        elseif tv == "string" then
            return string.format("%q", v)
        elseif tv == "table" then
             return nil --- handled by serTable
        else
             return "nil"
        end
     end
    local function keyToStr(k)
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
             return k
        elseif type(k) == "number" or type(k) == "boolean" then
            -- Preserve typed map keys in the no-codec Lua fallback. Quoting a
            -- numeric Spec/Spell ID here silently turned [71] into ["71"] on
            -- import and detached all geometry stored below that key.
            return "[" .. tostring(k) .. "]"
        else
            return "[" .. string.format("%q", k) .. "]"
        end
     end
    local function sortKeys(t)
        local keys = {}
        for k in pairs(t) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then
                return tostring(ta) < tostring(tb)
            end
            if ta == "number" then
                return a < b
            end
            return tostring(a) < tostring(b)
        end)
         return keys
    end
    local function serTable(t, indent)
        indent = indent or ""
        local indent2 = indent .. "  "
        local lines = {}
        table.insert(lines, "{\n")
        local keys = sortKeys(t)
        for _, k in ipairs(keys) do
            local v = t[k]
            local kStr = keyToStr(k)
            if type(v) == "table" then
                table.insert(lines, indent2 .. kStr .. " = " .. serTable(v, indent2) .. ",\n")
            else
                table.insert(lines, indent2 .. kStr .. " = " .. valToStr(v) .. ",\n")
            end
        end
        table.insert(lines, indent .. "}")
        return table.concat(lines)
    end
    return "return " .. serTable(root, "")
end
--- Key classification for general settings.
local function MSUF_IsColorKey(k)
    if type(k) ~= "string" then  return false end
    local lk = string.lower(k)
    --- Obvious markers
    if lk:find("color", 1, true) then  return true end
    --- Global theme/mode keys
    if lk == "barmode" or lk == "darkmode" or lk == "darkbartone" or lk == "darkbgbrightness" then  return true end
    if lk == "useclasscolors" or lk == "enablehealthgradient" or lk == "gradientstrength" then  return true end
    --- Font/Highlight naming
    if lk == "fontcolor" or lk == "highlightcolor" or lk == "usecustomfontcolor" then  return true end
    if lk == "nameclasscolor" or lk == "npcnamered" then  return true end
    --- Common RGB/A suffix patterns used for colors.
    local last = lk:sub(-1)
    if last == "r" or last == "g" or last == "b" or last == "a" then
        --- Avoid false positives like "offsetx/offsety".
        if lk:find("color", 1, true) or lk:find("font", 1, true) or lk:find("bg", 1, true) or lk:find("border", 1, true) or lk:find("outline", 1, true) or lk:find("gradient", 1, true) then
             return true
        end
        --- Explicit known custom font color fields
        if lk == "fontcolorcustomr" or lk == "fontcolorcustomg" or lk == "fontcolorcustomb" then
             return true
        end
    end
     return false
end
--- Aura-related general keys that should travel with Auras settings (even though they are 'color keys').
local MSUF_AURA_GENERAL_KEYS = {
aurasOwnBuffHighlightColor = true,
    aurasOwnDebuffHighlightColor = true,
    aurasStackCountColor = true,
}
local function MSUF_IsAuraGeneralKey(key)
    return (type(key) == "string") and (MSUF_AURA_GENERAL_KEYS[key] == true)
end
-- Unified, coldpath alpha keys: HP fill opacity, power fill opacity, background
-- opacity, and a toggle to keep text + portrait opaque. Note hpBarAlpha,
-- powerBarAlpha, hpBgAlpha, and powerBarBgAlpha are NOT colour keys here
-- (MSUF_IsColorKey matches "bg"); listing them keeps them travelling with unitframe
-- settings rather than colour settings.
local MSUF_UNITFRAME_ALPHA_KEYS = {
    hpBarAlpha = true,
    powerBarAlpha = true,
    hpBgAlpha = true,
    powerBarBgAlpha = true,
    alphaExcludeTextPortrait = true,
}
local MSUF_UNITFRAME_ALPHA_DEFAULTS = {
    hpBarAlpha = 1,
    powerBarAlpha = 1,
    hpBgAlpha = 0.85,
    powerBarBgAlpha = 0.85,
    alphaExcludeTextPortrait = false,
}
local MSUF_UNITFRAME_UNIT_KEYS = { "player", "target", "targettarget", "focustarget", "focus", "pet", "boss" }
local function MSUF_IsUnitframeAlphaKey(key)
    return (type(key) == "string") and (MSUF_UNITFRAME_ALPHA_KEYS[key] == true)
end
local function MSUF_IsCastbarKey(k)
    if type(k) ~= "string" then  return false end
    local lk = string.lower(k)
    --- Core castbar markers
    if lk:find("castbar", 1, true) then  return true end
    if lk:find("bosscast", 1, true) then  return true end
    if lk:find("empower", 1, true) then  return true end
    --- Enable toggles / timing
    if lk == "enableplayercastbar" or lk == "enabletargetcastbar" or lk == "enablefocuscastbar" then  return true end
    if lk == "castbarupdateinterval" then  return true end
    --- Per-castbar font override fields (global storage)
    if lk:find("spellnamefontsize", 1, true) or lk:find("timefontsize", 1, true) then  return true end
     return false
end
local function MSUF_IsUnitframeGeneralKey(key)
    return (MSUF_IsUnitframeAlphaKey(key) or (not MSUF_IsColorKey(key)) or MSUF_IsAuraGeneralKey(key)) and (not MSUF_IsCastbarKey(key))
end
local function MSUF_CopyGeneralSubset(filterFn)
    local out = {}
    local g = (MSUF_DB and MSUF_DB.general) or {}
    for k, v in pairs(g) do
        if filterFn(k, v) then
            out[k] = MSUF_DeepCopy(v)
        end
    end
     return out
end
local function MSUF_WipeGeneralSubset(filterFn)
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    if type(MSUF_DB.general) ~= "table" then
        MSUF_DB.general = {}
    end
    local g = MSUF_DB.general
    for k in pairs(g) do
        if filterFn(k, g[k]) then
            g[k] = nil
        end
    end
 end
local function MSUF_ApplyGeneralSubset(tbl)
    if not tbl then  return end
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    if type(MSUF_DB.general) ~= "table" then
        MSUF_DB.general = {}
    end
    local g = MSUF_DB.general
    for k, v in pairs(tbl) do
        g[k] = MSUF_DeepCopy(v)
    end
 end
--- Legacy combat/layered alpha keys retired by the unified alpha rewrite. Imported
--- profiles may still carry them; strip them so they never resurrect the old model.
local MSUF_UNITFRAME_LEGACY_ALPHA_KEYS = {
    "alphaInCombat", "alphaOutOfCombat", "alphaSync", "alphaSyncBoth", "alphaLayerMode",
    "alphaFGInCombat", "alphaFGOutOfCombat", "alphaBGInCombat", "alphaBGOutOfCombat",
    "alphaHPInCombat", "alphaHPOutOfCombat", "alphaPreserveHPColor", "bgA", "hpTextIgnoreAlpha",
}
local function MSUF_ProfileIO_EnsureUnitframeAlphaDB()
    if type(MSUF_DB) ~= "table" then  return end
    local function ensureAlpha(conf)
        if type(conf) ~= "table" then  return end
        for i = 1, #MSUF_UNITFRAME_LEGACY_ALPHA_KEYS do
            conf[MSUF_UNITFRAME_LEGACY_ALPHA_KEYS[i]] = nil
        end
        for k, v in pairs(MSUF_UNITFRAME_ALPHA_DEFAULTS) do
            if conf[k] == nil then
                conf[k] = v
            end
        end
    end
    for _, unitKey in ipairs(MSUF_UNITFRAME_UNIT_KEYS) do
        if type(MSUF_DB[unitKey]) ~= "table" then
            MSUF_DB[unitKey] = {}
        end
        ensureAlpha(MSUF_DB[unitKey])
    end
 end
local function MSUF_ProfileIO_EnsureGroupFramesDB()
    local ensureGF = _G.MSUF_GF_EnsureDB
    if type(ensureGF) == "function" then
        ensureGF()
        return
    end
    local gf = _G.MSUF_NS and _G.MSUF_NS.GF
    if gf and type(gf.EnsureDB) == "function" then
        gf.EnsureDB()
    end
end
local function MSUF_ProfileIO_EnsureCompleteProfileDB()
    MSUF_ProfileIO_RunEnsureDB()
    MSUF_ProfileIO_EnsureUnitframeAlphaDB()
    MSUF_ProfileIO_EnsureGroupFramesDB()
    local auras = MSUF and MSUF.MSUF_Auras3
    if auras then
        if type(auras.EnsureDB) == "function" then
            auras.EnsureDB()
        end
        local aurasDB = auras.DB
        if aurasDB and type(aurasDB.Ensure) == "function" then
            aurasDB.Ensure()
        end
    end
end

--- Export normalization does not try to make the live DB pretty. It creates a
--- clean payload copy, translates old aliases, and strips runtime/cache-only
--- state so copied profile strings stay portable across characters and clients.
local MSUF_GF_BLIZZARD_TYPE_DEFAULTS = {
    buffs = true,
    debuffs = true,
    dispels = true,
    externals = true,
}

local function MSUF_ProfileIO_EnsureBlizzardAuraPositionDefaults(auras)
    if type(auras) ~= "table" then return end
    if auras.blizzardContainerAnchor == nil then auras.blizzardContainerAnchor = "FRAME" end
    if auras.blizzardContainerX == nil then auras.blizzardContainerX = 0 end
    if auras.blizzardContainerY == nil then auras.blizzardContainerY = 0 end
end

local function MSUF_ProfileIO_GetGFAuraFilter()
    local gf = (type(MSUF) == "table" and MSUF.GF) or (_G.MSUF_NS and _G.MSUF_NS.GF)
    return (gf and gf.AuraFilter) or _G.MSUF_GF_AuraFilter
end

local function MSUF_ProfileIO_CopyDefaultBlacklistCats(groupKey)
    local af = MSUF_ProfileIO_GetGFAuraFilter()
    local defs = af and ((groupKey == "buff") and af.DEFAULT_BLACKLIST_BUFF
        or (groupKey == "debuff") and af.DEFAULT_BLACKLIST_DEBUFF
        or nil)
    if type(defs) ~= "table" then
        return {}
    end
    return MSUF_DeepCopy(defs)
end

local function MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, groupKey, defaultToken)
    local group = auras and auras[groupKey]
    if type(group) ~= "table" then return end

    if group.filterToken == nil then
        local fm = group.filterMode
        if fm == "RAID_PLAYER" or fm == "RAID_IN_COMBAT" or fm == "ALL_PLAYER" then
            group.filterToken = "ALL"
        elseif fm == "ALL" or fm == "PLAYER" or fm == "RAID" then
            group.filterToken = fm
        elseif fm == "NOT_PLAYER" then
            group.filterToken = "ALL"
        else
            group.filterToken = defaultToken
        end
    end
    group.filterToken = MSUF_ProfileIO_NormalizeGFAuraFilterToken(groupKey, group.filterToken)

    if type(group.blacklistCats) ~= "table" then
        group.blacklistCats = MSUF_ProfileIO_CopyDefaultBlacklistCats(groupKey)
    end
    if group.strata == nil then group.strata = "AUTO" end
    if groupKey == "buff" and group.trackedStrata == nil then group.trackedStrata = "AUTO" end
    if group.cooldownSwipeReverse == nil then group.cooldownSwipeReverse = false end
    if type(group.blacklist) ~= "table" then group.blacklist = {} end
    if type(group.blacklist.spells) ~= "table" then group.blacklist.spells = {} end
end

local function MSUF_ProfileIO_NormalizeGroupFrameForExport(conf)
    if type(conf) ~= "table" then return end
    if type(conf.auras) ~= "table" then return end

    local auras = conf.auras
    if auras.renderer ~= "CUSTOM" and auras.renderer ~= "NATIVE_12_1" then
        auras.renderer = "NATIVE_12_1"
    end
    if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
    for key, value in pairs(MSUF_GF_BLIZZARD_TYPE_DEFAULTS) do
        if auras.blizzardTypes[key] == nil then
            auras.blizzardTypes[key] = value
        end
    end
    if auras.blizzardIconSize == nil then auras.blizzardIconSize = 20 end
    if auras.blizzardShowCooldownText == nil then auras.blizzardShowCooldownText = true end
    if auras.blizzardOrganizationType == nil then auras.blizzardOrganizationType = "default" end
    if auras.blizzardDispelMode == nil then auras.blizzardDispelMode = "allDispellable" end
    if auras.blizzardDispelBorder == nil then auras.blizzardDispelBorder = false end
    MSUF_ProfileIO_EnsureBlizzardAuraPositionDefaults(auras)

    MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, "buff", "ALL")
    MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, "debuff", "ALL")
    MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, "externals", "RAID")
end

local function MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload)
    if type(payload) ~= "table" then return payload end
    MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_party)
    MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_raid)
    MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_mythicraid)
    return payload
end

local MSUF_PROFILEIO_WAGO_SCHEMA = 1
local MSUF_PROFILEIO_WAGO_FULL_KEY = "msuf6"
local MSUF_PROFILEIO_WAGO_PAYLOAD_KEYS = {
    auras2 = true,
    bars = true,
    boss = true,
    classColors = true,
    classPowerPerSpec = true,
    classPowerPresets = true,
    focus = true,
    gameplay = true,
    general = true,
    gf_mythicraid = true,
    gf_party = true,
    gf_priority = true,
    gf_raid = true,
    group = true,
    groupFrames = true,
    groupframes = true,
    npcColors = true,
    party = true,
    pet = true,
    player = true,
    shortenNames = true,
    target = true,
    targettarget = true,
    tot = true,
}
local MSUF_PROFILEIO_WAGO_AURA_DROP_KEYS = {
    buffGroupOffsetX = true,
    buffGroupOffsetY = true,
    debuffGroupOffsetX = true,
    debuffGroupOffsetY = true,
    buffGroupIconSize = true,
    debuffGroupIconSize = true,
    buffGrowthX = true,
    buffGrowthY = true,
    debuffGrowthX = true,
    debuffGrowthY = true,
    showCooldownText = true,
    cooldownSwipeReverse = true,
    showDurationBar = true,
    durationBarHeight = true,
    durationBarDisplay = true,
    durationBarPosition = true,
    durationBarDirection = true,
    stackTextOffsetX = true,
    stackTextOffsetY = true,
    cooldownTextAnchor = true,
    cooldownTextOffsetX = true,
    cooldownTextOffsetY = true,
    cooldownDecimalSeconds = true,
    buffAnchor = true,
    debuffAnchor = true,
    -- buffLayer/debuffLayer intentionally remain portable. Some external tools
    -- keep only this compatibility payload and omit the embedded msuf6 table.
    debuffTypeBorderMode = true,
    useDebuffTypeBorders = true,
}

local function MSUF_ProfileIO_CopyIfMissingValue(tbl, toKey, ...)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil then return end
    for i = 1, select("#", ...) do
        local fromKey = select(i, ...)
        if tbl[fromKey] ~= nil then
            tbl[toKey] = MSUF_DeepCopy(tbl[fromKey])
            return
        end
    end
end

local function MSUF_ProfileIO_CopyMissingFrom(tbl, defaults)
    if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
    for key, value in pairs(defaults) do
        if tbl[key] == nil then
            tbl[key] = MSUF_DeepCopy(value)
        end
    end
end

local function MSUF_ProfileIO_StripPrivateMSUFKeys(tbl, seen)
    if type(tbl) ~= "table" then return end
    seen = seen or {}
    if seen[tbl] then return end
    seen[tbl] = true
    for key, value in pairs(tbl) do
        if type(key) == "string" and key:match("^_msuf") then
            tbl[key] = nil
        elseif type(value) == "table" then
            MSUF_ProfileIO_StripPrivateMSUFKeys(value, seen)
        end
    end
end

local function MSUF_ProfileIO_NormalizeAuraFilterForWago(filter)
    if type(filter) ~= "table" then return end
    filter.onlyImportantAuras = nil
    local function normalizeGroup(group)
        if type(group) ~= "table" then return end
        group.includeNameplateOnly = nil
        group.cancelable = nil
        group.notCancelable = nil
        group.externalDefensive = nil
        group.bigDefensive = nil
        group.exclusive = nil
        group.crowdControl = nil
        if group.filterToken == nil then
            group.filterToken = "ALL"
        end
    end
    normalizeGroup(filter.buffs)
    normalizeGroup(filter.debuffs)
end

local function MSUF_ProfileIO_NormalizeAuraLayoutForWago(layout, layoutShared)
    if type(layout) ~= "table" then return end
    MSUF_ProfileIO_CopyMissingFrom(layout, layoutShared)
    MSUF_ProfileIO_CopyIfMissingValue(layout, "iconSize", "buffGroupIconSize", "debuffGroupIconSize")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "buffIconSize", "buffGroupIconSize", "iconSize")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "debuffIconSize", "debuffGroupIconSize", "iconSize")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "buffOffsetX", "buffGroupOffsetX", "offsetX")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "buffOffsetY", "buffGroupOffsetY", "offsetY")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "debuffOffsetX", "debuffGroupOffsetX", "offsetX")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "debuffOffsetY", "debuffGroupOffsetY", "offsetY")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "offsetX", "buffGroupOffsetX", "debuffGroupOffsetX")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "offsetY", "debuffGroupOffsetY", "buffGroupOffsetY")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "growth", "buffGrowthX", "debuffGrowthX")
    if layout.layoutMode == "SEPARATE" then
        layout.layoutMode = "SINGLE"
    end
    for key in pairs(MSUF_PROFILEIO_WAGO_AURA_DROP_KEYS) do
        layout[key] = nil
    end
end

local function MSUF_ProfileIO_NormalizeAurasForWago(auras)
    if type(auras) ~= "table" then return end
    MSUF_ProfileIO_StripPrivateMSUFKeys(auras)
    MSUF_ProfileIO_NormalizeAuraLayoutForWago(auras.shared)
    MSUF_ProfileIO_NormalizeAuraFilterForWago(auras.shared and auras.shared.filters)
    if type(auras.perUnit) == "table" then
        for _, unit in pairs(auras.perUnit) do
            if type(unit) == "table" then
                MSUF_ProfileIO_NormalizeAuraLayoutForWago(unit.layout, unit.layoutShared)
                unit.layoutShared = nil
                unit.overrideSharedLayout = nil
                MSUF_ProfileIO_NormalizeAuraFilterForWago(unit.filters)
            end
        end
    end
end

local function MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, groupKey, defaultToken)
    local group = auras and auras[groupKey]
    if type(group) ~= "table" then return end
    if group.filterToken == nil then
        group.filterToken = defaultToken
    end
    group.filterToken = MSUF_ProfileIO_NormalizeGFAuraFilterToken(groupKey, group.filterToken)
    if type(group.blacklist) == "table" then
        group.blacklist.spells = nil
    end
    group.cooldownSwipeReverse = nil
end

local function MSUF_ProfileIO_NormalizeGroupFrameForWago(conf)
    if type(conf) ~= "table" or type(conf.auras) ~= "table" then return end
    local auras = conf.auras
    if auras.renderer ~= "CUSTOM" and auras.renderer ~= "BLIZZARD" then
        auras.renderer = "BLIZZARD"
    end
    if auras.renderer == nil then auras.renderer = "BLIZZARD" end
    if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
    for key, value in pairs(MSUF_GF_BLIZZARD_TYPE_DEFAULTS) do
        if auras.blizzardTypes[key] == nil then
            auras.blizzardTypes[key] = value
        end
    end
    if auras.blizzardIconSize == nil then auras.blizzardIconSize = 20 end
    if auras.blizzardShowCooldownText == nil then auras.blizzardShowCooldownText = true end
    if auras.blizzardOrganizationType == nil then auras.blizzardOrganizationType = "default" end
    if auras.blizzardDispelMode == nil then auras.blizzardDispelMode = "allDispellable" end
    if auras.blizzardDispelBorder == nil then auras.blizzardDispelBorder = false end
    auras.blizzardContainerAnchor = "FRAME"
    auras.blizzardContainerX = 0
    auras.blizzardContainerY = 0
    MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, "buff", "RAID")
    MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, "debuff", "ALL")
    MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, "externals", "RAID")
end

local function MSUF_ProfileIO_MakeWagoPayload(payload)
    if type(payload) ~= "table" then return {} end
    local out = {}
    for key, value in pairs(payload) do
        if MSUF_PROFILEIO_WAGO_PAYLOAD_KEYS[key] then
            out[key] = MSUF_DeepCopy(value)
        end
    end
    if type(payload.auras3) == "table" then
        out.auras2 = MSUF_DeepCopy(payload.auras3)
    end
    out.auras3 = nil
    out.auras = nil
    out._msufProfileSchema = nil
    out._msufLegacyProfileSchema = nil
    MSUF_ProfileIO_NormalizeAurasForWago(out.auras2)
    MSUF_ProfileIO_NormalizeGroupFrameForWago(out.gf_party)
    MSUF_ProfileIO_NormalizeGroupFrameForWago(out.gf_raid)
    MSUF_ProfileIO_NormalizeGroupFrameForWago(out.gf_mythicraid)
    return out
end

local function MSUF_ProfileIO_MakeWagoSnapshot(snapshot)
    if type(snapshot) ~= "table" or snapshot.kind ~= "all" or type(snapshot.payload) ~= "table" then
        return snapshot, false
    end
    return {
        addon   = "MSUF",
        fmt     = 2,
        schema  = MSUF_PROFILEIO_WAGO_SCHEMA,
        kind    = "all",
        profile = snapshot.profile,
        payload = MSUF_ProfileIO_MakeWagoPayload(snapshot.payload),
        [MSUF_PROFILEIO_WAGO_FULL_KEY] = {
            schema  = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
            kind    = "all",
            profile = snapshot.profile,
            payload = MSUF_DeepCopy(snapshot.payload),
        },
    }, true
end

local function MSUF_ProfileIO_SelectWagoFullSnapshot(snapshot)
    if type(snapshot) ~= "table" then return snapshot end
    local full = snapshot[MSUF_PROFILEIO_WAGO_FULL_KEY]
    if type(full) == "table"
        and tonumber(full.schema) == MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
        and type(full.payload) == "table" then
        return {
            addon   = "MSUF",
            fmt     = 2,
            schema  = full.schema,
            kind    = type(full.kind) == "string" and full.kind or snapshot.kind,
            profile = type(full.profile) == "string" and full.profile or snapshot.profile,
            payload = full.payload,
        }
    end
    return snapshot
end

local function MSUF_CopyGroupFramePayload()
    local payload = {}
    if type(MSUF_DB) ~= "table" then
        return payload
    end
    if type(MSUF_DB.gf_party) == "table" then
        payload.gf_party = MSUF_DeepCopy(MSUF_DB.gf_party)
        MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_party)
    end
    if type(MSUF_DB.gf_raid) == "table" then
        payload.gf_raid = MSUF_DeepCopy(MSUF_DB.gf_raid)
        MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_raid)
    end
    if type(MSUF_DB.gf_mythicraid) == "table" then
        payload.gf_mythicraid = MSUF_DeepCopy(MSUF_DB.gf_mythicraid)
        MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_mythicraid)
    end
    if type(MSUF_DB.gf_priority) == "table" then
        payload.gf_priority = MSUF_DeepCopy(MSUF_DB.gf_priority)
    end
    return payload
end
--- Blizzard Edit Mode data in profile strings is strictly opt-in, per
--- direction: exports never carry general.blizzardEditModeSnapshot and
--- imports never apply it unless the profiles-page switch is on. Both flags
--- are session-transient by design — the user decides per session.
local MSUF_ProfileIO_ExportBlizzardEM = false
local MSUF_ProfileIO_ImportBlizzardEM = false
ExportPublic("MSUF_Profiles_SetExportBlizzardEditMode", function(value)
    MSUF_ProfileIO_ExportBlizzardEM = value == true
end)
ExportPublic("MSUF_Profiles_SetImportBlizzardEditMode", function(value)
    MSUF_ProfileIO_ImportBlizzardEM = value == true
end)

local function MSUF_SnapshotForKind(kind)
    MSUF_ProfileIO_EnsureCompleteProfileDB()
    local payload = {}
    if kind == "unitframe" then
        --- Everything EXCEPT: gameplay, colors, castbars
        for k, v in pairs(MSUF_DB or {}) do
            if k == "general" then
                payload.general = MSUF_CopyGeneralSubset(MSUF_IsUnitframeGeneralKey)
            elseif k == "classColors" or k == "npcColors" or k == "gameplay" then
                --- exclude
            else
                payload[k] = MSUF_DeepCopy(v)
            end
        end
        MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload)
    elseif kind == "castbar" then
        payload.general = MSUF_CopyGeneralSubset(function(key)
            return MSUF_IsCastbarKey(key) and (not MSUF_IsColorKey(key))
        end)
    elseif kind == "colors" then
        payload.general = MSUF_CopyGeneralSubset(function(key)
            return MSUF_IsColorKey(key)
        end)
        payload.classColors = MSUF_DeepCopy((MSUF_DB and MSUF_DB.classColors) or {})
        payload.npcColors   = MSUF_DeepCopy((MSUF_DB and MSUF_DB.npcColors) or {})
    elseif kind == "gameplay" then
        payload.gameplay = MSUF_DeepCopy((MSUF_DB and MSUF_DB.gameplay) or {})
    elseif kind == "groupframe" or kind == "groupframes" then
        payload = MSUF_CopyGroupFramePayload()
    elseif kind == "all" then
        payload = MSUF_DeepCopy(MSUF_DB or {})
        MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload)
    else
         return nil
    end
    if type(payload.general) == "table" then
        payload.general.blizzardEditModeSnapshot = nil
    end
    if kind == "all" and MSUF_ProfileIO_ExportBlizzardEM then
        local blizzSnapshot = type(MSUF_DB) == "table" and type(MSUF_DB.general) == "table"
            and MSUF_DB.general.blizzardEditModeSnapshot or nil
        if type(blizzSnapshot) == "table" then
            if type(payload.general) ~= "table" then payload.general = {} end
            payload.general.blizzardEditModeSnapshot = MSUF_DeepCopy(blizzSnapshot)
        end
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
    local af = MSUF_ProfileIO_GetGFAuraFilter()
    if af and type(af.InvalidateAllBlacklistHashes) == "function" then
        af.InvalidateAllBlacklistHashes()
    end
    if type(_G.MSUF_GF_InvalidateConfCache) == "function" then
        _G.MSUF_GF_InvalidateConfCache()
    end
    local gf = (type(MSUF) == "table" and MSUF.GF) or (_G.MSUF_NS and _G.MSUF_NS.GF)
    if gf and type(gf.Rebuild) == "function" then
        local rebuilt = false
        for i = 1, #touchedKinds do
            local groupKind = touchedKinds[i]
            local ok = MSUF_ProfileIO_RunProtected("GF.Rebuild(" .. tostring(groupKind) .. ")", gf.Rebuild, groupKind)
            rebuilt = ok or rebuilt
        end
        if rebuilt then return end
    elseif gf and type(gf.RefreshGeometry) == "function" then
        local refreshed = false
        for i = 1, #touchedKinds do
            local groupKind = touchedKinds[i]
            local ok = MSUF_ProfileIO_RunProtected("GF.RefreshGeometry(" .. tostring(groupKind) .. ")", gf.RefreshGeometry, groupKind)
            refreshed = ok or refreshed
            if type(gf.RefreshUnitBindings) == "function" then
                MSUF_ProfileIO_RunProtected("GF.RefreshUnitBindings(" .. tostring(groupKind) .. ")", gf.RefreshUnitBindings, groupKind)
            end
            if type(gf.RefreshVisuals) == "function" then
                MSUF_ProfileIO_RunProtected("GF.RefreshVisuals(" .. tostring(groupKind) .. ")", gf.RefreshVisuals, groupKind, gf.DIRTY_ALL or gf.DIRTY_CONFIG or gf.DIRTY_VISUAL)
            end
        end
        if refreshed then return end
    elseif gf and type(gf.RequestAuraRefresh) == "function" then
        gf.RequestAuraRefresh()
    elseif gf and type(gf.MarkAllDirty) == "function" then
        gf.MarkAllDirty(gf.DIRTY_AURAS or gf.DIRTY_ALL or 0x3F)
    end
    if type(_G.MSUF_GF_RefreshGeometry) == "function" then
        for i = 1, #touchedKinds do
            local groupKind = touchedKinds[i]
            _G.MSUF_GF_RefreshGeometry(groupKind)
            if type(_G.MSUF_GF_RefreshUnitBindings) == "function" then
                _G.MSUF_GF_RefreshUnitBindings(groupKind)
            end
            if type(_G.MSUF_GF_RefreshVisuals) == "function" then
                _G.MSUF_GF_RefreshVisuals(groupKind)
            end
        end
        return
    end
    if type(_G.MSUF_GF_Refresh) == "function" then
        _G.MSUF_GF_Refresh()
    elseif type(_G.MSUF_GF_RefreshAll) == "function" then
        _G.MSUF_GF_RefreshAll()
    elseif type(_G.MSUF_GF_RefreshVisuals) == "function" then
        _G.MSUF_GF_RefreshVisuals()
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
    local refresh = _G.MSUF_RefreshAllUnitAlphas or _G.MSUF_RequestAlphaRefresh
    if type(refresh) == "function" then
        if full then
            refresh()
        else
            for i = 1, #touchedUnits do refresh(touchedUnits[i]) end
        end
    end
end
local function MSUF_ApplySnapshotToActiveProfile(snapshot)
    if not snapshot then  return false, "not a table" end
    local valid, validationError = MSUF.ProfileIOValidateImportValue(snapshot)
    if not valid then return false, validationError end
    local copied, stagedSnapshot = MSUF_ProfileIO_RunProtected("snapshot staging", MSUF_DeepCopy, snapshot)
    if not copied or type(stagedSnapshot) ~= "table" then
        return false, "profile staging failed: " .. tostring(stagedSnapshot)
    end
    snapshot = stagedSnapshot
    snapshot = MSUF_ProfileIO_SelectWagoFullSnapshot(snapshot)
    local kind = snapshot.kind
    if kind == "groupframes" then
        kind = "groupframe"
    end
    local payload = snapshot.payload
    if type(kind) ~= "string" or type(payload) ~= "table" then
         return false, "invalid snapshot"
    end
    --- Opt-in gate for imported Blizzard Edit Mode data: stripped before the
    --- merge unless the profiles-page switch is on, so a foreign string can
    --- never silently rearrange the local Blizzard HUD.
    if not MSUF_ProfileIO_ImportBlizzardEM and type(payload.general) == "table" then
        payload.general.blizzardEditModeSnapshot = nil
    end
    if kind == "unitframe" or kind == "groupframe" or kind == "all" then
        MSUF_ProfileIO_TranslateProfileToCurrent(payload, {
            source = "snapshot_import",
            schema = snapshot.schema,
            markProfile = (kind == "all"),
            createGeneral = (kind == "all") or type(payload.general) == "table",
            normalizePositions = (kind == "unitframe" or kind == "all"),
        })
    else
        MSUF_ProfileIO_NormalizeImportedFontSizes(payload)
    end
    MSUF_ProfileIO_CollectProfileMediaWarnings(payload)
    MSUF_ProfileIO_RunEnsureDB()

    --- Always keep the profile-table reference stable (important!).
    --- Do not replace MSUF_DB with a new table here. Runtime modules keep
    --- references into the active profile and are invalidated by the apply hook.
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    if kind == "unitframe" then
        --- Wipe & replace the same general-key set that Unitframes export.
        MSUF_WipeGeneralSubset(MSUF_IsUnitframeGeneralKey)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general)
        end
        for k, v in pairs(payload) do
            if k ~= "general" then
                if type(v) == "table" then
                    if type(MSUF_DB[k]) ~= "table" then
                        MSUF_DB[k] = {}
                    end
                    MSUF_WipeTable(MSUF_DB[k])
                    for kk, vv in pairs(v) do
                        MSUF_DB[k][kk] = MSUF_DeepCopy(vv)
                    end
                else
                    MSUF_DB[k] = v
                end
            end
        end
    elseif kind == "groupframe" then
        if payload.gf_party ~= nil then
            if type(payload.gf_party) == "table" then
                if type(MSUF_DB.gf_party) ~= "table" then
                    MSUF_DB.gf_party = {}
                end
                MSUF_WipeTable(MSUF_DB.gf_party)
                for kk, vv in pairs(payload.gf_party) do
                    MSUF_DB.gf_party[kk] = MSUF_DeepCopy(vv)
                end
            else
                MSUF_DB.gf_party = MSUF_DeepCopy(payload.gf_party)
            end
        end
        if payload.gf_raid ~= nil then
            if type(payload.gf_raid) == "table" then
                if type(MSUF_DB.gf_raid) ~= "table" then
                    MSUF_DB.gf_raid = {}
                end
                MSUF_WipeTable(MSUF_DB.gf_raid)
                for kk, vv in pairs(payload.gf_raid) do
                    MSUF_DB.gf_raid[kk] = MSUF_DeepCopy(vv)
                end
            else
                MSUF_DB.gf_raid = MSUF_DeepCopy(payload.gf_raid)
            end
        end
        if payload.gf_mythicraid ~= nil then
            if type(payload.gf_mythicraid) == "table" then
                if type(MSUF_DB.gf_mythicraid) ~= "table" then
                    MSUF_DB.gf_mythicraid = {}
                end
                MSUF_WipeTable(MSUF_DB.gf_mythicraid)
                for kk, vv in pairs(payload.gf_mythicraid) do
                    MSUF_DB.gf_mythicraid[kk] = MSUF_DeepCopy(vv)
                end
            else
                MSUF_DB.gf_mythicraid = MSUF_DeepCopy(payload.gf_mythicraid)
            end
        end
        if payload.gf_priority ~= nil then
            if type(payload.gf_priority) == "table" then
                if type(MSUF_DB.gf_priority) ~= "table" then
                    MSUF_DB.gf_priority = {}
                end
                MSUF_WipeTable(MSUF_DB.gf_priority)
                for kk, vv in pairs(payload.gf_priority) do
                    MSUF_DB.gf_priority[kk] = MSUF_DeepCopy(vv)
                end
            else
                MSUF_DB.gf_priority = MSUF_DeepCopy(payload.gf_priority)
            end
        end
    elseif kind == "castbar" then
        MSUF_WipeGeneralSubset(function(key)
            return MSUF_IsCastbarKey(key) and (not MSUF_IsColorKey(key))
        end)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general)
        end
    elseif kind == "colors" then
        MSUF_WipeGeneralSubset(function(key)
            return MSUF_IsColorKey(key)
        end)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general)
        end
        if type(MSUF_DB.classColors) ~= "table" then MSUF_DB.classColors = {} end
        if type(MSUF_DB.npcColors) ~= "table" then MSUF_DB.npcColors = {} end
        MSUF_WipeTable(MSUF_DB.classColors)
        MSUF_WipeTable(MSUF_DB.npcColors)
        if type(payload.classColors) == "table" then
            for kk, vv in pairs(payload.classColors) do
                MSUF_DB.classColors[kk] = MSUF_DeepCopy(vv)
            end
        end
        if type(payload.npcColors) == "table" then
            for kk, vv in pairs(payload.npcColors) do
                MSUF_DB.npcColors[kk] = MSUF_DeepCopy(vv)
            end
        end
    elseif kind == "gameplay" then
        if type(MSUF_DB.gameplay) ~= "table" then MSUF_DB.gameplay = {} end
        MSUF_WipeTable(MSUF_DB.gameplay)
        if type(payload.gameplay) == "table" then
            for kk, vv in pairs(payload.gameplay) do
                MSUF_DB.gameplay[kk] = MSUF_DeepCopy(vv)
            end
        end
    elseif kind == "all" then
        MSUF_WipeTable(MSUF_DB)
        for kk, vv in pairs(payload) do
            MSUF_DB[kk] = MSUF_DeepCopy(vv)
        end
    else
         return false, "unknown kind"
    end
    --- Ensure the active profile table in GlobalDB points to MSUF_DB.
    if type(MSUF_GlobalDB) == "table" and type(MSUF_GlobalDB.profiles) == "table" and MSUF_ActiveProfile then
        MSUF_GlobalDB.profiles[MSUF_ActiveProfile] = MSUF_DB
    end
    MSUF_ProfileIO_RunEnsureDB(true)
    MSUF_ProfileIO_EnsureUnitframeAlphaDB()
    MSUF_ProfileIO_PostImportApply_Auras(snapshot.kind, payload)
    MSUF_ProfileIO_PostImportApply_GroupFrames(snapshot.kind, payload)
    MSUF_ProfileIO_PostImportApply_UnitAlphas(kind, payload)
    if type(payload.general) == "table"
        and type(payload.general.blizzardEditModeSnapshot) == "table" then
        MSUF_ProfileIO_CallGlobal("MSUF_BlizzardEditMode_ApplyProfileSnapshot")
    end
    MSUF_ProfileIO_PostProfileRuntimeApply("PROFILE_IMPORT", true)
    MSUF.ProfileIOCompleteFirstLoadImport()
     return true
end
function MSUF_ExportSelectionToString(kind)
    local snap = MSUF_SnapshotForKind(kind)
    if not snap then
         return nil
    end
    local exportSnap, wagoExport = MSUF_ProfileIO_MakeWagoSnapshot(snap)
    if wagoExport == true then
        local enc3 = _G.MSUF_EncodeCompactTableMSUF3
        if type(enc3) == "function" then
            local compact = enc3(exportSnap)
            if compact then
                 return compact
            end
        end
        return MSUF_SerializeLuaTable(exportSnap)
    end
    local enc = _G.MSUF_EncodeCompactTable
    if type(enc) == "function" then
        local compact = enc(snap)
        if compact then
             return compact
        end
    end
    --- 0-regression fallback
    return MSUF_SerializeLuaTable(snap)
end

local function MSUF_ApplyLegacyTableToActiveProfile(tbl)
    if type(tbl) ~= "table" then
        print("|cffff0000MSUF:|r Legacy import failed: not a table.")
        return false
    end
    local valid, validationError = MSUF.ProfileIOValidateImportValue(tbl)
    if not valid then
        print("|cffff0000MSUF:|r Legacy import failed: " .. tostring(validationError))
        return false
    end
    local prepared, staged = MSUF_ProfileIO_RunProtected("legacy import staging", function()
        local copy = MSUF_DeepCopy(tbl)
        MSUF_ProfileIO_TranslateProfileToCurrent(copy, {
            source = "legacy_import",
            markProfile = true,
        })
        return copy
    end)
    if not prepared or type(staged) ~= "table" then
        print("|cffff0000MSUF:|r Legacy import failed during staging: " .. tostring(staged))
        return false
    end
    tbl = staged
    if not MSUF_ProfileIO_ImportBlizzardEM and type(tbl.general) == "table" then
        tbl.general.blizzardEditModeSnapshot = nil
    end
    MSUF_ProfileIO_RunEnsureDB()
    MSUF_ProfileIO_CollectProfileMediaWarnings(tbl)
    --- Keep profile table reference stable; wipe + copy.
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    MSUF_WipeTable(MSUF_DB)
    for k, v in pairs(tbl) do
        MSUF_DB[k] = v
    end
    if type(MSUF_GlobalDB) == "table" and type(MSUF_GlobalDB.profiles) == "table" and MSUF_ActiveProfile then
        MSUF_GlobalDB.profiles[MSUF_ActiveProfile] = MSUF_DB
    end
    MSUF_ProfileIO_RunEnsureDB(true)
    MSUF.ProfileIOCompleteFirstLoadImport()
    MSUF_ProfileIO_EnsureUnitframeAlphaDB()
    MSUF_ProfileIO_PostImportApply_Auras("all", tbl)
    MSUF_ProfileIO_PostImportApply_GroupFrames("all", tbl)
    MSUF_ProfileIO_PostImportApply_UnitAlphas("all", tbl)
    MSUF_ProfileIO_PostProfileRuntimeApply("PROFILE_LEGACY_IMPORT", true)
    print("|cff00ff00MSUF:|r Legacy profile imported into the active profile.")
    MSUF_ProfileIO_ReportImportWarnings()
    return true
end
--- New import: understands snapshots (fmt=2) and applies selection into active profile.
--- New import: understands MSUF2/MSUF3/MSUF4 compact strings, snapshots (fmt=2), and legacy full dumps.
function MSUF_ImportFromString(str)
    MSUF_ProfileIO_ResetImportWarnings()
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Import failed (empty string).")
         return false
    end
    --- NEW: compact path (no loadstring)
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        local decoded = tryDec(str)
        if type(decoded) == "table" then
            local tbl = decoded
            --- Snapshot format?
            if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" and type(tbl.kind) == "string" then
                local okApply, why = MSUF_ApplySnapshotToActiveProfile(tbl)
                if okApply then
                    print("|cff00ff00MSUF:|r Imported " .. tostring(tbl.kind) .. " settings into the active profile.")
                    MSUF_ProfileIO_ReportImportWarnings()
                else
                    print("|cffff0000MSUF:|r Import failed: " .. tostring(why))
                end
                 return okApply == true
            end
            --- Otherwise treat decoded table as legacy full-profile dump.
            return MSUF_ApplyLegacyTableToActiveProfile(tbl)
        end
    end
    --- If this looks like a compact MSUF2/MSUF3/MSUF4 string, NEVER attempt loadstring.
    local prefix = str:match("^%s*(MSUF%d+):")
    if prefix == "MSUF2" or prefix == "MSUF3" or prefix == "MSUF4" then
        print("|cffff0000MSUF:|r Import failed: could not decode compact profile string (" .. prefix .. ").")
         return false
    end
    --- OLD PATH (Lua table string)
    local func, err = MSUF_ProfileIO_LoadLegacyChunk(str)
    if not func then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(err))
         return false
    end
    -- LoadLegacyChunk wraps a sandboxed literal parser that reports failure by
    -- returning nil plus a reason; it does not raise.
    local tbl = func()
    if type(tbl) ~= "table" then
        print("|cffff0000MSUF:|r Import failed: not a table.")
         return false
    end
    --- Snapshot format?
    if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" and type(tbl.kind) == "string" then
        local okApply, why = MSUF_ApplySnapshotToActiveProfile(tbl)
        if okApply then
            print("|cff00ff00MSUF:|r Imported " .. tostring(tbl.kind) .. " settings into the active profile.")
            MSUF_ProfileIO_ReportImportWarnings()
        else
            print("|cffff0000MSUF:|r Import failed: " .. tostring(why))
        end
         return okApply == true
    end
    --- Otherwise treat it as legacy full-profile dump.
    return MSUF_ApplyLegacyTableToActiveProfile(tbl)
 end
--- Legacy import: replaces the entire ACTIVE profile with the provided table.
function MSUF_ImportLegacyFromString(str)
    MSUF_ProfileIO_ResetImportWarnings()
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Legacy import failed (empty string).")
         return false
    end
    local function ImportDecodedLegacyTable(tbl)
        if type(tbl) == "table" and tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" then
            tbl = MSUF_ProfileIO_SelectWagoFullSnapshot(tbl)
            local kind = (tbl.kind == "groupframes") and "groupframe" or tbl.kind
            if kind == "all" then
                return MSUF_ApplyLegacyTableToActiveProfile(tbl.payload)
            end
            local okApply, why = MSUF_ApplySnapshotToActiveProfile(tbl)
            if okApply then
                print("|cff00ff00MSUF:|r Imported " .. tostring(tbl.kind) .. " settings into the active profile.")
                MSUF_ProfileIO_ReportImportWarnings()
            else
                print("|cffff0000MSUF:|r Legacy import failed: " .. tostring(why))
            end
            return okApply
        end
        return MSUF_ApplyLegacyTableToActiveProfile(tbl)
    end
    --- NEW: allow MSUF2: strings in legacy import
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        local decoded = tryDec(str)
        if type(decoded) == "table" then
            return ImportDecodedLegacyTable(decoded)
        end
    end
    --- If this looks like a compact MSUF2/MSUF3/MSUF4 string, NEVER attempt loadstring.
    local prefix = str:match("^%s*(MSUF%d+):")
    if prefix == "MSUF2" or prefix == "MSUF3" or prefix == "MSUF4" then
        print("|cffff0000MSUF:|r Legacy import failed: could not decode compact profile string (" .. prefix .. ").")
         return false
    end
    local func, err = MSUF_ProfileIO_LoadLegacyChunk(str)
    if not func then
        print("|cffff0000MSUF:|r Legacy import failed: " .. tostring(err))
         return false
    end
    return ImportDecodedLegacyTable(func())
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
local function MSUF_ProfileIO_EnsureProfilesTable()
    if not MSUF_GlobalDB or type(MSUF_GlobalDB) ~= "table" then
        MSUF_GlobalDB = {}
    end
    if type(MSUF_GlobalDB.profiles) ~= "table" then
        MSUF_GlobalDB.profiles = {}
    end
 end
local function MSUF_ProfileIO_EnsureProfileSystemInitialized()
    MSUF_ProfileIO_RunEnsureDB()
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    local active = MSUF_ActiveProfile
    local needsInit = type(active) ~= "string"
        or active == ""
        or type(MSUF_DB) ~= "table"
        or type(profiles[active]) ~= "table"
    if needsInit and type(MSUF_InitProfiles) == "function" then
        MSUF_InitProfiles()
    elseif MSUF_ProfileIO_TranslateProfilesToCurrent then
        MSUF_ProfileIO_TranslateProfilesToCurrent(profiles, "external_api")
    end
end
local function MSUF_ProfileIO_GetProfileTable(profileKey)
    if type(profileKey) ~= "string" or profileKey == "" then
         return nil
    end
    MSUF_ProfileIO_EnsureProfileSystemInitialized()
    MSUF_ProfileIO_EnsureProfilesTable()
    return MSUF_GlobalDB.profiles[profileKey]
end
local function MSUF_ProfileIO_WithTemporaryProfileDB(profile, fn)
    if type(profile) ~= "table" or type(fn) ~= "function" then
        return false, "invalid temporary profile"
    end
    local oldDB = MSUF_DB
    local auras3 = MSUF and MSUF.MSUF_Auras3
    local oldAuras3DBRef = type(auras3) == "table" and auras3.DBRef or nil
    local oldSuppressRuntimeSideEffects = _G.MSUF_ProfileIO_SuppressRuntimeSideEffects
    ExportPublic("MSUF_ProfileIO_SuppressRuntimeSideEffects", true)
    MSUF_DB = profile

    -- This is a real transaction boundary: every exit path must restore the
    -- active DB pointer and subsystem references before an error is reported.
    local runOK, result = pcall(fn)

    MSUF_DB = oldDB
    ExportPublic("MSUF_ProfileIO_SuppressRuntimeSideEffects", oldSuppressRuntimeSideEffects)
    if type(auras3) == "table" then
        auras3.DBRef = oldAuras3DBRef
    end

    local cacheOK, cacheError = true, nil
    local invalidateGF = _G.MSUF_GF_InvalidateConfCache
    if type(invalidateGF) == "function" then
        cacheOK, cacheError = MSUF_ProfileIO_RunProtected("GF.InvalidateConfCache", invalidateGF)
    else
        local gf = MSUF and MSUF.GF
        if gf and type(gf.InvalidateConfCache) == "function" then
            cacheOK, cacheError = MSUF_ProfileIO_RunProtected("GF.InvalidateConfCache", gf.InvalidateConfCache)
        end
    end

    if not runOK then
        MSUF_ProfileIO_ReportBoundaryError("temporary profile materialization", result)
        return false, result
    end
    if not cacheOK then return false, cacheError end
    return true, result
end
local function MSUF_ProfileIO_MaterializeProfileCopyForExport(profile, profileKey)
    if type(profile) ~= "table" then
        return nil, "not a table"
    end
    MSUF_ProfileIO_TranslateProfileToCurrent(profile, {
        source = "external_export",
        markProfile = true,
        trustNormalizationMarker = true,
    })
    if type(_G.MSUF_NormalizePortraitRenderDB) == "function" then
        _G.MSUF_NormalizePortraitRenderDB(profile)
    end
    local materialized, why = MSUF_ProfileIO_WithTemporaryProfileDB(profile, function()
        --- The exported table is a private copy. Let Defaults use its persisted
        --- revision fast path; missing/stale revisions still run the full pass.
        MSUF_ProfileIO_RunEnsureDB(false, true, true)
        MSUF_ProfileIO_EnsureUnitframeAlphaDB()
        MSUF_ProfileIO_EnsureGroupFramesDB()
        local auras = MSUF and MSUF.MSUF_Auras3
        if auras then
            if type(auras.EnsureDB) == "function" then
                auras.EnsureDB()
            end
            local aurasDB = auras.DB
            if aurasDB and type(aurasDB.Ensure) == "function" then
                aurasDB.Ensure()
            end
        end
    end)
    if not materialized then
        ExportPublic("MSUF_ProfileIO_LastExportMaterializeError", tostring(profileKey or "profile") .. ": " .. tostring(why))
        return nil, "profile materialization failed: " .. tostring(why)
    end
    return profile
end
local function MSUF_ProfileIO_OverwriteProfile(profileKey, newTable)
    if type(profileKey) ~= "string" or profileKey == "" then
         return false, "invalid profileKey"
    end
    if type(newTable) ~= "table" then
         return false, "not a table"
    end
    local valid, validationError = MSUF.ProfileIOValidateImportValue(newTable)
    if not valid then return false, validationError end
    local prepared, staged = MSUF_ProfileIO_RunProtected("external import staging", function()
        local copy = MSUF_DeepCopy(newTable)
        MSUF_ProfileIO_TranslateProfileToCurrent(copy, {
            source = "external_import",
            markProfile = true,
        })
        if type(_G.MSUF_NormalizePortraitRenderDB) == "function" then
            _G.MSUF_NormalizePortraitRenderDB(copy)
        end
        if type(_G.MSUF_MigrateDispelPriorityProfile) == "function" then
            _G.MSUF_MigrateDispelPriorityProfile(copy, true)
        end
        return copy
    end)
    if not prepared or type(staged) ~= "table" then
        return false, "profile staging failed: " .. tostring(staged)
    end
    newTable = staged
    MSUF_ProfileIO_CollectProfileMediaWarnings(newTable)
    MSUF_ProfileIO_EnsureProfileSystemInitialized()
    MSUF_ProfileIO_EnsureProfilesTable()
    local existing = MSUF_GlobalDB.profiles[profileKey]
    local isActive = (profileKey == MSUF_ActiveProfile)
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
        MSUF_GlobalDB.profiles[profileKey] = target
        MSUF_ProfileIO_RunEnsureDB(true)
        MSUF.ProfileIOCompleteFirstLoadImport()
        MSUF_ProfileIO_EnsureUnitframeAlphaDB()
        MSUF_ProfileIO_PostImportApply_Auras("all", target)
        MSUF_ProfileIO_PostImportApply_GroupFrames("all", target)
        MSUF_ProfileIO_PostImportApply_UnitAlphas("all", target)
        MSUF_ProfileIO_PostProfileRuntimeApply("PROFILE_EXTERNAL_IMPORT", true)
        MSUF_ProfileIO_ReportImportWarnings()
        return true
    end
    if type(existing) == "table" then
        --- For non-active profiles we can still preserve reference stability if something else points at it.
        MSUF_WipeTable(existing)
        for k, v in pairs(newTable) do
            existing[k] = v
        end
        MSUF_GlobalDB.profiles[profileKey] = existing
        MSUF_ProfileIO_ReportImportWarnings()
        MSUF.ProfileIOCompleteFirstLoadImport()
        return true
    end
    local stored = {}
    for k, v in pairs(newTable) do
        stored[k] = v
    end
    MSUF_GlobalDB.profiles[profileKey] = stored
    MSUF_ProfileIO_ReportImportWarnings()
    MSUF.ProfileIOCompleteFirstLoadImport()
    return true
end
function MSUF_ExportExternal(profileKey)
    local profileTbl = MSUF_ProfileIO_GetProfileTable(profileKey)
    if type(profileTbl) ~= "table" then
         return false, "unknown profileKey"
    end
    local payload
    if profileKey == MSUF_ActiveProfile then
        MSUF_ProfileIO_EnsureCompleteProfileDB()
        profileTbl = MSUF_DB
        payload = MSUF_DeepCopy(profileTbl)
    else
        payload = MSUF_DeepCopy(profileTbl)
        local materialized, why = MSUF_ProfileIO_MaterializeProfileCopyForExport(payload, profileKey)
        if type(materialized) ~= "table" then
            return false, tostring(why or "profile materialization failed")
        end
        payload = materialized
    end
    local snap = {
        addon   = "MSUF",
        fmt     = 2,
        schema  = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
        kind    = "all",
        profile = profileKey,
        payload = MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload),
    }
    local exportSnap = MSUF_ProfileIO_MakeWagoSnapshot(snap)
    local enc = _G.MSUF_EncodeCompactTableMSUF3
    if type(enc) == "function" then
        local compact = enc(exportSnap)
        if type(compact) == "string" and compact:match("%S") then
             return true, compact
        end
    end
    --- 0-regression fallback (rare): return Lua snapshot.
    return true, MSUF_SerializeLuaTable(exportSnap)
end
function MSUF_ImportExternal(profileString, profileKey)
    MSUF_ProfileIO_ResetImportWarnings()
    if type(profileString) ~= "string" or not profileString:match("%S") then
         return false, "empty profileString"
    end
    if type(profileKey) ~= "string" or profileKey == "" then
         return false, "invalid profileKey"
    end
    --- Prefer compact decode (no loadstring).
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        local decoded = tryDec(profileString)
        if type(decoded) == "table" then
            local tbl = decoded
            --- Snapshot format? (fmt=2)
            if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" and type(tbl.kind) == "string" then
                tbl = MSUF_ProfileIO_SelectWagoFullSnapshot(tbl)
                --- For external import we treat snapshot.payload as the full profile table when kind == "all".
                if tbl.kind == "all" then
                    return MSUF_ProfileIO_OverwriteProfile(profileKey, tbl.payload)
                end
                --- If some tool ever passes a partial snapshot, store the whole decoded table as-is (safer than half-applying).
                return MSUF_ProfileIO_OverwriteProfile(profileKey, tbl)
            end
            --- Otherwise treat decoded table as a full profile dump.
            return MSUF_ProfileIO_OverwriteProfile(profileKey, tbl)
        end
    end
    --- If it looks like a compact MSUF2/MSUF3/MSUF4 string, but decode failed, do NOT loadstring it.
    local prefix = profileString:match("^%s*(MSUF%d+):")
    if prefix == "MSUF2" or prefix == "MSUF3" or prefix == "MSUF4" then
        return false, "could not decode compact profile string (" .. tostring(prefix) .. ")"
    end
    --- Optional legacy table-string support (last resort).
    local func = MSUF_ProfileIO_LoadLegacyChunk(profileString)
    if not func then
         return false, "invalid lua table string"
    end
    local tbl = func()
    if type(tbl) ~= "table" then
         return false, "lua decode failed"
    end
    if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" and type(tbl.kind) == "string" then
        tbl = MSUF_ProfileIO_SelectWagoFullSnapshot(tbl)
        if tbl.kind == "all" then
            return MSUF_ProfileIO_OverwriteProfile(profileKey, tbl.payload)
        end
        return MSUF_ProfileIO_OverwriteProfile(profileKey, tbl)
    end
    return MSUF_ProfileIO_OverwriteProfile(profileKey, tbl)
end
--- Expose real implementations under stable, explicit names for load-order proxies.
ExportPublic("MSUF_Profiles_ExportExternal", MSUF_ExportExternal)
ExportPublic("MSUF_Profiles_ImportExternal", MSUF_ImportExternal)
--- Globals for the Options module.
ExportPublic("MSUF_ExportSelectionToString", MSUF_ExportSelectionToString)
ExportPublic("MSUF_ImportFromString", MSUF_ImportFromString)
ExportPublic("MSUF_ImportLegacyFromString", MSUF_ImportLegacyFromString)
--- Always expose the real implementations under stable, explicit names.
--- This lets other modules (or load-order proxies) call the correct logic even if _G.MSUF_ImportFromString was set earlier.
ExportPublic("MSUF_Profiles_ExportSelectionToString", MSUF_ExportSelectionToString)
ExportPublic("MSUF_Profiles_ImportFromString", MSUF_ImportFromString)
ExportPublic("MSUF_Profiles_ImportLegacyFromString", MSUF_ImportLegacyFromString)
ExportPublic("MSUF_ProfileIO_TranslateProfileToCurrent", MSUF_ProfileIO_TranslateProfileToCurrent)
ExportPublic("MSUF_ProfileIO_TranslateProfilesToCurrent", MSUF_ProfileIO_TranslateProfilesToCurrent)
ExportPublic("MSUF_CreateProfile", MSUF_CreateProfile)
ExportPublic("MSUF_SwitchProfile", MSUF_SwitchProfile)
ExportPublic("MSUF_ResetProfile", MSUF_ResetProfile)
ExportPublic("MSUF_DeleteProfile", MSUF_DeleteProfile)
ExportPublic("MSUF_CopyProfile", MSUF_CopyProfile)
ExportPublic("MSUF_RenameProfile", MSUF_RenameProfile)
ExportPublic("MSUF_GetAllProfiles", MSUF_GetAllProfiles)
if type(MSUF) == "table" then
    MSUF.MSUF_ExportSelectionToString = MSUF_ExportSelectionToString
    MSUF.MSUF_ImportFromString        = MSUF_ImportFromString
    MSUF.MSUF_ImportLegacyFromString  = MSUF_ImportLegacyFromString
    MSUF.MSUF_ProfileIO_TranslateProfileToCurrent = MSUF_ProfileIO_TranslateProfileToCurrent
    MSUF.MSUF_ProfileIO_TranslateProfilesToCurrent = MSUF_ProfileIO_TranslateProfilesToCurrent
end
