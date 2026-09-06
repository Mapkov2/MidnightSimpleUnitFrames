-- Optional Menu/Edit Mode chrome provider. Never touches unit frames or DB colors.
local _, MSUF = ...
local Skin = {}
MSUF.MenuSkin = Skin
local api, client, active, refreshing
local events
local appearance = {}
local records = setmetatable({}, { __mode = "k" })
local texts = setmetatable({}, { __mode = "k" })
local palettes = setmetatable({}, { __mode = "k" })
local groups = setmetatable({}, { __mode = "k" })
local unpack = unpack

local tokens = {
    bg = "background", popup = "popup", panel = "surface", panelNav = "ink", panel2 = "raised",
    card = "card", header = "surface", border = "border", borderSoft = "borderSoft", cardBorder = "borderSoft",
    coreShadow = "background", coreInk = "ink", coreSurface = "surface", coreRaised = "raised", coreRim = "rim",
    coreBlue = "blue", coreGlow = "accent", coreHot = "accentBright", accent = "accent", accent2 = "accentAlt",
    text = "text", title = "title", muted = "muted", searchPlaceholder = "muted", dim = "dim", disabled = "disabled",
    checkActive = "active", checkActiveEdge = "checkmark", checkInactive = "input", checkInactiveEdge = "borderSoft",
    pillBase = "buttonFill", pillBaseSolid = "buttonFill", pillHover = "hover", pillActive = "active",
    pillEdge = "buttonBorder", pillEdgeButton = "buttonBorder", pillEdgeHover = "accentBright", pillEdgeActive = "accent",
    pillText = "text", pillTextActive = "title", navPillBase = "ink", navPillBaseSolid = "background",
    navPillHover = "hover", navPillActive = "active", navPillEdge = "borderSoft", navPillEdgeHover = "accentBright",
    navPillEdgeActive = "accent", navText = "text", navTextActive = "title", navHeaderText = "muted",
    navHeaderHover = "accentBright", navArrowOpen = "accent", navArrowClosed = "muted",
    glassShell = "background", glassRail = "ink", glassHost = "surface", glassStatus = "surface", glassPopup = "popup",
    -- danger/ok/warning and arbitrary preview colors deliberately retain MSUF semantics.
}
local surfaceKeys = {
    "_msuf2Bg", "_msufUIGradient", "_msuf2MaterialGradient", "_msuf2PanelAsset", "_msuf2PanelAssetDepth",
    "_msuf2GlassTint", "_msuf2GlassWash", "_msuf2GlassDepth", "_msuf2GlassGrain", "_msuf2GlassOuterGlow",
    "_msuf2GlassTopGlow", "_msuf2GlassTopLine", "_msuf2GlassBottomLine", "_msuf2GlassLeftLine", "_msuf2GlassRightLine",
    "_msuf2PlasticTop", "_msuf2PlasticBottom", "_msuf2PlasticLip", "_msuf2EditBg", "_msuf2EditEdges",
    "_msuf2RoundedEditFill", "_msuf2RoundedEditEdge",
}
local buttonKeys = { "_msuf2Fill", "_msuf2Edge", "_msufUIFill", "_msufUIEdge", "_msuf2NavPillArt",
    "_msuf2CloseFill", "_msuf2CloseEdge", "_msuf2CloseLineA", "_msuf2CloseLineB", "_msuf2CloseFallback",
    "_msufUICloseLabel",
    "_msuf2ControlFill", "_msuf2ControlEdge", "_msuf2ControlIcon", "_msuf2ControlIconShadow" }
local partKeys = { "TL", "T", "TR", "L", "C", "M", "R", "BL", "B", "BR", "texture", "hoverWash", "glow", "sheen",
    "top", "bottom", "left", "right", "fill", "edge", "leftGlint", "rightGlint", "cornerGlow" }

local function HidePart(part, hidden, depth)
    if not part or depth > 3 then return end
    if part.Hide and part.IsShown then
        if hidden[part] == nil then hidden[part] = part:IsShown() end
        part:Hide()
    elseif type(part) == "table" then
        if part._neonPulse and part._neonPulse.Stop then part._neonPulse:Stop() end
        if part._neonPulse2 and part._neonPulse2.Stop then part._neonPulse2:Stop() end
        for i = 1, #partKeys do HidePart(part[partKeys[i]], hidden, depth + 1) end
        for i = 1, #part do HidePart(part[i], hidden, depth + 1) end
    end
