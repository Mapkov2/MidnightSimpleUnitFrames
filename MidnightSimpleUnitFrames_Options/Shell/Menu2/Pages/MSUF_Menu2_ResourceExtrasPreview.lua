local _, MSUF = ...
local M = MSUF.MSUF2
local W, T = M.Widgets, M.Theme
local Extras = {}
M.ResourceExtrasPreview = Extras

-- Only the preview choices live here. Runtime enablement stays in the profile.
local EFFECTS = {
    { key = "pain", label = "Ignore Pain", setting = "showIgnorePain" },
    { key = "arcane", label = "Arcane Window", setting = "showArcaneWindow" },
    { key = "cost", label = "Mana spend preview", setting = "manaUpcomingCost" },
    { key = "pause", label = "Regeneration pause after spending", setting = "manaRegenPause" },
    { key = "pulse", label = "Mana return pulse", setting = "manaGainPulse" },
    { key = "marks", label = "Resource marks and thresholds" },
}
local ARCANE_STATES = {
    { value = "active", text = "Active" },
    { value = "warning", text = "Warning phase" },
    { value = "soul", text = "Arcane Soul" },
}
local ACTIVE_STATE = { { value = "active", text = "Active" } }
local KEY_EFFECT = {
    showIgnorePain = "pain", ignorePainTimeMarker = "pain",
    showArcaneWindow = "arcane", arcaneWindowText = "arcane", arcaneWindowTextFrom = "arcane",
    arcaneWindowWarnSeconds = "arcane", arcaneWindowWarnLastGCD = "arcane",
    manaUpcomingCost = "cost", manaRegenPause = "pause", manaGainPulse = "pulse",
}
local selected, scenario = nil, "active"
local available, values

