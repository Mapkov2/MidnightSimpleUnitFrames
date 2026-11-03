-- Group preview selection owner.
local _, MSUF = ...
local M = MSUF.MSUF2
local RequireFields = M.PreviewContracts.RequireFields
local T = M.Theme
local Specs = M.GroupPreviewSpecs
local PreviewHelpers = M.PreviewHelpers
local Fallbacks = M.Fallbacks
local WHITE8X8 = Specs.WHITE8X8
local Tr = M.Tr
local floor = math.floor
local Chrome = RequireFields("GroupSelection.Chrome", M.GroupPreviewChrome, "ApplyGroupPreviewFlatBackdrop RegisterGroupPreviewControl UpdateHint")
local ApplyGroupPreviewFlatBackdrop = Chrome.ApplyGroupPreviewFlatBackdrop
local RegisterGroupPreviewControl = Chrome.RegisterGroupPreviewControl
local UpdateHint = Chrome.UpdateHint
local Model = RequireFields("GroupSelection.Model", M.GroupPreviewModel,
    "Conf CurrentScope CurrentSpellPlaced CurrentStatusSpec MockPowerHeight PreviewScopeLabel Round StatusSpecs")
local Conf = Model.Conf
local CurrentScope = Model.CurrentScope
local CurrentSpellPlaced = Model.CurrentSpellPlaced
local CurrentStatusSpec = Model.CurrentStatusSpec
local MockPowerHeight = Model.MockPowerHeight
local PreviewScopeLabel = Model.PreviewScopeLabel
local Round = Model.Round
local StatusSpecs = Model.StatusSpecs

local ExportPublic = MSUF.ExportPublic
local HANDLE_FALLBACK_COLOR = { 0.70, 0.80, 1.00 }
local NudgeStep = PreviewHelpers.NudgeStep or Fallbacks.One
local SECTION_PAGE, PAGE_FOCUS = Specs.SECTION_PAGE, Specs.PAGE_FOCUS
local function PageForGFSection(sectionKey)
    return SECTION_PAGE[sectionKey or ""]
end
local function PreviewFocusForPage(pageKey)
    local focus = M.gfPreviewFocus
    if focus and PageForGFSection(focus) == pageKey then return focus end
    return PAGE_FOCUS[pageKey]
end
-- The aura lane each aura section drives; the EM2 focus request names the same lane.
local SECTION_AURA_LANE = { buffs = "buff", debuffs = "debuff", externals = "externals" }
local SCOPE_PAGE_KEY = { raid = "gf_raid", mythicraid = "gf_mythicraid" }
local function OpenGFSection(sectionKey)
    M.gfPreviewFocus = sectionKey
    local pageKey = PageForGFSection(sectionKey)
    if not (pageKey and M.SelectPage) then return false end
    local lane = SECTION_AURA_LANE[sectionKey]
    local scope = CurrentScope()
    if M.SetMenuStateValue then
        M.SetMenuStateValue("gfScope", scope)
        if pageKey == "gf_auras" then
            M.SetMenuStateValue("auraStyleGFScope", scope == "mythicraid" and "raid" or scope)
            if lane then
                M.gfAuraLaneSelection = M.gfAuraLaneSelection or {}
                M.gfAuraLaneSelection[scope] = lane
                M.gfAuraToolSelection = M.gfAuraToolSelection or {}
                local tools = M.gfAuraToolSelection[scope]
                if type(tools) ~= "table" then
                    tools = {}
                    M.gfAuraToolSelection[scope] = tools
                end
                tools[lane] = "layout"
                if lane ~= "externals" then M.SetMenuStateValue("auraStyleGFLane", lane) end
            end
        end
    end
    if sectionKey == "portrait" then
        M.unitPortraitTabSelection = M.unitPortraitTabSelection or {}
        M.unitPortraitTabSelection.gf_party = "placement"
    elseif sectionKey == "sicons" then
        M.gfStatusIconTabSelection = M.gfStatusIconTabSelection or {}
        M.gfStatusIconTabSelection[scope] = "basic"
    end
    ExportPublic("MSUF_EM2_MenuFocusRequest", {
        key = SCOPE_PAGE_KEY[scope] or "gf_party",
        component = sectionKey,
        lane = lane,
        pageKey = pageKey,
        sectionId = lane and "auras" or sectionKey,
        source = "group-preview",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    })
    -- The scope/lane/tool view retains its bound controls across preview routes.
    return M.SelectPage(pageKey) ~= false
