--- Group Border + Group Number wiring smoke.
---
--- Both features were dead end-to-end: the block border had no live-apply path
--- (only GF.SetupHeader touched it, and its public wrapper had zero callers)
--- and neither the in-world nor the menu preview drew it. The raid group number
--- rendered nowhere in the menu preview and its in-world gate tested a table
--- that always exists. Pin the geometry and every wiring hop that rotted.

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source:gsub("\r\n", "\n")
end

local function Has(source, needle, message)
    assert(source:find(needle, 1, true), message)
end

-- ---------------------------------------------------------------- geometry --

local created = 0
local function NewTexture()
    created = created + 1
    local tex = { shown = false, points = {} }
    function tex:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function tex:ClearAllPoints() self.points = {} end
    function tex:SetPoint(point, _, relPoint, x, y)
        self.points[#self.points + 1] = { point, relPoint, x, y }
    end
    function tex:SetHeight(v) self.height = v end
    function tex:SetWidth(v) self.width = v end
    function tex:Show() self.shown = true end
    function tex:Hide() self.shown = false end
    return tex
end

local host = {}
function host:CreateTexture() return NewTexture() end

_G = _G or _ENV
_G.CreateFrame = function() return { SetPoint = function() end } end
_G.UIParent = {}
_G.InCombatLockdown = function() return false end
_G.issecretvalue = function() return false end

local MSUF = { GF = {}, UF = {} }
_G.MSUF_NS = MSUF
_G.MSUF = MSUF
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"))("MSUF", MSUF)

local GF = MSUF.GF
local Paint = GF.ApplyGroupBorderToFrame
assert(type(Paint) == "function", "ApplyGroupBorderToFrame is not exported")

-- Disabled draws nothing and allocates nothing.
assert(Paint(host, { groupBorderEnabled = false }) == false, "disabled border reported a draw")
assert(created == 0, "disabled border created textures")

-- Enabled draws all four edges with the configured size/padding/color.
assert(Paint(host, {
    groupBorderEnabled = true,
    groupBorderSize = 3,
    groupBorderPadding = 7,
    groupBorderR = 0.1, groupBorderG = 0.2, groupBorderB = 0.3, groupBorderA = 0.4,
}) == true, "enabled border did not report a draw")
local edges = host.MSUFGFGroupBorder
assert(type(edges) == "table", "border edge table missing")
for _, key in ipairs({ "top", "bottom", "left", "right" }) do
    local edge = edges[key]
    assert(edge and edge.shown, "border edge not shown: " .. key)
    assert(#edge.points == 2, "border edge needs two anchors: " .. key)
    assert(edge.color[1] == 0.1 and edge.color[4] == 0.4, "border color not applied: " .. key)
end
assert(edges.top.height == 3 and edges.left.width == 3, "border thickness not applied")
-- Padding pushes the box outward on every side.
assert(edges.top.points[1][3] == -7 and edges.top.points[1][4] == 7, "top-left padding sign flipped")
assert(edges.bottom.points[2][3] == 7 and edges.bottom.points[2][4] == -7, "bottom-right padding sign flipped")
assert(created == 4, "expected exactly four border edges, got " .. created)

-- Re-applying reuses the pooled textures instead of leaking new ones.
Paint(host, { groupBorderEnabled = true })
assert(created == 4, "border re-apply leaked textures")

-- Turning it off hides the pooled edges.
Paint(host, { groupBorderEnabled = false })
for _, key in ipairs({ "top", "bottom", "left", "right" }) do
    assert(edges[key].shown == false, "border edge stayed visible after disable: " .. key)
end

-- A caller may force the border off while another surface owns the block.
Paint(host, { groupBorderEnabled = true }, false)
assert(edges.top.shown == false, "forced-off border still drew")

-- ------------------------------------------------------------------ wiring --

local runtime = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua")
Has(runtime, "RefreshGroupBorderForMask(kind, mask)",
    "RefreshVisualsNow no longer refreshes the group block border")
Has(runtime, "GF.ApplyGroupBorder(kind)",
    "the group border live-apply hop is gone; only SetupHeader would reach it again")

local headers = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua")
Has(headers, "ApplyGroupBorderForKey(key)",
    "SetupHeader no longer routes through the preview-aware border apply")
Has(headers, "GroupBorderPreviewOwned",
    "the live anchor no longer yields the border to an active preview")

local preview = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
Has(preview, "GF.ApplyGroupBorderToFrame(container, conf)",
    "the in-world group preview stopped drawing the block border")
Has(preview, "raidGroupCfg.enabled == true",
    "the preview raid-group gate is back to testing the always-present table")
Has(preview, "RaidGroupPreviewText(raidGroupCfg.style",
    "the preview raid-group label no longer uses the shared runtime formatter")

local status = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua")
Has(status, "RaidGroupText = RaidGroupText,",
    "the raid-group formatter is no longer shared with the previews")
Has(status, "local index = RAID_TOKEN_INDEX[unit]",
    "the raid index no longer comes from the unit token, so group frames depend on UnitInRaid again")
Has(status, "if isPlayerKnown == true and isPlayer ~= true then",
    "the raid-group identity gate fails closed on an unknown identity again")

-- GROUP_ROSTER_UPDATE also fires on joins, leaves and disconnects. Subgroups
-- are cold data, so combat must cost nothing -- see the functional check below.
local groupStatus = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua")
Has(groupStatus, "UpdateRaidGroupColdPath",
    "the raid-group runners no longer route through the combat-deferred cold path")
Has(groupStatus, "if raidGroupDeferred then return end",
    "the combat deferral is no longer coalesced to one call per combat")

local render = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
Has(render, "PaintGroupBlockBorder(mock, conf, previewScale, ScaleValue)",
    "the menu group preview stopped drawing the block border")
Has(render, "StatusText(spec, runtimeCfg, conf)",
    "the status handle text no longer receives the runtime config, so the group number cannot follow its style")
Has(render, "if spec.fitTextBounds == true and statusHandle._statusText then",
    "the preview handle no longer shrinks onto its text, so it drifts half a box off the live anchor")
Has(render, "statusHandle:SetHitRectInsets(-padX, -padX, -padY, -padY)",
    "the shrunk group number handle lost the hit area that keeps it draggable")

-- The group number is a preview-only status spec: that is what gives it a
-- draggable handle plus the generic anchor/x/y write-back, without adding an
-- entry to the Status Icons dropdown.
local native = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")
Has(native, "PREVIEW_ONLY_STATUS_SPECS",
    "the preview-only status spec list is gone; the group number loses its drag handle")
Has(native, 'value = "showGroupNumber", text = "Group Number", enabled = "showGroupNumber"',
    "the group number preview spec is gone")
Has(native, 'anchor = "groupNumberAnchor"',
    "the group number handle no longer writes back to the real anchor key")
Has(native, "spec.alwaysInMode == true",
    "preview-only specs are gated behind the Status Icons selection again")
Has(native, "fitTextBounds = true",
    "the group number handle is a padded box again, so preview and frame disagree on where the anchor sits")
Has(native, "PreviewRaidGroupText",
    "the preview no longer formats the group number like the runtime")

local previewSpecs = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Specs.lua")
Has(previewSpecs, "showGroupNumber=raidGroup",
    "the preview cannot resolve the group number's compiled runtime config")

local handles = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua")
Has(handles, "handle._statusSpec.previewOnly ~= true",
    "clicking the group number handle hijacks the Status Icons selection again")

local page = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua")
Has(page, "groupNumberScopeHint:SetText(",
    "the Group Number card lost its raid-only scope hint")
Has(page, '"groupNumberStyle", "PAREN"',
    "the Group Number card lost its style dropdown")
Has(page, 'STATUS_ICON_ANCHORS, leftW, "groupNumberAnchor"',
    "the Group Number anchor dropdown cannot represent every anchor a preview drag can write")

local db = Read("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua")
Has(db, 'groupNumberStyle      = "PAREN"',
    "groupNumberStyle has no default, so the style dropdown would never persist")

-- Cards must fit inside their section, and every control inside its card.
-- Growing the Group Number card without moving the Group Border card below it
-- silently clipped both against the next section.
local function CardBottom(source, title)
    local y, h = source:match('W%.ControlCard%(indicators, "' .. title .. '", [^,]+, leftX, %-(%d+), leftW, (%d+)%)')
    assert(y and h, "could not read the " .. title .. " card geometry")
    return tonumber(y) + tonumber(h), tonumber(y), tonumber(h)
end
local sectionHeight = tonumber(page:match('CollapsibleSection%("indicators", "Frame Indicators", (%d+)'))
assert(sectionHeight, "indicators section height missing")
local numberBottom, _, numberHeight = CardBottom(page, "Group Number")
local borderBottom, borderY = CardBottom(page, "Group Border")
assert(borderY >= numberBottom,
    ("Group Border card overlaps Group Number (starts at %d, Group Number ends at %d)"):format(borderY, numberBottom))
assert(sectionHeight >= borderBottom,
    ("Frame Indicators section is %dpx but its cards need %dpx"):format(sectionHeight, borderBottom))
local hintY = tonumber(page:match("groupNumberScopeHint = W%.Text%(groupNumberCard, \"\", 16, %-(%d+)"))
assert(hintY, "group number scope hint offset missing")
local lastControlY = 316
assert(hintY >= lastControlY + 40,
    ("the scope hint at -%d overlaps the last slider at -%d"):format(hintY, lastControlY))
assert(numberHeight >= hintY + 40,
    ("the Group Number card (%dpx) clips its scope hint at -%d"):format(numberHeight, hintY))

-- ------------------------------------------------------------ style output --

-- Load the status element for the shared formatter both previews consume.
_G.UnitInRaid = function(unit) return tonumber(tostring(unit):match("^raid(%d+)$")) end
_G.GetRaidRosterInfo = function(i) return "Name" .. i, 0, math.ceil(i / 5) end
_G.UnitIsPlayer = function() return true end
_G.UnitExists = function() return true end
MSUF.UF.elements = {}
MSUF.UF.RegisterElement = function(name, element) MSUF.UF.elements[name] = element end
MSUF.UF.IsUnitToken = function(u) return type(u) == "string" and u ~= "" end
MSUF.UF.FreshUnitState = function(frame) return frame._msufUnitState end
MSUF.UF.ReadUnitExistsCached = function() return true, true end
MSUF.UF.ReadDeadCached = function() return false, true end
MSUF.UF.ReadConnectedCached = function() return true, true end
MSUF.UF.ReadUnitIsPlayerCached = function() return true, true end
MSUF.UF.ReadUnitClassCached = function() return "WARRIOR", true end
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"))("MSUF", MSUF)
local RT = assert(MSUF.UFStatusRuntime, "status runtime missing")

local Format = RT.RaidGroupText
assert(type(Format) == "function", "RaidGroupText is not exported")
assert(Format("PAREN", 3) == "(3)", "PAREN style changed")
assert(Format("BRACKET", 3) == "[3]", "BRACKET style changed")
assert(Format("NONE", 3) == "3", "NONE style changed")
assert(Format(nil, 3) == "(3)", "missing style must fall back to PAREN")

-- --------------------------------------------------------- combat behaviour --
-- Subgroups are cold data, so an in-combat roster event must cost nothing. When
-- the raid group is the sole consumer of GROUP_ROSTER_UPDATE the registration
-- is dropped for the fight (literally zero); leader/assist genuinely need the
-- event, so there the raid group only short-circuits. Either way a roster
-- change that happened during combat has to be repainted afterwards -- subgroup
-- swaps and token reassignment are NOT combat-blocked by the game.

local combat = false
_G.InCombatLockdown = function() return combat end
local driver
_G.CreateFrame = function()
    local f = { events = {} }
    function f:SetScript(_, fn) self.onEvent = fn end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetAllPoints() end
    function f:SetFrameLevel() end
    function f:Hide() end
    function f:Show() end
    driver = driver or f
    return f
end

local paints = 0
local realUpdateRaidGroup = RT.UpdateRaidGroup
RT.UpdateRaidGroup = function(f, s) paints = paints + 1; return realUpdateRaidGroup(f, s) end
local deferrals = 0
GF.DeferGroupRuntime = function() deferrals = deferrals + 1 end
GF.DIRTY_VISUAL = 0x02
GF.frames = {}
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua"))("MSUF", MSUF)
local groupRuntimeElement = assert(MSUF.UF.elements and MSUF.UF.elements.GroupStatusRuntime,
    "GroupStatusRuntime element missing")

local function NewStatusFS()
    local fs = {}
    function fs:SetText(t) self.text = t end
    function fs:SetShown(v) self.shown = v end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    function fs:GetParent() return nil end
    function fs:SetFont() return true end
    return fs
end

local FRAME_COUNT = 40
local function RunCombatScenario(leaderPair)
    paints, deferrals = 0, 0
    GF.frames = {}
    local scenarioStatus = {
        group = true, enabled = true, groupRuntimeEnabled = true,
        runtimeRaidGroup = true, runtimeLeaderPair = leaderPair or nil,
        groupRuntimeUnitlessEvents = { "GROUP_ROSTER_UPDATE" },
        raidGroup = { enabled = true, size = 10, anchor = "TOPRIGHT", x = 0, y = 0, layer = 7, style = "PAREN" },
        leader = { enabled = leaderPair or false }, assist = { enabled = false },
    }
    for i = 1, FRAME_COUNT do
        local f = {
            MSUFUnitKey = "raid" .. i, raidGroupNameText = NewStatusFS(),
            _msufUnitState = { existsKnown = true, exists = true },
            _msufActiveElements = { GroupStatusRuntime = true },
        }
        f.MSUFSpec = { status = scenarioStatus, _msufGFCompileSerial = 1 }
        GF.frames[f] = true
        groupRuntimeElement.Apply(f)
    end
    local applyPaints = paints
    paints = 0

    driver.onEvent(driver, "GROUP_ROSTER_UPDATE")
    local oocPaints = paints
    paints = 0

    combat = true
    driver.onEvent(driver, "PLAYER_REGEN_DISABLED")
    local stillRegistered = driver.events["GROUP_ROSTER_UPDATE"] == true
    for _ = 1, 3 do
        if driver.events["GROUP_ROSTER_UPDATE"] then driver.onEvent(driver, "GROUP_ROSTER_UPDATE") end
    end
    local combatPaints, combatDeferrals = paints, deferrals
    paints, deferrals = 0, 0

    combat = false
    driver.onEvent(driver, "PLAYER_REGEN_ENABLED")
    return {
        applyPaints = applyPaints, oocPaints = oocPaints, stillRegistered = stillRegistered,
        combatPaints = combatPaints, combatDeferrals = combatDeferrals, exitPaints = paints,
    }
end

local soleConsumer = RunCombatScenario(false)
assert(soleConsumer.applyPaints == FRAME_COUNT,
    "binding a frame must paint its raid group, even in combat")
assert(soleConsumer.oocPaints == FRAME_COUNT,
    "an out-of-combat roster event must repaint every frame")
assert(soleConsumer.stillRegistered == false,
    "GROUP_ROSTER_UPDATE stayed registered in combat although the raid group was its only consumer")
assert(soleConsumer.combatPaints == 0 and soleConsumer.combatDeferrals == 0,
    "in-combat roster handling is no longer free when the raid group owns the event")
assert(soleConsumer.exitPaints == FRAME_COUNT,
    "the roster change missed during combat was never replayed on combat exit")

local sharedConsumer = RunCombatScenario(true)
assert(sharedConsumer.stillRegistered == true,
    "GROUP_ROSTER_UPDATE was suspended even though leader/assist still need it live")
assert(sharedConsumer.combatPaints == 0,
    "the raid group repainted in combat instead of short-circuiting")
assert(sharedConsumer.combatDeferrals == 1,
    ("three in-combat roster events must coalesce into one deferral, got %d")
        :format(sharedConsumer.combatDeferrals))

print("group_border_number_smoke: ok")
