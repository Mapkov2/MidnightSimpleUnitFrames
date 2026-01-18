-- MSUF_Profiles.lua
-- Extracted from MidnightSimpleUnitFrames.lua (profiles + active profile state)

local addonName, ns = ...
-- Compact codec (MSUF2: base64(deflate(cbor(table))))
do
    local function MSUF_GetEncodingUtil()
        local E = _G.C_EncodingUtil
        if type(E) ~= "table" then return nil end
        if type(E.SerializeCBOR) ~= "function" then return nil end
        if type(E.DeserializeCBOR) ~= "function" then return nil end
        if type(E.CompressString) ~= "function" then return nil end
        if type(E.DecompressString) ~= "function" then return nil end
        if type(E.EncodeBase64) ~= "function" then return nil end
        if type(E.DecodeBase64) ~= "function" then return nil end
        return E
    end

    local function MSUF_EncodeCompactTable(tbl)
        local E = MSUF_GetEncodingUtil()
        if not E then return nil end

        local ok1, bin = pcall(E.SerializeCBOR, tbl)
        if not ok1 or type(bin) ~= "string" then return nil end

        local method = (_G.Enum and _G.Enum.CompressionMethod and _G.Enum.CompressionMethod.Deflate) or nil

        local ok2, comp
        if method ~= nil then
            ok2, comp = pcall(E.CompressString, bin, method, 9)
            if not ok2 or type(comp) ~= "string" then
                ok2, comp = pcall(E.CompressString, bin, method)
            end
        end
        if not ok2 or type(comp) ~= "string" then
            ok2, comp = pcall(E.CompressString, bin)
        end
        if not ok2 or type(comp) ~= "string" then return nil end

        local ok3, b64 = pcall(E.EncodeBase64, comp)
        if not ok3 or type(b64) ~= "string" then return nil end

        return "MSUF2:" .. b64
    end

    local function MSUF_TryDecodeCompactString(str)
        if type(str) ~= "string" then return nil end
        local b64 = str:match("^%s*MSUF2:%s*(.-)%s*$")
        if not b64 then return nil end

        local E = MSUF_GetEncodingUtil()
        if not E then return nil end

        b64 = b64:gsub("%s+", "") -- allow pasted newlines

        local ok1, comp = pcall(E.DecodeBase64, b64)
        if not ok1 or type(comp) ~= "string" then return nil end

        local method = (_G.Enum and _G.Enum.CompressionMethod and _G.Enum.CompressionMethod.Deflate) or nil

        local ok2, bin
        if method ~= nil then
            ok2, bin = pcall(E.DecompressString, comp, method)
        end
        if not ok2 or type(bin) ~= "string" then
            ok2, bin = pcall(E.DecompressString, comp)
        end
        if not ok2 or type(bin) ~= "string" then return nil end

        local ok3, tbl = pcall(E.DeserializeCBOR, bin)
        if not ok3 or type(tbl) ~= "table" then return nil end

        return tbl
    end

    _G.MSUF_EncodeCompactTable = _G.MSUF_EncodeCompactTable or MSUF_EncodeCompactTable
    _G.MSUF_TryDecodeCompactString = _G.MSUF_TryDecodeCompactString or MSUF_TryDecodeCompactString
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
    if not name or name == "" then return end

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
    if type(t) ~= "table" then return end
    for k in pairs(t) do
        t[k] = nil
    end
end

local function MSUF_DeepCopy(v)
    if type(v) ~= "table" then return v end
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
    if type(k) ~= "string" then return false end
    local lk = string.lower(k)

    -- Obvious markers
    if lk:find("color", 1, true) then return true end

    -- Global theme/mode keys
    if lk == "barmode" or lk == "darkmode" or lk == "darkbartone" or lk == "darkbgbrightness" then return true end
    if lk == "useclasscolors" or lk == "enablegradient" or lk == "gradientstrength" then return true end

    -- Font/Highlight naming
    if lk == "fontcolor" or lk == "highlightcolor" or lk == "usecustomfontcolor" then return true end
    if lk == "nameclasscolor" or lk == "npcnamered" then return true end

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
    aurasDispelBorderColor = true,
    aurasStealableBorderColor = true,
    aurasOwnBuffHighlightColor = true,
    aurasOwnDebuffHighlightColor = true,
    aurasStackCountColor = true,
}

local function MSUF_IsAuraGeneralKey(key)
    return (type(key) == "string") and (MSUF_AURA_GENERAL_KEYS[key] == true)
end


local function MSUF_IsCastbarKey(k)
    if type(k) ~= "string" then return false end
    local lk = string.lower(k)

    -- Core castbar markers
    if lk:find("castbar", 1, true) then return true end
    if lk:find("bosscast", 1, true) then return true end
    if lk:find("empower", 1, true) then return true end

    -- Enable toggles / timing
    if lk == "enableplayercastbar" or lk == "enabletargetcastbar" or lk == "enablefocuscastbar" then return true end
    if lk == "castbarupdateinterval" then return true end

    -- Per-castbar font override fields (global storage)
    if lk:find("spellnamefontsize", 1, true) or lk:find("timefontsize", 1, true) then return true end

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
    if type(tbl) ~= "table" then return end
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
    if type(payload) ~= "table" then return end

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

    if not touched then return end

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
    if type(snapshot) ~= "table" then return false, "not a table" end

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


-- Globals for the Options module.
_G.MSUF_ExportSelectionToString = _G.MSUF_ExportSelectionToString or MSUF_ExportSelectionToString
_G.MSUF_ImportFromString        = _G.MSUF_ImportFromString        or MSUF_ImportFromString
_G.MSUF_ImportLegacyFromString  = _G.MSUF_ImportLegacyFromString  or MSUF_ImportLegacyFromString

if type(ns) == "table" then
    ns.MSUF_ExportSelectionToString = ns.MSUF_ExportSelectionToString or MSUF_ExportSelectionToString
    ns.MSUF_ImportFromString        = ns.MSUF_ImportFromString        or MSUF_ImportFromString
    ns.MSUF_ImportLegacyFromString  = ns.MSUF_ImportLegacyFromString  or MSUF_ImportLegacyFromString
end