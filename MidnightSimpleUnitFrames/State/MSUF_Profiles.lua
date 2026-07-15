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
local function MSUF_ProfileIO_RunProtected(label, fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        ExportPublic("MSUF_ProfileIO_LastRuntimeApplyError", tostring(label or "runtime") .. ": " .. tostring(result))
        return false
    end
    return true, result
end

-- Profile imports can enter through Menu2, legacy globals, or the external
-- Wago API. Complete first-load at the shared mutation boundary so every
-- successful path records the same durable lifecycle result.
function MSUF.ProfileIOCompleteFirstLoadImport()
    local firstLoad = MSUF and MSUF.FirstLoad6
    if type(firstLoad) ~= "table" or type(firstLoad.CompleteProfileImport) ~= "function" then
        return false
    end
    local ok, completed = pcall(firstLoad.CompleteProfileImport, firstLoad, "import")
    if not ok then return false end
    if completed == true then
        local menu = MSUF and MSUF.MSUF2
        if type(menu) == "table" and type(menu.InvalidatePage) == "function" then
            menu.InvalidatePage("home")
        end
    end
    return completed == true
end
function MSUF.ProfileIOIsUUFAddonLoaded()
    if _G.C_AddOns and type(_G.C_AddOns.IsAddOnLoaded) == "function" then
        return _G.C_AddOns.IsAddOnLoaded("UnhaltedUnitFrames") == true
    end
    if type(_G.IsAddOnLoaded) == "function" then
        return _G.IsAddOnLoaded("UnhaltedUnitFrames") == true
    end
    return type(_G.UUF) == "table"
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
    elseif scale > 1.5 then
        scale = 1.5
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

--- UUF imports may carry absolute positions from another addon. If we keep the
--- old MSUF screen-position cache around, a converted import can look correct in
--- the DB but render at the previous cached coordinates.
local function MSUF_ProfileIO_ClearUUFUnitFrameScreenCache()
    local bucketFn = _G.MSUF_GetUnitFrameScreenCacheBucket
    local keyFn = _G.MSUF_GetUnitFrameScreenCacheKey
    if type(bucketFn) ~= "function" or type(keyFn) ~= "function" then
        return false
    end
    local bucket = bucketFn()
    if type(bucket) ~= "table" then
        return false
    end
    local units = { "player", "target", "targettarget", "focus", "focustarget", "pet" }
    for i = 1, #units do
        local unit = units[i]
        local id = keyFn(unit, unit)
        if id then bucket[id] = nil end
    end
    for i = 1, 5 do
        local unit = "boss" .. i
        local id = keyFn("boss", unit)
        if id then bucket[id] = nil end
    end
    return true
end
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
    --- Group-frame config tables are cached by identity. Drop those references
    --- before the runtime rebuild reads the newly active profile root.
    MSUF_ProfileIO_CallGlobal("MSUF_GF_InvalidateConfCache")

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
    local function TryBlizzardDecompress(E, compressed)
        if not E or type(compressed) ~= "string" then  return nil end
        if #compressed > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        if type(E.DecompressString) ~= "function" then  return nil end
        local method = GetDeflateEnum()
        local ok, res
        if method ~= nil then
            ok, res = pcall(E.DecompressString, compressed, method)
            if ok and type(res) == "string" and #res <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return res end
        end
        ok, res = pcall(E.DecompressString, compressed)
        if ok and type(res) == "string" and #res <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return res end
         return nil
    end
    local function GetLibDeflate()
        if _G.LibDeflate and type(_G.LibDeflate.DecompressDeflate) == "function" then
            return _G.LibDeflate
        end
        local libStub = _G.LibStub
        if libStub and type(libStub.GetLibrary) == "function" then
            local ok, lib = pcall(libStub.GetLibrary, libStub, "LibDeflate", true)
            if ok and lib and type(lib.DecompressDeflate) == "function" then
                return lib
            end
        end
        return nil
    end
    local function TryLibDeflateDecompress(compressed)
        local lib = GetLibDeflate()
        if not lib or type(compressed) ~= "string" then return nil end
        if #compressed > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        local ok, plain = pcall(lib.DecompressDeflate, lib, compressed)
        if ok and type(plain) == "string" and #plain <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return plain end
        return nil
    end
    local function TryDeserializeMaybeCompressed(E, payload)
        if type(payload) ~= "string" then return nil end
        if #payload > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        local plain = TryBlizzardDecompress(E, payload)
        local t = TryDeserialize(E, plain or payload)
        if t then return t end
        local libPlain = TryLibDeflateDecompress(payload)
        if libPlain and libPlain ~= plain then
            t = TryDeserialize(E, libPlain)
            if t then return t end
        end
        if plain then
            return TryDeserialize(E, payload)
        end
        return nil
    end
    local function TryBlizzardCompress(E, plain)
        if not E or type(plain) ~= "string" then  return nil end
        if type(E.CompressString) ~= "function" then
             return nil
        end
        local method = GetDeflateEnum()
        local ok, res
        if method ~= nil then
            ok, res = pcall(E.CompressString, plain, method, 9)
            if ok and type(res) == "string" then  return res end
            ok, res = pcall(E.CompressString, plain, method)
            if ok and type(res) == "string" then  return res end
        end
        ok, res = pcall(E.CompressString, plain)
        if ok and type(res) == "string" then  return res end
         return nil
    end
    TryDeserialize = function(E, payload)
        if not E or type(payload) ~= "string" then  return nil end
        if #payload > MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return nil end
        --- 1) CBOR via Blizzard
        local ok, tbl = pcall(E.DeserializeCBOR, payload)
        if ok and type(tbl) == "table" then
             return tbl
        end
        --- 2) AceSerializer (optional, if present)
        if _G.LibStub and type(_G.LibStub.GetLibrary) == "function" then
            local Ace = _G.LibStub:GetLibrary("AceSerializer-3.0", true)
            if Ace and type(Ace.Deserialize) == "function" then
                local ok2, success, t = pcall(Ace.Deserialize, payload)
                if ok2 and success and type(t) == "table" then
                     return t
                end
            end
        end
        --- 3) Very old MSUF legacy may have stored a Lua table literal.
        --- Only attempt if it looks like a table (avoid executing arbitrary code).
        local trimmed = payload:match("^%s*(.-)%s*$")
        if trimmed and trimmed:sub(1,1) == "{" and trimmed:sub(-1) == "}" then
            local fn = MSUF_ProfileIO_LoadLegacyChunk(trimmed)
            if fn then
                local ok3, t = pcall(fn)
                if ok3 and type(t) == "table" then
                     return t
                end
            end
        end
         return nil
    end
    local function IsSecretRuntimeValue(value)
        local isSecret = _G.issecretvalue
        if type(isSecret) ~= "function" then
            return false
        end
        local ok, secret = pcall(isSecret, value)
        return ok and secret == true
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
        local ok1, bin = pcall(E.SerializeCBOR, tbl)
        if not ok1 or type(bin) ~= "string" then  return nil end
        --- Prefer smaller strings when compression exists.
        local payload = TryBlizzardCompress(E, bin) or bin
        local ok2, b64 = pcall(E.EncodeBase64, payload)
        if not ok2 or type(b64) ~= "string" then  return nil end
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
                local ok1, blob = pcall(E.DecodeBase64, b64)
                if ok1 and type(blob) == "string" then
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
                local ok1, blob = pcall(E.DecodeBase64, b64)
                if ok1 and type(blob) == "string" then
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
            --- 3) Hard fallback: if LibDeflate is available (from another addon), try it.
            local ld = _G.LibDeflate
            if ld and type(ld.DecodeForPrint) == "function" and type(ld.DecompressDeflate) == "function" then
                local okDec, raw = pcall(ld.DecodeForPrint, ld, payload)
                if okDec and type(raw) == "string" and #raw <= MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then
                    local okDecomp, plain = pcall(ld.DecompressDeflate, ld, raw)
                    if okDecomp and type(plain) == "string" and #plain <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then
                        local t = TryDeserialize(E, plain)
                        if t then  return t end
                    else
                        local t = TryDeserialize(E, raw)
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
local function MSUF_ProfileIO_FirstProfileTable(profiles)
    for _, tbl in pairs(profiles) do
        if type(tbl) == "table" then
            return tbl
        end
    end
    return nil
end
local function MSUF_ProfileIO_EnsureProfileMenuDefaults(profile)
    if type(profile) ~= "table" then return end
    if type(profile.general) ~= "table" then
        profile.general = {}
    end
    if profile.general.navHoverScale == nil then
        profile.general.navHoverScale = 1.05
    end
    if profile.general.showGameMenuButton == nil then
        profile.general.showGameMenuButton = true
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
        active = "Default"
    end
    if type(profiles[active]) ~= "table" then
        local fallback = MSUF_ProfileIO_FirstProfileTable(profiles)
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
    profiles[name] = CopyTable(type(MSUF_DB) == "table" and MSUF_DB or {})
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
    if MSUF.ProfileIOIsUUFAddonLoaded() then
        ExportPublic("MSUF_ProfileIO_LastImportDeferredRuntime", true)
    else
        MSUF_ProfileIO_PostProfileRuntimeApply("PROFILE_SWITCH", false)
    end
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
    local ok, applied = pcall(probe.SetTexture, probe, path)
    if not ok or applied == false then
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
    "detachedPowerBarTexture",
    "detachedPowerBarBgTexture",
    "playerHPBarTexture",
    "playerHPBarBgTexture",
}

