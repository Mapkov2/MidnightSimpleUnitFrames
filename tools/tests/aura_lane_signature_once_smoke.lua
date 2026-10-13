-- aura_lane_signature_once_smoke.lua <repoRoot> <flavor>
--
-- Native aura lanes build their button signature once per finalization
-- (raid trace 2026-10-11).
-- FinalizeLane (Auras3/Runtime/MSUF_Auras3_Runtime_ConfigValues.lua) stores a
-- structural and a layout signature; both embed LaneButtonSignature
-- (MSUF_Auras3_Runtime_Signatures.lua), a ~70-field concatenation. The trace's
-- worst combat-end apply finalized 96 group lanes and built 192 button
-- signatures, 2.73 ms self. FinalizeLane now calls LaneShapeSignatures, which
-- builds it once and hands it to both builders.
--
-- Pinned on the real core (tools/tests/group_header_world.lua: every core file
-- of the flavor, a five-member raid and the single unit frames):
--   1. every FinalizeLane runs LaneButtonSignature exactly once (it ran twice);
--   2. the stored structural and layout signatures are byte-identical to the
--      builders as they were before this change (frozen copy below), for
--      every lane the boot finalized (group and unit lanes);
--   3. LaneShapeSignatures and the builders called with a lane alone
--      (NativeApply's fallback) answer the pre-change strings, also for
--      synthetic lanes that reach the branches the boot does not (standalone
--      slot, custom priority, pandemic colours and frame effect).
--
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2 (Mainline or Forever: the
-- Classic flavors replace this runtime).

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local SIGNATURES = "MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Signatures.lua"
local CONFIG_VALUES = "MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_ConfigValues.lua"

-- The line a function starts on, found by its declaration (no fixed numbers).
local function LineOf(path, pattern)
    local file = assert(io.open(root .. "/" .. path, "rb"), "missing source: " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local number = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        number = number + 1
        if line:find(pattern) then return number end
    end
    error(flavor .. ": no line matches " .. pattern .. " in " .. path)
end
local BUTTON_LINE = LineOf(SIGNATURES, "^LaneButtonSignature = function%(")
local FINALIZE_LINE = LineOf(CONFIG_VALUES, "^local function FinalizeLane%(")

---------------------------------------------------------------------------
-- Frozen reference: the three builders before this change (e97f8b46), each
-- of which called LaneButtonSignature itself. Do not edit to make this pass:
-- a changed signature string changes which native containers are reused.
---------------------------------------------------------------------------
local Reference = {}
local function ReferenceStandalone(lane)
    return lane and lane.max == 1
        and lane.weaponEnchants ~= true
        and lane.customPriority ~= true
end
function Reference.Button(lane, A3)
    return tostring(lane.size) .. "\030" .. tostring(lane.iconZoom) .. "\030" .. tostring(lane.spacing)
        .. "\030" .. tostring(lane.iconShape) .. "\030" .. tostring(lane.requestedIconShape)
        .. "\030" .. tostring(lane.buttonWidth) .. "\030" .. tostring(lane.buttonHeight)
        .. "\030" .. tostring(lane.step) .. "\030" .. tostring(lane.stepX) .. "\030" .. tostring(lane.stepY)
        .. "\030" .. tostring(lane.perRow)
        .. "\030" .. tostring(lane.cols) .. "\030" .. tostring(lane.rows)
        .. "\030" .. tostring(lane.width) .. "\030" .. tostring(lane.height)
        .. "\030" .. tostring(lane.layer)
        .. "\030" .. tostring(lane.strata)
        .. "\030" .. tostring(lane.xSign) .. "\030" .. tostring(lane.ySign)
        .. "\030" .. tostring(lane.verticalGrowth) .. "\030" .. tostring(lane.initialAnchor)
        .. "\030" .. tostring(lane.showCooldownText) .. "\030" .. tostring(lane.showCooldownSwipe)
        .. "\030" .. tostring(lane.cooldownSwipeReverse) .. "\030" .. tostring(lane.cooldownSize)
        .. "\030" .. tostring(lane.cooldownAnchor) .. "\030" .. tostring(lane.cooldownX)
        .. "\030" .. tostring(lane.cooldownY) .. "\030" .. tostring(lane.cooldownDecimalSeconds)
        .. "\030" .. tostring(lane.showDurationBar) .. "\030" .. tostring(lane.durationBarHeight)
        .. "\030" .. tostring(lane.durationBarDisplay) .. "\030" .. tostring(lane.durationBarPosition)
        .. "\030" .. tostring(lane.durationBarDirection)
        .. "\030" .. tostring(lane.showStacks) .. "\030" .. tostring(lane.stackAnchor)
        .. "\030" .. tostring(lane.stackSize) .. "\030" .. tostring(lane.stackX)
        .. "\030" .. tostring(lane.stackY) .. "\030" .. tostring(lane.showTooltip)
        .. "\030" .. tostring(lane.auraTooltipAnchor)
        .. "\030" .. tostring(lane.showAuraBorder) .. "\030" .. tostring(lane.showAuraSymbol)
        .. "\030" .. tostring(lane.showStealableMarker) .. "\030" .. tostring(lane.stealableStyle)
        .. "\030" .. tostring(lane.pandemicEnabled) .. "\030" .. tostring(lane.pandemicVisualEnabled)
        .. "\030" .. tostring(lane.pandemicStyle)
        .. "\030" .. tostring(lane.pandemicColor and (lane.pandemicColor[1] or lane.pandemicColor.r))
        .. "\030" .. tostring(lane.pandemicColor and (lane.pandemicColor[2] or lane.pandemicColor.g))
        .. "\030" .. tostring(lane.pandemicColor and (lane.pandemicColor[3] or lane.pandemicColor.b))
        .. "\030" .. tostring(lane.pandemicThickness) .. "\030" .. tostring(lane.pandemicPadding)
        .. "\030" .. tostring(lane.pandemicBorderAlpha) .. "\030" .. tostring(lane.pandemicTintAlpha)
        .. "\030" .. tostring(lane.pandemicBlend)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.type)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.priority)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.thickness)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.layer)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.tintAlpha)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.strata)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[1])
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[2])
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[3])
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[4])
        .. "\030" .. tostring(lane.padding)
        .. "\030" .. tostring(lane.portraitPositionWhenDisabled)
        .. "\030" .. tostring(lane.portraitLevelOffset)
        .. "\030" .. tostring(lane.iconStyle and lane.iconStyle.signature)
        .. "\030" .. tostring(A3.GetNativeVisualSignature and A3.GetNativeVisualSignature() or "0")
