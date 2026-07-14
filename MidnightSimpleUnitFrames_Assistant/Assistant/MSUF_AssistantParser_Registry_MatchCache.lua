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
    P._settingMatchScoreCacheHead = tonumber(P._settingMatchScoreCacheHead) or 1
    if P._settingMatchScoreCache[key] == nil then
        P._settingMatchScoreCacheOrder[#P._settingMatchScoreCacheOrder + 1] = key
    end
    P._settingMatchScoreCache[key] = tonumber(score) or 0
    local order = P._settingMatchScoreCacheOrder
    local head = P._settingMatchScoreCacheHead
    while #order - head + 1 > CACHE_LIMIT do
        local oldKey = order[head]
        order[head] = nil
        head = head + 1
        P._settingMatchScoreCache[oldKey] = nil
    end
    if head > CACHE_LIMIT and head > (#order / 2) then
        local compact = {}
        for index = head, #order do compact[#compact + 1] = order[index] end
        P._settingMatchScoreCacheOrder = compact
        head = 1
    end
    P._settingMatchScoreCacheHead = head
    return P._settingMatchScoreCache[key]
end

function P.ClearSettingMatchScoreCache()
    P._settingMatchScoreCache = {}
    P._settingMatchScoreCacheOrder = {}
    P._settingMatchScoreCacheHead = 1
end