end
local function HandleText(handle)
    if not handle then return "Group preview" end
    local label = handle._label
    local text = label and label.GetText and label:GetText()
    if text and text ~= "" then return text end
    local previewText = handle._previewText
    if previewText and previewText ~= "" then return previewText end
    return handle._key or "Group preview"
end
local GFTextFocus = (M.GroupPreviewTextFocus and M.GroupPreviewTextFocus.Install and M.GroupPreviewTextFocus.Install({
    CurrentScope = CurrentScope,
    Conf = Conf,
})) or {}
local CurrentTextKind = GFTextFocus.CurrentTextKind
local TextOffsetKeys = GFTextFocus.TextOffsetKeys
local TextLabel = GFTextFocus.TextLabel
local function SpellPlacedForHandle(handle, conf)
    local item = handle and handle._cfgSpellItem
    if type(item) ~= "table" then return nil end
    local specKey, auraName = item.specKey, item.auraName
    local specs = conf and conf.spellIndicators and conf.spellIndicators.specs
    local cfg = specKey and auraName and type(specs) == "table"
        and type(specs[specKey]) == "table" and specs[specKey][auraName] or nil
    if type(cfg) == "table" and type(cfg.placed) == "table" then return cfg.placed end
    if type(handle._msufSpellIndicatorPlaced) == "table" then return handle._msufSpellIndicatorPlaced end
    return nil
end
local function HandleOffsets(handle)
    if not handle then return nil end
    local conf = Conf(CurrentScope()) or {}
    if handle._cfgGroup then
        local auras = conf.auras or {}
        local cfg = auras[handle._cfgGroup] or {}
        if handle._cfgTrackedBuff then
            return cfg.trackedAnchor or "TOPLEFT", tonumber(cfg.trackedX) or 0, tonumber(cfg.trackedY) or 0
        end
        return cfg.anchor, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    elseif handle._cfgStatus then
        local spec = handle._statusSpec or CurrentStatusSpec()
        if not spec then return nil end
        return conf[spec.anchor] or spec.defaultAnchor, tonumber(conf[spec.x]) or 0, tonumber(conf[spec.y]) or 0
    elseif handle._cfgSpell then
        -- Dynamic preview handles own an exact spec+aura identity. Never let
        -- their coordinates fall back to whichever spell the menu happened
        -- to select previously.
        local cfg
        if handle._cfgSpellItem then
            cfg = SpellPlacedForHandle(handle, conf) or {}
        else
            cfg = CurrentSpellPlaced(CurrentScope()) or {}
        end
        return cfg.anchor, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    elseif handle._cfgDispelSymbol then
        return "DISPEL", tonumber(conf.dispelSymbolX) or 0, tonumber(conf.dispelSymbolY) or 0
    elseif handle._cfgPortrait then
        return "PORTRAIT", tonumber(conf.portraitOffsetX) or 0, tonumber(conf.portraitOffsetY) or 0
    elseif handle._cfgPower then
        -- Fixed runtime anchor (TOP -> frame BOTTOM); only the offsets move.
        return "TOP", tonumber(conf.detachedPowerBarOffsetX) or 0, tonumber(conf.detachedPowerBarOffsetY) or -4
    elseif handle._cfgText then
        local kind = handle._cfgTextKind or CurrentTextKind()
        local slot = handle._cfgTextSlot
        local xKey, yKey = TextOffsetKeys(kind, slot)
        return (kind == "name" and (conf.nameAnchor or "LEFT") or TextLabel(kind, slot)), tonumber(conf[xKey]) or 0, tonumber(conf[yKey]) or 0
    end
    return nil
end
local function DefaultHandleOffsets(handle)
    if not handle then return 0, 0 end
    local gf, scope = MSUF.GF, CurrentScope()
    local source, xKey, yKey
    if handle._cfgGroup then
        local auras = gf.GetDefault(scope, "auras") or {}
        source = auras[handle._cfgGroup] or {}
        xKey, yKey = "x", "y"
        if handle._cfgTrackedBuff then xKey, yKey = "trackedX", "trackedY" end
    elseif handle._cfgStatus then
        local spec = handle._statusSpec or CurrentStatusSpec()
        if spec then xKey, yKey = spec.x, spec.y end
    elseif handle._cfgDispelSymbol then xKey, yKey = "dispelSymbolX", "dispelSymbolY"
    elseif handle._cfgPortrait then xKey, yKey = "portraitOffsetX", "portraitOffsetY"
    elseif handle._cfgPower then xKey, yKey = "detachedPowerBarOffsetX", "detachedPowerBarOffsetY"
    elseif handle._cfgText then
        xKey, yKey = TextOffsetKeys(handle._cfgTextKind or CurrentTextKind(), handle._cfgTextSlot)
    end
    if not xKey then return 0, 0 end
    if source then return tonumber(source[xKey]) or 0, tonumber(source[yKey]) or 0 end
    return tonumber(gf.GetDefault(scope, xKey)) or 0, tonumber(gf.GetDefault(scope, yKey)) or 0
