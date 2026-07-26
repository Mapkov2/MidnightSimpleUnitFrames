-- Regression: Guided Setup stays readable, keeps conditional Spell Icon
-- controls in its mission, and acknowledges real setting interactions.
local root = arg and arg[1] or "."

local function Read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function Contains(source, value, message)
    assert(source:find(value, 1, true), message or ("missing contract: " .. value))
end

local guided = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_GuidedTour.lua")
local bindings = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings.lua")
local widgets = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua")
local shared = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua")
local units = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
local unitAuras = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua")
local unitText = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua")
local unitVisuals = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua")
local unitStatus = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua")
local groups = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group.lua")
local groupBars = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua")
local groupIndicators = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua")
local groupAuras = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua")
local editPopups = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Popups.lua")
local editMovers = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Movers.lua")

Contains(guided, "includeLockedControls = true", "Spell Icon Lab must include visible locked options")
Contains(guided, 'id = "power_moves"', "short tour does not explain MSUF power moves")
Contains(guided, 'id = "unit_copy_open"', "Unitframe workflow does not teach Copy To")
Contains(guided, 'id = "unit_copy_all"', "Unitframe workflow does not select all copy categories")
Contains(guided, 'id = "unit_copy_apply"', "Unitframe workflow does not execute the real copy")
Contains(guided, 'id = "uf_player_auras"', "Player workflow omits Aura containers and tools")
Contains(guided, 'id = "uf_player_name"', "Player workflow omits Name text")
Contains(guided, 'id = "uf_player_hp_text"', "Player workflow omits HP text")
Contains(guided, 'id = "uf_player_power_text"', "Player workflow omits Power text")
Contains(guided, 'id = "uf_player_portrait"', "Player workflow omits Portrait")
Contains(guided, 'id = "uf_player_power"', "Player workflow omits Power Bar")
Contains(guided, 'id = "uf_player_castbar"', "Player workflow omits Castbar")
Contains(guided, 'id = "uf_player_status"', "Player workflow omits Status Icons")
Contains(guided, 'id = "group_copy_open"', "Group workflow does not teach Copy To")
Contains(guided, 'id = "group_copy_apply"', "Group workflow does not execute the real copy")
Contains(guided, 'id = "gf_party_name"', "Party workflow omits Name text")
Contains(guided, 'id = "gf_party_hp_text"', "Party workflow omits HP text")
Contains(guided, 'id = "gf_party_power_text"', "Party workflow omits Power text")
Contains(guided, 'id = "gf_party_resource"', "Party workflow omits the Resource Bar")
Contains(guided, 'id = "gf_party_range"', "Party workflow omits Range Fade")
Contains(guided, 'id = "gf_party_dispel"', "Party workflow omits Dispel Overlay")
Contains(guided, 'id = "gf_party_stripe"', "Party workflow omits Debuff Stripe")
Contains(guided, 'id = "gf_party_indicators"', "Party workflow omits Frame Indicators")
Contains(guided, 'id = "gf_party_status"', "Party workflow omits Status Icons")
Contains(guided, 'id = "gf_party_corner_icons"', "Party workflow omits Corner Indicators")
Contains(guided, 'id = "gf_party_auras"', "Party workflow omits Aura lanes")
Contains(guided, 'id = "unit_intro"', "complete setup is not split into a Unitframe chapter")
Contains(guided, 'id = "group_intro"', "complete setup is not split into a Group Frames chapter")
Contains(guided, 'id = "class_intro"', "complete setup is not split into a Class Resources chapter")
Contains(guided, '"group/auras/spell/selected/placed/type"', "Spell Icon mission does not reach Indicator Type")
Contains(guided, '"group/auras/spell/selected/frame/type"', "Spell Icon mission does not reach Frame Effect")
Contains(guided, "local control = byPath[controlPaths[i]]", "curated Spell Icon controls are not kept in learning order")
Contains(guided, "type(widget.IsVisible) == \"function\"", "guided controls can target children of hidden tabs or notices")
Contains(guided, "label = GuidedControlLabel(record, widget)", "guided labels do not resolve from visible control titles")
Contains(guided, "Semantic identities are excellent stable keys, but terrible UI copy.", "technical control identities can leak into guided copy")
Contains(guided, "marker._msuf2DualPointer = true", "guided target needs the dual pointer")
Contains(guided, "CHANGED +10 XP", "guided interaction feedback missing")
Contains(guided, "MISSION %d/%d - %d XP", "mission progress label missing")
Contains(guided, "UNLOCK, THEN CHANGE IT - Enable Spell Indicators", "Spell Icon prerequisite coaching missing")
Contains(guided, "function M.NotifyGuidedTourControlInteraction(widget)", "interaction receipt API missing")
local refreshChromeBody = assert(guided:match("function M%.RefreshGuidedTourChrome%(reason%)(.-)function M%.RunGuidedTourStep"),
    "could not inspect Guided Tour chrome refresh")
