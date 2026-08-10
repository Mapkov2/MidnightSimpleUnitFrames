-- Assistant media resolver: normalizes user-facing media names to registered textures/fonts.
-- Resolver output is read-only lookup data; callers own validation and DB writes.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local R = A.MediaResolver or {}
A.MediaResolver = R

-- Assistant media resolver.
-- Converts human font/texture names into the same stored values Menu2 uses. It searches
-- registry labels, LibSharedMedia data, and MSUF's normalized font helpers without applying
-- the selection itself.
local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Normalize(text)
    if A.Normalize then return A.Normalize(text) end
    text = tostring(text or ""):lower():gsub("[,;:!?%(%)]", " "):gsub("[%[%]]", " ")
    text = text:gsub("%s+", " ")
    return Trim(text)
end

local function Compact(text)
    return Normalize(text):gsub("%s+", "")
end

local function AddItem(out, usedValue, usedLabel, value, label, key, path, source)
    value = tostring(value or "")
    label = Trim(label ~= nil and label or value)
    if value == "" and label == "" then return end
    local valueKey = value ~= "" and value or ("label:" .. label)
    if usedValue[valueKey] then return end
    usedValue[valueKey] = true
    local labelNorm = Normalize(label)
    if labelNorm ~= "" then usedLabel[labelNorm] = true end
    out[#out + 1] = {
        value = value,
        label = label ~= "" and label or value,
        key = key,
        path = path,
        source = source,
    }
end

local function FontSelectionValue(key, path)
    -- Font registry keys and actual file paths both appear in SavedVariables depending on
    -- addon version/import source. Normalize through the runtime font helpers when present.
    local normalizeFontKey = _G.MSUF_NormalizeFontKey
    if type(normalizeFontKey) == "function" then key = normalizeFontKey(key) end
    local normalizePath = _G.MSUF_NormalizeFontPath
    if type(normalizePath) == "function" then
        path = normalizePath(path)
        local direct = normalizePath(key)
        if type(direct) == "string" and direct ~= "" and direct:find("\\", 1, true) then
            return direct
        end
    end
    if type(path) == "string" and path ~= "" then return path end
    if type(key) == "string" and key ~= "" then
        local resolveKeyPath = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey or (MSUF and MSUF.MSUF_GetFontPathForKey)
        if type(resolveKeyPath) == "function" then
            local resolved = resolveKeyPath(key, 14, "")
            if type(resolved) == "string" and resolved ~= "" then return resolved end
        end
    end
    return key
end

function R.FontItems()
    local out, usedValue, usedLabel = {}, {}, {}
    local fontList = _G.MSUF_FONT_LIST or _G.FONT_LIST
    if type(fontList) == "table" then
        for i = 1, #fontList do
            local info = fontList[i]
            if type(info) == "table" then
                local key = info.key
                local value = FontSelectionValue(key, info.path)
                AddItem(out, usedValue, usedLabel, value, info.name or key or value, key, value, "MSUF")
            end
        end
    end
    local LSM = (MSUF and MSUF.LSM) or _G.MSUF_LSM
    if LSM and type(LSM.List) == "function" then
        local names = LSM:List("font")
        local hash = type(LSM.HashTable) == "function" and LSM:HashTable("font") or nil
        if type(names) == "table" then
            table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
            for i = 1, #names do
                local name = names[i]
                if type(name) == "string" and name ~= "" then
                    local path = type(hash) == "table" and hash[name] or nil
                    local normalizeFontKey = _G.MSUF_NormalizeFontKey
                    local key = type(normalizeFontKey) == "function" and normalizeFontKey(name) or name
                    local value = FontSelectionValue(key, path)
                    AddItem(out, usedValue, usedLabel, value, name, key, value, "LibSharedMedia")
                end
            end
        end
    end
    if #out == 0 then
        local value = FontSelectionValue("FRIZQT", "Fonts\\FRIZQT___CYR.TTF")
        AddItem(out, usedValue, usedLabel, value or "FRIZQT", "Friz Quadrata", "FRIZQT", value, "Fallback")
    end
    return out
