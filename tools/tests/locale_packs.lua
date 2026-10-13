-- locale_packs.lua: what the locale smokes share.
--
--   local Packs = assert(loadfile(root .. "/tools/tests/locale_packs.lua"))()
--   Packs.LOCALES                     the ten translated language packs
--   Packs.Load(root)                  pack name -> { key = value }, each pack run as the client runs it
--   Packs.ReadAllowlist(root, packs)  the parsed tools/locale-same-text-allowlist.tsv
--   Packs.Missing(packs, allowlist, key)   the packs that do not translate a string
--   Packs.ScanLiterals(source, onLiteral)  the quoted literals of a Lua source
--
-- enUS and enGB fall back to the key itself (MSUF_Localization.lua), so only the
-- ten other packs are ever checked.
local Packs = {}

Packs.LOCALES = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
Packs.ALLOWLIST = "tools/locale-same-text-allowlist.tsv"

local LOCALES_DIR = "MidnightSimpleUnitFrames/Locales/"

function Packs.Load(root)
    local packs = {}
    for _, locale in ipairs(Packs.LOCALES) do
        local previousGetLocale, previousCreateFrame = _G.GetLocale, _G.CreateFrame
        local previousNS, previousMSUF, previousL = _G.MSUF_NS, _G.MSUF, _G.MSUF_L
        _G.GetLocale = function() return locale end
        _G.CreateFrame = nil
        local namespace = {}
        _G.MSUF_NS, _G.MSUF = namespace, namespace
        assert(loadfile(root .. "/" .. LOCALES_DIR .. "MSUF_Localization.lua"))("MidnightSimpleUnitFrames", namespace)
        assert(loadfile(root .. "/" .. LOCALES_DIR .. locale .. ".lua"))("MidnightSimpleUnitFrames", namespace)
        namespace.FinalizeLocale()
        local keys = {}
        for key, value in pairs(namespace.L) do
            if type(key) == "string" and type(value) == "string" then keys[key] = value end
        end
        _G.GetLocale, _G.CreateFrame = previousGetLocale, previousCreateFrame
        _G.MSUF_NS, _G.MSUF, _G.MSUF_L = previousNS, previousMSUF, previousL
        packs[locale] = keys
    end
    return packs
end

local function Unescape(text)
    return (text:gsub("\\(.)", { n = "\n", t = "\t", r = "\r", ["\\"] = "\\" }))
end

--- tools/locale-same-text-allowlist.tsv: strings a pack may leave as the English
--- key. Columns Pack, Key, Reason; Pack is * or a comma list of pack names; the
--- key escapes \n, \t and \\. Returns { [key] = { ["*"] or [pack] = true }, ... }
--- and the rows (pack list, key, reason, line number) in file order.
function Packs.ReadAllowlist(root, packs)
    local handle = assert(io.open(root .. "/" .. Packs.ALLOWLIST, "rb"), "cannot open " .. Packs.ALLOWLIST)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local excused, rows, sawHeader, lineNumber = {}, {}, false, 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lineNumber = lineNumber + 1
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local where = Packs.ALLOWLIST .. ":" .. lineNumber
            local path, key, reason = line:match("^([^\t]*)\t([^\t]*)\t(.*)$")
            assert(path, where .. ": expected three tab-separated columns")
            if not sawHeader then
                assert(path == "Pack" and key == "Key" and reason == "Reason", where .. ": the first data line must be the header")
                sawHeader = true
            else
                assert(#reason >= 12, where .. ": the Reason must say why the string may stay English")
                local exact = Unescape(key)
                local entry = excused[exact] or {}
                excused[exact] = entry
                local row = { packs = {}, key = exact, reason = reason, line = lineNumber }
                for locale in path:gmatch("[^,]+") do
                    assert(locale == "*" or packs[locale], where .. ": unknown pack " .. locale)
                    assert(not entry[locale], where .. ": duplicate row for " .. locale .. " / " .. key)
                    entry[locale] = true
                    row.packs[#row.packs + 1] = locale
                end
                rows[#rows + 1] = row
            end
        end
    end
    assert(sawHeader, Packs.ALLOWLIST .. ": no header row")
    return excused, rows
end

--- True when the string is more than format specifiers, color codes and textures.
function Packs.HasWords(text)
    local plain = text:gsub("%%%%", ""):gsub("%%[%-+# 0]*%d*%.?%d*[sdifgxXcq]", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T[^|]*|t", "")
    return plain:find("%a") ~= nil
end

--- The packs that do not translate a string: no entry, or the English key itself.
function Packs.Missing(packs, allowlist, key)
    local missing = {}
    if not Packs.HasWords(key) then return missing end
    local row = allowlist[key]
    for _, locale in ipairs(Packs.LOCALES) do
        local value = packs[locale][key]
        if (value == nil or value == key) and not (row and (row["*"] or row[locale])) then
            missing[#missing + 1] = locale
        end
    end
    return missing
end

local ESCAPES = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }
--- Calls onLiteral(text, quoteAt) for each quoted string of a Lua source, folding
--- "a" .. "b" chains into one constant (quoteAt is where the first piece starts).
--- Comments are skipped, decimal escapes decoded.
function Packs.ScanLiterals(source, onLiteral)
    local pos, size, commentAt = 1, #source, 0
    local function ReadString(start)
        local quote = source:sub(start, start)
        local stop = "[" .. quote .. "\\\n]"
        local parts, at = {}, start + 1
        while true do
            local stopAt = source:find(stop, at)
            if not stopAt then return nil end
            local char = source:sub(stopAt, stopAt)
            if char == "\n" then return nil end
            parts[#parts + 1] = source:sub(at, stopAt - 1)
            if char == quote then return table.concat(parts), stopAt + 1 end
            local digits = source:match("^%d%d?%d?", stopAt + 1)
            if digits then
                parts[#parts + 1] = string.char(tonumber(digits) % 256)
                at = stopAt + 1 + #digits
            else
                local escaped = source:sub(stopAt + 1, stopAt + 1)
                parts[#parts + 1] = ESCAPES[escaped] or escaped
                at = stopAt + 2
            end
        end
    end
    while pos <= size do
        if commentAt < pos then commentAt = source:find("--", pos, true) or size + 1 end
        local quoteAt = source:find("[\"']", pos)
        if not quoteAt then return end
        if commentAt < quoteAt then
            local long = source:match("^%-%-%[(=*)%[", commentAt)
            if long then
                local _, closeAt = source:find("]" .. long .. "]", commentAt, true)
                pos = (closeAt or size) + 1
            else
                pos = (source:find("\n", commentAt, true) or size) + 1
            end
        else
            local text, nextPos = ReadString(quoteAt)
            if text then
                while true do
                    local joinAt = source:match("^%s*%.%.%s*()[\"']", nextPos)
                    if not joinAt then break end
                    local more, afterMore = ReadString(joinAt)
                    if not more then break end
                    text, nextPos = text .. more, afterMore
                end
                onLiteral(text, quoteAt)
                pos = nextPos
            else
                pos = quoteAt + 1
            end
        end
    end
end

return Packs