local MSUF_PROFILEIO_UNIT_TEXTURE_WARNING_KEYS = {
    "barTexture",
    "barBackgroundTexture",
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
    classificationIndicatorSize = 12,
    statusIndicatorSize = 14,
    statusTextSize = 14,
    statusGhostTextSize = 14,
    statusAFKTextSize = 14,
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
local function MSUF_ProfileIO_NormalizeUnitFramePositionDB(profile, legacyProfile)
    if type(profile) ~= "table" then return profile end

    local nested = (type(profile.unitframes) == "table" and profile.unitframes)
        or (type(profile.unitFrames) == "table" and profile.unitFrames)
        or nil
    if nested and (type(nested.player) == "table" or type(nested.target) == "table") then
        for i = 1, #MSUF_PROFILEIO_UNIT_KEYS do
            local key = MSUF_PROFILEIO_UNIT_KEYS[i]
            if type(profile[key]) ~= "table" and type(nested[key]) == "table" then
                profile[key] = MSUF_DeepCopy(nested[key])
            end
        end
        if type(profile.targettarget) ~= "table" then
            local tot = nested.targettarget or nested.tot or nested.targetoftarget
            if type(tot) == "table" then profile.targettarget = MSUF_DeepCopy(tot) end
        end
    end

    local function CopyAlias(fromKey, toKey)
        if type(profile[toKey]) ~= "table" and type(profile[fromKey]) == "table" then
            profile[toKey] = MSUF_DeepCopy(profile[fromKey])
        end
    end

    local function PromoteLegacyAlias(toKey, ...)
        if legacyProfile ~= true then return end
        local current = profile[toKey]
        local best
        for i = 1, select("#", ...) do
            local alias = profile[select(i, ...)]
            if type(alias) == "table" and (best == nil or (alias.enabled == true and best.enabled ~= true)) then
                best = alias
            end
        end
        if type(best) == "table" and (type(current) ~= "table" or (best.enabled == true and current.enabled ~= true)) then
            profile[toKey] = MSUF_DeepCopy(best)
        end
    end

    PromoteLegacyAlias("targettarget", "tot", "targetoftarget")
    PromoteLegacyAlias("focustarget", "focus_target", "focustargettarget")
    CopyAlias("tot", "targettarget")
    CopyAlias("targetoftarget", "targettarget")
    CopyAlias("focus_target", "focustarget")
    CopyAlias("focustargettarget", "focustarget")
    if type(profile.boss) ~= "table" then
        for i = 1, 5 do
            local boss = profile["boss" .. i]
            if type(boss) == "table" then
                profile.boss = MSUF_DeepCopy(boss)
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
    NormalizeUnit(profile.tot)
    NormalizeUnit(profile.targetoftarget)
    NormalizeUnit(profile.focus_target)
    NormalizeUnit(profile.focustargettarget)
    for i = 1, 5 do
        NormalizeUnit(profile["boss" .. i])
    end
    return profile
end

local MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA = 600
local MSUF_PROFILEIO_LEGACY_PROFILE_SCHEMA_56 = 560
--- This revision describes the normalization performed by
--- MSUF_ProfileIO_TranslateProfileToCurrent, independently from the broad
--- default-fill revision owned by MSUF_Defaults.lua. Bump it whenever that
--- translation pipeline gains a new mandatory repair.
local MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION = 5
local MSUF_PROFILEIO_TEXT_SCOPE_KEYS = {
    "general",
    "player", "target", "targettarget", "tot", "targetoftarget",
    "focus", "focustarget", "focus_target", "focustargettarget",
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
    "eliteIcon",
    "statusText",
    "combatStateIndicator",
    "restedStateIndicator",
    "restingStateIndicator",
    "incomingResIndicator",
    "pvpIndicator",
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
    buffGroupIconSize = { 1, 256 },
    debuffGroupIconSize = { 1, 256 },
    privateSize = { 1, 256 },
    spacing = { 0, 128 },
    splitSpacing = { 0, 256 },
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

local MSUF_PROFILEIO_A2_AURA_FRAME_DEFAULT_SIZE = {
    player = { 275, 40 },
    target = { 276, 40 },
    focus = { 216, 30 },
    targettarget = { 170, 36 },
    focustarget = { 170, 30 },
    boss = { 264, 35 },
}

local function MSUF_ProfileIO_A2AuraFrameKey(unit)
    if unit == "tot" or unit == "targetoftarget" then return "targettarget" end
    if unit == "focus_target" or unit == "focustargettarget" then return "focustarget" end
    if type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    return unit
end

local function MSUF_ProfileIO_A2AuraFrameSize(profile, unit)
    local key = MSUF_ProfileIO_A2AuraFrameKey(unit)
    local conf = type(profile) == "table" and type(profile[key]) == "table" and profile[key] or nil
    local defaults = MSUF_PROFILEIO_A2_AURA_FRAME_DEFAULT_SIZE[key] or MSUF_PROFILEIO_A2_AURA_FRAME_DEFAULT_SIZE.player
    local width = MSUF_ProfileIO_ToNumber(conf and (conf.width or conf.frameWidth)) or defaults[1]
    local height = MSUF_ProfileIO_ToNumber(conf and (conf.height or conf.frameHeight)) or defaults[2]
    if width < 1 then width = defaults[1] end
    if height < 1 then height = defaults[2] end
    return width, height
end

local function MSUF_ProfileIO_A2AuraReadNumber(primary, secondary, key, fallback)
    local n = type(primary) == "table" and MSUF_ProfileIO_ToNumber(primary[key]) or nil
    if n ~= nil then return n end
    n = type(secondary) == "table" and MSUF_ProfileIO_ToNumber(secondary[key]) or nil
    if n ~= nil then return n end
    return fallback or 0
end

local function MSUF_ProfileIO_ConvertLegacyAuras2Geometry(auras, profile)
    if type(auras) ~= "table" or auras._msufAuras3LegacyGeometry_v3 == true then return false end
    local shared = type(auras.shared) == "table" and auras.shared or {}
    auras.shared = shared
    local repairV1 = auras._msufAuras3LegacyGeometry_v1 == true
    local repairV2 = auras._msufAuras3LegacyGeometry_v2 == true
    local changed = false

    local function ReadRaw(primary, secondary, ...)
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            local value = type(primary) == "table" and primary[key] or nil
            if value ~= nil then return value end
            value = type(secondary) == "table" and secondary[key] or nil
            if value ~= nil then return value end
        end
        return nil
    end

    local function GrowthParts(value, wrap)
        value = tostring(value or "RIGHT"):upper()
        wrap = tostring(wrap or "DOWN"):upper()
        local combined = MSUF_PROFILEIO_AURA_GROWTH_PARTS[value]
        if combined then
            value = combined[1]
            wrap = combined[2] or wrap
        end
        if value ~= "LEFT" and value ~= "UP" and value ~= "DOWN" then value = "RIGHT" end
        if wrap ~= "UP" then wrap = "DOWN" end
        if value == "LEFT" then return -1, wrap == "UP" and 1 or -1, false end
        if value == "UP" then return 1, 1, true end
        if value == "DOWN" then return 1, -1, true end
        return 1, wrap == "UP" and 1 or -1, false
    end

    local function InitialAnchor(xSign, ySign)
        return (ySign > 0 and "BOTTOM" or "TOP") .. (xSign > 0 and "LEFT" or "RIGHT")
    end

    local function LegacyFirstIconAnchor(growth)
        growth = tostring(growth or "RIGHT"):upper()
        local combined = MSUF_PROFILEIO_AURA_GROWTH_PARTS[growth]
        if combined then growth = combined[1] end
        if growth == "LEFT" then return "BOTTOMRIGHT" end
        if growth == "DOWN" then return "TOPLEFT" end
        return "BOTTOMLEFT"
    end

    local function ConvertScope(unit, unitCfg, existedBeforeV3)
        if type(unitCfg) ~= "table" then return end
        local layout = type(unitCfg.layout) == "table" and unitCfg.layout or {}
        unitCfg.layout = layout
        local effectiveLayout = unitCfg.overrideLayout == true and layout or nil
        local layoutShared = unitCfg.overrideSharedLayout == true and type(unitCfg.layoutShared) == "table"
            and unitCfg.layoutShared or nil
        local width, height = MSUF_ProfileIO_A2AuraFrameSize(profile, unit)
        local baseX = MSUF_ProfileIO_A2AuraReadNumber(effectiveLayout, shared, "offsetX", 0)
        local baseY = MSUF_ProfileIO_A2AuraReadNumber(effectiveLayout, shared, "offsetY", 0)

        local function ReadLaneNumber(primary, secondary, key, aliasKey, fallback)
            local n = type(primary) == "table" and MSUF_ProfileIO_ToNumber(primary[key]) or nil
            if n ~= nil then return n end
            n = type(primary) == "table" and MSUF_ProfileIO_ToNumber(primary[aliasKey]) or nil
            if n ~= nil then return n end
            n = type(secondary) == "table" and MSUF_ProfileIO_ToNumber(secondary[key]) or nil
            if n ~= nil then return n end
            n = type(secondary) == "table" and MSUF_ProfileIO_ToNumber(secondary[aliasKey]) or nil
            if n ~= nil then return n end
            return fallback or 0
        end

        local function ConvertLane(kind, xKey, yKey, anchorKey, legacyXKey, legacyYKey)
            local originX
            local originY
            if repairV2 and existedBeforeV3 then
                -- v2 stored the old Aura2 container's BOTTOMLEFT origin. It
                -- still anchored Auras3's full-capacity lane there, which is
                -- why LEFT/UP and RIGHT/DOWN profiles drifted by whole rows.
                originX = ReadLaneNumber(layout, nil, xKey, legacyXKey, 0)
                originY = ReadLaneNumber(layout, nil, yKey, legacyYKey, 0)
            elseif repairV1 and existedBeforeV3 then
                local x = ReadLaneNumber(layout, nil, xKey, legacyXKey, 0)
                local y = ReadLaneNumber(layout, nil, yKey, legacyYKey, 0)
                local oldAnchor = tostring(layout[anchorKey] or ""):upper()
                if oldAnchor == "TOPRIGHT" or oldAnchor == "BOTTOMRIGHT" then
                    x = x + width
                end
                if oldAnchor == "TOPLEFT" or oldAnchor == "TOPRIGHT" then
                    y = y + height
                end
                originX, originY = x, y
            else
                originX = baseX + ReadLaneNumber(effectiveLayout, shared, xKey, legacyXKey, 0)
                originY = height + baseY + ReadLaneNumber(effectiveLayout, shared, yKey, legacyYKey, 0)
            end

            local growth = ReadRaw(layoutShared, shared, kind .. "GrowthX", kind .. "Growth", "growth") or "RIGHT"
            local wrap = ReadRaw(layoutShared, shared, kind .. "GrowthY", kind .. "RowWrap", "rowWrap") or "DOWN"
            local xSign, ySign = GrowthParts(growth, wrap)
            local anchor = InitialAnchor(xSign, ySign)
            local oldIconAnchor = LegacyFirstIconAnchor(growth)
            local size = MSUF_ProfileIO_ToNumber(ReadRaw(effectiveLayout, shared,
                kind .. "GroupIconSize", kind .. "IconSize", "iconSize")) or 26
            if size < 1 then size = 26 end

            -- Preserve the first Aura2 icon's rectangle, not the old empty
            -- container origin. Auras3 anchors a full-capacity layout host, so
            -- TOP/RIGHT anchors must be expressed relative to that host's far
            -- edge while keeping the first icon pixel-identical.
            local oldLeft = originX - (oldIconAnchor:find("RIGHT", 1, true) and size or 0)
            local oldBottom = originY - (oldIconAnchor:find("TOP", 1, true) and size or 0)
            local absoluteAnchorX = oldLeft + (anchor:find("RIGHT", 1, true) and size or 0)
            local absoluteAnchorY = oldBottom + (anchor:find("TOP", 1, true) and size or 0)
            local x = absoluteAnchorX - (anchor:find("RIGHT", 1, true) and width or 0)
            local y = absoluteAnchorY - (anchor:find("TOP", 1, true) and height or 0)
            if layout[anchorKey] ~= anchor then layout[anchorKey] = anchor; changed = true end
            if layout[xKey] ~= x then layout[xKey] = x; changed = true end
            if layout[yKey] ~= y then layout[yKey] = y; changed = true end

            local layerKey = kind .. "Layer"
            local strataKey = kind .. "Strata"
            if layout[layerKey] == nil then layout[layerKey] = 30; changed = true end
            if layout[strataKey] == nil then layout[strataKey] = "MEDIUM"; changed = true end
        end

        ConvertLane("buff", "buffGroupOffsetX", "buffGroupOffsetY", "buffAnchor", "buffOffsetX", "buffOffsetY")
        ConvertLane("debuff", "debuffGroupOffsetX", "debuffGroupOffsetY", "debuffAnchor", "debuffOffsetX", "debuffOffsetY")
        if unitCfg.overrideLayout ~= true then unitCfg.overrideLayout = true; changed = true end
    end

    local perUnit = type(auras.perUnit) == "table" and auras.perUnit or {}
    auras.perUnit = perUnit
    local existing = {}
    for unit in pairs(perUnit) do existing[unit] = true end
    -- Aura2 supported these scopes even when no per-unit override table had
    -- ever been created. Materialize them because their frame heights differ;
    -- one converted shared Y value cannot preserve all four geometries.
    local scopes = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
    for i = 1, #scopes do
        local unit = scopes[i]
        if type(perUnit[unit]) ~= "table" then perUnit[unit] = {}; changed = true end
    end
    for unit, unitCfg in pairs(perUnit) do
        ConvertScope(unit, unitCfg, existing[unit] == true)
    end
    auras._msufAuras3LegacyGeometry_v1 = true
    auras._msufAuras3LegacyGeometry_v2 = true
    auras._msufAuras3LegacyGeometry_v3 = true
    return true
end

local function MSUF_ProfileIO_HasScopedFontOverrideValue(scope)
    if type(scope) ~= "table" then return false end
    if scope.fontOutline ~= nil or scope.noOutline ~= nil or scope.boldText ~= nil then return true end
    if scope.fontMonochrome ~= nil or scope.fontTextAlpha ~= nil or scope.fontBaselineOffset ~= nil then return true end
    if scope.textBackdrop ~= nil or scope.fontShadowStrength ~= nil or scope.colorPowerTextByHealth ~= nil then return true end
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

local function MSUF_ProfileIO_ProfileHasLegacySignals(profile)
    if type(profile) ~= "table" then return false end
    if type(profile.auras2) == "table" then return true end
    if type(profile.tot) == "table" or type(profile.targetoftarget) == "table" then return true end
    if type(profile.focus_target) == "table" or type(profile.focustargettarget) == "table" then return true end
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
            if MSUF_ProfileIO_TableHasAnyValue(unitCfg.layout) and unitCfg.overrideLayout ~= true then return true end
            if MSUF_ProfileIO_TableHasAnyValue(unitCfg.layoutShared) and unitCfg.overrideSharedLayout ~= true then return true end
        end
    end
    return false
end

local function MSUF_ProfileIO_LegacyAliasBeatsCanonical(profile, toKey, ...)
    local current = profile and profile[toKey]
    for i = 1, select("#", ...) do
        local alias = profile and profile[select(i, ...)]
        if type(alias) == "table" and alias.enabled == true and (type(current) ~= "table" or current.enabled ~= true) then
            return true
        end
    end
    return false
end

local function MSUF_ProfileIO_ProfileNeedsLegacyRepair(profile)
    if type(profile) ~= "table" then return false end
    if type(profile.auras2) == "table" then return true end
    local translatedAuras = type(profile.auras3) == "table"
        and profile.auras3._msufAuras3TranslatedFromLegacyAuras2 == true
    local legacyVisualProfile = translatedAuras
        or profile._msufLegacy55FrameOutlineBackground_v1 == true
    if translatedAuras
        and (profile.auras3._msufAuras3LegacyGeometry_v3 ~= true
            or profile._msufLegacy55FrameOutlineBackground_v1 ~= true) then return true end
    if legacyVisualProfile and profile._msufLegacy55PowerTextVisibility_v1 ~= true then return true end
    if MSUF_ProfileIO_AuraOverridesNeedRepair(profile) then return true end
    if MSUF_ProfileIO_LegacyAliasBeatsCanonical(profile, "targettarget", "tot", "targetoftarget") then return true end
    if MSUF_ProfileIO_LegacyAliasBeatsCanonical(profile, "focustarget", "focus_target", "focustargettarget") then return true end
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

local function MSUF_ProfileIO_DetectProfileSchema(profile, context)
    local schema = tonumber(profile and profile._msufProfileSchema)
    if schema and not MSUF_ProfileIO_ProfileNeedsLegacyRepair(profile) then return schema end
    if MSUF_ProfileIO_ProfileHasLegacySignals(profile) then
        return MSUF_PROFILEIO_LEGACY_PROFILE_SCHEMA_56
    end
    local contextSchema = type(context) == "table" and tonumber(context.schema) or nil
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
    local source = tostring(type(context) == "table" and context.source or ""):lower()
    -- UUF conversion already emits 6.0 geometry. This compatibility mode is
    -- exclusively for native MSUF 5.5 profiles and SavedVariables.
    if source:find("uuf", 1, true) then return false end
    local translatedAuras = type(profile.auras3) == "table"
        and profile.auras3._msufAuras3TranslatedFromLegacyAuras2 == true
    local storedLegacyVisualProfile = profile._msufLegacy55FrameOutlineBackground_v1 == true
    if legacyProfile ~= true and translatedAuras ~= true and storedLegacyVisualProfile ~= true then return false end

    local changed = false
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

local function MSUF_ProfileIO_NormalizeLegacyAuras(profile, legacyProfile)
    if type(profile) ~= "table" then return false end
    local changed = false
    local fromLegacyAuras2 = false
    if type(profile.auras2) == "table" and (legacyProfile == true or type(profile.auras3) ~= "table") then
        profile.auras3 = MSUF_DeepCopy(profile.auras2)
        profile.auras3._msufAuras3TranslatedFromLegacyAuras2 = true
        fromLegacyAuras2 = true
        changed = true
    end
    if profile.auras ~= nil then
        profile.auras = nil
        changed = true
    end
    if profile.auras2 ~= nil then
        profile.auras2 = nil
        changed = true
    end
    local auras = profile.auras3
    if type(auras) ~= "table" then return changed end
    if fromLegacyAuras2 or (auras._msufAuras3TranslatedFromLegacyAuras2 == true and auras._msufAuras3LegacyGeometry_v3 ~= true) then
        changed = MSUF_ProfileIO_ConvertLegacyAuras2Geometry(auras, profile) or changed
    end
    local repairAuraOverrides = legacyProfile == true or MSUF_ProfileIO_AuraOverridesNeedRepair(profile)
    changed = MSUF_ProfileIO_NormalizeAuraLayoutTable(auras.shared) or changed
    if type(auras.perUnit) == "table" then
        for _, unitCfg in pairs(auras.perUnit) do
            if type(unitCfg) == "table" then
                changed = MSUF_ProfileIO_NormalizeAuraLayoutTable(unitCfg.layout) or changed
                changed = MSUF_ProfileIO_NormalizeAuraLayoutTable(unitCfg.layoutShared) or changed
                if repairAuraOverrides then
                    if MSUF_ProfileIO_TableHasAnyValue(unitCfg.layout) and unitCfg.overrideLayout ~= true then
                        unitCfg.overrideLayout = true
                        changed = true
                    end
                    if MSUF_ProfileIO_TableHasAnyValue(unitCfg.layoutShared) and unitCfg.overrideSharedLayout ~= true then
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
    end
    local schema = MSUF_ProfileIO_DetectProfileSchema(profile, context)
    local legacyProfile = schema < MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
    MSUF_ProfileIO_NormalizeImportedFontSizes(profile)
    if context.normalizePositions ~= false then
        MSUF_ProfileIO_NormalizeUnitFramePositionDB(profile, legacyProfile)
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
            changed = MSUF_ProfileIO_NormalizeTextScope(scope, isGroupScope, key ~= "general") or changed
            changed = MSUF_ProfileIO_NormalizeStatusScope(scope, isGroupScope) or changed
        end
    end
    changed = MSUF.ProfileIONormalizeLegacy55VisualCompatibility(profile, legacyProfile, context) or changed
    changed = MSUF_ProfileIO_NormalizeLegacyAuras(profile, legacyProfile) or changed
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
    --- Legacy alias used by older exports; only preserve/materialize it when it exists.
    if type(MSUF_DB.tot) == "table" then
        ensureAlpha(MSUF_DB.tot)
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
    return payload
end
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
    return {
        addon   = "MSUF",
        fmt     = 2,
        schema  = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
        kind    = kind,
        profile = MSUF_ActiveProfile or "Default",
        payload = payload,
    }
end

--- UUF conversion is a compatibility adapter, not a second profile format.
--- The converter maps UUF's saved-variable shape into normal MSUF profile
--- tables, then the regular legacy import path applies and refreshes it.
local function MSUF_ProfileIO_IsUUFConvertedPayload(payload)
    return type(payload) == "table"
        and type(payload._uufImport) == "table"
        and payload._uufImport.source == "UnhaltedUnitFrames"
end
local function MSUF_ProfileIO_ShouldPersistRootProfileKey(key)
    return key ~= "_uufImport"
end
local function MSUF_ProfileIO_ShouldSkipUUFImportSection(payload, isUUFImport, appliedKey)
    if MSUF_ProfileIO_IsUUFConvertedPayload(payload) then
        return payload._uufImport[appliedKey] ~= true
    end
    return isUUFImport == true
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
local function MSUF_ProfileIO_PostImportApply_Auras(kind, payload, isUUFImport)
    if not payload then  return end
    if MSUF_ProfileIO_ShouldSkipUUFImportSection(payload, isUUFImport, "aurasApplied") then
        return
    end
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
local function MSUF_ProfileIO_PostImportApply_GroupFrames(kind, payload, isUUFImport)
    if type(payload) ~= "table" then  return end
    if MSUF_ProfileIO_ShouldSkipUUFImportSection(payload, isUUFImport, "groupFramesApplied") then
        return
    end
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
    local touched = (kind == "groupframe") or (kind == "groupframes")
    if not touched then
        touched = (#touchedKinds > 0)
    end
    if not touched then  return end
    if #touchedKinds == 0 then
        AddKind("party")
        AddKind("raid")
        AddKind("mythicraid")
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
    local copied, stagedSnapshot = pcall(MSUF_DeepCopy, snapshot)
    if not copied then return false, "profile staging failed: " .. tostring(stagedSnapshot) end
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
    local isUUFImport = MSUF_ProfileIO_IsUUFConvertedPayload(payload)
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
    if isUUFImport then
        MSUF_ProfileIO_ClearUUFUnitFrameScreenCache()
    end
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
            if MSUF_ProfileIO_ShouldPersistRootProfileKey(kk) then
                MSUF_DB[kk] = MSUF_DeepCopy(vv)
            end
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
    MSUF_ProfileIO_PostImportApply_Auras(snapshot.kind, payload, isUUFImport)
    MSUF_ProfileIO_PostImportApply_GroupFrames(snapshot.kind, payload, isUUFImport)
    MSUF_ProfileIO_PostImportApply_UnitAlphas(kind, payload)
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

local UUF_IMPORT_PREFIX = "!UUF_"
local function MSUF_ProfileIO_IsUUFImportString(str)
    return type(str) == "string" and str:match("^%s*!UUF_") ~= nil
end

local function MSUF_ProfileIO_DecodeUUFProfileString(str)
    if not MSUF_ProfileIO_IsUUFImportString(str) then
        return nil, "not UUF"
    end
    local payload = str:match("^%s*(.-)%s*$")
    if not payload or payload:sub(1, #UUF_IMPORT_PREFIX) ~= UUF_IMPORT_PREFIX then
        return nil, "invalid UUF prefix"
    end
    if not (_G.LibStub and type(_G.LibStub.GetLibrary) == "function") then
        return nil, "LibStub unavailable"
    end
    local compress = _G.LibStub:GetLibrary("LibDeflate", true)
    local serializer = _G.LibStub:GetLibrary("AceSerializer-3.0", true)
    if not (compress and type(compress.DecodeForPrint) == "function" and type(compress.DecompressDeflate) == "function") then
        return nil, "LibDeflate unavailable"
    end
    if not (serializer and type(serializer.Deserialize) == "function") then
        return nil, "AceSerializer unavailable"
    end
    local encoded = payload:sub(#UUF_IMPORT_PREFIX + 1)
    if encoded == "" or #encoded > 8 * 1024 * 1024 then
        return nil, encoded == "" and "empty UUF payload" or "UUF payload is too large"
    end
    local okDecode, decoded = pcall(compress.DecodeForPrint, compress, encoded)
    if not okDecode or type(decoded) ~= "string" then
        return nil, "print-safe decode failed"
    end
    local okInflate, serialized = pcall(compress.DecompressDeflate, compress, decoded)
    if not okInflate or type(serialized) ~= "string" then
        return nil, "deflate decode failed"
    end
    if #serialized > 32 * 1024 * 1024 then
        return nil, "decompressed UUF payload is too large"
    end
    local okDeserialize, success, data = pcall(serializer.Deserialize, serializer, serialized)
    if not okDeserialize or success ~= true or type(data) ~= "table" then
        return nil, "AceSerializer decode failed"
    end
    -- UUF has shipped both the regular AceDB profile shape and a legacy
    -- double-wrapped shape caused by copying its root defaults into db.profile.
    -- Follow only the literal `profile` key and cap the depth so malformed or
    -- cyclic tables cannot turn import into an unbounded traversal.
    local profile = data
    for _ = 1, 4 do
        if type(profile) ~= "table" then break end
        if type(profile.General) == "table" or type(profile.Units) == "table" then
            return profile
        end
        profile = profile.profile
    end
    if type(data.profile) ~= "table" then
        return nil, "UUF payload has no profile table"
    end
    if type(profile) ~= "table" or (type(profile.General) ~= "table" and type(profile.Units) ~= "table") then
        return nil, "UUF payload has no recognized profile sections"
    end
    return profile
end

local function MSUF_ProfileIO_Color(c, fallbackR, fallbackG, fallbackB, fallbackA)
    if type(c) ~= "table" then
        return fallbackR, fallbackG, fallbackB, fallbackA
    end
    local r = tonumber(c.r or c[1]) or fallbackR
    local g = tonumber(c.g or c[2]) or fallbackG
    local b = tonumber(c.b or c[3]) or fallbackB
    local a = tonumber(c.a or c[4]) or fallbackA
    return r, g, b, a
end

local function MSUF_ProfileIO_CopyColorTable(c)
    if type(c) ~= "table" then
        return nil
    end
    local r, g, b, a = MSUF_ProfileIO_Color(c, nil, nil, nil, nil)
    if r == nil or g == nil or b == nil then
        return nil
    end
    local out = { r, g, b }
    if a ~= nil then out[4] = a end
    return out
end

local function MSUF_ProfileIO_MapUUFAnchorParent(anchorParent)
    if type(anchorParent) ~= "string" or anchorParent == "" then
        return nil, nil
    end
    local token = anchorParent:gsub("^UUF_", ""):gsub("^UnhaltedUnitFrames_", "")
    token = token:gsub("^MSUF_", "")
    token = token:gsub("Frame$", "")
    token = token:lower()
    if token == "uiparent" or token == "worldframe" then
        return nil, "GLOBAL"
    end
    local map = {
        player = "player",
        target = "target",
        focus = "focus",
        pet = "pet",
        party = "gf_party",
        raid = "gf_raid",
        boss = "boss",
        targettarget = "targettarget",
        targetoftarget = "targettarget",
        tot = "targettarget",
        focustarget = "focustarget",
        focus_target = "focustarget",
    }
    if map[token] then
        return nil, map[token]
    end
    return anchorParent, "GLOBAL"
end

local function MSUF_ProfileIO_NormalizeUUFAnchor(anchor, fallback)
    if type(anchor) ~= "string" or anchor == "" then return fallback end
    anchor = anchor:upper():gsub("%s+", "")
    local valid = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
        BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
        NAMELEFT = true, NAMERIGHT = true,
    }
    return valid[anchor] and anchor or fallback
end

local function MSUF_ProfileIO_UUFLayout(layout, fallbackAnchor, fallbackX, fallbackY)
    if type(layout) ~= "table" then
        return fallbackAnchor, fallbackX or 0, fallbackY or 0
    end
    return MSUF_ProfileIO_NormalizeUUFAnchor(layout[1], fallbackAnchor),
        tonumber(layout[3]) or fallbackX or 0,
        tonumber(layout[4]) or fallbackY or 0
end

local MSUF_PROFILEIO_RESTING_SYMBOLS = {
    DEFAULT = "DEFAULT",
    RESTING0 = "rested_zzz_diag",
    RESTING1 = "rested_zzz_compact",
    RESTING2 = "rested_sleep_zzzz",
    RESTING3 = "rested_sleep_zzzz",
    RESTING4 = "rested_moonzzz",
    RESTING5 = "rested_zzz_diag",
    RESTING6 = "DEFAULT",
    RESTING7 = "DEFAULT",
    RESTING8 = "rested_zzz_stack",
}

local MSUF_PROFILEIO_COMBAT_SYMBOLS = {
    DEFAULT = "DEFAULT",
    COMBAT0 = "weapon_swords_crossed",
    COMBAT1 = "weapon_swords_crossed",
    COMBAT2 = "weapon_swords_crossed",
    COMBAT3 = "weapon_fist_crossed",
    COMBAT4 = "weapon_fist_crossed",
    COMBAT5 = "DEFAULT",
    COMBAT6 = "DEFAULT",
    COMBAT7 = "DEFAULT",
    COMBAT8 = "weapon_swords_crossed",
}

local MSUF_PROFILEIO_VALID_STATUS_SYMBOLS = {
    DEFAULT = true,
    rested_moonzzz = true,
    rested_moonzzzz = true,
    rested_sleep_zzzz = true,
    rested_zzz_compact = true,
    rested_zzz_diag = true,
    rested_zzz_stack = true,
    weapon_axes_crossed = true,
    weapon_bows_crossed = true,
    weapon_crossbows_crossed = true,
    weapon_daggers_crossed = true,
    weapon_fishing_poles_crossed = true,
    weapon_fist_crossed = true,
    weapon_guns_crossed = true,
    weapon_maces_crossed = true,
    weapon_polearms_crossed = true,
    weapon_shuriken = true,
    weapon_staves_crossed = true,
    weapon_swords_crossed = true,
    weapon_thrown_crossed = true,
    weapon_wands_crossed = true,
    weapon_warglaives_crossed = true,
}

local function MSUF_ProfileIO_UUFStatusTextureKey(texture)
    if type(texture) ~= "string" or texture == "" then return nil end
    local normalized = texture:gsub("/", "\\")
    local file = normalized:match("([^\\]+)$") or normalized
    file = file:gsub("%.[A-Za-z0-9]+$", "")
    local key = file:upper()
    if key == "DEFAULT" or key:match("^RESTING%d+$") or key:match("^COMBAT%d+$") then
        return key
    end
    local upper = normalized:upper()
    return upper:match("RESTING%d+") or upper:match("COMBAT%d+") or nil
end

local function MSUF_ProfileIO_MapUUFStatusSymbol(kind, texture)
    if type(texture) ~= "string" or texture == "" then return nil end
    if MSUF_PROFILEIO_VALID_STATUS_SYMBOLS[texture] then
        return texture
    end

    local key = MSUF_ProfileIO_UUFStatusTextureKey(texture)
    if kind == "resting" then
        return (key and MSUF_PROFILEIO_RESTING_SYMBOLS[key]) or "DEFAULT"
    elseif kind == "combat" then
        return (key and MSUF_PROFILEIO_COMBAT_SYMBOLS[key]) or "DEFAULT"
    end
    return nil
end

local function MSUF_ProfileIO_ApplyUUFStatus(dst, src, map)
    if type(dst) ~= "table" or type(src) ~= "table" or type(map) ~= "table" then return end
    dst[map.enabled] = src.Enabled ~= false
    dst[map.size] = tonumber(src.Size) or dst[map.size]
    local anchor, x, y = MSUF_ProfileIO_UUFLayout(src.Layout, map.fallbackAnchor or "CENTER", 0, 0)
    dst[map.anchor] = anchor
    dst[map.x] = x
    dst[map.y] = y
    if map.symbol and src.Texture then
        local symbol = MSUF_ProfileIO_MapUUFStatusSymbol(map.symbolKind, src.Texture)
        if symbol then
            dst[map.symbol] = symbol
        end
    end
end

local function MSUF_ProfileIO_PortraitSideFromLayout(layout)
    if type(layout) ~= "table" then return "LEFT" end
    local point = tostring(layout[1] or ""):upper()
    local relative = tostring(layout[2] or ""):upper()
    if point:find("RIGHT", 1, true) and relative:find("LEFT", 1, true) then
        return "LEFT"
    elseif point:find("LEFT", 1, true) and relative:find("RIGHT", 1, true) then
        return "RIGHT"
    end
    return point:find("RIGHT", 1, true) and "LEFT" or "RIGHT"
end

local function MSUF_ProfileIO_ConvertUUFHealPrediction(src, dst, general)
    if type(src) ~= "table" then return end
    dst = type(dst) == "table" and dst or nil
    general = type(general) == "table" and general or nil

    local incoming = type(src.IncomingHeal) == "table" and src.IncomingHeal
        or type(src.Incoming) == "table" and src.Incoming or nil
    if incoming then
        if dst then dst.healPredEnabled = incoming.Enabled == true end
        if general then
            if incoming.Enabled == true then
                general.enableHealPrediction = true
                general.showSelfHealPrediction = true
            elseif general.enableHealPrediction == nil then
                general.enableHealPrediction = false
                general.showSelfHealPrediction = false
            end
            local r, g, b, a = MSUF_ProfileIO_Color(incoming.Colour, nil, nil, nil, nil)
            if r and g and b and (incoming.Enabled == true or general.healPredictionColorR == nil) then
                general.healPredictionColorR, general.healPredictionColorG, general.healPredictionColorB = r, g, b
                general.healPredictionColorA = a or general.healPredictionColorA or 0.45
            end
        end
    end

    local absorbs = type(src.Absorbs) == "table" and src.Absorbs or nil
    if absorbs then
        if dst then dst.enableAbsorbBar = absorbs.Enabled ~= false end
        if general then
            if absorbs.Enabled ~= false then
                general.enableAbsorbBar = true
            elseif general.enableAbsorbBar == nil then
                general.enableAbsorbBar = false
            end
            local r, g, b, a = MSUF_ProfileIO_Color(absorbs.Colour, nil, nil, nil, nil)
            if r and g and b and (absorbs.Enabled ~= false or general.absorbBarColorR == nil) then
                general.absorbBarColorR, general.absorbBarColorG, general.absorbBarColorB = r, g, b
                general.absorbBarColorA = a or general.absorbBarColorA or 0.75
            end
        end
    end

    local healAbsorbs = type(src.HealAbsorbs) == "table" and src.HealAbsorbs or nil
    if healAbsorbs then
        if dst then dst.healAbsorbEnabled = healAbsorbs.Enabled ~= false end
        if general then
            if healAbsorbs.Enabled ~= false then
                general.healAbsorbEnabled = true
            elseif general.healAbsorbEnabled == nil then
                general.healAbsorbEnabled = false
            end
            local r, g, b, a = MSUF_ProfileIO_Color(healAbsorbs.Colour, nil, nil, nil, nil)
            if r and g and b and (healAbsorbs.Enabled ~= false or general.healAbsorbBarColorR == nil) then
                general.healAbsorbBarColorR, general.healAbsorbBarColorG, general.healAbsorbBarColorB = r, g, b
                general.healAbsorbBarColorA = a or general.healAbsorbBarColorA or 1
            end
        end
    end
end

local function MSUF_ProfileIO_ApplyUUFCastbarGeneral(unitKey, castbar, general)
    if type(castbar) ~= "table" or type(general) ~= "table" then return end
    local map = {
        player = { enable = "enablePlayerCastbar", backend = "castbarPlayerBackend", memory = "castbarPlayerBackendBeforeHide", w = "castbarPlayerBarWidth", h = "castbarPlayerBarHeight", x = "castbarPlayerOffsetX", y = "castbarPlayerOffsetY", match = "castbarPlayerMatchWidth", icon = "castbarPlayerShowIcon", text = "castbarPlayerShowSpellName", time = "showPlayerCastTime", textX = "castbarPlayerTextOffsetX", textY = "castbarPlayerTextOffsetY", timeX = "castbarPlayerTimeOffsetX", timeY = "castbarPlayerTimeOffsetY" },
        target = { enable = "enableTargetCastbar", backend = "castbarTargetBackend", memory = "castbarTargetBackendBeforeHide", w = "castbarTargetBarWidth", h = "castbarTargetBarHeight", x = "castbarTargetOffsetX", y = "castbarTargetOffsetY", match = "castbarTargetMatchWidth", icon = "castbarTargetShowIcon", text = "castbarTargetShowSpellName", targetName = "castbarTargetShowTargetName", time = "showTargetCastTime", textX = "castbarTargetTextOffsetX", textY = "castbarTargetTextOffsetY", timeX = "castbarTargetTimeOffsetX", timeY = "castbarTargetTimeOffsetY" },
        focus = { enable = "enableFocusCastbar", backend = "castbarFocusBackend", memory = "castbarFocusBackendBeforeHide", w = "castbarFocusBarWidth", h = "castbarFocusBarHeight", x = "castbarFocusOffsetX", y = "castbarFocusOffsetY", match = "castbarFocusMatchWidth", icon = "castbarFocusShowIcon", text = "castbarFocusShowSpellName", targetName = "castbarFocusShowTargetName", time = "showFocusCastTime", textX = "castbarFocusTextOffsetX", textY = "castbarFocusTextOffsetY", timeX = "castbarFocusTimeOffsetX", timeY = "castbarFocusTimeOffsetY" },
        boss = { enable = "enableBossCastbar", backend = "bossCastbarBackend", memory = "bossCastbarBackendBeforeHide", w = "bossCastbarWidth", h = "bossCastbarHeight", x = "bossCastbarOffsetX", y = "bossCastbarOffsetY", match = "bossCastbarMatchWidth", icon = "showBossCastIcon", text = "showBossCastName", targetName = "showBossCastTargetName", time = "showBossCastTime", textX = "bossCastTextOffsetX", textY = "bossCastTextOffsetY", timeX = "bossCastTimeOffsetX", timeY = "bossCastTimeOffsetY" },
    }
    local keys = map[unitKey]
    if not keys then return end

    general[keys.enable] = castbar.Enabled ~= false
    general[keys.backend] = castbar.Enabled ~= false and "MSUF" or "HIDE"
    general[keys.memory] = castbar.Enabled ~= false and "MSUF" or "HIDE"
    general[keys.w] = tonumber(castbar.Width) or general[keys.w]
    general[keys.h] = tonumber(castbar.Height) or general[keys.h]
    general[keys.match] = castbar.MatchParentWidth == true

    local layout = type(castbar.Layout) == "table" and castbar.Layout or nil
    if layout then
        general[keys.x] = tonumber(layout[3]) or general[keys.x]
        general[keys.y] = tonumber(layout[4]) or general[keys.y]
    end

    local icon = type(castbar.Icon) == "table" and castbar.Icon or nil
    if icon then general[keys.icon] = icon.Enabled ~= false end

    local text = type(castbar.Text) == "table" and castbar.Text or {}
    local spellName = type(text.SpellName) == "table" and text.SpellName or nil
    if spellName then
        general[keys.text] = spellName.Enabled ~= false
        local _, x, y = MSUF_ProfileIO_UUFLayout(spellName.Layout, "LEFT", 0, 0)
        general[keys.textX], general[keys.textY] = x, y
        general.castbarSpellNameFontSize = tonumber(spellName.FontSize) or general.castbarSpellNameFontSize
        if unitKey == "boss" then
            general.bossCastNameFontSize = tonumber(spellName.FontSize) or general.bossCastNameFontSize
        end
    end
    local targetName = type(text.TargetName) == "table" and text.TargetName
        or type(text.CastTargetName) == "table" and text.CastTargetName
        or nil
    if keys.targetName and targetName then
        general[keys.targetName] = targetName.Enabled == true
    end
    local duration = type(text.Duration) == "table" and text.Duration or nil
    if duration then
        general[keys.time] = duration.Enabled ~= false
        local _, x, y = MSUF_ProfileIO_UUFLayout(duration.Layout, "RIGHT", -2, 0)
        general[keys.timeX], general[keys.timeY] = x, y
        general.castbarTimeFontSize = tonumber(duration.FontSize) or general.castbarTimeFontSize
        if unitKey == "boss" then
            general.bossCastTimeFontSize = tonumber(duration.FontSize) or general.bossCastTimeFontSize
        end
    end

    local r, gc, b = MSUF_ProfileIO_Color(castbar.Foreground, nil, nil, nil, nil)
    if r and gc and b and unitKey == "player" then
        general.castbarCustomR, general.castbarCustomG, general.castbarCustomB = r, gc, b
        general.playerCastbarOverrideMode = "CUSTOM"
        general.playerCastbarOverrideR, general.playerCastbarOverrideG, general.playerCastbarOverrideB = r, gc, b
    end
    local br, bg, bb = MSUF_ProfileIO_Color(castbar.Background, nil, nil, nil, nil)
    if br and bg and bb then
        general.castbarBgR, general.castbarBgG, general.castbarBgB = br, bg, bb
    end
    local nr, ng, nb = MSUF_ProfileIO_Color(castbar.NotInterruptibleColour, nil, nil, nil, nil)
    if nr and ng and nb then
        general.castbarNonInterruptibleCustomR, general.castbarNonInterruptibleCustomG, general.castbarNonInterruptibleCustomB = nr, ng, nb
    end
end

local function MSUF_ProfileIO_TagToTextMode(tag, isPower)
    if type(tag) ~= "string" or tag == "" then return nil end
    local s = tag:lower()
    s = s:gsub("%[powercolor%]", "")
    local hasCur = s:find(isPower and "curpp" or "curhp", 1, true) ~= nil
        or s:find("current", 1, true) ~= nil
    local hasMax = s:find(isPower and "maxpp" or "maxhp", 1, true) ~= nil
        or s:find("max", 1, true) ~= nil
    local hasPercent = s:find(isPower and "perpp" or "perhp", 1, true) ~= nil
        or s:find("percent", 1, true) ~= nil
        or s:find("perc", 1, true) ~= nil
    if hasCur and hasMax and hasPercent then return "CURMAXPERCENT" end
    if hasCur and hasMax then return "CURMAX" end
    if hasCur and hasPercent then return "CURPERCENT" end
    if hasMax and hasPercent then return "MAXPERCENT" end
    if hasCur then return "CURRENT" end
    if hasMax then return "MAX" end
    if hasPercent then return "PERCENT" end
    return nil
end

local function MSUF_ProfileIO_ColorObject(c)
    local r, g, b, a = MSUF_ProfileIO_Color(c, nil, nil, nil, nil)
    if r == nil or g == nil or b == nil then
        return nil
    end
    return { r = r, g = g, b = b, a = a or 1 }
end

local function MSUF_ProfileIO_UUFTagLayout(tagConf)
    local layout = type(tagConf) == "table" and type(tagConf.Layout) == "table" and tagConf.Layout or nil
    local point = MSUF_ProfileIO_NormalizeUUFAnchor(layout and layout[1], "CENTER")
    local relativePoint = MSUF_ProfileIO_NormalizeUUFAnchor(layout and layout[2], point)
    local x = tonumber(layout and layout[3]) or 0
    local y = tonumber(layout and layout[4]) or 0
    return point, relativePoint, x, y
end

local function MSUF_ProfileIO_UUFTextSlotFromPoint(point)
    point = tostring(point or ""):upper()
    if point:find("LEFT", 1, true) then
        return "Left"
    elseif point:find("RIGHT", 1, true) then
        return "Right"
    end
    return "Center"
end

local function MSUF_ProfileIO_SetUUFTextLayout(dst, prefix, tagConf)
    local point, relativePoint, x, y = MSUF_ProfileIO_UUFTagLayout(tagConf)
    dst["direct" .. prefix .. "Point"] = point
    dst["direct" .. prefix .. "RelativePoint"] = relativePoint
    dst["direct" .. prefix .. "OffsetX"] = x
    dst["direct" .. prefix .. "OffsetY"] = y
    local color = MSUF_ProfileIO_ColorObject(tagConf and tagConf.Colour)
    if color then
        dst["direct" .. prefix .. "Color"] = color
    end
    return point, relativePoint, x, y
end

local MSUF_PROFILEIO_UUF_SCOPED_FONT_KEYS = {
    "fontKey",
    "fontSize",
    "fontOutline",
    "boldText",
    "noOutline",
    "textBackdrop",
    "fontMonochrome",
    "fontShadowStrength",
    "fontTextAlpha",
    "fontBaselineOffset",
    "nameClassColor",
    "npcNameRed",
    "nameNpcClassColor",
    "colorHealthTextByHealth",
    "colorPowerTextByType",
    "powerTextColorByType",
    "useGlobalFontColor",
    "fontR",
    "fontG",
    "fontB",
    "nameColor",
    "nameColorMode",
    "nameColorR",
    "nameColorG",
    "nameColorB",
    "nameFontSize",
    "hpFontSize",
    "powerFontSize",
    "shortenNames",
    "nameShortenEnabled",
    "shortenNameMaxChars",
    "nameMaxChars",
    "shortenNameClipSide",
    "nameClipSide",
    "shortenNameFrontMaskPx",
    "shortenNameShowDots",
    "nameNoEllipsis",
}

local function MSUF_ProfileIO_ClearUUFScopedFontKeys(dst)
    for i = 1, #MSUF_PROFILEIO_UUF_SCOPED_FONT_KEYS do
        dst[MSUF_PROFILEIO_UUF_SCOPED_FONT_KEYS[i]] = nil
    end
end

local function MSUF_ProfileIO_ResetUUFSharedFontControls(outProfile)
    if type(outProfile) ~= "table" then return end
    local g = type(outProfile.general) == "table" and outProfile.general or {}
    outProfile.general = g
    outProfile.shortenNames = false
    outProfile.shortenNameClipSide = "LEFT"
    outProfile.shortenNameMaxChars = 6
    outProfile.shortenNameShowDots = true
    g.fontColor = "white"
    g.useCustomFontColor = false
    g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB = nil, nil, nil
    g.fontTextAlpha = 1
    g.textBackdrop = true
    g.fontShadowStrength = "NORMAL"
    g.fontMonochrome = false
    g.boldText = false
    g.noOutline = false
end

local MSUF_PROFILEIO_UUF_INHERITED_FONT_FLAGS = {
    "nameClassColor",
    "npcNameRed",
    "nameNpcClassColor",
    "colorHealthTextByHealth",
    "colorPowerTextByType",
    "powerTextColorByType",
    "useGlobalFontColor",
    "shortenNames",
    "nameShortenEnabled",
}

local function MSUF_ProfileIO_ResetUUFText(dst)
    if type(dst) ~= "table" then return end
    MSUF_ProfileIO_ClearUUFScopedFontKeys(dst)
    dst.directTextLayout = true
    dst.uufTextLayout = nil
    dst.fontOverride = true
    dst.showName = false
    dst.showHPText = false
    dst.showPowerText = false
    dst.textLeft, dst.textCenter, dst.textRight = "NONE", "NONE", "NONE"
    dst.powerTextLeft, dst.powerTextCenter, dst.powerTextRight = "NONE", "NONE", "NONE"
    dst.hpTextLeftHidePercentSymbol, dst.hpTextCenterHidePercentSymbol, dst.hpTextRightHidePercentSymbol = nil, nil, nil
    dst.powerTextLeftHidePercentSymbol, dst.powerTextCenterHidePercentSymbol, dst.powerTextRightHidePercentSymbol = nil, nil, nil
    dst.hpOffsetX, dst.hpOffsetY = 0, 0
    dst.powerOffsetX, dst.powerOffsetY = 0, 0
    dst.nameOffsetX, dst.nameOffsetY = 0, 0
    local prefixes = {
        "Name",
        "HealthLeft", "HealthCenter", "HealthRight",
        "PowerLeft", "PowerCenter", "PowerRight",
    }
    for i = 1, #prefixes do
        local directPrefix = "direct" .. prefixes[i]
        dst[directPrefix .. "Point"] = nil
        dst[directPrefix .. "RelativePoint"] = nil
        dst[directPrefix .. "OffsetX"] = nil
        dst[directPrefix .. "OffsetY"] = nil
        dst[directPrefix .. "Color"] = nil
        local legacyPrefix = "uuf" .. prefixes[i]
        dst[legacyPrefix .. "Point"] = nil
        dst[legacyPrefix .. "RelativePoint"] = nil
        dst[legacyPrefix .. "OffsetX"] = nil
        dst[legacyPrefix .. "OffsetY"] = nil
        dst[legacyPrefix .. "Color"] = nil
    end
end

local function MSUF_ProfileIO_ApplyUUFTag(dst, tagConf)
    if type(dst) ~= "table" or type(tagConf) ~= "table" then return end
    local tag = tostring(tagConf.Tag or "")
    if tag == "" then return end
    local lower = tag:lower()
    local point = MSUF_ProfileIO_UUFTagLayout(tagConf)
    if lower:find("%[name") or lower:find("name", 1, true) then
        dst.showName = true
        dst.nameFontSize = tonumber(tagConf.FontSize) or dst.nameFontSize
        local _, _, x, y = MSUF_ProfileIO_SetUUFTextLayout(dst, "Name", tagConf)
        dst.nameOffsetX = x
        dst.nameOffsetY = y
        if point:find("RIGHT", 1, true) then
            dst.nameAnchor = "RIGHT"
        elseif point:find("CENTER", 1, true) then
            dst.nameAnchor = "CENTER"
        else
            dst.nameAnchor = "LEFT"
        end
        local maxChars = lower:match("name:short:(%d+)")
        if maxChars then
            dst.shortenNames = true
            dst.nameShortenEnabled = true
            dst.shortenNameMaxChars = tonumber(maxChars) or dst.shortenNameMaxChars
            dst.shortenNameShowDots = false
        end
        return
    end
    local hpMode = MSUF_ProfileIO_TagToTextMode(tag, false)
    if hpMode then
        dst.showHPText = true
        dst.hpFontSize = tonumber(tagConf.FontSize) or dst.hpFontSize
        local slot = MSUF_ProfileIO_UUFTextSlotFromPoint(point)
        MSUF_ProfileIO_SetUUFTextLayout(dst, "Health" .. slot, tagConf)
        if slot == "Left" then
            dst.textLeft = hpMode
        elseif slot == "Center" then
            dst.textCenter = hpMode
        else
            dst.textRight = hpMode
        end
        return
    end
    local powerMode = MSUF_ProfileIO_TagToTextMode(tag, true)
    if powerMode then
        dst.showPowerText = true
        dst.powerFontSize = tonumber(tagConf.FontSize) or dst.powerFontSize
        local slot = MSUF_ProfileIO_UUFTextSlotFromPoint(point)
        MSUF_ProfileIO_SetUUFTextLayout(dst, "Power" .. slot, tagConf)
        if lower:find("%[powercolor%]") then
            dst.colorPowerTextByType = true
            dst.powerTextColorByType = true
            dst["directPower" .. slot .. "Color"] = nil
        end
        if slot == "Left" then
            dst.powerTextLeft = powerMode
        elseif slot == "Center" then
            dst.powerTextCenter = powerMode
        else
            dst.powerTextRight = powerMode
        end
    end
end

local MSUF_PROFILEIO_UUF_DIRECT_COLOR_FIELDS = {
    "directNameColor",
    "directHealthLeftColor",
    "directHealthCenterColor",
    "directHealthRightColor",
    "directPowerLeftColor",
    "directPowerCenterColor",
    "directPowerRightColor",
}

local MSUF_PROFILEIO_UUF_DIRECT_COLOR_UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }

local function MSUF_ProfileIO_NormalizeUUFScopedFontInheritance(outProfile)
    if type(outProfile) ~= "table" then return end
    for i = 1, #MSUF_PROFILEIO_UUF_DIRECT_COLOR_UNITS do
        local unit = outProfile[MSUF_PROFILEIO_UUF_DIRECT_COLOR_UNITS[i]]
        if type(unit) == "table" and unit.directTextLayout == true then
            for j = 1, #MSUF_PROFILEIO_UUF_INHERITED_FONT_FLAGS do
                local key = MSUF_PROFILEIO_UUF_INHERITED_FONT_FLAGS[j]
                if unit[key] == false then
                    unit[key] = nil
                end
            end
        end
    end
end

local function MSUF_ProfileIO_ColorComponent(value)
    return tonumber(value) or 1
end

local function MSUF_ProfileIO_SameColor(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    local ar, ag, ab = MSUF_ProfileIO_ColorComponent(a.r or a[1]), MSUF_ProfileIO_ColorComponent(a.g or a[2]), MSUF_ProfileIO_ColorComponent(a.b or a[3])
    local br, bg, bb = MSUF_ProfileIO_ColorComponent(b.r or b[1]), MSUF_ProfileIO_ColorComponent(b.g or b[2]), MSUF_ProfileIO_ColorComponent(b.b or b[3])
    local aa = tonumber(a.a or a[4] or 1) or 1
    local ba = tonumber(b.a or b[4] or 1) or 1
    return math.abs(ar - br) <= 0.0001
        and math.abs(ag - bg) <= 0.0001
        and math.abs(ab - bb) <= 0.0001
        and math.abs(aa - ba) <= 0.0001
end

local function MSUF_ProfileIO_NormalizeUniformUUFTextColor(outProfile)
    if type(outProfile) ~= "table" then return end
    local first
    for i = 1, #MSUF_PROFILEIO_UUF_DIRECT_COLOR_UNITS do
        local unit = outProfile[MSUF_PROFILEIO_UUF_DIRECT_COLOR_UNITS[i]]
        if type(unit) == "table" and unit.directTextLayout == true then
            for j = 1, #MSUF_PROFILEIO_UUF_DIRECT_COLOR_FIELDS do
                local color = unit[MSUF_PROFILEIO_UUF_DIRECT_COLOR_FIELDS[j]]
                if type(color) == "table" then
                    if not first then
                        first = color
                    elseif not MSUF_ProfileIO_SameColor(first, color) then
                        return
                    end
                end
            end
        end
    end
    if type(first) ~= "table" then return end

    local general = outProfile.general
    if type(general) ~= "table" then return end
    general.useCustomFontColor = true
    general.fontColorCustomR = MSUF_ProfileIO_ColorComponent(first.r or first[1])
    general.fontColorCustomG = MSUF_ProfileIO_ColorComponent(first.g or first[2])
    general.fontColorCustomB = MSUF_ProfileIO_ColorComponent(first.b or first[3])
    local alpha = tonumber(first.a or first[4])
    if alpha then
        if alpha < 0.7 then alpha = 0.7 elseif alpha > 1 then alpha = 1 end
        general.fontTextAlpha = alpha
    end

    for i = 1, #MSUF_PROFILEIO_UUF_DIRECT_COLOR_UNITS do
        local unit = outProfile[MSUF_PROFILEIO_UUF_DIRECT_COLOR_UNITS[i]]
        if type(unit) == "table" and unit.directTextLayout == true then
            for j = 1, #MSUF_PROFILEIO_UUF_DIRECT_COLOR_FIELDS do
                unit[MSUF_PROFILEIO_UUF_DIRECT_COLOR_FIELDS[j]] = nil
            end
            unit.nameColor = nil
            unit.useGlobalFontColor = nil
            unit.fontR, unit.fontG, unit.fontB = nil, nil, nil
        end
    end
end

-- UUF exports the raw AceDB profile table. Values supplied by AceDB defaults
-- (including anchor points, sizes, enabled flags, and default tags) are often
-- absent from the serialized string. Missing source fields must therefore fall
-- back to UUF's schema defaults, never to the profile currently active in MSUF.
local UUFGroup = {
    DefaultHealth = {
        ColourByClass = true,
        Inverse = false,
        Smooth = false,
        Foreground = { 8 / 255, 8 / 255, 8 / 255 },
        ForegroundOpacity = 0.8,
        Background = { 34 / 255, 34 / 255, 34 / 255 },
        BackgroundOpacity = 1.0,
    },
    DefaultPower = {
        Enabled = false,
        OnlyShowHealers = false,
        Height = 3,
        Foreground = { 8 / 255, 8 / 255, 8 / 255 },
        Background = { 128 / 255, 128 / 255, 128 / 255 },
        ColourByType = true,
        ColourBackgroundByType = false,
        Smooth = true,
    },
    DefaultSecondaryPower = {
        Enabled = false,
        Height = 3,
        Position = "TOP",
        ColourByType = true,
        BackgroundOpacity = 1,
    },
    UnitDefaults = {
        player = { enabled = true, forceHide = true, width = 244, height = 42, point = "CENTER", relativePoint = "CENTER", x = -425.1, y = -275.1 },
        target = { enabled = true, forceHide = true, width = 244, height = 42, point = "CENTER", relativePoint = "CENTER", x = 425.1, y = -275.1 },
        targettarget = { enabled = true, forceHide = true, width = 122, height = 22, point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT", x = 0, y = -26.1, anchorParent = "UUF_Target" },
        focus = { enabled = true, forceHide = true, width = 122, height = 22, point = "BOTTOMLEFT", relativePoint = "TOPLEFT", x = 0, y = 36.1, anchorParent = "UUF_Player" },
        focustarget = { enabled = true, forceHide = true, width = 122, height = 22, point = "LEFT", relativePoint = "RIGHT", x = 1, y = 0, anchorParent = "UUF_Focus" },
        pet = { enabled = true, forceHide = true, width = 122, height = 22, point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 0, y = -26.1, anchorParent = "UUF_Player" },
        boss = { enabled = true, forceHide = true, width = 244, height = 42, point = "CENTER", relativePoint = "CENTER", x = 550.1, y = -0.1, spacing = 26 },
    },
    GroupDefaults = {
        party = {
            enabled = true, forceHide = true, width = 252, height = 52,
            point = "CENTER", x = -550.1, y = -0.1, spacing = 1,
            growth = "DOWN", sort = "ROLE", roleOrder = { "TANK", "HEALER", "DAMAGER" },
            showPlayer = false,
        },
        raid = {
            enabled = true, forceHide = true, width = 90, height = 52,
            point = "TOPLEFT", x = 1.1, y = -1.1, spacing = 1,
            growth = "RIGHT_DOWN", sort = "GROUP", showPlayer = true,
            groups = { true, true, true, true, false, false, false, false },
        },
    },
}

local function MSUF_ProfileIO_MakeUUFUnitVisible(dst)
    if type(dst) ~= "table" then return end
    dst.useBlizzardFrame = false
    dst.showHP = true
    dst.showHealth = true
    dst.hpBarAlpha = tonumber(dst.hpBarAlpha) or 1
    if dst.hpBarAlpha <= 0 then dst.hpBarAlpha = 1 end
    dst.powerBarAlpha = tonumber(dst.powerBarAlpha) or 1
    if dst.powerBarAlpha <= 0 then dst.powerBarAlpha = 1 end
    dst.hpBgAlpha = tonumber(dst.hpBgAlpha) or 0.85
    if dst.hpBgAlpha <= 0 then dst.hpBgAlpha = 0.85 end
    dst.powerBarBgAlpha = tonumber(dst.powerBarBgAlpha) or dst.hpBgAlpha or 0.85
    if dst.powerBarBgAlpha <= 0 then dst.powerBarBgAlpha = 0.85 end
    dst.alphaExcludeTextPortrait = dst.alphaExcludeTextPortrait == true
    dst.loadCondHideMounted = false
    dst.loadCondHideOutOfCombat = false
    dst.loadCondHideSolo = false
    dst.loadCondHideInVehicle = false
    dst.loadCondHideInGroup = false
    dst.loadCondHideInInstance = false
    dst.loadCondHideInHousing = false
    dst.loadCondHideResting = false
    dst.loadCondHideInCombat = false
    dst.loadCondHideStealthed = false
    dst.loadCondActive = false
end

local function MSUF_ProfileIO_ConvertUUFUnit(unitKey, src, outProfile)
    if type(outProfile) ~= "table" then return end
    src = type(src) == "table" and src or {}
    local defaults = UUFGroup.UnitDefaults[unitKey]
    if type(defaults) ~= "table" then return end
    local dst = outProfile[unitKey] or {}
    outProfile[unitKey] = dst
    dst.enabled = src.Enabled == nil and defaults.enabled or src.Enabled ~= false
    dst.forceHideBlizzard = src.ForceHideBlizzard == nil and defaults.forceHide or src.ForceHideBlizzard == true
    MSUF_ProfileIO_MakeUUFUnitVisible(dst)
    MSUF_ProfileIO_ResetUUFText(dst)

    local frame = type(src.Frame) == "table" and src.Frame or {}
    dst.anchorFrameName = nil
    dst.anchorToUnitframe = "GLOBAL"
    dst.width = UUFGroup.SafeNumber(frame.Width or frame.width, defaults.width, 20, 1200)
    dst.height = UUFGroup.SafeNumber(frame.Height or frame.height, defaults.height, 8, 600)
    dst.frameStrata = frame.FrameStrata or frame.frameStrata or "LOW"
    local layout = type(frame.Layout) == "table" and frame.Layout or {}
    dst.point = MSUF_ProfileIO_NormalizeUUFAnchor(layout[1], defaults.point)
    dst.relativePoint = MSUF_ProfileIO_NormalizeUUFAnchor(layout[2], defaults.relativePoint)
    dst.offsetX = UUFGroup.SafeNumber(layout[3], defaults.x, -16384, 16384)
    dst.offsetY = UUFGroup.SafeNumber(layout[4], defaults.y, -16384, 16384)
    if unitKey == "boss" then
        local padding = UUFGroup.SafeNumber(layout[5], defaults.spacing, 0, 200)
        local bossCount = 5
        local containerHeight = (dst.height + padding) * bossCount - padding
        local point = dst.point
        local multiplier = (point == "BOTTOMLEFT" or point == "BOTTOM" or point == "BOTTOMRIGHT") and 1
            or (point == "CENTER" or point == "LEFT" or point == "RIGHT") and 0.5 or 0
        local firstOffsetY = containerHeight * multiplier
        if multiplier == 0.5 then firstOffsetY = firstOffsetY - (dst.height * 0.5) end

        local growsUp = type(frame.GrowthDirection) == "string" and frame.GrowthDirection:upper() == "UP"
        if growsUp then firstOffsetY = firstOffsetY - ((bossCount - 1) * (dst.height + padding)) end
        dst.offsetY = dst.offsetY + firstOffsetY
        dst.point = (point == "BOTTOMLEFT" and "TOPLEFT") or (point == "BOTTOM" and "TOP")
            or (point == "BOTTOMRIGHT" and "TOPRIGHT") or point
        dst.spacing = -(dst.height + padding)
        dst.bossLayoutMode = growsUp and "VERTICAL_UP" or "VERTICAL_DOWN"
    end
    local anchorFrameName, anchorUnit = MSUF_ProfileIO_MapUUFAnchorParent(frame.AnchorParent or defaults.anchorParent)
    if anchorFrameName then dst.anchorFrameName = anchorFrameName end
    if anchorUnit then dst.anchorToUnitframe = anchorUnit end

    local health = type(src.HealthBar) == "table" and src.HealthBar or {}
    local healthDefaults = UUFGroup.DefaultHealth
    local inverse = health.Inverse
    if inverse == nil then inverse = healthDefaults.Inverse end
    local smooth = health.Smooth
    if smooth == nil then smooth = healthDefaults.Smooth end
    dst.reverseFillBars = inverse == true
    dst.smoothFill = smooth == true
    dst.hpBarAlpha = UUFGroup.SafeNumber(health.ForegroundOpacity, healthDefaults.ForegroundOpacity, 0, 1)
    if dst.hpBarAlpha <= 0 then dst.hpBarAlpha = 1 end
    dst.powerBarAlpha = UUFGroup.SafeNumber(health.PowerOpacity or health.ForegroundOpacity, healthDefaults.ForegroundOpacity, 0, 1)
    if dst.powerBarAlpha <= 0 then dst.powerBarAlpha = 1 end
    dst.hpBgAlpha = UUFGroup.SafeNumber(health.BackgroundOpacity, healthDefaults.BackgroundOpacity, 0, 1)
    if dst.hpBgAlpha <= 0 then dst.hpBgAlpha = 0.85 end
    dst.powerBarBgAlpha = UUFGroup.SafeNumber(health.PowerBackgroundOpacity or health.BackgroundOpacity, healthDefaults.BackgroundOpacity, 0, 1)
    if dst.powerBarBgAlpha <= 0 then dst.powerBarBgAlpha = 0.85 end
    local fg = MSUF_ProfileIO_CopyColorTable(health.Foreground or healthDefaults.Foreground)
    local bg = MSUF_ProfileIO_CopyColorTable(health.Background or healthDefaults.Background)
    if fg then dst.importHealthForeground = fg end
    if bg then
        local r, g, b = MSUF_ProfileIO_Color(bg, 0, 0, 0, 1)
        dst.classBarBgR, dst.classBarBgG, dst.classBarBgB = r, g, b
    end

    local power = type(src.PowerBar) == "table" and src.PowerBar or {}
    local powerDefaults = UUFGroup.DefaultPower
    local powerEnabled = power.Enabled
    if powerEnabled == nil then powerEnabled = powerDefaults.Enabled end
    local powerSmooth = power.Smooth
    if powerSmooth == nil then powerSmooth = powerDefaults.Smooth end
    local powerBgByType = power.ColourBackgroundByType
    if powerBgByType == nil then powerBgByType = powerDefaults.ColourBackgroundByType end
    dst.showPowerBar = powerEnabled ~= false
    dst.showPower = dst.showPowerBar
    dst.powerBarHeight = UUFGroup.SafeNumber(power.Height, powerDefaults.Height, 1, 100)
    dst.powerSmoothFill = powerSmooth == true
    dst.powerBarBgMatchBarColor = powerBgByType == true
    local pfg = MSUF_ProfileIO_CopyColorTable(power.Foreground or powerDefaults.Foreground)
    if pfg then dst.importPowerForeground = pfg end

    if unitKey == "player" and type(outProfile.bars) == "table" then
        local secondary = UUFGroup.MergeDefaults(src.SecondaryPowerBar, UUFGroup.DefaultSecondaryPower)
        outProfile.bars.showClassPower = secondary.Enabled ~= false
        outProfile.bars.classPowerHeight = UUFGroup.SafeNumber(secondary.Height, 3, 1, 100)
        outProfile.bars.classPowerColorByType = secondary.ColourByType ~= false
        outProfile.bars.classPowerBgAlpha = UUFGroup.SafeNumber(secondary.BackgroundOpacity, 1, 0, 1)
        if secondary.Position == "BOTTOM" then
            outProfile.bars.classPowerOffsetY = tonumber(outProfile.bars.classPowerOffsetY) or -4
        elseif secondary.Position == "TOP" then
            outProfile.bars.classPowerOffsetY = 0
        end

        local alternative = type(src.AlternativePowerBar) == "table" and src.AlternativePowerBar or nil
        if alternative then
            outProfile.bars.showAltMana = alternative.Enabled == true
            outProfile.bars.altManaHeight = UUFGroup.SafeNumber(alternative.Height, outProfile.bars.altManaHeight, 1, 100)
            local al = type(alternative.Layout) == "table" and alternative.Layout or nil
            if al then
                outProfile.bars.altManaOffsetY = UUFGroup.SafeNumber(al[4], outProfile.bars.altManaOffsetY, -4096, 4096)
            end
        end
    end

    local portraitDefaults = UUFGroup.PortraitDefaults(unitKey)
    local portrait = UUFGroup.MergeDefaults(src.Portrait, portraitDefaults)
    dst.showPortrait = portrait.Enabled == true
    dst.portraitEnabled = portrait.Enabled == true
    dst.portraitMode = portrait.Enabled == true and MSUF_ProfileIO_PortraitSideFromLayout(portrait.Layout) or "OFF"
    dst.portraitWidth = UUFGroup.SafeNumber(portrait.Width or portrait.Size, portraitDefaults.Width, 1, 1200)
    dst.portraitHeight = UUFGroup.SafeNumber(portrait.Height or portrait.Size, portraitDefaults.Height, 1, 600)
    dst.portraitSizeOverride = UUFGroup.SafeNumber(portrait.Size or portrait.Width or portrait.Height, portraitDefaults.Height, 1, 1200)
    local pl = type(portrait.Layout) == "table" and portrait.Layout or nil
    if pl then
        dst.portraitPoint = MSUF_ProfileIO_NormalizeUUFAnchor(pl[1], portraitDefaults.Layout[1])
        dst.portraitRelativePoint = MSUF_ProfileIO_NormalizeUUFAnchor(pl[2], portraitDefaults.Layout[2])
        dst.portraitOffsetX = UUFGroup.SafeNumber(pl[3], 0, -4096, 4096)
        dst.portraitOffsetY = UUFGroup.SafeNumber(pl[4], 0, -4096, 4096)
    end
    dst.portraitZoom = UUFGroup.SafeNumber(portrait.Zoom, 0.3, 0, 1)
    dst.portraitRender = portrait.UseClassPortrait == true and "CLASS" or portrait.Style or "2D"
    dst.portraitUseClass = portrait.UseClassPortrait == true
    if portrait.UseClassPortrait == true then
        dst.portraitClassStyle = "BLIZZARD"
    end

    local castbarSource = type(src.CastBar) == "table" and src.CastBar
        or type(src.Castbar) == "table" and src.Castbar
        or nil
    local castbarDefaults = UUFGroup.CastbarDefaults(unitKey)
    local castbar = UUFGroup.MergeDefaults(castbarSource, castbarDefaults)
    dst.castbarEnabled = castbar.Enabled ~= false
    dst.castbarWidth = UUFGroup.SafeNumber(castbar.Width, castbarDefaults.Width or defaults.width, 1, 1200)
    dst.castbarHeight = UUFGroup.SafeNumber(castbar.Height, 24, 1, 600)
    dst.castbarMatchUnitWidth = castbar.MatchParentWidth == true
    local cl = type(castbar.Layout) == "table" and castbar.Layout or nil
    if cl then
        dst.castbarOffsetX = UUFGroup.SafeNumber(cl[3], 0, -4096, 4096)
        dst.castbarOffsetY = UUFGroup.SafeNumber(cl[4], 0, -4096, 4096)
    end
    MSUF_ProfileIO_ApplyUUFCastbarGeneral(unitKey, castbar, outProfile.general)

    MSUF_ProfileIO_ConvertUUFHealPrediction(src.HealPrediction, dst, outProfile.general)

    local tags = UUFGroup.TagsForUnit(unitKey, src.Tags)
    MSUF_ProfileIO_ApplyUUFTag(dst, tags.TagOne)
    MSUF_ProfileIO_ApplyUUFTag(dst, tags.TagTwo)
    MSUF_ProfileIO_ApplyUUFTag(dst, tags.TagThree)
    MSUF_ProfileIO_ApplyUUFTag(dst, tags.TagFour)
    MSUF_ProfileIO_ApplyUUFTag(dst, tags.TagFive)

    local indicators = type(src.Indicators) == "table" and src.Indicators or {}
    MSUF_ProfileIO_ApplyUUFStatus(dst, indicators.RaidTargetMarker, { enabled = "showRaidMarker", size = "raidMarkerSize", anchor = "raidMarkerAnchor", x = "raidMarkerOffsetX", y = "raidMarkerOffsetY", fallbackAnchor = "TOPLEFT" })
    MSUF_ProfileIO_ApplyUUFStatus(dst, indicators.LeaderAssistantIndicator, { enabled = "showLeaderIcon", size = "leaderIconSize", anchor = "leaderIconAnchor", x = "leaderIconOffsetX", y = "leaderIconOffsetY", fallbackAnchor = "TOPLEFT" })
    MSUF_ProfileIO_ApplyUUFStatus(dst, indicators.Resting, { enabled = "showRestingIndicator", size = "restedStateIndicatorSize", anchor = "restedStateIndicatorAnchor", x = "restedStateIndicatorOffsetX", y = "restedStateIndicatorOffsetY", fallbackAnchor = "TOPLEFT", symbol = "restedStateIndicatorSymbol", symbolKind = "resting" })
    MSUF_ProfileIO_ApplyUUFStatus(dst, indicators.Combat, { enabled = "showCombatStateIndicator", size = "combatStateIndicatorSize", anchor = "combatStateIndicatorAnchor", x = "combatStateIndicatorOffsetX", y = "combatStateIndicatorOffsetY", fallbackAnchor = "TOPLEFT", symbol = "combatStateIndicatorSymbol", symbolKind = "combat" })
    MSUF_ProfileIO_ApplyUUFStatus(dst, indicators.Resurrection, { enabled = "showIncomingResIndicator", size = "incomingResIndicatorSize", anchor = "incomingResIndicatorAnchor", x = "incomingResIndicatorOffsetX", y = "incomingResIndicatorOffsetY", fallbackAnchor = "TOPRIGHT" })
end

function UUFGroup.SafeNumber(value, fallback, minimum, maximum)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    if minimum ~= nil and value < minimum then value = minimum end
    if maximum ~= nil and value > maximum then value = maximum end
    return value
end

function UUFGroup.MergeDefaults(src, defaults)
    src = type(src) == "table" and src or {}
    defaults = type(defaults) == "table" and defaults or {}
    local out = {}
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            out[key] = UUFGroup.MergeDefaults(src[key], value)
        elseif src[key] == nil then
            out[key] = value
        else
            out[key] = src[key]
        end
    end
    for key, value in pairs(src) do
        if out[key] == nil then out[key] = value end
    end
    return out
end

function UUFGroup.PortraitDefaults(unitKey)
    local compact = unitKey == "targettarget" or unitKey == "focus" or unitKey == "focustarget" or unitKey == "pet"
    local rightSide = unitKey == "target" or unitKey == "focus" or unitKey == "pet"
    return {
        Enabled = unitKey == "boss",
        Width = compact and 22 or 42,
        Height = compact and 22 or 42,
        Layout = rightSide and { "LEFT", "RIGHT", 1, 0 } or { "RIGHT", "LEFT", -1, 0 },
        Zoom = 0.3,
        UseClassPortrait = false,
        Style = "2D",
    }
end

function UUFGroup.CastbarDefaults(unitKey)
    if unitKey == "targettarget" or unitKey == "focustarget" then
        return { Enabled = false }
    end
    local enabled = unitKey ~= "pet"
    local layout = unitKey == "focus"
        and { "BOTTOMLEFT", "TOPLEFT", 0, 1 }
        or { "TOPLEFT", "BOTTOMLEFT", 0, -1 }
    return {
        Enabled = enabled,
        Width = 244,
        Height = 24,
        Layout = layout,
        MatchParentWidth = true,
        Foreground = { 128 / 255, 128 / 255, 1 },
        Background = { 34 / 255, 34 / 255, 34 / 255 },
        NotInterruptibleColour = { 1, 64 / 255, 64 / 255 },
        Icon = { Enabled = true, Position = "LEFT" },
        Text = {
            SpellName = { Enabled = true, FontSize = 12, Layout = { "LEFT", "LEFT", 3, 0 }, Colour = { 1, 1, 1 } },
            Duration = { Enabled = true, FontSize = 12, Layout = { "RIGHT", "RIGHT", -3, 0 }, Colour = { 1, 1, 1 } },
        },
    }
end

function UUFGroup.AuraLane(enabled, size, point, relativePoint, x, y, count, perRow, growth, wrap)
    return {
        Enabled = enabled == true,
        OnlyShowPlayer = false,
        Size = size,
        Layout = { point, relativePoint, x, y, 1 },
        Num = count,
        Wrap = perRow,
        GrowthDirection = growth,
        WrapDirection = wrap,
        Sorting = "BLIZZARD",
        Count = {
            HideStacks = false,
            FontSize = 12,
            Layout = { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 2 },
        },
    }
end

function UUFGroup.AuraDefaults(unitKey)
    local buff, debuff
    if unitKey == "player" then
        buff = UUFGroup.AuraLane(true, 34, "BOTTOMRIGHT", "TOPRIGHT", 0, 1, 4, 4, "LEFT", "UP")
        debuff = UUFGroup.AuraLane(true, 34, "BOTTOMLEFT", "TOPLEFT", 0, 1, 3, 3, "RIGHT", "UP")
    elseif unitKey == "target" then
        buff = UUFGroup.AuraLane(true, 34, "BOTTOMLEFT", "TOPLEFT", 0, 1, 3, 3, "RIGHT", "UP")
        debuff = UUFGroup.AuraLane(true, 34, "BOTTOMRIGHT", "TOPRIGHT", 0, 1, 4, 4, "LEFT", "UP")
    elseif unitKey == "targettarget" or unitKey == "focustarget" then
        buff = UUFGroup.AuraLane(false, 22, "RIGHT", "LEFT", -1, 0, 3, 3, "LEFT", "UP")
        debuff = UUFGroup.AuraLane(false, 22, "LEFT", "RIGHT", 1, 0, 3, 3, "RIGHT", "UP")
    elseif unitKey == "focus" then
        buff = UUFGroup.AuraLane(true, 22, "RIGHT", "LEFT", -1, 0, 1, 1, "LEFT", "UP")
        debuff = UUFGroup.AuraLane(false, 22, "LEFT", "RIGHT", 1, 0, 3, 3, "RIGHT", "UP")
    elseif unitKey == "pet" then
        buff = UUFGroup.AuraLane(false, 22, "LEFT", "RIGHT", 1, 0, 1, 1, "RIGHT", "UP")
        debuff = UUFGroup.AuraLane(false, 22, "RIGHT", "LEFT", -1, 0, 3, 3, "LEFT", "UP")
    elseif unitKey == "boss" then
        buff = UUFGroup.AuraLane(true, 42, "LEFT", "RIGHT", 1, 0, 3, 3, "RIGHT", "UP")
        debuff = UUFGroup.AuraLane(false, 34, "BOTTOMRIGHT", "TOPRIGHT", 0, 1, 4, 4, "LEFT", "UP")
    elseif unitKey == "party" or unitKey == "raid" then
        buff = UUFGroup.AuraLane(unitKey == "party", 28, "BOTTOMLEFT", "BOTTOMLEFT", 2, 2, 3, 3, "RIGHT", "UP")
        debuff = UUFGroup.AuraLane(false, 28, "BOTTOMRIGHT", "BOTTOMRIGHT", -2, 2, 4, 4, "LEFT", "UP")
    end
    if not buff or not debuff then return nil end
    return { FrameStrata = (unitKey == "party" or unitKey == "raid") and "MEDIUM" or "LOW", Buffs = buff, Debuffs = debuff }
end

function UUFGroup.AnchorFraction(anchor)
    anchor = tostring(anchor or "CENTER"):upper()
    local x = anchor:find("LEFT", 1, true) and -0.5 or (anchor:find("RIGHT", 1, true) and 0.5 or 0)
    local y = anchor:find("BOTTOM", 1, true) and -0.5 or (anchor:find("TOP", 1, true) and 0.5 or 0)
    return x, y
end

-- Auras3 anchors a lane with the same point on both the lane and its unit
-- frame. UUF supports different point/relativePoint pairs. Keeping UUF's lane
-- point and folding the relative-point delta into the offset preserves the
-- exact screen position without requiring the lane's not-yet-known grid size.
function UUFGroup.NormalizeChildLayout(layout, frameWidth, frameHeight, fallback)
    layout = type(layout) == "table" and layout or {}
    fallback = type(fallback) == "table" and fallback or { "CENTER", "CENTER", 0, 0, 1 }
    local point = MSUF_ProfileIO_NormalizeUUFAnchor(layout[1], fallback[1] or "CENTER")
    local relativePoint = MSUF_ProfileIO_NormalizeUUFAnchor(layout[2], fallback[2] or point)
    local x = UUFGroup.SafeNumber(layout[3], tonumber(fallback[3]) or 0, -16384, 16384)
    local y = UUFGroup.SafeNumber(layout[4], tonumber(fallback[4]) or 0, -16384, 16384)
    local pointX, pointY = UUFGroup.AnchorFraction(point)
    local relativeX, relativeY = UUFGroup.AnchorFraction(relativePoint)
    x = x + (relativeX - pointX) * UUFGroup.SafeNumber(frameWidth, 0, 0, 4096)
    y = y + (relativeY - pointY) * UUFGroup.SafeNumber(frameHeight, 0, 0, 4096)
    return point, x, y, UUFGroup.SafeNumber(layout[5], tonumber(fallback[5]) or 1, 0, 128)
end

function UUFGroup.AuraGrowth(lane)
    local horizontal = type(lane.GrowthDirection) == "string" and lane.GrowthDirection:upper() or "RIGHT"
    local vertical = type(lane.WrapDirection) == "string" and lane.WrapDirection:upper() or "DOWN"
    if horizontal ~= "LEFT" and horizontal ~= "RIGHT" then horizontal = "RIGHT" end
    if vertical ~= "UP" and vertical ~= "DOWN" then vertical = "DOWN" end
    return horizontal, vertical
end

function UUFGroup.BuildUnitAuraConfig(unitKey, source, frameWidth, frameHeight)
    local defaults = UUFGroup.AuraDefaults(unitKey)
    if not defaults then return nil end
    local auras = UUFGroup.MergeDefaults(source, defaults)
    local buff, debuff = auras.Buffs, auras.Debuffs
    local buffAnchor, buffX, buffY, buffSpacing = UUFGroup.NormalizeChildLayout(buff.Layout, frameWidth, frameHeight, defaults.Buffs.Layout)
    local debuffAnchor, debuffX, debuffY, debuffSpacing = UUFGroup.NormalizeChildLayout(debuff.Layout, frameWidth, frameHeight, defaults.Debuffs.Layout)
    local buffGrowthX, buffGrowthY = UUFGroup.AuraGrowth(buff)
    local debuffGrowthX, debuffGrowthY = UUFGroup.AuraGrowth(debuff)
    local buffCount = type(buff.Count) == "table" and buff.Count or defaults.Buffs.Count
    local debuffCount = type(debuff.Count) == "table" and debuff.Count or defaults.Debuffs.Count
    local buffCountLayout = type(buffCount.Layout) == "table" and buffCount.Layout or defaults.Buffs.Count.Layout
    local debuffCountLayout = type(debuffCount.Layout) == "table" and debuffCount.Layout or defaults.Debuffs.Count.Layout
    return {
        enabled = buff.Enabled ~= false or debuff.Enabled ~= false,
        layout = {
            spacing = math.max(buffSpacing, debuffSpacing),
            buffAnchor = buffAnchor,
            buffGroupOffsetX = buffX,
            buffGroupOffsetY = buffY,
            buffGroupIconSize = UUFGroup.SafeNumber(buff.Size, defaults.Buffs.Size, 1, 128),
            debuffAnchor = debuffAnchor,
            debuffGroupOffsetX = debuffX,
            debuffGroupOffsetY = debuffY,
            debuffGroupIconSize = UUFGroup.SafeNumber(debuff.Size, defaults.Debuffs.Size, 1, 128),
            buffStackTextSize = UUFGroup.SafeNumber(buffCount.FontSize, 12, 6, 40),
            buffStackTextOffsetX = UUFGroup.SafeNumber(buffCountLayout[3], 0, -2000, 2000),
            buffStackTextOffsetY = UUFGroup.SafeNumber(buffCountLayout[4], 2, -2000, 2000),
            debuffStackTextSize = UUFGroup.SafeNumber(debuffCount.FontSize, 12, 6, 40),
            debuffStackTextOffsetX = UUFGroup.SafeNumber(debuffCountLayout[3], 0, -2000, 2000),
            debuffStackTextOffsetY = UUFGroup.SafeNumber(debuffCountLayout[4], 2, -2000, 2000),
        },
        shared = {
            showBuffs = buff.Enabled ~= false,
            showDebuffs = debuff.Enabled ~= false,
            maxBuffs = UUFGroup.SafeNumber(buff.Num, defaults.Buffs.Num, 0, 80),
            maxDebuffs = UUFGroup.SafeNumber(debuff.Num, defaults.Debuffs.Num, 0, 80),
            buffPerRow = UUFGroup.SafeNumber(buff.Wrap, defaults.Buffs.Wrap, 1, 40),
            debuffPerRow = UUFGroup.SafeNumber(debuff.Wrap, defaults.Debuffs.Wrap, 1, 40),
            buffGrowthX = buffGrowthX,
            buffGrowthY = buffGrowthY,
            debuffGrowthX = debuffGrowthX,
            debuffGrowthY = debuffGrowthY,
            buffShowStackCount = buffCount.HideStacks ~= true,
            debuffShowStackCount = debuffCount.HideStacks ~= true,
            buffStackCountAnchor = MSUF_ProfileIO_NormalizeUUFAnchor(buffCountLayout[1], "BOTTOMRIGHT"),
            debuffStackCountAnchor = MSUF_ProfileIO_NormalizeUUFAnchor(debuffCountLayout[1], "BOTTOMRIGHT"),
        },
        filters = {
            enabled = true,
            buffs = { onlyMine = buff.OnlyShowPlayer == true, filterToken = buff.OnlyShowPlayer == true and "PLAYER" or "ALL" },
            debuffs = { onlyMine = debuff.OnlyShowPlayer == true, filterToken = debuff.OnlyShowPlayer == true and "PLAYER" or "ALL" },
        },
    }
end

function UUFGroup.ConvertUnitAuras(unitKey, src, outProfile)
    if unitKey ~= "player" and unitKey ~= "target" and unitKey ~= "focus" and unitKey ~= "boss" then return false end
    local dst = type(outProfile[unitKey]) == "table" and outProfile[unitKey] or nil
    if not dst then return false end
    local converted = UUFGroup.BuildUnitAuraConfig(unitKey, type(src) == "table" and src.Auras or nil, dst.width, dst.height)
    if not converted then return false end
    local root = type(outProfile.auras3) == "table" and outProfile.auras3 or {}
    outProfile.auras3 = root
    root.perUnit = type(root.perUnit) == "table" and root.perUnit or {}
    local flag = unitKey == "player" and "showPlayer" or unitKey == "target" and "showTarget" or unitKey == "focus" and "showFocus" or "showBoss"
    root[flag] = converted.enabled
    root.enabled = root.enabled == true or converted.enabled
    local targets = unitKey == "boss" and { "boss1", "boss2", "boss3", "boss4", "boss5" } or { unitKey }
    for i = 1, #targets do
        root.perUnit[targets[i]] = {
            overrideLayout = true,
            overrideSharedLayout = true,
            overrideStyle = true,
            overrideFilters = true,
            layout = MSUF_DeepCopy(converted.layout),
            layoutShared = MSUF_DeepCopy(converted.shared),
            filters = MSUF_DeepCopy(converted.filters),
        }
    end
    return true
end

function UUFGroup.ApplyGroupAuras(kind, src, dst)
    local defaults = UUFGroup.AuraDefaults(kind)
    if not defaults or type(dst) ~= "table" then return false end
    local auras = UUFGroup.MergeDefaults(type(src) == "table" and src.Auras or nil, defaults)
    local buff, debuff = auras.Buffs, auras.Debuffs
    local buffAnchor, buffX, buffY, buffSpacing = UUFGroup.NormalizeChildLayout(buff.Layout, dst.width, dst.height, defaults.Buffs.Layout)
    local debuffAnchor, debuffX, debuffY, debuffSpacing = UUFGroup.NormalizeChildLayout(debuff.Layout, dst.width, dst.height, defaults.Debuffs.Layout)
    local buffGrowthX, buffGrowthY = UUFGroup.AuraGrowth(buff)
    local debuffGrowthX, debuffGrowthY = UUFGroup.AuraGrowth(debuff)
    dst.auras = {
        enabled = buff.Enabled ~= false or debuff.Enabled ~= false,
        renderer = "NATIVE_12_1",
        showTooltip = true,
        buff = {
            enabled = buff.Enabled ~= false,
            max = UUFGroup.SafeNumber(buff.Num, defaults.Buffs.Num, 0, 80),
            size = UUFGroup.SafeNumber(buff.Size, defaults.Buffs.Size, 1, 128),
            spacing = buffSpacing,
            perRow = UUFGroup.SafeNumber(buff.Wrap, defaults.Buffs.Wrap, 1, 40),
            growth = buffGrowthX .. buffGrowthY,
            anchor = buffAnchor,
            x = buffX,
            y = buffY,
            filterToken = buff.OnlyShowPlayer == true and "PLAYER" or "ALL",
            showStacks = not (type(buff.Count) == "table" and buff.Count.HideStacks == true),
        },
        debuff = {
            enabled = debuff.Enabled ~= false,
            max = UUFGroup.SafeNumber(debuff.Num, defaults.Debuffs.Num, 0, 80),
            size = UUFGroup.SafeNumber(debuff.Size, defaults.Debuffs.Size, 1, 128),
            spacing = debuffSpacing,
            perRow = UUFGroup.SafeNumber(debuff.Wrap, defaults.Debuffs.Wrap, 1, 40),
            growth = debuffGrowthX .. debuffGrowthY,
            anchor = debuffAnchor,
            x = debuffX,
            y = debuffY,
            filterToken = debuff.OnlyShowPlayer == true and "PLAYER" or "ALL",
            showStacks = not (type(debuff.Count) == "table" and debuff.Count.HideStacks == true),
        },
        externals = { enabled = false },
    }
    dst.auraIconSize = math.max(dst.auras.buff.size, dst.auras.debuff.size)
    return true
end

function UUFGroup.MergeTag(src, defaults)
    src = type(src) == "table" and src or {}
    defaults = type(defaults) == "table" and defaults or {}
    local sourceLayout = type(src.Layout) == "table" and src.Layout or {}
    local defaultLayout = type(defaults.Layout) == "table" and defaults.Layout or { "CENTER", "CENTER", 0, 0 }
    return {
        Tag = src.Tag == nil and (defaults.Tag or "") or src.Tag,
        FontSize = UUFGroup.SafeNumber(src.FontSize, defaults.FontSize or 12, 6, 72),
        Colour = type(src.Colour) == "table" and src.Colour or defaults.Colour or { 1, 1, 1 },
        Layout = {
            sourceLayout[1] or defaultLayout[1],
            sourceLayout[2] or defaultLayout[2],
            UUFGroup.SafeNumber(sourceLayout[3], defaultLayout[3] or 0, -4096, 4096),
            UUFGroup.SafeNumber(sourceLayout[4], defaultLayout[4] or 0, -4096, 4096),
        },
    }
end

function UUFGroup.TagsForUnit(unitKey, tags)
    tags = type(tags) == "table" and tags or {}
    local empty = { Tag = "", FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "CENTER", "CENTER", 0, 0 } }
    local name = { Tag = "[name]", FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "CENTER", "CENTER", 0, 0 } }
    local health = { Tag = "[curhp:abbr]", FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "RIGHT", "RIGHT", -3, 0 } }
    local power = { Tag = "[powercolor][curpp]", FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "RIGHT", "BOTTOMRIGHT", -3, 2 } }
    if unitKey == "target" or unitKey == "boss" then
        name.Layout = { "LEFT", "LEFT", 3, 0 }
    elseif unitKey == "player" then
        name = empty
    else
        health, power = empty, empty
    end
    return {
        TagOne = UUFGroup.MergeTag(tags.TagOne, name),
        TagTwo = UUFGroup.MergeTag(tags.TagTwo, health),
        TagThree = UUFGroup.MergeTag(tags.TagThree, power),
        TagFour = UUFGroup.MergeTag(tags.TagFour, empty),
        TagFive = UUFGroup.MergeTag(tags.TagFive, empty),
    }
end

function UUFGroup.TagsForGroup(kind, tags)
    tags = type(tags) == "table" and tags or {}
    local empty = { Tag = "", FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "CENTER", "CENTER", 0, 0 } }
    local name = { Tag = "[name]", FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "TOPLEFT", "TOPLEFT", 3, 0 } }
    local health = kind == "party"
        and { Tag = "[perhp]", FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "TOPRIGHT", "TOPRIGHT", -3, 0 } }
        or empty
    return {
        TagOne = UUFGroup.MergeTag(tags.TagOne, name),
        TagTwo = UUFGroup.MergeTag(tags.TagTwo, health),
        TagThree = UUFGroup.MergeTag(tags.TagThree, empty),
        TagFour = UUFGroup.MergeTag(tags.TagFour, empty),
        TagFive = UUFGroup.MergeTag(tags.TagFive, empty),
    }
