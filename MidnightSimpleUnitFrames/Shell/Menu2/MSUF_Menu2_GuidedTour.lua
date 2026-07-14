--- Menu-native MSUF 6.0 guided setup.
---
--- The guide walks native pages from a short section overview into every
--- registered control. It never copies settings into a second wizard and never
--- mutates a value when the user chooses Keep current/default or Skip.

local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local _G = _G
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min
local format = string.format
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local sort = table.sort

local function Tr(text)
    return type(M.Tr) == "function" and M.Tr(tostring(text or "")) or tostring(text or "")
end

local STAGES = {
    {
        id = "menu_basics", special = true, pageKey = "guided_setup", icon = "home",
        title = "Learn the MSUF menu",
        impact = "Skipping this personal step uses neutral guidance and leaves navigation, Search, autosave, Undo/Redo and page reset unexplained.",
    },
    {
        id = "edit_mode", special = true, pageKey = "guided_setup", icon = "uf_player",
        title = "Choose your anchor, then place frames",
        impact = "Skipping frame placement also skips the important choice between following the Cooldown Manager and independent Unitframe placement.",
    },
    { id = "uf_player", pageKey = "uf_player", icon = "uf_player", title = "Player frame", impact = "Skipping the Player frame leaves its layout, text, indicators and aura options unreviewed." },
    { id = "uf_target", pageKey = "uf_target", icon = "uf_target", title = "Target frame", impact = "Skipping the Target frame leaves its layout, text, indicators and aura options unreviewed." },
    { id = "uf_focus", pageKey = "uf_focus", icon = "uf_focus", title = "Focus frame", impact = "Skipping the Focus frame leaves its layout, text, indicators and aura options unreviewed." },
    { id = "uf_pet", pageKey = "uf_pet", icon = "uf_pet", title = "Pet frame", impact = "Skipping the Pet frame leaves its layout, text, indicators and aura options unreviewed." },
    { id = "uf_targettarget", pageKey = "uf_targettarget", icon = "uf_targettarget", title = "Target of target", impact = "Skipping Target of target leaves its layout, text and visibility options unreviewed." },
    { id = "uf_focustarget", pageKey = "uf_focustarget", icon = "uf_focustarget", title = "Focus target", impact = "Skipping Focus target leaves its layout, text and visibility options unreviewed." },
    { id = "uf_boss", pageKey = "uf_boss", icon = "uf_boss", title = "Boss frames", impact = "Skipping Boss frames leaves their shared layout, text, indicators and aura options unreviewed." },
    { id = "gf_layout", pageKey = "gf_layout", icon = "gf_layout", title = "Party and raid layout", impact = "Skipping group layout leaves frame size, growth, sorting, scaling and anchoring unreviewed." },
    { id = "gf_bars", pageKey = "gf_bars", icon = "gf_bars", title = "Group health and text", impact = "Skipping group bars leaves health, power, text, range and dispel presentation unreviewed." },
    { id = "gf_indicators", pageKey = "gf_indicators", icon = "gf_indicators", title = "Group indicators", impact = "Skipping group indicators leaves status icons, targeted spells and corner indicators unreviewed." },
    { id = "gf_auras", pageKey = "gf_auras", icon = "gf_auras", title = "Group auras", excludeSections = { si = true }, impact = "Skipping group auras leaves group buff and debuff behavior unreviewed." },
    {
        id = "gf_spell_icons", pageKey = "gf_auras", icon = "gf_auras", title = "Spell Icons",
        includeSections = { si = true }, includeEphemeralControls = true,
        impact = "Skipping Spell Icons leaves spec selection, tracked spells, custom SpellIDs, icon placement, cooldowns and full-frame effects unreviewed.",
    },
    { id = "opt_bars", pageKey = "opt_bars", icon = "opt_bars", title = "Bars and textures", impact = "Skipping Bars leaves global textures, absorbs, outlines, highlights and power behavior unreviewed." },
    { id = "opt_castbar", pageKey = "opt_castbar", icon = "opt_castbar", title = "Cast bars", impact = "Skipping Cast Bars leaves cast appearance, text, empowered casts and interrupt cues unreviewed." },
    { id = "opt_colors", pageKey = "opt_colors", icon = "opt_colors", title = "Colors", impact = "Skipping Colors leaves frame, power, aura, class, text and castbar colors unreviewed." },
    { id = "opt_fonts", pageKey = "opt_fonts", icon = "opt_fonts", title = "Fonts and text", impact = "Skipping Fonts leaves the global font, text styling, colors and name shortening unreviewed." },
    { id = "auras3_styling", pageKey = "auras3_styling", icon = "auras3_styling", title = "Aura styling", impact = "Skipping Aura styling leaves buff/debuff size, cooldown, stacks, duration bars and ordering unreviewed." },
    { id = "opt_misc", pageKey = "opt_misc", icon = "opt_misc", title = "Menu and miscellaneous", impact = "Skipping Miscellaneous leaves language, menu behavior, startup, tooltips and Blizzard-frame integration unreviewed." },
    { id = "classpower", pageKey = "classpower", icon = "classpower", title = "Class resources", impact = "Skipping Class Resources leaves class layout, behavior, style, visibility and alternative power displays unreviewed." },
    { id = "gameplay", pageKey = "gameplay", icon = "gameplay", title = "Gameplay features", impact = "Skipping Gameplay leaves combat timers, state behavior, class toggles and the combat crosshair unreviewed." },
    { id = "modules", pageKey = "modules", icon = "modules", title = "Modules and style", impact = "Skipping Modules leaves the optional MSUF Style module and its visual behavior unreviewed." },
    { id = "profiles", pageKey = "profiles", icon = "profiles", title = "Profiles and backup", impact = "Skipping Profiles leaves profile management, specialization assignment and export/import backup unreviewed." },
    {
        id = "final_review", special = true, pageKey = "guided_setup", icon = "home",
        title = "Review your guided setup",
        impact = "Skipping the final review hides the summary, but does not change any setting.",
    },
}

local STAGE_BY_ID = {}
for i = 1, #STAGES do
    STAGES[i].index = i
    STAGE_BY_ID[STAGES[i].id] = STAGES[i]
end
M.guidedTourStageCount = #STAGES

local function StageIncludesSection(stage, sectionId)
    if type(stage) ~= "table" then return true end
    local included = stage.includeSections
    if type(included) == "table" and included[sectionId] ~= true then return false end
    local excluded = stage.excludeSections
    return type(excluded) ~= "table" or excluded[sectionId] ~= true
end
function M.IsGuidedTourSectionIncluded(stageId, sectionId)
    return StageIncludesSection(STAGE_BY_ID[tostring(stageId or "")], tostring(sectionId or ""))
end
function M.GuidedTourIncludesEphemeralControls(stageId)
    local stage = STAGE_BY_ID[tostring(stageId or "")]
    return type(stage) == "table" and stage.includeEphemeralControls == true
end

local Runtime = M._guidedTourRuntime or {}
M._guidedTourRuntime = Runtime

local function Tour()
    return type(MSUF.GuidedTour6) == "table" and MSUF.GuidedTour6 or nil
end

local function FirstLoad()
    return type(MSUF.FirstLoad6) == "table" and MSUF.FirstLoad6 or nil
end

