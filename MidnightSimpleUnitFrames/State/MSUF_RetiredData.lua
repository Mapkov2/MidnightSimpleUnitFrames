-- Saved data that retired features left behind: the in-game Assistant's
-- (removed once per account) and the built-in profilers' (see below).
--
-- The in-game Assistant (the MidnightSimpleUnitFrames_Assistant addon, retired
-- in 6.5) kept its conversation history and context in every profile it
-- touched (profile.assistant) and its ledgers and logs in the account table
-- (MSUF_GlobalDB.assistant*, MSUF_GlobalDB.global.assistant*). Nothing reads
-- them any more, and the history holds the player's own text, so it must not
-- linger in SavedVariables or ride along in a shared profile string. The pass
-- runs once, when this addon's SavedVariables arrive; the export, copy and
-- import paths in State/MSUF_Profiles.lua drop profile.assistant as well, so a
-- string made by an older build cannot bring it back.
local _, MSUF = ...
if type(MSUF) ~= "table" then return end

local STAMP = "_msufRetiredAssistantDataCleared_v1"
local PREFIX = "assistant"

local function ClearPrefixedKeys(store)
    for key in pairs(store) do
        -- Clearing an existing field during pairs() is allowed in Lua.
        if type(key) == "string" and key:sub(1, #PREFIX) == PREFIX then
            store[key] = nil
        end
    end
end

--- The account SavedVariable, read when a cleanup runs (it exists only once
--- the client has loaded the SavedVariables).
local function AccountDB()
    return rawget(_G, "MSUF_GlobalDB")
end

--- Returns true when this call removed the data, false when there was no
--- account table yet or the stamp says it already ran.
local function ClearRetiredAssistantData()
    local globalDB = AccountDB()
    if type(globalDB) ~= "table" then return false end
    local global = globalDB.global
    if type(global) == "table" and global[STAMP] == true then return false end
    local profiles = globalDB.profiles
    if type(profiles) == "table" then
        for _, profile in pairs(profiles) do
            if type(profile) == "table" then profile.assistant = nil end
        end
    end
    ClearPrefixedKeys(globalDB)
    if type(global) ~= "table" then
        global = {}
        globalDB.global = global
    end
    ClearPrefixedKeys(global)
    global[STAMP] = true
    return true
end
MSUF.ClearRetiredAssistantData = ClearRetiredAssistantData

-- The built-in profilers were removed in favour of disposable external traces.
-- Their last report and armed trace state stayed in the account table. This
-- ran at the load of Kernel/MSUF_Util.lua, before the client had loaded the
-- SavedVariables, so it never saw them; the lifecycle runs it at ADDON_LOADED,
-- because an older build on the same account can write them again.
local function ClearRetiredProfilerData()
    local globalDB = AccountDB()
    if type(globalDB) ~= "table" then return false end
    globalDB.clickCoreProfilerLast = nil
    globalDB.cpTraceArm = nil
    return true
end
MSUF.ClearRetiredProfilerData = ClearRetiredProfilerData

