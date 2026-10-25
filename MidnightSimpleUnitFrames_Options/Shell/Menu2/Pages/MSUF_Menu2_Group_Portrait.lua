-- Group portrait editor; shared scope and history remain in the foundation.
local _, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.GroupPageParts
local W = Parts.W
local Schema = Parts.Schema
local Shared = Parts.Shared
local VT = Parts.VT
local floor = Parts.floor
local max = Parts.max
local min = Parts.min
local DeclarePartySetting = Parts.DeclarePartySetting
local GroupControlMeta = Parts.GroupControlMeta
local RegisterGroupControl = Parts.RegisterGroupControl
local Conf = Parts.Conf
local Val = Parts.Val
local QueueGF = Parts.QueueGF
local Set = Parts.Set
local Bool = Parts.Bool
local Num = Parts.Num
local CurrentScope = Parts.CurrentScope
local RefreshContext = Parts.RefreshContext
local SetSectionHeaderStatus = Parts.SetSectionHeaderStatus
local GroupPage = Parts.GroupPage

--- Party portrait workspace. Bindings are intentionally fixed to gf_party
--- rather than CurrentScope: the shell is hidden outside Party and Raid/Mythic
--- never receive portrait settings through the dynamic Group binding path.
local function PreparePartyPortraitSwitch(ctx, sec)
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local kind = "party"
    local function SetValue(key, value)
        Set(kind, key, value, "config")
        RefreshContext(ctx)
    end
    M._msuf2LastGroupPortraitSide = M._msuf2LastGroupPortraitSide or "LEFT"
    local portraitEnable
    portraitEnable = Schema.Build(ctx, sec, {
        { "sectionSwitch", "portraitMode", nil, { "Portrait" },
            meta = DeclarePartySetting(GroupControlMeta(ctx, "portrait.enabled"), "portraitMode"), scope = kind, domain = "config",
            get = function() return Val(kind, "portraitMode", "OFF") ~= "OFF" end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(value)
                local mode = Val(kind, "portraitMode", "OFF")
                if value then
                    SetValue("portraitMode", M._msuf2LastGroupPortraitSide)
                else
                    if mode == "LEFT" or mode == "RIGHT" then M._msuf2LastGroupPortraitSide = mode end
                    SetValue("portraitMode", "OFF")
                end
                if portraitEnable.refreshDetails then portraitEnable.refreshDetails() end
            end },
    }, Schema.UnitOptions()).portraitMode
    portraitEnable:SetChecked(Val(kind, "portraitMode", "OFF") ~= "OFF")
    return portraitEnable
end
-- Party portrait workspace. GroupPage.BuildPortrait runs a sequence of stages that share one state
-- table (`s`): shell, binders, tabs, controls and gates. The stages create their widgets in the order
-- the single builder did, so the layout is unchanged. The stages live on one table so the main chunk
-- keeps its local budget.
local PortraitBuild = {}
function PortraitBuild.Shell(ctx, builder)
    local s = { kind = "party", stateKey = "gf_party" }
    local cardH = { main = 224, geometry = 440, placement = 382, border = 440, style = 330 }
    local tabH = {
        general = cardH.main + 116,
        geometry = cardH.geometry + 116,
        placement = cardH.placement + 116,
        border = cardH.border + 116,
        advanced = cardH.style + 116,
    }
    local placementValues = Shared.PortraitPlacementValues()
    local renderValues = VT("2D", "2D portrait", "CLASS", "Class portrait")
    local sizeModeValues = VT("UNIFORM", "Uniform", "SEPARATE", "Width & height")
    local shapeValues = VT("SQUARE", "Square", "CIRCLE", "Circle", "ROUNDED", "Rounded", "DIAMOND", "Diamond")
    local borderValues = VT("NONE", "No border", "SOLID", "Solid", "CLASS_COLOR", "Class color", "REACTION", "Reaction color", "CUSTOM", "Custom color")
    local function ClassStyleValues()
        local media = MSUF and MSUF.PortraitMedia
        local source = media and media.GetPackOptions and media.GetPackOptions()
            or { { value = "BLIZZARD", text = "Blizzard Class Icon" } }
        local values = {}
        for i = 1, #source do
            local item = source[i]
            values[#values + 1] = {
                value = item.value or item.key,
                text = item.text or item.label or item.value or item.key,
            }
        end
        return values
    end
    local function NormalizeTab(value)
        if value ~= "general" and value ~= "geometry" and value ~= "placement"
            and value ~= "border" and value ~= "advanced" then
            return "general"
        end
        return value
    end
    M.unitPortraitTabSelection = M.unitPortraitTabSelection or {}
    local stateKey = "gf_party"
    local currentTab = NormalizeTab(M.unitPortraitTabSelection[stateKey])
    M.unitPortraitTabSelection[stateKey] = currentTab
    local initialHeight = tabH[currentTab] or tabH.general
    local sec = builder:CollapsibleSection("portrait", "Portrait", initialHeight, false)
    Schema.Section(sec, "party")
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local cardX = 16
    local cardW = max(260, min(620, sectionW - 32))
    local tabW = max(260, min(780, sectionW - 40))
    local RefreshPortraitControls = M.RefreshProxy()
    s.cardH, s.tabH, s.placementValues, s.renderValues = cardH, tabH, placementValues, renderValues
    s.sizeModeValues, s.shapeValues, s.borderValues = sizeModeValues, shapeValues, borderValues
    s.ClassStyleValues, s.NormalizeTab = ClassStyleValues, NormalizeTab
    s.sec, s.sectionW, s.cardX, s.cardW, s.tabW = sec, sectionW, cardX, cardW, tabW
    s.RefreshPortraitControls = RefreshPortraitControls
    return s
