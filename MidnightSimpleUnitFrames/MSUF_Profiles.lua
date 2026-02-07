-- Extracted from MidnightSimpleUnitFrames.lua (profiles + active profile state)
local addonName, ns = ...
-- Compact codec (backward compatible)
--
-- New export format (preferred):
--   MSUF3: base64(CBOR(table)) using Blizzard C_EncodingUtil
--
-- Legacy import formats supported:
--   MSUF2: LibDeflate 'print-safe' encoding of deflate-compressed payload (common Wago/WA style)
--   MSUF2: base64(deflate(CBOR(table))) from earlier internal experiments
--
-- Design goals:
--   * Export always uses Blizzard (MSUF3) when available.
--   * Import accepts MSUF3 + legacy MSUF2 variants automatically.
--   * For MSUF2 print-safe, we decode the print alphabet ourselves and then use Blizzard
--     DecompressString when available (no bundled LibDeflate needed).
--   * Never fall back to legacy loadstring() for MSUF2/MSUF3 prefixes.
do
    local function GetEncodingUtil()
        local E = _G.C_EncodingUtil
        if type(E) ~= "table" then  return nil end
        if type(E.SerializeCBOR) ~= "function" then  return nil end
        if type(E.DeserializeCBOR) ~= "function" then  return nil end
        if type(E.EncodeBase64) ~= "function" then  return nil end
        if type(E.DecodeBase64) ~= "function" then  return nil end
        -- Compress/Decompress are optional depending on branch/client.
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
    -- LibDeflate's print-safe alphabet is 64 chars:
    -- 0-9, A-Z, a-z, (, )
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
    -- Decode LibDeflate:EncodeForPrint output into raw bytes.
    -- LibDeflate's print codec has existed in multiple implementations; to be robust,
    -- we try BOTH bit-order variants (LSB-first and MSB-first) and accept whichever
    -- yields a payload that successfully decompresses/deserializes.
    local function DecodeForPrint_Variants(data)
        if type(data) ~= "string" or data == "" then  return nil, nil end
        data = StripWS(data)
        local map = EnsurePrintMap()
        -- Variant A: LSB-first packing
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
        -- Variant B: MSB-first packing
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
                    -- keep only the remaining low bits
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
    local function TryBlizzardDecompress(E, compressed)
        if not E or type(compressed) ~= "string" then  return nil end
        if type(E.DecompressString) ~= "function" then  return nil end
        local method = GetDeflateEnum()
        local ok, res
        if method ~= nil then
            ok, res = pcall(E.DecompressString, compressed, method)
            if ok and type(res) == "string" then  return res end
        end
        ok, res = pcall(E.DecompressString, compressed)
        if ok and type(res) == "string" then  return res end
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
    local function TryDeserialize(E, payload)
        if not E or type(payload) ~= "string" then  return nil end
        -- 1) CBOR via Blizzard
        local ok, tbl = pcall(E.DeserializeCBOR, payload)
        if ok and type(tbl) == "table" then
             return tbl
        end
        -- 2) AceSerializer (optional, if present)
        if _G.LibStub and type(_G.LibStub.GetLibrary) == "function" then
            local Ace = _G.LibStub:GetLibrary("AceSerializer-3.0", true)
            if Ace and type(Ace.Deserialize) == "function" then
                local ok2, success, t = pcall(Ace.Deserialize, payload)
                if ok2 and success and type(t) == "table" then
                     return t
                end
            end
        end
        -- 3) Very old MSUF legacy may have stored a Lua table literal.
        --    Only attempt if it looks like a table (avoid executing arbitrary code).
        local trimmed = payload:match("^%s*(.-)%s*$")
        if trimmed and trimmed:sub(1,1) == "{" and trimmed:sub(-1) == "}" then
            local fn = loadstring and loadstring("return " .. trimmed)
            if fn then
                local ok3, t = pcall(fn)
                if ok3 and type(t) == "table" then
                     return t
                end
            end
        end
         return nil
    end
    local function EncodeCompactTable(tbl)
        local E = GetEncodingUtil()
        if not E then  return nil end
        local ok1, bin = pcall(E.SerializeCBOR, tbl)
        if not ok1 or type(bin) ~= "string" then  return nil end
        -- Prefer smaller strings when compression exists.
        local payload = TryBlizzardCompress(E, bin) or bin
        local ok2, b64 = pcall(E.EncodeBase64, payload)
        if not ok2 or type(b64) ~= "string" then  return nil end
        return "MSUF3:" .. b64
    end
    local function TryDecodeCompactString(str)
        if type(str) ~= "string" then  return nil end
        local E = GetEncodingUtil()
        if not E then  return nil end
        local s = str:match("^%s*(.-)%s*$")
        if not s then  return nil end
        -- MSUF3: base64(CBOR) [optionally compressed]
        do
            local b64 = s:match("^MSUF3:%s*(.+)$")
            if b64 then
                b64 = StripWS(b64)
                local ok1, blob = pcall(E.DecodeBase64, b64)
                if ok1 and type(blob) == "string" then
                    local plain = TryBlizzardDecompress(E, blob) or blob
                    local t = TryDeserialize(E, plain)
                    if t then  return t end
                end
                 return nil
            end
        end
        -- MSUF2: legacy variants
        do
            local payload = s:match("^MSUF2:%s*(.+)$")
            if not payload then  return nil end
            payload = payload:gsub("^%s+", ""):gsub("%s+$", "")
            -- 1) Try Blizzard base64 first (older internal MSUF2 variant)
            local b64 = StripWS(payload)
            local ok1, blob = pcall(E.DecodeBase64, b64)
            if ok1 and type(blob) == "string" then
                local plain = TryBlizzardDecompress(E, blob) or blob
                local t = TryDeserialize(E, plain)
                if t then  return t end
            end
            -- 2) Try LibDeflate print-safe (Wago/WA style)
            local raw_lsb, raw_msb = DecodeForPrint_Variants(payload)
            if raw_lsb then
                local plain = TryBlizzardDecompress(E, raw_lsb) or raw_lsb
                local t = TryDeserialize(E, plain)
                if t then  return t end
            end
            if raw_msb then
                local plain = TryBlizzardDecompress(E, raw_msb) or raw_msb
                local t = TryDeserialize(E, plain)
                if t then  return t end
            end
            -- 3) Hard fallback: if LibDeflate is available (from another addon), try it.
            local ld = _G.LibDeflate
            if ld and type(ld.DecodeForPrint) == "function" and type(ld.DecompressDeflate) == "function" then
                local okDec, raw = pcall(ld.DecodeForPrint, ld, payload)
                if okDec and type(raw) == "string" then
                    local okDecomp, plain = pcall(ld.DecompressDeflate, ld, raw)
                    if okDecomp and type(plain) == "string" then
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
    _G.MSUF_EncodeCompactTable = _G.MSUF_EncodeCompactTable or EncodeCompactTable
    _G.MSUF_TryDecodeCompactString = _G.MSUF_TryDecodeCompactString or TryDecodeCompactString
