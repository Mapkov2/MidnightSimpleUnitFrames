-- Every key any language pack defines must exist in all twelve packs.
--
-- The packs are executed, never pattern-matched: a pack defines keys both as
-- `L["key"] = "value"` lines and inside `local MSUF2_* = { ["key"] = ... }`
-- tables that are copied into L afterwards, so a line parser sees only part of
-- a pack and reports gaps that are not there.
--
-- Deliberate omissions live in tools/locale-coverage-exceptions.tsv with a
-- reason per row. A row that no longer excuses a real omission fails too, so
-- the list cannot rot into a blanket mute.
local repo = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local LOCALES_DIR = "MidnightSimpleUnitFrames/Locales/"
local EXCEPTIONS = "tools/locale-coverage-exceptions.tsv"

local function Read(path)
    local handle = assert(io.open(repo .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

local function Unescape(text, where)
    if not text:find("\\", 1, true) then return text end
    local out, index, size = {}, 1, #text
    while index <= size do
        local char = text:sub(index, index)
        if char == "\\" and index < size then
            local escape = text:sub(index + 1, index + 1)
            local literal = (escape == "n" and "\n") or (escape == "t" and "\t")
                or (escape == "r" and "\r") or (escape == "\\" and "\\")
            assert(literal, where .. ": unknown escape \\" .. escape)
            out[#out + 1] = literal
            index = index + 2
        else
            out[#out + 1] = char
            index = index + 1
        end
    end
    return table.concat(out)
end

local function Escape(text)
    return (text:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("\r", "\\r"))
end

--- Run one pack exactly as the client does: the real localization core picks
--- the active locale, the pack registers its loader, FinalizeLocale runs it.
local function LoadPack(locale)
    local previousGetLocale, previousCreateFrame = _G.GetLocale, _G.CreateFrame
    local previousNS, previousMSUF, previousL = _G.MSUF_NS, _G.MSUF, _G.MSUF_L
    _G.GetLocale = function() return locale end
    _G.CreateFrame = nil
    local namespace = {}
    _G.MSUF_NS, _G.MSUF = namespace, namespace
    assert(loadfile(repo .. "/" .. LOCALES_DIR .. "MSUF_Localization.lua"),
        "cannot load the localization core")("MidnightSimpleUnitFrames", namespace)
    assert(namespace.SUPPORTED_LOCALES[locale], locale .. " is not a supported locale")
    local chunk = assert(loadfile(repo .. "/" .. LOCALES_DIR .. locale .. ".lua"),
        "cannot load language pack " .. locale)
    chunk("MidnightSimpleUnitFrames", namespace)
    assert(namespace.FinalizeLocale() == locale, locale .. ": the core selected another pack")
    local keys, count = {}, 0
    for key, value in pairs(namespace.L) do
        if type(key) == "string" and type(value) == "string" then
            keys[key] = true
            count = count + 1
        end
    end
    local supported = namespace.SUPPORTED_LOCALES
    _G.GetLocale, _G.CreateFrame = previousGetLocale, previousCreateFrame
    _G.MSUF_NS, _G.MSUF, _G.MSUF_L = previousNS, previousMSUF, previousL
    return keys, count, supported
end

-- The supported-locale table is the authority, so a thirteenth pack cannot be
-- added without this smoke covering it.
local _, _, supported = LoadPack("enUS")
local locales = {}
for locale in pairs(supported) do locales[#locales + 1] = locale end
table.sort(locales)
assert(#locales == 12, "expected 12 supported locales, found " .. #locales)

local packs, union, unionCount = {}, {}, 0
for _, locale in ipairs(locales) do
    local keys, count = LoadPack(locale)
    assert(count > 0, locale .. ": language pack defines no keys")
    packs[locale] = keys
    for key in pairs(keys) do
        if not union[key] then
            union[key] = true
            unionCount = unionCount + 1
        end
    end
end

-- tools/locale-coverage-exceptions.tsv: Path, Key, Reason.
local rows, seen = {}, {}
local lineNumber, sawHeader = 0, false
for line in (Read(EXCEPTIONS) .. "\n"):gmatch("([^\n]*)\n") do
    lineNumber = lineNumber + 1
    if line ~= "" and line:sub(1, 1) ~= "#" then
        local where = EXCEPTIONS .. ":" .. lineNumber
        local path, key, reason = line:match("^([^\t]*)\t([^\t]*)\t(.*)$")
        assert(path, where .. ": expected three tab-separated columns")
        if not sawHeader then
            assert(path == "Path" and key == "Key" and reason == "Reason",
                where .. ": first data line must be the header Path/Key/Reason")
            sawHeader = true
        else
            assert(path == "*" or packs[path:match("([^/]+)%.lua$") or ""],
                where .. ": Path must be * or a language pack, got " .. path)
            assert(path ~= "*" or key ~= "*", where .. ": * / * would mute the whole check")
            assert(#reason >= 20, where .. ": Reason must say why the omission is deliberate")
            local exact = key ~= "*" and Unescape(key, where) or "*"
            local identity = path .. "\t" .. key
            assert(not seen[identity], where .. ": duplicate row for " .. path .. " / " .. key)
            seen[identity] = true
            rows[#rows + 1] = { path = path, locale = path:match("([^/]+)%.lua$"),
                key = exact, used = false, where = where }
        end
    end
end
assert(sawHeader, EXCEPTIONS .. ": file has no header row")
assert(#rows > 0, EXCEPTIONS .. ": file has no rows")

local function Matches(row, locale)
    return row.path == "*" or row.locale == locale
end

-- Pass 1: whole-pack rows. A pack excused this way is out of the per-key pass,
-- so a per-key row cannot claim to be used because such a pack omits the key.
local excusedPack = {}
for _, row in ipairs(rows) do
    if row.key == "*" then
        local locale = assert(row.locale, row.where .. ": * key needs a concrete pack")
        local omits = false
        for key in pairs(union) do
            if not packs[locale][key] then omits = true break end
        end
        assert(omits, row.where .. ": " .. locale .. " defines every key; delete this row")
        row.used, excusedPack[locale] = true, true
    end
end

-- Pass 2: per-key rows and the packs they must cover.
local perKey = {}
for _, row in ipairs(rows) do
    if row.key ~= "*" then
        perKey[row.key] = perKey[row.key] or {}
        perKey[row.key][#perKey[row.key] + 1] = row
    end
end

local failures, failureCount = {}, 0
for _, locale in ipairs(locales) do
    if not excusedPack[locale] then
        local missing = {}
        for key in pairs(union) do
            if not packs[locale][key] then
                local excused = false
                for _, row in ipairs(perKey[key] or {}) do
                    if Matches(row, locale) then
                        row.used, excused = true, true
                    end
                end
                if not excused then missing[#missing + 1] = key end
            end
        end
        if #missing > 0 then
            table.sort(missing)
            failureCount = failureCount + #missing
            local shown = {}
            for index = 1, math.min(#missing, 12) do
                shown[index] = '  "' .. Escape(missing[index]) .. '"'
            end
            if #missing > 12 then shown[#shown + 1] = "  ... and " .. (#missing - 12) .. " more" end
            failures[#failures + 1] = LOCALES_DIR .. locale .. ".lua does not define "
                .. #missing .. " key(s) other packs define:\n" .. table.concat(shown, "\n")
        end
    end
end

if #failures > 0 then
    error("locale key coverage regressed.\n" .. table.concat(failures, "\n")
        .. "\nTranslate the key in that pack, or add a reviewed row to " .. EXCEPTIONS, 0)
end

local stale = {}
for _, row in ipairs(rows) do
    if not row.used then
        stale[#stale + 1] = row.where .. ": " .. row.path .. " / " .. row.key
    end
end
if #stale > 0 then
    error("every locale pack now defines these excused keys; delete the rows from "
        .. EXCEPTIONS .. ":\n  " .. table.concat(stale, "\n  "), 0)
end

print(string.format(
    "PASS locale key coverage: %d packs, %d distinct keys, %d exception row(s), %d unexcused gap(s)",
    #locales, unionCount, #rows, failureCount))
