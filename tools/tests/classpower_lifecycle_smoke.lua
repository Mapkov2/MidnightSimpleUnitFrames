-- classpower_lifecycle_smoke.lua <repoRoot>
--
-- Class Resource lifecycle transitions against the REAL ClassPower stack of a
-- client TOC (tools/tests/classpower_world.lua):
--   1. A profile with every Class Resource feature off disables the module
--      (CP.DisableNow). The second Player HP bar lives in PHP.frame and an
--      outline host that is a sibling on the player frame; both hide, and both
--      come back when the module is enabled again. Toggling only the bar off
--      and on keeps its outline too.
--   2. A maximum that grows while the structure stays (UNIT_MAXPOWER, or a
--      talent that adds combo points) recompiles the visual: ramp and custom
--      slot colours cover the new pips exactly as a full refresh paints them.
--   3. A full refresh inside an MSUF Edit Mode session hides Alt Mana (it is no
--      Edit Mode mover); leaving Edit Mode shows it again.
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

-- 2. Slot colours follow a grown maximum.
local function PipColors(CP)
    local colors = {}
    for i = 1, CP.currentMax or 0 do
        local color = CP.bars[i] and CP.bars[i].color
        colors[i] = color and { color[1], color[2], color[3] } or false
    end
    return colors
end

local function SameColors(left, right)
    if #left ~= #right then return false end
    for i = 1, #left do
        local a, b = left[i], right[i]
        if not (a and b) then return false end
        for channel = 1, 3 do
            if math.abs(a[channel] - b[channel]) > 1e-6 then return false end
        end
    end
    return true
end

local function Describe(colors)
    local out = {}
    for i, color in ipairs(colors) do
        out[i] = color and ("%d:(%.2f,%.2f,%.2f)"):format(i, color[1], color[2], color[3]) or (i .. ":unpainted")
    end
    return table.concat(out, " ")
end

for _, mode in ipairs({ "ramp", "custom" }) do
    for _, event in ipairs({ { "UNIT_MAXPOWER", "player", "COMBO_POINTS" }, { "PLAYER_TALENT_UPDATE" } }) do
        -- Custom slots without an override fall back to the ramp colour of their slot.
        local t = World.Start(repo, "Mainline", "ROGUE", 1, World.PT.ENERGY, {
            classPowerSlotColorModes = { COMBO_POINTS = mode },
        }, {
            beforeLoad = function(_, S)
                S.maxCombo = 5
                function UnitPowerMax(_, powerType)
                    if powerType == S.primary then return 100 end
                    if powerType == World.PT.COMBO then return S.maxCombo end
                    return 5
                end
            end,
        })
        t.env:RunTimers()
        local CP, S = t.CP, t.S
        local label = mode .. " slot colours, " .. event[1]
        Check(CP.visible and CP.currentMax == 5, label .. ": Rogue combo points did not start at five")
        S.combo = 7
        S.maxCombo = 7
        t.onEvent(t.eventFrame, event[1], event[2], event[3])
        t.env:RunTimers()
        local grown = PipColors(CP)
        Check(CP.currentMax == 7 and CP.visual and CP.visual.maxP == 7,
            label .. ": the visual was not compiled for seven pips (max " .. tostring(CP.currentMax)
            .. ", visual " .. tostring(CP.visual and CP.visual.maxP) .. ")")
        _G.MSUF_ClassPower_Refresh()
        t.env:RunTimers()
        local full = PipColors(CP)
        Check(SameColors(grown, full), label .. ": the grown pips are painted\n    " .. Describe(grown)
            .. "\n    a full refresh paints\n    " .. Describe(full))
    end
end

-- 3. Alt Mana is a live surface, not an Edit Mode mover: a full refresh inside an
--    MSUF Edit Mode session hides it, and leaving Edit Mode shows it again.
do
    local listeners = {}
    local t = World.Start(repo, "Mainline", "PRIEST", 3, 13, { showAltMana = true }, {
        beforeLoad = function()
            _G.MSUF_RegisterAnyEditModeListener = function(fn) listeners[#listeners + 1] = fn end
        end,
    })
    t.env:RunTimers()
    local AM = World.Upvalue(t.CP.DisableNow, "AM")
    local function Shown() return AM.visible == true and AM.container ~= nil and AM.container.shown == true end
    local function Notify(active)
        _G.MSUF_UnitEditModeActive = active
        for _, fn in ipairs(listeners) do fn(active) end
        t.env:RunTimers()
    end
    Check(#listeners > 0, "ClassPower registers no Edit Mode listener")
    Check(Shown(), "Shadow Alt Mana did not show")
    Notify(true)
    -- A Class Resource option changed from the menu while Edit Mode is open.
    _G.MSUF_ClassPower_Apply({ full = true })
    t.env:RunTimers()
    Check(not Shown(), "a full refresh in Edit Mode kept Alt Mana (it is no Edit Mode mover)")
    Notify(false)
    Check(Shown(), "leaving Edit Mode did not bring Alt Mana back")
    -- Leaving again without a refresh in between changes nothing.
    Notify(true)
    Notify(false)
    Check(Shown(), "an Edit Mode session without a refresh hid Alt Mana")
    -- Turned off in Edit Mode, it stays off.
    Notify(true)
    MSUF_DB.bars.showAltMana = false
    _G.MSUF_ClassPower_Apply({ full = true })
    t.env:RunTimers()
    Notify(false)
    Check(not Shown(), "leaving Edit Mode showed an Alt Mana bar that was turned off")
    _G.MSUF_UnitEditModeActive = nil
end

if #failures > 0 then
    error("classpower_lifecycle_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_lifecycle_smoke: ok (Player HP disable, grown maximum slot colours, Alt Mana after Edit Mode)")
