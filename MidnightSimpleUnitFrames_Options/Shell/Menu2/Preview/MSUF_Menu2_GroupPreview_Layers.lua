-- Group preview layers owner.
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
local Chrome = RequireFields("GroupLayers.Chrome", M.GroupPreviewChrome, "ApplyGroupChrome LAYER_HEADER_COLOR LayerFont UpdateHint")
local ApplyGroupChrome = Chrome.ApplyGroupChrome
local LAYER_HEADER_COLOR = Chrome.LAYER_HEADER_COLOR
local LayerFont = Chrome.LayerFont
local UpdateHint = Chrome.UpdateHint
local Selection = RequireFields("GroupLayers.Selection", M.GroupPreviewSelection, "OpenGFSection")
local OpenGFSection = Selection.OpenGFSection

local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Menu2/GroupPreview_Layers")
local Layers = {}
--- What a group layer chip does. The layer flags themselves live in M.gfPreviewLayerVisible, shared by every group preview.
local GroupLayerChip = {}
function GroupLayerChip.Available(owner, key)
    return not (owner and owner._layerAvailable and owner._layerAvailable[key] == false)
end
function GroupLayerChip.On(owner, key)
    if not GroupLayerChip.Available(owner, key) then return false end
    if M.gfPreviewSoloLayer ~= nil then return M.gfPreviewSoloLayer == key end
    return M.gfPreviewLayerVisible[key] ~= false
end
function GroupLayerChip.Refresh(owner)
    for j = 1, #(owner._layerButtons or {}) do owner._layerButtons[j]:Refresh() end
    PreviewHelpers.RefreshSampleEffectHint(owner)
    if owner.RequestRefresh then owner:RequestRefresh("GROUP_PREVIEW_LAYER")
    elseif owner.Refresh then owner:Refresh("GROUP_PREVIEW_LAYER") end
end
--- The sample-effect hint hides every painted sample layer exactly as a plain click on its chip would.
function GroupLayerChip.HideSamples(owner)
    local visible, state, changed = M.gfPreviewLayerVisible, M._msuf2SampleLayers, false
    for i = 1, #(owner._layerButtons or {}) do
        local key = owner._layerButtons[i].key
        if PreviewHelpers.IsSampleEffectLayer(key) and GroupLayerChip.On(owner, key) then
            M.gfPreviewSoloLayer = nil
            visible[key], changed = false, true
            if state then state.auto[key] = nil end
        end
    end
    if changed then GroupLayerChip.Refresh(owner) end
end
function GroupLayerChip.Click(self, owner)
    if not GroupLayerChip.Available(owner, self.key) then
        if GameTooltip then GameTooltip:Hide() end
        OpenGFSection(self._sectionKey)
        return
    end
    local visible, sampleState = M.gfPreviewLayerVisible, M._msuf2SampleLayers
    if IsShiftKeyDown and IsShiftKeyDown() then
        local solo
        if M.gfPreviewSoloLayer ~= self.key then solo = self.key end
        M.gfPreviewSoloLayer = solo
        -- Soloing a sample layer is asking for it, so it has to paint.
        if solo and PreviewHelpers.IsSampleEffectLayer(solo) and visible[solo] == false then
            visible[solo] = true
            if sampleState then sampleState.auto[solo] = nil end
        end
    else
        M.gfPreviewSoloLayer = nil
        visible[self.key] = visible[self.key] == false
        -- A chip click is the user's own choice: the settings section no longer owns this layer's state.
        if sampleState then sampleState.auto[self.key] = nil end
    end
    GroupLayerChip.Refresh(owner)
end
function GroupLayerChip.Enter(self, owner, available, on, tr)
    local label = self.fs and self.fs:GetText() or tr("Layer")
    if available and PreviewHelpers.IsSampleEffectLayer(self.key) and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        PreviewHelpers.AddSampleEffectTooltipLine(self.key, tr)
        GameTooltip:Show()
    end
    if not owner._hint then return end
    if not available then
        owner._hint:SetText(string.format(tr("%s is off in settings. Click to open its options."), label))
        return
    end
    local solo = M.gfPreviewSoloLayer == self.key
    local action = solo and "Shift-click clears solo layer" or (on and "click to hide - Shift-click to solo" or "click to show")
    owner._hint:SetText(label .. " - " .. tr(action))