local function Invoke(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return false end
    local ok, a, b, c = pcall(fn, object, ...)
    if not ok then return false end
    return a ~= false, a, b, c
end

local function TourIsActive()
    local ok, active = Invoke(Tour(), "IsActive")
    return ok and active == true
end

local function TourState()
    local ok, state = Invoke(Tour(), "GetState")
    return ok and type(state) == "table" and state or {}
end

local function CurrentStage()
    local state = TourState()
    local stage = STAGE_BY_ID[tostring(state.currentStageId or "")]
    if not stage then stage = STAGES[min(max(tonumber(state.currentStageIndex) or 1, 1), #STAGES)] end
    return stage or STAGES[1]
end

local function ActiveProfileName()
    local profile = tostring(_G.MSUF_ActiveProfile or "Default")
    return profile ~= "" and profile or "Default"
end

local function ProfileMismatch()
    local state = TourState()
    local tourProfile = tostring(state.profileName or "")
    local activeProfile = ActiveProfileName()
    return tourProfile ~= "" and tourProfile ~= activeProfile, tourProfile, activeProfile
end

local function PlayerDisplayName()
    local name
    if type(_G.UnitName) == "function" then
        local ok, value = pcall(_G.UnitName, "player")
        if ok then name = value end
    end
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(name) then name = nil end
    if type(name) == "string" then name = name:match("^[^-]+") else name = nil end
    if not name or name == "" or name == "Unknown" then name = Tr("Player") end
    return name
end

local function Preference(key, fallback)
    local ok, value = Invoke(Tour(), "GetPreference", key)
    if not ok or value == nil or value == "" then return fallback end
    return value
end

local function PersonalQuestionsComplete()
    return Preference("playstyle") ~= nil and Preference("informationStyle") ~= nil
end

local COOLDOWN_ANCHOR_PREFERENCE = "unitframeCooldownAnchor"
local EDIT_MODE_MOVED_PREFERENCE = "editModeMoved"
local EDIT_MODE_MOVED_KEY_PREFERENCE = "editModeMovedKey"
local VALID_COOLDOWN_ANCHOR_DECISION = { cooldown = true, independent = true }
local function CooldownAnchorDecision()
    local value = Preference(COOLDOWN_ANCHOR_PREFERENCE)
    return VALID_COOLDOWN_ANCHOR_DECISION[value] and value or nil
end
local function CooldownAnchorDecisionComplete()
    return CooldownAnchorDecision() ~= nil
end
local function EditModePlacementComplete()
    local ok, complete = Invoke(Tour(), "IsEditModePlacementComplete")
    if ok then return complete == true end
    return Preference(EDIT_MODE_MOVED_PREFERENCE) == true
end
M.GetGuidedCooldownAnchorDecision = CooldownAnchorDecision
M.IsGuidedEditModePlacementUnlocked = CooldownAnchorDecisionComplete
M.IsGuidedEditModePlacementComplete = EditModePlacementComplete

local PREFERENCE_LABELS = {
    general = "General play",
    solo = "Solo and world",
    dungeons = "Dungeons",
    raid = "Raid and Mythic",
    calm = "Clean and calm",
    balanced = "Balanced",
    detailed = "Full combat detail",
}

local function PreferenceLabel(value)
    return Tr(PREFERENCE_LABELS[value] or "Balanced")
end

local function PersonalizedTitle(stage)
    if stage.id == "menu_basics" then return format(Tr("Welcome, %s"), PlayerDisplayName()) end
    if stage.id == "final_review" then return format(Tr("%s, your setup is ready"), PlayerDisplayName()) end
    return Tr(stage.title)
end

local function ControlIsAction(control)
    return control and (control.classification == "action" or control.kind == "button")
end

local function StageCue(stage, position)
    local section = position and position.section
    local control = position and position.control
    if control then
        local label = Tr(control.label)
        local help = tostring(control.help or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if help ~= "" then
            return format(Tr("The green arrow points to %s: %s"), label, Tr(help))
        end
        if ControlIsAction(control) then
            return format(Tr("The green arrow points to %s; use this action now or keep it untouched and continue."), label)
        end
        return format(Tr("The green arrow points to %s; adjust this option live, keep its current/default value, or skip it."), label)
    end
    local sectionId = section and (tostring(section.id or "") .. " " .. tostring(section.label or "")):lower() or ""
    if section then
        if sectionId:find("preview", 1, true) then
            if stage.id == "opt_bars" then
                return Tr("Sample = visual only · real changes = Unit/Group Preview · frame placement = MSUF Edit Mode")
            end
            if stage.id == "opt_castbar" then
                return Tr("Normal/Channel/Empowered = simulation · Interrupt = feedback · handles = saved position")
            end
            if stage.id == "auras3_styling" or stage.id == "gf_auras" then
                return Tr("Live/Dummy = display only · colored aura handles = saved positions")
            end
            if stage.id:match("^gf_") then
                return Tr("Scope = Party/Raid/Mythic · drag = inner position · Shift-layer = isolate · Ctrl-wheel/drag = zoom/pan · Edit Mode = container")
            end
            if stage.id == "classpower" then
                return Tr("Preview controls = inspect layouts and states · MSUF Edit Mode = whole-frame placement")
            end
            return Tr("Drag = inner position · gear/double-click = options · right-click = actions · Ctrl-wheel/drag = zoom/pan · Edit Mode = whole frame")
        end
        return format(Tr("%s is highlighted. Adjust it live, keep it as is, or continue."), Tr(section.label))
    end
    if stage.id == "menu_basics" then
        if PersonalQuestionsComplete() then
            return format(Tr("Your focus: %s, with %s information."), PreferenceLabel(Preference("playstyle", "dungeons")), PreferenceLabel(Preference("informationStyle", "balanced")))
        end
        return Tr("Choose one answer in each row. You can skip this personal step at any time.")
    end
    if stage.id == "edit_mode" then
        local decision = CooldownAnchorDecision()
        if decision and EditModePlacementComplete() then
            return Tr("Frame moved: placement is complete. Exit MSUF Edit Mode when you are happy, then continue.")
        end
        if decision == "cooldown" then
            return Tr("Anchor chosen: Unitframes follow Main Cooldowns. Open MSUF Edit Mode and drag the highlighted frame once to continue.")
        end
        if decision == "independent" then
            return Tr("Anchor chosen: Unitframes stay independent of Main Cooldowns. Open MSUF Edit Mode and drag the highlighted frame once to continue.")
        end
        return Tr("Before moving any frame, choose whether all Unitframes should follow Main Cooldowns or use independent placement.")
    end
    if stage.id:match("^uf_") then return Tr("Start with Preview, then follow each highlighted frame section.") end
    if stage.id == "gf_spell_icons" then
        return Tr("Configure Spell Icons completely: choose the scope and spec, select or add a spell, then review its icon, cooldown and frame effects.")
    end
    if stage.id:match("^gf_") then
        local playstyle = Preference("playstyle", "general")
        if playstyle == "raid" then return Tr("Raid focus: compare Raid and Mythic scopes before reviewing each highlighted section.") end
        if playstyle == "solo" then return Tr("Solo focus: keep group defaults or prepare the Party scope for occasional groups.") end
        if playstyle == "dungeons" then return Tr("Dungeon focus: begin with Party or Mythic scope, then review each highlighted section.") end
        return Tr("Compare the Party, Raid or Mythic scope that matters to you, then follow the highlights.")
    end
    if stage.id == "opt_bars" then return Tr("Sample = visual only · tests = temporary · scope = shared/unit/group") end
    if stage.id == "opt_castbar" then return Tr("Simulate casts here; position castbar handles in Preview or MSUF Edit Mode.") end
    if stage.id == "opt_fonts" then return Tr("Use the scope selector for shared, unit and group text; compare readability in Preview.") end
    if stage.id == "auras3_styling" then return Tr("Live/Dummy = display only · colored handles = saved positions · scope = shared/unit/group/custom") end
    if stage.id == "classpower" then return Tr("Use the interactive preview for layouts and states; use Edit Mode for whole-frame placement.") end
    if stage.id == "profiles" then return Tr("Finish with a profile check and export a backup of your setup.") end
    if stage.id == "final_review" then return Tr("Review your choices and skipped areas. Finish adds no extra setting changes.") end
    local informationStyle = Preference("informationStyle", "balanced")
    if informationStyle == "calm" then return Tr("Clarity focus: prefer the simplest readable option in each highlighted section.") end
    if informationStyle == "detailed" then return Tr("Combat-detail focus: inspect indicators, timers and visibility in each highlighted section.") end
    return Tr("Review the highlighted sections; previews update while your changes autosave.")
end

local function BlockedByCombat()
    return type(M.BlockCombatAction) == "function" and M.BlockCombatAction() == true
end

local function SetGuidedCooldownAnchorDecision(value)
    if not VALID_COOLDOWN_ANCHOR_DECISION[value] or BlockedByCombat() then return false end
    local previousDecision = CooldownAnchorDecision()
    local enabled = value == "cooldown"
    local general = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or nil
    if type(general) ~= "table" then
        local db = _G.MSUF_DB
        if type(db) ~= "table" then return false end
        db.general = type(db.general) == "table" and db.general or {}
        general = db.general
    end
    if general.anchorToCooldown ~= enabled then
        if type(M.SetGeneralValue) == "function" then
            if M.SetGeneralValue("anchorToCooldown", enabled, "MSUF2_GUIDED_COOLDOWN_ANCHOR") == false then return false end
        else
            general.anchorToCooldown = enabled
        end
    end
    local stored = Invoke(Tour(), "SetPreference", COOLDOWN_ANCHOR_PREFERENCE, value)
    if not stored then return false end
    if previousDecision ~= value then
        Invoke(Tour(), "SetPreference", EDIT_MODE_MOVED_PREFERENCE, nil)
        Invoke(Tour(), "SetPreference", EDIT_MODE_MOVED_KEY_PREFERENCE, nil)
    end
    local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if type(apply) == "table" and type(apply.Flush) == "function" then apply.Flush() end
    return true
end
M.SetGuidedCooldownAnchorDecision = SetGuidedCooldownAnchorDecision

local function RefreshEditModePlacementCue()
    local editMode = _G.MSUF_EM2
    local movers = editMode and editMode.Movers
    if movers and type(movers.RefreshGuidedPlacementCue) == "function" then
        movers.RefreshGuidedPlacementCue()
    end
end

local function ShouldShowEditModeOpenCue()
    if not TourIsActive() or CurrentStage().id ~= "edit_mode" then return false end
    if not CooldownAnchorDecisionComplete() or EditModePlacementComplete() then return false end
    local status = type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {}
    return status.active ~= true and status.combatLocked ~= true
end
M.ShouldShowGuidedEditModeOpenCue = ShouldShowEditModeOpenCue

local function RefreshEditModeOpenCue(show)
    local T = M.Theme
    local button = M.dashboardToolbarEditModeButton
    local cue = Runtime.editModeOpenCue
    show = show == true and button ~= nil and T ~= nil
    if not show then
        if cue then cue:Hide() end
        Runtime.editModeOpenCueVisible = nil
        return
    end
    if not cue or cue:GetParent() ~= button then
        if cue then cue:Hide() end
        cue = CreateFrame("Frame", nil, button)
        cue:SetAllPoints(button)
        cue:EnableMouse(false)
        cue:SetFrameLevel((button:GetFrameLevel() or 1) + 12)
        local color = T.colors.ok or { 0.24, 0.82, 0.46, 1 }
        local function Arrow(point, rotation)
            local texture = cue:CreateTexture(nil, "OVERLAY", nil, 7)
            local usedAtlas = texture.SetAtlas and pcall(texture.SetAtlas, texture, "NPE_ArrowRight", false)
            if not usedAtlas and T.media then texture:SetTexture(T.media.collapseArrow) end
            texture:SetSize(20, 20)
            texture:SetPoint(point, cue, point, point == "LEFT" and 3 or -3, 0)
            if rotation and texture.SetRotation then texture:SetRotation(rotation) end
            texture:SetVertexColor(color[1], color[2], color[3], 1)
            return texture
        end
        cue._leftArrow = Arrow("LEFT")
        cue._rightArrow = Arrow("RIGHT", math.pi)
        Runtime.editModeOpenCue = cue
    end
    cue:Show()
    if not Runtime.editModeOpenCueVisible then
        Runtime.editModeOpenCueVisible = true
        if type(T.PlayMotion) == "function" then
            T.PlayMotion(cue, "controlFocusIn", { fromAlpha = 0.30, toAlpha = 1, duration = 0.18 })
        end
        if type(T.PlayNeonFlash) == "function" then
            T.PlayNeonFlash(button, "success", { alpha = 0.28, duration = 0.80 })
        end
    end
end

function M.NotifyGuidedEditModeMoved(moverKey)
    local ok, marked = Invoke(Tour(), "MarkEditModePlacementComplete", moverKey)
    if not ok or marked ~= true then return false end
    RefreshEditModePlacementCue()
    if M.activeKey == "guided_setup" and type(M.RequestRefresh) == "function" then
        M.RequestRefresh(nil, "GUIDED_EDIT_MODE_MOVED")
    end
    if type(M.RefreshGuidedTourChrome) == "function" then
        M.RefreshGuidedTourChrome("EDIT_MODE_MOVED")
    end
    return true
end

local function ExpectedPage(stage)
    stage = stage or CurrentStage()
    return stage.special and "guided_setup" or stage.pageKey
end

local function SafeText(fontString)
    if type(fontString) == "string" then return fontString end
    if not (fontString and type(fontString.GetText) == "function") then return "" end
    local ok, value = pcall(fontString.GetText, fontString)
    value = ok and tostring(value or "") or ""
    return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function FrameTop(frame)
    if not (frame and type(frame.GetTop) == "function") then return nil end
    local ok, value = pcall(frame.GetTop, frame)
    return ok and tonumber(value) or nil
end

local function FrameLeft(frame)
    if not (frame and type(frame.GetLeft) == "function") then return nil end
    local ok, value = pcall(frame.GetLeft, frame)
    return ok and tonumber(value) or nil
end

local IsWidgetInside

local function SortedSections(pageKey)
    local entry = M.cache and M.cache[pageKey]
    local source = entry and entry.sections
    local sections = {}
    if type(source) == "table" then
        for sectionId, body in pairs(source) do
            local collapsible = body and body._msuf2CollapsibleEntry
            if collapsible then
                local label = SafeText(collapsible.label)
                if label == "" then label = tostring(sectionId or "Section") end
                sections[#sections + 1] = {
                    id = tostring(sectionId or ""),
                    body = body,
                    outer = collapsible.outer,
                    entry = collapsible,
                    label = label,
                    top = FrameTop(collapsible.outer),
                    guidedOrder = tonumber(collapsible.guidedOrder),
                    collapsible = true,
                }
            end
        end
    end
    local regions = entry and entry.guidedRegions
    if type(regions) == "table" then
        for regionId, region in pairs(regions) do
            local body = type(region) == "table" and (region.body or region.outer) or nil
            local outer = type(region) == "table" and (region.outer or body) or nil
            if body and outer then
                local label = SafeText(region.label)
                if label == "" then label = SafeText(body.title) end
                if label == "" then label = "Scope and overrides" end
                sections[#sections + 1] = {
                    id = "region:" .. tostring(region.id or regionId or ""),
                    body = body,
                    outer = outer,
                    entry = region,
                    label = label,
                    top = FrameTop(outer),
                    guidedOrder = tonumber(region.guidedOrder),
                    region = true,
                }
            end
        end
    end
    sort(sections, function(a, b)
        if a.guidedOrder ~= b.guidedOrder then
            if a.guidedOrder == nil then return false end
            if b.guidedOrder == nil then return true end
            return a.guidedOrder < b.guidedOrder
        end
        if a.top ~= b.top then
            if a.top == nil then return false end
            if b.top == nil then return true end
            return a.top > b.top
        end
        return a.id < b.id
    end)
    return sections
end

local function StageSections(stage)
    local sections = SortedSections(stage and stage.pageKey)
    if type(stage) ~= "table" then return sections end
    local filtered = {}
    for i = 1, #sections do
        local section = sections[i]
        if StageIncludesSection(stage, section.id) then filtered[#filtered + 1] = section end
    end
    return filtered
end

local function ClearControlEmphasis()
    Runtime.controlEmphasisSignature = nil
    Runtime.controlEmphasisWidget = nil
    local emphasized = Runtime.controlEmphasis
    if type(emphasized) ~= "table" then return end
    for i = 1, #emphasized do
        local item = emphasized[i]
        local widget = item and item.widget
        if widget and type(widget.SetAlpha) == "function" and item.originalAlpha ~= nil then
            local current = type(widget.GetAlpha) == "function" and widget:GetAlpha() or item.appliedAlpha
            if current == nil or item.appliedAlpha == nil or math.abs(current - item.appliedAlpha) < 0.001 then
                widget:SetAlpha(item.originalAlpha)
            end
        end
        local marker = item and item.marker
        if marker then
            if M.Theme and type(M.Theme.StopMotion) == "function" then M.Theme.StopMotion(marker) end
            if type(marker.Hide) == "function" then marker:Hide() end
        end
    end
    Runtime.controlEmphasis = nil
end

local function ClearSectionEmphasis(pageKey)
    Runtime.emphasisSignature = nil
    ClearControlEmphasis()
    local cache = M.cache
    if type(cache) ~= "table" then return end
    for key in pairs(cache) do
        if pageKey == nil or key == pageKey then
            local sections = SortedSections(key)
            for i = 1, #sections do
                local section = sections[i]
                local outer = section.outer
                if outer and outer.SetAlpha and outer._msuf2GuidedOriginalAlpha ~= nil then
                    outer:SetAlpha(outer._msuf2GuidedOriginalAlpha)
                    outer._msuf2GuidedOriginalAlpha = nil
                end
                local flash = outer and outer._msuf2NeonFlash
                if flash then
                    if flash._msuf2FlashGroup and flash._msuf2FlashGroup.Stop then flash._msuf2FlashGroup:Stop() end
                    if flash.SetAlpha then flash:SetAlpha(0) end
                    if flash.Hide then flash:Hide() end
                end
                local marker = section.entry and section.entry._msuf2GuidedArrow
                if marker then
                    if M.Theme and type(M.Theme.StopMotion) == "function" then M.Theme.StopMotion(marker) end
                    marker:Hide()
                end
                local controlMarker = section.entry and section.entry._msuf2GuidedControlArrow
                if controlMarker then
                    if M.Theme and type(M.Theme.StopMotion) == "function" then M.Theme.StopMotion(controlMarker) end
                    controlMarker:Hide()
                end
            end
        end
    end
end

local function EmphasizeSection(pageKey, current, currentControl)
    local T = M.Theme
    local sections = SortedSections(pageKey)
    local signature = tostring(pageKey or "") .. "\031" .. tostring(current and current.id or "")
    local animate = Runtime.emphasisSignature ~= signature
    Runtime.emphasisSignature = signature
    for i = 1, #sections do
        local section = sections[i]
        local entry = section.entry
        local selected = current and section.id == current.id
        local outer = section.outer
        local related = selected
        if current and not related and outer and current.outer and IsWidgetInside then
            related = IsWidgetInside(current.outer, outer) or IsWidgetInside(outer, current.outer)
        end
        if outer and outer.SetAlpha then
            if outer._msuf2GuidedOriginalAlpha == nil then
                outer._msuf2GuidedOriginalAlpha = outer.GetAlpha and outer:GetAlpha() or 1
            end
            local original = outer._msuf2GuidedOriginalAlpha
            outer:SetAlpha(related and original or (original * 0.46))
        end
        local marker = entry._msuf2GuidedArrow
        if selected and not marker and outer and outer.CreateTexture and T and T.media then
            marker = outer:CreateTexture(nil, "OVERLAY", nil, 7)
            local usedAtlas = false
            if marker.SetAtlas then
                local ok = pcall(marker.SetAtlas, marker, "NPE_ArrowRight", false)
                usedAtlas = ok
            end
            if not usedAtlas then marker:SetTexture(T.media.collapseArrow) end
            marker:SetSize(20, 20)
            marker:SetPoint("RIGHT", outer, "LEFT", -4, 0)
            local color = T.colors.accent
            marker:SetVertexColor(color[1], color[2], color[3], 1)
            entry._msuf2GuidedArrow = marker
        end
        if marker then
            local showMarker = selected and not currentControl
            marker:SetShown(showMarker and true or false)
            if showMarker and animate and T and type(T.PlayMotion) == "function" then
                T.PlayMotion(marker, "controlFocusIn", { fromAlpha = 0.28, toAlpha = 1, duration = 0.16 })
            end
        end
    end
end

IsWidgetInside = function(widget, ancestor)
    local current = widget
    for _ = 1, 48 do
        if not current then return false end
        if current == ancestor then return true end
        if type(current.GetParent) ~= "function" then return false end
        local ok, parent = pcall(current.GetParent, current)
        if not ok or parent == current then return false end
        current = parent
    end
    return false
end

local function RuntimeControlRecords()
    local catalog = M.RuntimeControlCatalog
    if not (catalog and type(catalog.GetRecords) == "function") then return {} end
    local ok, records = pcall(catalog.GetRecords)
    return ok and type(records) == "table" and records or {}
end

local function GuidedWidgetIsActionable(widget)
    if not widget or widget._msuf2AppliedEnabled == false or widget._msuf2DesiredEnabled == false then return false end
    local function ObjectEnabled(object)
        if not object or type(object.IsEnabled) ~= "function" then return true end
        local ok, enabled = pcall(object.IsEnabled, object)
        return not ok or (enabled ~= false and enabled ~= 0)
    end
    if not ObjectEnabled(widget) then return false end
    if type(widget.buttons) == "table" and #widget.buttons > 0 then
        for i = 1, #widget.buttons do
            local button = widget.buttons[i]
            if button
                and button._msuf2AppliedEnabled ~= false
                and button._msuf2DesiredEnabled ~= false
                and ObjectEnabled(button)
            then
                return true
            end
        end
        return false
    end
    return true
end
M.IsGuidedTourWidgetActionable = GuidedWidgetIsActionable

local function SectionControls(pageKey, section, sections, records, includeEphemeral)
    local catalog = M.RuntimeControlCatalog
    if not (catalog and section and section.body) then return {} end
    records = type(records) == "table" and records or RuntimeControlRecords()
    sections = type(sections) == "table" and sections or SortedSections(pageKey)
    local controls, seen = {}, {}
    for i = 1, #records do
        local record = records[i]
        if type(record) == "table"
            and record.pageKey == pageKey
            and (record.classification == "setting" or record.classification == "action"
                or (includeEphemeral == true and record.classification == "ephemeral"))
            and type(record.controlId) == "string"
            and not seen[record.controlId]
        then
            local internal = type(catalog.Get) == "function" and catalog.Get(record.controlId) or nil
            local widget = internal and internal.widget
            local owner = GuidedWidgetIsActionable(widget) and IsWidgetInside(widget, section.body) and section or nil
            if owner then
                for j = 1, #sections do
                    local candidate = sections[j]
                    if candidate ~= owner
                        and candidate.body ~= owner.body
                        and IsWidgetInside(widget, candidate.body)
                        and IsWidgetInside(candidate.body, owner.body)
                    then
                        owner = candidate
                    end
                end
            end
            if owner == section then
                seen[record.controlId] = true
                controls[#controls + 1] = {
                    id = record.controlId,
                    label = tostring(record.label or record.identityLabel or record.controlId),
                    help = tostring(record.help or ""),
                    kind = tostring(record.kind or ""),
                    classification = tostring(record.classification or ""),
                    widget = widget,
                    top = FrameTop(widget),
                    left = FrameLeft(widget),
                }
            end
        end
    end
    sort(controls, function(a, b)
        if a.top ~= b.top then
            if a.top == nil then return false end
            if b.top == nil then return true end
            if math.abs(a.top - b.top) > 2 then return a.top > b.top end
        end
        if a.left ~= b.left then
            if a.left == nil then return false end
            if b.left == nil then return true end
            if math.abs(a.left - b.left) > 2 then return a.left < b.left end
        end
        local al, bl = a.label:lower(), b.label:lower()
        return al == bl and a.id < b.id or al < bl
    end)
    return controls
end

local function PageGuideModel(pageKey)
    local entry = M.cache and M.cache[pageKey]
    local cached = Runtime.controlModel
    if entry and cached and cached.pageKey == pageKey and cached.entry == entry then return cached end
    local sections = SortedSections(pageKey)
    local records = RuntimeControlRecords()
    local controlsBySection, allControls, seen = {}, {}, {}
    for i = 1, #sections do
        local list = SectionControls(pageKey, sections[i], sections, records)
        controlsBySection[sections[i].id] = list
        for j = 1, #list do
            local control = list[j]
            if not seen[control.id] then
                seen[control.id] = true
                allControls[#allControls + 1] = control
            end
        end
    end
    local model = {
        pageKey = pageKey,
        entry = entry,
        sections = sections,
        controlsBySection = controlsBySection,
        allControls = allControls,
    }
    if entry then Runtime.controlModel = model end
    return model
end

local function AllStageControls(stage)
    local sections = StageSections(stage)
    local records = RuntimeControlRecords()
    local controls, seen = {}, {}
    for i = 1, #sections do
        local list = SectionControls(stage.pageKey, sections[i], sections, records, stage.includeEphemeralControls)
        for j = 1, #list do
            local control = list[j]
            if not seen[control.id] then
                seen[control.id] = true
                controls[#controls + 1] = control
            end
        end
    end
    return controls
end

local function EmphasizeControl(stage, section, controls, current)
    if not (stage and section and current and current.widget) then
        ClearControlEmphasis()
        return
    end
    local signature = table.concat({ stage.id or "", section.id or "", current.id or "" }, "\031")
    if Runtime.controlEmphasisSignature == signature
        and Runtime.controlEmphasisWidget == current.widget
        and type(Runtime.controlEmphasis) == "table"
    then
        return
    end
    ClearControlEmphasis()
    Runtime.controlEmphasisSignature = signature
    Runtime.controlEmphasisWidget = current.widget
    Runtime.controlEmphasis = {}

    local selectedWidget = current.widget
    for i = 1, #controls do
        local control = controls[i]
        local widget = control.widget
        if widget and type(widget.SetAlpha) == "function" then
            local original = type(widget.GetAlpha) == "function" and widget:GetAlpha() or 1
            local related = control.id == current.id
                or IsWidgetInside(selectedWidget, widget)
                or IsWidgetInside(widget, selectedWidget)
            if not related then
                local applied = original * 0.38
                widget:SetAlpha(applied)
                Runtime.controlEmphasis[#Runtime.controlEmphasis + 1] = {
                    widget = widget,
                    originalAlpha = original,
                    appliedAlpha = applied,
                }
            end
        end
    end

    local T = M.Theme
    if type(CreateFrame) == "function" and T then
        local marker = Runtime.controlMarker
        if not marker then
            marker = CreateFrame("Frame", nil, selectedWidget)
            marker:SetSize(20, 20)
            local texture = marker:CreateTexture(nil, "OVERLAY", nil, 7)
            texture:SetAllPoints()
            local usedAtlas = false
            if type(texture.SetAtlas) == "function" then
                usedAtlas = pcall(texture.SetAtlas, texture, "NPE_ArrowRight", false)
            end
            if not usedAtlas and T.media then texture:SetTexture(T.media.collapseArrow) end
            marker._msuf2Texture = texture
            Runtime.controlMarker = marker
        else
            marker:SetParent(selectedWidget)
        end
        marker:ClearAllPoints()
        marker:SetPoint("RIGHT", selectedWidget, "LEFT", -4, 0)
        if type(marker.SetFrameLevel) == "function" and type(selectedWidget.GetFrameLevel) == "function" then
            marker:SetFrameLevel(selectedWidget:GetFrameLevel() + 8)
        end
        local color = T.colors and T.colors.accent
        local texture = marker._msuf2Texture
        if color and texture then texture:SetVertexColor(color[1], color[2], color[3], 1) end
        marker:Show()
        Runtime.controlEmphasis[#Runtime.controlEmphasis + 1] = { marker = marker }
        if type(T.PlayMotion) == "function" then
            T.PlayMotion(marker, "controlFocusIn", { fromAlpha = 0.28, toAlpha = 1, duration = 0.16 })
        end
    end
    if T and type(T.PlayNeonFlash) == "function" and type(selectedWidget.CreateTexture) == "function" then
        T.PlayNeonFlash(selectedWidget, "success", { alpha = 0.24, duration = 0.72 })
    end
end

local function ResultName(code)
    if code == "s" or code == "skipped" then return "skipped" end
    if code == "k" or code == "kept" then return "kept" end
    return "reviewed"
end

local function RecordControl(stage, section, control, result)
    if not control then return false end
    return Invoke(Tour(), "RecordControl", stage.id, control.id, ResultName(result), {
        pageKey = stage.pageKey,
        sectionId = section.id,
        label = control.label,
        help = control.help,
    })
end

local function RecordControls(stage, section, controls, result)
    controls = type(controls) == "table" and controls or {}
    for i = 1, #controls do RecordControl(stage, section, controls[i], result) end
    return #controls
end

local function RecordSectionOnly(stage, section, result)
    result = ResultName(result)
    Invoke(Tour(), "RecordSection", stage.id, section.id, result, {
        pageKey = stage.pageKey,
        label = section.label,
    })
end

local function RecordSectionAndControls(stage, section, result, sections, records)
    records = type(records) == "table" and records or RuntimeControlRecords()
    local controls = SectionControls(stage.pageKey, section, sections, records, stage.includeEphemeralControls)
    RecordControls(stage, section, controls, result)
    RecordSectionOnly(stage, section, result)
    return #controls
end

local function DerivedSectionResult(stage, controls, fallback)
    local state = TourState()
    local byStage = type(state.controlResults) == "table" and state.controlResults[stage.id] or nil
    byStage = type(byStage) == "table" and byStage or {}
    local found, allKept, allSkipped = 0, true, true
    for i = 1, #controls do
        local code = byStage[controls[i].id]
        if code then
            found = found + 1
            if code ~= "k" then allKept = false end
            if code ~= "s" then allSkipped = false end
        else
            allKept = false
            allSkipped = false
        end
    end
    if #controls > 0 and found == #controls and allSkipped then return "skipped" end
    if #controls > 0 and found == #controls and allKept then return "kept" end
    if found > 0 then return "reviewed" end
    return ResultName(fallback)
end

local function DerivedStageResult(stage, sections, fallback)
    local state = TourState()
    local results = type(state.sectionResults) == "table" and state.sectionResults or {}
    local found, allKept, allSkipped = 0, true, true
    for i = 1, #sections do
        local code = results[stage.id .. "\031" .. sections[i].id]
        if code then
            found = found + 1
            if code ~= "k" then allKept = false end
            if code ~= "s" then allSkipped = false end
        else
            allKept = false
            allSkipped = false
        end
    end
    if found > 0 and found == #sections and allSkipped then return "skipped" end
    if found > 0 and found == #sections and allKept then return "kept" end
    if found > 0 then return "reviewed" end
    return ResultName(fallback)
end

local function RecordWholeStage(stage, sections, result)
    result = ResultName(result)
    sections = sections or {}
    for i = 1, #sections do RecordSectionAndControls(stage, sections[i], result, sections) end
    Invoke(Tour(), "RecordStage", stage.id, result)
end

local function ReadCursor(stage)
    local ok, cursor = Invoke(Tour(), "GetCursor", stage.id)
    cursor = ok and type(cursor) == "table" and cursor or nil
    if not cursor then
        return { overview = true, sectionIndex = 0, controlIndex = 0, controlTotal = 0 }
    end
    return {
        overview = cursor.overview ~= false,
        sectionId = type(cursor.sectionId) == "string" and cursor.sectionId or nil,
        sectionIndex = max(0, tonumber(cursor.sectionIndex) or 0),
        controlId = type(cursor.controlId) == "string" and cursor.controlId or nil,
        controlIndex = max(0, tonumber(cursor.controlIndex) or 0),
        controlTotal = max(0, tonumber(cursor.controlTotal) or 0),
    }
end

local function WriteCursor(stage, cursor)
    return Invoke(Tour(), "SetCursor", stage.id, cursor)
end

local function FindCursorSection(cursor, sections)
    if cursor.overview ~= false then return nil, 0 end
    if cursor.sectionId then
        for i = 1, #sections do
            if sections[i].id == cursor.sectionId then return sections[i], i end
        end
    end
    local index = min(max(tonumber(cursor.sectionIndex) or 1, 1), #sections)
    return sections[index], index
end

local function FindCursorControl(cursor, controls)
    if not cursor or (not cursor.controlId and (tonumber(cursor.controlIndex) or 0) < 1) then return nil, 0 end
    if cursor.controlId then
        for i = 1, #controls do
            if controls[i].id == cursor.controlId then return controls[i], i end
        end
    end
    if #controls == 0 then return nil, 0 end
    local index = min(max(tonumber(cursor.controlIndex) or 1, 1), #controls)
    return controls[index], index
end

local function FocusGuidedWidget(widget, fallback, flash)
    local outer = widget or fallback
    local scroll = M.scrollFrame
    local child = M.scrollChild
    Runtime.focusRequest = (tonumber(Runtime.focusRequest) or 0) + 1
    local request = Runtime.focusRequest
    local function FinishFocus(pass)
        if request ~= Runtime.focusRequest then return end
        if type(M.RefreshPinnedPreviews) == "function" then M.RefreshPinnedPreviews(scroll) end
        if outer and scroll and child
            and outer.GetTop and scroll.GetTop and scroll.GetBottom
            and scroll.GetVerticalScroll and scroll.SetVerticalScroll
        then
            local outerTop = outer:GetTop()
            local scrollTop, scrollBottom = scroll:GetTop(), scroll:GetBottom()
            if outerTop and scrollTop and scrollBottom then
                local visibleTop = scrollTop
                local activePreview = scroll._msuf2PinnedPreviewActiveRecord
                local preview = activePreview and activePreview.box
                local targetInsidePreview = preview and IsWidgetInside(outer, preview)
                if preview and preview._msuf2PinnedFloating == true
                    and (not preview.IsShown or preview:IsShown())
                    and preview.GetBottom
                then
                    local previewBottom = preview:GetBottom()
                    if previewBottom and previewBottom < visibleTop and previewBottom > scrollBottom then
                        visibleTop = previewBottom
                    end
                end
                if not targetInsidePreview then
                    -- Leave enough room above a control to keep its section
                    -- heading visible; section-only steps can sit nearer the top.
                    local topInset = widget and 52 or 16
                    local desiredTop = max(scrollBottom + 32, visibleTop - topInset)
                    local current = tonumber(scroll:GetVerticalScroll()) or 0
                    local childHeight = tonumber(child.GetHeight and child:GetHeight()) or 0
                    local scrollHeight = tonumber(scroll.GetHeight and scroll:GetHeight()) or 0
                    local maxScroll = max(0, childHeight - scrollHeight)
                    local target = min(max(current + (desiredTop - outerTop), 0), maxScroll)
                    if math.abs(target - current) >= 1 then scroll:SetVerticalScroll(floor(target + 0.5)) end
                end
                if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
            end
        end
        local T = M.Theme
        if pass == 1 and flash and outer and T and type(T.PlayNeonFlash) == "function" and type(outer.CreateTexture) == "function" then
            T.PlayNeonFlash(outer, "success", { alpha = 0.24, duration = 0.72 })
        end
        -- The first scroll can activate or resize a pinned Preview. Re-run on
        -- the settled geometry so the target lands below that overlay.
        if pass == 1 and C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function() FinishFocus(2) end)
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function() FinishFocus(1) end)
    else
        FinishFocus(1)
        FinishFocus(2)
    end
end

local function FocusCurrentSection(stage)
    if stage.special then return end
    local cursor = ReadCursor(stage)
    if cursor.overview ~= false then
        if type(M.CloseAutoFocusedSections) == "function" then M.CloseAutoFocusedSections(stage.pageKey) end
        ClearSectionEmphasis(stage.pageKey)
        return
    end
    local sections = StageSections(stage)
    local section, index = FindCursorSection(cursor, sections)
    if not section then
        WriteCursor(stage, { overview = true, sectionIndex = 0, controlIndex = 0, controlTotal = 0 })
        return
    end
    local controls = SectionControls(stage.pageKey, section, sections, nil, stage.includeEphemeralControls)
    local control, controlIndex = FindCursorControl(cursor, controls)
    if cursor.sectionId ~= section.id
        or cursor.sectionIndex ~= index
        or cursor.controlId ~= (control and control.id or nil)
        or cursor.controlIndex ~= controlIndex
        or cursor.controlTotal ~= #controls
    then
        WriteCursor(stage, {
            overview = false,
            sectionId = section.id,
            sectionIndex = index,
            controlId = control and control.id or nil,
            controlIndex = controlIndex,
            controlTotal = #controls,
        })
    end
    local W = M.Widgets
    if type(M.CloseAutoFocusedSections) == "function" then M.CloseAutoFocusedSections(stage.pageKey) end
    if W and type(W.FocusCollapsibleSection) == "function" then
        for i = 1, #sections do
            local ancestor = sections[i]
            if ancestor.collapsible
                and ancestor.id ~= section.id
                and section.outer
                and IsWidgetInside(section.outer, ancestor.body)
            then
                W.FocusCollapsibleSection(ancestor.body, { persist = false, flash = false })
            end
        end
        if section.collapsible then
            W.FocusCollapsibleSection(section.body, { persist = false, flash = true })
        else
            FocusGuidedWidget(section.outer, nil, true)
        end
    end
    if control then FocusGuidedWidget(control.widget, section.outer, false) end
    EmphasizeSection(stage.pageKey, section, control)
    EmphasizeControl(stage, section, controls, control)
end

local function InvalidateGuidedPage()
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("guided_setup") end
end

local function SelectExpectedPage(stage)
    local pageKey = ExpectedPage(stage)
    Runtime.manualAway = nil
    Runtime.warning = nil
    if stage.special then InvalidateGuidedPage() end
    if M.frame and type(M.frame.IsShown) == "function" and M.frame:IsShown() then
        -- Consecutive special stages share the guided_setup page key, but each
        -- stage builds different page content. Invalidation removes the cached
        -- wrapper, so only use the same-page refresh path while that wrapper
        -- still exists; otherwise SelectPage must rebuild it immediately.
        if M.activeKey == pageKey and M.cache and M.cache[pageKey] then
            if type(M.RefreshGuidedTourChrome) == "function" then M.RefreshGuidedTourChrome("SAME_PAGE_STAGE") end
            return true
        end
        if type(M.SelectPage) == "function" then return M.SelectPage(pageKey) end
    elseif type(M.Open) == "function" then
        return M.Open(pageKey)
    elseif type(M.SelectPage) == "function" then
        return M.SelectPage(pageKey)
    end
    return false
end

local function SetStage(stage, resetCursor)
    if not stage then return false end
    ClearSectionEmphasis()
    Invoke(Tour(), "SetStage", stage.id, stage.index)
    if resetCursor or not select(2, Invoke(Tour(), "GetCursor", stage.id)) then
        WriteCursor(stage, { overview = true, sectionIndex = 0, controlIndex = 0, controlTotal = 0 })
    end
    return SelectExpectedPage(stage)
end

local function CompleteTour()
    ClearSectionEmphasis()
    Invoke(Tour(), "Complete")
    Invoke(FirstLoad(), "Complete", "guided_tour")
    Runtime.warning = nil
    Runtime.manualAway = nil
    Runtime.lastVisualSignature = nil
    M.RefreshGuidedTourChrome("COMPLETE")
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    if type(M.SelectPage) == "function" then M.SelectPage("home") end
    return true
end

local function AdvanceStage(stage, resetCursor)
    if stage.index >= #STAGES then return CompleteTour() end
    return SetStage(STAGES[stage.index + 1], resetCursor ~= false)
end

local function ReturnToPreviousStage(stage)
    if stage.index <= 1 then return false end
    local previous = STAGES[stage.index - 1]
    ClearSectionEmphasis()
    Invoke(Tour(), "SetStage", previous.id, previous.index)
    return SelectExpectedPage(previous)
end

local function CurrentPosition(stage)
    if stage.special then return { overview = true, sections = {}, index = 0 } end
    local sections = StageSections(stage)
    local cursor = ReadCursor(stage)
    local section, index = FindCursorSection(cursor, sections)
    if not section then cursor.overview = true end
    local controls = section and SectionControls(stage.pageKey, section, sections, nil, stage.includeEphemeralControls) or {}
    local control, controlIndex = FindCursorControl(cursor, controls)
    return {
        overview = cursor.overview ~= false,
        cursor = cursor,
        sections = sections,
        section = section,
        index = index,
        controls = controls,
        control = control,
        controlIndex = controlIndex,
    }
end

local function KeepLabel(stage, position)
    if stage.special then return "Keep as is" end
    if position.overview then return "Keep current" end
    if ControlIsAction(position.control) then return "Keep action" end
    if position.control then return "Keep option" end
    return "Keep section"
end

local function SetSectionCursor(stage, sections, sectionIndex, controlIndex, reason)
    local section = sections[sectionIndex]
    if not section then return false end
    local controls = SectionControls(stage.pageKey, section, sections, nil, stage.includeEphemeralControls)
    controlIndex = min(max(tonumber(controlIndex) or 0, 0), #controls)
    local control = controlIndex > 0 and controls[controlIndex] or nil
    WriteCursor(stage, {
        overview = false,
        sectionId = section.id,
        sectionIndex = sectionIndex,
        controlId = control and control.id or nil,
        controlIndex = control and controlIndex or 0,
        controlTotal = #controls,
    })
    FocusCurrentSection(stage)
    M.RefreshGuidedTourChrome(reason or "GUIDED_POSITION")
    return true
end

local function AdvanceCurrent(result)
    if ProfileMismatch() then return false end
    local stage = CurrentStage()
    local position = CurrentPosition(stage)
    result = ResultName(result)

    if stage.id == "final_review" then return CompleteTour() end
    if stage.special then
        Invoke(Tour(), "RecordStage", stage.id, result)
        return AdvanceStage(stage, true)
    end
    if position.overview then
        if result == "reviewed" and #position.sections > 0 then
            return SetSectionCursor(stage, position.sections, 1, 0, "FIRST_SECTION")
        end
        RecordWholeStage(stage, position.sections, result)
        return AdvanceStage(stage, true)
    end

    if not position.control then
        if result == "reviewed" and #position.controls > 0 then
            return SetSectionCursor(stage, position.sections, position.index, 1, "FIRST_CONTROL")
        end
        if result == "reviewed" then
            RecordSectionOnly(stage, position.section, result)
        else
            RecordSectionAndControls(stage, position.section, result, position.sections)
        end
    else
        RecordControl(stage, position.section, position.control, result)
        if position.controlIndex < #position.controls then
            return SetSectionCursor(stage, position.sections, position.index, position.controlIndex + 1, "NEXT_CONTROL")
        end
        RecordSectionOnly(stage, position.section, DerivedSectionResult(stage, position.controls, result))
    end

    if position.index < #position.sections then
        return SetSectionCursor(stage, position.sections, position.index + 1, 0, "NEXT_SECTION")
    end
    Invoke(Tour(), "RecordStage", stage.id, DerivedStageResult(stage, position.sections, result))
    return AdvanceStage(stage, true)
end

local function BackCurrent()
    if ProfileMismatch() then
        return type(M.StartGuidedTour) == "function"
            and M.StartGuidedTour({ source = "profile_change", restart = true })
            or false
    end
    if Runtime.warning then
        Runtime.warning = nil
        M.RefreshGuidedTourChrome("CANCEL_SKIP")
        return true
    end
    if Runtime.manualAway then
        Runtime.manualAway = nil
        return SelectExpectedPage(CurrentStage())
    end
    local stage = CurrentStage()
    local position = CurrentPosition(stage)
    if stage.special or position.overview then return ReturnToPreviousStage(stage) end
    if position.control then
        local previousControl = position.controlIndex - 1
        return SetSectionCursor(stage, position.sections, position.index, max(0, previousControl), previousControl > 0 and "PREVIOUS_CONTROL" or "SECTION_OVERVIEW")
    end
    if position.index <= 1 then
        WriteCursor(stage, { overview = true, sectionIndex = 0, controlIndex = 0, controlTotal = 0 })
        if type(M.CloseAutoFocusedSections) == "function" then M.CloseAutoFocusedSections(stage.pageKey) end
        ClearSectionEmphasis(stage.pageKey)
        M.RefreshGuidedTourChrome("SECTION_OVERVIEW")
        return true
    end
    return SetSectionCursor(stage, position.sections, position.index - 1, 0, "PREVIOUS_SECTION")
end

local function LabelList(controls, limit)
    local labels, seen = {}, {}
    for i = 1, #controls do
        local label = tostring(controls[i].label or "")
        if label ~= "" and not seen[label] then
            seen[label] = true
            labels[#labels + 1] = label
            if #labels >= (limit or 4) then break end
        end
    end
    local value = table.concat(labels, ", ")
    if #controls > #labels then value = value .. format(Tr(" and %d more"), #controls - #labels) end
    return value
end

local function SkipSignature(stage, position)
    return table.concat({
        stage.id,
        position.section and position.section.id or "overview",
        position.control and position.control.id or "section",
    }, "\031")
end

local function SkipWarning(stage, position)
    if position.control then
        local help = tostring(position.control.help or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local detail = help ~= "" and help or format(Tr("the %s option"), Tr(position.control.label))
        return table.concat({
            format(Tr("Skip %s?"), Tr(position.control.label)),
            format(Tr("What you will miss: %s"), Tr(detail)),
            position.control.classification == "action"
                and Tr("The action is not run. Use Confirm skip to continue.")
                or Tr("Its current/default value stays unchanged. Use Confirm skip to continue."),
        }, "\n"), 1
    end

    local controls = position.section and position.controls
        or (not stage.special and AllStageControls(stage, position.sections))
        or {}
    local parts = { Tr(stage.impact) }
    if position.section then
        parts[1] = format(Tr("Skip the %s section?"), Tr(position.section.label))
        if #controls > 0 then
            parts[#parts + 1] = format(Tr("All %d options in this section stay unreviewed: %s."), #controls, LabelList(controls, 4))
        else
            parts[#parts + 1] = Tr("This section has no registered option, so only its guidance is skipped.")
        end
    elseif not stage.special and #position.sections > 0 then
        parts[#parts + 1] = format(Tr("%d native sections."), #position.sections)
        if #controls > 0 then
            parts[#parts + 1] = format(Tr("All %d options stay unreviewed: %s."), #controls, LabelList(controls, 4))
        end
    elseif #controls > 0 then
        parts[#parts + 1] = format(Tr("%d visible options: %s."), #controls, LabelList(controls, 4))
    elseif not stage.special and #position.sections > 0 then
        parts[#parts + 1] = Tr("Their current options remain unreviewed.")
    end
    parts[#parts + 1] = Tr("Current/default values stay unchanged. Use Confirm skip to continue.")
    return table.concat(parts, "\n"), #controls
end

local function SkipCurrent()
    if ProfileMismatch() then return false end
    local stage = CurrentStage()
    if stage.id == "final_review" then return false end
    local position = CurrentPosition(stage)
    local signature = SkipSignature(stage, position)
    if Runtime.warning then
        local warning = Runtime.warning
        local sectionId = position.section and position.section.id or nil
        if warning.stageId == stage.id and warning.sectionId == sectionId then
            Runtime.warning = nil
            return AdvanceCurrent("skipped")
        end
    end
    local text, count = SkipWarning(stage, position)
    Runtime.warning = {
        signature = signature,
        stageId = stage.id,
        sectionId = position.section and position.section.id or nil,
        controlId = position.control and position.control.id or nil,
        text = text,
        count = count,
    }
    M.RefreshGuidedTourChrome("SKIP_WARNING")
    return true
end

local function PauseTour()
    Runtime.warning = nil
    Runtime.manualAway = nil
    ClearSectionEmphasis()
    local frame = M.frame
    if type(M.HideSlashMenuAndMinibar) == "function" then
        M.HideSlashMenuAndMinibar(frame)
    elseif frame and type(frame.Hide) == "function" then
        frame:Hide()
    end
    return true
end

local function SetButtonEnabled(button, enabled)
    if not button then return end
    button._msuf2GuidedEnabled = enabled and true or false
    if type(button.SetEnabled) == "function" then button:SetEnabled(enabled and true or false) end
    if type(button.SetAlpha) == "function" then button:SetAlpha(enabled and 1 or 0.42) end
end

local function SetButtonText(button, text)
    if button and type(button.SetText) == "function" then button:SetText(Tr(text)) end
    if button and M.Theme and type(M.Theme.CenterButtonLabel) == "function" then M.Theme.CenterButtonLabel(button) end
end

local function SetFontColor(fontString, color)
    if fontString and color and type(fontString.SetTextColor) == "function" then
        fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function SetStageIcon(chrome, stage)
    local T = M.Theme
    local icon = chrome and chrome.icon
    if not (T and icon) then return end
    local grid = T.navIconGrid and T.navIconGrid[stage.icon]
    if grid and T.media and T.media.navIcons then
        icon:SetTexture(T.media.navIcons)
        icon:SetTexCoord(grid[1] / 8, (grid[1] + 1) / 8, grid[2] / 8, (grid[2] + 1) / 8)
    elseif T.media and T.media.logo then
        icon:SetTexture(T.media.logo)
        icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    end
    local color = T.navIconColors and T.navIconColors[stage.icon] or T.colors.accent
    if color then icon:SetVertexColor(color[1], color[2], color[3], 1) end
end

local function AnchorTourScroll(chrome, active)
    if not (chrome and chrome.scroll and chrome.host and chrome.status) then return end
    local scroll = chrome.scroll
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", active and chrome or chrome.status, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", chrome.host, "BOTTOMRIGHT", -24, 0)
    scroll._msuf2MaxScroll = nil
    scroll._msuf2SmoothScrollTarget = nil
    if type(scroll._msuf2RefreshScrollBar) == "function" then scroll:_msuf2RefreshScrollBar() end
end

local function LayoutChrome(chrome, warning, helpText)
    local hostWidth = max(420, tonumber(chrome.host and chrome.host:GetWidth()) or 760)
    local compact = hostWidth < 700
    local baseHeight = compact and (warning and 234 or 196) or (warning and 164 or 132)
    local charsPerLine = max(36, floor((hostWidth - 28) / 6.2))
    local estimatedLines = min(9, max(1, ceil(#tostring(helpText or "") / charsPerLine)))
    local includedLines = compact and (warning and 5 or 3) or (warning and 3 or 2)
    local height = baseHeight + (max(0, estimatedLines - includedLines) * 13)
    chrome:SetHeight(height)
    chrome._msuf2Compact = compact

    chrome.iconWell:ClearAllPoints()
    chrome.iconWell:SetPoint("TOPLEFT", chrome, "TOPLEFT", 16, -12)
    chrome.iconWell:SetSize(36, 36)
    chrome.title:ClearAllPoints()
    chrome.title:SetPoint("TOPLEFT", chrome, "TOPLEFT", 60, -12)
    chrome.title:SetPoint("RIGHT", chrome.step, "LEFT", -12, 0)
    chrome.step:ClearAllPoints()
    chrome.step:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -16, -16)
    chrome.step:SetWidth(compact and 84 or 112)
    chrome.section:ClearAllPoints()
    chrome.section:SetPoint("TOPLEFT", chrome, "TOPLEFT", 60, -32)
    chrome.section:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -16, -32)
    chrome.cueArrow:ClearAllPoints()
    chrome.cueArrow:SetPoint("TOPLEFT", chrome, "TOPLEFT", 16, compact and -64 or -56)
    chrome.help:ClearAllPoints()
    chrome.help:SetPoint("TOPLEFT", chrome, "TOPLEFT", 36, compact and -60 or -52)
    chrome.help:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -16, compact and 88 or 60)
    chrome.help:SetWidth(hostWidth - 48)
    chrome.progress:ClearAllPoints()
    chrome.progress:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 16, compact and 76 or 44)
    chrome.progress:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -16, compact and 76 or 44)
    chrome.progress:SetHeight(4)

    local buttons = { chrome.back, chrome.keep, chrome.skip, chrome.next, chrome.pause }
    local minimums = compact and { 48, 72, 58, 60, 54 } or { 58, 82, 68, 72, 64 }
    local maximums = compact and { 112, 126, 138, 112, 96 } or { 126, 146, 158, 126, 108 }
    local widths = {}
    for i = 1, #buttons do
        local preferred = minimums[i]
        local fontString = buttons[i]._msuf2Label
            or (type(buttons[i].GetFontString) == "function" and buttons[i]:GetFontString() or nil)
        if fontString and type(fontString.GetStringWidth) == "function" then
            local ok, textWidth = pcall(fontString.GetStringWidth, fontString)
            if ok and tonumber(textWidth) then
                minimums[i] = max(minimums[i], ceil(textWidth + 8))
                preferred = ceil(textWidth + 22)
                maximums[i] = max(maximums[i], minimums[i])
            end
        end
        widths[i] = min(max(preferred, minimums[i]), maximums[i])
    end
    local gap = compact and 5 or 7
    local function FitRow(indices)
        local available = hostWidth - 20 - (gap * (#indices - 1))
        local widthTotal, flexible = 0, 0
        for i = 1, #indices do
            local index = indices[i]
            widthTotal = widthTotal + widths[index]
            flexible = flexible + max(0, widths[index] - minimums[index])
        end
        if widthTotal <= available or flexible <= 0 then return end
        local overflow = widthTotal - available
        for i = 1, #indices do
            local index = indices[i]
            local room = max(0, widths[index] - minimums[index])
            local reduction = min(room, floor((overflow * room / flexible) + 0.5))
            widths[index] = widths[index] - reduction
        end
        widthTotal = 0
        for i = 1, #indices do widthTotal = widthTotal + widths[indices[i]] end
        local remainder = max(0, widthTotal - available)
        while remainder > 0 do
            local changed = false
            for i = #indices, 1, -1 do
                local index = indices[i]
                if widths[index] > minimums[index] and remainder > 0 then
                    widths[index] = widths[index] - 1
                    remainder = remainder - 1
                    changed = true
                end
            end
            if not changed then break end
        end
    end
    local function PlaceRow(indices, bottom)
        FitRow(indices)
        local total = gap * (#indices - 1)
        for i = 1, #indices do total = total + widths[indices[i]] end
        local x = max(10, floor((hostWidth - total) / 2))
        for i = 1, #indices do
            local index = indices[i]
            local button = buttons[index]
            button:ClearAllPoints()
            button:SetSize(widths[index], 24)
            button:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", x, bottom)
            x = x + widths[index] + gap
        end
    end
    if compact then
        PlaceRow({ 1, 2, 3 }, 39)
        PlaceRow({ 4, 5 }, 10)
    else
        PlaceRow({ 1, 2, 3, 4, 5 }, 10)
    end
    AnchorTourScroll(chrome, true)
end

local function ProgressFraction(stage, position)
    local within = 0
    if not stage.special and not position.overview and #position.sections > 0 then
        local total, completed = 1, 1 -- stage overview
        local records = RuntimeControlRecords()
        for i = 1, #position.sections do
            local controls = SectionControls(stage.pageKey, position.sections[i], position.sections, records, stage.includeEphemeralControls)
            total = total + 1 + #controls -- section overview plus every registered control
            if i < position.index then
                completed = completed + 1 + #controls
            elseif i == position.index and position.control then
                completed = completed + 1 + max(0, position.controlIndex - 1)
            end
        end
        within = min(max(completed / max(1, total), 0), 0.99)
    elseif stage.id == "final_review" then
        within = 1
    end
    return min(max(((stage.index - 1) + within) / #STAGES, 0), 1)
end

local function PlayChromeTransition(chrome, signature, reason)
    if Runtime.lastVisualSignature == signature or reason == "HOST_SIZE" or reason == "WINDOW_RESIZE" then return end
    Runtime.lastVisualSignature = signature
    local T = M.Theme
    if not (T and type(T.PlayMotion) == "function") then return end
    T.PlayMotion(chrome.iconWell, "controlFocusIn", { fromAlpha = 0.28, toAlpha = 1, duration = 0.18 })
    T.PlayMotion(chrome.title, "controlFocusIn", { fromAlpha = 0.38, toAlpha = 1, duration = 0.16 })
    T.PlayMotion(chrome.help, "controlFocusIn", { fromAlpha = 0.30, toAlpha = 1, duration = 0.20 })
    T.PlayMotion(chrome.progressFill, "controlFocusIn", { fromAlpha = 0.45, toAlpha = 1, duration = 0.22 })
end

local function StopChromeTransition(chrome)
    local T = M.Theme
    if not (chrome and T and type(T.StopMotion) == "function") then return end
    local regions = { chrome.iconWell, chrome.title, chrome.help, chrome.progressFill }
    for i = 1, #regions do T.StopMotion(regions[i]) end
end

local function RegisterSpecialClickTargets(stageId, key, widgets)
    local targets = Runtime.specialClickTargets
    if type(targets) ~= "table" or targets.stageId ~= stageId then
        targets = { stageId = stageId, groups = {} }
        Runtime.specialClickTargets = targets
    end
    targets.groups[key] = type(widgets) == "table" and widgets or {}
end

local function FlashGuidedClickTargets(chrome, stage, position, context, reason)
    if reason == "HOST_SIZE" or reason == "WINDOW_RESIZE" then return end
    local T = M.Theme
    if not (T and type(T.PlayNeonFlash) == "function") then return end
    context = context or {}
    local editStatus = stage.id == "edit_mode"
        and (type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {})
        or {}
    local signature = table.concat({
        stage.id,
        position.section and position.section.id or "overview",
        position.control and position.control.id or "section",
        context.profileMismatch and "profile" or "profile-ok",
        context.manualAway and "away" or "here",
        context.warning and tostring(context.warning.signature or "warning") or "normal",
        tostring(Preference("playstyle") or ""),
        tostring(Preference("informationStyle") or ""),
        tostring(CooldownAnchorDecision() or ""),
        EditModePlacementComplete() and "placed" or "unplaced",
        editStatus.active and "edit-on" or "edit-off",
    }, "\031")
    if Runtime.lastClickCueSignature == signature then return end
    Runtime.lastClickCueSignature = signature

    local widgets, seen = {}, {}
    local function Add(widget)
        if widget and not seen[widget] then
            seen[widget] = true
            widgets[#widgets + 1] = widget
        end
    end
    local function AddGroup(key)
        local targets = Runtime.specialClickTargets
        local group = targets and targets.stageId == stage.id and targets.groups and targets.groups[key]
        for i = 1, #(group or {}) do Add(group[i]) end
    end

    if context.profileMismatch then
        Add(chrome.back)
    elseif context.manualAway then
        Add(chrome.next)
    elseif context.warning then
        Add(chrome.skip)
    elseif stage.id == "menu_basics" then
        if Preference("playstyle") == nil then AddGroup("playstyle") end
        if Preference("informationStyle") == nil then AddGroup("informationStyle") end
        if PersonalQuestionsComplete() then Add(chrome.next) end
    elseif stage.id == "edit_mode" then
        if not CooldownAnchorDecisionComplete() then
            AddGroup("anchor")
        elseif EditModePlacementComplete() then
            Add(chrome.next)
        elseif editStatus.active ~= true then
            Add(M.dashboardToolbarEditModeButton)
        end
    elseif stage.id == "final_review" or not position.control then
        Add(chrome.next)
    end

    for i = 1, #widgets do
        local widget = widgets[i]
        T.PlayNeonFlash(widget, "success", { alpha = 0.28, duration = 0.82 })
        if type(T.PlayMotion) == "function" then
            T.PlayMotion(widget, "controlFocusIn", { fromAlpha = 0.52, toAlpha = 1, duration = 0.18 })
        end
    end
end

function M.RefreshGuidedTourChrome(reason)
    local chrome = Runtime.chrome
    if not chrome then return false end
    if not TourIsActive() then
        Runtime.warning = nil
        Runtime.manualAway = nil
        Runtime.lastVisualSignature = nil
        Runtime.lastClickCueSignature = nil
        ClearSectionEmphasis()
        StopChromeTransition(chrome)
        chrome:Hide()
        RefreshEditModeOpenCue(false)
        AnchorTourScroll(chrome, false)
        return false
    end

    local stage = CurrentStage()
    local profileMismatch, tourProfile, activeProfile = ProfileMismatch()
    if profileMismatch then
        Runtime.warning = nil
        Runtime.manualAway = nil
    end
    local expected = ExpectedPage(stage)
    local position = CurrentPosition(stage)
    local currentPage = M.activeKey
    if currentPage and currentPage ~= expected then Runtime.manualAway = true end
    local manualAway = Runtime.manualAway == true and currentPage ~= expected
    local warning = Runtime.warning
    local showEditModeOpenCue = not profileMismatch
        and not manualAway
        and not warning
        and ShouldShowEditModeOpenCue()
    local displayHelp = profileMismatch
        and format(Tr("This tour belongs to profile %s. You are now editing %s. Restart the tour here or switch back to continue safely."), tourProfile, activeProfile)
        or manualAway and Tr("Return to the guided page when you are ready to continue.")
        or warning and warning.text
        or StageCue(stage, position)
    if profileMismatch or manualAway then
        ClearSectionEmphasis()
    elseif stage.special or position.overview then
        ClearSectionEmphasis(stage.pageKey)
    elseif position.section then
        EmphasizeSection(stage.pageKey, position.section, position.control)
        EmphasizeControl(stage, position.section, position.controls, position.control)
    end
    SetStageIcon(chrome, stage)
    chrome.step:SetText(format(Tr("Step %d / %d"), stage.index, #STAGES))

    if profileMismatch then
        chrome.title:SetText(Tr("Active profile changed"))
        chrome.section:SetText(format(Tr("Tour profile: %s - Active profile: %s"), tourProfile, activeProfile))
        chrome.help:SetText(displayHelp)
    elseif manualAway then
        chrome.title:SetText(format(Tr("Tour paused - %s"), PersonalizedTitle(stage)))
        chrome.section:SetText(Tr("Progress is saved while you use another page."))
        chrome.help:SetText(displayHelp)
    else
        chrome.title:SetText(PersonalizedTitle(stage))
        if stage.special then
            chrome.section:SetText(stage.id == "final_review" and Tr("Final review") or Tr("Guided introduction"))
        elseif position.overview then
            local controls = AllStageControls(stage, position.sections)
            chrome.section:SetText(format(Tr("Overview · %d sections · %d options"), #position.sections, #controls))
        elseif position.control then
            if ControlIsAction(position.control) then
                chrome.section:SetText(format(Tr("Section %d / %d · Action %d / %d · %s"), position.index, #position.sections, position.controlIndex, #position.controls, Tr(position.control.label)))
            else
                chrome.section:SetText(format(Tr("Section %d / %d · Option %d / %d · %s"), position.index, #position.sections, position.controlIndex, #position.controls, Tr(position.control.label)))
            end
        elseif position.section then
            chrome.section:SetText(format(Tr("Section %d / %d · %s · %d options"), position.index, #position.sections, Tr(position.section.label), #position.controls))
        end
        chrome.help:SetText(displayHelp)
    end
    local alert = profileMismatch or warning
    SetFontColor(chrome.help, alert and (M.Theme.colors.warning or M.Theme.colors.warn) or M.Theme.colors.muted)
    local cueColor = alert and (M.Theme.colors.warning or M.Theme.colors.warn) or M.Theme.colors.accent
    if cueColor then chrome.cueArrow:SetVertexColor(cueColor[1], cueColor[2], cueColor[3], 1) end

    local fraction = ProgressFraction(stage, position)
    chrome.progressFill:SetWidth(max(1, floor(((chrome.progress:GetWidth() or 1) - 2) * fraction)))

    local firstPosition = stage.index == 1 and (stage.special or position.overview)
    local final = stage.id == "final_review"
    local waitingForAnchorDecision = stage.id == "edit_mode" and not CooldownAnchorDecisionComplete()
    local waitingForEditModeMove = stage.id == "edit_mode" and not waitingForAnchorDecision and not EditModePlacementComplete()
    SetButtonText(chrome.back, profileMismatch and "Restart tour" or (warning and "Cancel" or "Back"))
    SetButtonText(chrome.keep, KeepLabel(stage, position))
    SetButtonText(chrome.skip, warning and "Confirm skip" or "Skip")
    SetButtonText(chrome.next, manualAway and "Return" or (final and "Finish" or (waitingForEditModeMove and "Move a frame first" or "Next")))
    SetButtonText(chrome.pause, "Pause")
    LayoutChrome(chrome, alert ~= nil and alert ~= false, displayHelp)

    if profileMismatch then
        SetButtonEnabled(chrome.back, true)
        SetButtonEnabled(chrome.keep, false)
        SetButtonEnabled(chrome.skip, false)
        SetButtonEnabled(chrome.next, false)
    elseif manualAway then
        SetButtonEnabled(chrome.back, false)
        SetButtonEnabled(chrome.keep, false)
        SetButtonEnabled(chrome.skip, false)
        SetButtonEnabled(chrome.next, true)
    elseif warning then
        SetButtonEnabled(chrome.back, true)
        SetButtonEnabled(chrome.keep, false)
        SetButtonEnabled(chrome.skip, true)
        SetButtonEnabled(chrome.next, false)
    else
        SetButtonEnabled(chrome.back, not firstPosition)
        SetButtonEnabled(chrome.keep, not final and stage.id ~= "menu_basics" and not waitingForAnchorDecision and not waitingForEditModeMove)
        SetButtonEnabled(chrome.skip, not final)
        SetButtonEnabled(chrome.next, (stage.id ~= "menu_basics" or PersonalQuestionsComplete()) and not waitingForAnchorDecision and not waitingForEditModeMove)
    end
    SetButtonEnabled(chrome.pause, true)
    chrome:Show()
    if (reason == "HOST_SIZE" or reason == "WINDOW_RESIZE")
        and not profileMismatch and not manualAway
        and not stage.special and not position.overview and position.section
    then
        FocusGuidedWidget(position.control and position.control.widget, position.section.outer, false)
    end
    local signature = table.concat({ stage.id, position.section and position.section.id or "overview", position.control and position.control.id or "section", profileMismatch and "profile" or (warning and "warning" or "normal"), manualAway and "away" or "guided" }, "\031")
    PlayChromeTransition(chrome, signature, reason)
    RefreshEditModeOpenCue(showEditModeOpenCue)
    RefreshEditModePlacementCue()
    FlashGuidedClickTargets(chrome, stage, position, {
        profileMismatch = profileMismatch,
        manualAway = manualAway,
        warning = warning,
    }, reason)
    return true
end

local function ChromeButton(parent, T, label, handler)
    local button = T.Button(parent, Tr(label), 70, 24)
    button._msuf2SkipHistoryCheckpoint = true
    if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
    button:SetScript("OnClick", function(self)
        if self._msuf2GuidedEnabled == false or BlockedByCombat() then return end
        handler()
    end)
    return button
end

local function RegisterChromeControl(button, suffix, label, help)
    if type(M.RegisterMenuChromeControl) == "function" then
        M.RegisterMenuChromeControl(button, "guided-tour." .. suffix, Tr(label), "action", {
            actionKey = "guided_setup_step",
            actionFixedArgs = { step = suffix },
            historyMode = "none",
            help = Tr(help),
        })
    end
end

function M.RunGuidedTourStep(step)
    step = tostring(step or ""):lower()
    if BlockedByCombat() or not TourIsActive() then return false, "guided_setup_inactive" end
    local stage = CurrentStage()
    if (step == "keep" or step == "next") and stage.id == "edit_mode" then
        if not CooldownAnchorDecisionComplete() then return false, "guided_edit_mode_anchor_required" end
        if not EditModePlacementComplete() then return false, "guided_edit_mode_move_required" end
    end
    if step == "back" then
        BackCurrent()
    elseif step == "keep" then
        AdvanceCurrent("kept")
    elseif step == "skip" then
        local skipped = SkipCurrent()
        if skipped and Runtime.warning then
            return true, "confirmation_needed", Runtime.warning.text
        end
    elseif step == "next" then
        if Runtime.manualAway then
            Runtime.manualAway = nil
            SelectExpectedPage(CurrentStage())
        else
            AdvanceCurrent("reviewed")
        end
    elseif step == "pause" then
        PauseTour()
    else
        return false, "unknown_guided_setup_step"
    end
    return true, step
end

function M.InstallGuidedTourChrome(frame, status, host, scroll)
    if Runtime.chrome then
        Runtime.chrome.frame = frame or Runtime.chrome.frame
        Runtime.chrome.status = status or Runtime.chrome.status
        Runtime.chrome.host = host or Runtime.chrome.host
        Runtime.chrome.scroll = scroll or Runtime.chrome.scroll
        M.RefreshGuidedTourChrome("REINSTALL")
        return Runtime.chrome
    end
    local T = M.Theme
    if not (frame and status and host and scroll and T and type(T.Panel) == "function" and type(T.Font) == "function" and type(T.Button) == "function") then
        return nil
    end

    local chrome = T.Panel(host, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    if type(T.ApplySurface) == "function" then T.ApplySurface(chrome, "status") end
    chrome:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, 0)
    chrome:SetPoint("TOPRIGHT", status, "BOTTOMRIGHT", 0, 0)
    chrome:SetHeight(132)
    if type(chrome.SetFrameLevel) == "function" then chrome:SetFrameLevel((host:GetFrameLevel() or 1) + 5) end
    chrome.frame, chrome.status, chrome.host, chrome.scroll = frame, status, host, scroll

    local divider = chrome:CreateTexture(nil, "ARTWORK", nil, 3)
    divider:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 16, 0)
    divider:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -16, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.18)

    local iconWell = T.Panel(chrome, nil, T.colors.pillBaseSolid or T.colors.panel2, T.colors.pillEdge or T.colors.borderSoft)
    if type(T.ApplySurface) == "function" then T.ApplySurface(iconWell, "card") end
    local icon = iconWell:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", iconWell, "CENTER", 0, 0)
    chrome.iconWell, chrome.icon = iconWell, icon

    chrome.title = T.Font(chrome, "GameFontNormal", "", T.colors.text)
    chrome.title:SetJustifyH("LEFT")
    chrome.step = T.Font(chrome, "GameFontDisableSmall", "", T.colors.accent)
    chrome.step:SetJustifyH("RIGHT")
    chrome.section = T.Font(chrome, "GameFontDisableSmall", "", T.colors.muted)
    chrome.section:SetJustifyH("LEFT")
    local cueArrow = chrome:CreateTexture(nil, "OVERLAY", nil, 4)
    local cueAtlas = cueArrow.SetAtlas and pcall(cueArrow.SetAtlas, cueArrow, "NPE_ArrowRight", false)
    if not cueAtlas then cueArrow:SetTexture(T.media.collapseArrow) end
    cueArrow:SetSize(16, 16)
    cueArrow:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
    chrome.cueArrow = cueArrow
    chrome.help = T.Font(chrome, "GameFontHighlightSmall", "", T.colors.muted)
    chrome.help:SetJustifyH("LEFT")
    if chrome.help.SetWordWrap then chrome.help:SetWordWrap(true) end
    if chrome.help.SetNonSpaceWrap then chrome.help:SetNonSpaceWrap(true) end

    local progress = CreateFrame("Frame", nil, chrome)
    local progressBg = progress:CreateTexture(nil, "BACKGROUND")
    progressBg:SetAllPoints()
    local track = T.colors.coreShadow or T.colors.bg
    progressBg:SetColorTexture(track[1], track[2], track[3], 0.92)
    local progressFill = progress:CreateTexture(nil, "ARTWORK")
    progressFill:SetPoint("TOPLEFT", progress, "TOPLEFT", 1, -1)
    progressFill:SetPoint("BOTTOMLEFT", progress, "BOTTOMLEFT", 1, 1)
    progressFill:SetWidth(1)
    progressFill:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.96)
    chrome.progress, chrome.progressFill = progress, progressFill

    chrome.back = ChromeButton(chrome, T, "Back", function() M.RunGuidedTourStep("back") end)
    chrome.keep = ChromeButton(chrome, T, "Keep current", function() M.RunGuidedTourStep("keep") end)
    chrome.skip = ChromeButton(chrome, T, "Skip", function() M.RunGuidedTourStep("skip") end)
    chrome.next = ChromeButton(chrome, T, "Next", function() M.RunGuidedTourStep("next") end)
    chrome.pause = ChromeButton(chrome, T, "Pause", function() M.RunGuidedTourStep("pause") end)
    if type(T.SkinPrimaryButton) == "function" then T.SkinPrimaryButton(chrome.next) end

    RegisterChromeControl(chrome.back, "back", "Guided setup: Back", "Returns to the previous section, overview or stage.")
    RegisterChromeControl(chrome.keep, "keep", "Guided setup: Keep current/default", "Keeps current values unchanged and advances.")
    RegisterChromeControl(chrome.skip, "skip", "Guided setup: Skip", "Shows an inline impact warning before skipping.")
    RegisterChromeControl(chrome.next, "next", "Guided setup: Next", "Opens the next guided section or stage.")
    RegisterChromeControl(chrome.pause, "pause", "Guided setup: Pause", "Closes the menu while preserving guided setup progress.")

    Runtime.chrome = chrome
    chrome:Hide()
    if type(host.HookScript) == "function" and not host._msuf2GuidedTourSizeHook then
        host._msuf2GuidedTourSizeHook = true
        host:HookScript("OnSizeChanged", function()
            if TourIsActive() then M.RefreshGuidedTourChrome("HOST_SIZE") end
        end)
    end
    if type(frame.HookScript) == "function" and not frame._msuf2GuidedTourHideHook then
        frame._msuf2GuidedTourHideHook = true
        frame:HookScript("OnHide", function()
            ClearSectionEmphasis()
            StopChromeTransition(chrome)
        end)
    end
    M.RefreshGuidedTourChrome("INSTALL")
    return chrome
end

function M.GuidedTourOnPageSelected(pageKey)
    if not TourIsActive() then
        M.RefreshGuidedTourChrome("PAGE_INACTIVE")
        return false
    end
    local stage = CurrentStage()
    local expected = ExpectedPage(stage)
    if tostring(pageKey or "") ~= expected then
        Runtime.manualAway = true
        Runtime.warning = nil
        ClearSectionEmphasis()
        M.RefreshGuidedTourChrome("MANUAL_PAGE")
        return false
    end
    Runtime.manualAway = nil
    if not stage.special then FocusCurrentSection(stage) end
    M.RefreshGuidedTourChrome("GUIDED_PAGE")
    return true
end

function M.StartGuidedTour(opts)
    if BlockedByCombat() then return false end
    opts = type(opts) == "table" and opts or {}
    local stage = STAGE_BY_ID[tostring(opts.stageId or "")] or STAGES[1]
    local restorePoint
    if type(M.CaptureGuidedTourRestorePoint) == "function" then
        local captured, value = pcall(M.CaptureGuidedTourRestorePoint)
        if captured and type(value) == "table" then restorePoint = value end
    end
    local ok = Invoke(Tour(), "Start", ActiveProfileName(), stage.id, restorePoint)
    if not ok then return false end
    Invoke(FirstLoad(), "Start", "guided_tour")
    Runtime.warning = nil
    Runtime.manualAway = nil
    Runtime.lastVisualSignature = nil
    Invoke(Tour(), "SetStage", stage.id, stage.index)
    WriteCursor(stage, { overview = true, sectionIndex = 0, controlIndex = 0, controlTotal = 0 })
    if type(M.InvalidatePage) == "function" then
        M.InvalidatePage("home")
        M.InvalidatePage("guided_setup")
    end
    return SelectExpectedPage(stage)
end

function M.ResumeGuidedTour()
    if BlockedByCombat() or not TourIsActive() then return false end
    Invoke(Tour(), "Resume")
    Runtime.warning = nil
    Runtime.manualAway = nil
    return SelectExpectedPage(CurrentStage())
end

function M.OpenGuidedTourAtStage(stageId, opts)
    if BlockedByCombat() then return false end
    opts = type(opts) == "table" and opts or {}
    local stage = STAGE_BY_ID[tostring(stageId or "")]
    if not stage then return false end
    if not TourIsActive() then
        opts.stageId = stage.id
        return M.StartGuidedTour(opts)
    end
    ClearSectionEmphasis()
    Invoke(Tour(), "SetStage", stage.id, stage.index)
    if opts.resetCursor == true then WriteCursor(stage, { overview = true, sectionIndex = 0, controlIndex = 0, controlTotal = 0 }) end
    Runtime.warning = nil
    Runtime.manualAway = nil
    return SelectExpectedPage(stage)
end

function M.GetGuidedTourCurrentPage()
    return ExpectedPage(CurrentStage())
end

function M.GetGuidedTourSummary()
    local ok, source = Invoke(Tour(), "GetSummary")
    source = ok and type(source) == "table" and source or {}
    local summary = {
        reviewedStages = tonumber(source.reviewedStages) or 0,
        keptStages = tonumber(source.keptStages) or 0,
        skippedStages = tonumber(source.skippedStages) or 0,
        reviewedSections = tonumber(source.reviewedSections) or 0,
        keptSections = tonumber(source.keptSections) or 0,
        skippedSections = tonumber(source.skippedSections) or 0,
        reviewedControls = tonumber(source.reviewedControls) or 0,
        keptControls = tonumber(source.keptControls) or 0,
        skippedControls = tonumber(source.skippedControls) or 0,
        totalStages = #STAGES,
        skippedItems = {},
        skippedAreas = {},
        skippedSectionItems = {},
    }
    local state = TourState()
    local stageResults = type(state.stageResults) == "table" and state.stageResults or {}
    for i = 1, #STAGES do
        local stage = STAGES[i]
        if stageResults[stage.id] == "s" then
            summary.skippedAreas[#summary.skippedAreas + 1] = Tr(stage.title)
        end
    end
    local sectionResults = type(state.sectionResults) == "table" and state.sectionResults or {}
    local sectionMetadata = type(state.sectionMetadata) == "table" and state.sectionMetadata or {}
    for resultKey, code in pairs(sectionResults) do
        if code == "s" then
            local metadata = type(sectionMetadata[resultKey]) == "table" and sectionMetadata[resultKey] or {}
            local stageId = tostring(metadata.stageId or resultKey:match("^(.-)\031") or "")
            local stage = STAGE_BY_ID[stageId]
            if stage and stageResults[stageId] ~= "s" then
                summary.skippedSectionItems[#summary.skippedSectionItems + 1] = {
                    stageIndex = stage.index,
                    stageLabel = Tr(stage.title),
                    label = Tr(metadata.label or metadata.sectionId or "Section"),
                }
            end
        end
    end
    sort(summary.skippedSectionItems, function(a, b)
        if a.stageIndex ~= b.stageIndex then return a.stageIndex < b.stageIndex end
        return a.label < b.label
    end)
    local skipped = type(state.skippedControls) == "table" and state.skippedControls or {}
    for controlId, item in pairs(skipped) do
        if type(item) == "table" then
            local stageId = tostring(item.stageId or "")
            local sectionId = tostring(item.sectionId or "")
            local coveredByStage = stageResults[stageId] == "s"
            local coveredBySection = sectionId ~= "" and sectionResults[stageId .. "\031" .. sectionId] == "s"
            if not coveredByStage and not coveredBySection then
                local stage = STAGE_BY_ID[stageId]
                summary.skippedItems[#summary.skippedItems + 1] = {
                    controlId = tostring(controlId),
                    stageId = stageId,
                    stageIndex = stage and stage.index or (#STAGES + 1),
                    stageLabel = stage and Tr(stage.title) or Tr("Guided setup"),
                    label = tostring(item.label or controlId),
                    pageKey = item.pageKey,
                    sectionId = item.sectionId,
                }
            end
        end
    end
    sort(summary.skippedItems, function(a, b)
        if a.stageIndex ~= b.stageIndex then return a.stageIndex < b.stageIndex end
        local al, bl = a.label:lower(), b.label:lower()
        return al == bl and a.controlId < b.controlId or al < bl
    end)
    return summary
end

local function SetWrapped(fontString, width)
    if not fontString then return end
    fontString:SetWidth(max(40, width or 40))
    fontString:SetJustifyH("LEFT")
    if fontString.SetWordWrap then fontString:SetWordWrap(true) end
    if fontString.SetNonSpaceWrap then fontString:SetNonSpaceWrap(true) end
end

local function AddCardIcon(card, T, iconKey)
    local well = T.Panel(card, nil, T.colors.pillBaseSolid or T.colors.panel2, T.colors.pillEdge or T.colors.borderSoft)
    well:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
    well:SetSize(32, 32)
    local icon = well:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    local grid = T.navIconGrid and T.navIconGrid[iconKey]
    if grid and T.media and T.media.navIcons then
        icon:SetTexture(T.media.navIcons)
        icon:SetTexCoord(grid[1] / 8, (grid[1] + 1) / 8, grid[2] / 8, (grid[2] + 1) / 8)
    elseif T.media and T.media.logo then
        icon:SetTexture(T.media.logo)
        icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    end
    local color = T.navIconColors and T.navIconColors[iconKey] or T.colors.accent
    icon:SetVertexColor(color[1], color[2], color[3], 1)
    return well
end

local function InfoCard(builder, T, title, body, iconKey, height)
    local card = builder:Section("", height or 82)
    if card.title then card.title:SetText("") end
    AddCardIcon(card, T, iconKey or "home")
    local heading = T.Font(card, "GameFontNormal", Tr(title), T.colors.text)
    heading:SetPoint("TOPLEFT", card, "TOPLEFT", 56, -12)
    heading:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    heading:SetJustifyH("LEFT")
    local copy = T.Font(card, "GameFontHighlightSmall", Tr(body), T.colors.muted)
    copy:SetPoint("TOPLEFT", card, "TOPLEFT", 56, -36)
    SetWrapped(copy, builder.width - 70)
    if type(T.PlayMotion) == "function" then
        T.PlayMotion(card, "controlFocusIn", { fromAlpha = 0.18, toAlpha = 1, duration = 0.20 })
    end
    return card
end

local function Header(builder, title, subtitle)
    return builder:Header(Tr(title), Tr(subtitle), 72)
end

local function PersonalQuestion(ctx, builder, T, W, key, label, values)
    local card = builder:Section("", 100)
    if card.title then card.title:SetText("") end
    local localized = {}
    for i = 1, #values do
        localized[i] = { value = values[i].value, text = Tr(values[i].text), icon = values[i].icon }
    end
    local segment = W.Segment(card, Tr(label), localized, max(240, builder.width - 28))
    RegisterSpecialClickTargets("menu_basics", key, segment.buttons)
    local function Refresh()
        segment:SetValue(Preference(key))
    end
    for i = 1, #(segment.buttons or {}) do
        local button = segment.buttons[i]
        local value = localized[i]
        if value and type(T.AttachNavIcon) == "function" then T.AttachNavIcon(button, value.icon, false, true) end
        button:SetScript("OnClick", function(self)
            if BlockedByCombat() then return end
            Invoke(Tour(), "SetPreference", key, self._msuf2Value)
            Refresh()
            if type(T.PlayMotion) == "function" then
                T.PlayMotion(self, "controlFocusIn", { fromAlpha = 0.45, toAlpha = 1, duration = 0.16 })
            end
            M.RefreshGuidedTourChrome("PERSONAL_CHOICE")
        end)
    end
    if type(M.RegisterSearchWidget) == "function" then
        local identity = "guided_setup.preference." .. key
        M.RegisterSearchWidget(segment, {
            controlId = "menu2." .. identity,
            identityKey = identity,
            controlPath = identity:gsub("%.", "/"),
            pageKey = "guided_setup",
            label = Tr(label),
            kind = "segment",
            classification = "ephemeral",
            ephemeral = true,
            help = Tr("Personalizes guided setup hints without changing MSUF settings."),
        })
    end
    if type(ctx.AddRefresher) == "function" then ctx:AddRefresher(Refresh) end
    Refresh()
    return card
end

local function BuildMenuBasicsPage(ctx, T, W)
    Runtime.specialClickTargets = { stageId = "menu_basics", groups = {} }
    local b = W.PageBuilder(ctx)
    Header(b, format(Tr("Welcome, %s"), PlayerDisplayName()), "Two quick choices make the guide fit how you play.")
    PersonalQuestion(ctx, b, T, W, "playstyle", "Where do you spend most of your time?", {
        { value = "solo", text = "Solo / World", icon = "uf_player" },
        { value = "dungeons", text = "Dungeons", icon = "gf_layout" },
        { value = "raid", text = "Raid / Mythic", icon = "gf_indicators" },
    })
    PersonalQuestion(ctx, b, T, W, "informationStyle", "How much combat information should stand out?", {
        { value = "calm", text = "Clean", icon = "opt_fonts" },
        { value = "balanced", text = "Balanced", icon = "opt_bars" },
        { value = "detailed", text = "Combat detail", icon = "auras3_styling" },
    })
    InfoCard(b, T, "Navigate and find", "Use the left rail for pages and Search for an exact native control.", "home", 76)
    InfoCard(b, T, "Autosave and history", "Changes autosave. Undo and Redo restore recent edits; Pause saves this exact tour position.", "profiles", 78)
    InfoCard(b, T, "Reset with intent", "Reset All affects only the current supported page and asks first.", "gameplay", 76)
    return math.abs(b.y) + 34
end

local function RegisterGuidedPageButton(button, suffix, label, help)
    if type(M.RegisterSearchWidget) == "function" then
        local identity = "guided_setup." .. suffix
        M.RegisterSearchWidget(button, {
            controlId = "menu2." .. identity,
            identityKey = identity,
            controlPath = identity:gsub("%.", "/"),
            pageKey = "guided_setup",
            label = Tr(label),
            kind = "button",
            classification = "action",
            help = Tr(help),
            historyMode = "none",
        })
    end
end

local function BuildEditModePage(ctx, T, W)
    Runtime.specialClickTargets = { stageId = "edit_mode", groups = {} }
    local b = W.PageBuilder(ctx)
    Header(b, "Choose the frame anchor first", "This decides what every Unitframe position is relative to. Choose before opening MSUF Edit Mode.")

    local decisionCard = b:Section("", 146)
    if decisionCard.title then decisionCard.title:SetText("") end
    local decisionValues = {
        { value = "cooldown", text = Tr("Follow Main Cooldowns") },
        { value = "independent", text = Tr("Independent placement") },
    }
    local decision = W.Segment(decisionCard, Tr("Should all Unitframes follow the Cooldown Manager?"), decisionValues, max(240, b.width - 32))
    RegisterSpecialClickTargets("edit_mode", "anchor", decision.buttons)
    if type(W.MoveWidget) == "function" then W.MoveWidget(decision, decisionCard, 16, -18, max(240, b.width - 32), "LEFT") end
    local decisionCopy = T.Font(decisionCard, "GameFontHighlightSmall", "", T.colors.muted)
    decisionCopy:SetPoint("TOPLEFT", decisionCard, "TOPLEFT", 16, -88)
    SetWrapped(decisionCopy, b.width - 32)

    InfoCard(b, T, "What you can move", "Unitframes, supported castbars, group containers, aura groups and the tooltip preview. Boss 1 moves the shared Boss layout.", "uf_player", 86)
    InfoCard(b, T, "Drag, select and align", "Drag to place; click for quick controls. Arrow keys nudge, while Grid and Snap align.", "gf_layout", 80)
    InfoCard(b, T, "Undo, Cancel All, Exit", "Undo and Redo affect individual moves. Cancel All restores the entry snapshot; Exit keeps your work.", "gameplay", 82)
    InfoCard(b, T, "Combat pauses safely", "Combat closes the menu and Edit Mode but keeps changes made so far. Reopen MSUF afterward to resume here.", "opt_misc", 82)

    local action = b:Section("", 84)
    if action.title then action.title:SetText("") end
    local stateLabel = T.Font(action, "GameFontNormal", "", T.colors.text)
    stateLabel:SetPoint("TOPLEFT", action, "TOPLEFT", 16, -20)
    stateLabel:SetWidth(max(120, b.width - 252))
    stateLabel:SetJustifyH("LEFT")
    local stateCopy = T.Font(action, "GameFontDisableSmall", "", T.colors.muted)
    stateCopy:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)
    stateCopy:SetWidth(max(120, b.width - 252))
    stateCopy:SetJustifyH("LEFT")
    local button = T.Button(action, Tr("Open MSUF Edit Mode"), min(210, max(150, floor(b.width * 0.30))), 28)
    button:SetPoint("RIGHT", action, "RIGHT", -16, 0)
    if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
    if type(T.SkinPrimaryButton) == "function" then T.SkinPrimaryButton(button) end

    local function Refresh()
        local status = type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {}
        local active = status.active == true
        local anchorDecision = CooldownAnchorDecision()
        local placementComplete = EditModePlacementComplete()
        decision:SetValue(anchorDecision)
        if anchorDecision == "cooldown" then
            decisionCopy:SetText(Tr("Selected: Unitframes follow Essential Cooldown Manager. If Main Cooldowns move, the anchored Unitframe layout follows."))
        elseif anchorDecision == "independent" then
            decisionCopy:SetText(Tr("Selected: Unitframes use the current global/custom anchor. Moving Main Cooldowns will not move them."))
        else
            decisionCopy:SetText(Tr("Required before placement. Changing this later can shift the whole layout because the saved offsets use a different anchor."))
        end
        if placementComplete then
            stateLabel:SetText(Tr("Frame moved - placement complete"))
            stateCopy:SetText(active and Tr("Exit keeps the result. You can now continue the guide.") or Tr("The required Edit Mode movement is complete."))
        elseif active then
            stateLabel:SetText(Tr("Move one highlighted frame to continue"))
            stateCopy:SetText(Tr("Two arrows point to a movable frame. Drag it once; Next unlocks after a real position change."))
        elseif anchorDecision then
            stateLabel:SetText(Tr("Anchor chosen - open Edit Mode and move a frame"))
            stateCopy:SetText(Tr("The placement step completes after you drag the highlighted frame once."))
        else
            stateLabel:SetText(Tr("Choose anchoring before placement"))
            stateCopy:SetText(Tr("Edit Mode unlocks after the anchor choice above."))
        end
        SetFontColor(stateLabel, placementComplete and (T.colors.ok or T.colors.accent) or (active and (T.colors.warning or T.colors.accent) or T.colors.text))
        SetButtonText(button, active and "Exit and keep changes" or "Open MSUF Edit Mode")
        SetButtonEnabled(button, not status.combatLocked and (active or anchorDecision ~= nil))
    end
    for i = 1, #(decision.buttons or {}) do
        local choice = decision.buttons[i]
        choice:SetScript("OnClick", function(self)
            if SetGuidedCooldownAnchorDecision(self._msuf2Value) then
                Refresh()
                M.RefreshGuidedTourChrome("COOLDOWN_ANCHOR_DECISION")
            end
        end)
    end
    if type(M.RegisterSearchWidget) == "function" then
        M.RegisterSearchWidget(decision, {
            controlId = "menu2.guided_setup.cooldown_anchor_decision",
            identityKey = "guided_setup.cooldown_anchor_decision",
            controlPath = "guided_setup/cooldown_anchor_decision",
            pageKey = "guided_setup",
            label = Tr("Unitframe Cooldown Manager anchoring"),
            kind = "segment",
            classification = "setting",
            help = Tr("Choose this before moving frames because it changes the anchor used by every Unitframe position."),
        })
    end
    button:SetScript("OnClick", function()
        if BlockedByCombat() then return end
        local status = type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {}
        if type(M.SetMSUFEditModeActive) == "function" then
            M.SetMSUFEditModeActive(not status.active, nil, { source = "guided_tour" })
        end
        Refresh()
    end)
    RegisterGuidedPageButton(button, "edit_mode_toggle", "Open or exit MSUF Edit Mode", "Moves whole MSUF frames and group containers; exiting keeps changes.")
    if type(ctx.AddRefresher) == "function" then ctx:AddRefresher(Refresh) end
    Refresh()
    return math.abs(b.y) + 34
end

local function SummaryCard(builder, T, title, value, body, color)
    local card = builder:Section("", 78)
    if card.title then card.title:SetText("") end
    local number = T.Font(card, "GameFontNormalLarge", tostring(value or 0), color or T.colors.accent)
    number:SetPoint("LEFT", card, "LEFT", 16, 8)
    number:SetWidth(56)
    number:SetJustifyH("CENTER")
    local heading = T.Font(card, "GameFontNormal", Tr(title), T.colors.text)
    heading:SetPoint("TOPLEFT", card, "TOPLEFT", 84, -16)
    local copy = T.Font(card, "GameFontDisableSmall", Tr(body), T.colors.muted)
    copy:SetPoint("TOPLEFT", card, "TOPLEFT", 84, -40)
    SetWrapped(copy, builder.width - 98)
    return card
end

local function BuildFinalReviewPage(ctx, T, W)
    local summary = M.GetGuidedTourSummary()
    local b = W.PageBuilder(ctx)
    Header(b, format(Tr("%s, your setup is ready"), PlayerDisplayName()), "Finishing records the tour as complete and changes nothing else.")
    InfoCard(b, T, "Your guide focus", format(Tr("%s · %s information"), PreferenceLabel(Preference("playstyle", "general")), PreferenceLabel(Preference("informationStyle", "balanced"))), "home", 72)
    SummaryCard(b, T, "Reviewed sections", summary.reviewedSections, format(Tr("%d discovered options were actively reviewed."), summary.reviewedControls), T.colors.ok or T.colors.accent)
    SummaryCard(b, T, "Kept sections", summary.keptSections, format(Tr("%d discovered options were deliberately left as they are."), summary.keptControls), T.colors.accent)
    SummaryCard(b, T, "Skipped sections", summary.skippedSections, format(Tr("%d discovered options remain unchanged after warnings."), summary.skippedControls), summary.skippedSections > 0 and (T.colors.warning or T.colors.warn) or T.colors.muted)

    if #summary.skippedAreas > 0 or #summary.skippedSectionItems > 0 or #summary.skippedItems > 0 then
        local lines, limit = {}, 8
        for i = 1, #summary.skippedAreas do
            if #lines >= limit then break end
            lines[#lines + 1] = "\226\128\162 " .. summary.skippedAreas[i]
        end
        for i = 1, #summary.skippedSectionItems do
            if #lines >= limit then break end
            local item = summary.skippedSectionItems[i]
            lines[#lines + 1] = "\226\128\162 " .. item.stageLabel .. ": " .. item.label
        end
        for i = 1, #summary.skippedItems do
            if #lines >= limit then break end
            local item = summary.skippedItems[i]
            lines[#lines + 1] = "\226\128\162 " .. item.stageLabel .. ": " .. Tr(item.label)
        end
        local detailTotal = #summary.skippedAreas + #summary.skippedSectionItems + #summary.skippedItems
        if detailTotal > #lines then
            lines[#lines + 1] = format(Tr("and %d more skipped items"), detailTotal - #lines)
        end
        InfoCard(b, T, "Skipped areas", table.concat(lines, "\n"), "opt_misc", 58 + (#lines * 15))
    else
        InfoCard(b, T, "Nothing was skipped", "Every guided section was reviewed or deliberately kept as is.", "home", 78)
    end

    local restorePoint = select(2, Invoke(Tour(), "GetRestorePoint"))
    if type(restorePoint) == "table" and type(M.RestoreGuidedTourRestorePoint) == "function" then
        local restoreAlreadyUsed = TourState().restorePointUsedAt ~= nil
        local restoreProfileMismatch = ProfileMismatch()
        local restore = b:Section("", 92)
        if restore.title then restore.title:SetText("") end
        local title = T.Font(restore, "GameFontNormal", Tr(restoreAlreadyUsed and "Starting setup restored" or "Starting setup saved"), T.colors.text)
        title:SetPoint("TOPLEFT", restore, "TOPLEFT", 16, -20)
        title:SetWidth(max(120, b.width - 260))
        title:SetJustifyH("LEFT")
        local copy = T.Font(restore, "GameFontDisableSmall", Tr(restoreAlreadyUsed
            and "The starting profile values are active again. Finish when you are ready."
            or "You can restore the profile state captured before this guided setup."),
            restoreAlreadyUsed and (T.colors.ok or T.colors.accent) or T.colors.muted)
        copy:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        SetWrapped(copy, max(120, b.width - 260))
        local button = T.Button(restore, Tr(restoreAlreadyUsed and "Starting setup restored" or "Restore starting setup"), min(220, max(170, floor(b.width * 0.32))), 28)
        button:SetPoint("RIGHT", restore, "RIGHT", -16, 0)
        button._msuf2SkipHistoryCheckpoint = true
        if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
        local armed = false
        SetButtonEnabled(button, not restoreAlreadyUsed and not restoreProfileMismatch)
        button:SetScript("OnClick", function()
            if restoreAlreadyUsed or ProfileMismatch() or BlockedByCombat() then return end
            if not armed then
                armed = true
                SetButtonText(button, "Confirm restore")
                copy:SetText(Tr("This replaces the current profile values with the setup starting point. Click again to confirm."))
                SetFontColor(copy, T.colors.warning or T.colors.warn or T.colors.muted)
                return
            end
            local point = select(2, Invoke(Tour(), "GetRestorePoint"))
            if type(point) ~= "table" then return end
            Invoke(Tour(), "MarkRestorePointUsed", true)
            local ok, restored = pcall(M.RestoreGuidedTourRestorePoint, point)
            if not ok or restored ~= true then
                Invoke(Tour(), "MarkRestorePointUsed", false)
                armed = false
                SetButtonText(button, "Restore starting setup")
                copy:SetText(Tr("The starting setup could not be restored. Your current values remain active."))
                SetFontColor(copy, T.colors.warning or T.colors.warn or T.colors.muted)
            end
        end)
        RegisterGuidedPageButton(button, "restore_start", "Restore starting setup", "Restores the active profile values captured before guided setup began after a second confirmation.")
    end
    return math.abs(b.y) + 34
end

function M.BuildGuidedSetupPage(ctx)
    local T, W = M.Theme, M.Widgets
    if not (ctx and ctx.wrapper and T and W and type(W.PageBuilder) == "function") then return 240 end
    local stage = CurrentStage()
    if stage.id == "edit_mode" then return BuildEditModePage(ctx, T, W) end
    if stage.id == "final_review" then return BuildFinalReviewPage(ctx, T, W) end
    return BuildMenuBasicsPage(ctx, T, W)
end

M.navPrimaryForKey = type(M.navPrimaryForKey) == "table" and M.navPrimaryForKey or {}
M.navPrimaryForKey.guided_setup = "home"
if type(M.RegisterPage) == "function" then
    M.RegisterPage("guided_setup", { title = "Guided Setup", build = M.BuildGuidedSetupPage, version = 1 })
end