end
--- The hint line is a message surface, nothing else. Selected element, offsets
--- and actions live in the selection bar, the full control list behind the ?
--- button, so the text no longer changes shape per selection.
--- The selected element is user intent, but `_selectedHandle` is a live frame
--- pointer on a box whose lifecycle is suspend/resume: one shared native box
--- serves every Group preview page, and Group sections open on *other* pages, so
--- opening an element's settings suspends the box mid-click. Storing the
--- selection only as that pointer therefore destroyed the intent on every
--- suspend, and the selection bar resumed reading "No element selected" - no
--- X/Y, no axis pulse. Unit frames never showed it because their sections open
--- on the page their preview already sits on, so nothing suspends.
---
--- Suspend hands the key over, resume takes it back. Both halves are exact
--- inverses and neither knows anything about navigation.
local function SuspendSelection(box)
    local handle = box._selectedHandle
    if handle and handle._key ~= nil then box._msufGFSuspendedSelectionKey = handle._key end
    box._selectedHandle = nil
end
local function ResumeSelection(box)
    if box._msufGFSuspendedSelectionKey == nil then return nil end
    if box._selectedHandle then
        -- Only a *different* element retires the key. Suspending stops the drag
        -- first, which refreshes while the selection it is about to hand over is
        -- still live, so retiring on any live selection would drop the key one
        -- step before the resume could ever run.
        if box._selectedHandle._key ~= box._msufGFSuspendedSelectionKey then
            box._msufGFSuspendedSelectionKey = nil
        end
        return box._selectedHandle
    end
    -- Mid-transition the box is already invisible while its handles still carry
    -- their own Shown flag. Resuming there would spend the key on the page that
    -- is being torn down.
    if box.IsVisible and not box:IsVisible() then return nil end
    local handle = box._handles and box._handles[box._msufGFSuspendedSelectionKey]
    if not handle or handle._locked then return nil end
    if handle.IsVisible and not handle:IsVisible() then return nil end
    box._msufGFSuspendedSelectionKey = nil
    -- A plain re-select: the menu-state side effects of a real click (aura lane,
    -- status entry, text tab) were written when it was clicked, and the keyboard
    -- focus belongs to whatever the resumed page opened.
    box._selectedHandle = handle
    return handle
end
local function RefreshHandleSelection(box)
    if not box then return end
    local selected = box._selectedHandle
    local guidesOn = M.gfPreviewLayerVisible and M.gfPreviewLayerVisible.guides == true
    if selected and selected.IsShown and not selected:IsShown() then
        selected = nil
        box._selectedHandle = nil
    end
    local resumed = ResumeSelection(box)
    if resumed then selected = resumed end
    if PreviewHelpers.RefreshSelectedLayerButtons then
        PreviewHelpers.RefreshSelectedLayerButtons(box, selected, "_layerButtons")
    end
    local handles = box._handleList or {}
    for i = 1, #handles do
        local handle = handles[i]
        if handle then
            local color = handle._color or HANDLE_FALLBACK_COLOR
            local isSelected = handle == selected
            local isHover = handle._hovering == true
            local isDrag = handle._dragging == true
            local visualState = (guidesOn and 1 or 0) + (isSelected and 2 or 0) + (isHover and 4 or 0)
                + (isDrag and 8 or 0) + (handle._locked and 16 or 0) + (handle._cfgText and 32 or 0)
            local r, g, b = color[1], color[2], color[3]
            if handle._msufGFSelectionVisualState ~= visualState
                or handle._msufGFSelectionVisualR ~= r
                or handle._msufGFSelectionVisualG ~= g
                or handle._msufGFSelectionVisualB ~= b then
                handle._msufGFSelectionVisualState = visualState
                handle._msufGFSelectionVisualR = r
                handle._msufGFSelectionVisualG = g
                handle._msufGFSelectionVisualB = b
                if handle._selectFill then handle._selectFill:SetColorTexture(r, g, b, guidesOn and (isDrag and 0.18 or (isHover and 0.14 or 0)) or 0) end
                if handle._selectBorder then
                    handle._selectBorder:SetShown(guidesOn and (isSelected or isHover))
                    handle._selectBorder:SetBackdropBorderColor(r, g, b, isSelected and 0.70 or 0.72)
                end
                if handle.SetBackdropBorderColor then
                    local borderAlpha = guidesOn and (isSelected and 0.70 or (isHover and 0.85 or (handle._locked and 0.55 or 0.95))) or 0
                    if handle._cfgText then borderAlpha = 0 end
                    handle:SetBackdropBorderColor(r, g, b, borderAlpha)
                end
                if handle.SetBackdropColor and not handle._cfgText then
                    local alpha = guidesOn and 0.42 or 0
                    handle:SetBackdropColor(r * 0.12, g * 0.12, b * 0.12, alpha)
                end
                if handle._cfgText and handle.SetBackdropColor then handle:SetBackdropColor(0, 0, 0, 0) end
                if handle._msuf2SettingsGear then handle._msuf2SettingsGear:SetShown(guidesOn and isSelected) end
            end
        end
    end
    UpdateHint(box)