end
function PortraitBuild.Binders(ctx, s)
    local kind, stateKey = s.kind, s.stateKey
    local function AttachPortraitFocus(widget)
        W.AttachGroupEditFocus(widget, stateKey, "portrait")
        return widget
    end
    local function PortraitMeta(path, key, extraKeys)
        local meta = GroupControlMeta(ctx, "portrait." .. tostring(path))
        if key then
            meta.searchSettingKeys = { "gf_party." .. tostring(key) }
        end
        if extraKeys then
            meta.searchSettingKeys = extraKeys
        end
        return DeclarePartySetting(meta, key or extraKeys[1]:sub(#"gf_party." + 1))
    end
    local function SetValue(key, value)
        Set(kind, key, value, "config")
        RefreshContext(ctx)
    end
    local function RegisterPreviewOffsetVirtual(axis, key, label)
        if not M.RegisterVirtualRuntimeControl then return end
        local path = "preview.selection.portrait_offset_" .. tostring(axis)
        local meta = GroupControlMeta(ctx, path, "setting")
        meta.kind = "textinput"
        meta.label = label
        DeclarePartySetting(meta, tostring(key))
        meta.searchSettingKeys = { meta.settingKey }
        meta.command = {
            kind = "textinput",
            historyMode = "single",
            interaction = "preview.handle.offset",
            previewSurface = "group",
            previewHandleKey = "portrait",
            previewScope = "party",
            get = function() return tonumber(Val(kind, key, 0)) or 0 end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", write = { virtual = true,
                call = SetValue, keyOnly = true, validNumber = true, success = true
            } --[[schema setter: H4.Group.2]],
        }
        M.RegisterVirtualRuntimeControl(meta, "group-preview-offset")
    end
    RegisterPreviewOffsetVirtual("x", "portraitOffsetX", "Party Portrait X Offset")
    RegisterPreviewOffsetVirtual("y", "portraitOffsetY", "Party Portrait Y Offset")
    -- Fixed Party access is deliberate: these controls must never follow gfScope.
    s.rowOptions = { bind = function(c, widget, row, controlKind)
        local key, default = row[2], row[3]
        local meta = row.meta or PortraitMeta(key, key)
        local get, set = row.get, row.set
        if controlKind == "color" then
            local rKey, gKey, bKey = key .. "R", key .. "G", key .. "B"
            meta = PortraitMeta(key, nil, { "gf_party." .. rKey, "gf_party." .. gKey, "gf_party." .. bKey })
            get = function() return Num(kind, rKey, default[1]), Num(kind, gKey, default[2]), Num(kind, bKey, default[3]) end
            set = function(r, g, b)
                local conf = Conf(kind)
                if conf[rKey] == r and conf[gKey] == g and conf[bKey] == b then return end
                conf[rKey], conf[gKey], conf[bKey] = r, g, b
                QueueGF(kind, "config")
                RefreshContext(ctx)
            end
        elseif not get then
            get = function()
                local read = controlKind == "toggle" and Bool or controlKind == "slider" and Num or Val
                local value = read(kind, key, default)
                return row.normalize and row.normalize(value) or value
            end
            if row.normalize then
                row.customSetReason = "Normalizes the selected portrait mode before the fixed Party write."
                set = nil
                row.write = {
                    call = SetValue, keyOnly = true,
                    convert = function(value)
                        if controlKind == "toggle" then return value and true or false end
                        if controlKind == "slider" then return tonumber(value) or default end
                        return row.normalize and row.normalize(value or default) or (value or default)
                    end, after = row.afterSet
                } --[[schema setter: H4.Group.4]]
            else
                row.write = { call = SetValue, keyOnly = true, boolean = controlKind == "toggle",
                    numberDefault = controlKind == "slider" and default or nil,
                    after = row.afterSet } --[[schema setter: Group.Portrait]]
                if controlKind ~= "toggle" and controlKind ~= "slider" then row.write.fallback = default end
            end
        end
        Schema.UnitBinding(c, widget, { row[1], key, default, row[4], meta = meta,
            scope = "party", domain = "config", get = get, set = set, write = row.write,
            customSetReason = row.customSetReason or "Normalizes portrait values and coordinates the fixed Party editor.",
                roundStep = controlKind == "slider" }, controlKind)
        AttachPortraitFocus(widget)
    end }
    s.AttachPortraitFocus, s.PortraitMeta, s.SetValue = AttachPortraitFocus, PortraitMeta, SetValue
end
function PortraitBuild.Tabs(ctx, s)
    local stateKey = s.stateKey
    local tabH, NormalizeTab = s.tabH, s.NormalizeTab
    local sec, sectionW, cardX, cardW, tabW, cardH = s.sec, s.sectionW, s.cardX, s.cardW, s.tabW, s.cardH
    local RefreshPortraitControls, AttachPortraitFocus = s.RefreshPortraitControls, s.AttachPortraitFocus
    local function SetSectionHeight(height)
        height = max(120, floor((tonumber(height) or tabH.general) + 0.5))
        local entry = sec and sec._msuf2CollapsibleEntry
        if entry then
            -- The Portrait content builds lazily after its Party-only shell has
            -- already been hidden for Raid/Mythic.  Preserve the desired Party
            -- tab height, but never let that deferred build reactivate space in
            -- a scope where the section is unavailable.
            entry._msufPartyPortraitContentHeight = height
            local appliedHeight = entry._msufPartyPortraitVisible == false and 0 or height
            entry.contentHeight = appliedHeight
            if sec and sec.SetHeight then sec:SetHeight(appliedHeight) end
            if entry.body and entry.body.SetHeight then entry.body:SetHeight(appliedHeight) end
            if entry.outer and entry.outer.SetHeight then
                entry.outer:SetHeight((entry.headerHeight or 28) + (entry.open and appliedHeight or 0))
            end
            if entry.builder and entry.builder.RequestRelayoutCollapsibles then entry.builder:RequestRelayoutCollapsibles() end
        elseif sec and sec.SetHeight then
            sec:SetHeight(height)
        end
    end
    local tabFrames = {}
    local generalTab, geometryTab, placementTab, borderTab, advancedTab =
        Shared.MakeTabFrames(sec, -64, sectionW, tabFrames, "general", "geometry", "placement", "border", "advanced")
    local cards = {}
    for _, card in ipairs({ { generalTab, "main", "Visibility & Mode" }, { geometryTab, "geometry", "Geometry" },
        { placementTab, "placement", "Placement" }, { borderTab, "border", "Shape & Border" }, { advancedTab, "style", "Class & Background" } }) do
        Schema.Build(ctx, card[1], {
            { "card", card[2], nil, { card[3], nil, cardX, -4, cardW, cardH[card[2]] },
                meta = GroupControlMeta(ctx, "portrait.card." .. card[2]), scope = "group", domain = "layout" },
        }, nil, cards)
    end
    local mainCard, geometryCard, placementCard, borderCard, styleCard = cards.main, cards.geometry, cards.placement, cards.border, cards.style
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(borderCard, { "group.portrait.border" }, {
            title = "Portrait Border Color",
            note = "Configure the Party portrait border color and opacity.",
            historySource = "menu:group-portrait-border-color",
        })
    end
    local narrow = sectionW < 700
    local portraitTabs, RefreshTabs, ReadTab, SetGuidedTab = W.SegmentTabs(ctx, sec, {
        label = "",
        values = narrow
            and VT("general", "General", "placement", "Place", "geometry", "Size", "border", "Border", "advanced", "More")
            or VT("general", "General", "placement", "Placement", "geometry", "Size & Zoom", "border", "Shape & Border", "advanced", "More Options"),
        width = tabW,
        frames = tabFrames,
        defaultTab = "general",
        get = function() return NormalizeTab(M.unitPortraitTabSelection[stateKey]) end,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.",
            set = function(value) M.unitPortraitTabSelection[stateKey] = NormalizeTab(value) end,
        afterRefresh = function(tab) SetSectionHeight(tabH[NormalizeTab(tab)] or tabH.general) end,
        x = 20,
        y = -12,
    })
    if portraitTabs._msuf2Title then portraitTabs._msuf2Title:Hide() end
    AttachPortraitFocus(portraitTabs)
    RegisterGroupControl(portraitTabs, ctx, "portrait.workspace_tab", "Portrait area", "segment", "ephemeral")
    Schema.Owned(portraitTabs, "group", "navigation")
    sec._msuf2GuidedSelectTab = function(tab)
        tab = NormalizeTab(tab)
        if ReadTab and ReadTab() == tab then return true end
        if SetGuidedTab then SetGuidedTab(tab)
        else
            M.unitPortraitTabSelection[stateKey] = tab
            if RefreshTabs then RefreshTabs() end
        end
        return not ReadTab or ReadTab() == tab
    end
    local portraitEnable = PreparePartyPortraitSwitch(ctx, sec)
    portraitEnable.refreshDetails = function() RefreshPortraitControls() end
    AttachPortraitFocus(portraitEnable)
    s.mainCard, s.geometryCard, s.placementCard, s.borderCard, s.styleCard = mainCard, geometryCard, placementCard, borderCard, styleCard
    s.portraitEnable = portraitEnable
end
function PortraitBuild.Controls(ctx, s)
    local kind, cardW = s.kind, s.cardW
    local mainCard, geometryCard, placementCard, borderCard, styleCard = s.mainCard, s.geometryCard, s.placementCard, s.borderCard, s.styleCard
    local renderValues, sizeModeValues, shapeValues, borderValues = s.renderValues, s.sizeModeValues, s.shapeValues, s.borderValues
    local placementValues, ClassStyleValues = s.placementValues, s.ClassStyleValues
    local RefreshPortraitControls, PortraitMeta, SetValue = s.RefreshPortraitControls, s.PortraitMeta, s.SetValue
    local options, controls = s.rowOptions, {}
    Schema.Build(ctx, mainCard, {
        { "segment", "position", nil, { "Position", VT("LEFT", "Left", "RIGHT", "Right"), min(220, cardW - 32) },
            { 16, -62, min(220, cardW - 32) },
            meta = PortraitMeta("position", "portraitMode"),
            get = function() return Val(kind, "portraitMode", "OFF") == "RIGHT" and "RIGHT" or "LEFT" end,
            write = { call = SetValue, keyOnly = true,
                convert = function(value) return value == "RIGHT" and "RIGHT" or "LEFT" end,
                before = function(value) M._msuf2LastGroupPortraitSide = value end, after = RefreshPortraitControls
            } --[[schema setter: J5.GroupPortrait.Position]] },
        { "dropdown", "portraitRender", "2D", { "Render", renderValues, 220 }, { 16, -116, min(220, cardW - 32) }, afterSet = RefreshPortraitControls },
        { "toggle", "portraitClickable", false, { "Clickable portrait", 16, -174, cardW - 32 },
            flagsAfter = { _msuf2SearchText = "Clickable portrait group frame target right click menu click casting mouseover" } },
    }, options, controls)
    Schema.Build(ctx, borderCard, {
        { "dropdown", "portraitShape", "SQUARE", { "Shape", shapeValues, 220 }, { 16, -58, min(220, cardW - 32) }, afterSet = RefreshPortraitControls },
    }, options, controls)
    Schema.Build(ctx, geometryCard, {
        { "segment", "portraitSizeMode", nil, { "Size mode", sizeModeValues, min(360, cardW - 32) },
            { 16, -62, min(360, cardW - 32) },
            get = function()
                local conf = Conf(kind)
                local mode = conf.portraitSizeMode
                if mode == "UNIFORM" or mode == "SEPARATE" then return mode end
                return ((tonumber(conf.portraitWidth) or 0) > 0 or (tonumber(conf.portraitHeight) or 0) > 0)
                    and "SEPARATE" or "UNIFORM"
            end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", write = {
                call = SetValue, keyOnly = true,
                convert = function(value) return value == "SEPARATE" and "SEPARATE" or "UNIFORM" end,
                after = RefreshPortraitControls
            } --[[schema setter: H4.Group.7]] },
        { "slider", "portraitSizeOverride", 0, { "Size override", 0, 128, 1, 280 }, { 16, -116, cardW - 58, "CENTER" } },
        { "slider", "portraitWidth", 0, { "Width override", 0, 256, 1, 280 }, { 16, -170, cardW - 58, "CENTER" } },
        { "slider", "portraitHeight", 0, { "Height override", 0, 256, 1, 280 }, { 16, -224, cardW - 58, "CENTER" } },
        -- 100-300 %, matching the portrait runtime and unit controls.
        { "slider", "portraitZoom", 100, { "Portrait zoom", 100, 300, 1, 280 }, { 16, -278, cardW - 58, "CENTER" } },
        { "slider", "portraitPanX", 0, { "Zoom center X", -100, 100, 1, 280 }, { 16, -332, cardW - 58, "CENTER" } },
        { "slider", "portraitPanY", 0, { "Zoom center Y", -100, 100, 1, 280 }, { 16, -386, cardW - 58, "CENTER" } },
    }, options, controls)
    Schema.Build(ctx, placementCard, {
        { "dropdown", "portraitPlacement", "ATTACHED", { "Placement", placementValues.modes, 220 },
            { 16, -58, min(220, cardW - 32) }, afterSet = RefreshPortraitControls,
            flagsAfter = { _msuf2SearchText = "Portrait placement attached detached overlay free position anchor" } },
        { "dropdown", "portraitDetachedPoint", "RIGHT", { "Portrait anchor point", placementValues.points, 220 }, { 16, -112, min(220, cardW - 32) } },
        { "dropdown", "portraitDetachedTo", "LEFT", { "Attach to frame point", placementValues.points, 220 }, { 16, -166, min(220, cardW - 32) } },
        { "dropdown", "portraitOverlayAlign", "LEFT", { "Overlay alignment", placementValues.overlay, 220 }, { 16, -220, min(220, cardW - 32) } },
        { "slider", "portraitLevelOffset", 7, { "Layer offset", 0, 30, 1, 280 }, { 16, -274, cardW - 58, "CENTER" },
            flagsAfter = { _msuf2SearchText = "Portrait layer offset frame level behind in front of bars" } },
        { "slider", "portraitAlpha", 100, { "Portrait opacity", 0, 100, 1, 280 }, { 16, -328, cardW - 58, "CENTER" } },
    }, options, controls)
    Schema.Build(ctx, borderCard, {
        { "dropdown", "portraitBorderStyle", "NONE", { "Border", borderValues, 220 }, { 16, -112, min(220, cardW - 32) }, afterSet = RefreshPortraitControls },
        { "slider", "portraitEdgeSoftness", 0, { "Portrait edge softness", 0, 30, 2, 280 }, { 16, -166, cardW - 58, "CENTER" },
            flagsAfter = { _msuf2SearchText = "Portrait edge softness feather fade borderless percent" } },
        { "dropdown", "portraitBorderArt", "FLAT", { "Border art", placementValues.borderArt, 220 },
            { 16, -220, min(220, cardW - 32) }, afterSet = RefreshPortraitControls },
        { "dropdown", "portraitBorderDirection", "UP", { "Border direction", placementValues.borderDirection, 220 }, { 16, -274, min(220, cardW - 32) } },
        { "slider", "portraitBorderThickness", 2, { "Border thickness", 1, 12, 1, 280 }, { 16, -328, cardW - 58, "CENTER" } },
        { "toggle", "portraitFillBorder", false, { "Fill border into frame gap", 16, -396, cardW - 32 } },
    }, options, controls)
    Schema.Build(ctx, styleCard, {
        { "dropdown", "portraitClassStyle", "BLIZZARD", { "Class portrait style", ClassStyleValues, 220 },
            { 16, -58, min(220, cardW - 32) }, normalize = M.NormalizePortraitClassStyle },
        { "toggle", "portraitBgEnabled", false, { "Portrait background", 16, -112, cardW - 32 }, afterSet = RefreshPortraitControls },
        { "color", "portraitBgColor", { 0.05, 0.05, 0.05 }, { "Portrait Background Color" }, { 16, -158, min(260, cardW - 32), "LEFT" } },
        { "slider", "portraitBgColorA", 0.85, { "Background opacity", 0, 1, 0.05, 280 }, { 16, -210, cardW - 58, "CENTER" }, beforeBind = M.UsePercentInput },
        { "toggle", "portraitCastSpellIcon", false, { "Show cast spell icon in portrait", 16, -274, cardW - 32 },
            flagsAfter = { _msuf2SearchText = "Portrait cast spell icon casting channel empower" } },
    }, options, controls)
    s.controls = controls