end
local function RestoreHidden(hidden)
    for region, shown in pairs(hidden or {}) do
        if shown and not region:IsShown() then region:Show() end
        hidden[region] = nil
    end
end
local function Suppress(target, record, keys)
    if record.suppressed then return end
    record.hidden = record.hidden or {}
    for i = 1, #keys do HidePart(target[keys[i]], record.hidden, 0) end
    if target.GetBackdropColor and target.SetBackdropColor then
        record.bg = record.bg or { target:GetBackdropColor() }
        record.edge = record.edge or (target.GetBackdropBorderColor and { target:GetBackdropBorderColor() } or nil)
        target:SetBackdropColor(0, 0, 0, 0)
        if target.SetBackdropBorderColor then target:SetBackdropBorderColor(0, 0, 0, 0) end
    end
    record.suppressed = true
end
local function Restore(target, record)
    RestoreHidden(record.hidden)
    if record.bg and record.bg[1] and target.SetBackdropColor then target:SetBackdropColor(unpack(record.bg)) end
    if record.edge and record.edge[1] and target.SetBackdropBorderColor then target:SetBackdropBorderColor(unpack(record.edge)) end
    record.bg, record.edge, record.suppressed, record.skinned = nil, nil, nil, nil
    record.focused = nil
    -- Native painters cache previous writes; restoring a provider is a paint boundary.
    target._msuf2BackdropInfoApplied, target._msuf2BackdropR, target._msuf2BackdropBorderR = nil, nil, nil
    target._msuf2GlassApplied, target._msuf2SliderVisualReady = nil, nil
end
local function Record(target, kind, paint, a, b, rank)
    if not api or not target then return nil end
    local record = records[target]
    if not record then record = { kind = kind }; records[target] = record end
    if record.kind ~= kind then return nil end
    if (rank or 0) >= (record.rank or 0) then
        if (rank or 0) > (record.rank or 0) then record.suppressed = nil end
        record.paint, record.a, record.b, record.rank = paint, a, b, rank
    end
    return record
end
local function Role(role)
    if type(role) == "table" then role = role.glass end
    if role == "shell" or role == "popup" or role == "card" or role == "input" or role == "status" then return role end
    if role == "rail" then return "navigation" end
    return "panel"
end

function Skin.Surface(target, role, paint, a, b, rank)
    local record = Record(target, "surface", paint, a, b, rank)
    if not record or not active then return false end
    role = Role(role)
    if not record.skinned or record.role ~= role then
        local ok, reason = client:SkinFrame(target, { role = role, activeRole = role == "input" and "navigationActive" or nil })
        if not ok or reason ~= "applied" then return false end
        record.skinned, record.role = true, role
    end
    Suppress(target, record, surfaceKeys)
    if role == "input" then
        local focused = target.HasFocus and target:HasFocus() == true or false
        if record.focused ~= focused then client:SetActive(target, focused); record.focused = focused end
    end
    return true
end

function Skin.Button(button, selected, hover, paint)
    local record = Record(button, "button", paint, selected, hover)
    if not record or not active then return false end
    local nav = button._msuf2NavItem == true
    local role = (button._msuf2Danger or button._msufUIDanger) and "buttonDanger"
        or (button._msuf2Success or button._msufUISuccess) and "buttonSuccess"
        or (button._msuf2Primary or button._msufUIPrimary) and "buttonPrimary"
        or nav and "navigation" or "button"
    if not record.skinned or record.role ~= role or record.nav ~= nav then
        local ok, reason = client:SkinButton(button, { role = role, activeRole = nav and "navigationActive" or role,
            useControlShape = true, active = selected == true, listItem = nav })
        if not ok or reason ~= "applied" then return false end
        record.skinned, record.role, record.nav, record.selected = true, role, nav, selected == true
    elseif record.selected ~= (selected == true) then
        client:SetActive(button, selected == true)
        record.selected = selected == true
    end
    Suppress(button, record, buttonKeys)
    local label = button._msuf2Label or button._label
    if label and label.SetTextColor then
        local enabled = not button.IsEnabled or button:IsEnabled()
        local token = not enabled and "disabled" or role == "buttonDanger" and "danger"
            or role == "buttonSuccess" and "success" or "text"
        label:SetTextColor(api:GetColor(token))
    end
    return true
end