end
function MSUF_GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end
function MSUF_InitProfiles()
    MSUF_GlobalDB = MSUF_GlobalDB or {}
    MSUF_GlobalDB.profiles = MSUF_GlobalDB.profiles or {}
    MSUF_GlobalDB.char = MSUF_GlobalDB.char or {}
    local charKey = MSUF_GetCharKey()
    local char = MSUF_GlobalDB.char[charKey] or {}
    MSUF_GlobalDB.char[charKey] = char
    local active = char.activeProfile
    if not next(MSUF_GlobalDB.profiles) then
        local base = MSUF_DB or {}
        MSUF_GlobalDB.profiles["Default"] = CopyTable(base)
        if not active then
            active = "Default"
        end
        print("|cff00ff00MSUF:|r Migrated existing settings into profile 'Default'.")
    end
    if not active then
        active = "Default"
    end
    if not MSUF_GlobalDB.profiles[active] then
        local fallback
        for _, tbl in pairs(MSUF_GlobalDB.profiles) do
            fallback = tbl
            break
        end
        MSUF_GlobalDB.profiles[active] = CopyTable(fallback or {})
    end
    char.activeProfile = active
    MSUF_ActiveProfile = active
    MSUF_DB = MSUF_GlobalDB.profiles[active]
 end
function MSUF_CreateProfile(name)
    if not name or name == "" then  return end
    MSUF_GlobalDB = MSUF_GlobalDB or {}
    MSUF_GlobalDB.profiles = MSUF_GlobalDB.profiles or {}
    if MSUF_GlobalDB.profiles[name] then
        print("|cffff0000MSUF:|r Profile '"..name.."' already exists.")
         return
    end
    MSUF_GlobalDB.profiles[name] = CopyTable(MSUF_DB or {})
    print("|cff00ff00MSUF:|r Created new profile '"..name.."'.")
 end