end
function PortraitBuild.Gates(ctx, s)
    local kind, sec, portraitEnable, RefreshPortraitControls = s.kind, s.sec, s.portraitEnable, s.RefreshPortraitControls
    local c = s.controls
    local activeControls = {
        c.portraitRender, c.portraitClickable, c.portraitShape, c.portraitSizeMode, c.portraitSizeOverride, c.portraitWidth,
        c.portraitHeight, c.portraitPlacement, c.portraitLevelOffset, c.portraitAlpha, c.portraitBorderStyle,
        c.portraitEdgeSoftness, c.portraitBgEnabled, c.portraitCastSpellIcon,
    }
    local function Active(conf) return (conf.portraitMode or "OFF") ~= "OFF" end
    local function Placed(conf, value)
        return Active(conf) and (conf.portraitPlacement or "ATTACHED") == value
    end
    local function FillsBar(conf)
        return (conf.portraitPlacement or "ATTACHED") == "OVERLAY"
            and (conf.portraitOverlayAlign or "LEFT") == "FULL"
    end
    local function UsesSeparateSize(conf)
        local mode = conf.portraitSizeMode
        if mode == "SEPARATE" then return true end
        if mode == "UNIFORM" then return false end
        return (tonumber(conf.portraitWidth) or 0) > 0 or (tonumber(conf.portraitHeight) or 0) > 0
    end
    RefreshPortraitControls = RefreshPortraitControls(M.BindGateGroup(ctx, function() return Conf(kind) end, {
        { enable = { portraitEnable } },
        { controls = activeControls, on = Active, reason = W.TurnOnReason and W.TurnOnReason("Portrait") },
        { controls = c.position, on = function(conf) return Placed(conf, "ATTACHED") end },
        { controls = { c.portraitDetachedPoint, c.portraitDetachedTo }, on = function(conf) return Placed(conf, "DETACHED") end },
        { controls = c.portraitOverlayAlign, on = function(conf) return Placed(conf, "OVERLAY") end },
        { controls = c.portraitSizeMode, on = function(conf) return Active(conf) and not FillsBar(conf) end },
        { controls = c.portraitSizeOverride, on = function(conf)
            return Active(conf) and not FillsBar(conf) and not UsesSeparateSize(conf)
        end },
        { controls = { c.portraitWidth, c.portraitHeight }, on = function(conf)
            return Active(conf) and not FillsBar(conf) and UsesSeparateSize(conf)
        end },
        { controls = { c.portraitZoom, c.portraitPanX, c.portraitPanY },
            on = function(conf) return Active(conf) and (conf.portraitRender or "2D") ~= "CLASS" end },
        { controls = c.portraitEdgeSoftness, on = function(conf)
            return Active(conf)
                and (conf.portraitShape or "SQUARE") ~= "BLIZZARD"
                and (conf.portraitBorderStyle or "NONE") == "NONE"
        end },
        { controls = { c.portraitBorderThickness, c.portraitBorderArt },
            on = function(conf) return Active(conf) and (conf.portraitBorderStyle or "NONE") ~= "NONE" end },
        { controls = c.portraitBorderDirection, on = function(conf)
            return Active(conf) and (conf.portraitBorderStyle or "NONE") ~= "NONE"
                and (conf.portraitBorderArt or "FLAT") == "RELIEF"
        end },
        { controls = c.portraitFillBorder, on = function(conf)
            return Active(conf) and (conf.portraitBorderStyle or "NONE") ~= "NONE"
                and (conf.portraitShape or "SQUARE") == "SQUARE"
                and (conf.portraitBorderArt or "FLAT") ~= "RELIEF"
        end },
        { controls = c.portraitClassStyle, on = function(conf) return Active(conf) and (conf.portraitRender or "2D") == "CLASS" end },
        { controls = { c.portraitBgColor, c.portraitBgColorA },
            on = function(conf) return Active(conf) and conf.portraitBgEnabled == true end },
    }, {
        also = function() SetSectionHeaderStatus(sec, nil) end,
        track = function(c, refresh) return M.TrackCollapsibleRefresh(c, sec, refresh) end,
    }))
    if sec._msufPartyPortraitRefresh then sec._msufPartyPortraitRefresh() end