end
--- Preview layers: label, swatch colour, owning settings section, layer key and whether the layer starts on.
--- The order follows the Unit preview wherever the two share concepts: guides, text, portrait, resources,
--- content, status, then the optional bounds measurement at the far right. The configured frame outline
--- is rendered independently, so Bounds is only the cyan measurement guide and starts off; sample-effect
--- layers stay off until a chip click or their open settings section asks for them.
--- A chip whose layer is off in settings turns into a shortcut to the setting that enables it, so the
--- Dispel Symbol chip names its own accordion rather than the overlay's.
local LAYER_DEFS = {
    { "Guides", { 0.42, 0.72, 1.00 }, "layout", "guides", false },
    { "Text", { 0.70, 0.90, 1.00 }, "text", "text", true },
    { "Portrait", { 0.90, 0.42, 1.00 }, "portrait", "portrait", true },
    { "Power", { 0.30, 0.62, 0.98 }, "power", "power", true },
    { "Buffs", { 0.20, 0.90, 0.35 }, "buffs", "buff", true },
    { "Tracked", { 0.42, 0.68, 1.00 }, "buffs", "trackedBuff", true },
    { "Debuffs", { 0.90, 0.20, 0.22 }, "debuffs", "debuff", true },
    { "External", { 0.30, 0.72, 1.00 }, "externals", "external", true },
    { "Spells", { 0.86, 0.50, 1.00 }, "si", "si", true },
    { "CD/Stack", { 1.00, 0.82, 0.28 }, "textcolor", "auraText", true },
    { "Status", { 0.95, 0.78, 0.22 }, "sicons", "status", true },
    { "Dispel Overlay", { 0.25, 0.72, 1.00 }, "dispel", "dispelOverlay", false },
    { "Dispel Symbol", { 0.34, 0.84, 1.00 }, "dispelSymbol", "dispelSymbol", false },
    { "Bounds", { 0.25, 0.75, 0.88 }, "layout", "bounds", false },
}
function Layers.Build(state)
    local box, chrome, layerW, RegisterPreviewControl = state.box, state.chrome, state.layerW, state.RegisterPreviewControl
    local layers = PixelLayoutRegion(CreateFrame("Frame", nil, box, T.Template()))
    local layerColors = T.colors or {}
    ApplyGroupChrome(layers, "sidebar", layerColors.coreShadow or layerColors.panel, layerColors.borderSoft)
    -- Layer chips flow along the bottom edge instead of holding a fixed column,
    -- so the stage keeps the full card width. Same treatment as the Unit preview.
    layers:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 12)
    layers:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    layers:SetHeight(30)
    box._layers = layers
    local layersTitle = LayerFont(layers, "Preview Layers", chrome.layerHeader or (T.colors and T.colors.muted) or LAYER_HEADER_COLOR)
    layersTitle:SetPoint("LEFT", layers, "LEFT", 10, 0)
    box._msuf2LayerRailHeader = layersTitle
    if type(M.gfPreviewLayerVisible) ~= "table" then M.gfPreviewLayerVisible = {} end
    local layerVisibility = M.gfPreviewLayerVisible
    for i = 1, #LAYER_DEFS do
        local def = LAYER_DEFS[i]
        if layerVisibility[def[4]] == nil then layerVisibility[def[4]] = def[5] end
    end
    box._layerButtons = {}
    box.layerVisibility = layerVisibility
    local groupLayerButtonOpts = PreviewHelpers.LayerChipButtonOpts(Tr, layerColors, chrome, {
        IsAvailable = GroupLayerChip.Available,
        IsOn = GroupLayerChip.On,
        OnClick = GroupLayerChip.Click,
        OnEnter = GroupLayerChip.Enter,
        OnLeave = function(_, owner) UpdateHint(owner) end,
    })
    for i = 1, #LAYER_DEFS do
        local def = LAYER_DEFS[i]
        local btn = PreviewHelpers.CreateLayerButton(layers, box, {
            key = def[4], label = def[1], color = def[2],
        }, i, layerW, groupLayerButtonOpts)
        btn._sectionKey, btn._layerKey = def[3], def[4]
        btn._label, btn._stripe, btn._bg, btn._off = btn.fs, btn.bar, btn.bg, btn.off
        M.AddTooltip(btn, "Layer disabled", "Click to open the setting that enables this layer.", {
            hook = true,
            enabled = function(self) return self._layerAvailable == false end,
        })
        btn._msuf2CommandAction = {
            kind = "toggle",
            historyMode = "none",
            get = function()
                if btn._layerAvailable == false then return false end
                if M.gfPreviewSoloLayer ~= nil then return M.gfPreviewSoloLayer == btn._layerKey end
                return layerVisibility[btn._layerKey] ~= false
            end,
            set = function(enabled)
                if btn._layerAvailable == false then return false end
                enabled = enabled == true
                M.gfPreviewSoloLayer = nil
                layerVisibility[btn._layerKey] = enabled
                local sampleState = M._msuf2SampleLayers
                if sampleState then sampleState.auto[btn._layerKey] = nil end
                if box.RequestRefresh then box:RequestRefresh("GROUP_PREVIEW_SEARCH_LAYER")
                elseif box.Refresh then box:Refresh() end
                return (layerVisibility[btn._layerKey] ~= false) == enabled
            end,
        }
        RegisterPreviewControl(btn, "layer." .. tostring(def[4]), def[1] .. " preview layer", "button", "ephemeral")
        if def[4] == "portrait" then btn:Hide() end
        box._layerButtons[#box._layerButtons + 1] = btn
    end
    PreviewHelpers.SetupSampleEffectHint(box, state.stage, {
        Tr = Tr, T = T, buttons = "_layerButtons", IsOn = GroupLayerChip.On, Hide = GroupLayerChip.HideSamples,
    })
    box.LayoutLayerRail = function(self, railWidth)
        return PreviewHelpers.LayoutLayerRail(self, self._layers, self._layerButtons, railWidth)
    end
    -- The stage is the surface; the rail sits over it with its header shown.
    box.ApplyDockedPreviewLayout = function(self, bottomInset)
        return PreviewHelpers.ApplyDockedPreviewLayout(self, self._layers, self._stage, bottomInset, true)
    end
end

M.GroupPreviewLayers = Layers