function MSUF_SwitchProfile(name)
    if not name or not MSUF_GlobalDB or not MSUF_GlobalDB.profiles or not MSUF_GlobalDB.profiles[name] then
        print("|cffff0000MSUF:|r Unknown profile: "..tostring(name))
         return
    end
    local charKey = MSUF_GetCharKey()
    MSUF_GlobalDB.char = MSUF_GlobalDB.char or {}
    local char = MSUF_GlobalDB.char[charKey] or {}
    MSUF_GlobalDB.char[charKey] = char
    char.activeProfile = name
    MSUF_ActiveProfile = name
    MSUF_DB = MSUF_GlobalDB.profiles[name]
    -- Invalidate cached config references (UFCore caches per-frame config table refs).
    do
        local ns = _G.MSUF_NS
        local core = (type(ns) == "table" and ns.MSUF_UnitframeCore) or nil
        if core and type(core.InvalidateAllFrameConfigs) == "function" then
            core.InvalidateAllFrameConfigs()
        end
    end
    if EnsureDB then
        EnsureDB()
    end
    if ApplyAllSettings then
        ApplyAllSettings()
    end
    if UpdateAllFonts then
        UpdateAllFonts()
    end
    print("|cff00ff00MSUF:|r Switched to profile '"..name.."'.")
 end
function MSUF_ResetProfile(name)
    name = name or MSUF_ActiveProfile
    if not name or not MSUF_GlobalDB or not MSUF_GlobalDB.profiles or not MSUF_GlobalDB.profiles[name] then
         return
    end
    MSUF_GlobalDB.profiles[name] = {}
    if name == MSUF_ActiveProfile then
        MSUF_DB = MSUF_GlobalDB.profiles[name]
        if EnsureDB then
            EnsureDB()
        end
        if ApplyAllSettings then
            ApplyAllSettings()
        end
        if UpdateAllFonts then
            UpdateAllFonts()
        end
    end
    print("|cffffd700MSUF:|r Profile '"..name.."' reset to defaults.")
 end
function MSUF_DeleteProfile(name)
    name = name or MSUF_ActiveProfile
    if not name or not MSUF_GlobalDB or not MSUF_GlobalDB.profiles or not MSUF_GlobalDB.profiles[name] then
         return
    end
    if name == "Default" then
        print("|cffff0000MSUF:|r You cannot delete the 'Default' profile. Use Reset instead.")
         return
    end
    local fallbackName
    for profileName in pairs(MSUF_GlobalDB.profiles) do
        if profileName ~= name then
            fallbackName = fallbackName or profileName
        end
    end
    if not fallbackName then
        print("|cffff0000MSUF:|r Cannot delete the last remaining profile.")
         return
    end
    if MSUF_GlobalDB.char then
        for _, char in pairs(MSUF_GlobalDB.char) do
            if char.activeProfile == name then
                char.activeProfile = fallbackName
            end
        end
    end
    MSUF_GlobalDB.profiles[name] = nil
    if MSUF_ActiveProfile == name then
        MSUF_SwitchProfile(fallbackName)
    end
    print("|cffffd700MSUF:|r Profile '"..name.."' deleted.")
 end
function MSUF_GetAllProfiles()
    local list = {}
    if MSUF_GlobalDB and MSUF_GlobalDB.profiles then
        for name in pairs(MSUF_GlobalDB.profiles) do
            table.insert(list, name)
        end
        table.sort(list)
    end
     return list