Contains(refreshChromeBody, "ReconcileGuidedEditModePopup(stage)",
    "chrome refresh does not reconcile an already-open geometry popup")
Contains(guided, "guided_setting_change_required", "Next does not require an interaction with the highlighted setting")
Contains(guided, "return { overview = false, sectionIndex = 1, controlIndex = 1", "normal missions do not start on a real control")
Contains(guided, "local changeReady = stage.special or not position.control or touched", "Next button is not locked to the current interaction")
Contains(guided, "local color = (T.colors and T.colors.ok)", "guided target is not guaranteed to use the green success color")
Contains(guided, 'AddGroup("setupArea")', "setup route choices are not highlighted as the first action")
Contains(guided, 'value = "unitframes"', "intro cannot select Unitframes only")
Contains(guided, 'value = "groupframes"', "intro cannot select Group Frames only")
Contains(guided, 'value = "classresources"', "intro cannot select Class Resources only")
Contains(guided, 'value = "all"', "intro cannot select the complete three-part tour")
Contains(guided, "SetTourPreviewInlineMode(true)", "guided pages do not activate inline preview mode")
Contains(guided, "SetTourPreviewInlineMode(false)", "guided exit does not restore normal preview behavior")
Contains(guided, "function M.GuidedTourOwnsPreviewLayout()", "guided tour does not own floating-preview layout")
Contains(guided, "M.StartNewAssistantTask()", "Finish does not hand off to the Dashboard Assistant")
Contains(guided, 'tonumber(state.currentStageIndex) ~= stage.index', "expanded tour does not normalize saved stage indexes")
Contains(guided, 'scroll = false', "lazy Player sections are not materialized without moving the viewport")
Contains(guided, 'stage.area == "groupframes"', "Party missions do not restore Party as their master scope")
Contains(bindings, "NotifyGuidedControlInteraction(self)", "bound widgets do not report interaction")
Contains(bindings, "NotifyGuidedControlInteraction(dropdown)", "dropdown interaction is not reported")
Contains(bindings, "NotifyGuidedControlInteraction(editBox)", "text interaction is not reported")
Contains(bindings, "NotifyGuidedControlInteraction(colorButton)", "color interaction is not reported")
Contains(widgets, "M.GuidedTourOwnsPreviewLayout() == true", "normal floating pins are not suppressed during the tour")
Contains(widgets, "if pinBtn.Hide then pinBtn:Hide() end", "tour still offers a misleading Pin Preview action")
Contains(widgets, "stableId", "guided Copy To regions do not have stable identities")
Contains(widgets, "opts.scroll ~= false", "silent lazy-section preparation still scrolls the Player page")
Contains(unitAuras, '"unit_aura_tools"', "Player Aura selectors do not have a stable guided region")
Contains(unitText, "sec._msuf2GuidedSelectTab", "Player Text missions cannot open the required tab")
Contains(unitVisuals, "sec._msuf2GuidedSelectTab", "Player Castbar mission cannot open the General tab")
Contains(unitStatus, "sec._msuf2GuidedSelectTab", "Player Status mission cannot open the Basic tab")
Contains(shared, "opts.onPopupCreated(popup, api)", "real Copy To popup cannot join the guided flow")
Contains(shared, "NotifyGuidedInteraction(runBtn)", "Unit Copy Selected action is not acknowledged before the popup closes")
Contains(shared, "NotifyGuidedInteraction(btn)", "Group copy destination is not acknowledged before the popup closes")
Contains(units, 'M.RegisterGuidedCopyPopup("unit"', "Player Copy To popup cannot be restored on resume")
Contains(groups, 'M.RegisterGuidedCopyPopup("group"', "Party Copy To popup cannot be restored on resume")
Contains(units, '"unit_copy_popup"', "Player Copy To popup has no stable guided region")
Contains(groups, '"group_copy_popup"', "Party Copy To popup has no stable guided region")
Contains(groups, "sec._msuf2GuidedSelectScope = SelectScope", "Party missions cannot restore their master scope live")
Contains(groupBars, "text._msuf2GuidedSelectTab", "Party Text missions cannot open the required tab")
Contains(groupBars, '"text." .. kind .. ".slot.mode"', "Party HP/Power slot editor has no stable guided identity")
Contains(groupBars, "text._msuf2GuidedSelectSlot", "Party text missions cannot select the slot edited by the shared control")
Contains(unitText, "sec._msuf2GuidedSelectSlot", "Player text missions cannot select the slot edited by the shared control")
Contains(groupIndicators, "sicons._msuf2GuidedSelectTab", "Party Status mission cannot open the Basic tab")
Contains(groupIndicators, '"corner.editor.spell_ids"', "Corner custom spell input has no stable guided identity")
Contains(groupAuras, '"group_aura_tools"', "Party Aura selectors do not have a stable guided region")
Contains(groupAuras, '"group-workspace.container-selector"', "Party Aura container selector has no stable guided identity")
Contains(editPopups, "NotifyGuidedPopupOpened(key)", "popup router does not acknowledge guided geometry popups")
assert(not editMovers:find("menu.NotifyGuidedEditModePopupOpened", 1, true),
    "mover still owns the popup acknowledgement instead of the popup router")

