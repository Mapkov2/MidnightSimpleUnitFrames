-- menu_factory_profile_memo_smoke.lua <repoRoot> <flavor>
--
-- Section Reset and the "custom" badge on the Unit and Group pages compare a
-- section with the factory profile. Decoding that ~49 KB profile costs several
-- milliseconds, and it used to run once per page build and scope switch. The
-- factory profile is a constant of the session, so the pages share one decoded
-- copy (Pages/MSUF_Menu2_UnitSectionShared.lua, Shared.FactoryProfile).
--
-- This boots the client (tools/tests/client_world.lua), builds the Player,
-- Target and Group Layout pages twice and asks each page's section defaults
-- the way Reset and the badge do: the factory profile is created once, the
-- answers are its unit and group tables, and Reset still restores copies,
-- never the shared table itself.
--
-- Plain Lua 5.1 with the repo root and a flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local world = World.New(root, flavor):Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local Methods = world.widgets.Methods
local function Store(field) return function(self, value) self[field] = value end end
local function Fetch(field) return function(self) return self[field] end end
for name, method in pairs({
    SetChecked = Store("checked"), GetChecked = Fetch("checked"),
    SetCheckedTexture = Store("checkedTexture"), GetCheckedTexture = Fetch("checkedTexture"),
    SetDisabledCheckedTexture = Store("disabledCheckedTexture"), GetDisabledCheckedTexture = Fetch("disabledCheckedTexture"),
    GetDisabledTexture = Fetch("disabledTexture"), GetHighlightTexture = Fetch("highlightTexture"),
    GetNormalTexture = Fetch("normalTexture"), GetPushedTexture = Fetch("pushedTexture"),
    SetThumbTexture = Store("thumbTexture"), GetThumbTexture = Fetch("thumbTexture"),
    SetValueStep = Store("valueStep"), SetObeyStepOnDrag = Store("obeyStepOnDrag"), SetStepsPerPage = Store("stepsPerPage"),
    SetAutoFocus = Store("autoFocus"), SetNumeric = Store("numeric"), SetMaxLetters = Store("maxLetters"),
    SetPropagateMouseWheel = Store("propagateMouseWheel"),
    SetGradientAlpha = function(self, ...) self.gradientAlpha = { ... } end,
    HasFocus = function() return false end, ClearFocus = function() end, SetFocus = function() end,
    HighlightText = function() end, SetCursorPosition = function() end, GetCursorPosition = function() return 0 end,
    SetTextInsets = function() end,
}) do
    if Methods[name] == nil then Methods[name] = method end
end
local StubGetValue = Methods.GetValue
Methods.GetValue = function(self)
    local value = StubGetValue(self)
    if value == nil then value = self.minimum or 0 end
    return value
end

local env, MSUF = world.env, world.core
local M = Check(world.options.MSUF2, "Menu2 did not load")
env.InCombatLockdown = function() return false end
env.MSUF_EnsureDB(true)
M.frame = M.frame or { IsShown = function() return true end }
M.cache = M.cache or {}
M.scrollChild = M.scrollChild or env.CreateFrame("Frame", nil, env.UIParent)

Check(type(MSUF.MSUF_CreateFactoryDefaultProfile) == "function", "MSUF.MSUF_CreateFactoryDefaultProfile is missing")
-- The harness has no C_EncodingUtil to inflate the real string, so the creator is
-- replaced by one that returns a new, recognisable profile on every call, as the
-- real one does (callers such as profile reset own and change what it returns).
local decodes = 0
local function NewFactoryProfile()
    return {
        player = { width = 275, height = 40, colorStatus = { 1, 0.5, 0 } },
        target = { width = 276, height = 41 },
        gf_party = { width = 120, height = 40 },
        gf_raid = { width = 110, height = 44 },
    }
end
local fresh = NewFactoryProfile()
MSUF.MSUF_CreateFactoryDefaultProfile = function()
    decodes = decodes + 1
    return NewFactoryProfile()
end
env.MSUF_CreateFactoryDefaultProfile = MSUF.MSUF_CreateFactoryDefaultProfile

-- Each page's section-UX options, as the page hands them to AttachSectionUX.
local Shared = Check(M.UnitSectionsShared, "the shared unit section helpers did not load")
local optsByPage = {}
local AttachSectionUX = Check(Shared.AttachSectionUX, "AttachSectionUX is missing")
Shared.AttachSectionUX = function(ctx, opts, ...)
    if ctx and ctx.key and type(opts) == "table" and type(opts.defaults) == "function" then optsByPage[ctx.key] = opts end
    return AttachSectionUX(ctx, opts, ...)
end
local function Build(key)
    M.InvalidatePage(key)
    Check(M.BuildPageEntry(key, true), "the " .. key .. " page did not build")
    world.widgets:RunTimers(20000)
    return Check(optsByPage[key], "the " .. key .. " page attached no section defaults")
end

local answers = {}
for pass = 1, 2 do
    for _, case in ipairs({ { "uf_player", "player" }, { "uf_target", "target" }, { "gf_layout", "party" }, { "gf_layout", "raid" } }) do
        local opts = Build(case[1])
        local defaults = Check(opts.defaults(case[2]), case[1] .. " has no section defaults for " .. case[2])
        local expected = case[1] == "gf_layout" and fresh["gf_" .. case[2]] or fresh[case[2]]
        Check(type(expected) == "table", "harness: the fresh factory profile has no " .. case[2] .. " table")
        for key, value in pairs(expected) do
            if type(value) ~= "table" then
                Check(defaults[key] == value, case[1] .. " " .. case[2] .. "." .. tostring(key) .. " differs from the factory profile")
            end
        end
        if pass == 2 then
            Check(defaults == answers[case[1] .. case[2]], case[1] .. " decoded a second factory profile for " .. case[2])
        end
        answers[case[1] .. case[2]] = defaults
    end
end
Check(decodes == 1, "four pages built twice decoded the factory profile " .. decodes .. " times; expected once per session")

-- Reset restores copies: the shared factory table is never handed to a profile.
local resetSource = Check(answers.uf_playerplayer, "harness: no Player defaults")
local tableKey
for key, value in pairs(resetSource) do
    if type(value) == "table" then tableKey = key; break end
end
Check(tableKey ~= nil, "harness: the Player factory defaults hold no table value")
local copy = M.DeepCopy(resetSource[tableKey])
Check(type(copy) == "table" and copy ~= resetSource[tableKey], "M.DeepCopy no longer copies a factory table value")

print(string.format("menu_factory_profile_memo_smoke: ok (%s; %d decode for %d page builds)", flavor, decodes, 8))