function Skin.WindowAction(button, kind, paint, hover, down)
    local record = Record(button, "action", paint, hover, down)
    if not record or not active or appearance.windowActionStyle == "native" then return false end
    if kind == "restore" then kind = "minimize" end
    if not record.skinned or record.action ~= kind then
        local ok, reason = client:SkinWindowAction(button, kind)
        if not ok or reason ~= "applied" then return false end
        record.skinned, record.action = true, kind
    end
    Suppress(button, record, buttonKeys)
    local group = button._msuf2ControlGroup
    if group then
        local hidden = groups[group]
        if not hidden then hidden = {}; groups[group] = hidden end
        HidePart(group._msuf2ControlGroupBase, hidden, 0)
        HidePart(group._msuf2ControlGroupHover, hidden, 0)
    end
    return true
end

function Skin.TrackPaint(target, paint, a, b)
    Record(target, "native", paint, a, b)
end
function Skin.TrackText(fs, color)
    if not api or not fs or not palettes[color] then return end
    texts[fs] = color
end
local function PaintPalette(color, entry)
    if active then
        local r, g, b, a = api:GetColor(entry.token)
        color[1], color[2], color[3], color[4] = r, g, b, a
    else
        for i = 1, 4 do color[i] = entry[i] end
    end
end
function Skin.BindColors(colors)
    if not api or type(colors) ~= "table" then return end
    for key, token in pairs(tokens) do
        local color = colors[key]
        if type(color) == "table" and not palettes[color] then
            local entry = { color[1], color[2], color[3], color[4], token = token }
            palettes[color] = entry
            PaintPalette(color, entry)
        end
    end
end
function Skin.IsActive() return active == true end
function Skin.Owns(target) return active == true and records[target] and records[target].skinned == true end

local function Repaint(target, record)
    local ok, message = pcall(record.paint, target, record.a, record.b)
    if not ok then
        local handler = geterrorhandler and geterrorhandler()
        if handler then pcall(handler, "MSUF MapkoSkin repaint: " .. tostring(message)) end
    end
end

function Skin.Refresh(_, domain, key)
    if not api or refreshing then return end
    if domain and domain ~= "ready" and domain ~= "profile" and domain ~= "color" and domain ~= "theme"
        and domain ~= "appearance" and domain ~= "geometry" and domain ~= "windowAction"
        and not (domain == "adapter" and key == "master") then return end
    if InCombatLockdown and InCombatLockdown() then
        Skin.pending = true
        if events then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    refreshing = true
    active = api:IsEnabled() and not (MSUF_DB and MSUF_DB.general and MSUF_DB.general.mapkoSkinMenus == false)
    appearance = api:GetAppearanceSnapshot()
    for color, entry in pairs(palettes) do PaintPalette(color, entry) end
    -- Release before native repaint, including a modern -> native glyph switch.
    if not active then client:ReleaseAll() end
    for _, hidden in pairs(groups) do RestoreHidden(hidden) end
    for target, record in pairs(records) do
        if not active or (record.kind == "action" and appearance.windowActionStyle == "native") then
            if active and record.skinned then client:Release(target) end
            Restore(target, record)
        end
    end
    for fs, color in pairs(texts) do
        if fs.SetTextColor then fs:SetTextColor(unpack(color)) end
    end
    for target, record in pairs(records) do
        target._msuf2SliderVisualReady = nil
        if record.paint then Repaint(target, record) end
    end
    refreshing, Skin.pending = false, nil
    if events then events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
end

local function Connect()
    if api then return end
    local provider = _G.MapkoSkin
    local candidate = provider and provider.GetAPI and provider.GetAPI(2, 1)
    if not candidate or type(hooksecurefunc) ~= "function" then return end
    local registered = candidate:RegisterAddon("MidnightSimpleUnitFrames", { integrationVersion = 1 })
    if not registered then return end
    api, client = candidate, registered
    hooksecurefunc(api, "OnAppearanceChanged", Skin.Refresh)
    Skin.Refresh()
    Skin.BindColors(MSUF.UI and MSUF.UI.colors)
end
Connect()
events = CreateFrame("Frame")
if not api then events:RegisterEvent("ADDON_LOADED") end
if Skin.pending then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "MapkoSkin" then
        Connect()
        if api then events:UnregisterEvent("ADDON_LOADED") end
    elseif event == "PLAYER_REGEN_ENABLED" and Skin.pending then Skin.Refresh() end
end)
