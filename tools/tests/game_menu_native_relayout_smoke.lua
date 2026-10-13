-- game_menu_native_relayout_smoke.lua <repoRoot>
--
-- Blizzard's Game Menu is a VerticalLayoutFrame: InitButtons releases and
-- re-acquires its pooled buttons and marks the frame dirty, and Layout runs
-- on a later OnUpdate, re-anchoring every button and resizing the menu. It
-- happens on every open (OnShow) and again while the menu is open
-- (STORE_STATUS_CHANGED, TRIAL_STATUS_UPDATE). MSUF must keep its button in
-- place after each of those relayouts, whichever of its queued pass and the
-- native Layout runs first, and must keep its bookkeeping in its own tables:
-- no field on GameMenuFrame or the pooled buttons. During combat lockdown it
-- writes nothing on the Blizzard menu, protected or not, and re-places its
-- button once combat ends.
--
-- Real Shell/MSUF_GameMenu.lua in a Mainline client world. Plain Lua 5.1,
-- repo root as arg 1.

local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Mainline")
local env, ns, widgets = world.env, world.core, world.widgets
ns.ExportPublic = function(name, value) env[name] = value end

env.MSUF_DB = { general = {} }
env.EllesmereUI = false
env.LOGOUT, env.MACROS = "Logout", "Macros"
local menu = env.CreateFrame("Frame", "GameMenuFrame", env.UIParent)
env.GameMenuFrame = menu
-- An ordinary menu: no secure child protects it.
function menu:IsProtected() return false, false end
local macro = env.CreateFrame("Button", nil, menu)
macro:SetText("Macros")
macro:SetSize(200, 24)
local exit = env.CreateFrame("Button", nil, menu)
exit:SetText("Logout")
exit:SetSize(200, 24)
-- MainMenuFrameTemplates.lua / LayoutFrame.lua, reduced to their geometry.
local native, combatWrites = false, {}
function menu:Layout()
    native = true
    self:SetHeight(400)
    macro:ClearAllPoints()
    macro:SetPoint("TOP", self, "TOP", 0, -200)
    exit:ClearAllPoints()
    exit:SetPoint("TOP", self, "TOP", 0, -320)
    native = false
end
function menu:InitButtons()
    native = true
    macro:ClearAllPoints()
    exit:ClearAllPoints()
    native = false
end
-- Every geometry or visibility write on the Blizzard menu outside its own
-- code is logged while combat lockdown holds.
for label, frame in pairs({ GameMenuFrame = menu, Macros = macro, Logout = exit }) do
    for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetHeight", "SetSize", "Show", "Hide" }) do
        local original = frame[method]
        frame[method] = function(self, ...)
            if not native and widgets:IsInCombat() then combatWrites[#combatWrites + 1] = label .. ":" .. method end
            return original(self, ...)
        end
    end
end
menu:Layout()
local nativeKeys = {}
for _, frame in ipairs({ menu, macro, exit }) do
    nativeKeys[frame] = {}
    for key in pairs(frame) do nativeKeys[frame][key] = true end
end
-- The client publishes a named frame as a global.
local create = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    local frame = create(kind, name, parent, template)
    if name then env[name] = frame end
    frame.IsProtected = frame.IsProtected or function() return false, false end
    return frame
end

local ok, err = world:LoadFile(root .. "/MidnightSimpleUnitFrames/Shell/MSUF_GameMenu.lua", "MidnightSimpleUnitFrames", ns)
assert(ok, tostring(err))
widgets:FireEvent("PLAYER_LOGIN")
env.MSUF_PositionGameMenuButton()
local button = assert(env.MSUF_GameMenuButton, "the MSUF Game Menu button was not created")

local function AssertPlaced(context)
    assert(menu:GetHeight() == 436, context .. ": the menu lost the MSUF row, height " .. tostring(menu:GetHeight()))
    local _, _, _, _, macroY = macro:GetPoint(1)
    local _, _, _, _, exitY = exit:GetPoint(1)
    assert(macroY == -188 and exitY == -348, context .. ": the native buttons lost the MSUF offsets ("
        .. tostring(macroY) .. ", " .. tostring(exitY) .. ")")
    local _, anchor = button:GetPoint(1)
    assert(button:IsShown() and anchor == macro, context .. ": the MSUF button is not shown below Macros")
end
-- MSUF's own state stays in MSUF's tables; a hook may replace a method.
local function AssertNoMSUFFields(context)
    for frame, keys in pairs(nativeKeys) do
        for key, value in pairs(frame) do
            assert(keys[key] or not tostring(key):lower():find("msuf", 1, true),
                context .. ": MSUF wrote " .. tostring(key) .. " onto a Blizzard Game Menu frame")
            assert(keys[key] or type(value) ~= "table" or key == "scripts",
                context .. ": MSUF stored a table field " .. tostring(key) .. " on a Blizzard Game Menu frame")
        end
    end
end
AssertPlaced("first open")
AssertNoMSUFFields("first open")

-- Queued pass first, native Layout after it (and the other way round), on
-- open and while the menu is open.
for round = 1, 3 do
    menu:InitButtons()
    widgets:RunTimers()
    menu:Layout()
    widgets:RunTimers()
    AssertPlaced("relayout " .. round .. ", queued pass before Layout")
    menu:InitButtons()
    menu:Layout()
    widgets:RunTimers()
    AssertPlaced("relayout " .. round .. ", Layout before the queued pass")
end
AssertNoMSUFFields("after the relayouts")

-- Combat: the menu opens (or relays out on a store/trial event) under
-- lockdown. The native layout stands untouched until combat ends; then MSUF
-- re-places its row once.
widgets:EnterCombat()
menu:InitButtons()
menu:Layout()
widgets:RunTimers()
env.MSUF_PositionGameMenuButton()
assert(#combatWrites == 0, "MSUF wrote the Blizzard Game Menu during combat: " .. table.concat(combatWrites, ", "))
assert(menu:GetHeight() == 400 and not button:IsShown(), "the MSUF row stayed on the native combat layout")
widgets:LeaveCombat()
AssertPlaced("after combat")

-- Turned off: the next native relayout stays native.
env.MSUF_SetGameMenuButtonEnabled(false)
menu:InitButtons()
menu:Layout()
widgets:RunTimers()
local _, _, _, _, macroY = macro:GetPoint(1)
assert(menu:GetHeight() == 400 and macroY == -200 and not button:IsShown(),
    "a native relayout re-applied the disabled MSUF row")
print("game_menu_native_relayout_smoke: OK")
