-- Edit Mode arrow-key nudge (Shell/EditMode/MSUF_EditMode_Layout_Nudge.lua):
-- the arrows are override bindings on hidden buttons while Edit Mode is open.
--
-- 1. Edit Mode exits at PLAYER_REGEN_DISABLED. The configuration lock already
--    refuses there (Kernel InCombat remembers the edge for the rest of the
--    frame), but InCombatLockdown() is still false and ClearOverrideBindings
--    is still allowed. Deferring the clear to PLAYER_REGEN_ENABLED left the
--    arrow keys (default movement and turning) bound to the hidden buttons for
--    the whole fight.
-- 2. A castbar mover selected with its popup closed (Done after a click, or
--    the WoW Forever gamepad's move mode, which selects without opening it)
--    fell through to db["castbar_player"], which does not exist: castbar
--    offsets live in db.general. The arrows and the pad moved nothing.
-- 3. An aura group's popup (the toolbar then reads "<Unit> / Auras") opens
--    without changing the unit key or the preview nudge target, and the router
--    checked the external, resource and preview routes first: the arrows and
--    the pad moved a previously clicked resource bar, external frame or the
--    tooltip preview instead of the aura group.
-- 4. A mover drag selected the element for the toolbar (Focus) but never set
--    the unit key: only the mover's OnClick does, and a real drag suppresses
--    that click. The arrows and the toolbar's Reset then acted on the element
--    clicked before (on a fresh session, the Player frame).
--
-- Loads the real MSUF_EditMode_State.lua, MSUF_EditMode_Layout_Nudge.lua,
-- MSUF_EditMode_Movers.lua, MSUF_EditMode_HUD_Selection.lua and
-- Game/Forever/PadEditMode.lua, with the Kernel's InCombat taken verbatim from
-- Kernel/MSUF_Util.lua.
-- Usage: lua tools/tests/editmode_nudge_routing_smoke.lua <repoRoot>
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local EM_DIR = "MidnightSimpleUnitFrames/Shell/EditMode/"

local function Read(rel)
    local handle = assert(io.open(root .. "/" .. rel, "rb"), "missing " .. rel)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

-- Client: the lockdown starts after the PLAYER_REGEN_DISABLED dispatch, and a
-- protected binding write under lockdown is blocked.
local now, lockdown = 100, false
GetTime = function() return now end
InCombatLockdown = function() return lockdown end
local bindings, blocked = {}, {}
ClearOverrideBindings = function(owner)
    if lockdown then blocked[#blocked + 1] = "ClearOverrideBindings"; return end
    for key, value in pairs(bindings) do if value.owner == owner then bindings[key] = nil end end
end
SetOverrideBindingClick = function(owner, _, key, buttonName)
    if lockdown then blocked[#blocked + 1] = "SetOverrideBindingClick"; return end
    bindings[key] = { owner = owner, button = buttonName }
end
IsAltKeyDown = function() return false end
IsControlKeyDown = function() return false end
IsShiftKeyDown = function() return false end
C_Timer = { After = function() end }

local created = {}
local Frame = {}
Frame.__index = Frame
function Frame:SetScript(name, handler) self.scripts[name] = handler end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:IsEventRegistered(event) return self.events[event] == true end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:SetSize() end
CreateFrame = function(_, name)
    local frame = setmetatable({ scripts = {}, events = {}, shown = true, name = name }, Frame)
    created[#created + 1] = frame
    if name then _G[name] = frame end
    return frame
end
UIParent = CreateFrame("Frame")

-- Kernel InCombat and the configuration lock built on it (Kernel/MSUF_Util.lua).
local util = Read("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
local inCombatBody = assert(util:match("(local combatEdgeTime\nlocal function InCombat%(event%).-\nend)\n"),
    "Kernel/MSUF_Util.lua no longer defines InCombat(event) after combatEdgeTime")
local InCombat = assert(loadstring(inCombatBody .. "\nreturn InCombat", "Kernel InCombat"))()
assert(util:find("    local function IsConfigCombatLocked(event)\n        return InCombat(event) == true\n    end", 1, true),
    "the configuration lock must stay the edge-aware InCombat(event)")
MSUF_IsConfigCombatLocked = function(event) return InCombat(event) == true end

local ns = { ExportPublic = function(name, value) _G[name] = value; return value end }
local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
RequireFixture.Install(root, ns)

MSUF_DB = { player = { offsetX = 0, offsetY = 0 }, general = {}, bars = {}, auras3 = { perUnit = {}, shared = {} } }
MSUF_GetCastbarPrefix = function(unit) return "castbar" .. unit:sub(1, 1):upper() .. unit:sub(2) end
MSUF_GetCastbarDefaultOffsets = function(unit) if unit == "player" then return 0, 5 end return 65, -15 end
local castbarSyncs = 0
MSUF_SyncCastbarPositionPopup = function() castbarSyncs = castbarSyncs + 1 end
MSUF_EM_UndoBeforeChange = function() end
MSUF_EM2 = {
    Util = {
        Round = function(v) return v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5) end,
        RefreshUFPreview = function() end,
        ApplySettingsForKeySafe = function() return true end,
        ApplyAllSettingsSafe = function() return true end,
        ApplyGroupSettingsForKeySafe = function() return true end,
        -- Shell/EditMode/MSUF_EditMode_Core.lua Util.IsConfigCombatLocked/BlockConfigCombatLocked.
        IsConfigCombatLocked = function(event) return MSUF_IsConfigCombatLocked(event) and true or false end,
        BlockConfigCombatLocked = function() return MSUF_IsConfigCombatLocked() and true or false end,
        ShowConfigCombatLockMessage = function() end,
        ProfileIdentity = function() return "profile" end,
        IsCurrentProfile = function() return true end,
        SharedHistoryService = function() return nil end,
        SyncMovers = function() end,
    },
}
local EM2 = MSUF_EM2
-- Registry rows as MSUF_EditMode_Elements.lua registers them.
local elements = Read(EM_DIR .. "MSUF_EditMode_Elements.lua")
assert(elements:find('key         = "castbar_" .. unit,', 1, true)
    and elements:find('popupType   = "castbar",', 1, true) and elements:find("castbarUnit = unit,", 1, true)
    and elements:find('RegisterCastbarMover("player", "Player Castbar", 110)', 1, true),
    "castbar movers must stay registered as castbar_<unit> with popupType castbar and castbarUnit")
local registry = {
    player = { key = "player", popupType = "unit", canNudge = true },
    target = { key = "target", popupType = "unit", canNudge = true },
    castbar_player = { key = "castbar_player", popupType = "castbar", castbarUnit = "player", canNudge = true },
    -- RegisterResourceMovers' Class Resources row.
    classpower = {
        key = "classpower", popupType = "resource", resourceKind = "classpower", canNudge = true,
        historyCategory = "classpower", historyKey = "bars",
        subframeOffsetXKey = "classPowerOffsetX", subframeOffsetYKey = "classPowerOffsetY",
        getFrame = function() return UIParent end,
        getConf = function() return MSUF_DB.bars end,
        commitSubframePosition = function() return true end,
    },
    ["external:msuf.blizzard:minimap"] = { key = "external:msuf.blizzard:minimap", externalPublicElement = true },
}
local externalNudges = 0
EM2.ExternalElements = { Nudge = function() externalNudges = externalNudges + 1; return true end }
EM2.Registry = { Get = function(key) return registry[key] end, All = function() return registry end }
local focusKey
EM2.Focus = {
    SetSelection = function(key) focusKey = key; return key ~= nil end,
    GetSelection = function() return focusKey end,
    NudgeSelection = function() return false end,
    NotifyPositionChanged = function() end,
}
local castPopupOpen = false
EM2.CastPopup = { IsOpen = function() return castPopupOpen end, GetUnit = function() return "player" end }
local auraPopupOpen = false
EM2.AuraPopup = { IsOpen = function() return auraPopupOpen end }
local undoEntries = {}
EM2.Undo = {
    PrepareChange = function(category, key) return { category = category, key = key } end,
    CommitPrepared = function(snapshot) undoEntries[#undoEntries + 1] = snapshot.category .. ":" .. snapshot.key; return true end,
}
for _, file in ipairs({ "MSUF_EditMode_State.lua", "MSUF_EditMode_Layout_Nudge.lua" }) do
    assert(loadfile(root .. "/" .. EM_DIR .. file))("MidnightSimpleUnitFrames", ns)
end
-- WoW Forever's pad: the mover layer's own nudge option, as PadNavigation calls it.
local watched = {}
ns.Client = { IsForever = true }
ns.PadNavigation = {
    Kit = { Haptic = function() end },
    Watch = function(name, _, _, options) watched[name] = options end,
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Forever/PadEditMode.lua"))("MidnightSimpleUnitFrames", ns)
local moverLayer = assert(watched.MSUF_EM2_MoverParent, "PadEditMode did not watch the mover layer")

local function Arrow(dir)
    local binding = assert(bindings[dir], dir .. " is not bound")
    local button = assert(_G[binding.button], "missing nudge button " .. binding.button)
    button.scripts.OnClick(button, "LeftButton", true)
end

-- 1. Combat edge: Edit Mode's exit at PLAYER_REGEN_DISABLED releases the arrows.
assert(EM2.State.Enter("player") == true, "Edit Mode did not open")
assert(bindings.UP and bindings.DOWN and bindings.LEFT and bindings.RIGHT
    and bindings.RIGHT.button == "MSUF_EM2_NudgeRIGHT", "Edit Mode did not bind the arrow keys to its nudge buttons")
local combatFrame
for _, frame in ipairs(created) do
    if frame.events.PLAYER_REGEN_DISABLED and frame.scripts.OnEvent then combatFrame = frame end
end
assert(combatFrame, "Edit Mode registered no combat listener while open")
combatFrame.scripts.OnEvent(combatFrame, "PLAYER_REGEN_DISABLED")
lockdown = true
assert(not EM2.State.IsActive(), "Edit Mode did not exit at PLAYER_REGEN_DISABLED")
assert(next(bindings) == nil and #blocked == 0,
    "the arrow keys stayed bound to Edit Mode's nudge buttons into the fight (cleared only after combat)")
local owner = assert(MSUF_EM2_NudgeOwner, "nudge binding owner missing")
assert(not owner.__msufPendingClear, "a clear the edge already did was still queued for after combat")
-- Under a real lockdown the clear still waits for PLAYER_REGEN_ENABLED.
lockdown = false
now = now + 1
combatFrame.scripts.OnEvent(combatFrame, "PLAYER_REGEN_ENABLED")
assert(EM2.State.Enter("player") == true and bindings.RIGHT, "Edit Mode did not reopen after combat")
lockdown = true
now = now + 1
EM2.Nudge.Disable()
assert(bindings.RIGHT and #blocked == 0 and owner.__msufPendingClear == true and owner.events.PLAYER_REGEN_ENABLED,
    "a disable under lockdown must defer the clear to PLAYER_REGEN_ENABLED")
lockdown = false
owner.scripts.OnEvent(owner, "PLAYER_REGEN_ENABLED")
assert(next(bindings) == nil and not owner.__msufPendingClear, "the deferred clear did not run after combat")
EM2.State.Exit("test")

-- 2. Castbar mover selected, popup closed: the arrows and the pad move it.
local general = MSUF_DB.general
assert(EM2.State.Enter("player") == true, "Edit Mode did not open")
EM2.State.SetUnitKey("castbar_player")          -- the mover click (Movers.lua OnClick)
Arrow("RIGHT")
assert(general.castbarPlayerOffsetX == 1 and general.castbarPlayerOffsetY == 5 and castbarSyncs > 0,
    "the right arrow did not move the selected Player Castbar with its popup closed")
assert(MSUF_DB.player.offsetX == 0 and MSUF_DB.castbar_player == nil,
    "a castbar nudge must not write the Player frame or a castbar_player profile table")
assert(undoEntries[#undoEntries] == "castbar:player", "the castbar nudge did not record its undo entry")
Arrow("UP")
assert(general.castbarPlayerOffsetX == 1 and general.castbarPlayerOffsetY == 6, "the up arrow did not move the castbar")
-- The pad's move mode selects the mover without opening its popup.
EM2.State.SetUnitKey("player")
local castbarMover, playerMover = { _barKey = "castbar_player" }, { _barKey = "player" }
assert(moverLayer.movable(castbarMover), "the pad must offer Move on a castbar mover")
for _ = 1, 3 do moverLayer.nudge(nil, castbarMover, 1, 0) end
assert(EM2.State.GetUnitKey() == "castbar_player" and general.castbarPlayerOffsetX == 4,
    "the pad's move mode on the Player Castbar mover moved nothing")
moverLayer.nudge(nil, playerMover, 0, -1)
assert(MSUF_DB.player.offsetY == -1 and general.castbarPlayerOffsetY == 6, "the pad's unit mover nudge regressed")
-- With the popup open the popup's castbar still moves (the existing route).
EM2.State.SetUnitKey("castbar_player")
castPopupOpen = true
Arrow("LEFT")
castPopupOpen = false
assert(general.castbarPlayerOffsetX == 3, "the castbar popup's arrow nudge regressed")
EM2.State.Exit("test")

-- 3. The open aura popup wins over an earlier resource, external or preview selection.
local bars = MSUF_DB.bars
local function BuffX()
    local layout = MSUF_DB.auras3.perUnit.player and MSUF_DB.auras3.perUnit.player.layout
    return layout and layout.buffGroupOffsetX or 0
end
-- Auras3/MSUF_Auras3_EditMode_Drag.lua OpenAuraGroupPopup: the aura globals, then the popup.
local function OpenAuraPopup(unit, kind)
    MSUF_EM2_ActiveAuraGroup, MSUF_EM2_ActiveAuraUnit = kind, unit
    auraPopupOpen = true
end
assert(EM2.State.Enter("player") == true, "Edit Mode did not open")
EM2.State.SetUnitKey("classpower")              -- the Class Resources mover click
Arrow("RIGHT")
assert(bars.classPowerOffsetX == 1 and BuffX() == 0, "the arrows no longer move the selected Class Resources")
OpenAuraPopup("player", "buff")
Arrow("RIGHT")
assert(BuffX() == 1 and bars.classPowerOffsetX == 1,
    "with the player's Buffs popup open the arrows moved the earlier Class Resources selection")
watched.MSUF_EM2_AuraPopup.nudge(nil, nil, 1, 0) -- the pad's move mode in the aura popup
assert(BuffX() == 2 and bars.classPowerOffsetX == 1, "the pad in the Buffs popup moved Class Resources")
auraPopupOpen = false
EM2.State.SetUnitKey("external:msuf.blizzard:minimap")
Arrow("RIGHT")
assert(externalNudges == 1, "the arrows no longer move the selected external element")
OpenAuraPopup("player", "buff")
Arrow("RIGHT")
assert(BuffX() == 3 and externalNudges == 1,
    "with the player's Buffs popup open the arrows moved the earlier external selection")
auraPopupOpen = false
EM2.State.SetUnitKey("player")
local previewNudges = 0
MSUF_EM2_SetPreviewNudgeTarget({ frame = UIParent, Nudge = function() previewNudges = previewNudges + 1 end })
Arrow("RIGHT")
assert(previewNudges == 1, "the arrows no longer move the targeted preview")
OpenAuraPopup("player", "buff")
Arrow("RIGHT")
assert(BuffX() == 4 and previewNudges == 1,
    "with the player's Buffs popup open the arrows moved the earlier tooltip preview target")
auraPopupOpen = false
EM2.State.Exit("test")

-- 4. A mover drag selects its element for the arrows and the toolbar's Reset too.
-- Movers build textures, labels and backdrops; those cosmetic calls are no-ops here.
local function Lenient(frame)
    return setmetatable(frame, { __index = function(_, method)
        if Frame[method] then return Frame[method] end
        if not method:find("^%u") then return nil end -- fields, not widget methods
        if method == "CreateTexture" or method == "CreateFontString" then
            return function() return Lenient({ scripts = {}, events = {}, shown = true }) end
        end
        if method == "GetFrameLevel" then return function() return 10 end end
        if method == "IsMouseOver" then return function() return false end end
        return function() end
    end })
end
local plainCreateFrame = CreateFrame
CreateFrame = function(...) return Lenient(plainCreateFrame(...)) end
local cursorX, cursorY = 500, 400
GetCursorPosition = function() return cursorX, cursorY end
MSUF_UF_FrameRectToUI = function() return 0, 100, 100, 0 end
Lenient(UIParent)
UIParent.GetWidth = function() return 1366 end
UIParent.GetHeight = function() return 768 end
UIParent.GetEffectiveScale = function() return 1 end
MSUF_EM_UndoBeginChange = function() return true end
MSUF_EM_UndoCommitChange = function() return true end
MSUF_BlockConfigCombatLocked = function() return MSUF_IsConfigCombatLocked() end
MSUF_GetDefaultUnitOffsets = function(key) if key == "player" then return -260, -200 end return 260, -200 end
MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = function() end
EM2.Util.Tr = function(text) return text end
EM2.Util.ThemeColor = function(_, fallback) return fallback end
EM2.Ticker = { BeginDrag = function() return true end, EndDrag = function() return true end,
    IsDragging = function() return false end }
EM2.HUD = { RefreshUnitSelector = function() end, SetStatus = function() end, RefreshControls = function() end }
EM2.HUDKit = { HelpText = function(text) return text end }
for _, file in ipairs({ "MSUF_EditMode_Movers.lua", "MSUF_EditMode_HUD_Selection.lua" }) do
    assert(loadfile(root .. "/" .. EM_DIR .. file))("MidnightSimpleUnitFrames", ns)
end
MSUF_DB.player.offsetX, MSUF_DB.player.offsetY = 0, 0
MSUF_DB.target = { offsetX = 300, offsetY = 0 }
assert(EM2.State.Enter() == true and EM2.State.GetUnitKey() == "player", "a fresh session must start on the player")
EM2.Movers.Show()
local targetMover = assert(EM2.Movers.Get("target"), "no Target mover")
-- Press on the Target mover, move the cursor 60 px, release: the click that follows is suppressed.
targetMover.scripts.OnMouseDown(targetMover, "LeftButton")
cursorX = cursorX + 60
targetMover.scripts.OnMouseUp(targetMover, "LeftButton")
targetMover.scripts.OnClick(targetMover, "LeftButton")
assert(focusKey == "target", "the drag did not select the Target frame for the toolbar")
assert(EM2.State.GetUnitKey() == "target", "the drag selected the Target frame for the toolbar but not for the arrows")
Arrow("RIGHT")
assert(MSUF_DB.target.offsetX == 301 and MSUF_DB.player.offsetX == 0,
    "the right arrow after dragging the Target frame moved the Player frame instead")
assert(EM2.HUDSelection.CurrentSelectionKey() == "target", "the toolbar's Reset would act on another frame")
EM2.HUD.ResetCurrentPosition()
assert(MSUF_DB.target.offsetX == 260 and MSUF_DB.player.offsetX == 0,
    "the toolbar's Reset after dragging the Target frame reset the Player frame instead")
-- A click replaces another element's open popup (Popups.Open starts with
-- Popups.CloseAll); the arrows prefer an open castbar or aura popup over the
-- unit key, so a drag must close those too.
local popupsSource = Read(EM_DIR .. "MSUF_EditMode_Popups.lua")
local closeAll = assert(popupsSource:match("\nfunction Popups%.CloseAll%(%)\n(.-)\nend\n"), "Popups.CloseAll is missing")
assert(closeAll:find("if EM2.CastPopup then EM2.CastPopup.Close() end", 1, true)
    and closeAll:find("if EM2.AuraPopup then EM2.AuraPopup.Close() end", 1, true)
    and popupsSource:find("    Popups.CloseAll()\n\n    if pType == \"external\" then", 1, true),
    "Popups.Open must close every popup, the castbar and aura popups among them, before it opens one")
EM2.CastPopup.Close = function() castPopupOpen = false end
EM2.AuraPopup.Close = function() auraPopupOpen = false end
EM2.Popups = { CloseAll = function() EM2.CastPopup.Close(); EM2.AuraPopup.Close() end }
local function Drag(mover)
    mover.scripts.OnMouseDown(mover, "LeftButton")
    cursorX = cursorX + 60
    mover.scripts.OnMouseUp(mover, "LeftButton")
    mover.scripts.OnClick(mover, "LeftButton")
end
local castbarX = general.castbarPlayerOffsetX
EM2.State.SetUnitKey("castbar_player")          -- the Player Castbar mover click opened its popup
castPopupOpen = true
Drag(targetMover)
Arrow("RIGHT")
assert(not castPopupOpen and MSUF_DB.target.offsetX == 261 and general.castbarPlayerOffsetX == castbarX,
    "after dragging the Target frame with the Player Castbar popup open the arrows moved the castbar")
-- Dragging the castbar whose popup is open keeps that popup and its arrows.
local castbarDragMover = assert(EM2.Movers.Get("castbar_player"), "no Player Castbar mover")
EM2.State.SetUnitKey("castbar_player")
castPopupOpen = true
Drag(castbarDragMover)
Arrow("RIGHT")
assert(castPopupOpen and general.castbarPlayerOffsetX == castbarX + 1 and MSUF_DB.target.offsetX == 261,
    "dragging the Player Castbar closed its own popup")
castPopupOpen = false
OpenAuraPopup("player", "buff")                 -- an aura group click; the unit key stays
local buffX = BuffX()
Drag(targetMover)
Arrow("RIGHT")
assert(not auraPopupOpen and MSUF_DB.target.offsetX == 262 and BuffX() == buffX,
    "after dragging the Target frame with the player's Buffs popup open the arrows moved the Buffs")
-- A plain click (no drag) still selects through OnClick as before.
local playerMover = assert(EM2.Movers.Get("player"), "no Player mover")
playerMover.scripts.OnMouseDown(playerMover, "LeftButton")
playerMover.scripts.OnMouseUp(playerMover, "LeftButton")
playerMover.scripts.OnClick(playerMover, "LeftButton")
assert(EM2.State.GetUnitKey() == "player" and focusKey == "player", "a mover click no longer selects its element")
EM2.State.Exit("test")

print("Edit Mode nudge routing: arrows released at the combat edge, castbar selected without its popup, "
    .. "open aura popup over earlier selections, drag selects for arrows and Reset passed")