end

function R.StatusbarItems()
    local out, usedValue, usedLabel = {}, {}, {}
    local provider = _G.MSUF_StatusBarTextureItems or (MSUF and MSUF.UI and MSUF.UI.StatusBarTextureItems)
    local items = type(provider) == "function" and provider() or nil
    if type(items) == "table" then
        for i = 1, #items do
            local item = items[i]
            if type(item) == "table" then
                AddItem(out, usedValue, usedLabel, item.value, item.text or item.value, item.value, item.texture, "MSUF")
            end
        end
    end
    if #out == 0 then
        local fallback = {
            "Blizzard", "Solid", "Flat", "RaidHP", "RaidPower", "Skills", "Outline", "TooltipBorder", "DialogBG", "Parchment",
            "MSUF Charcoal", "MSUF Lucent", "MSUF Minimalist", "MSUF Slickrock", "MSUF Smooth", "MSUF Smooth v2", "MSUF Smoother", "Better Blizzard",
        }
        for i = 1, #fallback do AddItem(out, usedValue, usedLabel, fallback[i], fallback[i], fallback[i], nil, "Fallback") end
    end
    return out
end

function R.BorderItems()
    local out, usedValue, usedLabel = {}, {}, {}
    local styles = (MSUF and MSUF.BorderStyles) or _G.MSUF_BorderStyles
    local items = styles and type(styles.FrameList) == "function"
        and styles.FrameList("None (solid color)") or {}
    local section = "True Outline"
    for i = 1, #items do
        local item = items[i]
        if item.header == true or item.categoryHeader == true then
            section = item.text or section
        else
            AddItem(out, usedValue, usedLabel, item.value,
                section .. ": " .. tostring(item.text or item.value),
                item.text or item.value, item.texture, section)
        end
    end
    return out
end

local function LooksLikeFontSetting(setting)
    if not setting or setting.type ~= "string" then return false end
    if setting.mediaType == "font" then return true end
    local key = tostring(setting.key or ""):lower()
    local attr = tostring(setting.attribute or ""):lower()
    if key == "general.fontkey" or attr == "fontfamily" then return true end
    return false
end

local function LooksLikeTextureSetting(setting)
    if not setting or setting.type ~= "string" then return false end
    if setting.mediaType == "statusbar" or setting.mediaType == "texture" then return true end
    local label = tostring(setting.label or ""):lower()
    local attr = tostring(setting.attribute or ""):lower()
    local key = tostring(setting.key or ""):lower()
    if label:find("texture", 1, true) or attr:find("texture", 1, true) or key:find("texture", 1, true) then return true end
    return false
end

local function LooksLikeBorderSetting(setting)
    return setting and setting.type == "string" and setting.mediaType == "border"
end

-- Portrait packs are not LibSharedMedia: the options page builds its dropdown
-- from MSUF.PortraitMedia.GetPackOptions(), so the installed set decides what
-- exists. That is the same shape as the texture list, and the same reason a
-- fixed value list would be wrong for these settings.
function R.PortraitPackItems()
    local out, usedValue, usedLabel = {}, {}, {}
    local media = MSUF and MSUF.PortraitMedia
    local provider = type(media) == "table" and media.GetPackOptions or nil
    local items = type(provider) == "function" and provider() or nil
    if type(items) == "table" then
        for i = 1, #items do
            local item = items[i]
            if type(item) == "table" then
                local value = item.value or item.key
                AddItem(out, usedValue, usedLabel, value,
                    item.text or item.label or value, value, nil, "MSUF")
            end
        end
    end
    if #out == 0 then
        -- The Blizzard class icon is the built-in default and is always present
        -- even with no packs installed.
        AddItem(out, usedValue, usedLabel, "BLIZZARD", "Blizzard Class Icon", "BLIZZARD", nil, "Fallback")
    end
    return out
end

