-- classpower_page_reset_coverage_smoke.lua <repoRoot> <flavor>
--
-- The Class Resources page "Reset to defaults" must restore every bars setting
-- the page itself writes. The page's own key inventory is the resource
-- workspace (ClassPowerWorkspace.Attach/Decorate collect the setting key of
-- every control the page builds), so this smoke builds the real page with all
-- of its sections open, dirties each bars.* key the workspace lists plus the
-- resource marks and every client-only resource extra, runs the real
-- M.ResetPageToDefaults("classpower") and requires each one back at factory.
--
-- It also pins the documented owner split (MSUF_Menu2_Bindings_Reset.lua,
-- ResetClassPowerPage): Player Power stays a Player setting, so the page reset
-- touches no player.* key but playerPowerSource, and bars keys of other pages
-- (the resource colours on Colors) stay untouched.
--
-- Plain Lua 5.1, repo root as arg 1 and the client flavor as arg 2.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("classpower_page_reset_coverage_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, {
    page = "home",
    beforeCore = function(world)
        -- Same harness gap as classpower_workspace_smoke: keep centers numeric.
        world.widgets.Methods.GetCenter = function(frame)
            return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
                (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
        end
    end,
})
local M, env, F = mw.M, mw.env, mw.core.ProfileFields
Check(mw:Select("classpower"), "Class Resources page did not open")
local ui = Check(M.ClassPowerWorkspace and M.ClassPowerWorkspace.current, "resource workspace missing")
-- Open every section of every resource so lazy sections register their keys.
for kind in pairs(ui.entries) do
    ui:Select(kind)
    mw:RunTimers()
    for _, entry in ipairs(ui.entries[kind]) do entry.SetOpenImmediate(true) end
    mw:RunTimers()
end
-- The harness cannot decode the embedded factory string; the booted profile
-- is the factory baseline the reset returns to.
local factory = F.CopySnapshot(env.MSUF_DB)
mw.core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end

local SENTINEL = "__classpower_page_reset_coverage__"
local owned, playerKeys = {}, {}
for kind, keys in pairs(ui.keys) do
    for path in pairs(keys) do
        if path:match("^bars%.") then owned[path] = kind
        elseif path:match("^player%.") and path ~= "player.playerPowerSource" then playerKeys[path] = kind end
    end
end
owned["bars.resourceMarks"] = "extras"
local clientOnly = M.ResourceExtrasPage and M.ResourceExtrasPage.ClientOnlySettings and M.ResourceExtrasPage.ClientOnlySettings()
for path in pairs(clientOnly or {}) do owned[path] = "extras" end
-- Colors-page keys beside the extras: the Class Resources reset must keep them.
local foreign = { "bars.ignorePainColor", "bars.arcaneWindowColor", "bars.arcaneWindowSoulColor",
    "bars.arcaneWindowWarnColor", "bars.manaRegenPauseColor", "bars.manaGainPulseColor", "bars.manaCostColor",
    "bars.barOutlineThickness", "bars.powerBarTexture" }

local function Split(path) return path:match("^(%w+)%.(.+)$") end
local db = M.EnsureDB()
local count, hpCount = 0, 0
for path, kind in pairs(owned) do
    local rootKey, key = Split(path)
    db[rootKey] = type(db[rootKey]) == "table" and db[rootKey] or {}
    db[rootKey][key] = SENTINEL
    count = count + 1
    if kind == "hp" then hpCount = hpCount + 1 end
end
for path in pairs(playerKeys) do
    local rootKey, key = Split(path)
    db[rootKey][key] = SENTINEL
end
for _, path in ipairs(foreign) do
    local rootKey, key = Split(path)
    db[rootKey][key] = SENTINEL
end
Check(hpCount >= 20, "precondition: the Extra Health Bar sections registered only " .. hpCount .. " keys")
Check(next(playerKeys) ~= nil, "precondition: the Player Power sections registered no player keys")

local ok, result = pcall(M.ResetPageToDefaults, "classpower")
Check(ok and result == true, "resetting classpower failed: " .. tostring(result))
db = M.EnsureDB()
local missed = {}
for path in pairs(owned) do
    local rootKey, key = Split(path)
    local expected = type(factory[rootKey]) == "table" and factory[rootKey][key] or nil
    local value = type(db[rootKey]) == "table" and db[rootKey][key] or nil
    -- The defaults pass after a reset may store a factory nil as false.
    if not (value == expected or (value == false and expected == nil)) then
        missed[#missed + 1] = path .. "=" .. tostring(value)
    end
end
table.sort(missed)
Check(#missed == 0, "Class Resources reset left page settings at the user's value: " .. table.concat(missed, ", "))
for path in pairs(playerKeys) do
    local rootKey, key = Split(path)
    Check(db[rootKey][key] == SENTINEL, "Class Resources reset replaced the Player setting " .. path)
end
for _, path in ipairs(foreign) do
    local rootKey, key = Split(path)
    Check(db[rootKey][key] == SENTINEL, "Class Resources reset replaced another page's setting " .. path)
end

print(string.format("classpower_page_reset_coverage_smoke: %s ok (%d page keys restored, %d Player keys kept)",
    flavor, count, (function() local n = 0 for _ in pairs(playerKeys) do n = n + 1 end return n end)()))
