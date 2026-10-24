--- Group preview handle, drag, and nudge helpers.
---
--- Native owns the preview host. This module owns interactive handles and the
--- save/write behavior behind drag and keyboard nudges.
local _, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Menu2/GroupPreview_Handles"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local Handles = M.GroupPreviewHandles or {}
M.GroupPreviewHandles = Handles
local Fallbacks = M.Fallbacks or {}
local max = math.max
local HANDLE_CLICK_DRAG_THRESHOLD = 3
local HANDLE_LABEL_HIT_HEIGHT = 14
local function ResolveTextDragPixelDelta(round, current, startValue, scale, endpointBias)
    endpointBias = tonumber(endpointBias) or 0
    return round(((tonumber(current) or 0) + endpointBias) * scale)
        - round(((tonumber(startValue) or 0) + endpointBias) * scale)
end
Handles._ResolveTextDragPixelDelta = ResolveTextDragPixelDelta
local function FallbackHandleText(handle)
    return handle and (handle._previewText or handle._key) or "Handle"
end
-- Install forwards each of these from deps onto the shared state, using the fallback when deps lacks it.
local HANDLE_DEPENDENCIES = {
    { "TR", Fallbacks.Identity }, { "Round", Fallbacks.Round }, { "ResolveAnchor", Fallbacks.Center },
    { "PointOffset", Fallbacks.ZeroPair }, { "HandleOffset", Fallbacks.ZeroPair }, { "CurrentStatusSpec", Fallbacks.Nil },
    { "CurrentSpellConfig", Fallbacks.Nil }, { "HandleText", FallbackHandleText }, { "HandleOffsets", Fallbacks.Nil },
    { "UpdateHint", Fallbacks.Noop }, { "RefreshHandleSelection", Fallbacks.Noop }, { "StatusLabel", Fallbacks.Status },
    { "StartPan", Fallbacks.False }, { "StopPan", Fallbacks.Noop }, { "ZoomWheel", Fallbacks.Noop },
}
local SPELL_DROP_ANCHOR_FRAC = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
-- A handle takes its universal Layer from its section; the tracked buff row shares the buffs section but has its own layer.
local GROUP_HANDLE_LAYER_BY_KEY = { trackedBuff = "trackedBuff" }
local GROUP_SECTION_LAYER = {
    text = "text", power = "power", portrait = "portrait", si = "si", sicons = "status",
    buffs = "buff", debuffs = "debuff", externals = "external", dispel = "dispelSymbol", dispelSymbol = "dispelSymbol",
}
-- Handle kinds whose offsets are one X/Y key pair of the group config, with the Y value used while it is unset.
local FIXED_OFFSET_KINDS = {
    -- The symbol row keeps its configured anchor; dragging edits the same X/Y offsets shown by Preview. In "one per dispel type"
    -- mode the handle spans the whole row, so the stored offset stays the row origin and the per-type steps are re-derived on render.
    { "_cfgDispelSymbol", "dispelSymbolX", "dispelSymbolY", 0 },
    -- Portrait placement keeps its configured anchor/side. Dragging only edits the X/Y offsets owned by Preview.
    { "_cfgPortrait", "portraitOffsetX", "portraitOffsetY", 0 },
    -- The drag preserved the runtime's TOP -> frame BOTTOM anchor, so the final point offsets are the detached offsets in preview px.
    { "_cfgPower", "detachedPowerBarOffsetX", "detachedPowerBarOffsetY", -4 },
}
-- Per-drag state written by StartHandleDrag and cleared when the drag ends.
local DRAG_STATE_KEYS = {
    "_dragging", "_dragPoint", "_dragRelTo", "_dragRelPoint", "_dragStartX", "_dragStartY", "_dragCfgStartX", "_dragCfgStartY",
    "_dragEndpointBiasX", "_dragEndpointBiasY", "_dragCursorX", "_dragCursorY", "_dragScale", "_suppressSettingsOnRelease", "_didDragMove",
}
-- Region pools every aura handle keeps, one entry per pooled icon.
local ICON_POOL_KEYS = { "_icons", "_iconSwipes", "_iconBorders", "_iconStacks", "_iconTimers", "_iconDurationBars" }
-- Preview font strings that paint a text handle when H.TextRegions has no answer: the slot picks one, no slot takes all three.
local TEXT_REGION_KEYS = {
    name = { "_nameFS" },
    hp = { "_hpLeftFS", "_hpCenterFS", "_hpRightFS" },
    power = { "_powerLeftFS", "_powerCenterFS", "_powerRightFS" },
}
local TEXT_REGION_SLOT = { left = 1, center = 2, right = 3 }
local TEXT_NAME_COLOR, TEXT_HP_COLOR, TEXT_POWER_COLOR = { 0.30, 0.66, 1.00 }, { 0.25, 0.90, 0.42 }, { 0.95, 0.72, 0.18 }
-- Text handles in creation order: box._textHandles key, handle key, label, color, text kind, slot (nil = the whole group).
local TEXT_HANDLES = {
    { "name", "nameText", "NAME", TEXT_NAME_COLOR, "name" },
    { "hpGroup", "hpText", "HP", TEXT_HP_COLOR, "hp" },
    { "hpLeft", "hpTextLeft", "HP L", TEXT_HP_COLOR, "hp", "left" },
    { "hpCenter", "hpTextCenter", "HP C", TEXT_HP_COLOR, "hp", "center" },
    { "hpRight", "hpTextRight", "HP R", TEXT_HP_COLOR, "hp", "right" },
    { "powerGroup", "powerText", "POWER", TEXT_POWER_COLOR, "power" },
    { "powerLeft", "powerTextLeft", "PWR L", TEXT_POWER_COLOR, "power", "left" },
    { "powerCenter", "powerTextCenter", "PWR C", TEXT_POWER_COLOR, "power", "center" },
    { "powerRight", "powerTextRight", "PWR R", TEXT_POWER_COLOR, "power", "right" },
}
-- Aura lane, resource bar, portrait and dispel-symbol handles in creation order (the status and spell handles follow).
-- w/h default to 86x34, stage parents a handle on the preview stage, pool is the number of pooled aura icons and
-- fields are the flags the drag, nudge and render code read from the handle.
local LAYER_HANDLES = {
    { slot = "buffHandle", key = "buff", section = "buffs", color = { 0.36, 0.79, 0.36 }, label = "BUFFS", pool = 6,
        fields = { _cfgGroup = "buff" } },
    { slot = "trackedBuffHandle", key = "trackedBuff", section = "buffs", color = { 0.62, 0.78, 1.00 }, label = "TRACKED", pool = 4,
        fields = { _cfgGroup = "buff", _cfgTrackedBuff = true, _previewText = "Tracked Buff Icons" } },
    { slot = "debuffHandle", key = "debuff", section = "debuffs", color = { 0.89, 0.29, 0.29 }, label = "DEBUFFS", pool = 6,
        fields = { _cfgGroup = "debuff" } },
    { slot = "externalHandle", key = "external", section = "externals", color = { 0.30, 0.72, 1.00 }, label = "EXTERNAL", pool = 2,
        fields = { _cfgGroup = "externals", _openSettingsOnRightClick = true } },
    -- Resource bar handle. Live parity: only the detached bar owns free
    -- offsets (the embedded bar's texture cannot move on the live frame), so
    -- the render locks this handle while the bar is embedded; a simple click
    -- still opens its owning settings section like any other layer.
    { slot = "powerBarHandle", key = "powerBar", section = "power", color = { 0.30, 0.62, 0.98 }, label = "POWER", h = 16,
        fields = { _cfgPower = true, _previewText = "Resource Bar" } },
    -- Attached portraits can sit completely outside the mock frame. Keep their
    -- mouse handle on the preview stage so WoW does not clip hit-testing to
    -- the mock parent's bounds; rendering/offsets remain anchored to the mock.
    { slot = "portraitHandle", key = "portrait", section = "portrait", color = { 0.90, 0.42, 1.00 }, label = "PORTRAIT", w = 36, h = 36,
        stage = true, fields = { _cfgPortrait = true, _previewText = "Portrait" } },
    -- Dispel-type symbol row. Like the portrait it can sit outside the mock
    -- frame, so its mouse handle lives on the preview stage; rendering and
    -- offsets stay anchored to the mock. Five icon slots: one per dispel type in
    -- "one per dispel type" mode, of which only the first is used in TOP mode.
    { slot = "dispelSymbolHandle", key = "dispelSymbol", section = "dispelSymbol", color = { 0.30, 0.80, 1.00 }, label = "DISPEL",
        w = 44, h = 20, stage = true, pool = 5, fields = { _cfgDispelSymbol = true, _previewText = "Dispel Symbol" } },
}
local SPELL_HANDLE = { slot = "spellHandle", key = "si", section = "si", color = { 0.69, 0.50, 0.88 }, label = "SPELL", w = 44, h = 44,
    pool = 1, fields = { _cfgSpell = true } }
-- What Handles.Install returns for the group preview render layer.
local HANDLE_BUNDLE_KEYS = {
    "buffHandle", "trackedBuffHandle", "debuffHandle", "externalHandle", "powerBarHandle", "portraitHandle", "dispelSymbolHandle",
    "statusHandles", "spellHandle", "SelectHandle", "NudgeHandlePosition", "AddIconPool", "StopHandleDrag",
}

local function InteractionLevel(ns, mock, extra)
    local core = ns.UFPreviewCore
    if core and type(core.InteractionFrameLevel) == "function" then
        return core.InteractionFrameLevel(mock, extra)
    end
    return ((mock.GetFrameLevel and mock:GetFrameLevel()) or 0) + 140 + (tonumber(extra) or 0)
end
-- Cold paths only (scripted nudge, spell drop, release, text focus); the per-frame drag and key-repeat nudge paths
-- below keep these checks inline so they add no Lua call.
local function ManagerCombatLocked(M)
    return type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked()
end
local function RequestBoxRefresh(box, reason)
    if box.RequestRefresh then
        box:RequestRefresh(reason)
    elseif box.Refresh then
        box:Refresh()
    end
end
-- Points the Spell Indicators page at an aura. Multi-spec selection owns the aura dropdown namespace: switch it
-- before recording the aura, otherwise a spell from spec B is written under the previously selected spec A.
local function SelectSpellAura(M, scope, si, specKey, auraName)
    if si and si.spec == "multi" then
        M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
        M.gfSpellMultiSpecSelection[scope] = specKey
    end
    local gp = M.GroupPage or {}
    if type(gp.SetCurrentSpellAura) == "function" then
        gp.SetCurrentSpellAura(scope, auraName, specKey)
    else
        M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
        M.gfSpellIndicatorSelection[scope] = auraName
    end
end
-- The config keys (X, Y, and the Y value while unset) of a handle kind that stores its offsets directly.
local function FixedOffsetKeys(handle)
    for i = 1, #FIXED_OFFSET_KINDS do
        local kind = FIXED_OFFSET_KINDS[i]
        if handle[kind[1]] then return kind[2], kind[3], kind[4] end
    end
end
local function MirrorTextRegions(m, kind, slot)
    local keys = TEXT_REGION_KEYS[kind]
    if not keys then return nil end
    local index = #keys == 1 and 1 or TEXT_REGION_SLOT[slot]
    if index then return { m[keys[index]] } end
    return { m[keys[1]], m[keys[2]], m[keys[3]] }
end
-- Capture every point so grouped HP/Power regions and their focus frame
-- retain their complete geometry during the temporary drag preview.
local function CaptureTextDragFrame(list, frame)
    if not (list and frame and frame.GetPoint and frame.ClearAllPoints and frame.SetPoint) then return end
    if frame.IsShown and not frame:IsShown() then return end
    local count = (frame.GetNumPoints and frame:GetNumPoints()) or 1
    if count < 1 then return end
    local points
    for i = 1, count do
        local point, relTo, relPoint, xOfs, yOfs = frame:GetPoint(i)
        if point then
            points = points or {}
            points[#points + 1] = { point = point, relTo = relTo, relPoint = relPoint, x = xOfs or 0, y = yOfs or 0 }
        end
    end
    if not points then return end
    list[#list + 1] = { frame = frame, points = points }
end
-- Group Aura lanes only render in the CUSTOM renderer: moving one has to show.
local function AuraLaneConf(conf, group)
    conf.auras = conf.auras or {}
    conf.auras.renderer = "CUSTOM"
    conf.auras[group] = conf.auras[group] or {}
    return conf.auras[group]
end
-- The pooled region at index i, created from parent[method](parent, nil, layer) the first time.
local function PooledRegion(pool, i, parent, method, layer)
    local region = pool[i]
    if not region then
        region = PixelLayoutRegion(parent[method](parent, nil, layer))
        pool[i] = region
    end
    return region
end
-- Pooled aura texts get the preview font once and stay hidden until a render shows them.
local function PreparePreviewText(T, fs, drawLayer)
    if fs.SetFont and fs._msufGFPreviewFont ~= true then
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE")
        fs._msufGFPreviewFont = true
    end
    if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY", drawLayer) end
    fs:Hide()
end
-- Runtime AuraButtons keep the duration bar, cooldown swipe and text on
-- separate child frames inside the selected universal Layer slot.  The
-- preview used to create every region directly on the handle, which
-- made all of them inherit the icon's base level and let overlapping
-- text lie about the real runtime ordering.
local function EnsureIconDetailLayer(handle, key)
    local layer = handle[key]
    if not layer then
        layer = PixelLayoutRegion(CreateFrame("Frame", nil, handle))
        layer:SetAllPoints(handle)
        layer:EnableMouse(false)
        if layer.SetMouseMotionEnabled then layer:SetMouseMotionEnabled(false) end
        handle[key] = layer
    end
    return layer
end
-- A preview gear is a search action on the Group Frames pages only; inside
-- another page (each Colors category) it stays navigation, as on units.
local function GroupGearClassification()
    return tostring(M.activeKey or ""):match("^gf_") and "action" or "navigation"
end
-- Registers the handle as a preview control and, when the helper exists, its open-settings gear.
local function RegisterHandleControls(st, handle, key, label)
    local box, M, T, Tr, PreviewHelpers = st.box, st.M, st.T, st.TR, st.PreviewHelpers
    local SelectHandle, OpenHandleSettings, RegisterPreviewControl = st.SelectHandle, st.OpenHandleSettings, st.RegisterPreviewControl
    handle._msuf2CommandAction = {
        kind = "button",
        historyMode = "none",
        interaction = "preview.handle.select",
        previewSurface = "group",
        previewHandleKey = key,
        previewScope = st.H.CurrentScope(),
        set = function()
            if handle.IsShown and not handle:IsShown() then return false end
            SelectHandle(handle)
            return box._selectedHandle == handle
        end,
    }
    RegisterPreviewControl(handle, "handle." .. tostring(key), label or key, "button", "ephemeral")
    if not PreviewHelpers.EnsurePreviewHandleGear then return end
    local gear = PreviewHelpers.EnsurePreviewHandleGear(handle, {
        T = T,
        Tr = Tr,
        shown = false,
        openSettings = OpenHandleSettings,
    })
    if not gear then return end
    gear._msuf2GroupPreviewOpenCommand = gear._msuf2GroupPreviewOpenCommand or {
        kind = "button",
        historyMode = "none",
        set = function() return OpenHandleSettings(handle) end,
    }
    RegisterPreviewControl(gear, "handle." .. tostring(key) .. ".open_settings",
        M.Format("Open %s settings", M.Tr(label or key)), "button", GroupGearClassification(), {
            historyMode = "none",
            help = "Opens the exact Group Frames settings section for this preview element.",
            command = gear._msuf2GroupPreviewOpenCommand,
        })
end

--- Install stages. Each binds one slice of the handle behaviour onto the shared
--- per-install state table; Handles.Install runs them in the original order.
local Stage = {}

function Handles.Install(box, deps)
    if not box then return nil end
    deps = deps or {}
    local M = deps.M or M
    local ns = deps.MSUF or MSUF
    -- The old monolith closed over the native preview mock. After splitting the
    -- file, bind it explicitly so preview handles never fall back to UIParent.
    local mock = box._mock or box
    local dragParent = box._stage or box
    local st = {
        box = box, M = M, MSUF = ns, mock = mock, dragParent = dragParent,
        H = deps.H or {}, T = deps.T or M.Theme or {}, PreviewHelpers = M.PreviewHelpers or {},
        RegisterPreviewControl = deps.RegisterPreviewControl,
        OpenSection = deps.OpenSection or (M.GroupPreview and M.GroupPreview.OpenSection),
        WHITE8X8 = deps.WHITE8X8 or "Interface\\Buttons\\WHITE8X8",
        AuraDurationBarColor = ns.MSUF_Auras3.GetDurationBarColor,
    }
    for i = 1, #HANDLE_DEPENDENCIES do
        local name = HANDLE_DEPENDENCIES[i][1]
        st[name] = deps[name] or HANDLE_DEPENDENCIES[i][2]
    end
    st.OffsetToConfig = deps.OffsetToConfig or st.Round
    box._handles = {}
    box._handleList = {}
    local dragFrame = PixelLayoutRegion(CreateFrame("Frame", nil, dragParent), true)
    box._dragFrame = dragFrame
    dragFrame:SetAllPoints(dragParent)
    dragFrame:EnableMouse(true)
    dragFrame:EnableMouseWheel(true)
    if dragFrame.SetPropagateMouseWheel then dragFrame:SetPropagateMouseWheel(false) end
    dragFrame:SetScript("OnMouseWheel", st.ZoomWheel)
    if dragFrame.SetFrameLevel then
        dragFrame:SetFrameLevel(InteractionLevel(ns, mock, 2))
    end
    dragFrame:Hide()
    Stage.BindSelection(st)
    Stage.BindRefresh(st)
    Stage.BindTextDrag(st)
    Stage.BindPositionWriters(st)
    Stage.BindNudge(st)
    Stage.BindExactNudge(st)
    Stage.BindDrag(st)
    Stage.BindDragStart(st)
    Stage.BindHandleFactory(st)
    Stage.BindIconPool(st)
    Stage.CreateLayerHandles(st)
    Stage.BindSpellDrop(st)
    Stage.CreateTextHandles(st)
    return Stage.BuildBundle(st)
end

--- Handle selection and the spell config lookups behind it.
function Stage.BindSelection(st)
    local H, M, ns, box, OpenSection = st.H, st.M, st.MSUF, st.box, st.OpenSection
    -- Resolved once here, never per drag frame: only used when the GF table has no SpellIndicators registry.
    local spellRegistryFallback = MSUF.Require("MSUF_GF_SpellIndicators", FILE)
    local function SelectHandle(handle)
        box._selectedHandle = handle
        if box.SetFocus then box:SetFocus() end
        if handle then
            -- Preview-only entries have no slot in the Status Icons dropdown;
            -- writing their value into that selection would blank the dropdown and
            -- hide every real status handle.
            local statusSpec = handle._cfgStatus and handle._statusSpec
            if statusSpec and statusSpec.previewOnly ~= true then
                M.SetMenuStateValue("gfStatusIconSelection", statusSpec.value)
            end
            if handle._cfgSpellItem then
                local scope, item = H.CurrentScope(), handle._cfgSpellItem
                local conf = H.Conf(scope)
                SelectSpellAura(M, scope, conf and conf.spellIndicators, item.specKey, item.auraName)
            end
            local textKind = handle._cfgTextKind
            if textKind then
                local scope = H.CurrentScope()
                M.gfTextTabSelection = M.gfTextTabSelection or {}
                M.gfTextTabSelection[scope] = textKind
                if handle._cfgTextSlot then
                    H.SetTextMoveTogether(scope, textKind, false)
                    M.gfTextSlotSelection = M.gfTextSlotSelection or {}
                    M.gfTextSlotSelection[scope] = M.gfTextSlotSelection[scope] or {}
                    M.gfTextSlotSelection[scope][textKind] = handle._cfgTextSlot
                elseif textKind == "hp" or textKind == "power" then
                    H.SetTextMoveTogether(scope, textKind, true)
                end
            end
        end
        st.RefreshHandleSelection(box)
    end
    local function SpellConfigForHandle(handle, create)
        local item = handle and handle._cfgSpellItem
        if not item then return st.CurrentSpellConfig(H.CurrentScope(), create) end
        local specKey, auraName = item.specKey, item.auraName
        if not (specKey and auraName and auraName ~= "") then return nil end
        local conf = H.Conf(H.CurrentScope())
        if not conf then return nil end
        if type(conf.spellIndicators) ~= "table" then
            if not create then return nil end
            conf.spellIndicators = { enabled = true, spec = "auto", specs = {}, layer = 9 }
        end
        local si = conf.spellIndicators
        si.specs = si.specs or {}
        si.specs[specKey] = si.specs[specKey] or {}
        local entries = si.specs[specKey]
        if create and type(entries[auraName]) ~= "table" then
            -- Preview items may exist only as merged SpecDefaults. Writing
            -- through them must materialize the saved entry with its
            -- default shape, or the write is lost / the icon shape resets.
            local gf = ns.GF
            local registry = (gf and gf.SpellIndicators) or spellRegistryFallback
            if registry and type(registry.MaterializeAuraConfig) == "function" then
                registry.MaterializeAuraConfig(si, specKey, auraName)
            else
                entries[auraName] = { enabled = true, onlyOwn = true }
            end
        end
        return si.specs[specKey][auraName]
    end
    local function SpellPlacedForHandle(handle, create)
        local cfg = SpellConfigForHandle(handle, create)
        if cfg and create and type(cfg.placed) ~= "table" then
            cfg.placed = { type = "icon", anchor = "TOPLEFT", x = 0, y = 0, size = 18, showCooldownSwipe = true }
        end
        if cfg and type(cfg.placed) == "table" then return cfg.placed end
        -- Active multi-spec entries may still exist only in compiled
        -- SpecDefaults. Read the exact geometry that was rendered until the
        -- first write materializes its saved entry.
        local rendered = handle and handle._msufSpellIndicatorPlaced
        if not create and type(rendered) == "table" then return rendered end
        return nil
    end
    local function OpenHandleSettings(handle)
        if handle and handle._sectionKey and type(OpenSection) == "function" then
            OpenSection(handle._sectionKey)
            return true
        end
        return false
    end
    st.SelectHandle, st.OpenHandleSettings = SelectHandle, OpenHandleSettings
    st.SpellConfigForHandle, st.SpellPlacedForHandle = SpellConfigForHandle, SpellPlacedForHandle
end

--- History checkpoints, the combat gate and the post-move refresh of the
--- live group frames.
function Stage.BindRefresh(st)
    local H, M, ns, box, HandleText, RefreshHandleSelection = st.H, st.M, st.MSUF, st.box, st.HandleText, st.RefreshHandleSelection
    -- Collaborators the refresh paths use when the GF table lacks the method, and the apply service. They are
    -- resolved once here: the drag-frame and key-repeat nudge paths must never call MSUF.Require.
    local refreshAurasFallback = MSUF.Require("MSUF_GF_RefreshPreviewAuras", FILE)
    local refreshSpellsFallback = MSUF.Require("MSUF_GF_RefreshPreviewSpellIndicators", FILE)
    local ApplyService = MSUF.Require("MSUF_Menu2_ApplyService", FILE)
    local function HandleHistoryLabel(handle, action)
        return tostring(action or "Move") .. ": " .. tostring(HandleText(handle))
    end
    local function CheckpointHandleHistory(handle, action)
        if type(M.CheckpointHistory) ~= "function" then return end
        M.CheckpointHistory(
            HandleHistoryLabel(handle, action),
            "groupPreview:" .. tostring(H.CurrentScope()) .. ":" .. tostring(handle and handle._key or "handle") .. ":" .. tostring(action or "move")
        )
    end
    -- Runs every drag frame and every key-repeat nudge: keep the combat check inline.
    local function ConfigCombatLocked()
        if type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() then return true end
        return type(InCombatLockdown) == "function" and InCombatLockdown() == true
    end
    -- Runs on every drag frame of an aura or spell handle.
    local function RefreshGroupIndicatorDragPreview(handle)
        if ConfigCombatLocked() then return false end
        local gf = ns.GF
        local refreshKind = H.CurrentScope()
        if handle and handle._cfgSpell then
            if gf and type(gf.RefreshPreviewSpellIndicators) == "function" then
                return gf.RefreshPreviewSpellIndicators(refreshKind) == true
            end
            return refreshSpellsFallback(refreshKind) == true
        end
        if gf and type(gf.RefreshPreviewAuras) == "function" then
            return gf.RefreshPreviewAuras(refreshKind) == true
        end
        return refreshAurasFallback(refreshKind) == true
    end
    -- Runs on every key-repeat nudge as well as on release.
    local function RefreshGroupPreviewAfterMove(handle, skipPreviewRefresh)
        if ConfigCombatLocked() then return false end
        local gf, a3 = ns.GF, ns.MSUF_Auras3
        local refreshKind = H.CurrentScope()
        local auraGroupMove = handle and handle._cfgGroup
        if gf and type(gf.InvalidateCompiledSpecs) == "function" then
            gf.InvalidateCompiledSpecs(refreshKind)
        end
        if handle and handle._cfgSpell and gf and gf.SpellIndicators and type(gf.SpellIndicators.InvalidateRuntimeCaches) == "function" then
            gf.SpellIndicators.InvalidateRuntimeCaches()
        end
        if auraGroupMove then
            ApplyService.RequestAuras(refreshKind, "MSUF2_GROUP_PREVIEW_AURA_MOVE")
            ApplyService.Flush()
        elseif gf and gf.RefreshVisuals then
            local dirty = gf.DIRTY_VISUAL or 0x02
            if handle and (handle._cfgGroup or handle._cfgSpell) then dirty = gf.DIRTY_AURAS or dirty end
            gf.RefreshVisuals(refreshKind, dirty)
        elseif gf and gf.MarkAllDirty then
            gf.MarkAllDirty(gf.DIRTY_VISUAL or 0x02)
        end
        if auraGroupMove and not (a3 and type(a3.RequestScope) == "function")
            and a3 and type(a3.NotifyPreview) == "function" then
            a3.NotifyPreview("MSUF2_GROUP_PREVIEW_AURA_MOVE", refreshKind)
        end
        if not skipPreviewRefresh then
            if box.RequestRefresh then
                box:RequestRefresh("GROUP_PREVIEW_HANDLE_MOVE")
            elseif box.Refresh then
                box:Refresh()
            end
        end
        RefreshHandleSelection(box)
        return true
    end
    st.CheckpointHandleHistory, st.ConfigCombatLocked, st.HandleHistoryLabel = CheckpointHandleHistory, ConfigCombatLocked, HandleHistoryLabel
    st.RefreshGroupIndicatorDragPreview, st.RefreshGroupPreviewAfterMove = RefreshGroupIndicatorDragPreview, RefreshGroupPreviewAfterMove
end

--- Text handle drag: captured region geometry, live drag painting and the
--- offset writer behind name/HP/power text moves.
function Stage.BindTextDrag(st)
    local H, Round, box, UpdateHint, RefreshHandleSelection = st.H, st.Round, st.box, st.UpdateHint, st.RefreshHandleSelection
    local RefreshGroupPreviewAfterMove, CheckpointHandleHistory = st.RefreshGroupPreviewAfterMove, st.CheckpointHandleHistory
    local function TextRegionsForHandle(handle)
        if not (handle and box._mock) then return nil end
        local kind = handle._cfgTextKind or H.CurrentTextKind()
        local slot = handle._cfgTextSlot
        if kind == "hp" and (slot == "left" or slot == "right") then
            -- Under reverse order the configured left slot renders on the
            -- physical right FontString (and vice versa); pair the handle with
            -- the FontString that shows its slot's content.
            local conf = H.Conf(H.CurrentScope())
            if conf and conf.hpTextReverse == true then
                slot = slot == "left" and "right" or "left"
            end
        end
        if type(H.TextRegions) == "function" then
            local regions = H.TextRegions(box._mock, kind, slot)
            if regions then return regions end
        end
        return MirrorTextRegions(box._mock, kind, slot)
    end
    local function CaptureTextDragRegions(handle)
        if not handle then return end
        local captured = {}
        local regions = TextRegionsForHandle(handle)
        if regions then
            for i = 1, #regions do
                CaptureTextDragFrame(captured, regions[i])
            end
        end
        local focus = box._msufMenuTextFocus
        if focus and focus.kind == (handle._cfgTextKind or H.CurrentTextKind()) and focus.slot == handle._cfgTextSlot then
            CaptureTextDragFrame(captured, box._msufMenuTextFocusFrame)
        end
        handle._textDragRegions = captured
    end
    local function ApplyTextRegionDrag(handle, nextX, nextY)
        if not handle then return false end
        local previewScale = handle._previewScale or (box._mock and box._mock._previewScale) or 1
        if previewScale <= 0 then previewScale = 1 end
        local dx = ResolveTextDragPixelDelta(Round, nextX, handle._dragCfgStartX or 0, previewScale, handle._dragEndpointBiasX)
        local dy = ResolveTextDragPixelDelta(Round, nextY, handle._dragCfgStartY or 0, previewScale, handle._dragEndpointBiasY)
        local moved = false
        local captured = handle._textDragRegions
        if captured then
            -- The delta is in the units of the outer preview frame. The engine texts sit in the zoomed cell, whose
            -- offsets are in the cell's own units: the same screen distance is the delta over the scale ratio.
            local mockScale = box._mock and box._mock.GetEffectiveScale and box._mock:GetEffectiveScale() or 1
            for i = 1, #captured do
                local item = captured[i]
                local frame = item and item.frame
                local points = item and item.points
                if frame and points and frame.ClearAllPoints and frame.SetPoint then
                    local owner = frame.GetEffectiveScale and frame or (frame.GetParent and frame:GetParent())
                    local frameScale = owner and owner.GetEffectiveScale and owner:GetEffectiveScale() or mockScale
                    local k = (mockScale and mockScale > 0 and frameScale and frameScale > 0) and mockScale / frameScale or 1
                    frame:ClearAllPoints()
                    for j = 1, #points do
                        local p = points[j]
                        frame:SetPoint(p.point, p.relTo or box._mock, p.relPoint or p.point, (p.x or 0) + dx * k, (p.y or 0) + dy * k)
                    end
                    -- Direct drag painting temporarily mutates the same region
                    -- cached by Group Preview Name layout. Mark it dirty so the
                    -- next render reasserts saved geometry even if a write was
                    -- rejected or rounded back to its starting value.
                    if frame._msufPreviewNameNaturalWidth == true then
                        frame._msufPreviewNameGeometryDirty = true
                    end
                    moved = true
                end
            end
        end
        if handle._dragPoint then
            handle:ClearAllPoints()
            handle:SetPoint(handle._dragPoint, handle._dragRelTo or box._mock, handle._dragRelPoint or handle._dragPoint, (handle._dragStartX or 0) + dx,
                (handle._dragStartY or 0) + dy)
            moved = true
        end
        return moved
    end
    local function ReleaseTextDragRegions(handle)
        if handle then handle._textDragRegions = nil end
    end
    local function WriteTextHandleOffsets(handle, x, y, action, checkpoint, previewOnly)
        if not handle then return false end
        local conf = H.Conf(H.CurrentScope())
        if not conf then return false end
        local kind = handle._cfgTextKind or H.CurrentTextKind()
        local xKey, yKey = H.TextOffsetKeys(kind, handle._cfgTextSlot)
        conf[xKey] = Round(x or 0)
        conf[yKey] = Round(y or 0)
        if previewOnly then
            UpdateHint(box, handle)
            RefreshHandleSelection(box)
        else
            RefreshGroupPreviewAfterMove(handle)
        end
        if checkpoint then CheckpointHandleHistory(handle, action or "Move") end
        return true
    end
    st.ApplyTextRegionDrag, st.CaptureTextDragRegions = ApplyTextRegionDrag, CaptureTextDragRegions
    st.ReleaseTextDragRegions, st.WriteTextHandleOffsets = ReleaseTextDragRegions, WriteTextHandleOffsets
end

--- Position writer: saving a dragged handle into the config.
function Stage.BindPositionWriters(st)
    local H, OffsetToConfig, box, ResolveAnchor = st.H, st.OffsetToConfig, st.box, st.ResolveAnchor
    local ConfigCombatLocked, CheckpointHandleHistory = st.ConfigCombatLocked, st.CheckpointHandleHistory
    local RefreshGroupPreviewAfterMove, SpellPlacedForHandle = st.RefreshGroupPreviewAfterMove, st.SpellPlacedForHandle
    local CurrentStatusSpec, HandleOffset, PointOffset = st.CurrentStatusSpec, st.HandleOffset, st.PointOffset
    local RefreshGroupIndicatorDragPreview = st.RefreshGroupIndicatorDragPreview
    -- Runs on every drag frame (previewOnly) and on release; no helper calls beyond the original path.
    -- hot path: kept whole (perf rule)
    local function SaveHandlePosition(handle, action, previewOnly)
        if not (handle and box._mock) or handle._locked or ConfigCombatLocked() then return false end
        if handle._cfgText then return end
        local m = box._mock
        for i = 1, #FIXED_OFFSET_KINDS do
            local kind = FIXED_OFFSET_KINDS[i]
            if handle[kind[1]] then
                local _, _, _, offX, offY = handle:GetPoint(1)
                local scale = handle._previewWriteScale or handle._previewScale or m._previewScale or 1
                local conf = H.Conf(H.CurrentScope())
                if not conf then return end
                conf[kind[2]] = OffsetToConfig((offX or 0) - (handle._msufEngineOffsetX or 0), scale)
                conf[kind[3]] = OffsetToConfig((offY or 0) - (handle._msufEngineOffsetY or 0), scale)
                if not previewOnly then
                    RefreshGroupPreviewAfterMove(handle)
                    CheckpointHandleHistory(handle, action)
                end
                return true
            end
        end
        local anchorFrame = (handle._cfgGroup and handle._previewAnchorFrame) or m
        local mL, mT = anchorFrame:GetLeft() or 0, anchorFrame:GetTop() or 0
        local mW, mH = max(1, anchorFrame:GetWidth() or 1), max(1, anchorFrame:GetHeight() or 1)
        local hL, hT = handle:GetLeft() or 0, handle:GetTop() or 0
        local hB = handle:GetBottom() or 0
        local hW, hH = handle:GetWidth() or 1, handle:GetHeight() or 1
        local anchor, offX, offY
        if handle._cfgGroup and handle._previewOriginX and handle._previewOriginY then
            local px = hL + handle._previewOriginX
            local py = hB + handle._previewOriginY
            anchor = ResolveAnchor((px - mL) / mW, (mT - py) / mH)
            offX, offY = PointOffset(px, py, anchorFrame, anchor)
        else
            local cx, cy = hL + hW * 0.5, hT - hH * 0.5
            anchor = ResolveAnchor((cx - mL) / mW, (mT - cy) / mH)
            offX, offY = HandleOffset(handle, m, anchor)
        end
        local scale = handle._previewWriteScale or handle._previewScale or m._previewScale or 1
        local cfgX, cfgY = OffsetToConfig(offX, scale), OffsetToConfig(offY, scale)
        local conf = H.Conf(H.CurrentScope())
        if handle._cfgGroup then
            local lane = AuraLaneConf(conf, handle._cfgGroup)
            if handle._cfgTrackedBuff then
                lane.trackedAnchor, lane.trackedX, lane.trackedY = anchor, cfgX, cfgY
            else
                lane.anchor, lane.x, lane.y = anchor, cfgX, cfgY
            end
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or CurrentStatusSpec()
            if spec then conf[spec.anchor], conf[spec.x], conf[spec.y] = anchor, cfgX, cfgY end
        elseif handle._cfgSpell then
            -- create=true: items rendered purely from SpecDefaults have no
            -- saved entry yet; a read-only lookup silently dropped this write.
            local placed = SpellPlacedForHandle(handle, true)
            if placed then placed.anchor, placed.x, placed.y = anchor, cfgX, cfgY end
        end
        if previewOnly then
            -- Pointer-drag hot path: Aura/Spell handles repaint their pooled
            -- dummy indicators. Runtime group frames,
            -- history, and the full preview refresh remain release-only.
            if handle._cfgGroup or handle._cfgSpell then RefreshGroupIndicatorDragPreview(handle) end
        else
            RefreshGroupPreviewAfterMove(handle)
            CheckpointHandleHistory(handle, action)
        end
        return true
    end
    st.SaveHandlePosition = SaveHandlePosition
end

--- Arrow-key nudge. It runs on every key-repeat press, so the ladder stays inline.
function Stage.BindNudge(st)
    local H, Round = st.H, st.Round
    local CheckpointHandleHistory, RefreshGroupPreviewAfterMove = st.CheckpointHandleHistory, st.RefreshGroupPreviewAfterMove
    local CurrentStatusSpec, HandleOffsets = st.CurrentStatusSpec, st.HandleOffsets
    local SpellPlacedForHandle, WriteTextHandleOffsets = st.SpellPlacedForHandle, st.WriteTextHandleOffsets
    local function NudgeHandlePosition(handle, dx, dy)
        if not handle then return false end
        if handle._cfgText then
            local _, x, y = HandleOffsets(handle)
            local step = H.NudgeStep()
            return WriteTextHandleOffsets(handle, (tonumber(x) or 0) + (dx * step), (tonumber(y) or 0) + (dy * step), "Nudge", true)
        end
        local conf = H.Conf(H.CurrentScope())
        if not conf then return false end
        local x, y
        if handle._cfgSpell then
            local placed = SpellPlacedForHandle(handle, false)
            x, y = placed and placed.x, placed and placed.y
        else
            local _
            _, x, y = HandleOffsets(handle)
        end
        local step = H.NudgeStep()
        local cfgX, cfgY = Round((tonumber(x) or 0) + (dx * step)), Round((tonumber(y) or 0) + (dy * step))
        if handle._cfgGroup then
            local lane = AuraLaneConf(conf, handle._cfgGroup)
            if handle._cfgTrackedBuff then
                lane.trackedX, lane.trackedY = cfgX, cfgY
            else
                lane.x, lane.y = cfgX, cfgY
            end
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or CurrentStatusSpec()
            if not spec then return false end
            conf[spec.x], conf[spec.y] = cfgX, cfgY
        elseif handle._cfgSpell then
            local placed = SpellPlacedForHandle(handle, true)
            if not placed then return false end
            placed.x, placed.y = cfgX, cfgY
        else
            local fixed
            for i = 1, #FIXED_OFFSET_KINDS do
                if handle[FIXED_OFFSET_KINDS[i][1]] then
                    fixed = FIXED_OFFSET_KINDS[i]
                    break
                end
            end
            if not fixed or handle._locked then return false end
            conf[fixed[2]], conf[fixed[3]] = cfgX, cfgY
        end
        RefreshGroupPreviewAfterMove(handle)
        CheckpointHandleHistory(handle, "Nudge")
        return true
    end
    st.NudgeHandlePosition = NudgeHandlePosition
end

--- Exact (scripted) nudges: read/write one handle's configured position and
--- the transactional box:NudgeHandleExact API.
function Stage.BindExactNudge(st)
    local H, M, Round, box = st.H, st.M, st.Round, st.box
    local CurrentStatusSpec, SelectHandle = st.CurrentStatusSpec, st.SelectHandle
    local SpellPlacedForHandle, WriteTextHandleOffsets = st.SpellPlacedForHandle, st.WriteTextHandleOffsets
    local ExactPreviewDelta = MSUF.MSUF2.PreviewHelpers.ExactPreviewDelta
    -- Where a handle keeps its position: the table, its X/Y keys, the anchor key and the Y value used while unset.
    -- create makes the missing aura lane / spell entry (a nil table with keys means nothing is saved yet); nil keys
    -- mean the handle has no stored position. Only these scripted nudges use it; the drag and key-repeat paths above
    -- keep their own inline ladders.
    local function OffsetSlot(handle, conf, create)
        if handle._cfgGroup then
            local lane = create and AuraLaneConf(conf, handle._cfgGroup) or (conf.auras and conf.auras[handle._cfgGroup])
            if handle._cfgTrackedBuff then return lane, "trackedX", "trackedY", "trackedAnchor" end
            return lane, "x", "y", "anchor"
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or CurrentStatusSpec()
            if spec and spec.x and spec.y then return conf, spec.x, spec.y, spec.anchor end
            return nil
        elseif handle._cfgSpell then
            -- create=true: items rendered purely from SpecDefaults have no
            -- saved entry yet; a read-only lookup silently dropped the write.
            return SpellPlacedForHandle(handle, create), "x", "y", "anchor"
        end
        local xKey, yKey, defaultY = FixedOffsetKeys(handle)
        return conf, xKey, yKey, nil, defaultY
    end
    local function ReadHandlePositionExact(handle)
        local conf = handle and H.Conf(H.CurrentScope())
        if not conf then return nil end
        local slot, xKey, yKey, _, defaultY
        if handle._cfgText then
            slot = conf
            xKey, yKey = H.TextOffsetKeys(handle._cfgTextKind or H.CurrentTextKind(), handle._cfgTextSlot)
        else
            slot, xKey, yKey, _, defaultY = OffsetSlot(handle, conf, false)
        end
        if not (xKey and yKey) then return nil end
        return tonumber(slot and slot[xKey]) or 0, tonumber(slot and slot[yKey]) or defaultY or 0
    end
    local function WriteHandlePositionExact(handle, x, y, reason)
        if not handle then return false end
        x, y = Round(x), Round(y)
        if handle._cfgText then
            return WriteTextHandleOffsets(handle, x, y, reason or "Nudge", false, false)
        end
        local conf = H.Conf(H.CurrentScope())
        if not conf then return false end
        local slot, xKey, yKey = OffsetSlot(handle, conf, true)
        if not (slot and xKey) then return false end
        slot[xKey], slot[yKey] = x, y
        st.RefreshGroupPreviewAfterMove(handle)
        return true
    end
    local function RestoreGroupPreviewSelection(previous)
        if previous and previous._key and box._handles[previous._key] == previous then SelectHandle(previous) else SelectHandle(nil) end
    end

    --- Move one explicitly named handle on this exact Group preview surface.
    --- No Edit Mode mover or shared/stale preview target participates.
    function box:NudgeHandleExact(handleKey, dx, dy)
        if ManagerCombatLocked(M) then return false, "combat-locked" end
        if type(handleKey) ~= "string" or handleKey == "" then return false, "handle-required" end
        dx, dy = ExactPreviewDelta(dx), ExactPreviewDelta(dy)
        if dx == nil or dy == nil then return false, "invalid-delta" end
        if self._msufGFNativePreviewDisposed then return false, "preview-disposed" end
        if not (self.IsShown and self:IsShown() and (not self.IsVisible or self:IsVisible())) then return false, "preview-not-visible" end
        local handle = self._handles and self._handles[handleKey]
        if not handle then return false, "unknown-handle" end
        if handle._dragging == true or (self._dragFrame and self._dragFrame._handle) then return false, "handle-busy" end
        if handle._locked or (handle.IsShown and not handle:IsShown()) then return false, "handle-not-visible" end
        local beforeX, beforeY = ReadHandlePositionExact(handle)
        if tonumber(beforeX) == nil or tonumber(beforeY) == nil then return false, "handle-not-readable" end
        beforeX, beforeY = tonumber(beforeX), tonumber(beforeY)
        local expectedX, expectedY = Round(beforeX + dx), Round(beforeY + dy)
        local previous = self._selectedHandle
        SelectHandle(handle)
        if self._selectedHandle ~= handle then
            RestoreGroupPreviewSelection(previous)
            return false, "selection-failed"
        end
        if expectedX == beforeX and expectedY == beforeY then return true, beforeX, beforeY, beforeX, beforeY end

        local outcome
        local function Mutate()
            local wrote = WriteHandlePositionExact(handle, expectedX, expectedY, "Exact nudge") == true
            local afterX, afterY = ReadHandlePositionExact(handle)
            afterX, afterY = tonumber(afterX), tonumber(afterY)
            if wrote and afterX == expectedX and afterY == expectedY then
                outcome = { true, beforeX, beforeY, afterX, afterY }
                return true
            end
            local rolledBack = WriteHandlePositionExact(handle, beforeX, beforeY, "Exact nudge rollback") == true
            local restoredX, restoredY = ReadHandlePositionExact(handle)
            local reason = (not rolledBack or tonumber(restoredX) ~= beforeX or tonumber(restoredY) ~= beforeY)
                and "rollback-failed" or (wrote and "readback-mismatch" or "write-failed")
            outcome = { false, reason }
            return false
        end
        local capturing = type(M.IsHistoryCapturing) == "function" and M.IsHistoryCapturing()
        if type(M.CaptureHistory) == "function" and not capturing then
            M.CaptureHistory(st.HandleHistoryLabel(handle, "Nudge"),
                "groupPreview:" .. tostring(H.CurrentScope()) .. ":" .. handleKey .. ":exact-nudge", Mutate)
        else
            Mutate()
            if outcome and outcome[1] then st.CheckpointHandleHistory(handle, "Nudge") end
        end
        if not (outcome and outcome[1]) then RestoreGroupPreviewSelection(previous) end
        if outcome and outcome[1] then return true, outcome[2], outcome[3], outcome[4], outcome[5] end
        return false, (outcome and outcome[2]) or "write-failed"
    end
end

--- Pointer drag lifecycle: per-frame update and release for every handle kind.
function Stage.BindDrag(st)
    local M, PreviewHelpers, box, Round = st.M, st.PreviewHelpers, st.box, st.Round
    local ConfigCombatLocked, RefreshHandleSelection, SaveHandlePosition = st.ConfigCombatLocked, st.RefreshHandleSelection, st.SaveHandlePosition
    local ApplyTextRegionDrag, ReleaseTextDragRegions = st.ApplyTextRegionDrag, st.ReleaseTextDragRegions
    local StopPan, UpdateHint, WriteTextHandleOffsets = st.StopPan, st.UpdateHint, st.WriteTextHandleOffsets
    local function StopHandleDrag(handle, button, allowOpenSettings)
        if box._stage and box._stage._msufGFPreviewPanning then StopPan(box._stage) end
        if button and button ~= "LeftButton" then return end
        handle = handle or (box._dragFrame and box._dragFrame._handle)
        local wasDragging = handle and handle._dragging == true
        local textDrag = handle and handle._cfgText
        local didMove = handle and handle._didDragMove == true
        if didMove and PreviewHelpers.NotePreviewElementMoved then PreviewHelpers.NotePreviewElementMoved() end
        local openSettingsOnRelease = handle and allowOpenSettings == true
            and button == "LeftButton"
            and handle._suppressSettingsOnRelease ~= true
            and not didMove
        if box._dragFrame then
            box._dragFrame:SetScript("OnUpdate", nil)
            box._dragFrame._handle = nil
            box._dragFrame:Hide()
        end
        local hadFrozenScale = box._dragFrozenScale ~= nil
        if not textDrag then box._dragFrozenScale = nil end
        if handle then
            if textDrag and box.SetTextDragRefreshSuppressed then box:SetTextDragRefreshSuppressed(false) end
            for i = 1, #DRAG_STATE_KEYS do
                handle[DRAG_STATE_KEYS[i]] = nil
            end
        end
        local didFinalRefresh
        if wasDragging and textDrag then
            if handle._lastDragX ~= nil or handle._lastDragY ~= nil then
                st.RefreshGroupPreviewAfterMove(handle, true)
                if box.Refresh then box:Refresh("GROUP_PREVIEW_TEXT_DRAG_END") end
                if M.RequestRefresh then M.RequestRefresh(nil, "gf-text-drag-controls") end
                st.CheckpointHandleHistory(handle, "Move")
                didFinalRefresh = true
            else
                RefreshHandleSelection(box)
            end
        elseif wasDragging and didMove then
            SaveHandlePosition(handle, "Move")
            didFinalRefresh = true
        else
            RefreshHandleSelection(box)
        end
        if hadFrozenScale and not box._manualZoom and not didFinalRefresh and not openSettingsOnRelease then
            RequestBoxRefresh(box, "GROUP_PREVIEW_DRAG_END")
        end
        if textDrag then
            ReleaseTextDragRegions(handle)
            box._dragFrozenScale = nil
        end
        if openSettingsOnRelease then st.OpenHandleSettings(handle) end
    end
    box._dragFrame:SetScript("OnMouseUp", function(_, button)
        StopHandleDrag(nil, button, true)
    end)
    local function UpdateHandleDrag(df)
        local handle = df and df._handle
        if not (handle and handle._dragging) then return end
        if ConfigCombatLocked() then
            StopHandleDrag(handle, "LeftButton")
            return
        end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            StopHandleDrag(handle, "LeftButton", true)
            return
        end
        local cx, cy = GetCursorPosition()
        if not (cx and cy) then return end
        local cursorX, cursorY = handle._dragCursorX or cx, handle._dragCursorY or cy
        if handle._didDragMove ~= true then
            local cursorDX, cursorDY = cx - cursorX, cy - cursorY
            if cursorDX * cursorDX + cursorDY * cursorDY < HANDLE_CLICK_DRAG_THRESHOLD * HANDLE_CLICK_DRAG_THRESHOLD then
                return
            end
            handle._didDragMove = true
        end
        -- Text handles drag in config units (screen delta over UI and preview scale); every other handle drags in
        -- screen pixels over the scale of the frame it is anchored to.
        local startX, startY, scale, previewScale
        if handle._cfgText then
            startX, startY = handle._dragCfgStartX, handle._dragCfgStartY
            scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if scale <= 0 then scale = 1 end
            previewScale = handle._previewScale or (box._mock and box._mock._previewScale) or 1
            if previewScale <= 0 then previewScale = 1 end
        else
            startX, startY, scale, previewScale = handle._dragStartX, handle._dragStartY, handle._dragScale or 1, 1
            if scale <= 0 then scale = 1 end
        end
        local nextX = Round((startX or 0) + (cx - cursorX) / scale / previewScale)
        local nextY = Round((startY or 0) + (cy - cursorY) / scale / previewScale)
        if handle._lastDragX == nextX and handle._lastDragY == nextY then return end
        handle._lastDragX = nextX
        handle._lastDragY = nextY
        if handle._cfgText then
            ApplyTextRegionDrag(handle, nextX, nextY)
            WriteTextHandleOffsets(handle, nextX, nextY, "Move", false, true)
            return
        end
        handle:ClearAllPoints()
        handle:SetPoint(handle._dragPoint or "CENTER", handle._dragRelTo or box._mock, handle._dragRelPoint or "CENTER", nextX, nextY)
        UpdateHint(box, handle)
        SaveHandlePosition(handle, "Move", true)
    end
    st.StopHandleDrag, st.UpdateHandleDrag = StopHandleDrag, UpdateHandleDrag
end

--- Pointer drag start: selection, the pan shortcut and the drag origin of every
--- handle kind.
function Stage.BindDragStart(st)
    local PreviewHelpers, box, ConfigCombatLocked, SelectHandle = st.PreviewHelpers, st.box, st.ConfigCombatLocked, st.SelectHandle
    local RefreshHandleSelection, StartPan, UpdateHandleDrag = st.RefreshHandleSelection, st.StartPan, st.UpdateHandleDrag
    local function StartHandleDrag(handle, button)
        if ConfigCombatLocked() then return end
        if button and button ~= "LeftButton" then return end
        if handle then handle._didDragMove = nil end
        if button == "LeftButton" and IsControlKeyDown and IsControlKeyDown() and StartPan(box._stage, box, button) then
            handle._suppressNextClick = true
            handle._suppressSettingsOnRelease = true
            return
        end
        SelectHandle(handle)
        if PreviewHelpers.ShowPreviewMoveCue then PreviewHelpers.ShowPreviewMoveCue(box, handle) end
        if not handle or handle._locked then return end
        local point, relativeTo, relativePoint, xOfs, yOfs = handle:GetPoint(1)
        local cx, cy = GetCursorPosition()
        if not (point and cx and cy) then return end
        handle._dragging = true
        box._dragFrozenScale = tonumber(box._mockScale) or tonumber(box._mockAutoScale) or 1
        if handle._cfgText then
            local _, cfgX, cfgY = st.HandleOffsets(handle)
            handle._dragCfgStartX = tonumber(cfgX) or 0
            handle._dragCfgStartY = tonumber(cfgY) or 0
            if handle._cfgTextKind == "name" then
                local fs = box._mock and box._mock._nameFS
                handle._dragEndpointBiasX = (tonumber(fs and fs._msufPreviewNameEndpointX)
                    or handle._dragCfgStartX) - handle._dragCfgStartX
                handle._dragEndpointBiasY = (tonumber(fs and fs._msufPreviewNameEndpointY)
                    or handle._dragCfgStartY) - handle._dragCfgStartY
            end
            st.CaptureTextDragRegions(handle)
            if box.SetTextDragRefreshSuppressed then
                box:SetTextDragRefreshSuppressed(true)
            elseif box.CancelPendingRefresh then
                box:CancelPendingRefresh()
            end
        end
        handle._dragPoint = point
        handle._dragRelTo = relativeTo or box._mock
        handle._dragRelPoint = relativePoint or point
        handle._dragStartX = xOfs or 0
        handle._dragStartY = yOfs or 0
        handle._dragCursorX = cx
        handle._dragCursorY = cy
        handle._lastDragX = nil
        handle._lastDragY = nil
        local rel = handle._dragRelTo
        handle._dragScale = (rel and rel.GetEffectiveScale and rel:GetEffectiveScale())
            or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())
            or 1
        box._dragFrame._handle = handle
        if box._dragFrame.SetAllPoints then box._dragFrame:SetAllPoints(box._stage or box) end
        box._dragFrame:SetScript("OnUpdate", UpdateHandleDrag)
        box._dragFrame:Show()
        RefreshHandleSelection(box)
    end
    st.StartHandleDrag = StartHandleDrag
end

--- Handle factory: the preview handle button (scripts, tooltip, quick actions,
--- control registration).
function Stage.BindHandleFactory(st)
    local box, M, T, Tr, WHITE8X8, PreviewHelpers, mock = st.box, st.M, st.T, st.TR, st.WHITE8X8, st.PreviewHelpers, st.mock
    local HandleText, RefreshHandleSelection, SelectHandle = st.HandleText, st.RefreshHandleSelection, st.SelectHandle
    local OpenHandleSettings, StartHandleDrag, StopHandleDrag = st.OpenHandleSettings, st.StartHandleDrag, st.StopHandleDrag
    -- Every handle of this install shares these scripts; each one only uses the frame it is called on.
    local function OnEnter(self)
        self._hovering = true
        RefreshHandleSelection(box)
        local showTooltip = GameTooltip and (not PreviewHelpers.ShouldShowPreviewHandleTooltip
            or PreviewHelpers.ShouldShowPreviewHandleTooltip(box))
        if not showTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(HandleText(self), 1, 1, 1)
        if self._locked then
            GameTooltip:AddLine((M.Tr and M.Tr("This preview layer is locked.")) or "This preview layer is locked.", 0.82, 0.82, 0.82, true)
        else
            GameTooltip:AddLine(Tr("Drag to move. Arrow keys nudge."), 0.82, 0.82, 0.82, true)
        end
        GameTooltip:AddLine(Tr("Right-click opens quick actions."), 0.50, 0.78, 0.92, true)
        GameTooltip:Show()
    end
    local function OnLeave(self)
        self._hovering = nil
        RefreshHandleSelection(box)
        if GameTooltip then GameTooltip:Hide() end
    end
    local function OnClick(self, button)
        if self._suppressNextClick then
            self._suppressNextClick = nil
            return
        end
        SelectHandle(self)
        if button ~= "RightButton" then return end
        if self._openSettingsOnRightClick == true then
            OpenHandleSettings(self)
        elseif PreviewHelpers.ShowPreviewHandleContext then
            PreviewHelpers.ShowPreviewHandleContext(self, {
                M = M,
                T = T,
                Tr = Tr,
                title = HandleText(self),
                openSettings = OpenHandleSettings,
            })
        end
    end
    local function OnMouseUp(self, button) StopHandleDrag(self, button, true) end
    local function OnDragStop(self, button) StopHandleDrag(self, button, false) end
    local function OnHide(self)
        StopHandleDrag(self, nil, false)
        if box._selectedHandle == self then SelectHandle(nil) end
    end
    local function CreatePreviewHandle(key, sectionKey, color, label, width, height, locked, parent)
        local handle = PixelLayoutRegion(CreateFrame("Button", nil, parent or mock, T.Template()), true)
        handle:SetSize(width or 32, height or 32)
        -- The colored label is part of the visible affordance. Without this,
        -- clicking its glyphs falls through to a different overlapping handle
        -- or the preview canvas and appears to route randomly.
        if handle.SetHitRectInsets then handle:SetHitRectInsets(0, 0, -HANDLE_LABEL_HIT_HEIGHT, 0) end
        handle:SetMovable(true)
        handle:EnableMouse(true)
        handle:EnableMouseWheel(true)
        if handle.SetPropagateMouseWheel then handle:SetPropagateMouseWheel(false) end
        if handle.RegisterForClicks then handle:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp") end
        if handle.RegisterForDrag then handle:RegisterForDrag("LeftButton") end
        PixelLayoutRegion(handle, "SetBackdrop", { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
        handle:SetBackdropColor(color[1] * 0.12, color[2] * 0.12, color[3] * 0.12, 0.42)
        handle:SetBackdropBorderColor(color[1], color[2], color[3], locked and 0.55 or 0.95)
        handle._key = key
        handle._sectionKey = sectionKey
        handle._previewLayerKey = GROUP_HANDLE_LAYER_BY_KEY[key] or GROUP_SECTION_LAYER[sectionKey]
        handle._locked = locked and true or false
        handle._color = color
        local selectFill = PixelLayoutRegion(handle:CreateTexture(nil, "OVERLAY", nil, 6))
        selectFill:SetAllPoints()
        selectFill:SetColorTexture(color[1], color[2], color[3], 0)
        handle._selectFill = selectFill
        local selectBorder = PixelLayoutRegion(CreateFrame("Frame", nil, handle, T.Template()))
        selectBorder:SetPoint("TOPLEFT", handle, "TOPLEFT", -2, 2)
        selectBorder:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", 2, -2)
        PixelLayoutRegion(selectBorder, "SetBackdrop", { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
        selectBorder:SetBackdropColor(0, 0, 0, 0)
        selectBorder:SetBackdropBorderColor(color[1], color[2], color[3], 1)
        selectBorder:Hide()
        handle._selectBorder = selectBorder
        local fs = T.Font(handle, "GameFontDisableSmall", label or key, { color[1], color[2], color[3], 0.95 })
        fs:SetPoint("BOTTOM", handle, "TOP", 0, 1)
        fs:SetJustifyH("CENTER")
        handle._label = fs
        handle:SetScript("OnEnter", OnEnter)
        handle:SetScript("OnLeave", OnLeave)
        handle:SetScript("OnClick", OnClick)
        handle:SetScript("OnMouseWheel", st.ZoomWheel)
        handle:SetScript("OnMouseDown", StartHandleDrag)
        handle:SetScript("OnMouseUp", OnMouseUp)
        handle:SetScript("OnDragStart", StartHandleDrag)
        handle:SetScript("OnDragStop", OnDragStop)
        handle:HookScript("OnHide", OnHide)
        RegisterHandleControls(st, handle, key, label)
        box._handles[key] = handle
        box._handleList[#box._handleList + 1] = handle
        return handle
    end
    st.CreatePreviewHandle = CreatePreviewHandle
end

--- Pooled aura icon regions (icon, swipe, border, stack, timer, duration bar)
--- of a handle.
function Stage.BindIconPool(st)
    local T, WHITE8X8, AuraDurationBarColor = st.T, st.WHITE8X8, st.AuraDurationBarColor
    local function AddIconPool(handle, count)
        for i = 1, #ICON_POOL_KEYS do
            handle[ICON_POOL_KEYS[i]] = handle[ICON_POOL_KEYS[i]] or {}
        end
        local durationLayer = EnsureIconDetailLayer(handle, "_iconDurationLayer")
        local swipeLayer = EnsureIconDetailLayer(handle, "_iconSwipeLayer")
        local textLayer = EnsureIconDetailLayer(handle, "_iconTextLayer")
        for i = 1, count do
            PooledRegion(handle._icons, i, handle, "CreateTexture", "ARTWORK"):SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local swipe = PooledRegion(handle._iconSwipes, i, swipeLayer, "CreateTexture", "ARTWORK")
            swipe:SetTexture(WHITE8X8)
            swipe:SetVertexColor(0, 0, 0, 0.58)
            swipe:Hide()
            PooledRegion(handle._iconBorders, i, handle, "CreateTexture", "OVERLAY"):Hide()
            PreparePreviewText(T, PooledRegion(handle._iconStacks, i, textLayer, "CreateFontString", "OVERLAY"), 6)
            PreparePreviewText(T, PooledRegion(handle._iconTimers, i, textLayer, "CreateFontString", "OVERLAY"), 7)
            local durationBar = PooledRegion(handle._iconDurationBars, i, durationLayer, "CreateTexture", "OVERLAY")
            durationBar:SetTexture(WHITE8X8)
            local durationR, durationG, durationB = AuraDurationBarColor()
            durationBar:SetVertexColor(durationR, durationG, durationB, 0.92)
            durationBar:Hide()
        end
    end
    st.AddIconPool = AddIconPool
end

--- Creates the aura, power, portrait, dispel, status and spell indicator
--- handles plus the dynamic per-spell handle pool.
function Stage.CreateLayerHandles(st)
    local AddIconPool, CreatePreviewHandle, H, StatusLabel, T, box = st.AddIconPool, st.CreatePreviewHandle, st.H, st.StatusLabel, st.T, st.box
    local function CreateLayerHandle(row)
        local handle = CreatePreviewHandle(row.key, row.section, row.color, row.label, row.w or 86, row.h or 34, false,
            row.stage and st.dragParent or nil)
        for field, value in pairs(row.fields) do
            handle[field] = value
        end
        if row.slot == "spellHandle" then AddIconPool(handle, row.pool) end
        st[row.slot] = handle
    end
    for i = 1, #LAYER_HANDLES do
        CreateLayerHandle(LAYER_HANDLES[i])
    end
    local statusHandles = {}
    local statusSpecs = H.StatusSpecs()
    for i = 1, #statusSpecs do
        local spec = statusSpecs[i]
        local statusHandle = CreatePreviewHandle("status_" .. tostring(spec.value or i), "sicons", { 0.80, 0.67, 0.20 }, StatusLabel(spec), 78, 28, false)
        statusHandle._cfgStatus = true
        statusHandle._statusSpec = spec
        statusHandles[#statusHandles + 1] = statusHandle
    end
    st.statusHandles = statusHandles
    CreateLayerHandle(SPELL_HANDLE)
    local spellIndicatorHandles = {}
    box._spellIndicatorHandles = spellIndicatorHandles
    local function SpellIndicatorHandleKey(item, index)
        local key = tostring(item and (item.key or item.slotKey) or index or "spell")
        key = key:gsub("[^%w_]+", "_")
        if key == "" then key = tostring(index or "spell") end
        return "si_" .. key
    end
    function box:EnsureSpellIndicatorHandle(item, index)
        if type(item) ~= "table" then return nil end
        local key = SpellIndicatorHandleKey(item, index)
        local handle = spellIndicatorHandles[key]
        if not handle then
            local c = item.color or { 0.69, 0.50, 0.88 }
            handle = CreatePreviewHandle(key, "si", { c[1] or 0.69, c[2] or 0.50, c[3] or 0.88 },
                tostring(item.display or item.auraName or "SPELL"):upper(), 44, 44, false)
            handle._cfgSpell = true
            spellIndicatorHandles[key] = handle
        end
        local identity = handle._cfgSpellItem or {}
        identity.specKey, identity.auraName = item.specKey, item.auraName
        handle._cfgSpellItem = identity
        handle._msufSpellIndicatorPlaced = item.spellIndicatorSlot == true and item or item.placed
        handle._previewText = item.display or item.auraName or "Spell"
        handle._msufSpellIndicatorPreviewKey = key
        return handle
    end
    function box:HideUnusedSpellIndicatorHandles(active)
        active = active or {}
        for key, handle in pairs(spellIndicatorHandles) do
            if not active[key] then handle:Hide() end
        end
    end
end

--- Spell drop target: cursor hit-testing, the drop guide and the
--- box:SetSpellDropTarget / box:DropSpellIndicatorAtCursor API.
function Stage.BindSpellDrop(st)
    local H, M, T, Tr, WHITE8X8, box, mock = st.H, st.M, st.T, st.TR, st.WHITE8X8, st.box, st.mock
    local SpellConfigForHandle, SpellPlacedForHandle, UpdateHint = st.SpellConfigForHandle, st.SpellPlacedForHandle, st.UpdateHint
    local function CursorPositionInUI()
        local x, y = GetCursorPosition()
        if not (x and y) then return nil end
        local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        return x / scale, y / scale
    end
    local function CursorInsideFrame(frame)
        if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return false end
        local x, y = CursorPositionInUI()
        if not (x and y) then return false end
        local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        return left and right and top and bottom and x >= left and x <= right and y >= bottom and y <= top or false
    end
    local function EnsureSpellDropGuide()
        if box._spellDropGuide then return box._spellDropGuide end
        local guide = PixelLayoutRegion(CreateFrame("Frame", nil, mock, T.Template()))
        guide:SetAllPoints(mock)
        guide:EnableMouse(false)
        if guide.SetFrameLevel then guide:SetFrameLevel(InteractionLevel(st.MSUF, mock, 1)) end
        PixelLayoutRegion(guide, "SetBackdrop", { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 2 })
        guide._text = T.Font(guide, "GameFontNormal", "Drop to place spell icon", { 0.72, 0.90, 1, 1 })
        guide._text:SetPoint("BOTTOM", guide, "TOP", 0, 6)
        guide:Hide()
        box._spellDropGuide = guide
        return guide
    end
    function box:SetSpellDropTarget(active, spellLabel)
        local guide = EnsureSpellDropGuide()
        if not active then
            guide:Hide()
            guide._dropInside = nil
            guide._dropLabel = nil
            if self._hint then UpdateHint(self, self._selectedHandle) end
            return false
        end
        local inside = CursorInsideFrame(mock)
        if guide._dropInside ~= inside then
            guide._dropInside = inside
            if inside then
                guide:SetBackdropColor(0.12, 0.72, 0.38, 0.10)
                guide:SetBackdropBorderColor(0.22, 1.00, 0.55, 1)
                guide._text:SetText("Release to place and position")
                guide._text:SetTextColor(0.42, 1.00, 0.65, 1)
            else
                guide:SetBackdropColor(0.12, 0.50, 0.82, 0.07)
                guide:SetBackdropBorderColor(0.32, 0.76, 1.00, 0.95)
                guide._text:SetText("Drag onto the frame to place")
                guide._text:SetTextColor(0.72, 0.90, 1.00, 1)
            end
        end
        guide:Show()
        if self._hint and (guide._dropLabel ~= spellLabel or guide._hintInside ~= inside) then
            guide._dropLabel = spellLabel
            guide._hintInside = inside
            self._hint:SetText(string.format("%s   %s", tostring(spellLabel or Tr("Spell icon")),
                Tr(inside and "release to place at this position" or "drag onto the unit frame")))
        end
        return inside
    end
    function box:DropSpellIndicatorAtCursor(specKey, auraName)
        if ManagerCombatLocked(M) then return false, "combat-locked" end
        if not (specKey and auraName and auraName ~= "") then return false, "spell-required" end
        if not CursorInsideFrame(mock) then return false, "outside-frame" end
        local cursorX, cursorY = CursorPositionInUI()
        local left, bottom = mock:GetLeft(), mock:GetBottom()
        local width, height = mock:GetWidth(), mock:GetHeight()
        if not (cursorX and cursorY and left and bottom and width and height and width > 0 and height > 0) then
            return false, "preview-geometry-unavailable"
        end
        local kind = H.CurrentScope()
        local dropHandle = {
            _key = "si_drop_" .. tostring(specKey) .. ":" .. tostring(auraName),
            _cfgSpell = true,
            _cfgSpellItem = { specKey = specKey, auraName = auraName },
            _previewText = auraName,
        }
        local existingCfg = SpellConfigForHandle(dropHandle, false)
        local placedForSize = existingCfg and type(existingCfg.placed) == "table" and existingCfg.placed or {}
        local previewScale = tonumber(box._mockScale) or tonumber(box._mockAutoScale) or 1
        if previewScale <= 0 then previewScale = 1 end
        local iconWidth = tonumber(placedForSize.size) or 18
        if (placedForSize.type or "icon") == "bar" then iconWidth = tonumber(placedForSize.barWidth) or (iconWidth * 3) end
        local iconHeight = tonumber(placedForSize.size) or 18
        iconWidth, iconHeight = iconWidth * previewScale, iconHeight * previewScale
        local rx = (cursorX - left) / width
        local ry = 1 - ((cursorY - bottom) / height)
        local anchor = st.ResolveAnchor(rx, ry)
        local frac = SPELL_DROP_ANCHOR_FRAC[anchor] or SPELL_DROP_ANCHOR_FRAC.CENTER
        local anchorX = cursorX + ((frac[1] - 0.5) * iconWidth)
        local anchorY = cursorY + ((frac[2] - 0.5) * iconHeight)
        local offX, offY = st.PointOffset(anchorX, anchorY, mock, anchor)
        local nextX, nextY = st.OffsetToConfig(offX, previewScale), st.OffsetToConfig(offY, previewScale)
        local placedSuccessfully = false
        local function PlaceSpellIcon()
            local cfg = SpellConfigForHandle(dropHandle, true)
            local placed = SpellPlacedForHandle(dropHandle, true)
            if not (placed and cfg) then return false end
            local conf = H.Conf(kind)
            local si = conf and conf.spellIndicators
            if si then si.enabled = true end
            cfg.enabled = true
            placed.type = (placed.type and placed.type ~= "none") and placed.type or "icon"
            placed.anchor, placed.x, placed.y = anchor, nextX, nextY
            SelectSpellAura(M, kind, si, specKey, auraName)
            st.RefreshGroupPreviewAfterMove(dropHandle)
            placedSuccessfully = true
            return true
        end
        local historyKey = "group:spellDrop:" .. tostring(kind) .. ":" .. tostring(specKey) .. ":" .. tostring(auraName)
        if type(M.RunWithHistory) == "function" then
            M.RunWithHistory("Place Spell Indicator", historyKey, PlaceSpellIcon)
        else
            PlaceSpellIcon()
            if placedSuccessfully then st.CheckpointHandleHistory(dropHandle, "Place") end
        end
        if not placedSuccessfully then return false, "spell-config-unavailable" end
        if M.RequestRefresh then M.RequestRefresh(nil, "gf-spell-drop-controls") end
        return true, anchor, nextX, nextY
    end
end

--- Text handles (name, HP and power groups/slots) and the
--- box:FocusTextSlot API.
function Stage.CreateTextHandles(st)
    local CreatePreviewHandle, H, box = st.CreatePreviewHandle, st.H, st.box
    local textHandles = {}
    for i = 1, #TEXT_HANDLES do
        local row = TEXT_HANDLES[i]
        local color, kind, slot = row[4], row[5], row[6]
        local handle = CreatePreviewHandle(row[2], "text", color, row[3], 74, 18, false)
        handle._cfgText = true
        handle._cfgTextKind = kind
        handle._cfgTextSlot = slot
        handle._previewText = H.TextLabel(kind, slot)
        if handle.SetBackdropColor then handle:SetBackdropColor(0, 0, 0, 0) end
        if handle.SetBackdropBorderColor then handle:SetBackdropBorderColor(color[1], color[2], color[3], 0) end
        if handle._label then handle._label:Hide() end
        textHandles[row[1]] = handle
    end
    box._textHandles = textHandles
    function box:FocusTextSlot(kind, slot, active)
        kind = H.NormalizeTextFocusKind(kind)
        slot = H.NormalizeTextFocusSlot(slot)
        self._msufMenuTextFocus = kind and { kind = kind, slot = slot, active = active == true } or nil
        RequestBoxRefresh(self, kind and "GROUP_PREVIEW_TEXT_FOCUS" or "GROUP_PREVIEW_TEXT_CLEAR_FOCUS")
        return true
    end
end

--- Public handle bundle consumed by the group preview render layer.
function Stage.BuildBundle(st)
    local bundle = {}
    for i = 1, #HANDLE_BUNDLE_KEYS do
        bundle[HANDLE_BUNDLE_KEYS[i]] = st[HANDLE_BUNDLE_KEYS[i]]
    end
    return bundle
end

local function VisibleGroupPreview()
    local found
    local previews = M._gfNativePreviews
    for i = 1, #(previews or {}) do
        local box = previews[i]
        local visible = box
            and not box._msufGFNativePreviewDisposed
            and box.IsShown and box:IsShown()
            and (not box.IsVisible or box:IsVisible())
        if visible then
            if found and found ~= box then return nil, "ambiguous-preview" end
            found = box
        end
    end
    if not found then return nil, "preview-not-visible" end
    return found
end
-- UpdateSpellDropTarget runs every frame while a spell tile is dragged: these entry points stay a single
-- VisibleGroupPreview call plus the method call, with no shared dispatch helper in between.
M.GroupPreview = M.GroupPreview or {}
function M.GroupPreview.UpdateSpellDropTarget(active, spellLabel)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.SetSpellDropTarget) ~= "function" then return false, "spell-drop-api-unavailable" end
    return box:SetSpellDropTarget(active == true, spellLabel)
end
function M.GroupPreview.DropSpellIndicatorAtCursor(specKey, auraName)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.DropSpellIndicatorAtCursor) ~= "function" then return false, "spell-drop-api-unavailable" end
    return box:DropSpellIndicatorAtCursor(specKey, auraName)
end
function M.GroupPreview.NudgeHandle(handleKey, dx, dy)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.NudgeHandleExact) ~= "function" then return false, "nudge-api-unavailable" end
    return box:NudgeHandleExact(handleKey, dx, dy)
end
function M.GroupPreview.Pan(dx, dy)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.PanExact) ~= "function" then return false, "pan-api-unavailable" end
    return box:PanExact(dx, dy)
end
ExportPublic("MSUF_GroupPreview_NudgeHandle", function(handleKey, dx, dy)
    return M.GroupPreview.NudgeHandle(handleKey, dx, dy)
end)
ExportPublic("MSUF_GroupPreview_Pan", function(dx, dy)
    return M.GroupPreview.Pan(dx, dy)
end)