end
---------------------------------------------------------------------
-- Spec-based profile auto-switch (per-character)
--
-- Stored in:
--   MSUF_GlobalDB.char[charKey].specAutoSwitch  (boolean)
--   MSUF_GlobalDB.char[charKey].specProfileMap  (table: specID -> profileName)
--
-- Design goals:
--   - Very small, fully optional (off by default).
--   - Combat-safe: if spec changes in combat, we defer the switch.
--   - Works with existing global profiles (no DB migration needed).
---------------------------------------------------------------------
local function MSUF_GetCharMeta()
    _G.MSUF_GlobalDB = _G.MSUF_GlobalDB or {}
    local gdb = _G.MSUF_GlobalDB
    gdb.char = gdb.char or {}
    local charKey = (type(_G.MSUF_GetCharKey) == "function") and _G.MSUF_GetCharKey() or (UnitName("player") .. "-" .. GetRealmName())
    local char = gdb.char[charKey]
    if type(char) ~= "table" then
        char = {}
        gdb.char[charKey] = char
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
        if type(_G.MSUF_ApplySpecProfileIfEnabled) == "function" then
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
            if type(_G.MSUF_ApplySpecProfileIfEnabled) == "function" then
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
-- Combat-safe deferrer (shared)
local function MSUF_RunAfterCombat_SpecProfile(fn)
    if type(fn) ~= "function" then  return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        _G.MSUF_PendingSpecProfileSwitch = fn
        local f = _G.MSUF_SpecProfileDeferFrame
        if not f and type(_G.CreateFrame) == "function" then
            f = _G.CreateFrame("Frame")
            _G.MSUF_SpecProfileDeferFrame = f
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function()
                local pending = _G.MSUF_PendingSpecProfileSwitch
                if pending then
                    _G.MSUF_PendingSpecProfileSwitch = nil
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
    -- Only switch to existing profiles.
    if not (_G.MSUF_GlobalDB and _G.MSUF_GlobalDB.profiles and _G.MSUF_GlobalDB.profiles[profileName]) then
         return
    end
    if _G.MSUF_ActiveProfile == profileName then
         return
    end
    MSUF_RunAfterCombat_SpecProfile(function()
        -- Re-check after combat (spec could have changed again).
        if not MSUF_IsSpecAutoSwitchEnabled() then  return end
        local cur = MSUF_GetPlayerSpecID()
        if cur ~= specID then  return end
        local mapped = MSUF_GetSpecProfile(specID)
        if mapped ~= profileName then  return end
        if _G.MSUF_ActiveProfile == profileName then  return end
        if type(_G.MSUF_SwitchProfile) == "function" then
            _G.MSUF_SwitchProfile(profileName)
        end
     end)
 end
-- Event driver (very small; only does work when enabled)
do
    local f
    local function EnsureFrame()
        if f then  return end
        if type(_G.CreateFrame) ~= "function" then  return end
        f = _G.CreateFrame("Frame")
        _G.MSUF_SpecProfileEventFrame = f
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_LOGIN")
        f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        f:SetScript("OnEvent", function(_, event, arg1)
            if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
                 return
            end
            if not MSUF_IsSpecAutoSwitchEnabled() then
                 return
            end
            MSUF_ApplySpecProfileIfEnabled(event)
         end)
     end
    EnsureFrame()
end
---------------------------------------------------------------------
-- Profile Export / Import (Selection-based, with legacy import button)
--
-- New snapshot format (Lua table):
--   return {
--     addon   = "MSUF",
--     fmt     = 2,
--     schema  = 1,
--     kind    = "unitframe" | "castbar" | "colors" | "gameplay" | "all",
--     profile = "<active profile name>",
--     payload = { ...selected settings... },
--   }
--
-- Import behavior:
--   - If the snapshot matches the format above: apply only the selected category into the
--     CURRENT ACTIVE profile (keeps everything else unchanged).
--   - Legacy import (old "return { ... }" profile dump) remains available via
--     MSUF_ImportLegacyFromString(str).
---------------------------------------------------------------------
local function MSUF_WipeTable(t)
    if type(t) ~= "table" then  return end
    for k in pairs(t) do
        t[k] = nil
    end
 end
local function MSUF_DeepCopy(v)
    if type(v) ~= "table" then  return v end
    if type(CopyTable) == "function" then
        return CopyTable(v)
    end
    -- Fallback deep copy (should rarely be needed)
    local out = {}
    for k, vv in pairs(v) do
        out[k] = MSUF_DeepCopy(vv)
    end
     return out
end
-- Deterministic-ish Lua serializer (good enough for UI copy/paste strings).
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
             return nil -- handled by serTable
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
-- Key classification for general settings.
local function MSUF_IsColorKey(k)
    if type(k) ~= "string" then  return false end
    local lk = string.lower(k)
    -- Obvious markers
    if lk:find("color", 1, true) then  return true end
    -- Global theme/mode keys
    if lk == "barmode" or lk == "darkmode" or lk == "darkbartone" or lk == "darkbgbrightness" then  return true end
    if lk == "useclasscolors" or lk == "enablegradient" or lk == "gradientstrength" then  return true end
    -- Font/Highlight naming
    if lk == "fontcolor" or lk == "highlightcolor" or lk == "usecustomfontcolor" then  return true end
    if lk == "nameclasscolor" or lk == "npcnamered" then  return true end
    -- Common RGB/A suffix patterns used for colors.
    local last = lk:sub(-1)
    if last == "r" or last == "g" or last == "b" or last == "a" then
        -- Avoid false positives like "offsetx/offsety".
        if lk:find("color", 1, true) or lk:find("font", 1, true) or lk:find("bg", 1, true) or lk:find("border", 1, true) or lk:find("outline", 1, true) or lk:find("gradient", 1, true) then
             return true
        end
        -- Explicit known custom font color fields
        if lk == "fontcolorcustomr" or lk == "fontcolorcustomg" or lk == "fontcolorcustomb" then
             return true
        end
    end
     return false
