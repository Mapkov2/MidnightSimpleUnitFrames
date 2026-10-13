-- editmode_blizzard_layout_fields_smoke.lua <repoRoot>
--
-- MSUF Edit Mode offers Blizzard's Micro Menu and Bags settings. Blizzard
-- applies them as plain fields its layout code reads: the system mixins
-- assign MicroMenu.isHorizontal, layoutFramesGoingRight/Up and
-- BagsBar.isHorizontal, direction, bagPadding; MicroMenu:SetNormalScale stores
-- normalScale; Layout() caches oldGridSettings (live and forever
-- Blizzard_EditMode/Shared/EditModeSystemTemplates.lua,
-- Blizzard_MicroMenu/Shared/MicroMenuContainer.lua,
-- Blizzard_MainMenuBarBagButtons/Shared/BagsBar.lua). Written from MSUF code,
-- or by one of those Blizzard methods called from MSUF code, every such field
-- carries MSUF taint into Blizzard's layout. Blizzard's own application path,
-- EDIT_MODE_LAYOUTS_UPDATED (a synchronous event, EditModeManagerDocumentation
-- .lua) -> UpdateLayoutInfo, also re-lays the action bars; it answers
-- SetActiveLayout and may answer SaveLayouts inside the call.
--
-- The smoke delivers that event synchronously inside SaveLayouts to a
-- modelled Blizzard handler and records which Micro Menu and Bags values each
-- layout pass carries. Pinned: a changed Micro Menu orientation, order or size
-- and a changed Bags orientation, direction or padding are staged in MSUF's
-- per-character SavedVariables (MSUF_GlobalDB.char[character]
-- .blizzardEditModeStaged[layout]) and read back by their controls, with zero
-- SaveLayouts, no layout activation, no field write and no field-writing
-- method call; the profile snapshot (what an opt-in export carries) keeps the
-- committed values, also right after an import, and takes the staged ones when
-- the Reload commits them, before that save. No other MSUF
-- save (a live size, a move, an imported snapshot) carries a staged value into
-- a layout pass, and an undo of staged values only (a full capture) saves
-- nothing. A new staged value says a reload applies it and offers one
-- MSUF-owned Reload prompt naming the pending elements; the offer returns on
-- the next Edit Mode visit and goes once nothing is staged. The Reload click
-- and the profile import's reload (MSUF_BlizzardEditMode_ReloadUI) are one
-- path: never in combat, it merges the staged values, saves exactly once and
-- reloads right after; that is the only layout pass with staged values, and
-- with nothing staged it only reloads. Every SaveLayouts runs through the one
-- wrapper, called from the listed functions only. The queue eye size
-- (MicroMenu:SetQueueStatusScale, scale and anchors only) and the Bags size
-- (widget SetScale) apply at once. Nothing commits during combat.
--
-- Plain Lua 5.1, repo root as arg 1. Real Shell/EditMode files.

local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local function Check(ok, message)
    if not ok then error(message, 2) end
end
local function Load(relative, namespace)
    local chunk = assert(loadfile(root .. "/" .. relative))
    chunk("MidnightSimpleUnitFrames", namespace)
end

-- Enum values from the live EditModeManagerConstantsDocumentation.lua.
local SYSTEM = { Minimap = 2, ChatFrame = 8, HudTooltip = 11, MicroMenu = 13, Bags = 14, DamageMeter = 23 }
local MICRO = { Orientation = 0, Order = 1, Size = 2, EyeSize = 3 }
local BAGS = { Orientation = 0, Direction = 1, Size = 2, BagSlotPadding = 3 }
-- Blizzard Lua methods on these frames that store fields with the caller's taint.
local FIELD_WRITERS = {
    "SetNormalScale", "SetOverrideScale", "ClearOverrideScale", "UpdateScale", "Layout", "MarkDirty",
    "AnchorToMenuContainer", "UpdateSystem", "UpdateSystemSetting", "UpdateSystemSettingOrientation",
    "UpdateSystemSettingOrder", "UpdateSystemSettingSize", "UpdateSystemSettingEyeSize",
    "UpdateSystemSettingDirection", "UpdateSystemSettingBagSlotPadding",
}
local log = { writes = {}, calls = {}, scale = nil, eyeScale = nil }

