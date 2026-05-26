--- Auras3/MSUF_Auras3_Menu.lua
--- Cold-path Menu2 integration for Auras3.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2
if type(M) ~= "table" then return end

local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local A3 = MSUF.MSUF_Auras3 or _G.MSUF_Auras3
local Model = A3 and A3.MenuModel
if type(W) ~= "table" or type(T) ~= "table" or type(Model) ~= "table" then return end

local CreateFrame = _G.CreateFrame
local GameTooltip = _G.GameTooltip
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local tostring, tonumber, type, ipairs = tostring, tonumber, type, ipairs
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local AURA_TABS = {
    { value = "overview", text = "Overview" },
    { value = "rules", text = "Rules" },
    { value = "blacklist", text = "Blacklist" },
    { value = "colors", text = "Colors" },
    { value = "special", text = "Special" },
}

local AURA_SCOPE_VALUES = {
    { value = "shared", text = "Shared" },
    { value = "player", text = "Player" },
    { value = "target", text = "Target" },
    { value = "focus", text = "Focus" },
    { value = "boss", text = "Boss" },
    { value = "party", text = "Party" },
    { value = "raid", text = "Raid / Mythic" },
}

local UNIT_AURA_LANE_TABS = {
    { value = "buff", text = "Buffs" },
    { value = "debuff", text = "Debuffs" },
}

local UNIT_AURA_MODE_TABS = {
    { value = "basic", text = "Basic" },
    { value = "advanced", text = "Advanced" },
}

local GROUP_STYLE_SCOPES = {
    { value = "party", text = "Party" },
    { value = "raid", text = "Raid / Mythic" },
}

local GROUP_STYLE_LANES = {
    { value = "buff", text = "Buffs" },
    { value = "debuff", text = "Debuffs" },
    { value = "externals", text = "Defensives" },
}

local GROUP_BLACKLIST_LANES = {
    { value = "buff", text = "Buffs" },
    { value = "debuff", text = "Debuffs" },
}

local GF_RENDERERS = GP.GF_RENDERERS or {
    { value = "BLIZZARD", text = "Blizzard" },
    { value = "CUSTOM", text = "MSUF Custom" },
}

local GF_AURA_ORG = GP.GF_AURA_ORG or {
    { value = "default", text = "Default" },
    { value = "compact", text = "Compact" },
}

local BLIZZARD_CONTAINER_STRATA = {
    { value = "AUTO", text = "Auto (Frame)" },
    { value = "BACKGROUND", text = "BACKGROUND" },
    { value = "LOW", text = "LOW" },
    { value = "MEDIUM", text = "MEDIUM" },
    { value = "HIGH", text = "HIGH" },
    { value = "DIALOG", text = "DIALOG" },
}

local BUFF_EXCLUSIVE = {
    { value = "none", text = "None" },
    { value = "bigDefensive", text = "Big Defensives" },
    { value = "externalDefensive", text = "External Defensives" },
    { value = "important", text = "Important" },
}

local DEBUFF_EXCLUSIVE = {
    { value = "none", text = "None" },
    { value = "important", text = "Important" },
    { value = "raid", text = "Raid" },
    { value = "all", text = "All" },
}

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(M.Tr) == "function" then return M.Tr(text) end
    return text
end

local function CurrentScope()
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local scope = M.auraScope or "shared"
    if scope == "mythicraid" then scope = "raid" end
    if scope ~= "shared" and scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" and scope ~= "party" and scope ~= "raid" then
        scope = "shared"
    end
    return scope
end

local function SetCurrentScope(scope)
    scope = scope or "shared"
    if scope == "mythicraid" then scope = "raid" end
    if scope == "party" or scope == "raid" then
        if type(M.PersistMenuStateValue) == "function" then
            M.PersistMenuStateValue("auraStyleGFScope", scope)
        else
            M.auraStyleGFScope = scope
        end
    end
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("auraScope", scope)
    else
        M.auraScope = scope
    end
end

local function IsGroupAuraScope(scope)
    scope = scope or CurrentScope()
    return scope == "party" or scope == "raid" or scope == "mythicraid"
end

local function CurrentTab()
    local tab = M.auraStyleTab or "overview"
    if tab == "text" then return "colors" end
    if tab == "lists" then return "blacklist" end
    for i = 1, #AURA_TABS do
        if AURA_TABS[i].value == tab then return tab end
    end
    return "overview"
end

local function SetCurrentTab(tab)
    tab = tab or "overview"
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("auraStyleTab", tab)
    else
        M.auraStyleTab = tab
    end
end

local function Rebuild(ctx)
    local key = ctx and ctx.key or M.activeKey or "auras3"
    if M.InvalidatePage and M.SelectPage and M.frame and M.frame.IsShown and M.frame:IsShown() then
        M.InvalidatePage(key)
        M.activeKey = nil
        M.SelectPage(key)
    elseif M.Refresh then
        M.Refresh(ctx)
    end
end

local function ApplyAndRefresh(ctx, unit, reason, refreshControls)
    Model.Apply(unit, reason or "AURAS3_MENU")
    if refreshControls and M.Refresh then M.Refresh(ctx) end
end

local function BindSwitch(ctx, parent, label, x, y, width, getValue, setValue, unit, reason, refreshControls)
    local widget = W.SwitchAt(parent, label, x, y, width or 180)
    M.BindToggle(ctx, widget,
        function() return getValue() and true or false end,
        function(v)
            setValue(v and true or false)
            ApplyAndRefresh(ctx, unit, reason, refreshControls)
        end)
    return widget
end

local function BindSlider(ctx, parent, label, x, y, minVal, maxVal, step, width, getValue, setValue, unit, reason)
    local widget = W.Slider(parent, label, minVal, maxVal, step, width)
    W.MoveWidget(widget, parent, x, y, width)
    M.BindSlider(ctx, widget,
        function() return tonumber(getValue()) or 0 end,
        function(v)
            setValue(v)
            ApplyAndRefresh(ctx, unit, reason)
        end)
    return widget
end

local function BindDropdown(ctx, parent, label, x, y, values, width, getValue, setValue, unit, reason, refreshControls)
    local widget = W.Dropdown(parent, label, values, width)
    W.MoveWidget(widget, parent, x, y, width)
    M.BindDropdown(ctx, widget,
        function() return getValue() end,
        function(v)
            setValue(v)
            ApplyAndRefresh(ctx, unit, reason, refreshControls)
        end)
    return widget
end

local function BindTextInput(ctx, parent, label, x, y, width, getValue, setValue, unit, reason, refreshControls)
    local widget = W.TextInput(parent, label, width)
    W.MoveWidget(widget, parent, x, y, width)
    M.BindTextInput(ctx, widget,
        function() return getValue() or "" end,
        function(v)
            setValue(v or "")
            ApplyAndRefresh(ctx, unit, reason, refreshControls)
        end)
    return widget
end

local function BindColor(ctx, parent, label, x, y, getRGB, setRGB, unit, reason, refreshControls)
    local widget = W.Color(parent, label)
    W.MoveWidget(widget, parent, x, y)
    M.BindColor(ctx, widget,
        function() return getRGB() end,
        function(r, g, b)
            setRGB(r, g, b)
            ApplyAndRefresh(ctx, unit or "shared", reason or "AURAS3_COLOR", refreshControls)
        end)
    return widget
end

local function AddTooltip(widget, title, body)
    if not (widget and widget.SetScript) then return widget end
    widget:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Tr(title or ""), 1, 1, 1)
        if body and body ~= "" then GameTooltip:AddLine(Tr(body), 0.75, 0.78, 0.86, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return widget
end

local function StyleButton(parent, label, width, height)
    local btn = T.Button(parent, Tr(label or ""), width or 104, height or 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(btn) end
    return btn
end

local function MakePill(parent, label, width, onClick)
    local btn = StyleButton(parent, label, width or 88, 24)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function SetButtonActive(btn, active)
    if btn and btn.SetActive then btn:SetActive(active and true or false) end
end

local function BuildScopeTabs(ctx, parent, x, y, width, onChanged)
    local values = AURA_SCOPE_VALUES
    local gap = 6
    local count = #values
    local bw = floor(((width or 520) - gap * (count - 1)) / count)
    local buttons = {}
    for i = 1, count do
        local item = values[i]
        local btn = MakePill(parent, item.text, bw, function()
            SetCurrentScope(item.value)
            if onChanged then onChanged(item.value) else Rebuild(ctx) end
        end)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (bw + gap), y)
        buttons[#buttons + 1] = btn
    end
    M.AddRefresher(ctx, function()
        local scope = CurrentScope()
        for i = 1, #values do SetButtonActive(buttons[i], values[i].value == scope) end
    end)
    return buttons
end

local function BuildTabButtons(ctx, parent, x, y, width)
    local gap = 6
    local count = #AURA_TABS
    local bw = floor(((width or 620) - gap * (count - 1)) / count)
    local buttons = {}
    for i = 1, count do
        local item = AURA_TABS[i]
        local btn = MakePill(parent, item.text, bw, function()
            SetCurrentTab(item.value)
            Rebuild(ctx)
        end)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (bw + gap), y)
        buttons[#buttons + 1] = btn
    end
    M.AddRefresher(ctx, function()
        local tab = CurrentTab()
        for i = 1, #AURA_TABS do SetButtonActive(buttons[i], AURA_TABS[i].value == tab) end
    end)
    return buttons
end

local function CreateAuraPreviewIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(24, 24)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.85)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    if f.icon.SetTexCoord then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    f.edge = {}
    for i = 1, 4 do
        f.edge[i] = f:CreateTexture(nil, "OVERLAY")
        f.edge[i]:SetTexture(TEX_W8)
    end
    f.edge[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); f.edge[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); f.edge[1]:SetHeight(1)
    f.edge[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); f.edge[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); f.edge[2]:SetHeight(1)
    f.edge[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); f.edge[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); f.edge[3]:SetWidth(1)
    f.edge[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); f.edge[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); f.edge[4]:SetWidth(1)
    f.stack = f:CreateFontString(nil, "OVERLAY")
    f.stack:SetFont(FONT, 9, "OUTLINE")
    f.stack:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f.timer = f:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(FONT, 8, "OUTLINE")
    f.timer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 1)
    return f
end