end
-- Aura-related general keys that should travel with Auras settings (even though they are 'color keys').
local MSUF_AURA_GENERAL_KEYS = {
aurasOwnBuffHighlightColor = true,
    aurasOwnDebuffHighlightColor = true,
    aurasStackCountColor = true,
}
local function MSUF_IsAuraGeneralKey(key)
    return (type(key) == "string") and (MSUF_AURA_GENERAL_KEYS[key] == true)
end
local function MSUF_IsCastbarKey(k)
    if type(k) ~= "string" then  return false end
    local lk = string.lower(k)
    -- Core castbar markers
    if lk:find("castbar", 1, true) then  return true end
    if lk:find("bosscast", 1, true) then  return true end
    if lk:find("empower", 1, true) then  return true end
    -- Enable toggles / timing
    if lk == "enableplayercastbar" or lk == "enabletargetcastbar" or lk == "enablefocuscastbar" then  return true end
    if lk == "castbarupdateinterval" then  return true end
    -- Per-castbar font override fields (global storage)
    if lk:find("spellnamefontsize", 1, true) or lk:find("timefontsize", 1, true) then  return true end
     return false
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
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    for k in pairs(g) do
        if filterFn(k, g[k]) then
            g[k] = nil
        end
    end
 end
local function MSUF_ApplyGeneralSubset(tbl)
    if type(tbl) ~= "table" then  return end
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    for k, v in pairs(tbl) do
        g[k] = MSUF_DeepCopy(v)
    end
 end
local function MSUF_SnapshotForKind(kind)
    EnsureDB()
    local payload = {}
    if kind == "unitframe" then
        -- Everything EXCEPT: gameplay, colors, castbars
        for k, v in pairs(MSUF_DB or {}) do
            if k == "general" then
                payload.general = MSUF_CopyGeneralSubset(function(key)
                    return ((not MSUF_IsColorKey(key)) or MSUF_IsAuraGeneralKey(key)) and (not MSUF_IsCastbarKey(key))
                end)
            elseif k == "classColors" or k == "npcColors" or k == "gameplay" then
                -- exclude
            else
                payload[k] = MSUF_DeepCopy(v)
            end
        end
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
    elseif kind == "all" then
        payload = MSUF_DeepCopy(MSUF_DB or {})
    else
         return nil
    end
    return {
        addon   = "MSUF",
        fmt     = 2,
        schema  = 1,
        kind    = kind,
        profile = MSUF_ActiveProfile or "Default",
        payload = payload,
    }
end
-- After a profile import we must explicitly refresh Auras/Auras2 so the live UI matches without /reload.
-- Keep this scoped (Auras only) to avoid unintended regressions in other modules.
local function MSUF_ProfileIO_PostImportApply_Auras(kind, payload)
    if type(payload) ~= "table" then  return end
    local touched = false
    if type(payload.auras2) == "table" then
        touched = true
    else
        local g = payload.general
        if type(g) == "table" then
            for k in pairs(MSUF_AURA_GENERAL_KEYS) do
                if g[k] ~= nil then
                    touched = true
                    break
                end
            end
        end
    end
    if not touched then  return end
    if type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end
    if type(_G.MSUF_Auras2_ApplyFontsFromGlobal) == "function" then
        _G.MSUF_Auras2_ApplyFontsFromGlobal()
    end
    -- Legacy auras (if still present in the build / older profiles).
    if type(_G.MSUF_UpdateTargetAuras) == "function" then
        _G.MSUF_UpdateTargetAuras()
    end
 end