assert(not guided:find("original * 0.46", 1, true), "guided sections must not be faded")
assert(not guided:find("original * 0.38", 1, true), "guided controls must not be faded")
assert(not guided:find("function M.AcquireGuidedTourPreviewDock", 1, true), "guided setup still reparents the preview into a dock")
assert(not widgets:find("GUIDED_TOUR_PREVIEW_DOCK", 1, true), "pinned preview still contains guided dock behavior")
assert(not guided:find('nextLabel = "Start mission"', 1, true), "normal missions still contain an unhighlighted overview step")
assert(not guided:find('nextLabel = "Enter section"', 1, true), "normal missions still contain an unhighlighted section step")

local function Node(parent, top, left)
    return {
        GetParent = function() return parent end,
        GetTop = function() return top end,
        GetLeft = function() return left end,
        IsShown = function() return true end,
        IsEnabled = function() return true end,
    }
end

local outer = Node(nil, 700, 100)
local body = Node(outer, 670, 100)
local widget = Node(body, 630, 130)
local widget2 = Node(body, 590, 130)
widget._msuf2Title = { GetText = function() return "Enable" end }
widget2._msuf2Title = { GetText = function() return "Growth direction" end }
body._msuf2CollapsibleEntry = {
    outer = outer,
    body = body,
    label = { GetText = function() return "Frame basics" end },
    guidedOrder = 1,
}
local controlId = "menu2.uf_player.test_setting"
local controlId2 = "menu2.uf_player.second_setting"
widget._msuf2CommandAction = { controlId = controlId }
widget2._msuf2CommandAction = { controlId = controlId2 }
local state = {
    status = "active",
    profileName = "Default",
    currentStageId = "uf_player",
    currentStageIndex = 3,
    cursors = {
        uf_player = {
            overview = true,
            sectionIndex = 0,
            controlIndex = 0,
            controlTotal = 0,
        },
    },
    controlResults = {},
}
local tour = {}
function tour:IsActive() return self == tour and state.status == "active" end
function tour:GetState() return state end
function tour:GetCursor(stageId) return state.cursors[stageId] end
function tour:SetCursor(stageId, cursor) state.cursors[stageId] = cursor return true end
local M = {
    activeKey = "uf_player",
    cache = { uf_player = { sections = { frame_basics = body } } },
    RuntimeControlCatalog = {
        GetRecords = function()
            return {
                { controlId = controlId, pageKey = "uf_player", classification = "setting", label = "Enable", identityLabel = "unit.basics.enabled", kind = "toggle" },
                { controlId = controlId2, pageKey = "uf_player", classification = "setting", label = "Up", identityLabel = "unit.layout.growth_direction", kind = "slider" },
            }
        end,
        Get = function(id)
            if id == controlId then return { widget = widget } end
            if id == controlId2 then return { widget = widget2 } end
        end,
    },
}
local MSUF = { MSUF2 = M, GuidedTour6 = tour }
assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_GuidedTour.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(M.guidedTourStageCount == 39, "guided setup lost the thirty-nine-stage core workflow")
assert(M.GuidedTourOwnsPreviewLayout() == true, "active guided tour did not suppress floating preview pins")
state.status = "paused"
assert(M.GuidedTourOwnsPreviewLayout() == false, "inactive guided tour still owned preview layout")
state.status = "active"
local refreshReason
M.RefreshGuidedTourChrome = function(reason) refreshReason = reason end
_G.MSUF_ActiveProfile = "Default"
local advanced, blocked = M.RunGuidedTourStep("next")
assert(advanced == false and blocked == "guided_setting_change_required", "Next advanced without changing the green setting")
assert(state.cursors.uf_player.controlId == controlId, "legacy overview cursor did not migrate to the first green setting")
assert(M.NotifyGuidedTourControlInteraction(widget) == true, "current guided control interaction was rejected")
assert(refreshReason == "CONTROL_USED", "guided interaction did not refresh its checkpoint")
assert(M.NotifyGuidedTourControlInteraction(Node(body, 610, 130)) == false, "unrelated widget cleared the checkpoint")
local warned, warningReason, warningText = M.RunGuidedTourStep("skip")
assert(warned == true and warningReason == "confirmation_needed", "first setting did not show its skip warning")
assert(warningText:find("Enable", 1, true), "visible Enable label was not used for guided copy")
assert(not warningText:find("unit.basics.enabled", 1, true), "technical basics identity leaked into guided copy")
assert(M.RunGuidedTourStep("back") == true, "first skip warning could not be cancelled")
assert(M.RunGuidedTourStep("next") == true, "changed setting did not unlock Next")
assert(state.cursors.uf_player.controlId == controlId2, "Next did not move the green marker to the next setting")
warned, warningReason, warningText = M.RunGuidedTourStep("skip")
assert(warned == true and warningReason == "confirmation_needed", "second setting did not show its skip warning")
assert(warningText:find("Growth direction", 1, true), "visible control title was not used for guided copy")
assert(not warningText:find("unit.layout.growth_direction", 1, true), "technical identity leaked into guided copy")
assert(not warningText:find(" Up ", 1, true), "transient option value leaked into guided copy")
assert(M.RunGuidedTourStep("back") == true, "skip warning could not be cancelled")
advanced, blocked = M.RunGuidedTourStep("next")
assert(advanced == false and blocked == "guided_setting_change_required", "new green setting inherited the previous interaction")