end
function GroupPage.BuildPortrait(ctx, builder)
    local s = PortraitBuild.Shell(ctx, builder)
    PortraitBuild.Binders(ctx, s)
    PortraitBuild.Tabs(ctx, s)
    PortraitBuild.Controls(ctx, s)
    PortraitBuild.Gates(ctx, s)
end

--- Hide and collapse the Portrait shell outside Party without destroying the
--- cached page. Restoring the original geometry makes scope switching cheap
--- and keeps Raid/Mythic controls completely inaccessible.
function GroupPage.PreparePortraitShell(ctx, section)
    Schema.Section(section, "party")
    PreparePartyPortraitSwitch(ctx, section)
    local entry = section and section._msuf2CollapsibleEntry
    if not entry then return end
    entry._msufPartyPortraitHeaderHeight = entry._msufPartyPortraitHeaderHeight or entry.headerHeight
    entry._msufPartyPortraitContentHeight = entry._msufPartyPortraitContentHeight or entry.contentHeight
    local function Refresh()
        local shown = CurrentScope() == "party"
        entry._msufPartyPortraitVisible = shown
        if shown then
            entry.headerHeight = entry._msufPartyPortraitHeaderHeight or 28
            entry.contentHeight = entry._msufPartyPortraitContentHeight or entry.contentHeight or 340
            if entry.outer then entry.outer:Show() end
        else
            if (entry.contentHeight or 0) > 0 then entry._msufPartyPortraitContentHeight = entry.contentHeight end
            entry.headerHeight, entry.contentHeight = 0, 0
            if entry.outer then entry.outer:Hide() end
        end
        if entry.body and entry.body.SetHeight then entry.body:SetHeight(entry.contentHeight or 0) end
        if entry.outer and entry.outer.SetHeight then
            entry.outer:SetHeight((entry.headerHeight or 0) + (entry.open and (entry.contentHeight or 0) or 0))
        end
        if entry.builder and entry.builder.RequestRelayoutCollapsibles then entry.builder:RequestRelayoutCollapsibles() end
    end
    section._msufPartyPortraitRefresh = Refresh
    if M.AddRefresherOnce then M.AddRefresherOnce(ctx, "group-party-portrait-shell", Refresh)
    elseif M.AddRefresher then M.AddRefresher(ctx, Refresh) end
    Refresh()
    return Refresh
end