local function MSUF_ApplySnapshotToActiveProfile(snapshot)
    if type(snapshot) ~= "table" then  return false, "not a table" end
    local kind = snapshot.kind
    local payload = snapshot.payload
    if type(kind) ~= "string" or type(payload) ~= "table" then
         return false, "invalid snapshot"
    end
    EnsureDB()
    -- Always keep the profile-table reference stable (important!).
    MSUF_DB = MSUF_DB or {}
    if kind == "unitframe" then
        -- Wipe & replace non-color/non-castbar general keys
        MSUF_WipeGeneralSubset(function(key)
            return (not MSUF_IsColorKey(key)) and (not MSUF_IsCastbarKey(key))
        end)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general)
        end
        for k, v in pairs(payload) do
            if k ~= "general" then
                if type(v) == "table" then
                    MSUF_DB[k] = MSUF_DB[k] or {}
                    MSUF_WipeTable(MSUF_DB[k])
                    for kk, vv in pairs(v) do
                        MSUF_DB[k][kk] = MSUF_DeepCopy(vv)
                    end
                else
                    MSUF_DB[k] = v
                end
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
        MSUF_DB.classColors = MSUF_DB.classColors or {}
        MSUF_DB.npcColors   = MSUF_DB.npcColors or {}
        MSUF_WipeTable(MSUF_DB.classColors)
        MSUF_WipeTable(MSUF_DB.npcColors)
        for kk, vv in pairs(payload.classColors or {}) do
            MSUF_DB.classColors[kk] = MSUF_DeepCopy(vv)
        end
        for kk, vv in pairs(payload.npcColors or {}) do
            MSUF_DB.npcColors[kk] = MSUF_DeepCopy(vv)
        end
    elseif kind == "gameplay" then
        MSUF_DB.gameplay = MSUF_DB.gameplay or {}
        MSUF_WipeTable(MSUF_DB.gameplay)
        for kk, vv in pairs(payload.gameplay or {}) do
            MSUF_DB.gameplay[kk] = MSUF_DeepCopy(vv)
        end
    elseif kind == "all" then
        MSUF_WipeTable(MSUF_DB)
        for kk, vv in pairs(payload) do
            MSUF_DB[kk] = MSUF_DeepCopy(vv)
        end
    else
         return false, "unknown kind"
    end
    -- Ensure the active profile table in GlobalDB points to MSUF_DB.
    if MSUF_GlobalDB and MSUF_GlobalDB.profiles and MSUF_ActiveProfile then
        MSUF_GlobalDB.profiles[MSUF_ActiveProfile] = MSUF_DB
    end
    EnsureDB()
    MSUF_ProfileIO_PostImportApply_Auras(snapshot.kind, payload)
     return true
end
function MSUF_ExportSelectionToString(kind)
    local snap = MSUF_SnapshotForKind(kind)
    if not snap then
         return nil
    end
    local enc = _G.MSUF_EncodeCompactTable
    if type(enc) == "function" then
        local compact = enc(snap)
        if compact then
             return compact
        end
    end
    -- 0-regression fallback
    return MSUF_SerializeLuaTable(snap)
end
local function MSUF_ApplyLegacyTableToActiveProfile(tbl)
    if type(tbl) ~= "table" then
        print("|cffff0000MSUF:|r Legacy import failed: not a table.")
         return false
    end
    EnsureDB()
    -- Keep profile table reference stable; wipe + copy.
    MSUF_DB = MSUF_DB or {}
    MSUF_WipeTable(MSUF_DB)
    for k, v in pairs(tbl) do
        MSUF_DB[k] = MSUF_DeepCopy(v)
    end
    if MSUF_GlobalDB and MSUF_GlobalDB.profiles and MSUF_ActiveProfile then
        MSUF_GlobalDB.profiles[MSUF_ActiveProfile] = MSUF_DB
    end
    EnsureDB()
    print("|cff00ff00MSUF:|r Legacy profile imported into the active profile.")
     return true
end
-- New import: understands snapshots (fmt=2) and applies selection into active profile.
-- New import: understands MSUF2 compact strings, snapshots (fmt=2), and legacy full dumps.
function MSUF_ImportFromString(str)
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Import failed (empty string).")
         return
    end
    -- NEW: compact path (no loadstring)
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        local decoded = tryDec(str)
        if type(decoded) == "table" then
            local tbl = decoded
            -- Snapshot format?
            if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" and type(tbl.kind) == "string" then
                local okApply, why = MSUF_ApplySnapshotToActiveProfile(tbl)
                if okApply then
                    print("|cff00ff00MSUF:|r Imported " .. tostring(tbl.kind) .. " settings into the active profile.")
                else
                    print("|cffff0000MSUF:|r Import failed: " .. tostring(why))
                end
                 return
            end
            -- Otherwise treat decoded table as legacy full-profile dump.
            MSUF_ApplyLegacyTableToActiveProfile(tbl)
             return
        end
    end
    -- If this looks like a compact MSUF2/MSUF3 string, NEVER attempt loadstring.
    local prefix = str:match("^%s*(MSUF%d+):")
    if prefix == "MSUF2" or prefix == "MSUF3" then
        print("|cffff0000MSUF:|r Import failed: could not decode compact profile string (" .. prefix .. ").")
         return
    end
    -- OLD PATH (Lua table string)
    local func, err = loadstring(str)
    if not func then
        func, err = loadstring("return " .. str)
    end
    if not func then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(err))
         return
    end
    local ok, tbl = pcall(func)
    if not ok then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(tbl))
         return
    end
    if type(tbl) ~= "table" then
        print("|cffff0000MSUF:|r Import failed: not a table.")
         return
    end
    -- Snapshot format?
    if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" and type(tbl.kind) == "string" then
        local okApply, why = MSUF_ApplySnapshotToActiveProfile(tbl)
        if okApply then
            print("|cff00ff00MSUF:|r Imported " .. tostring(tbl.kind) .. " settings into the active profile.")
        else
            print("|cffff0000MSUF:|r Import failed: " .. tostring(why))
        end
         return
    end
    -- Otherwise treat it as legacy full-profile dump.
    MSUF_ApplyLegacyTableToActiveProfile(tbl)
 end