function R.MediaTypeForSetting(setting)
    -- Declared media wins over the name heuristics below.
    if type(setting) == "table" and setting.mediaType == "portraitpack" then return "portraitpack" end
    if LooksLikeBorderSetting(setting) then return "border" end
    if LooksLikeFontSetting(setting) then return "font" end
    if LooksLikeTextureSetting(setting) then return "statusbar" end
    return nil
end

local function StripCommandNoise(query)
    query = Trim(query)
    query = query:gsub("^to%s+", ""):gsub("^as%s+", ""):gsub("^is%s+", ""):gsub("^be%s+", "")
    query = query:gsub("^font%s+", ""):gsub("^texture%s+", "")
    query = query:gsub("^bar%s+texture%s+", "")
    query = query:gsub("^castbar%s+texture%s+", "")
    query = Trim(query)
    return query
end

function R.ExtractQuery(setting, text, raw)
    local rawText = tostring(raw or "")
    local quoted = rawText:match('"([^"]*)"') or rawText:match("'([^']*)'")
    if quoted ~= nil and Trim(quoted) ~= "" then return Trim(quoted) end

    local prefixes = setting and (setting.valuePrefixes or setting.aliases) or {}
    for i = 1, #(prefixes or {}) do
        local prefix = tostring(prefixes[i] or "")
        if prefix ~= "" then
            local pattern = "%f[%a]" .. prefix:gsub("(%W)", "%%%1"):lower() .. "%f[%A]"
            local s, e = rawText:lower():find(pattern)
            if s then
                local value = Trim(rawText:sub(e + 1))
                value = StripCommandNoise(value)
                if value ~= "" then return value end
            end
        end
    end

    local textNorm = Normalize(text)
    local value = textNorm
    value = value:gsub("^set%s+", ""):gsub("^change%s+", ""):gsub("^make%s+", "")
    value = value:gsub("^use%s+", ""):gsub("^select%s+", "")
    for i = 1, #(prefixes or {}) do
        local p = Normalize(prefixes[i])
        if p ~= "" then value = value:gsub("^" .. p:gsub("(%W)", "%%%1") .. "%s*", "") end
    end
    value = StripCommandNoise(value)
    return value ~= "" and value or nil
end

local function TokenScore(normQuery, normLabel, compactQuery, compactLabel)
    if normQuery == "" then return 0 end
    if normQuery == normLabel or compactQuery == compactLabel then return 10000 + #compactLabel end
    if normLabel:find("^" .. normQuery, 1, false) or compactLabel:find("^" .. compactQuery, 1, false) then return 8000 + #compactQuery end
    if normLabel:find(normQuery, 1, true) or compactLabel:find(compactQuery, 1, true) then return 6000 + #compactQuery end
    local total, hit = 0, 0
    for token in normQuery:gmatch("%S+") do
        total = total + 1
        if normLabel:find(token, 1, true) then hit = hit + 1 end
    end
    if total > 0 and hit == total then return 4000 + hit * 100 end
    if total > 0 and hit > 0 then return 1000 + hit * 100 end
    return 0
end

local function ScoreItem(query, item)
    local normQuery = Normalize(query)
    local compactQuery = Compact(query)
    local labels = {
        item.label,
        item.value,
        item.key,
        item.path,
    }
    local best = 0
    for i = 1, #labels do
        local label = labels[i]
        if type(label) == "string" and label ~= "" then
            local score = TokenScore(normQuery, Normalize(label), compactQuery, Compact(label))
            if score > best then best = score end
        end
    end
    return best
end

local function MediaResultBefore(a, b)
    if not b then return true end
    if (a._score or 0) ~= (b._score or 0) then return (a._score or 0) > (b._score or 0) end
    return tostring(a.label or a.value):lower() < tostring(b.label or b.value):lower()
end