end
local Helpers = {
    CurrentScope = CurrentScope, Conf = Conf, PreviewScopeLabel = PreviewScopeLabel,
    SetTextMoveTogether = GFTextFocus.SetTextMoveTogether or Fallbacks.Noop,
    CurrentTextKind = CurrentTextKind, TextOffsetKeys = TextOffsetKeys,
    NudgeStep = NudgeStep, StatusSpecs = StatusSpecs, TextLabel = TextLabel, PreviewFocusForPage = PreviewFocusForPage,
    MockPowerHeight = MockPowerHeight, TextMovesTogether = GFTextFocus.TextMovesTogether or Fallbacks.True,
    PlaceHandleAroundRegions = GFTextFocus.PlaceHandleAroundRegions or Fallbacks.False,
    NormalizeTextFocusKind = GFTextFocus.NormalizeTextFocusKind or Fallbacks.Identity,
    NormalizeTextFocusSlot = GFTextFocus.NormalizeTextFocusSlot or Fallbacks.Identity,
    ApplyTextFocus = GFTextFocus.ApplyTextFocus or Fallbacks.Noop,
}
local GroupSelection = {}
function GroupSelection.Theme()
    return T
end
function GroupSelection.HandleList(owner)
    return owner._handleList
end
-- Locked handles are shown but not movable, so they are not a
-- selectable row or a Tab stop either.
function GroupSelection.IsPlaced(handle)
    if handle._locked then return false end
    return not (handle.IsShown and not handle:IsShown())
end
function GroupSelection.Read(owner, handle)
    -- Name X/Y are anchor-local offsets. Reading the rendered handle
    -- center here makes X=0 mean "center the glyphs in the frame", which
    -- silently rewrites LEFT/RIGHT/TOP anchors into an apparent CENTER.
    -- Keep every other Group handle in the shared rendered-coordinate
    -- space; only Name mirrors the stored offset contract used by its
    -- anchor control and renderer.
    if handle and handle._cfgText == true and handle._cfgTextKind == "name" then
        local _, rawX, rawY = HandleOffsets(handle)
        return Round(tonumber(rawX) or 0), Round(tonumber(rawY) or 0)
    end
    local selection = M.PreviewSelectionBar
    local x, y
    if selection and selection.ReadRenderedCoordinates then
        x, y = selection.ReadRenderedCoordinates(handle, owner and owner._mock,
            owner and (owner._mockScale or (owner._mock and owner._mock._previewScale)) or 1)
    end
    if x == nil or y == nil then
        local _, rawX, rawY = HandleOffsets(handle)
        x, y = rawX, rawY
    end
    return Round(tonumber(x) or 0), Round(tonumber(y) or 0)
end
-- NudgeHandleExact remains the audited storage writer. Name uses its
-- anchor-local stored offsets; every other handle translates exact
-- entry from the shared rendered coordinate space.
function GroupSelection.Nudge(owner, handle, dx, dy)
    if dx == 0 and dy == 0 then return true end
    if not owner.NudgeHandleExact then return false end
    return owner:NudgeHandleExact(handle._key, dx, dy) == true
end
function GroupSelection.WriteStored(owner, handle, x, y)
    local _, curX, curY = HandleOffsets(handle)
    return GroupSelection.Nudge(owner, handle, (tonumber(x) or 0) - (tonumber(curX) or 0), (tonumber(y) or 0) - (tonumber(curY) or 0))