local function BlizzardFrame(label, fields)
    local methods = {}
    function methods:GetScale() return 1 end
    function methods:ClearAllPoints() end
    function methods:SetPoint() end
    function methods:SetScale(scale) log.scale = scale end
    function methods:SetQueueStatusScale(scale) log.eyeScale = scale end
    for index = 1, #FIELD_WRITERS do
        local method = FIELD_WRITERS[index]
        methods[method] = function() log.calls[#log.calls + 1] = label .. ":" .. method end
    end
    return setmetatable({}, {
        __index = function(_, key)
            if fields[key] ~= nil then return fields[key] end
            return methods[key]
        end,
        __newindex = function(_, key, value)
            log.writes[#log.writes + 1] = label .. "." .. tostring(key)
            fields[key] = value
        end,
    })
end

_G.Enum = {
    EditModeSystem = SYSTEM,
    EditModePresetLayoutsMeta = { NumValues = 2 },
    EditModeMinimapSetting = { HeaderUnderneath = 0, RotateMinimap = 1, Size = 2 },
    EditModeChatFrameSetting = { WidthHundreds = 0, WidthTensAndOnes = 1, HeightHundreds = 2, HeightTensAndOnes = 3 },
    EditModeMicroMenuSetting = MICRO,
    EditModeBagsSetting = BAGS,
    EditModeDamageMeterSetting = { FrameWidth = 3, FrameHeight = 4 },
    EditModeLayoutType = { Account = 1, Character = 2 },
    MicroMenuOrientation = { Horizontal = 0, Vertical = 1 },
    MicroMenuOrder = { Default = 0, Reverse = 1 },
    BagsOrientation = { Horizontal = 0, Vertical = 1 },
}
_G.HUD_EDIT_MODE_MICRO_MENU_LABEL, _G.HUD_EDIT_MODE_BAGS_LABEL = "Micro Menu", "Bags"
local created = {}
local function PlainFrame(systemId)
    local frame = { system = systemId, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, fn) self.onEvent = fn end
    function frame:GetScale() return 1 end
    function frame:ClearAllPoints() end
    function frame:SetPoint() end
    return frame
end
_G.CreateFrame = function()
    local frame = PlainFrame(nil)
    created[#created + 1] = frame
    return frame
end
local function Fire(event, ...)
    for _, frame in ipairs(created) do
        if frame.events[event] and frame.onEvent then frame.onEvent(frame, event, ...) end
    end
end
_G.UIParent = PlainFrame(nil)
-- MicroMenuContainer.xml and MainMenuBarBagButtons.xml seed these values.
_G.MicroMenu = BlizzardFrame("MicroMenu",
    { isHorizontal = true, layoutFramesGoingRight = true, layoutFramesGoingUp = false, normalScale = 1 })
local container = BlizzardFrame("MicroMenuContainer", { system = SYSTEM.MicroMenu })
local bags = BlizzardFrame("BagsBar", { system = SYSTEM.Bags, isHorizontal = true, direction = 0, bagPadding = 4 })
_G.EditModeManagerFrame = { registeredSystemFrames = { PlainFrame(SYSTEM.Minimap), container, bags } }
local combat = false
_G.InCombatLockdown = function() return combat end
-- MSUF's own SavedVariables and character key (State/MSUF_Profiles.lua).
_G.MSUF_GlobalDB = { char = {} }
_G.MSUF_GetCharKey = function() return "Tester-Realm" end

local function Row(setting, value) return { setting = setting, value = value } end
local function Entry(systemId, settings)
    return { system = systemId, settings = settings,
        anchorInfo = { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", offsetX = 0, offsetY = 0 } }
end
local microEntry = Entry(SYSTEM.MicroMenu, { Row(MICRO.Orientation, 0), Row(MICRO.Order, 0), Row(MICRO.Size, 6),
    Row(MICRO.EyeSize, 10) })
local bagsEntry = Entry(SYSTEM.Bags, { Row(BAGS.Orientation, 0), Row(BAGS.Direction, 0), Row(BAGS.Size, 5),
    Row(BAGS.BagSlotPadding, 4) })
local layoutInfo = { activeLayout = 3, layouts = { { layoutName = "Mine", layoutType = 1, systems = { microEntry, bagsEntry } } } }
-- What Blizzard applied at load; a layout pass carrying anything else carries a
-- staged value.
local APPLIED = {
    [SYSTEM.MicroMenu] = { [MICRO.Orientation] = 0, [MICRO.Order] = 0, [MICRO.Size] = 6 },
    [SYSTEM.Bags] = { [BAGS.Orientation] = 0, [BAGS.Direction] = 0, [BAGS.BagSlotPadding] = 4 },
}
local sequence = {}
-- EditModeManagerFrame:OnEvent -> UpdateLayoutInfo, as far as this smoke needs it.
local function BlizzardLayoutPass(info)
    local staged = false
    for _, entry in ipairs(info.layouts[info.activeLayout - 2].systems) do
        for _, row in ipairs(entry.settings) do
            local applied = APPLIED[entry.system]
            if applied and applied[row.setting] ~= nil and applied[row.setting] ~= row.value then staged = true end
        end
    end
    sequence[#sequence + 1] = staged and "pass:staged" or "pass"
end
local general
local saves = 0
-- The profile snapshot's Bags padding at each save (what an export would carry).
local snapshotAtSave
_G.C_EditMode = {
    GetLayouts = function() return layoutInfo end,
    -- The synchronous echo: EDIT_MODE_LAYOUTS_UPDATED inside the save.
    SaveLayouts = function(info)
        Check(info == layoutInfo, "the adapter saved a detached layout table")
        saves = saves + 1
        sequence[#sequence + 1] = "save"
        local bagsSnapshot = general.blizzardEditModeSnapshot and general.blizzardEditModeSnapshot.bags
        snapshotAtSave = bagsSnapshot and bagsSnapshot.settings and bagsSnapshot.settings[BAGS.BagSlotPadding]
        BlizzardLayoutPass(info)
        Fire("EDIT_MODE_LAYOUTS_UPDATED", info, false)
    end,
    SetActiveLayout = function() error("MSUF activated a layout (C_EditMode.SetActiveLayout)", 2) end,
}
_G.ReloadUI = function()
    Check(not combat, "ReloadUI ran during combat")
    sequence[#sequence + 1] = "reload"
end
local registered, session = {}, nil
_G.MSUF_EditModeAPI = {
    RegisterElement = function(_, element) registered[element.id] = element; return true end,
    UnregisterOwner = function() return true end,
    RegisterSessionListener = function(_, callback) session = callback; return true end,
    RefreshOwner = function() return true end,
}
general = { blizzardEditModeIntegration = true, blizzardEditModeSnapshot = {} }
_G.MSUF_GetGeneralDB = function() return general end
_G.MSUF_EM2 = { Registry = {} }
local statuses = {}
_G.MSUF_EM2_SetHUDStatus = function(text) statuses[#statuses + 1] = text end
local prompt, prompts = nil, 0
local ns = {
    ExportPublic = function(name, value) _G[name] = value; return value end,
    Client = { IsForever = false, SupportsEvent = function() return true end },
    UI = {
        ShowPrompt = function(key, spec) prompt, prompts = { key = key, spec = spec }, prompts + 1 end,
        HidePrompt = function(key) if prompt and prompt.key == key then prompt = nil end end,
    },
}
local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
RequireFixture.Install(root, ns)
Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalProvider.lua", ns)
Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Blizzard.lua", ns)
Fire("PLAYER_LOGIN")
Check(registered.micromenu and registered.bags, "the Micro Menu and Bags elements were not registered")

local function Control(element, id)
    for _, control in ipairs(registered[element].extraControls or {}) do
        if control.id == id then return control end
    end
    error("missing " .. element .. " control " .. id)
end
local function Stored(entry, setting)
    for _, row in ipairs(entry.settings) do
        if row.setting == setting then return row.value end
    end
end
local function Staged(element)
    local char = _G.MSUF_GlobalDB.char["Tester-Realm"]
    local layouts = char and char.blizzardEditModeStaged
    local layout = layouts and layouts.Mine
    return layout and layout[element]
end
local function CheckUntouched(context)
    Check(#log.writes == 0, context .. ": MSUF wrote " .. table.concat(log.writes, ", "))
    Check(#log.calls == 0, context .. ": MSUF called " .. table.concat(log.calls, ", ") .. " from addon code")
    for _, step in ipairs(sequence) do
        Check(step ~= "pass:staged", context .. ": an MSUF save handed a staged value to Blizzard's layout pass")
    end
    log.writes, log.calls, sequence = {}, {}, {}
end
local function Offered(context, names)
    Check(prompt and prompt.spec.owned == true and prompt.spec.onAccept, context .. " did not offer the MSUF-owned Reload prompt")
    Check(prompt.spec.text:find("Apply: " .. names, 1, true), context .. ": the prompt does not name "
        .. names .. ": " .. tostring(prompt.spec.text))
    Check(statuses[#statuses] == "Requires a UI reload.", context .. " did not say a reload applies it")
end

-- Each staged setting: zero saves, staged per character and layout, read back,
-- nothing on the Blizzard frames, one reload offer per new value.
local cases = {
    { "micromenu", "vertical", true, microEntry, MICRO.Orientation, 1, "Micro Menu" },
    { "micromenu", "reverse", true, microEntry, MICRO.Order, 1, "Micro Menu" },
    { "micromenu", "size", 120, microEntry, MICRO.Size, 10, "Micro Menu" },
    { "bags", "vertical", true, bagsEntry, BAGS.Orientation, 1, "Bags, Micro Menu" },
    { "bags", "reversedir", true, bagsEntry, BAGS.Direction, 1, "Bags, Micro Menu" },
    { "bags", "padding", 7, bagsEntry, BAGS.BagSlotPadding, 7, "Bags, Micro Menu" },
}
for _, case in ipairs(cases) do
    local element, id, value, entry, setting, raw, names = case[1], case[2], case[3], case[4], case[5], case[6], case[7]
    local label = element .. " " .. id
    local savesBefore, before = saves, prompts
    local shown = Stored(entry, setting)
    Check(Control(element, id).set(value) == true, label .. " did not commit")
    Check(saves == savesBefore, label .. " called SaveLayouts while staging")
    CheckUntouched(label)
    Check(Stored(entry, setting) == shown, label .. " reached the layout MSUF saves")
    Check((Staged(element) or {})[setting] == raw, label .. " was not staged per character and layout")
    Check(Control(element, id).get() == value, label .. " does not read back its staged value")
    local snapshot = general.blizzardEditModeSnapshot[element]
    Check(snapshot and snapshot.settings and snapshot.settings[setting] == shown,
        label .. ": the profile snapshot took the pending value instead of the committed one")
    Check(prompts == before + 1, label .. " did not offer the reload once")
    Offered(label, names)
    Control(element, id).set(value)
    Check(prompts == before + 1 and saves == savesBefore, label .. ": the same value again saved or offered again")
end
Check(_G.MicroMenu.isHorizontal == true and _G.MicroMenu.normalScale == 1 and bags.bagPadding == 4
    and bags.isHorizontal == true, "Blizzard's own Micro Menu or Bags state changed before the reload")

-- Live sizes save and apply at once; their save carries no staged value.
local before = prompts
Check(Control("bags", "size").set(150) == true and math.abs((log.scale or 0) - 1.5) < 1e-9,
    "the Bags size did not apply through SetScale: " .. tostring(log.scale))
Check(Control("micromenu", "eyesize").set(120) == true and math.abs((log.eyeScale or 0) - 1.2) < 1e-9,
    "the queue eye size did not apply through SetQueueStatusScale: " .. tostring(log.eyeScale))
Check(prompts == before and saves > 0, "a live size change offered a reload or was not saved")
CheckUntouched("live sizes")

-- A move saves the anchor without the staged values.
local moved = registered.bags.captureState()
moved.x, moved.settings = moved.x + 10, nil
Check(registered.bags.restoreState(moved) == true, "the Bags move did not commit")
CheckUntouched("Bags move")

-- The next Edit Mode visit offers the pending reload again.
prompt = nil
session(false)
session(true)
Offered("next visit", "Bags, Micro Menu")
CheckUntouched("next visit")

-- Undo back to the applied values from full captures (the live sizes ride
-- along unchanged): no save, the offer for Bags goes, then all.
local savesBefore = saves
local undo = registered.bags.captureState()
Check(undo.settings[BAGS.Size] == 15 and undo.settings[BAGS.BagSlotPadding] == 7,
    "the Bags capture is not a full capture holding the pending values")
undo.settings[BAGS.Orientation], undo.settings[BAGS.Direction], undo.settings[BAGS.BagSlotPadding] = 0, 0, 4
Check(registered.bags.restoreState(undo) == true and Staged("bags") == nil, "the Bags undo did not clear its staged values")
Check(prompt ~= nil, "undoing the Bags changes dropped the Micro Menu offer")
undo = registered.micromenu.captureState()
Check(undo.settings[MICRO.EyeSize] == 14 and undo.settings[MICRO.Size] == 10,
    "the Micro Menu capture is not a full capture holding the pending values")
undo.settings[MICRO.Orientation], undo.settings[MICRO.Order], undo.settings[MICRO.Size] = 0, 0, 6
Check(registered.micromenu.restoreState(undo) == true and Staged("micromenu") == nil, "the Micro Menu undo did not clear")
Check(prompt == nil and saves == savesBefore, "the undo saved a layout or kept the reload offer")
CheckUntouched("undo")

-- Combat: nothing commits, and the offer cannot reload.
Check(Control("bags", "vertical").set(true) == true, "the Bags change did not commit")
Offered("Bags vertical after undo", "Bags")
combat = true
savesBefore = saves
log.scale = nil
Check(Control("bags", "size").set(100) ~= true and Control("micromenu", "vertical").set(true) ~= true,
    "a setting committed during combat")
Check(prompt.spec.canAnswer() == false, "the Reload prompt can be answered during combat")
prompt.spec.onAccept()
Check(saves == savesBefore and log.scale == nil and #sequence == 0, "combat saved, applied or reloaded")
combat = false

-- An imported profile snapshot stages its Micro Menu and Bags values too.
general.blizzardEditModeSnapshot.micromenu.settings = { [MICRO.Orientation] = 1, [MICRO.Size] = 4, [MICRO.EyeSize] = 6 }
general.blizzardEditModeSnapshot.bags.settings = { [BAGS.Orientation] = 1, [BAGS.Size] = 3, [BAGS.BagSlotPadding] = 2 }
Check(_G.MSUF_BlizzardEditMode_ApplyProfileSnapshot() == true, "the profile snapshot did not apply")
Check(Stored(microEntry, MICRO.Size) == 6 and Stored(bagsEntry, BAGS.BagSlotPadding) == 4
    and Staged("micromenu")[MICRO.Size] == 4 and Staged("bags")[BAGS.BagSlotPadding] == 2,
    "the profile snapshot saved staged values instead of staging them")
Check(math.abs((log.scale or 0) - 0.9) < 1e-9 and Stored(bagsEntry, BAGS.Size) == 3,
    "the snapshot's live Bags size did not apply and save: " .. tostring(log.scale))
CheckUntouched("profile snapshot")
-- An export before the Reload carries the committed state, not the pending import.
local exported = general.blizzardEditModeSnapshot
Check(exported.bags.settings[BAGS.BagSlotPadding] == 4 and exported.bags.settings[BAGS.Orientation] == 0
    and exported.micromenu.settings[MICRO.Size] == 6 and exported.micromenu.settings[MICRO.Orientation] == 0,
    "the imported snapshot keeps pending Micro Menu or Bags values an export would carry")
Check(exported.bags.settings[BAGS.Size] == 3 and exported.micromenu.settings[MICRO.EyeSize] == 6,
    "the imported snapshot lost the committed live sizes")

-- The Reload click out of combat, here through the profile import's entry:
-- one save with the merged values, then the reload; the only layout pass that
-- carries staged values.
Check(prompt.spec.canAnswer() == true, "the Reload prompt cannot be answered out of combat")
Check(prompt.spec.onAccept == _G.MSUF_BlizzardEditMode_ReloadUI,
    "the Reload offer and the profile import's reload take different paths")
savesBefore = saves
_G.MSUF_BlizzardEditMode_ReloadUI()
Check(saves == savesBefore + 1, "Reload saved " .. tostring(saves - savesBefore) .. " times, expected once")
Check(table.concat(sequence, ",") == "save,pass:staged,reload",
    "Reload did not save the merged layout right before reloading: " .. table.concat(sequence, ","))
Check(Stored(microEntry, MICRO.Orientation) == 1 and Stored(microEntry, MICRO.Size) == 4
    and Stored(bagsEntry, BAGS.Orientation) == 1 and Stored(bagsEntry, BAGS.BagSlotPadding) == 2,
    "Reload did not merge the staged values into the saved layout")
Check(Staged("micromenu") == nil and Staged("bags") == nil, "Reload left the staged values pending")
Check(snapshotAtSave == 2 and general.blizzardEditModeSnapshot.micromenu.settings[MICRO.Size] == 4,
    "Reload did not commit the staged values into the profile snapshot before saving")
Check(#log.writes == 0 and #log.calls == 0, "Reload wrote a Blizzard field or called a field-writing method")
sequence = {}
_G.MSUF_BlizzardEditMode_ReloadUI()
Check(table.concat(sequence, ",") == "reload", "a reload with nothing staged saved: " .. table.concat(sequence, ","))

-- Commit a padding change (2 -> 7), then the next login: the export carries 7.
Check(Control("bags", "padding").set(7) == true and Staged("bags")[BAGS.BagSlotPadding] == 7,
    "the padding change was not staged")
Check(general.blizzardEditModeSnapshot.bags.settings[BAGS.BagSlotPadding] == 2,
    "the pending padding entered the profile snapshot before the Reload")
prompt.spec.onAccept()
Check(snapshotAtSave == 7 and Stored(bagsEntry, BAGS.BagSlotPadding) == 7, "the Reload did not commit padding 7")
-- ReloadUI ends the session without its exit refresh, and the next login keeps
-- an existing snapshot: what the Reload stored is what that login exports.
Check(general.blizzardEditModeSnapshot.bags.settings[BAGS.BagSlotPadding] == 7,
    "after the next login the profile snapshot (and so the export) does not carry the committed padding 7")

-- Every SaveLayouts runs through the one wrapper, from the listed callers only
-- (each documented at its call: out of combat, no staged value carried).
local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Blizzard.lua", "rb"))
local source = handle:read("*a"):gsub("\r\n", "\n")
handle:close()
local ALLOWED = { EnsureEditableLayout = 1, ReloadWithStaged = 1, MutateSettings = 1, Restore = 1, ApplyProfileSnapshot = 1 }
local found, direct, current = {}, 0, nil
for line in (source .. "\n"):gmatch("([^\n]*)\n") do
    current = line:match("^local function ([%w_]+)") or line:match("^([%w_]+) = function") or current
    local code = line:gsub("%-%-.*$", "")
    for prefix in code:gmatch("([%w_%.:]*)SaveLayouts%(") do
        if prefix:sub(-1) == "." or prefix:sub(-1) == ":" then
            direct = direct + 1
        elseif not code:find("function SaveLayouts(", 1, true) then
            found[current or "?"] = (found[current or "?"] or 0) + 1
        end
    end
end
Check(direct == 1, "C_EditMode.SaveLayouts is called outside the one wrapper (" .. direct .. " direct calls)")
for name, count in pairs(found) do
    Check(ALLOWED[name] == count, "SaveLayouts is called from " .. name .. " (" .. count .. "x), not a listed caller")
end
for name, count in pairs(ALLOWED) do
    Check(found[name] == count, "the listed SaveLayouts caller " .. name .. " no longer saves once")
end
print("editmode_blizzard_layout_fields_smoke: OK")