end

function UUFGroup.ApplyIndicator(dst, src, map)
    if type(dst) ~= "table" or type(src) ~= "table" or type(map) ~= "table" then return end
    dst[map.enabled] = src.Enabled ~= false
    dst[map.size] = UUFGroup.SafeNumber(src.Size, dst[map.size], 1, 256)
    local anchor, x, y = MSUF_ProfileIO_UUFLayout(src.Layout, map.fallbackAnchor or "CENTER", 0, 0)
    dst[map.anchor] = anchor
    dst[map.x] = UUFGroup.SafeNumber(x, 0, -4096, 4096)
    dst[map.y] = UUFGroup.SafeNumber(y, 0, -4096, 4096)
end

function UUFGroup.RoleOrder(value)
    local result, seen = {}, {}
    local function Add(role)
        role = type(role) == "string" and role:upper() or nil
        if role == "DPS" then role = "DAMAGER" end
        if (role == "TANK" or role == "HEALER" or role == "DAMAGER" or role == "NONE") and not seen[role] then
            seen[role] = true
            result[#result + 1] = role
        end
    end
    if type(value) == "table" then
        for i = 1, #value do Add(value[i]) end
    elseif type(value) == "string" then
        for role in value:gmatch("[^,%s]+") do Add(role) end
    end
    Add("TANK")
    Add("HEALER")
    Add("DAMAGER")
    return table.concat(result, ",")
end

function UUFGroup.ApplyTags(dst, tags)
    if type(dst) ~= "table" or type(tags) ~= "table" then return end
    dst.showName = false
    dst.showHPText = false
    dst.showPowerText = false
    dst.showPower = false
    dst.textLeft, dst.textCenter, dst.textRight = "NONE", "NONE", "NONE"
    dst.powerTextLeft, dst.powerTextCenter, dst.powerTextRight = "NONE", "NONE", "NONE"
    dst.fontOverride = true

    for i = 1, 5 do
        local tag = tags["Tag" .. ({ "One", "Two", "Three", "Four", "Five" })[i]]
        local token = type(tag) == "table" and type(tag.Tag) == "string" and tag.Tag or nil
        if token and token ~= "" then
            local point, _, x, y = MSUF_ProfileIO_UUFTagLayout(tag)
            local slot = MSUF_ProfileIO_UUFTextSlotFromPoint(point)
            local lower = token:lower()
            local fontSize = UUFGroup.SafeNumber(tag.FontSize, nil, 6, 72)
            local color = MSUF_ProfileIO_ColorObject(tag.Colour)
            if lower:find("name", 1, true) then
                dst.showName = true
                dst.nameAnchor = slot:upper()
                dst.nameOffsetX = UUFGroup.SafeNumber(x, 0, -4096, 4096)
                dst.nameOffsetY = UUFGroup.SafeNumber(y, 0, -4096, 4096)
                dst.nameFontSize = fontSize or dst.nameFontSize
                if color then
                    dst.nameColorMode = "CUSTOM"
                    dst.nameColorR, dst.nameColorG, dst.nameColorB = color.r, color.g, color.b
                end
            else
                local isPower = lower:find("pp", 1, true) ~= nil
                    or lower:find("power", 1, true) ~= nil
                    or lower:find("mana", 1, true) ~= nil
                local mode = MSUF_ProfileIO_TagToTextMode(token, isPower)
                if mode then
                    if isPower then
                        dst.showPowerText, dst.showPower = true, true
                        dst["powerText" .. slot] = mode
                        dst.powerFontSize = fontSize or dst.powerFontSize
                        dst["powerText" .. slot .. "OffsetX"] = UUFGroup.SafeNumber(x, 0, -4096, 4096)
                        dst["powerText" .. slot .. "OffsetY"] = UUFGroup.SafeNumber(y, 0, -4096, 4096)
                    else
                        dst.showHPText = true
                        dst["text" .. slot] = mode
                        dst.hpFontSize = fontSize or dst.hpFontSize
                        dst["hpText" .. slot .. "OffsetX"] = UUFGroup.SafeNumber(x, 0, -4096, 4096)
                        dst["hpText" .. slot .. "OffsetY"] = UUFGroup.SafeNumber(y, 0, -4096, 4096)
                    end
                    if color then
                        dst.useGlobalFontColor = false
                        dst.fontR, dst.fontG, dst.fontB = color.r, color.g, color.b
                    end
                end
            end
        end
    end
end

function UUFGroup.Convert(kind, src, outProfile)
    if type(outProfile) ~= "table" then return false end
    src = type(src) == "table" and src or {}
    local defaults = UUFGroup.GroupDefaults[kind]
    if type(defaults) ~= "table" then return false end
    local dbKey = kind == "raid" and "gf_raid" or "gf_party"
    local dst = type(outProfile[dbKey]) == "table" and outProfile[dbKey] or {}
    outProfile[dbKey] = dst
    local frame = type(src.Frame) == "table" and src.Frame or {}
    local health = type(src.HealthBar) == "table" and src.HealthBar or {}
    local power = type(src.PowerBar) == "table" and src.PowerBar or {}
    local indicators = type(src.Indicators) == "table" and src.Indicators or {}

    local enabled = src.Enabled
    if enabled == nil then enabled = defaults.enabled end
    local forceHide = src.ForceHideBlizzard
    if forceHide == nil then forceHide = defaults.forceHide end
    dst.enabled = enabled ~= false
    dst.blizzardFallbackMode = forceHide == true and "NONE" or "AUTO"
    dst.width = UUFGroup.SafeNumber(frame.Width or frame.width, defaults.width, 20, 1200)
    dst.height = UUFGroup.SafeNumber(frame.Height or frame.height, defaults.height, 8, 600)
    local layout = type(frame.Layout) == "table" and frame.Layout or {}
    dst.point = MSUF_ProfileIO_NormalizeUUFAnchor(layout[1], defaults.point)
    dst.anchorPoint = dst.point
    dst.relativePoint = MSUF_ProfileIO_NormalizeUUFAnchor(layout[2], defaults.point)
    dst.offsetX = UUFGroup.SafeNumber(layout[3], defaults.x, -16384, 16384)
    dst.offsetY = UUFGroup.SafeNumber(layout[4], defaults.y, -16384, 16384)
    dst.positionMode = "GRID_BOUNDS_V2"
    dst.spacing = UUFGroup.SafeNumber(layout[5], defaults.spacing, 0, 200)
    if type(frame.AnchorParent) == "string" and frame.AnchorParent ~= "" and frame.AnchorParent ~= "UIParent" then
        dst.anchorToFrame = frame.AnchorParent
    else
        dst.anchorToFrame = nil
    end

    local growth = type(frame.GrowthDirection) == "string" and frame.GrowthDirection:upper() or defaults.growth
    local primaryGrowth, groupGrowth = growth:match("^([A-Z]+)_([A-Z]+)$")
    if kind == "raid" and primaryGrowth then
        primaryGrowth = ({ RIGHT = "LEFT", LEFT = "RIGHT", UP = "DOWN", DOWN = "UP" })[primaryGrowth]
        if groupGrowth ~= "UP" and groupGrowth ~= "DOWN" and groupGrowth ~= "LEFT" and groupGrowth ~= "RIGHT" then
            groupGrowth = nil
        end
    else
        primaryGrowth = growth:match("^([A-Z]+)") or "DOWN"
        groupGrowth = nil
    end
    if primaryGrowth ~= "UP" and primaryGrowth ~= "DOWN" and primaryGrowth ~= "LEFT" and primaryGrowth ~= "RIGHT" then
        primaryGrowth = "DOWN"
    end
    dst.growth = primaryGrowth
    dst.groupGrowth = groupGrowth
    local showPlayer = frame.ShowPlayer
    if showPlayer == nil then showPlayer = defaults.showPlayer end
    dst.showPlayer = showPlayer ~= false
    local sortMode = type(frame.SortBy) == "string" and frame.SortBy:upper() or defaults.sort
    if sortMode ~= "NAME" and sortMode ~= "ROLE" and sortMode ~= "GROUP" and sortMode ~= "GROUP_ROLE" then
        sortMode = "INDEX"
    end
    if kind == "party" and (sortMode == "GROUP" or sortMode == "GROUP_ROLE") then sortMode = "INDEX" end
    dst.sortMode = sortMode
    dst.sortByRole = sortMode == "ROLE" or sortMode == "GROUP_ROLE"
    dst.sortByName = sortMode == "NAME"
    dst.roleOrder = UUFGroup.RoleOrder(frame.RoleOrder or defaults.roleOrder)

    if kind == "raid" then
        dst.unitsPerColumn = 5
        dst.preserveRaidGroups = true
        local groups, enabledGroups, highestEnabledGroup = {}, 0, 0
        if frame.AutoAdjustGroups ~= true then
            for i = 1, 8 do
                local groupValue
                if type(frame.Groups) == "table" then
                    groupValue = frame.Groups[i]
                    if groupValue == nil then groupValue = frame.Groups[tostring(i)] end
                end
                if groupValue == nil then groupValue = defaults.groups[i] end
                groups[i] = groupValue == true
                if groups[i] then
                    enabledGroups = enabledGroups + 1
                    highestEnabledGroup = i
                end
            end
        else
            for i = 1, 8 do groups[i] = true end
            enabledGroups, highestEnabledGroup = 8, 8
        end
        if enabledGroups == 0 then
            for i = 1, 8 do groups[i] = defaults.groups[i] == true end
            enabledGroups, highestEnabledGroup = 4, 4
        end
        dst.groupFilter = groups
        dst.maxColumns = highestEnabledGroup
    end

    local healthDefaults = UUFGroup.DefaultHealth
    local inverse = health.Inverse
    if inverse == nil then inverse = healthDefaults.Inverse end
    local smooth = health.Smooth
    if smooth == nil then smooth = healthDefaults.Smooth end
    local colourByClass = health.ColourByClass
    if colourByClass == nil then colourByClass = healthDefaults.ColourByClass end
    dst.reverseFill = inverse == true
    dst.smoothFill = smooth == true
    dst.hpBarAlpha = UUFGroup.SafeNumber(health.ForegroundOpacity, healthDefaults.ForegroundOpacity, 0, 1)
    dst.hpBgAlpha = UUFGroup.SafeNumber(health.BackgroundOpacity, healthDefaults.BackgroundOpacity, 0, 1)
    if colourByClass ~= false then
        dst.healthColorMode = "CLASS"
    else
        dst.healthColorMode = "CUSTOM"
        local r, g, b = MSUF_ProfileIO_Color(health.Foreground or healthDefaults.Foreground, 8 / 255, 8 / 255, 8 / 255, 1)
        dst.healthCustomR, dst.healthCustomG, dst.healthCustomB = r, g, b
    end
    local br, bg, bb = MSUF_ProfileIO_Color(health.Background or healthDefaults.Background, nil, nil, nil, nil)
    if br and bg and bb then dst.bgR, dst.bgG, dst.bgB = br, bg, bb end
    if type(health.DispelHighlight) == "table" then
        dst.dispelEnabled = health.DispelHighlight.Enabled ~= false
        dst.dispelOverlayEnabled = health.DispelHighlight.Enabled ~= false
        dst.dispelOverlayStyle = health.DispelHighlight.Style == "GRADIENT" and "FULL" or dst.dispelOverlayStyle
    end

    local powerDefaults = UUFGroup.DefaultPower
    local powerEnabled = power.Enabled
    if powerEnabled == nil then powerEnabled = powerDefaults.Enabled end
    local powerSmooth = power.Smooth
    if powerSmooth == nil then powerSmooth = powerDefaults.Smooth end
    local onlyHealers = power.OnlyShowHealers
    if onlyHealers == nil then onlyHealers = powerDefaults.OnlyShowHealers end
    dst.powerBarEnabled = powerEnabled ~= false
    dst.powerHeight = UUFGroup.SafeNumber(power.Height, powerDefaults.Height, 1, 100)
    dst.powerSmoothFill = powerSmooth == true
    dst.powerShowHealer = true
    dst.powerShowTank = onlyHealers ~= true
    dst.powerShowDamager = onlyHealers ~= true

    local prediction = type(src.HealPrediction) == "table" and src.HealPrediction or nil
    if prediction then
        local incoming = type(prediction.IncomingHeal) == "table" and prediction.IncomingHeal
            or type(prediction.Incoming) == "table" and prediction.Incoming or nil
        local absorbs = type(prediction.Absorbs) == "table" and prediction.Absorbs or nil
        local healAbsorbs = type(prediction.HealAbsorbs) == "table" and prediction.HealAbsorbs or nil
        dst.hlOverride = true
        if incoming then dst.healPredEnabled = incoming.Enabled == true end
        if absorbs then dst.enableAbsorbBar = absorbs.Enabled ~= false end
        if healAbsorbs then dst.healAbsorbEnabled = healAbsorbs.Enabled ~= false end
        MSUF_ProfileIO_ConvertUUFHealPrediction({ Incoming = incoming, Absorbs = absorbs, HealAbsorbs = healAbsorbs }, nil, outProfile.general)
    end

    local target = type(indicators.Target) == "table" and indicators.Target or nil
    if target then
        dst.targetIndicator = target.Enabled ~= false
        local r, g, b = MSUF_ProfileIO_Color(target.Colour, nil, nil, nil, nil)
        if r and g and b then dst.targetR, dst.targetG, dst.targetB = r, g, b end
    end
    local threat = type(indicators.Threat) == "table" and indicators.Threat or nil
    if threat then dst.aggroEnabled = threat.Enabled ~= false end
    local role = type(indicators.Role) == "table" and indicators.Role or nil
    if role then
        UUFGroup.ApplyIndicator(dst, role, { enabled = "roleIcon", size = "roleIconSize", anchor = "roleIconAnchor", x = "roleIconX", y = "roleIconY", fallbackAnchor = "TOPLEFT" })
        dst.roleIconShowTank = role.ShowTank ~= false
        dst.roleIconShowHealer = role.ShowHealer ~= false
        dst.roleIconShowDPS = role.ShowDamager ~= false
    end
    UUFGroup.ApplyIndicator(dst, indicators.RaidTargetMarker, { enabled = "raidMarker", size = "raidMarkerSize", anchor = "raidMarkerAnchor", x = "raidMarkerX", y = "raidMarkerY" })
    UUFGroup.ApplyIndicator(dst, indicators.LeaderAssistantIndicator, { enabled = "leaderIcon", size = "leaderIconSize", anchor = "leaderIconAnchor", x = "leaderIconX", y = "leaderIconY", fallbackAnchor = "TOPRIGHT" })
    if type(indicators.LeaderAssistantIndicator) == "table" then dst.assistIcon = indicators.LeaderAssistantIndicator.Enabled ~= false end
    UUFGroup.ApplyIndicator(dst, indicators.ReadyCheckIndicator, { enabled = "readyCheckIcon", size = "readyCheckSize", anchor = "readyCheckAnchor", x = "readyCheckX", y = "readyCheckY" })
    UUFGroup.ApplyIndicator(dst, indicators.ResurrectIndicator or indicators.Resurrection, { enabled = "resurrectIcon", size = "resurrectIconSize", anchor = "resurrectAnchor", x = "resurrectX", y = "resurrectY" })
    UUFGroup.ApplyIndicator(dst, indicators.Summon, { enabled = "summonIcon", size = "summonIconSize", anchor = "summonAnchor", x = "summonX", y = "summonY" })
    UUFGroup.ApplyIndicator(dst, indicators.Phase, { enabled = "phaseIcon", size = "phaseIconSize", anchor = "phaseAnchor", x = "phaseX", y = "phaseY", fallbackAnchor = "TOPLEFT" })
    UUFGroup.ApplyTags(dst, UUFGroup.TagsForGroup(kind, src.Tags))
    UUFGroup.ApplyGroupAuras(kind, src, dst)
    return true
end

local function MSUF_ProfileIO_CopyUUFGeneral(src, outProfile)
    if type(src) ~= "table" then return end
    local g = outProfile.general or {}
    local bars = outProfile.bars or {}
    outProfile.general = g
    outProfile.bars = bars
    local ui = type(src.UIScale) == "table" and src.UIScale or nil
    if ui then
        g.UIScale = {
            Enabled = ui.Enabled == true,
            Scale = tonumber(ui.Scale) or 1.0,
        }
        g.globalUiScalePreset = g.UIScale.Enabled and "custom" or "auto"
        g.globalUiScaleValue = g.UIScale.Enabled and g.UIScale.Scale or nil
    end
    local textures = type(src.Textures) == "table" and src.Textures or nil
    if textures then
        g.barTexture = textures.Foreground or g.barTexture
        g.barBackgroundTexture = textures.Background or g.barBackgroundTexture
        g.castbarTexture = textures.Foreground or g.castbarTexture
        g.castbarBackgroundTexture = textures.Background or g.castbarBackgroundTexture
    end
    local fonts = type(src.Fonts) == "table" and src.Fonts or nil
    if fonts then
        g.fontKey = fonts.Font or g.fontKey
        local flag = type(fonts.FontFlag) == "string" and fonts.FontFlag:upper() or nil
        if flag then
            local compact = flag:gsub("[%s,_%-]", "")
            local hasOutline = compact:find("OUTLINE", 1, true) ~= nil
            local hasThick = compact:find("THICKOUTLINE", 1, true) ~= nil
            g.noOutline = compact == "" or compact == "NONE" or not hasOutline
            g.boldText = hasThick
            g.fontMonochrome = flag:find("MONOCHROME", 1, true) ~= nil
        end
        local shadow = type(fonts.Shadow) == "table" and fonts.Shadow or nil
        if shadow then
            g.textBackdrop = shadow.Enabled == true
            if g.textBackdrop then
                local _, _, _, sa = MSUF_ProfileIO_Color(shadow.Colour, nil, nil, nil, nil)
                local sx = math.abs(tonumber(shadow.XPos) or 1)
                local sy = math.abs(tonumber(shadow.YPos) or -1)
                if sx >= 2 or sy >= 2 then
                    g.fontShadowStrength = "DEEP"
                elseif sa and sa < 0.75 then
                    g.fontShadowStrength = "SOFT"
                else
                    g.fontShadowStrength = "NORMAL"
                end
            end
        end
    end
    local range = type(src.Range) == "table" and src.Range or nil
    if range then
        g.rangeFadeEnabled = range.Enabled ~= false
        g.rangeFadeAlpha = tonumber(range.OutOfRange) or g.rangeFadeAlpha
        for _, unitKey in ipairs({ "target", "targettarget", "focustarget", "focus", "pet", "boss" }) do
            outProfile[unitKey] = outProfile[unitKey] or {}
            outProfile[unitKey].rangeFadeEnabled = range.Enabled ~= false
            outProfile[unitKey].rangeFadeAlpha = tonumber(range.OutOfRange) or outProfile[unitKey].rangeFadeAlpha
        end
    end
    if src.Separator ~= nil then
        g.hpTextSeparator = tostring(src.Separator)
        g.powerTextSeparator = tostring(src.Separator)
    end
    if src.ToTSeparator ~= nil then
        g.totInlineSeparator = tostring(src.ToTSeparator)
    end
    g.useShortNumbers = src.UseCustomAbbreviations ~= true

    local colours = type(src.Colours) == "table" and src.Colours or nil
    if colours then
        if type(colours.Reaction) == "table" then
            outProfile.npcColors = type(outProfile.npcColors) == "table" and outProfile.npcColors or {}
            local function CopyReaction(kind, index, fallbackIndex)
                local c = colours.Reaction[index] or colours.Reaction[fallbackIndex]
                local r, g, b = MSUF_ProfileIO_Color(c, nil, nil, nil, nil)
                if r and g and b then
                    outProfile.npcColors[kind] = { r = r, g = g, b = b }
                end
            end
            CopyReaction("enemy", 2, 1)
            CopyReaction("neutral", 4, 3)
            CopyReaction("friendly", 5, 6)
        end
        local powerOverrides = {}
        if type(colours.Power) == "table" then
            for powerType, color in pairs(colours.Power) do
                local c = MSUF_ProfileIO_CopyColorTable(color)
                if c then powerOverrides[powerType] = { r = c[1], g = c[2], b = c[3] } end
            end
        end
        if next(powerOverrides) then
            g.powerColorOverrides = powerOverrides
        end
        local classPowerOverrides = {}
        if type(colours.SecondaryPower) == "table" then
            for powerType, color in pairs(colours.SecondaryPower) do
                local c = MSUF_ProfileIO_CopyColorTable(color)
                if c then classPowerOverrides[powerType] = { r = c[1], g = c[2], b = c[3] } end
            end
        end
        if next(classPowerOverrides) then
            g.classPowerColorOverrides = classPowerOverrides
        end
    end
end

local function MSUF_ProfileIO_GetUUFImportBase(profileKey)
    MSUF_ProfileIO_RunEnsureDB(true)
    if type(MSUF_InitProfiles) == "function" then
        MSUF_InitProfiles()
    end
    if type(profileKey) == "string" and profileKey ~= ""
        and type(MSUF_GlobalDB) == "table"
        and type(MSUF_GlobalDB.profiles) == "table"
        and type(MSUF_GlobalDB.profiles[profileKey]) == "table" then
        return MSUF_DeepCopy(MSUF_GlobalDB.profiles[profileKey])
    end
    if type(MSUF_DB) == "table" then
        return MSUF_DeepCopy(MSUF_DB)
    end
    return {}
end

local function MSUF_ProfileIO_ConvertUUFProfile(profile, baseProfile)
    if type(profile) ~= "table" then return nil end
    local out = type(baseProfile) == "table" and MSUF_DeepCopy(baseProfile) or {}
    out.general = type(out.general) == "table" and out.general or {}
    out.bars = type(out.bars) == "table" and out.bars or {}
    out.gameplay = type(out.gameplay) == "table" and out.gameplay or {}
    out._uufImport = {
        source = "UnhaltedUnitFrames",
        aurasApplied = false,
        groupFramesApplied = false,
    }
    out.general.disableBlizzardUnitFrames = true
    out.general.hardKillBlizzardPlayerFrame = true
    out.general.anchorToCooldown = false
    out.general.anchorName = "UIParent"
    out.general.msufUiScale = 1.0
    MSUF_ProfileIO_ResetUUFSharedFontControls(out)
    out.general.nameClassColor = false
    out.general.npcNameRed = false
    out.general.nameNpcClassColor = false
    out.general.colorHealthTextByHealth = false
    out.general.colorPowerTextByType = false
    out.general.npcColorMode = "reaction"
    MSUF_ProfileIO_CopyUUFGeneral(profile.General, out)

    local units = type(profile.Units) == "table" and profile.Units or {}
    MSUF_ProfileIO_ConvertUUFUnit("player", units.player, out)
    MSUF_ProfileIO_ConvertUUFUnit("target", units.target, out)
    MSUF_ProfileIO_ConvertUUFUnit("targettarget", units.targettarget or units.targetoftarget or units.tot, out)
    MSUF_ProfileIO_ConvertUUFUnit("focus", units.focus, out)
    MSUF_ProfileIO_ConvertUUFUnit("focustarget", units.focustarget or units.focus_target, out)
    MSUF_ProfileIO_ConvertUUFUnit("pet", units.pet, out)
    MSUF_ProfileIO_ConvertUUFUnit("boss", units.boss, out)
    local auraApplied = false
    auraApplied = UUFGroup.ConvertUnitAuras("player", units.player, out) or auraApplied
    auraApplied = UUFGroup.ConvertUnitAuras("target", units.target, out) or auraApplied
    auraApplied = UUFGroup.ConvertUnitAuras("focus", units.focus, out) or auraApplied
    auraApplied = UUFGroup.ConvertUnitAuras("boss", units.boss, out) or auraApplied
    local partyApplied = UUFGroup.Convert("party", units.party, out)
    local raidApplied = UUFGroup.Convert("raid", units.raid, out)
    out._uufImport.groupFramesApplied = partyApplied == true or raidApplied == true
    out._uufImport.aurasApplied = auraApplied == true
    if type(out.targettarget) == "table" then
        out.targettarget.showToTInTargetName = false
    end

    local g = out.general
    local playerHealth = units.player and units.player.HealthBar
    if type(playerHealth) ~= "table" then
        playerHealth = units.target and units.target.HealthBar
    end
    if type(playerHealth) ~= "table" then
        playerHealth = UUFGroup.DefaultHealth
    end
    if type(playerHealth) == "table" then
        if playerHealth.ColourByClass == false then
            g.barMode = "unified"
            g.useClassColors = false
            g.darkMode = false
            local r, gc, b = MSUF_ProfileIO_Color(playerHealth.Foreground or UUFGroup.DefaultHealth.Foreground, 0.1, 0.6, 0.9, 1)
            g.unifiedBarR, g.unifiedBarG, g.unifiedBarB = r, gc, b
        else
            g.barMode = "class"
            g.useClassColors = true
            g.darkMode = false
        end
        local br, bg, bb = MSUF_ProfileIO_Color(playerHealth.Background or UUFGroup.DefaultHealth.Background, nil, nil, nil, nil)
        if br and bg and bb then
            g.classBarBgR, g.classBarBgG, g.classBarBgB = br, bg, bb
            g.darkBgCustomColor = true
        end
    end

    local playerPower = units.player and units.player.PowerBar
    if type(playerPower) ~= "table" then
        playerPower = UUFGroup.DefaultPower
    end
    if type(playerPower) == "table" then
        if playerPower.ColourByType == false then
            g.powerColorMode = "static"
            local r, gc, b = MSUF_ProfileIO_Color(playerPower.Foreground or UUFGroup.DefaultPower.Foreground, 0.1, 0.35, 0.95, 1)
            g.powerBarColorR, g.powerBarColorG, g.powerBarColorB = r, gc, b
        else
            g.powerColorMode = "power"
        end
    end

    local castbar = units.player and (units.player.CastBar or units.player.Castbar)
    if type(castbar) == "table" then
        local r, gc, b = MSUF_ProfileIO_Color(castbar.Foreground, nil, nil, nil, nil)
        if r and gc and b then
            g.castbarCustomR, g.castbarCustomG, g.castbarCustomB = r, gc, b
            g.playerCastbarOverrideMode = "CUSTOM"
            g.playerCastbarOverrideR, g.playerCastbarOverrideG, g.playerCastbarOverrideB = r, gc, b
        end
        local br, bg, bb = MSUF_ProfileIO_Color(castbar.Background, nil, nil, nil, nil)
        if br and bg and bb then
            g.castbarBgR, g.castbarBgG, g.castbarBgB = br, bg, bb
        end
        local nr, ng, nb = MSUF_ProfileIO_Color(castbar.NotInterruptibleColour, nil, nil, nil, nil)
        if nr and ng and nb then
            g.castbarNonInterruptibleCustomR, g.castbarNonInterruptibleCustomG, g.castbarNonInterruptibleCustomB = nr, ng, nb
        end
    end
    MSUF_ProfileIO_NormalizeUniformUUFTextColor(out)
    MSUF_ProfileIO_NormalizeUUFScopedFontInheritance(out)
    return out
end
local function MSUF_ApplyLegacyTableToActiveProfile(tbl, isUUFImport)
    if type(tbl) ~= "table" then
        print("|cffff0000MSUF:|r Legacy import failed: not a table.")
         return false
    end
    isUUFImport = isUUFImport == true or MSUF_ProfileIO_IsUUFConvertedPayload(tbl)
    local valid, validationError = MSUF.ProfileIOValidateImportValue(tbl)
    if not valid then
        print("|cffff0000MSUF:|r Legacy import failed: " .. tostring(validationError))
        return false
    end
    local prepared, staged = pcall(function()
        local copy = MSUF_DeepCopy(tbl)
        MSUF_ProfileIO_TranslateProfileToCurrent(copy, {
            source = isUUFImport and "uuf_import" or "legacy_import",
            markProfile = true,
        })
        return copy
    end)
    if not prepared or type(staged) ~= "table" then
        print("|cffff0000MSUF:|r Legacy import failed during staging: " .. tostring(staged))
        return false
    end
    tbl = staged
    MSUF_ProfileIO_RunEnsureDB()
    if isUUFImport then
        MSUF_ProfileIO_ClearUUFUnitFrameScreenCache()
    end
    MSUF_ProfileIO_CollectProfileMediaWarnings(tbl)
    --- Keep profile table reference stable; wipe + copy.
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    MSUF_WipeTable(MSUF_DB)
    for k, v in pairs(tbl) do
        if MSUF_ProfileIO_ShouldPersistRootProfileKey(k) then
            MSUF_DB[k] = v
        end
    end
    if type(MSUF_GlobalDB) == "table" and type(MSUF_GlobalDB.profiles) == "table" and MSUF_ActiveProfile then
        MSUF_GlobalDB.profiles[MSUF_ActiveProfile] = MSUF_DB
    end
    MSUF_ProfileIO_RunEnsureDB(true)
    MSUF.ProfileIOCompleteFirstLoadImport()
    if isUUFImport and MSUF.ProfileIOIsUUFAddonLoaded() then
        -- UUF and MSUF both intercept Blizzard frame parenting. Applying MSUF
        -- live while UUF is loaded recurses between both SetParent hooks and
        -- aborts the import with a C stack overflow. The converted profile is
        -- already persisted above; defer every live rebuild until UUF is
        -- disabled and the UI is reloaded.
        ExportPublic("MSUF_ProfileIO_LastImportDeferredRuntime", true)
        print("|cffffd700MSUF:|r UUF profile saved. Disable UnhaltedUnitFrames, then reload the UI to apply it safely.")
        MSUF_ProfileIO_ReportImportWarnings()
        return true
    end
    MSUF_ProfileIO_EnsureUnitframeAlphaDB()
    MSUF_ProfileIO_PostImportApply_Auras("all", tbl, isUUFImport)
    MSUF_ProfileIO_PostImportApply_GroupFrames("all", tbl, isUUFImport)
    MSUF_ProfileIO_PostImportApply_UnitAlphas("all", tbl)
    MSUF_ProfileIO_PostProfileRuntimeApply(isUUFImport and "PROFILE_IMPORT" or "PROFILE_LEGACY_IMPORT", true)
    if isUUFImport then
        -- UUF can switch a profile from Blizzard-owned frames back to MSUF and
        -- can also replace every anchor in one transaction. Re-register the
        -- existence watches and invalidate live position caches after the full
        -- apply so previously hidden frames cannot remain hidden or stale.
        MSUF_ProfileIO_CallGlobal("MSUF_RefreshAllUnitVisibilityDrivers")
        MSUF_ProfileIO_CallGlobal("MSUF_ForceReanchorAllUnitFrames_Once")
    end
    if not isUUFImport then
        print("|cff00ff00MSUF:|r Legacy profile imported into the active profile.")
    end
    MSUF_ProfileIO_ReportImportWarnings()
     return true
end
--- New import: understands snapshots (fmt=2) and applies selection into active profile.
--- New import: understands MSUF2/MSUF3/MSUF4 compact strings, snapshots (fmt=2), and legacy full dumps.
function MSUF_ImportFromString(str)
    MSUF_ProfileIO_ResetImportWarnings()
    ExportPublic("MSUF_ProfileIO_LastImportDeferredRuntime", nil)
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Import failed (empty string).")
         return false
    end
    if MSUF_ProfileIO_IsUUFImportString(str) then
        local uufProfile, why = MSUF_ProfileIO_DecodeUUFProfileString(str)
        if type(uufProfile) ~= "table" then
            print("|cffff0000MSUF:|r UUF import failed: " .. tostring(why))
            return false
        end
        local converted = MSUF_ProfileIO_ConvertUUFProfile(uufProfile, MSUF_ProfileIO_GetUUFImportBase())
        if type(converted) ~= "table" then
            print("|cffff0000MSUF:|r UUF import failed: profile conversion failed.")
            return false
        end
        local ok = MSUF_ApplyLegacyTableToActiveProfile(converted, true)
        if ok then
            print("|cff00ff00MSUF:|r UUF profile imported into the active profile.")
        end
        return ok == true
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
    local ok, tbl = pcall(func)
    if not ok then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(tbl))
         return false
    end
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
    ExportPublic("MSUF_ProfileIO_LastImportDeferredRuntime", nil)
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Legacy import failed (empty string).")
         return false
    end
    if MSUF_ProfileIO_IsUUFImportString(str) then
        local uufProfile, why = MSUF_ProfileIO_DecodeUUFProfileString(str)
        if type(uufProfile) ~= "table" then
            print("|cffff0000MSUF:|r UUF import failed: " .. tostring(why))
            return false
        end
        local converted = MSUF_ProfileIO_ConvertUUFProfile(uufProfile, MSUF_ProfileIO_GetUUFImportBase())
        if type(converted) ~= "table" then
            print("|cffff0000MSUF:|r UUF import failed: profile conversion failed.")
            return false
        end
        local ok = MSUF_ApplyLegacyTableToActiveProfile(converted, true)
        if ok then
            print("|cff00ff00MSUF:|r UUF profile imported into the active profile.")
        end
        return ok == true
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
    local ok, tbl = pcall(func)
    if not ok then
        print("|cffff0000MSUF:|r Legacy import failed: " .. tostring(tbl))
         return false
    end
    return ImportDecodedLegacyTable(tbl)
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
    local ok, result = pcall(fn)
    MSUF_DB = oldDB
    ExportPublic("MSUF_ProfileIO_SuppressRuntimeSideEffects", oldSuppressRuntimeSideEffects)
    if type(auras3) == "table" then
        auras3.DBRef = oldAuras3DBRef
    end
    local invalidateGF = _G.MSUF_GF_InvalidateConfCache
    if type(invalidateGF) == "function" then
        pcall(invalidateGF)
    else
        local gf = MSUF and MSUF.GF
        if gf and type(gf.InvalidateConfCache) == "function" then
            pcall(gf.InvalidateConfCache)
        end
    end
    if not ok then
        return false, result
    end
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
    local ok, why = MSUF_ProfileIO_WithTemporaryProfileDB(profile, function()
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
    if not ok then
        ExportPublic("MSUF_ProfileIO_LastExportMaterializeError", tostring(profileKey or "profile") .. ": " .. tostring(why))
        return nil, "profile materialization failed"
    end
    return profile
end
local function MSUF_ProfileIO_OverwriteProfile(profileKey, newTable, isUUFImport)
    if type(profileKey) ~= "string" or profileKey == "" then
         return false, "invalid profileKey"
    end
    if type(newTable) ~= "table" then
         return false, "not a table"
    end
    isUUFImport = isUUFImport == true or MSUF_ProfileIO_IsUUFConvertedPayload(newTable)
    local valid, validationError = MSUF.ProfileIOValidateImportValue(newTable)
    if not valid then return false, validationError end
    local prepared, staged = pcall(function()
        local copy = MSUF_DeepCopy(newTable)
        MSUF_ProfileIO_TranslateProfileToCurrent(copy, {
            source = isUUFImport and "external_uuf_import" or "external_import",
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
    if not prepared or type(staged) ~= "table" then return false, "profile staging failed: " .. tostring(staged) end
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
        local postPayload = isUUFImport and newTable or target
        if isUUFImport then
            MSUF_ProfileIO_ClearUUFUnitFrameScreenCache()
        end
        MSUF_WipeTable(target)
        for k, v in pairs(newTable) do
            if MSUF_ProfileIO_ShouldPersistRootProfileKey(k) then
                target[k] = v
            end
        end
        MSUF_GlobalDB.profiles[profileKey] = target
        MSUF_ProfileIO_RunEnsureDB(true)
        MSUF.ProfileIOCompleteFirstLoadImport()
        if isUUFImport and MSUF.ProfileIOIsUUFAddonLoaded() then
            ExportPublic("MSUF_ProfileIO_LastImportDeferredRuntime", true)
            MSUF_ProfileIO_ReportImportWarnings()
            return true
        end
        MSUF_ProfileIO_EnsureUnitframeAlphaDB()
        MSUF_ProfileIO_PostImportApply_Auras("all", postPayload, isUUFImport)
        MSUF_ProfileIO_PostImportApply_GroupFrames("all", postPayload, isUUFImport)
        MSUF_ProfileIO_PostImportApply_UnitAlphas("all", postPayload)
        MSUF_ProfileIO_PostProfileRuntimeApply("PROFILE_EXTERNAL_IMPORT", true)
        if isUUFImport then
            MSUF_ProfileIO_CallGlobal("MSUF_RefreshAllUnitVisibilityDrivers")
            MSUF_ProfileIO_CallGlobal("MSUF_ForceReanchorAllUnitFrames_Once")
        end
        MSUF_ProfileIO_ReportImportWarnings()
         return true
    end
    if type(existing) == "table" then
        --- For non-active profiles we can still preserve reference stability if something else points at it.
        MSUF_WipeTable(existing)
        for k, v in pairs(newTable) do
            if MSUF_ProfileIO_ShouldPersistRootProfileKey(k) then
                existing[k] = v
            end
        end
        MSUF_GlobalDB.profiles[profileKey] = existing
        MSUF_ProfileIO_ReportImportWarnings()
        MSUF.ProfileIOCompleteFirstLoadImport()
         return true
    end
    local stored = {}
    for k, v in pairs(newTable) do
        if MSUF_ProfileIO_ShouldPersistRootProfileKey(k) then
            stored[k] = v
        end
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
    ExportPublic("MSUF_ProfileIO_LastImportDeferredRuntime", nil)
    if type(profileString) ~= "string" or not profileString:match("%S") then
         return false, "empty profileString"
    end
    if type(profileKey) ~= "string" or profileKey == "" then
         return false, "invalid profileKey"
    end
    if MSUF_ProfileIO_IsUUFImportString(profileString) then
        local uufProfile, why = MSUF_ProfileIO_DecodeUUFProfileString(profileString)
        if type(uufProfile) ~= "table" then
            return false, "UUF import failed: " .. tostring(why)
        end
        local converted = MSUF_ProfileIO_ConvertUUFProfile(uufProfile, MSUF_ProfileIO_GetUUFImportBase(profileKey))
        if type(converted) ~= "table" then
            return false, "UUF import failed: profile conversion failed"
        end
        return MSUF_ProfileIO_OverwriteProfile(profileKey, converted, true)
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
    local ok, tbl = pcall(func)
    if not ok or type(tbl) ~= "table" then
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
ExportPublic("MSUF_Profiles_IsUUFImportString", MSUF_ProfileIO_IsUUFImportString)
--- Globals for the Options module.
ExportPublic("MSUF_ExportSelectionToString", MSUF_ExportSelectionToString)
ExportPublic("MSUF_ImportFromString", MSUF_ImportFromString)
ExportPublic("MSUF_ImportLegacyFromString", MSUF_ImportLegacyFromString)
ExportPublic("MSUF_IsUUFImportString", MSUF_ProfileIO_IsUUFImportString)
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
    MSUF.MSUF_IsUUFImportString       = MSUF_ProfileIO_IsUUFImportString
    MSUF.MSUF_ProfileIO_TranslateProfileToCurrent = MSUF_ProfileIO_TranslateProfileToCurrent
    MSUF.MSUF_ProfileIO_TranslateProfilesToCurrent = MSUF_ProfileIO_TranslateProfilesToCurrent
end