local function Choices()
    if values then return values end
    local _, built = M.ResourceExtrasPage.ClientOnlySettings()
    values, available = {}, {}
    for _, effect in ipairs(EFFECTS) do
        if not effect.setting or effect.key == "cost" or built["bars." .. effect.setting] then
            values[#values + 1] = { value = effect.key, text = effect.label }
            available[effect.key] = effect
        end
    end
    return values
end
function Extras.Selection()
    Choices()
    if not available[selected] then selected = values[1].value end
    return selected, scenario, available[selected]
end
function Extras.Select(effect, state)
    Choices()
    if not available[effect] then return false end
    selected = effect
    if state then
        scenario = state == "warning" and "warning" or state == "soul" and "soul" or "active"
    end
    return true
end
function Extras.FocusKey(key)
    local effect = KEY_EFFECT[key]
    if not effect and key:find("^resourceExtra") then
        effect = selected == "arcane" and "arcane" or "pain"
    end
    if effect then
        Extras.Select(effect)
        if key == "arcaneWindowWarnSeconds" or key == "arcaneWindowWarnLastGCD" then scenario = "warning" end
    end
end
function Extras.FocusPath(path)
    local key = path:match("^resource_extras%.(.+)$")
    if key and key:find("^marks%.") then Extras.Select("marks")
    elseif key then Extras.FocusKey(key) end
end

local function Refresh(page)
    Extras.UpdateHeader(page.ctx, page.workspace.selected)
    M.RequestRefresh(page.ctx, "resource-extra-example")
end
local function Bind(page, widget, path, get, set)
    local meta = M.ControlMeta("classpower", "advanced", "resource_extras.preview." .. path, "ephemeral",
        M.ClassPowerWorkspace.Decorate({}, "resource_extras.preview." .. path))
    M.ClassPowerWorkspace.BindDropdownWidget(page.ctx, widget, get, set, meta)
end
function Extras.BuildHeader(page, head, selectorH, width, resource, quick)
    local inputWidth = math.min(330, math.max(120, width - 264))
    local effect = W.Dropdown(head, "Preview effect", Choices, inputWidth)
    W.MoveWidget(effect, head, 14, -selectorH - 16, inputWidth)
    Bind(page, effect, "effect", Extras.Selection, function(value)
        Extras.Select(value)
        Refresh(page)
    end)
    local state = W.Dropdown(head, "Example state", function()
        return selected == "arcane" and ARCANE_STATES or ACTIVE_STATE
    end, inputWidth)
    W.MoveWidget(state, head, 14, -selectorH - 70, inputWidth)
    Bind(page, state, "state", function() return selected == "arcane" and scenario or "active" end,
        function(value) Extras.Select(selected, value) Refresh(page) end)
    local status = T.Font(head, "GameFontDisableSmall", "", T.colors.muted)
    status:SetPoint("TOPRIGHT", head, "TOPRIGHT", -16, -selectorH - 88)
    status:SetWidth(math.max(100, width - inputWidth - 50))
    status:SetJustifyH("RIGHT")
    page.ctx._resourceExtraHeader = {
        head = head, selectorH = selectorH, resource = resource, quick = quick,
        effect = effect, state = state, status = status, inputWidth = inputWidth,
    }
    W.SetControlShown(effect, false)
    W.SetControlShown(state, false)
    status:Hide()
    M.TrackRefresh(page.ctx, function() Extras.UpdateHeader(page.ctx, page.workspace.selected) end)
end
function Extras.UpdateHeader(ctx, kind)
    local ui = ctx._resourceExtraHeader
    if not ui then return end
    local effect, state, spec = Extras.Selection()
    local extras = kind == "extras"
    local height = ui.selectorH + (extras and 136 or 82)
    if ui.head:GetHeight() ~= height then
        ui.head:SetHeight(height)
        local record = ui.head._msuf2StickyPageHeaderRecord
        if record and record.active then M.RelayoutPageHeaderHost() end
    end
    W.SetControlShown(ui.effect, extras)
    W.SetControlShown(ui.state, extras and effect ~= "marks")
    ui.status:SetShown(extras and effect ~= "marks")
    ui.quick:SetShown(not extras)
    W.SetControlShown(ui.resource, not extras or effect == "marks")
    W.MoveWidget(ui.resource, ui.head, 14, -ui.selectorH - (extras and 70 or 16), ui.inputWidth)
    if not extras then return end
    ui.effect:SetValue(effect)
    ui.state:SetValue(effect == "arcane" and state or "active")
    local bars = M.EnsureDB().bars
    T.SetTranslatedText(ui.status, M.Tr(spec.setting and bars[spec.setting] == true
        and "Example - enabled in profile" or "Example - disabled in profile"))
end

local function CopyInto(target, source)
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(source) do target[key] = value end
    return target
end
function Extras.Config(preview, bars, player, spec)
    preview._resourceExtraExample = nil
    if preview._selectedWorkspaceKey ~= "extras" then return bars, player, spec end
    local effect, state = Extras.Selection()
    if effect == "marks" then return bars, player, spec end
    preview._resourceExtraExample = effect
    preview._resourceExtraState = state
    preview._resourceExtraBars = preview._resourceExtraBars or {}
    preview._resourceExtraPlayer = preview._resourceExtraPlayer or {}
    local sampleBars = CopyInto(preview._resourceExtraBars, bars)
    local samplePlayer = CopyInto(preview._resourceExtraPlayer, player)
    sampleBars.showClassPower, sampleBars.playerHPBarEnabled, sampleBars.showAltMana = false, false, false
    sampleBars.showIgnorePain, sampleBars.showArcaneWindow = effect == "pain", effect == "arcane"
    sampleBars.manaUpcomingCost = effect == "cost"
    sampleBars.manaRegenPause, sampleBars.manaGainPulse = effect == "pause", effect == "pulse"
    sampleBars.resourceMarks = nil
    -- One subdued Player Power bar makes duration-bar offsets observable in auto-fit.
    samplePlayer.powerBarDetached = true
    samplePlayer.detachedPowerBarAnchorToClassPower = true
    samplePlayer.playerPowerSource = "MANA"
    samplePlayer._msufResourceExtraMana = effect ~= "pain"
    samplePlayer._msufResourceExtraPower = effect == "pain" and "RAGE" or "MANA"
    return sampleBars, samplePlayer, nil
end
function Extras.Eligibility(preview)
    return preview._resourceExtraExample == "pain", preview._resourceExtraExample == "arcane"
end
function Extras.ArcaneSample(preview, warn)
    if preview._resourceExtraExample ~= "arcane" then return math.max(.5, warn - .5), false end
    local state = preview._resourceExtraState
    local seconds = state == "warning" and math.max(.5, warn - .5) or state == "active" and math.max(8, warn + 1) or 8
    return seconds, state == "soul"
end
function Extras.PaintLabels(preview, bars)
    local extras = preview._selectedWorkspaceKey == "extras"
    local _, _, spec = Extras.Selection()
    local title = extras and M.Format("Preview - %s", M.Tr(spec.label)) or M.Format("Preview - %s", M.Tr("Class Resources"))
    if preview:GetParent().title then T.SetTranslatedText(preview:GetParent().title, title) end
    T.SetTranslatedText(preview.title, title)
    if preview.detachedPower then
        local duration = preview._resourceExtraExample == "pain" or preview._resourceExtraExample == "arcane"
        preview.detachedPower:SetAlpha(duration and .35 or 1)
    end
    if extras and spec.setting then
        T.SetTranslatedText(preview.hint, M.Tr(spec.setting and bars[spec.setting] == true
            and "Example - enabled in profile" or "Example - disabled in profile"))
    else
        T.SetTranslatedText(preview.hint, M.Tr("Click to open settings. Move resources in Edit Mode."))
    end
end