local function PreferredFontFamilyMatch(query, choices)
    query = Trim(query or "")
    if query == "" or type(choices) ~= "table" or #choices == 0 then return nil end
    local normQuery = Normalize(query)
    local compactQuery = Compact(query)
    if normQuery == "" or compactQuery == "" then return nil end

    local function eachLabel(item, fn)
        local labels = { item and item.label, item and item.value, item and item.key, item and item.path }
        for i = 1, #labels do
            local label = labels[i]
            if type(label) == "string" and label ~= "" and fn(Normalize(label), Compact(label)) then return true end
        end
        return false
    end

    local preferred = {
        normQuery .. " regular",
        normQuery .. " normal",
        normQuery .. " book",
    }
    local preferredCompact = {
        compactQuery .. "regular",
        compactQuery .. "normal",
        compactQuery .. "book",
    }

    for p = 1, #preferred do
        for i = 1, #choices do
            local item = choices[i]
            if eachLabel(item, function(normLabel, compactLabel)
                return normLabel == preferred[p]
                    or compactLabel == preferredCompact[p]
                    or compactLabel:sub(1, #preferredCompact[p]) == preferredCompact[p]
            end) then
                return item
            end
        end
    end
    return nil
end

local function InsertTopMediaResult(top, item, limit)
    local pos = #top + 1
    while pos > 1 and MediaResultBefore(item, top[pos - 1]) do
        pos = pos - 1
    end
    table.insert(top, pos, item)
    if #top > limit then table.remove(top) end
end

function R.Find(mediaType, query, opts)
    opts = opts or {}
    query = Trim(query or "")
    if query == "" then return nil end
    local items = mediaType == "font" and R.FontItems()
        or mediaType == "portraitpack" and R.PortraitPackItems()
        or mediaType == "border" and R.BorderItems()
        or R.StatusbarItems()
    local limit = tonumber(opts.limit) or 8
    local top = {}
    local exacts = {}
    local matchCount = 0
    local best = 0
    local normQuery = Normalize(query)
    local compactQuery = Compact(query)
    for i = 1, #(items or {}) do
        if i % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local item = items[i]
        local score = ScoreItem(query, item)
        if score > 0 then
            item._score = score
            matchCount = matchCount + 1
            InsertTopMediaResult(top, item, limit)
            if score > best then best = score end
            local labels = { item.label, item.value, item.key }
            for j = 1, #labels do
                local label = labels[j]
                if type(label) == "string" and label ~= "" then
                    if Normalize(label) == normQuery or Compact(label) == compactQuery then
                        exacts[#exacts + 1] = item
                        break
                    end
                end
            end
        end
    end
    if matchCount == 0 then return { status = "none", query = query, mediaType = mediaType } end
    if #exacts == 1 then
        return { status = "exact", mediaType = mediaType, query = query, item = exacts[1], value = exacts[1].value, label = exacts[1].label }
    end
    if mediaType == "font" then
        local preferred = PreferredFontFamilyMatch(query, top)
        if preferred then
            return { status = "exact", mediaType = mediaType, query = query, item = preferred, value = preferred.value, label = preferred.label }
        end
    end
    if matchCount == 1 then
        local item = top[1]
        return { status = "exact", mediaType = mediaType, query = query, item = item, value = item.value, label = item.label }
    end
    return { status = "choices", mediaType = mediaType, query = query, choices = top }
end

function R.ResolveSetting(setting, text, raw)
    local mediaType = R.MediaTypeForSetting(setting)
    if not mediaType then return nil end
    local query = R.ExtractQuery(setting, text, raw)
    if not query or query == "" then return nil end
    local lowered = Normalize(query)
    if mediaType == "statusbar" and (lowered == "global" or lowered == "follow global" or lowered == "inherit" or lowered == "default") then
        return { status = "exact", value = query, label = query, mediaType = mediaType, query = query }
    end
    return R.Find(mediaType, query, { limit = 8 })
end

function R.NoMatchMessage(mediaType, query)
    local label = mediaType == "font" and "font"
        or mediaType == "portraitpack" and "portrait pack"
        or mediaType == "border" and "outline style"
        or "texture"
    return "I don't see a matching " .. label .. " in the current MSUF media list. Pick one of the names shown there."
end