-- Regression: entering the Party placement mission with its geometry popup
-- already open used to leave "Open size popup" disabled forever.
state.preferences = {
    setupMode = "complete",
    setupArea = "all",
    groupEditModeMoved = true,
}
state.currentStageId = "group_edit_mode"
function tour:GetPreference(key) return state.preferences[key] end
function tour:SetStage(stageId, stageIndex)
    state.currentStageId, state.currentStageIndex = stageId, stageIndex
    return true
end
function tour:MarkEditModePopupOpened(key)
    if state.currentStageId ~= "group_edit_mode" or (key ~= "gf_party" and key ~= "party") then return false end
    local changed = state.preferences.groupEditModePopupOpened ~= true
    state.preferences.groupEditModePopupOpened = true
    return true, changed
end
local popupOpen, popupKey = true, "gf_party"
_G.MSUF_EM2 = {
    Popups = {
        IsAnyOpen = function() return popupOpen end,
        Open = function(key)
            popupKey, popupOpen = key, true
            return true
        end,
    },
    Focus = { GetSelection = function() return popupKey end },
    Movers = { Get = function() return {} end },
}
assert(M.ReconcileGuidedEditModePopup({ id = "group_edit_mode" }) == true,
    "already-open Party popup was not reconciled")
assert(state.preferences.groupEditModePopupOpened == true,
    "already-open Party popup did not complete its requirement")

state.preferences.groupEditModePopupOpened = nil
popupOpen, popupKey = false, nil
local opened, openedReason = M.RunGuidedTourStep("next")
assert(opened == true and openedReason == "guided_group_edit_mode_popup_opened",
    "Open size popup action did not open the Party geometry popup")
assert(popupOpen == true and popupKey == "gf_party" and state.preferences.groupEditModePopupOpened == true,
    "Party geometry popup action did not acknowledge the live popup")

print("PASS guided tour interaction: every normal step highlights and requires a new setting interaction")