-- Legacy import: replaces the entire ACTIVE profile with the provided table.
function MSUF_ImportLegacyFromString(str)
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Legacy import failed (empty string).")
         return
    end
    -- NEW: allow MSUF2: strings in legacy import
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        local decoded = tryDec(str)
        if type(decoded) == "table" then
            MSUF_ApplyLegacyTableToActiveProfile(decoded)
             return
        end
    end
    -- If this looks like a compact MSUF2/MSUF3 string, NEVER attempt loadstring.
    local prefix = str:match("^%s*(MSUF%d+):")
    if prefix == "MSUF2" or prefix == "MSUF3" then
        print("|cffff0000MSUF:|r Legacy import failed: could not decode compact profile string (" .. prefix .. ").")
         return
    end
    local func, err = loadstring(str)
    if not func then
        func, err = loadstring("return " .. str)
    end
    if not func then
        print("|cffff0000MSUF:|r Legacy import failed: " .. tostring(err))
         return
    end
    local ok, tbl = pcall(func)
    if not ok then
        print("|cffff0000MSUF:|r Legacy import failed: " .. tostring(tbl))
         return
    end
    MSUF_ApplyLegacyTableToActiveProfile(tbl)
 end
---------------------------------------------------------------------
-- External Wago UI Packs API (stateless by profileKey)
--
-- Goals:
--  - Allow tools to export/import a SPECIFIC profile by key without switching MSUF_ActiveProfile.
--  - Keep DB table references stable (important for runtime caches) when overwriting the ACTIVE profile.
--  - Zero regression: existing import/export code paths remain unchanged.
--
-- API:
--   ok, strOrErr = MSUF_ExportExternal(profileKey)
--   ok, errOrNil = MSUF_ImportExternal(profileString, profileKey)
---------------------------------------------------------------------
local function MSUF_ProfileIO_EnsureProfilesTable()
    if not MSUF_GlobalDB or type(MSUF_GlobalDB) ~= "table" then
        MSUF_GlobalDB = {}
    end
    if type(MSUF_GlobalDB.profiles) ~= "table" then
        MSUF_GlobalDB.profiles = {}
    end
 end
local function MSUF_ProfileIO_GetProfileTable(profileKey)
    if type(profileKey) ~= "string" or profileKey == "" then
         return nil
    end
    -- Ensure profile system is initialized (safe, used elsewhere via EnsureDB()).
    if type(EnsureDB) == "function" then
        EnsureDB()
    elseif type(MSUF_InitProfiles) == "function" then
        MSUF_InitProfiles()
    end
    MSUF_ProfileIO_EnsureProfilesTable()
    return MSUF_GlobalDB.profiles[profileKey]
end
local function MSUF_ProfileIO_OverwriteProfile(profileKey, newTable)
    if type(profileKey) ~= "string" or profileKey == "" then
         return false, "invalid profileKey"
    end
    if type(newTable) ~= "table" then
         return false, "not a table"
    end
    MSUF_ProfileIO_EnsureProfilesTable()
    local existing = MSUF_GlobalDB.profiles[profileKey]
    local isActive = (profileKey == MSUF_ActiveProfile)
    -- Keep references stable for ACTIVE profile (and if someone holds a ref to the existing table).
    if isActive and type(MSUF_DB) == "table" then
        -- Prefer wiping the active table ref (MSUF_DB) to avoid cache/reference drift.
        local target = MSUF_DB
        MSUF_WipeTable(target)
        for k, v in pairs(newTable) do
            target[k] = MSUF_DeepCopy(v)
        end
        MSUF_GlobalDB.profiles[profileKey] = target
         return true
    end
    if type(existing) == "table" then
        -- For non-active profiles we can still preserve reference stability if something else points at it.
        MSUF_WipeTable(existing)
        for k, v in pairs(newTable) do
            existing[k] = MSUF_DeepCopy(v)
        end
        MSUF_GlobalDB.profiles[profileKey] = existing
         return true
    end
    MSUF_GlobalDB.profiles[profileKey] = MSUF_DeepCopy(newTable)
     return true