local function BuildMiniAuraPreview(ctx, parent, scope, x, y, width, height)
    local box = T.Panel(parent, nil, { 0.010, 0.016, 0.034, 0.88 }, T.colors.borderSoft)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width or 300, height or 104)
    W.LabelAt(box, "Preview", 10, -10, 100, "GameFontNormalSmall", T.colors.text)
    local icons = {}
    for i = 1, 14 do icons[i] = CreateAuraPreviewIcon(box) end
    local buffTex = { 135987, 136116, 135932, 136085, 132333, 135981, 136048 }
    local debuffTex = { 136118, 136139, 136197, 135817, 132851, 136188, 136170 }
    M.AddRefresher(ctx, function()
        local readScope = scope == "shared" and "shared" or scope
        local size = min(28, max(18, Model.ReadNumber(readScope, "iconSize", 26, 10, 64)))
        local spacing = min(5, max(1, Model.ReadNumber(readScope, "spacing", 2, 0, 12)))
        local count = min(14, max(4, Model.ReadNumber(readScope, "perRow", 12, 1, 40)))
        for i = 1, #icons do
            local icon = icons[i]
            if i <= count then
                local col = (i - 1) % 7
                local row = floor((i - 1) / 7)
                icon:SetSize(size, size)
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", box, "TOPLEFT", 10 + col * (size + spacing), -34 - row * (size + spacing))
                icon.icon:SetTexture(i <= 7 and buffTex[((i - 1) % #buffTex) + 1] or debuffTex[((i - 8) % #debuffTex) + 1])
                local r, g, b = i <= 7 and 0.20 or 0.78, i <= 7 and 0.72 or 0.20, i <= 7 and 0.42 or 0.24
                for e = 1, 4 do icon.edge[e]:SetVertexColor(r, g, b, 0.95) end
                icon.stack:SetText(Model.ReadSharedBool("showStackCount", true) and (i % 3 == 1 and "2" or "") or "")
                icon.timer:SetText(Model.ReadSharedBool("showCooldownText", true) and (i % 2 == 0 and "12" or "") or "")
                icon:Show()
            else
                icon:Hide()
            end
        end
    end)
    return box
end

local function AuraControlCard(parent, title, subtitle, x, y, width, height)
    local card = W.ControlCard(parent, title, subtitle, x, y, width, height)
    if card and T.ApplyBackdrop then
        T.ApplyBackdrop(card, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
    end
    return card
end

local function GroupPage()
    return M.GroupPage or GP or {}
end

local function GroupScopeKinds(scope)
    scope = tostring(scope or "raid")
    if scope == "party" then return "party" end
    return "raid", "mythicraid"
end

local function CurrentGFStyleScope()
    local scope = M.auraStyleGFScope or "raid"
    if scope == "mythicraid" then scope = "raid" end
    if scope ~= "party" and scope ~= "raid" then scope = "raid" end
    return scope
end

local function SetCurrentGFStyleScope(scope)
    scope = scope == "party" and "party" or "raid"
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("auraStyleGFScope", scope)
        if IsGroupAuraScope(M.auraScope) then M.PersistMenuStateValue("auraScope", scope) end
    else
        M.auraStyleGFScope = scope
        if IsGroupAuraScope(M.auraScope) then M.auraScope = scope end
    end
end

local function CurrentGFStyleLane(includeExternals)
    local lane = M.auraStyleGFLane or "debuff"
    if lane == "externals" and includeExternals then return lane end
    if lane ~= "buff" and lane ~= "debuff" then lane = "debuff" end
    return lane
end

local function SetCurrentGFStyleLane(lane)
    lane = lane == "buff" and "buff" or (lane == "externals" and "externals" or "debuff")
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("auraStyleGFLane", lane)
    else
        M.auraStyleGFLane = lane
    end
end

local function CurrentGFBlacklistLane()
    local lane = M.auraStyleGFBlacklistLane or CurrentGFStyleLane(false)
    if lane ~= "buff" and lane ~= "debuff" then lane = "debuff" end
    return lane
end

local function SetCurrentGFBlacklistLane(lane)
    lane = lane == "buff" and "buff" or "debuff"
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("auraStyleGFBlacklistLane", lane)
        M.PersistMenuStateValue("auraStyleGFLane", lane)
    else
        M.auraStyleGFBlacklistLane = lane
        M.auraStyleGFLane = lane
    end
end

local function GF()
    local gp = GroupPage()
    return gp.GF and gp.GF()
end

local function AuraFilter()
    local gf = GF()
    return (gf and gf.AuraFilter) or _G.MSUF_GF_AuraFilter
end

local function GroupConf(kind)
    local gp = GroupPage()
    if type(gp.Conf) == "function" then return gp.Conf(kind) end
    if type(M.EnsureDB) ~= "function" then return nil end
    local db = M.EnsureDB()
    local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
    db[key] = db[key] or {}
    return db[key]
end

local function GFAurasRoot(kind)
    local gp = GroupPage()
    if type(gp.AurasRoot) == "function" then return gp.AurasRoot(kind) end
    local conf = GroupConf(kind)
    if type(conf) ~= "table" then return nil end
    conf.auras = conf.auras or {}
    conf.auras.blizzardTypes = conf.auras.blizzardTypes or {}
    conf.auras.buff = conf.auras.buff or {}
    conf.auras.debuff = conf.auras.debuff or {}
    conf.auras.externals = conf.auras.externals or {}
    return conf.auras
end

local function GFAuraGroup(kind, groupKey)
    local gp = GroupPage()
    if type(gp.AuraGroup) == "function" then return gp.AuraGroup(kind, groupKey) end
    local root = GFAurasRoot(kind)
    if type(root) ~= "table" then return nil end
    root[groupKey] = root[groupKey] or {}
    return root[groupKey]
end

local function GFQueue(scope, mode)
    local gp = GroupPage()
    if type(gp.QueueGF) == "function" then
        local a, b = GroupScopeKinds(scope)
        gp.QueueGF(a, mode or "visual")
        if b then gp.QueueGF(b, mode or "visual") end
    end
    if type(gp.RefreshGFPreview) == "function" then gp.RefreshGFPreview() end
end

local function GFRequestTextRefresh()
    if _G.MSUF_GF_InvalidateCooldownTextCurve then _G.MSUF_GF_InvalidateCooldownTextCurve() end
    if _G.MSUF_GF_ForceCooldownTextRecolor then _G.MSUF_GF_ForceCooldownTextRecolor() end
    GFQueue("party", "visual")
    GFQueue("raid", "visual")
end

local function GFInvalidateBlacklist(scope, groupKey)
    local af = AuraFilter()
    if not (af and type(af.InvalidateBlacklistHash) == "function") then return end
    local a, b = GroupScopeKinds(scope)
    local g = GFAuraGroup(a, groupKey)
    if g then af.InvalidateBlacklistHash(g) end
    if b then
        g = GFAuraGroup(b, groupKey)
        if g then af.InvalidateBlacklistHash(g) end
    end
end

local function GFReadGroup(scope, groupKey)
    local kind = GroupScopeKinds(scope)
    return GFAuraGroup(kind, groupKey) or {}
end

local function GFReadRoot(scope)
    local kind = GroupScopeKinds(scope)
    return GFAurasRoot(kind) or {}
end

local function GFReadConf(scope)
    local kind = GroupScopeKinds(scope)
    return GroupConf(kind) or {}
end

local function GFPrivateAuras(kind)
    local conf = GroupConf(kind)
    if type(conf) ~= "table" then return nil end
    if type(conf.privateAuras) ~= "table" then conf.privateAuras = {} end
    return conf.privateAuras
end

local function GFReadPrivate(scope)
    local kind = GroupScopeKinds(scope)
    return GFPrivateAuras(kind) or {}
end

local function GFWriteGroupValue(scope, groupKey, key, value, mode)
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local g = GFAuraGroup(kind, groupKey)
        if not g then return end
        if g[key] == value then return end
        g[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then GFQueue(scope, mode or "visual") end
end

local function GFWritePrivateValue(scope, key, value, mode)
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local pa = GFPrivateAuras(kind)
        if not pa or pa[key] == value then return end
        pa[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then GFQueue(scope, mode or "visual") end
end

local function GFWriteBlizzardType(scope, key, value)
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local root = GFAurasRoot(kind)
        if not root then return end
        root.blizzardTypes = root.blizzardTypes or {}
        if root.blizzardTypes[key] == value then return end
        root.blizzardTypes[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then GFQueue(scope, "rebuild") end
end

local function GFReadBlizzardType(scope, key, defaultValue)
    local root = GFReadRoot(scope)
    local types = root.blizzardTypes
    if type(types) ~= "table" or types[key] == nil then return defaultValue and true or false end
    return types[key] == true
end

local function GFApplyBlizzardLayering(scope, forceReapply)
    local gf = GF()
    if gf and type(gf.ApplyBlizzardAuraContainerLayering) == "function" then
        local a, b = GroupScopeKinds(scope)
        gf.ApplyBlizzardAuraContainerLayering(a, forceReapply == true)
        if b then gf.ApplyBlizzardAuraContainerLayering(b, forceReapply == true) end
    end
    GFQueue(scope, "visual")
end

local function GFWriteRootValue(scope, key, value, mode)
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local root = GFAurasRoot(kind)
        if not root or root[key] == value then return end
        root[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then GFQueue(scope, mode or "visual") end
end

local function GFWriteConfValue(scope, key, value, mode)
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local conf = GroupConf(kind)
        if not conf or conf[key] == value then return end
        conf[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then GFQueue(scope, mode or "visual") end
end

local function GFReadBlacklistCat(scope, groupKey, catKey)
    local g = GFReadGroup(scope, groupKey)
    return type(g.blacklistCats) == "table" and g.blacklistCats[catKey] == true
end

local function GFWriteBlacklistCat(scope, groupKey, catKey, value)
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local g = GFAuraGroup(kind, groupKey)
        if not g then return end
        if type(g.blacklistCats) ~= "table" then g.blacklistCats = {} end
        local nextValue = value and true or nil
        if g.blacklistCats[catKey] == nextValue then return end
        g.blacklistCats[catKey] = nextValue
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then
        GFInvalidateBlacklist(scope, groupKey)
        GFQueue(scope, "visual")
    end
end

local function GroupScopeLabel(scope)
    return scope == "party" and "Party" or "Raid / Mythic"
end

local function GroupLaneLabel(lane)
    if lane == "buff" then return "Buffs" end
    if lane == "externals" then return "Defensives" end
    return "Debuffs"
end

local function BuildGFStyleScopeTabs(ctx, parent, x, y, width)
    local gap = 6
    local bw = floor(((width or 260) - gap) / 2)
    local buttons = {}
    for i = 1, #GROUP_STYLE_SCOPES do
        local item = GROUP_STYLE_SCOPES[i]
        local btn = MakePill(parent, item.text, bw, function()
            SetCurrentGFStyleScope(item.value)
            Rebuild(ctx)
        end)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (bw + gap), y)
        buttons[i] = btn
    end
    M.AddRefresher(ctx, function()
        local scope = CurrentGFStyleScope()
        for i = 1, #GROUP_STYLE_SCOPES do SetButtonActive(buttons[i], GROUP_STYLE_SCOPES[i].value == scope) end
    end)
end

local function BuildGFLaneTabs(ctx, parent, x, y, width, includeExternals, blacklist)
    local values = includeExternals and GROUP_STYLE_LANES or GROUP_BLACKLIST_LANES
    local gap = 6
    local bw = floor(((width or 360) - gap * (#values - 1)) / #values)
    local buttons = {}
    for i = 1, #values do
        local item = values[i]
        local btn = MakePill(parent, item.text, bw, function()
            if blacklist then
                SetCurrentGFBlacklistLane(item.value)
            else
                SetCurrentGFStyleLane(item.value)
            end
            Rebuild(ctx)
        end)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (bw + gap), y)
        buttons[i] = btn
    end
    M.AddRefresher(ctx, function()
        local lane = blacklist and CurrentGFBlacklistLane() or CurrentGFStyleLane(includeExternals)
        for i = 1, #values do SetButtonActive(buttons[i], values[i].value == lane) end
    end)
end

local function GroupFilterValues(groupKey)
    local af = AuraFilter()
    local source = groupKey == "debuff" and af and af.DEBUFF_FILTER_ITEMS or af and af.BUFF_FILTER_ITEMS
    local out = {}
    if type(source) == "table" then
        for i = 1, #source do
            local item = source[i]
            if item then
                out[#out + 1] = {
                    value = item.value or item.key,
                    text = item.text or item.label or tostring(item.value or item.key or ""),
                }
            end
        end
    end
    if #out > 0 then return out end
    if groupKey == "buff" then
        return {
            { value = "ALL", text = "All Buffs" },
            { value = "PLAYER", text = "My Buffs Only" },
            { value = "RAID", text = "Raid Buffs" },
            { value = "IMPORTANT", text = "Important" },
        }
    end
    return {
        { value = "ALL", text = "All Debuffs" },
        { value = "PLAYER", text = "My Debuffs Only" },
        { value = "RAID", text = "Boss / Raid" },
        { value = "DISPELLABLE", text = "Dispellable" },
        { value = "IMPORTANT", text = "Important" },
    }
end

local function GFAnchorValues()
    local gp = GroupPage()
    local values = gp.STATUS_ICON_ANCHORS or gp.AURA_ANCHORS
    if type(values) == "table" and #values > 0 then return values end
    return {
        { value = "CENTER", text = "Center" },
        { value = "TOPLEFT", text = "Top Left" },
        { value = "TOPRIGHT", text = "Top Right" },
        { value = "BOTTOMLEFT", text = "Bottom Left" },
        { value = "BOTTOMRIGHT", text = "Bottom Right" },
    }
end

local function BindGFToggle(ctx, parent, label, x, y, width, scope, groupKey, key, default, mode)
    local widget = W.ToggleAt(parent, label, x, y, width or 180)
    M.BindToggle(ctx, widget,
        function()
            local cfg = GFReadGroup(scope, groupKey)
            local value = cfg[key]
            if value == nil then value = default end
            return value and true or false
        end,
        function(value)
            GFWriteGroupValue(scope, groupKey, key, value and true or false, mode or "visual")
        end)
    return widget
end

local function BindGFRootToggle(ctx, parent, label, x, y, width, scope, key, default, mode, afterSet)
    local widget = W.ToggleAt(parent, label, x, y, width or 180)
    M.BindToggle(ctx, widget,
        function()
            local root = GFReadRoot(scope)
            local value = root[key]
            if value == nil then value = default end
            return value and true or false
        end,
        function(value)
            GFWriteRootValue(scope, key, value and true or false, mode or "visual")
            if afterSet then afterSet(value and true or false) end
        end)
    return widget
end

local function BindGFPrivateToggle(ctx, parent, label, x, y, width, scope, key, default, mode)
    local widget = W.ToggleAt(parent, label, x, y, width or 180)
    M.BindToggle(ctx, widget,
        function()
            local pa = GFReadPrivate(scope)
            local value = pa[key]
            if value == nil then value = default end
            return value and true or false
        end,
        function(value)
            GFWritePrivateValue(scope, key, value and true or false, mode or "visual")
        end)
    return widget
end

local function BindGFConfToggle(ctx, parent, label, x, y, width, scope, key, default, mode, afterSet)
    local widget = W.ToggleAt(parent, label, x, y, width or 180)
    M.BindToggle(ctx, widget,
        function()
            local conf = GFReadConf(scope)
            local value = conf[key]
            if value == nil then value = default end
            return value and true or false
        end,
        function(value)
            GFWriteConfValue(scope, key, value and true or false, mode or "visual")
            if afterSet then afterSet(value and true or false) end
        end)
    return widget
end

local function BindGFRootSlider(ctx, parent, label, x, y, minVal, maxVal, step, width, scope, key, default, mode, afterSet)
    local widget = W.Slider(parent, label, minVal, maxVal, step, width)
    W.MoveWidget(widget, parent, x, y, width)
    M.BindSlider(ctx, widget,
        function()
            local root = GFReadRoot(scope)
            return tonumber(root[key]) or default or 0
        end,
        function(value)
            value = floor((tonumber(value) or default or 0) + 0.5)
            GFWriteRootValue(scope, key, value, mode or "visual")
            if afterSet then afterSet(value) end
        end)
    return widget
end

local function BindGFRootDropdown(ctx, parent, label, x, y, values, width, scope, key, default, mode, afterSet)
    local widget = W.Dropdown(parent, label, values, width)
    W.MoveWidget(widget, parent, x, y, width)
    M.BindDropdown(ctx, widget,
        function()
            local root = GFReadRoot(scope)
            return root[key] or default
        end,
        function(value)
            value = value or default
            GFWriteRootValue(scope, key, value, mode or "visual")
            if afterSet then afterSet(value) end
        end)
    return widget
end

local function BindGFBlizzardTypeToggle(ctx, parent, label, x, y, width, scope, key, default)
    local widget = W.ToggleAt(parent, label, x, y, width or 180)
    M.BindToggle(ctx, widget,
        function() return GFReadBlizzardType(scope, key, default) end,
        function(value) GFWriteBlizzardType(scope, key, value and true or false) end)
    return widget
end

local function BindGFSlider(ctx, parent, label, x, y, minVal, maxVal, step, width, scope, groupKey, key, default, mode)
    local widget = W.Slider(parent, label, minVal, maxVal, step, width)
    W.MoveWidget(widget, parent, x, y, width)
    M.BindSlider(ctx, widget,
        function()
            local cfg = GFReadGroup(scope, groupKey)
            return tonumber(cfg[key]) or default or 0
        end,
        function(value)
            value = floor((tonumber(value) or default or 0) + 0.5)
            GFWriteGroupValue(scope, groupKey, key, value, mode or "visual")
        end)
    return widget
end

local function BindGFDropdown(ctx, parent, label, x, y, values, width, scope, groupKey, key, default, mode)
    local widget = W.Dropdown(parent, label, values, width)
    W.MoveWidget(widget, parent, x, y, width)
    M.BindDropdown(ctx, widget,
        function()
            local cfg = GFReadGroup(scope, groupKey)
            return cfg[key] or default
        end,
        function(value)
            GFWriteGroupValue(scope, groupKey, key, value or default, mode or "visual")
        end)
    return widget
end

local function CreateGroupAuraTextPreview(ctx, parent, scope, groupKey, x, y, width)
    local box = T.Panel(parent, nil, { 0.014, 0.020, 0.040, 0.82 }, T.colors.borderSoft)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width, 76)
    W.LabelAt(box, "Preview", 10, -10, 90, "GameFontNormalSmall", T.colors.muted)

    local icons = {}
    local textures = groupKey == "buff" and { 135987, 136116, 135932 }
        or groupKey == "externals" and { 135966, 136243, 135940 }
        or { 136118, 136139, 136197 }
    for i = 1, 3 do
        local icon = CreateAuraPreviewIcon(box)
        icon:SetSize(34, 34)
        icon:SetPoint("TOPLEFT", box, "TOPLEFT", max(94, width - 148) + (i - 1) * 44, -28)
        icon.icon:SetTexture(textures[i])
        icons[i] = icon
    end
    M.AddRefresher(ctx, function()
        local cfg = GFReadGroup(scope, groupKey)
        local showCd = cfg.showCooldown ~= false
        local showStacks = cfg.showStacks ~= false
        local showSwipe = cfg.showCooldownSwipe ~= false
        local size = max(6, min(24, tonumber(cfg.cooldownSize) or (groupKey == "externals" and 10 or 8)))
        local stackSize = max(6, min(24, tonumber(cfg.stackSize) or 10))
        for i = 1, #icons do
            local icon = icons[i]
            icon.timer:SetFont(FONT, size, "OUTLINE")
            icon.stack:SetFont(FONT, stackSize, "OUTLINE")
            icon.timer:SetText(showCd and (i == 2 and "5" or "3") or "")
            icon.stack:SetText(showStacks and (i == 2 and "3" or "2") or "")
            icon.bg:SetColorTexture(0, 0, 0, showSwipe and 0.82 or 0.38)
        end
    end)
    return box
end

local function BuildGroupFrameDisplayControls(ctx, parent, x, y, width)
    local scope = CurrentGFStyleScope()
    local card = AuraControlCard(parent, "Group Frame Aura Display", "Renderer, Blizzard routing and layer controls. Raid and Mythic Raid are edited together.", x, y, width, 384)
    W.LabelAt(card, "Group", 16, -46, 80, "GameFontNormalSmall", T.colors.accent)
    BuildGFStyleScopeTabs(ctx, card, 80, -42, min(270, width - 112))

    local leftW = max(250, floor((width - 60) / 2))
    local rightX = 36 + leftW
    local rightW = max(250, width - rightX - 20)
    local routeW = max(120, floor((rightW - 12) / 2))
    local routeX2 = rightX + routeW + 12
    local nativeControls = {}

    local rendererMode = BindGFRootDropdown(ctx, card, "Renderer", 16, -104, GF_RENDERERS, min(220, leftW), scope, "renderer", "BLIZZARD", "rebuild",
        function() GFApplyBlizzardLayering(scope, true) end)
    AddTooltip(rendererMode, "Aura Display Mode", "Blizzard mode lets WoW place the selected aura types. MSUF Custom gives MSUF full positioning, filters and styling control.")

    nativeControls[#nativeControls + 1] = BindGFRootSlider(ctx, card, "Blizzard Icon Size", 16, -164, 8, 80, 1, min(260, leftW), scope, "blizzardIconSize", 20, "geometry",
        function() GFApplyBlizzardLayering(scope, false) end)
    nativeControls[#nativeControls + 1] = BindGFRootDropdown(ctx, card, "Organization", 16, -224, GF_AURA_ORG, min(260, leftW), scope, "blizzardOrganizationType", "default", "geometry")
    nativeControls[#nativeControls + 1] = BindGFRootDropdown(ctx, card, "Aura Layer Strata", 16, -284, BLIZZARD_CONTAINER_STRATA, min(220, leftW), scope, "blizzardContainerStrata", "AUTO", "visual",
        function() GFApplyBlizzardLayering(scope, false) end)
    nativeControls[#nativeControls + 1] = BindGFRootSlider(ctx, card, "Frame level offset", 16, -344, 0, 30, 1, min(260, leftW), scope, "blizzardContainerFrameLevel", 1, "visual",
        function() GFApplyBlizzardLayering(scope, false) end)

    W.LabelAt(card, "Aura types handled by Blizzard", rightX, -86, rightW, "GameFontNormalSmall", T.colors.accent)
    local buffChk = BindGFBlizzardTypeToggle(ctx, card, "Buffs", rightX, -116, routeW, scope, "buffs", true)
    local debuffChk = BindGFBlizzardTypeToggle(ctx, card, "Debuffs", routeX2, -116, routeW, scope, "debuffs", true)
    local dispelChk = BindGFBlizzardTypeToggle(ctx, card, "Dispels", rightX, -148, routeW, scope, "dispels", true)
    local extChk = BindGFBlizzardTypeToggle(ctx, card, "Defensives", routeX2, -148, routeW, scope, "externals", true)
    local privateChk = BindGFBlizzardTypeToggle(ctx, card, "Private Auras", rightX, -180, routeW, scope, "privateAuras", true)
    nativeControls[#nativeControls + 1] = buffChk
    nativeControls[#nativeControls + 1] = debuffChk
    nativeControls[#nativeControls + 1] = dispelChk
    nativeControls[#nativeControls + 1] = extChk
    nativeControls[#nativeControls + 1] = privateChk

    nativeControls[#nativeControls + 1] = BindGFRootToggle(ctx, card, "Blizzard Cooldown Text", rightX, -230, rightW, scope, "blizzardShowCooldownText", true, "visual")
    local dispelBorder = BindGFRootToggle(ctx, card, "MSUF Dispel Highlights", rightX, -262, rightW, scope, "blizzardDispelBorder", false, "rebuild")
    nativeControls[#nativeControls + 1] = BindGFRootToggle(ctx, card, "Keep private auras above frames", rightX, -294, rightW, scope, "blizzardPrivateLayerFix", true, "visual",
        function() GFApplyBlizzardLayering(scope, true) end)
    AddTooltip(buffChk, "Use Blizzard: Buffs", "Off means MSUF Custom Buffs can run while Blizzard rendering is still active.")
    AddTooltip(debuffChk, "Use Blizzard: Debuffs", "When enabled, WoW owns debuff icons. MSUF custom filtering only applies to MSUF Custom icons.")
    AddTooltip(dispelBorder, "MSUF Dispel Highlights", "Keeps Blizzard aura icons active, but lets MSUF draw dispel border, glow and overlay visuals.")

    M.AddRefresher(ctx, function()
        local root = GFReadRoot(scope)
        local native = (root.renderer or "BLIZZARD") ~= "CUSTOM"
        local nativeDispels = native and GFReadBlizzardType(scope, "dispels", true)
        if W.SetControlsEnabled then W.SetControlsEnabled(nativeControls, native) end
        if W.SetControlEnabled then
            W.SetControlEnabled(rendererMode, true)
            W.SetControlEnabled(dispelBorder, nativeDispels)
        end
    end)
end

local function BuildGroupFrameStyleControls(ctx, parent, x, y, width)
    local scope = CurrentGFStyleScope()
    local groupKey = CurrentGFStyleLane(true)
    local card = AuraControlCard(parent, "Group Frame Custom Aura Style", "Moved here from Group Frames. Raid and Mythic Raid are edited together.", x, y, width, 410)
    W.LabelAt(card, "Group", 16, -46, 80, "GameFontNormalSmall", T.colors.accent)
    BuildGFStyleScopeTabs(ctx, card, 80, -42, min(270, width - 112))
    W.LabelAt(card, "Lane", 16, -86, 80, "GameFontNormalSmall", T.colors.accent)
    BuildGFLaneTabs(ctx, card, 80, -82, min(430, width - 112), true, false)

    local leftW = max(250, floor((width - 60) / 2))
    local rightX = 36 + leftW
    local rightW = max(250, width - rightX - 20)
    W.LabelAt(card, GroupScopeLabel(scope) .. " - " .. GroupLaneLabel(groupKey), 16, -126, width - 32, "GameFontNormalSmall", T.colors.text)

    local controls = {}
    if groupKey == "buff" or groupKey == "debuff" then
        controls[#controls + 1] = BindGFDropdown(ctx, card, "Base Filter", 16, -178, GroupFilterValues(groupKey), leftW, scope, groupKey, "filterToken", groupKey == "buff" and "RAID" or "ALL", "visual")
        if groupKey == "debuff" then
            controls[#controls + 1] = BindGFToggle(ctx, card, "Show Dispel Type Border", 16, -232, leftW, scope, groupKey, "showDispelBorder", true, "visual")
        end
    else
        W.Text(card, "Defensives use Blizzard's big-defensive token and only expose text styling here.", 16, -168, leftW, T.colors.muted)
    end

    controls[#controls + 1] = BindGFToggle(ctx, card, "Show Cooldown Swipe", rightX, -158, rightW, scope, groupKey, "showCooldownSwipe", true, "visual")
    controls[#controls + 1] = BindGFToggle(ctx, card, "Show Cooldown Text", rightX, -190, rightW, scope, groupKey, "showCooldown", true, "visual")
    controls[#controls + 1] = BindGFToggle(ctx, card, "Show Stack Count", rightX, -222, rightW, scope, groupKey, "showStacks", groupKey ~= "externals", "visual")
    CreateGroupAuraTextPreview(ctx, card, scope, groupKey, rightX, -262, rightW)

    controls[#controls + 1] = BindGFSlider(ctx, card, "Cooldown Font", 16, -300, 6, 24, 1, leftW, scope, groupKey, "cooldownSize", groupKey == "externals" and 10 or 8, "font")
    controls[#controls + 1] = BindGFDropdown(ctx, card, "Cooldown Anchor", 16, -354, GFAnchorValues(), leftW, scope, groupKey, "cooldownAnchor", "CENTER", "geometry")
    controls[#controls + 1] = BindGFSlider(ctx, card, "Stack Font", rightX, -354, 6, 24, 1, rightW, scope, groupKey, "stackSize", 10, "font")
end

local function CategoryLabel(cat)
    if cat and cat.key == "RAID_BUFFS" then return "Raid / Mythic Buffs" end
    return (cat and cat.label) or (cat and cat.key) or ""
end

local function BuildGroupFrameCategoryBlacklist(ctx, parent, x, y, width)
    local af = AuraFilter()
    local meta = af and af.DECLASSIFIED_META
    local card = AuraControlCard(parent, "Group Frame Category Blacklist", "Hides Blizzard-declassified spells from MSUF Custom group-frame aura icons.", x, y, width, 356)
    W.LabelAt(card, "Group", 16, -46, 80, "GameFontNormalSmall", T.colors.accent)
    BuildGFStyleScopeTabs(ctx, card, 80, -42, min(270, width - 112))
    W.LabelAt(card, "Lane", 16, -86, 80, "GameFontNormalSmall", T.colors.accent)
    BuildGFLaneTabs(ctx, card, 80, -82, min(300, width - 112), false, true)

    local scope = CurrentGFStyleScope()
    local groupKey = CurrentGFBlacklistLane()
    local hint = groupKey == "buff"
        and "Checked categories hide MSUF custom buff icons only. Blizzard-rendered buffs bypass this list while Use Blizzard: Buffs is enabled."
        or "Checked categories hide MSUF custom debuff icons only. Blizzard-rendered debuffs bypass this list while Use Blizzard: Debuffs is enabled."
    W.Text(card, hint, 16, -124, width - 32, T.colors.danger or T.colors.muted)

    if not (type(meta) == "table" and #meta > 0) then
        W.Text(card, "No public aura category data is loaded.", 16, -166, width - 32, T.colors.muted)
        return
    end

    local half = ceil(#meta / 2)
    local colW = max(230, floor((width - 56) / 2))
    local x2 = 16 + colW + 24
    local startY = -176
    for i = 1, #meta do
        local cat = meta[i]
        local col = i <= half and 0 or 1
        local row = col == 0 and (i - 1) or (i - half - 1)
        local tx = col == 0 and 16 or x2
        local toggle = W.ToggleAt(card, CategoryLabel(cat), tx, startY - row * 30, colW)
        M.BindToggle(ctx, toggle,
            function() return GFReadBlacklistCat(scope, groupKey, cat.key) end,
            function(value) GFWriteBlacklistCat(scope, groupKey, cat.key, value) end)
        if cat.tooltip then
            AddTooltip(toggle, CategoryLabel(cat), cat.tooltip)
        end
    end
end

local function BuildGroupFrameUtilityControls(ctx, parent, x, y, width)
    local scope = CurrentGFStyleScope()
    local card = AuraControlCard(parent, "Group Frame Aura Utilities", "Shared aura behavior. Raid and Mythic Raid are edited together.", x, y, width, 226)
    W.LabelAt(card, "Group", 16, -46, 80, "GameFontNormalSmall", T.colors.accent)
    BuildGFStyleScopeTabs(ctx, card, 80, -42, min(270, width - 112))

    local colW = max(230, floor((width - 56) / 2))
    local rightX = 16 + colW + 24
    BindGFConfToggle(ctx, card, "Cooldown darkens on loss", 16, -96, colW, scope, "cooldownSwipeDarkenOnLoss", false, "visual")
    BindGFConfToggle(ctx, card, "Masque skin", 16, -128, colW, scope, "masqueEnabled", false, "visual", function()
        local gf = GF()
        if gf and gf.Masque and type(gf.Masque.ReskinAllIcons) == "function" then
            gf.Masque.ReskinAllIcons()
        end
    end)
    BindGFRootToggle(ctx, card, "Dynamic icon scale", 16, -160, colW, scope, "dynamicScale", false, "geometry")
    BindGFRootToggle(ctx, card, "Show tooltip on auras", rightX, -96, colW, scope, "showTooltip", true, "visual")
    BindGFRootToggle(ctx, card, "Sort by duration", rightX, -128, colW, scope, "sortByDuration", false, "visual")
    BindGFRootToggle(ctx, card, "Prefer player auras", rightX, -160, colW, scope, "preferPlayer", true, "visual")
    BindGFPrivateToggle(ctx, card, "Private aura countdown", 16, -192, colW, scope, "showCountdown", true, "visual")
    BindGFPrivateToggle(ctx, card, "Private aura numbers", rightX, -192, colW, scope, "showNumbers", false, "visual")
end

function M.BuildAuras3UnitSection(ctx, builder, unit)
    if not Model.UnitSupported(unit) then return end

    local sec = builder:CollapsibleSection("auras3", "Auras", 696, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 18
    local gap = 18
    local colW = max(260, floor((sectionW - leftX * 2 - gap) / 2))
    local rightX = leftX + colW + gap
    local controlW = max(180, colW - 32)
    local visualControls = {}
    local textControls = {}
    local ruleControls = {}

    W.LabelAt(sec, "Unit Scope", leftX, -14, 120, "GameFontNormalSmall", T.colors.accent)
    local unitName = Model.ScopeLabel(unit)
    local unitBadge = W.LabelAt(sec, unitName, leftX + 112, -14, 120, "GameFontHighlightSmall", T.colors.text)
    local status = W.Text(sec, "", rightX, -14, colW, T.colors.muted)

    local enable = BindSwitch(ctx, sec, "Enable Auras", leftX, -44, 180,
        function() return Model.UnitEnabled(unit) end,
        function(v) Model.SetUnitEnabled(unit, v) end,
        unit, "AURAS3_UNIT_ENABLE", true)
    enable._msuf2UnitFrameGateAlwaysEnabled = true

    local sharedVisuals = BindSwitch(ctx, sec, "Use Shared Visuals", leftX, -76, 200,
        function() return Model.UseSharedVisuals(unit) end,
        function(v) Model.SetUseSharedVisuals(unit, v) end,
        unit, "AURAS3_UNIT_SHARED_VISUALS", true)
    sharedVisuals._msuf2UnitFrameGateAlwaysEnabled = true

    local sharedRules = BindSwitch(ctx, sec, "Use Shared Rules", leftX, -108, 200,
        function() return Model.UseSharedRules(unit) end,
        function(v) Model.SetUseSharedRules(unit, v) end,
        unit, "AURAS3_UNIT_SHARED_RULES", true)
    sharedRules._msuf2UnitFrameGateAlwaysEnabled = true

    local styleBtn = StyleButton(sec, "Aura Style", 118, 24)
    styleBtn:SetPoint("TOPLEFT", sec, "TOPLEFT", rightX, -44)
    styleBtn._msuf2UnitFrameGateAlwaysEnabled = true
    styleBtn:SetScript("OnClick", function()
        SetCurrentScope(unit)
        if M.SelectPage then M.SelectPage("auras3") end
    end)

    local popupBtn = StyleButton(sec, "Position Popup", 136, 24)
    popupBtn:SetPoint("TOPLEFT", sec, "TOPLEFT", rightX + 130, -44)
    popupBtn:SetScript("OnClick", function()
        if type(_G.MSUF_OpenAuras3PositionPopup) == "function" then _G.MSUF_OpenAuras3PositionPopup(unit == "boss" and "boss1" or unit, popupBtn) end
    end)

    local resetBtn = StyleButton(sec, "Reset Visuals", 124, 24)
    resetBtn:SetPoint("TOPLEFT", sec, "TOPLEFT", rightX, -76)
    resetBtn:SetScript("OnClick", function()
        Model.SetUseSharedVisuals(unit, true)
        ApplyAndRefresh(ctx, unit, "AURAS3_UNIT_RESET_VISUALS", true)
    end)

    local blacklistBtn = StyleButton(sec, "Blacklist", 112, 24)
    blacklistBtn:SetPoint("TOPLEFT", sec, "TOPLEFT", rightX + 136, -76)
    blacklistBtn._msuf2UnitFrameGateAlwaysEnabled = true
    blacklistBtn:SetScript("OnClick", function()
        SetCurrentScope(unit)
        SetCurrentTab("blacklist")
        if M.SelectPage then M.SelectPage("auras3") end
    end)

    local laneTabsW = min(280, colW)
    local modeTabsW = min(280, colW)
    local laneTabs = W.Segment(sec, "Aura Type", UNIT_AURA_LANE_TABS, laneTabsW)
    W.MoveWidget(laneTabs, sec, leftX, -148, laneTabsW, "LEFT")
    laneTabs._msuf2UnitFrameGateAlwaysEnabled = true
    local modeTabs = W.Segment(sec, "Settings", UNIT_AURA_MODE_TABS, modeTabsW)
    W.MoveWidget(modeTabs, sec, rightX, -148, modeTabsW, "LEFT")
    modeTabs._msuf2UnitFrameGateAlwaysEnabled = true

    M.unitAuraLaneSelection = M.unitAuraLaneSelection or {}
    M.unitAuraModeSelection = M.unitAuraModeSelection or {}

    local function CurrentAuraLane()
        local key = M.unitAuraLaneSelection[unit] or "buff"
        return key == "debuff" and "debuff" or "buff"
    end

    local function CurrentAuraMode()
        local key = M.unitAuraModeSelection[unit] or "basic"
        return key == "advanced" and "advanced" or "basic"
    end

    local RefreshAuraTabs
    M.BindSegment(ctx, laneTabs,
        CurrentAuraLane,
        function(value)
            M.unitAuraLaneSelection[unit] = value == "debuff" and "debuff" or "buff"
            if RefreshAuraTabs then RefreshAuraTabs() end
        end)
    M.BindSegment(ctx, modeTabs,
        CurrentAuraMode,
        function(value)
            M.unitAuraModeSelection[unit] = value == "advanced" and "advanced" or "basic"
            if RefreshAuraTabs then RefreshAuraTabs() end
        end)

    local tabFrames = {}
    local function CreateUnitAuraTab(kind, mode)
        local frame = CreateFrame("Frame", nil, sec)
        frame:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -204)
        frame:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", 0, 12)
        frame._msuf2Width = sectionW
        tabFrames[kind .. "_" .. mode] = frame
        return frame
    end

    local function LaneLabel(kind)
        return kind == "buff" and "Buffs" or "Debuffs"
    end

    local function LaneSingular(kind)
        return kind == "buff" and "Buff" or "Debuff"
    end

    local function LaneSizeKey(kind)
        return kind == "buff" and "buffGroupIconSize" or "debuffGroupIconSize"
    end

    local function LaneMaxKey(kind)
        return kind == "buff" and "maxBuffs" or "maxDebuffs"
    end

    local function AddLaneBasicControls(parent, kind)
        local label = LaneLabel(kind)
        local prefix = LaneSingular(kind)
        local sizeKey = LaneSizeKey(kind)
        local maxKey = LaneMaxKey(kind)

        local basics = AuraControlCard(parent, label .. " Basic", nil, leftX, -8, colW, 250)
        visualControls[#visualControls + 1] = BindSwitch(ctx, basics, "Show " .. label, 16, -44, 190,
            function() return Model.GroupShown(unit, kind) end,
            function(v) Model.SetGroupShown(unit, kind, v) end,
            unit, "AURAS3_UNIT_" .. kind .. "_SHOW", true)
        visualControls[#visualControls + 1] = BindSlider(ctx, basics, "Icon Size", 16, -92, 10, 80, 1, controlW,
            function() return Model.ReadNumber(unit, sizeKey, 26, 1, 128) end,
            function(v) Model.WriteNumber(unit, sizeKey, v, 1, 128) end,
            unit, "AURAS3_UNIT_" .. kind .. "_SIZE")
        visualControls[#visualControls + 1] = BindSlider(ctx, basics, "Max " .. prefix .. "s", 16, -152, 0, 80, 1, controlW,
            function() return Model.ReadNumber(unit, maxKey, kind == "buff" and 8 or 12, 0, 80) end,
            function(v) Model.WriteNumber(unit, maxKey, v, 0, 80) end,
            unit, "AURAS3_UNIT_" .. kind .. "_MAX")
        W.Text(basics, "Position: drag the preview handle, use arrow keys, or open Position Popup.", 16, -218, colW - 32, T.colors.muted)

        local flow = AuraControlCard(parent, label .. " Flow", nil, rightX, -8, colW, 250)
        visualControls[#visualControls + 1] = BindDropdown(ctx, flow, "Growth Direction", 16, -44, Model.GrowthValues(), controlW,
            function() return Model.ReadLaneGrowth(unit, kind) end,
            function(v) Model.WriteLaneGrowth(unit, kind, v) end,
            unit, "AURAS3_UNIT_" .. kind .. "_GROWTH")
        visualControls[#visualControls + 1] = BindSlider(ctx, flow, prefix .. "s per row", 16, -104, 1, 40, 1, controlW,
            function() return Model.ReadLanePerRow(unit, kind) end,
            function(v) Model.WriteLanePerRow(unit, kind, v) end,
            unit, "AURAS3_UNIT_" .. kind .. "_PER_ROW")
        W.Text(flow, "Use separate directions here when Buffs and Debuffs should build away from different anchors.", 16, -170, colW - 32, T.colors.muted)
    end

    local function AddLaneAdvancedControls(parent, kind)
        local label = LaneLabel(kind)
        local prefix = LaneSingular(kind)

        local flow = AuraControlCard(parent, label .. " Advanced Flow", nil, leftX, -8, colW, 312)
        visualControls[#visualControls + 1] = BindDropdown(ctx, flow, "Growth Direction", 16, -44, Model.GrowthValues(), controlW,
            function() return Model.ReadLaneGrowth(unit, kind) end,
            function(v) Model.WriteLaneGrowth(unit, kind, v) end,
            unit, "AURAS3_UNIT_" .. kind .. "_ADV_GROWTH")
        visualControls[#visualControls + 1] = BindDropdown(ctx, flow, "Row Wrap", 16, -96, Model.RowWrapValues(), controlW,
            function() return Model.ReadLaneRowWrap(unit, kind) end,
            function(v) Model.WriteLaneRowWrap(unit, kind, v) end,
            unit, "AURAS3_UNIT_" .. kind .. "_ROW_WRAP")
        visualControls[#visualControls + 1] = BindSlider(ctx, flow, prefix .. "s per row", 16, -148, 1, 40, 1, controlW,
            function() return Model.ReadLanePerRow(unit, kind) end,
            function(v) Model.WriteLanePerRow(unit, kind, v) end,
            unit, "AURAS3_UNIT_" .. kind .. "_ADV_PER_ROW")
        visualControls[#visualControls + 1] = BindSlider(ctx, flow, "Spacing", 16, -208, 0, 12, 1, controlW,
            function() return Model.ReadNumber(unit, "spacing", 2, 0, 64) end,
            function(v) Model.WriteNumber(unit, "spacing", v, 0, 64) end,
            unit, "AURAS3_UNIT_SPACING")
        W.Text(flow, "Spacing is shared by both lanes; direction and row wrap are lane-specific.", 16, -280, colW - 32, T.colors.muted)

        local text = AuraControlCard(parent, "Text", "Applies to both Buffs and Debuffs.", rightX, -8, colW, 390)
        textControls[#textControls + 1] = BindSwitch(ctx, text, "Show Stack Count", 16, -70, 190,
            function() return Model.ReadSharedBool("showStackCount", true) end,
            function(v) Model.WriteSharedBool("showStackCount", v) end,
            unit, "AURAS3_UNIT_STACK_TOGGLE", true)
        textControls[#textControls + 1] = BindSwitch(ctx, text, "Show Cooldown Text", 16, -102, 200,
            function() return Model.ReadSharedBool("showCooldownText", true) end,
            function(v) Model.WriteSharedBool("showCooldownText", v) end,
            unit, "AURAS3_UNIT_COOLDOWN_TOGGLE", true)
        textControls[#textControls + 1] = BindDropdown(ctx, text, "Stack Anchor", 16, -154, Model.StackAnchorValues(), controlW,
            function() return Model.ReadStackAnchor(unit) end,
            function(v) Model.WriteStackAnchor(unit, v) end,
            unit, "AURAS3_UNIT_STACK_ANCHOR")
        textControls[#textControls + 1] = BindSlider(ctx, text, "Stack size", 16, -210, 6, 40, 1, controlW,
            function() return Model.ReadNumber(unit, "stackTextSize", 14, 6, 40) end,
            function(v) Model.WriteNumber(unit, "stackTextSize", v, 6, 40) end,
            unit, "AURAS3_UNIT_STACK_SIZE")
        textControls[#textControls + 1] = BindSlider(ctx, text, "Cooldown size", 16, -270, 6, 40, 1, controlW,
            function() return Model.ReadNumber(unit, "cooldownTextSize", 14, 6, 40) end,
            function(v) Model.WriteNumber(unit, "cooldownTextSize", v, 6, 40) end,
            unit, "AURAS3_UNIT_COOLDOWN_SIZE")
        W.Text(text, "Font family uses Global Font settings.", 16, -356, colW - 32, T.colors.muted)
    end

    AddLaneBasicControls(CreateUnitAuraTab("buff", "basic"), "buff")
    AddLaneAdvancedControls(CreateUnitAuraTab("buff", "advanced"), "buff")
    AddLaneBasicControls(CreateUnitAuraTab("debuff", "basic"), "debuff")
    AddLaneAdvancedControls(CreateUnitAuraTab("debuff", "advanced"), "debuff")

    RefreshAuraTabs = function()
        local activeKey = CurrentAuraLane() .. "_" .. CurrentAuraMode()
        for key, frame in pairs(tabFrames) do
            if key == activeKey then frame:Show() else frame:Hide() end
        end
    end
    M.AddRefresher(ctx, RefreshAuraTabs)
    laneTabs:SetValue(CurrentAuraLane())
    modeTabs:SetValue(CurrentAuraMode())
    RefreshAuraTabs()

    M.AddRefresher(ctx, function()
        local customVisuals = not Model.UseSharedVisuals(unit)
        local customRules = not Model.UseSharedRules(unit)
        if unitBadge and unitBadge.SetText then unitBadge:SetText(Model.ScopeLabel(unit)) end
        if status and status.SetText then
            status:SetText(customVisuals and "Custom visual settings for this unit." or "This unit inherits Shared visuals. Dragging aura handles creates a custom layout.")
        end
        W.SetControlsEnabled(visualControls, customVisuals)
        W.SetControlsEnabled(textControls, customVisuals)
        W.SetControlsEnabled(ruleControls, customRules)
        W.SetControlEnabled(resetBtn, customVisuals)
        W.SetControlEnabled(popupBtn, Model.UnitEnabled(unit))
    end)
end

local function BuildOverviewTab(ctx, b, scope)
    local section = b:Section("Overview", 342)
    local w = section._msuf2Width or b.width or 720
    local leftW = max(300, floor(w * 0.48))
    local rightX = leftW + 34
    local rightW = w - rightX - 18
    W.ControlCardBackdrop(section, 14, -38, leftW, 180)
    W.LabelAt(section, "Visible Units", 30, -56, 180, "GameFontNormalSmall", T.colors.accent)
    BindSwitch(ctx, section, "Player", 30, -86, 110, function() return Model.UnitEnabled("player") end, function(v) Model.SetUnitEnabled("player", v) end, "player", "AURAS3_OVERVIEW_PLAYER", true)
    BindSwitch(ctx, section, "Target", 168, -86, 110, function() return Model.UnitEnabled("target") end, function(v) Model.SetUnitEnabled("target", v) end, "target", "AURAS3_OVERVIEW_TARGET", true)
    BindSwitch(ctx, section, "Focus", 30, -118, 110, function() return Model.UnitEnabled("focus") end, function(v) Model.SetUnitEnabled("focus", v) end, "focus", "AURAS3_OVERVIEW_FOCUS", true)
    BindSwitch(ctx, section, "Boss", 168, -118, 110, function() return Model.UnitEnabled("boss") end, function(v) Model.SetUnitEnabled("boss", v) end, "boss", "AURAS3_OVERVIEW_BOSS", true)
    W.Text(section, "Unit pages own positioning. Aura Style owns unit rules, blacklists, colors and group-frame custom aura filters/style.", 30, -154, leftW - 32, T.colors.muted)

    W.ControlCardBackdrop(section, rightX, -38, rightW, 254)
    W.LabelAt(section, "Active Scope", rightX + 16, -56, 160, "GameFontNormalSmall", T.colors.accent)
    local summary = W.Text(section, "", rightX + 16, -84, rightW - 32, T.colors.muted)
    BuildMiniAuraPreview(ctx, section, scope, rightX + 16, -130, rightW - 32, 132)
    M.AddRefresher(ctx, function()
        local text
        if scope == "shared" then
            text = "Shared is the baseline for every unit frame."
        else
            local v = Model.UseSharedVisuals(scope) and "inherits visuals" or "overrides visuals"
            local r = Model.UseSharedRules(scope) and "uses shared rules" or "overrides rules"
            text = Model.ScopeLabel(scope) .. " " .. v .. " and " .. r .. "."
        end
        summary:SetText(text)
    end)
end

local function BuildGroupOverviewTab(ctx, b, scope)
    local section = b:Section("Overview", 342)
    local w = section._msuf2Width or b.width or 720
    local card = AuraControlCard(section, "Group Frame Aura Style", "This scope edits " .. GroupScopeLabel(scope) .. ". Position, size and growth stay on the Group Frames page.", 24, -42, w - 48, 214)
    W.LabelAt(card, "Active Scope", 16, -54, 160, "GameFontNormalSmall", T.colors.accent)
    W.Text(card, GroupScopeLabel(scope), 16, -82, w - 96, T.colors.text)
    W.Text(card, "Use Rules for renderer, Blizzard routing, custom filters and aura text. Use Blacklist for declassified category hiding. Use Special for shared group-frame aura behavior.", 16, -120, w - 96, T.colors.muted)
end

local function BuildGroupRulesTab(ctx, b)
    local section = b:Section("Rules", 884)
    local w = section._msuf2Width or b.width or 720
    BuildGroupFrameDisplayControls(ctx, section, 24, -42, w - 48)
    BuildGroupFrameStyleControls(ctx, section, 24, -450, w - 48)
end

local function BuildGroupBlacklistTab(ctx, b)
    local section = b:Section("Blacklist", 440)
    local w = section._msuf2Width or b.width or 720
    BuildGroupFrameCategoryBlacklist(ctx, section, 24, -42, w - 48)
end

local function BuildGroupSpecialTab(ctx, b)
    local section = b:Section("Special", 320)
    local w = section._msuf2Width or b.width or 720
    BuildGroupFrameUtilityControls(ctx, section, 24, -42, w - 48)
end

local function BuildRulesTab(ctx, b, scope)
    local section = b:Section("Rules", 1380)
    local w = section._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 48) / 2))
    local rightX = 24 + colW + 16
    local filterControls = {}
    local useShared
    if scope ~= "shared" then
        useShared = BindSwitch(ctx, section, "Use Shared Rules", 24, -38, 190,
            function() return Model.UseSharedRules(scope) end,
            function(v) Model.SetUseSharedRules(scope, v) end,
            scope, "AURAS3_RULES_SHARED", true)
    end
    local enableFilters = BindSwitch(ctx, section, "Enable Filters", scope == "shared" and 24 or 234, -38, 180,
        function() return Model.ScopeFiltersEnabled(scope) end,
        function(v) Model.SetScopeFiltersEnabled(scope, v) end,
        scope, "AURAS3_RULES_ENABLE", true)

    local function FilterToggle(card, label, kind, key, x, y, tip)
        local widget = BindSwitch(ctx, card, label, x, y, colW - 64,
            function() return Model.ReadFilter(scope, kind, key, false) == true end,
            function(v) Model.WriteFilter(scope, kind, key, v) end,
            scope, "AURAS3_RULE_" .. kind .. "_" .. key, true)
        AddTooltip(widget, label, tip or "")
        filterControls[#filterControls + 1] = widget
        return widget
    end

    local buff = AuraControlCard(section, "Buffs", nil, 24, -84, colW, 378)
    local debuff = AuraControlCard(section, "Debuffs", nil, rightX, -84, colW, 378)
    BindSwitch(ctx, buff, "Show Buffs", 16, -44, 160,
        function() return Model.ReadSharedBool("showBuffs", true) end,
        function(v) Model.WriteSharedBool("showBuffs", v) end,
        "shared", "AURAS3_RULE_SHOW_BUFFS", true)
    BindSwitch(ctx, debuff, "Show Debuffs", 16, -44, 170,
        function() return Model.ReadSharedBool("showDebuffs", true) end,
        function(v) Model.WriteSharedBool("showDebuffs", v) end,
        "shared", "AURAS3_RULE_SHOW_DEBUFFS", true)

    W.LabelAt(buff, "Unexclusive Filters", 16, -86, colW - 32, "GameFontNormalSmall", T.colors.accent)
    FilterToggle(buff, "Player", "buff", "onlyMine", 16, -112, "Auras applied by the player.")
    FilterToggle(buff, "Raid", "buff", "raid", 16, -144, "Stored as a Blizzard filter token for the Auras3 filter module.")
    FilterToggle(buff, "Cancelable", "buff", "cancelable", 16, -176, "Stored as a Blizzard filter token for the Auras3 filter module.")
    FilterToggle(buff, "Not Cancelable", "buff", "notCancelable", 16, -208, "Stored as a Blizzard filter token for the Auras3 filter module.")
    FilterToggle(buff, "Stealable", "buff", "includeStealable", 16, -240, "Connected to Auras3 stealable buff marker.")
    filterControls[#filterControls + 1] = BindDropdown(ctx, buff, "Exclusive Filter", 16, -292, BUFF_EXCLUSIVE, min(250, colW - 32),
        function() return Model.ReadFilter(scope, "buff", "exclusive", "none") end,
        function(v) Model.WriteFilter(scope, "buff", "exclusive", v or "none") end,
        scope, "AURAS3_RULE_BUFF_EXCLUSIVE", true)

    W.LabelAt(debuff, "Unexclusive Filters", 16, -86, colW - 32, "GameFontNormalSmall", T.colors.accent)
    FilterToggle(debuff, "Player", "debuff", "onlyMine", 16, -112, "Debuffs applied by the player.")
    FilterToggle(debuff, "Raid", "debuff", "raid", 16, -144, "Stored as a Blizzard filter token for the Auras3 filter module.")
    FilterToggle(debuff, "Dispellable", "debuff", "includeDispellable", 16, -176, "Stored for the Auras3 filter module.")
    FilterToggle(debuff, "Not Dispellable", "debuff", "notDispellable", 16, -208, "Stored for the Auras3 filter module.")
    FilterToggle(debuff, "Boss", "debuff", "boss", 16, -240, "Stored for the Auras3 filter module.")
    filterControls[#filterControls + 1] = BindDropdown(ctx, debuff, "Exclusive Filter", 16, -292, DEBUFF_EXCLUSIVE, min(250, colW - 32),
        function() return Model.ReadFilter(scope, "debuff", "exclusive", "none") end,
        function(v) Model.WriteFilter(scope, "debuff", "exclusive", v or "none") end,
        scope, "AURAS3_RULE_DEBUFF_EXCLUSIVE", true)

    W.Text(section, "Currently active: Player, Important and stealable marker. Other Blizzard filter tokens are saved here for the later filter module.", 24, -474, w - 48, T.colors.muted)
    BuildGroupFrameDisplayControls(ctx, section, 24, -532, w - 48)
    BuildGroupFrameStyleControls(ctx, section, 24, -940, w - 48)
    M.AddRefresher(ctx, function()
        local customRules = scope == "shared" or not Model.UseSharedRules(scope)
        local filtersOn = customRules and Model.ScopeFiltersEnabled(scope)
        W.SetControlEnabled(enableFilters, customRules)
        W.SetControlsEnabled(filterControls, filtersOn)
        if useShared then W.SetControlEnabled(useShared, scope ~= "shared") end
    end)
end

local function BuildBlacklistTab(ctx, b, scope)
    local section = b:Section("Blacklist", 940)
    local w = section._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 68) / 2))
    local rightX = 36 + colW + 24
    local editEnabled = scope == "shared" or not Model.UseSharedBlacklist(scope)
    local useShared
    if scope ~= "shared" then
        useShared = BindSwitch(ctx, section, "Use Shared Blacklist", 24, -42, 210,
            function() return Model.UseSharedBlacklist(scope) end,
            function(v) Model.SetUseSharedBlacklist(scope, v) end,
            scope, "AURAS3_LISTS_SHARED", true)
    end

    local manual = AuraControlCard(section, "Blacklist", "Prepared spell-ID list for custom Auras3 lanes.", 24, -72, colW, 222)
    local preset = AuraControlCard(section, "Blacklist Presets", "Curated aura ID groups that can be added to the blacklist.", rightX, -72, colW, 222)

    local inputValue = ""
    local input = BindTextInput(ctx, manual, "Spell ID, spell link, or resolvable spell name", 16, -82, colW - 32,
        function() return inputValue end,
        function(v) inputValue = v or "" end,
        scope, "AURAS3_LIST_INPUT", false)
    local add = StyleButton(manual, "Add", 104, 24)
    add:SetPoint("TOPLEFT", manual, "TOPLEFT", 16, -134)
    add:SetScript("OnClick", function()
        local value = input and input.GetText and input:GetText() or inputValue
        Model.AddBlacklistSpell(scope, value)
        if input and input.SetText then input:SetText("") end
        inputValue = ""
        ApplyAndRefresh(ctx, scope, "AURAS3_BLACKLIST_ADD", true)
    end)
    local remove = StyleButton(manual, "Remove", 112, 24)
    remove:SetPoint("TOPLEFT", manual, "TOPLEFT", 134, -134)
    remove:SetScript("OnClick", function()
        local value = input and input.GetText and input:GetText() or inputValue
        Model.RemoveBlacklistSpell(scope, value)
        ApplyAndRefresh(ctx, scope, "AURAS3_BLACKLIST_REMOVE", true)
    end)
    W.Text(manual, "Runtime checks prepared spell IDs only. Names must resolve to an ID at Apply.", 16, -176, colW - 32, T.colors.muted)

    local function CurrentPreset()
        local key = M.auraBlacklistPreset or "RAID_BUFFS"
        local values = Model.BlacklistPresetValues()
        for i = 1, #values do
            if values[i].value == key then return key end
        end
        return values[1] and values[1].value or "RAID_BUFFS"
    end

    local presetDrop = W.Dropdown(preset, "Preset", function() return Model.BlacklistPresetValues() end, colW - 32)
    W.MoveWidget(presetDrop, preset, 16, -82, colW - 32)
    M.BindDropdown(ctx, presetDrop,
        function() return CurrentPreset() end,
        function(v)
            M.auraBlacklistPreset = v or "RAID_BUFFS"
            M.auraBlacklistSpell = nil
            if M.Refresh then M.Refresh(ctx) end
        end)
    local spellDrop = W.Dropdown(preset, "Spell", function() return Model.BlacklistSpellValues(CurrentPreset()) end, colW - 32)
    W.MoveWidget(spellDrop, preset, 16, -136, colW - 32)
    M.BindDropdown(ctx, spellDrop,
        function()
            local values = Model.BlacklistSpellValues(CurrentPreset())
            local selected = M.auraBlacklistSpell
            for i = 1, #values do
                if values[i].value == selected then return selected end
            end
            return values[1] and values[1].value or nil
        end,
        function(v) M.auraBlacklistSpell = v end)
    local addPreset = StyleButton(preset, "Add Spell", 112, 24)
    addPreset:SetPoint("TOPLEFT", preset, "TOPLEFT", 16, -184)
    addPreset:SetScript("OnClick", function()
        local values = Model.BlacklistSpellValues(CurrentPreset())
        local spellID = M.auraBlacklistSpell or (values[1] and values[1].value)
        Model.AddBlacklistPresetSpell(scope, spellID)
        ApplyAndRefresh(ctx, scope, "AURAS3_BLACKLIST_PRESET_ADD", true)
    end)
    local addPresetGroup = StyleButton(preset, "Add Group", 112, 24)
    addPresetGroup:SetPoint("TOPLEFT", preset, "TOPLEFT", 138, -184)
    addPresetGroup:SetScript("OnClick", function()
        Model.AddBlacklistPresetGroup(scope, CurrentPreset())
        ApplyAndRefresh(ctx, scope, "AURAS3_BLACKLIST_PRESET_GROUP_ADD", true)
    end)

    local current = AuraControlCard(section, "Current List", nil, 24, -318, w - 48, 184)
    local prepared = W.Text(current, "", 16, -18, w - 80, T.colors.accent)
    local emptyText = W.Text(current, "No blacklisted spells.", 16, -48, w - 80, T.colors.muted)
    local moreText = W.Text(current, "Click an entry to remove it.", 16, -164, w - 80, T.colors.muted)
    local listScroll = CreateFrame("ScrollFrame", nil, current, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", current, "TOPLEFT", 16, -42)
    listScroll:SetSize(w - 82, 116)
    if listScroll.EnableMouseWheel then listScroll:EnableMouseWheel(true) end
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(w - 104, 116)
    listScroll:SetScrollChild(listChild)
    listScroll:SetScript("OnMouseWheel", function(self, delta)
        local step = 42
        local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
        local value = (self.GetVerticalScroll and self:GetVerticalScroll() or 0) - ((tonumber(delta) or 0) * step)
        if value < 0 then value = 0 end
        if value > range then value = range end
        if self.SetVerticalScroll then self:SetVerticalScroll(value) end
    end)
    local rows = {}
    local rowW = w - 112
    local rowH = 22
    local function EnsureRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Button", nil, listChild)
        row:SetSize(rowW, rowH)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0.020, 0.026, 0.052, 0.78)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.icon:SetSize(18, 18)
        row.text = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(0.050, 0.065, 0.120, 0.92)
        end)
        row:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(0.020, 0.026, 0.052, 0.78)
        end)
        row:SetScript("OnClick", function(self)
            if not editEnabled then return end
            Model.RemoveBlacklistSpell(scope, self._msufValue)
            ApplyAndRefresh(ctx, scope, "AURAS3_BLACKLIST_REMOVE_ROW", true)
        end)
        row:Hide()
        rows[i] = row
        return row
    end

    M.AddRefresher(ctx, function()
        editEnabled = scope == "shared" or not Model.UseSharedBlacklist(scope)
        if useShared then W.SetControlEnabled(useShared, scope ~= "shared") end
        W.SetControlEnabled(input, editEnabled)
        W.SetControlEnabled(add, editEnabled)
        W.SetControlEnabled(remove, editEnabled)
        W.SetControlEnabled(presetDrop, editEnabled)
        W.SetControlEnabled(spellDrop, editEnabled)
        W.SetControlEnabled(addPreset, editEnabled)
        W.SetControlEnabled(addPresetGroup, editEnabled)
        local count = Model.BlacklistPreparedCount(scope)
        prepared:SetText(count == 1 and "1 prepared blacklist entry" or (tostring(count) .. " prepared blacklist entries"))
        local entries = Model.BlacklistEntries(scope)
        emptyText:SetShown(#entries == 0)
        listScroll:SetShown(#entries > 0)
        listChild:SetHeight(max(116, (#entries * 24) + 2))
        for i = 1, max(#rows, #entries) do
            local row = rows[i]
            local item = entries[i]
            if item then
                row = EnsureRow(i)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 24))
                row._msufValue = item.value
                if item.icon then
                    if type(MSUF_SetIconTexture) == "function" then
                        MSUF_SetIconTexture(row.icon, item.icon, "")
                    else
                        row.icon:SetTexture(item.icon)
                    end
                    row.icon:SetTexCoord(0, 1, 0, 1)
                    row.icon:Show()
                    row.text:ClearAllPoints()
                    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                else
                    row.icon:Hide()
                    row.text:ClearAllPoints()
                    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                end
                row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.text:SetText(item.text or item.value or "")
                row:SetAlpha(editEnabled and 1 or 0.55)
                row:Show()
            elseif row then
                row._msufValue = nil
                row:Hide()
            end
        end
        moreText:SetShown(#entries > 0)
    end)

    BuildGroupFrameCategoryBlacklist(ctx, section, 24, -532, w - 48)
end

local function BuildColorsTab(ctx, b, scope)
    local section = b:Section("Colors", 662)
    local w = section._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 56) / 2))
    local rightX = 24 + colW + 16
    local cooldown = AuraControlCard(section, "Cooldown Timer Colors", nil, 24, -38, colW, 330)
    local markers = AuraControlCard(section, "Stack & Highlights", nil, rightX, -38, colW, 330)
    local preview = T.Panel(cooldown, nil, { 0.014, 0.020, 0.040, 0.82 }, T.colors.borderSoft)
    preview:SetPoint("TOPLEFT", cooldown, "TOPLEFT", 16, -66)
    preview:SetSize(colW - 32, 88)
    W.LabelAt(preview, "Preview", 12, -12, 120, "GameFontNormalSmall", T.colors.muted)

    local samples = {}
    for i = 1, 3 do
        local box = T.Panel(preview, nil, { 0.020, 0.024, 0.046, 0.92 }, T.colors.borderSoft)
        box:SetPoint("LEFT", preview, "LEFT", 88 + (i - 1) * 78, -6)
        box:SetSize(64, 54)
        local fs = T.Font(box, nil, i == 1 and "60" or (i == 2 and "15" or "5"), T.colors.text)
        fs:SetFont(FONT, 18, "OUTLINE")
        fs:SetPoint("CENTER", box, "CENTER", 0, 6)
        local label = T.Font(box, "GameFontDisableSmall", i == 1 and "Safe" or (i == 2 and "Warn" or "Urgent"), T.colors.muted)
        label:SetPoint("BOTTOM", box, "BOTTOM", 0, 5)
        samples[i] = fs
    end

    local function RefreshColorSamples()
        local sr, sg, sb = Model.ReadGeneralColor("aurasCooldownTextSafeColor", 1, 1, 1)
        local wr, wg, wb = Model.ReadGeneralColor("aurasCooldownTextWarningColor", 1, 0.85, 0.20)
        local ur, ug, ub = Model.ReadGeneralColor("aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
        local buckets = Model.ReadGeneralBool("aurasCooldownTextUseBuckets", true)
        if samples[1] then samples[1]:SetTextColor(sr, sg, sb, 1) end
        if samples[2] then samples[2]:SetTextColor(buckets and wr or sr, buckets and wg or sg, buckets and wb or sb, 1) end
        if samples[3] then samples[3]:SetTextColor(buckets and ur or sr, buckets and ug or sg, buckets and ub or sb, 1) end
    end

    BindSwitch(ctx, cooldown, "Color by time", 16, -170, colW - 32,
        function() return Model.ReadGeneralBool("aurasCooldownTextUseBuckets", true) end,
        function(v) Model.WriteGeneralBool("aurasCooldownTextUseBuckets", v); RefreshColorSamples(); GFRequestTextRefresh() end,
        "shared", "AURAS3_COLOR_BUCKETS", false)
    BindColor(ctx, cooldown, "Safe", 16, -212,
        function() return Model.ReadGeneralColor("aurasCooldownTextSafeColor", 1, 1, 1) end,
        function(r, g, bcol) Model.WriteGeneralColor("aurasCooldownTextSafeColor", r, g, bcol); RefreshColorSamples(); GFRequestTextRefresh() end,
        "shared", "AURAS3_COLOR_SAFE", false)
    BindColor(ctx, cooldown, "Warning", 16, -246,
        function() return Model.ReadGeneralColor("aurasCooldownTextWarningColor", 1, 0.85, 0.20) end,
        function(r, g, bcol) Model.WriteGeneralColor("aurasCooldownTextWarningColor", r, g, bcol); RefreshColorSamples(); GFRequestTextRefresh() end,
        "shared", "AURAS3_COLOR_WARNING", false)
    BindColor(ctx, cooldown, "Urgent", 16, -280,
        function() return Model.ReadGeneralColor("aurasCooldownTextUrgentColor", 1, 0.55, 0.10) end,
        function(r, g, bcol) Model.WriteGeneralColor("aurasCooldownTextUrgentColor", r, g, bcol); RefreshColorSamples(); GFRequestTextRefresh() end,
        "shared", "AURAS3_COLOR_URGENT", false)

    BindColor(ctx, markers, "Stack Count", 16, -56,
        function() return Model.ReadGeneralColor("aurasStackCountColor", 1, 1, 1) end,
        function(r, g, bcol) Model.WriteGeneralColor("aurasStackCountColor", r, g, bcol); GFRequestTextRefresh() end,
        "shared", "AURAS3_COLOR_STACK", false)
    BindColor(ctx, markers, "Own Buff", 16, -98,
        function() return Model.ReadGeneralColor("aurasOwnBuffHighlightColor", 1, 0.85, 0.20) end,
        function(r, g, bcol) Model.WriteGeneralColor("aurasOwnBuffHighlightColor", r, g, bcol) end,
        "shared", "AURAS3_COLOR_OWN_BUFF", false)
    BindColor(ctx, markers, "Own Debuff", 16, -140,
        function() return Model.ReadGeneralColor("aurasOwnDebuffHighlightColor", 1, 0.30, 0.30) end,
        function(r, g, bcol) Model.WriteGeneralColor("aurasOwnDebuffHighlightColor", r, g, bcol) end,
        "shared", "AURAS3_COLOR_OWN_DEBUFF", false)
    BindSlider(ctx, markers, "Safe seconds", 16, -190, 0, 600, 1, min(250, colW - 32),
        function() return Model.ReadGeneralNumber("aurasCooldownTextSafeSeconds", 60, 0, 600) end,
        function(v) Model.WriteGeneralNumber("aurasCooldownTextSafeSeconds", v, 0, 600) end,
        "shared", "AURAS3_COLOR_SAFE_SECONDS")
    BindSlider(ctx, markers, "Warning <= sec", 16, -250, 0, 60, 1, min(250, colW - 32),
        function() return Model.ReadGeneralNumber("aurasCooldownTextWarningSeconds", 15, 0, 60) end,
        function(v) Model.WriteGeneralNumber("aurasCooldownTextWarningSeconds", v, 0, 60) end,
        "shared", "AURAS3_COLOR_WARNING_SECONDS")

    local groupTimers = AuraControlCard(section, "Group Frame Timer Buckets", "Applies to MSUF Custom group-frame aura icons. Raid and Mythic use the same thresholds.", 24, -388, w - 48, 196)
    BindSwitch(ctx, groupTimers, "Color group-frame aura timers by remaining time", 16, -58, min(360, w - 96),
        function() return Model.ReadGeneralBool("gfAurasCooldownTextUseBuckets", true) end,
        function(v) Model.WriteGeneralBool("gfAurasCooldownTextUseBuckets", v); GFRequestTextRefresh() end,
        "shared", "AURAS3_GF_COLOR_BUCKETS", false)
    local timerColW = max(190, floor((w - 112) / 3))
    BindSlider(ctx, groupTimers, "Safe (seconds)", 16, -120, 0, 600, 1, timerColW,
        function() return Model.ReadGeneralNumber("gfAurasCooldownTextSafeSeconds", 60, 0, 600) end,
        function(v) Model.WriteGeneralNumber("gfAurasCooldownTextSafeSeconds", v, 0, 600); GFRequestTextRefresh() end,
        "shared", "AURAS3_GF_COLOR_SAFE_SECONDS")
    BindSlider(ctx, groupTimers, "Warning <=", 40 + timerColW, -120, 0, 60, 1, timerColW,
        function() return Model.ReadGeneralNumber("gfAurasCooldownTextWarningSeconds", 15, 0, 60) end,
        function(v) Model.WriteGeneralNumber("gfAurasCooldownTextWarningSeconds", v, 0, 60); GFRequestTextRefresh() end,
        "shared", "AURAS3_GF_COLOR_WARNING_SECONDS")
    BindSlider(ctx, groupTimers, "Urgent <=", 64 + timerColW * 2, -120, 0, 30, 1, timerColW,
        function() return Model.ReadGeneralNumber("gfAurasCooldownTextUrgentSeconds", 5, 0, 30) end,
        function(v) Model.WriteGeneralNumber("gfAurasCooldownTextUrgentSeconds", v, 0, 30); GFRequestTextRefresh() end,
        "shared", "AURAS3_GF_COLOR_URGENT_SECONDS")

    W.Text(section, "Aura text size, anchor and position live on UnitFrame pages and in Aura Style > Rules for Group Frames.", 24, -606, w - 48, T.colors.muted)
    M.AddRefresher(ctx, RefreshColorSamples)
end

local function BuildSpecialTab(ctx, b, scope)
    local section = b:Section("Special", 590)
    local w = section._msuf2Width or b.width or 720
    local locked = scope ~= "player"
    W.LabelAt(section, "Private Auras", 24, -42, 180, "GameFontNormal", T.colors.text)
    local controls = {}
    controls[#controls + 1] = BindSwitch(ctx, section, "Enable Private Auras", 24, -78, 220,
        function() return Model.ReadSharedBool("privateAurasEnabled", true) end,
        function(v) Model.WriteSharedBool("privateAurasEnabled", v) end,
        "player", "AURAS3_PRIVATE_ENABLE", true)
    controls[#controls + 1] = BindSwitch(ctx, section, "Show on Player", 24, -112, 180,
        function() return Model.ReadSharedBool("showPrivateAurasPlayer", true) end,
        function(v) Model.WriteSharedBool("showPrivateAurasPlayer", v) end,
        "player", "AURAS3_PRIVATE_SHOW_PLAYER", true)
    controls[#controls + 1] = BindSlider(ctx, section, "Max Private Auras", 24, -164, 0, 12, 1, 260,
        function() return Model.ReadSharedNumber("privateAuraMaxPlayer", 4, 0, 12) end,
        function(v) Model.WriteSharedNumber("privateAuraMaxPlayer", v, 0, 12) end,
        "player", "AURAS3_PRIVATE_MAX")
    controls[#controls + 1] = BindDropdown(ctx, section, "Growth Direction", 330, -164, Model.GrowthValues(), 220,
        function() return tostring(Model.ReadValue("shared", "privateGrowth", "RIGHT") or "RIGHT") end,
        function(v) Model.WriteValue("shared", "privateGrowth", v or "RIGHT") end,
        "player", "AURAS3_PRIVATE_GROWTH")
    local hint = W.Text(section, "", 24, -246, w - 48, T.colors.muted)
    M.AddRefresher(ctx, function()
        locked = CurrentScope() ~= "player"
        W.SetControlsEnabled(controls, not locked)
        hint:SetText(locked and "Private Auras are only configurable for Player." or "Private Aura values are stored in the shared Auras3 profile and only apply to Player.")
    end)

    BuildGroupFrameUtilityControls(ctx, section, 24, -322, w - 48)
end

local function BuildAuraStyle(ctx)
    Model.EnsureDB()
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Aura Style", "Shared rules, blacklists, group-frame custom aura filters, colors and player-only special aura settings.", 72)
    local w = max(320, tonumber(ctx and ctx.width) or 720)
    local chrome = b:Section("Aura Scope", 108)
    W.LabelAt(chrome, "Scope", 18, -20, 80, "GameFontNormalSmall", T.colors.accent)
    BuildScopeTabs(ctx, chrome, 92, -16, min(820, w - 128), function()
        Rebuild(ctx)
    end)
    W.LabelAt(chrome, "Tab", 18, -62, 80, "GameFontNormalSmall", T.colors.accent)
    BuildTabButtons(ctx, chrome, 92, -58, min(680, w - 128))

    local scope = CurrentScope()
    local tab = CurrentTab()
    if IsGroupAuraScope(scope) and tab == "rules" then
        BuildGroupRulesTab(ctx, b)
    elseif IsGroupAuraScope(scope) and tab == "blacklist" then
        BuildGroupBlacklistTab(ctx, b)
    elseif IsGroupAuraScope(scope) and tab == "special" then
        BuildGroupSpecialTab(ctx, b)
    elseif IsGroupAuraScope(scope) and tab == "overview" then
        BuildGroupOverviewTab(ctx, b, scope)
    elseif tab == "rules" then
        BuildRulesTab(ctx, b, scope)
    elseif tab == "blacklist" then
        BuildBlacklistTab(ctx, b, scope)
    elseif tab == "colors" then
        BuildColorsTab(ctx, b, scope)
    elseif tab == "special" then
        BuildSpecialTab(ctx, b, scope)
    else
        BuildOverviewTab(ctx, b, scope)
    end
    ctx:SetContentHeight(abs(b.y) + 42)
end

M.RegisterPage("auras3", { title = "MSUF Aura Style", build = BuildAuraStyle, version = 38 })