end
function Reference.Structural(lane, A3)
    local standalone = ReferenceStandalone(lane)
    return tostring(lane.kind) .. "\030" .. tostring(lane.identityCandidateMode)
        .. "\030" .. Reference.Button(lane, A3)
        .. "\030" .. (standalone and (tostring(lane.anchor) .. "\030" .. tostring(lane.x)
            .. "\030" .. tostring(lane.y)) or "host")
        .. "\030" .. tostring(lane.weaponEnchants)
        .. "\030" .. tostring(lane.customPriority)
        .. "\030" .. tostring(lane.customPrioritySignature)
        .. "\030" .. tostring(lane.customPriority and lane.max or nil)
        .. "\030" .. tostring(lane.customPriority and lane.candidateFilterSignature or nil)
        .. "\030" .. tostring(standalone)
end
function Reference.Layout(lane, A3)
    return Reference.Button(lane, A3) .. "\030" .. tostring(lane.anchor) .. "\030" .. tostring(lane.x)
        .. "\030" .. tostring(lane.y) .. "\030" .. tostring(lane.alpha)
end

---------------------------------------------------------------------------
-- 1 and 2: the real boot.
---------------------------------------------------------------------------
local function IsAt(info, line, file)
    return info and info.linedefined == line and info.source:find(file, 1, true) ~= nil
end

local finalized = {}  -- { lane, buttons, structural, layout } per FinalizeLane
local strays = 0      -- LaneButtonSignature calls outside FinalizeLane
local A3              -- the runtime's A3 (an upvalue of LaneButtonSignature)
local active = {}     -- open FinalizeLane activations (innermost last)

local function InsideFinalize()
    local level = 3
    while true do
        local info = debug.getinfo(level, "S")
        if not info then return false end
        if IsAt(info, FINALIZE_LINE, "Runtime_ConfigValues") then return true end
        level = level + 1
    end
end