end
function MSUF_ExportExternal(profileKey)
    local profileTbl = MSUF_ProfileIO_GetProfileTable(profileKey)
    if type(profileTbl) ~= "table" then
         return false, "unknown profileKey"
    end
    local snap = {
        addon   = "MSUF",
        fmt     = 2,
        schema  = 1,
        kind    = "all",
        profile = profileKey,
        payload = MSUF_DeepCopy(profileTbl),
    }
    local enc = _G.MSUF_EncodeCompactTable
    if type(enc) == "function" then
        local compact = enc(snap)
        if type(compact) == "string" and compact:match("%S") then
             return true, compact
        end
    end
    -- 0-regression fallback (rare): return Lua snapshot.
    return true, MSUF_SerializeLuaTable(snap)
end
function MSUF_ImportExternal(profileString, profileKey)
    if type(profileString) ~= "string" or not profileString:match("%S") then
         return false, "empty profileString"
    end
    if type(profileKey) ~= "string" or profileKey == "" then
         return false, "invalid profileKey"
    end
    -- Prefer compact decode (no loadstring).
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        local decoded = tryDec(profileString)
        if type(decoded) == "table" then
            local tbl = decoded
            -- Snapshot format? (fmt=2)
            if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" and type(tbl.kind) == "string" then
                -- For external import we treat snapshot.payload as the full profile table when kind == "all".
                if tbl.kind == "all" then
                    return MSUF_ProfileIO_OverwriteProfile(profileKey, tbl.payload)
                end
                -- If some tool ever passes a partial snapshot, store the whole decoded table as-is (safer than half-applying).
                return MSUF_ProfileIO_OverwriteProfile(profileKey, tbl)
            end
            -- Otherwise treat decoded table as a full profile dump.
            return MSUF_ProfileIO_OverwriteProfile(profileKey, tbl)
        end
    end
    -- If it looks like a compact MSUF2/MSUF3 string, but decode failed, do NOT loadstring it.
    local prefix = profileString:match("^%s*(MSUF%d+):")
    if prefix == "MSUF2" or prefix == "MSUF3" then
        return false, "could not decode compact profile string (" .. tostring(prefix) .. ")"
    end
    -- Optional legacy table-string support (last resort).
    local func = loadstring(profileString)
    if not func then
        func = loadstring("return " .. profileString)
    end
    if not func then
         return false, "invalid lua table string"
    end
    local ok, tbl = pcall(func)
    if not ok or type(tbl) ~= "table" then
         return false, "lua decode failed"
    end
    return MSUF_ProfileIO_OverwriteProfile(profileKey, tbl)
end
-- Expose real implementations under stable, explicit names for load-order proxies.
_G.MSUF_Profiles_ExportExternal = MSUF_ExportExternal
_G.MSUF_Profiles_ImportExternal = MSUF_ImportExternal
-- Globals for the Options module.
_G.MSUF_ExportSelectionToString = _G.MSUF_ExportSelectionToString or MSUF_ExportSelectionToString
_G.MSUF_ImportFromString        = _G.MSUF_ImportFromString        or MSUF_ImportFromString
_G.MSUF_ImportLegacyFromString  = _G.MSUF_ImportLegacyFromString  or MSUF_ImportLegacyFromString
-- Always expose the real implementations under stable, explicit names.
-- This lets other modules (or load-order proxies) call the correct logic even if _G.MSUF_ImportFromString was set earlier.
_G.MSUF_Profiles_ExportSelectionToString = MSUF_ExportSelectionToString
_G.MSUF_Profiles_ImportFromString        = MSUF_ImportFromString
_G.MSUF_Profiles_ImportLegacyFromString  = MSUF_ImportLegacyFromString
if type(ns) == "table" then
    ns.MSUF_ExportSelectionToString = ns.MSUF_ExportSelectionToString or MSUF_ExportSelectionToString
    ns.MSUF_ImportFromString        = ns.MSUF_ImportFromString        or MSUF_ImportFromString
    ns.MSUF_ImportLegacyFromString  = ns.MSUF_ImportLegacyFromString  or MSUF_ImportLegacyFromString
end