end
function GroupSelection.Write(owner, handle, x, y)
    if handle and handle._cfgText == true and handle._cfgTextKind == "name" then
        return GroupSelection.WriteStored(owner, handle, x, y)
    end
    local curX, curY = GroupSelection.Read(owner, handle)
    return GroupSelection.Nudge(owner, handle, (tonumber(x) or curX) - curX, (tonumber(y) or curY) - curY)
end
function GroupSelection.Reset(owner, handle)
    return GroupSelection.WriteStored(owner, handle, DefaultHandleOffsets(handle))
end
function GroupSelection.NudgeDelta(owner, dx, dy)
    local handle = owner._selectedHandle
    if not (handle and owner.NudgeHandleExact) then return false end
    return owner:NudgeHandleExact(handle._key, dx, dy) == true
end
-- Mirrors the fallbacks ReadHandlePositionExact already treats as
-- each handle type's default.
function GroupSelection.DefaultOffsets(_, handle)
    return DefaultHandleOffsets(handle)
end
function GroupSelection.OpenSettings(_, handle)
    local open = M.GroupPreview and M.GroupPreview.OpenSection
    if not (handle._sectionKey and open) then return false end
    open(handle._sectionKey)
    return true
end
-- Selection bar edit field, its axis, Search path, label, route note and setting key: the shared X/Y
-- fields are pinned to the Party Portrait handle for Search.
GroupSelection.OffsetRows = {
    { "editX", "x", "selection.portrait_offset_x", "Party Portrait X Offset",
        "The shared Preview X field is pinned to the Party Portrait handle for this exact Search route.",
        "gf_party.portraitOffsetX" },
    { "editY", "y", "selection.portrait_offset_y", "Party Portrait Y Offset",
        "The shared Preview Y field is pinned to the Party Portrait handle for this exact Search route.",
        "gf_party.portraitOffsetY" },
}
function GroupSelection.Create(box, stage, selectHandle)
    local selectionAPI = M.PreviewSelectionBar
    selectionAPI.Create(box, {
        Tr = Tr,
        Theme = GroupSelection.Theme,
        ApplyBackdrop = ApplyGroupPreviewFlatBackdrop,
        Round = Round,
        HandleList = GroupSelection.HandleList,
        HandleLabel = HandleText,
        IsPlaced = GroupSelection.IsPlaced,
        ReadOffsets = GroupSelection.Read,
        WriteOffsets = GroupSelection.Write,
        ResetOffsets = GroupSelection.Reset,
        NudgeDelta = GroupSelection.NudgeDelta,
        DefaultOffsets = GroupSelection.DefaultOffsets,
        OpenSettings = GroupSelection.OpenSettings,
        SelectHandle = function(_, handle) return selectHandle(handle) end,
        UpdateHint = UpdateHint,
    })
    selectionAPI.CreatePicker(box, stage)
    local registerControl = box._msuf2RegisterGroupPreviewControl or RegisterGroupPreviewControl
    registerControl(box._msuf2ElementPicker, "element_picker", "Group Preview Element Picker", "button", "ephemeral")
    local selectionBar = box._msuf2SelectionBar
    if not selectionBar then return end
    -- Exact offset rows belong to the Group Frames pages; a preview inside
    -- another page (each Colors category) keeps its fields ephemeral.
    local offsetClass = tostring(M.activeKey or ""):match("^gf_") and "setting" or "ephemeral"
    local rows = GroupSelection.OffsetRows
    for i = 1, #rows do
        local row = rows[i]
        local edit = selectionBar[row[1]]
        selectionAPI.BindExactOffsetSearchTarget(edit, box, "portrait")
        registerControl(edit, row[3], row[4], "textinput", offsetClass, {
            searchRouteDisposition = "dynamic",
            searchRouteDispositionReason = row[5],
            searchSettingKeys = { row[6] },
            command = selectionAPI.BuildExactOffsetCommand(box, "portrait", row[2], {
                previewSurface = "group", previewScope = "party",
            }),
        })
    end
    registerControl(selectionBar.resetButton, "selection.reset", "Reset selected preview element offset", "button", "ephemeral")
    registerControl(selectionBar.openButton, "selection.open_settings", "Open selected preview element settings", "button", "ephemeral")
end

M.GroupPreviewSelection = {
    OpenGFSection = OpenGFSection,
    HandleText = HandleText,
    HandleOffsets = HandleOffsets,
    SuspendSelection = SuspendSelection,
    RefreshHandleSelection = RefreshHandleSelection,
    Helpers = Helpers,
    GroupSelection = GroupSelection,
}