local function Hook(event)
    local info = debug.getinfo(2, "S")
    if IsAt(info, FINALIZE_LINE, "Runtime_ConfigValues") then
        if event == "return" or event == "tail return" then
            local entry = active[#active]
            active[#active] = nil
            if entry and entry.lane then
                -- The return hook sees the lane with its signatures stored.
                entry.structural = entry.lane._msufA3StructuralSignature
                entry.layout = entry.lane._msufA3LayoutSignature
                entry.expectedStructural = Reference.Structural(entry.lane, A3)
                entry.expectedLayout = Reference.Layout(entry.lane, A3)
            end
        else
            local _, lane = debug.getlocal(2, 1)
            local entry = { lane = type(lane) == "table" and lane or nil, buttons = 0 }
            active[#active + 1] = entry
            if entry.lane then finalized[#finalized + 1] = entry end
        end
    elseif IsAt(info, BUTTON_LINE, "Runtime_Signatures") and event ~= "return" and event ~= "tail return" then
        if not A3 then
            local fn = debug.getinfo(2, "f").func
            local index = 1
            while true do
                local name, value = debug.getupvalue(fn, index)
                if not name then break end
                if name == "A3" then A3 = value end
                index = index + 1
            end
        end
        if InsideFinalize() and active[#active] then
            active[#active].buttons = active[#active].buttons + 1
        else
            strays = strays + 1
        end
    end
end

local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
debug.sethook(Hook, "cr")
local h = Harness.New(root, flavor)
local GF = h.GF
local raid = GF.GetConf("raid")
raid.enabled = true
GF.RefreshHeaderLayout()
h:SetRaid(5)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
debug.sethook()

Check(A3 ~= nil, "LaneButtonSignature never ran: no native aura lane was finalized")
Check(#active == 0, #active .. " FinalizeLane activations never returned (hook bookkeeping)")
local groupLanes, unitLanes = 0, 0
for index = 1, #finalized do
    local entry = finalized[index]
    local lane = entry.lane
    local label = tostring(lane.unit) .. " " .. tostring(lane.kind) .. " (#" .. index .. ")"
    if type(lane.unit) == "string" and (lane.unit:match("^raid%d+$") or lane.unit:match("^party%d+$")) then
        groupLanes = groupLanes + 1
    else
        unitLanes = unitLanes + 1
    end
    Check(entry.buttons == 1, label .. ": FinalizeLane built " .. entry.buttons .. " button signatures, want 1")
    Check(type(entry.structural) == "string" and entry.structural == entry.expectedStructural,
        label .. ": the structural signature differs from the previous builder")
    Check(type(entry.layout) == "string" and entry.layout == entry.expectedLayout,
        label .. ": the layout signature differs from the previous builder")
end
Check(groupLanes > 0, "the boot finalized no group lane")
Check(unitLanes > 0, "the boot finalized no unit lane")
Check(strays == 0, strays .. " LaneButtonSignature calls ran outside FinalizeLane during the boot")

---------------------------------------------------------------------------
-- 3: the builders alone, on synthetic lanes.
---------------------------------------------------------------------------
local namespace = { Auras3RuntimeFactories = {} }
assert(loadfile(root .. "/" .. SIGNATURES))("MidnightSimpleUnitFrames", namespace)
local stubA3 = { GetNativeVisualSignature = function() return "3:1" end }
local Signatures = namespace.Auras3RuntimeFactories.Signatures("MidnightSimpleUnitFrames", namespace, stubA3, {},
    function() end, {})
Check(type(Signatures.LaneShapeSignatures) == "function", "Signatures exports no LaneShapeSignatures")

local function Lane(fields)
    local lane = {
        unit = "target", kind = "buff", identityCandidateMode = "HELPFUL", size = 26, iconZoom = 1.1,
        spacing = 2, iconShape = "SQUARE", requestedIconShape = "SQUARE", buttonWidth = 26, buttonHeight = 26,
        step = 28, stepX = 28, stepY = 28, perRow = 8, cols = 8, rows = 2, width = 222, height = 54, layer = 9,
        strata = "MEDIUM", xSign = 1, ySign = -1, verticalGrowth = false, initialAnchor = "TOPLEFT",
        showCooldownText = true, showCooldownSwipe = true, cooldownSwipeReverse = false, cooldownSize = 12,
        cooldownAnchor = "CENTER", cooldownX = 0, cooldownY = 0, cooldownDecimalSeconds = 3,
        showDurationBar = false, showStacks = true, stackAnchor = "BOTTOMRIGHT", stackSize = 11, stackX = -1,
        stackY = 1, showTooltip = true, auraTooltipAnchor = "ANCHOR_BOTTOMRIGHT", showAuraBorder = true,
        anchor = "BOTTOMLEFT", x = 4, y = -6, alpha = 0.8, max = 16,
        iconStyle = { signature = "style:7" }, candidateFilterSignature = "cf", customPrioritySignature = "cp",
    }
    for key, value in pairs(fields or {}) do lane[key] = value end
    return lane
end
local cases = {
    { "flowing lane", Lane() },
    { "standalone slot", Lane({ max = 1 }) },
    { "custom priority", Lane({ max = 1, customPriority = true }) },
    { "weapon enchants", Lane({ max = 1, weaponEnchants = true }) },
    { "pandemic array colour", Lane({ pandemicEnabled = true, pandemicVisualEnabled = true,
        pandemicStyle = "border", pandemicColor = { 1, 0.5, 0 }, pandemicThickness = 2 }) },
    { "pandemic rgb colour and frame effect", Lane({ pandemicEnabled = true, pandemicColor = { r = 0.2, g = 0.4, b = 0.6 },
        pandemicFrameEffect = { type = "glow", priority = 3, thickness = 2, layer = 4, tintAlpha = 0.5,
            strata = "HIGH", color = { 0.1, 0.2, 0.3, 0.4 } } }) },
}
for index = 1, #cases do
    local label, lane = cases[index][1], cases[index][2]
    local structural = Reference.Structural(lane, stubA3)
    local layout = Reference.Layout(lane, stubA3)
    local shapeStructural, shapeLayout = Signatures.LaneShapeSignatures(lane)
    Check(shapeStructural == structural, label .. ": LaneShapeSignatures changed the structural signature")
    Check(shapeLayout == layout, label .. ": LaneShapeSignatures changed the layout signature")
    Check(Signatures.LaneStructuralSignature(lane) == structural,
        label .. ": the structural signature of a lane alone changed")
    Check(Signatures.LaneLayoutSignature(lane) == layout,
        label .. ": the layout signature of a lane alone changed")
end

print(("aura_lane_signature_once_smoke: ok (%s, %d lanes: %d group, %d unit)"):format(
    flavor, #finalized, groupLanes, unitLanes))
