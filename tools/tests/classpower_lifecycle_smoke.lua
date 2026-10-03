-- classpower_lifecycle_smoke.lua <repoRoot>
--
-- Class Resource lifecycle transitions against the REAL ClassPower stack of a
-- client TOC (tools/tests/classpower_world.lua):
--   1. A profile with every Class Resource feature off disables the module
--      (CP.DisableNow). The second Player HP bar lives in PHP.frame and an
--      outline host that is a sibling on the player frame; both hide, and both
--      come back when the module is enabled again. Toggling only the bar off
--      and on keeps its outline too.
--
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

--- The shared unit-frame helpers the Player HP bar reads at controller load.
local function PlayerHPHooks()
    return {
        beforeLoad = function()
            _G.MSUF_UF_NormalizePlayerHPShape = function(value)
                value = value and tostring(value):upper() or "BAR"
                return value ~= "" and value or "BAR"
            end
            _G.MSUF_UF_NormalizeClassPowerShape = function() return "BAR" end
            _G.MSUF_UF_ShapeOutlineAlpha = function() return 1 end
            _G.MSUF_SetFontChecked = function(region, path, size, flags)
                region:SetFont(path, size, flags)
                return true
            end
        end,
    }
end

-- 1. The second Player HP bar follows the module lifecycle, outline included.
do
    local t = World.Start(repo, "Mainline", "WARRIOR", 1, World.PT.RAGE, {
        showClassPower = false, playerHPBarEnabled = true, playerHPBarWidthMode = "custom", playerHPBarWidth = 180,
    }, PlayerHPHooks())
    t.env:RunTimers()
    local PHP = World.Upvalue(t.CP.DisableNow, "PHP")
    local function Shown()
        return PHP.frame ~= nil and PHP.frame.shown == true, PHP.borderHost ~= nil and PHP.borderHost.shown == true
    end
    local frameShown, outlineShown = Shown()
    Check(PHP.visible and frameShown and outlineShown, "the second Player HP bar did not show with its outline")

    MSUF_DB.bars.playerHPBarEnabled = false
    Check(not t.module.IsEnabled(), "a profile with every Class Resource feature off keeps the module enabled")
    t.module.Disable()
    t.env:RunTimers()
    frameShown, outlineShown = Shown()
    Check(not PHP.visible and not frameShown, "module disable left the second Player HP bar on screen")
    Check(not outlineShown, "module disable left the second Player HP bar's outline on screen")
    -- A profile switch then applies the whole profile.
    _G.MSUF_ClassPower_Apply({ full = true, cdm = true })
    t.env:RunTimers()
    frameShown, outlineShown = Shown()
    Check(not frameShown and not outlineShown, "the profile apply after a module disable showed the Player HP bar")

    MSUF_DB.bars.playerHPBarEnabled = true
    t.module.Enable()
    t.env:RunTimers()
    frameShown, outlineShown = Shown()
    Check(PHP.visible and frameShown and outlineShown, "the re-enabled second Player HP bar lost its outline")

    MSUF_DB.bars.playerHPBarEnabled = false
    _G.MSUF_ClassPower_Apply({ full = true })
    t.env:RunTimers()
    frameShown, outlineShown = Shown()
    Check(not frameShown and not outlineShown, "turning the Player HP bar off left part of it on screen")
    MSUF_DB.bars.playerHPBarEnabled = true
    _G.MSUF_ClassPower_Apply({ full = true })
    t.env:RunTimers()
    frameShown, outlineShown = Shown()
    Check(frameShown and outlineShown, "turning the Player HP bar off and on lost its outline")
end

if #failures > 0 then
    error("classpower_lifecycle_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_lifecycle_smoke: ok (Player HP disable)")
