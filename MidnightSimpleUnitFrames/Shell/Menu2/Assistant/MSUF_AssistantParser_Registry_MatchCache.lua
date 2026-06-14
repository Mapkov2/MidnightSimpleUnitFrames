local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local P = A.Parser or {}
A.Parser = P

-- Bounded score cache for registry matching.
-- The assistant scores many settings against the same text; caching keeps typing responsive
-- while avoiding persistent growth from long pasted messages.
local CACHE_LIMIT = 4096

local function CacheKey(setting, text)
    local key = tostring(setting and setting.key or "")
    text = tostring(text or "")
    if key == "" or text == "" or #text > 320 then return nil end
    return key .. "\031" .. text
end

function P.SettingMatchScoreCacheGet(setting, text)
    local key = CacheKey(setting, text)
    if not key then return nil end
    local cache = P._settingMatchScoreCache
    if type(cache) ~= "table" then return nil end
    return cache[key]
end

function P.SettingMatchScoreCachePut(setting, text, score)
    local key = CacheKey(setting, text)
    if not key then return score end
    P._settingMatchScoreCache = P._settingMatchScoreCache or {}
    P._settingMatchScoreCacheOrder = P._settingMatchScoreCacheOrder or {}
    if P._settingMatchScoreCache[key] == nil then
        P._settingMatchScoreCacheOrder[#P._settingMatchScoreCacheOrder + 1] = key
    end
    P._settingMatchScoreCache[key] = tonumber(score) or 0
    while #P._settingMatchScoreCacheOrder > CACHE_LIMIT do
        local oldKey = table.remove(P._settingMatchScoreCacheOrder, 1)
        P._settingMatchScoreCache[oldKey] = nil
    end
    return P._settingMatchScoreCache[key]
end

function P.ClearSettingMatchScoreCache()
    P._settingMatchScoreCache = {}
    P._settingMatchScoreCacheOrder = {}
end
