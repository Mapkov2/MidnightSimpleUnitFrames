--- GroupFrames/MSUF_GroupFrames_Additional.lua
--- Extra blocks of a group scope: the party members' targets, group pets,
--- allied boss units and healer mana bars. The first three are small secure
--- buttons outside the group headers; the mana bars are plain rows.
---
--- Protected writes (attributes, unit watches, state drivers, points and the
--- visibility of secure buttons and their holders) only happen out of combat; a
--- request in combat is kept and replayed at PLAYER_REGEN_ENABLED. The mana rows
--- are not protected and follow the roster in combat too.
---
--- Health is painted on two paths: the value path writes the bar values (and the
--- colour only where it follows the value, or when the bar empties or refills);
--- the identity path also writes the name, colours and background, for unit,
--- name, connection and target changes. Compound tokens such as party1target
--- raise no unit events, so their values come from one 0.2 s ticker on the block
--- while it is shown.
local _, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "GroupFrames")
local GF = MSUF.GF
local Client = MSUF.Client
local InCombat = MSUF.Util.InCombat
local floor, min, max = math.floor, math.min, math.max
local UnitHealth, UnitHealthMax, UnitPower, UnitPowerMax = UnitHealth, UnitHealthMax, UnitPower, UnitPowerMax
-- Names read like the engine frames' (UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua):
-- WoW Forever character names and nickname providers apply here too.
local ReadDisplayName = MSUF.UFText.ReadDisplayName
local issecretvalue = _G.issecretvalue or function() return false end
local holders, targetButtons, bossButtons, manaRows = {}, {}, {}, {}
local previewPools = setmetatable({}, {__mode = "k"})
local screenPreviews, previewRequests = {}, {}
local pending, activeKind, refreshQueued = false, nil, false
local rosterRefreshQueued = false
local styleSerial = 1
local events = CreateFrame("Frame")
local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_CONNECTION" }
local BLOCKS = { "pets", "targets", "friendlyBoss", "healerMana" }
GF.ADDITIONAL_BLOCKS = BLOCKS
-- Each block starts at its own spot (centre offset from the screen centre), so
-- two enabled blocks never begin stacked on each other.
local DEFAULT_X = { targets = -250, pets = -250, friendlyBoss = 250, healerMana = 250 }
local DEFAULT_Y = { targets = 150, pets = -150, friendlyBoss = 150, healerMana = -150 }
GF.ADDITIONAL_DEFAULT_X, GF.ADDITIONAL_DEFAULT_Y = DEFAULT_X, DEFAULT_Y
local TARGET_TICK = 0.2
-- Allied boss frames need boss unit tokens, which Classic Era and TBC lack.
local BOSS_UNITS = not (Client and type(Client.SupportsUnit) == "function") or Client.SupportsUnit("boss1") == true
GF.ADDITIONAL_HAS_BOSS_UNITS = BOSS_UNITS
local PARTY_UNITS, PARTY_TARGETS, BOSS_TOKENS, BOSS_DRIVERS = {}, {}, {}, {}
for i = 1, 4 do PARTY_UNITS[i], PARTY_TARGETS[i] = "party" .. i, "party" .. i .. "target" end
for i = 1, 5 do
    BOSS_TOKENS[i] = "boss" .. i
    BOSS_DRIVERS[i] = "[@boss" .. i .. ",help,exists] show; hide"
end

local function Number(conf, key, fallback, low, high)
    return max(low, min(high, tonumber(conf[key]) or fallback))
end
local function CacheColorUnit(button)
    local unit = button.unit
    local colorUnit = unit
    if button._msufAdditionalPrefix == "pets" and type(unit) == "string" and not issecretvalue(unit) then
        if unit == "pet" then colorUnit = "player"
        else colorUnit = unit:gsub("^raidpet(%d+)$", "raid%1"):gsub("^partypet(%d+)$", "party%1") end
    end
    button._msufAdditionalColorUnit = colorUnit
end

local function PaintColors(button, kind, prefix, class, pct, unit, hp, maxHP, event)
    local spec = GF.GetCompiledSpec and GF.GetCompiledSpec(kind)
    local common = MSUF.UFBarTextCommon
    if button.MSUFSpec ~= spec then button._msufHealthGradientCurve, button._msufHealthGradientChannels = nil, nil end
    button.MSUFSpec = spec
    local health = spec and spec.health or {}
    local colorUnit = button._msufAdditionalColorUnit or unit
    local r, g, b = .18, .65, .38
    if prefix == "healerMana" then r, g, b = .15, .35, .8
    elseif unit and common and common.ApplyHealthStatusColor then
        common.ApplyHealthStatusColor(button.Health, button, health.mode == "class" and colorUnit or unit, hp, maxHP, nil, event)
        r, g, b = button.Health:GetStatusBarColor()
    elseif health.mode == "gradient" and common and common.PreviewHealthGradientColor then
        r, g, b = common.PreviewHealthGradientColor(health, pct or .7)
    elseif health.mode == "unified" or health.mode == "custom" or health.mode == "dark" then
        r, g, b = health.r, health.g, health.b
    elseif prefix ~= "friendlyBoss" and class and common and common.ClassColorForToken then r, g, b = common.ClassColorForToken(class)
    elseif common and common.NPCColor then r, g, b = common.NPCColor("friendly") end
    if not unit or prefix == "healerMana" then button.Health:SetStatusBarColor(r, g, b) end
    if not rawget(button, "bg") then
        button.bg = PixelLayoutRegion(button.Health:CreateTexture(nil, "BACKGROUND"))
        button.bg:SetAllPoints()
    end
    local bg = health.background or {}
    local br, bgc, bb = bg.r or .04, bg.g or .04, bg.b or .04
    if health.backgroundColorMode == "match_health" or health.backgroundMatchHealth then br, bgc, bb = r, g, b
    elseif health.backgroundColorMode == "health_gradient" and common then
        if unit and common.GradientColor then br, bgc, bb = common.GradientColor(unit, nil, button, hp, maxHP, event)
        elseif common.PreviewHealthGradientColor then br, bgc, bb = common.PreviewHealthGradientColor(health, pct or .7) end
    elseif health.backgroundClassColor and common then
        if unit and common.ClassColor then br, bgc, bb = common.ClassColor(colorUnit)
        elseif common.ClassColorForToken then br, bgc, bb = common.ClassColorForToken(class) end
    end
    local texture = spec and spec.backgroundTexture
    if texture then
        if button.bg._msufBgTexture ~= texture then
            button.bg:SetTexture(texture)
            button.bg._msufBgTexture = texture
        end
        button.bg:SetVertexColor(br, bgc, bb, bg.a or .95)
    else button.bg:SetColorTexture(br, bgc, bb, bg.a or .95) end
    if unit and type(_G.UnitClass) == "function" then
        local _, token = _G.UnitClass(colorUnit)
        if type(token) == "string" and not issecretvalue(token) then class = token end
    end
    if prefix ~= "healerMana" and GF.ResolveNameColor then button.Name:SetTextColor(GF.ResolveNameColor(kind, class)) end
    -- Bar and background colours that follow the health value need the value path.
    button._msufValueColors = health.mode == "gradient" or health.backgroundColorMode == "health_gradient"
end

-- Value path: bar values, then the colour where it follows the value, or when
-- the bar empties or refills (the status colour of a dead or revived unit).
local function PaintValue(button, event)
    local unit = button.unit
    if not unit then return end
    local hp, maxHP = UnitHealth(unit), button._msufMaxHP
    -- BindHealth seeds the maximum before unit events can run. Never inspect
    -- the cached value: UnitHealthMax can return a secret number.
    if event ~= "UNIT_HEALTH" then
        maxHP = UnitHealthMax(unit)
        button._msufMaxHP = maxHP
        button.Health:SetMinMaxValues(0, maxHP)
    end
    button.Health:SetValue(hp)
    local empty = not issecretvalue(hp) and hp == 0
    if button._msufValueColors or empty ~= (button._msufEmpty == true) then
        button._msufEmpty = empty
        PaintColors(button, button._msufAdditionalKind or "party", button._msufAdditionalPrefix or "pets", nil, nil, unit, hp, maxHP, event)
    end
end
-- Identity path: everything, for a new unit, name, connection or target.
local function PaintIdentity(button, event)
    local unit = button.unit
    if not unit then return end
    local hp, maxHP = UnitHealth(unit), UnitHealthMax(unit)
    button._msufMaxHP = maxHP
    button.Health:SetMinMaxValues(0, maxHP)
    button.Health:SetValue(hp)
    button._msufEmpty = not issecretvalue(hp) and hp == 0
    button.Name:SetText(ReadDisplayName(unit))
    PaintColors(button, button._msufAdditionalKind or "party", button._msufAdditionalPrefix or "pets", nil, nil, unit, hp, maxHP, event or "UNIT_NAME_UPDATE")
end
local function OnUnitEvent(button, event)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then PaintValue(button, event)
    else PaintIdentity(button, event) end
end
-- A compound token (party1target) raises no unit events; the ticker owns it.
local function IsCompound(unit)
    return unit ~= "target" and unit:find("target$") ~= nil
end
local function BindHealth(button, unit)
    button.unit = unit
    button._msufMaxHP = nil
    CacheColorUnit(button)
    local listen = unit ~= nil and not IsCompound(unit)
    for i = 1, #UNIT_EVENTS do
        button:UnregisterEvent(UNIT_EVENTS[i])
        if listen then button:RegisterUnitEvent(UNIT_EVENTS[i], unit) end
    end
    if unit then PaintIdentity(button, "UNIT_NAME_UPDATE") else button.Name:SetText("") end
end
local function HealthAttribute(button, name, unit)
    if name == "unit" then BindHealth(button, unit) end
end
local function HealthShown(button) PaintIdentity(button, "UNIT_NAME_UPDATE") end
local function StyleHealth(button, kind, conf, prefix)
    PixelLayoutRegion(button)
    button._msufAdditionalKind, button._msufAdditionalPrefix = kind, prefix
    CacheColorUnit(button)
    button.Health:SetStatusBarTexture(GF.ResolveBarTexture(kind))
    button.Name:SetFont(GF.ResolveFontPath(kind), Number(conf, prefix .. "TextSize", 11, 7, 32), GF.ResolveFontFlags(kind))
    PaintColors(button, kind, prefix, nil, .7, button.unit, button.unit and UnitHealth(button.unit), button.unit and UnitHealthMax(button.unit),
        "GROUP_ROSTER_UPDATE")
end
-- The XML template names this function as its OnLoad handler. Its regions sit
-- on the health bar under parentKeys; the painters use them from the button.
function GF.AdditionalUnitOnLoad(button)
    local health = button.Health
    button.Name = health and health.Name or button.Name
    if health and health.Background and not rawget(button, "bg") then button.bg = health.Background end
    button:SetScript("OnEvent", OnUnitEvent)
    button:HookScript("OnAttributeChanged", HealthAttribute)
    button:HookScript("OnShow", HealthShown)
    local header = button:GetParent()
    local kind = header._msufAdditionalKind or activeKind or "party"
    StyleHealth(button, kind, GF.GetConf(kind), header._msufAdditionalPrefix or "pets")
    button._msufStyleSerial = styleSerial
    -- Click-cast addons (ClickCastFrames) bind the same way as on the group frames.
    if GF.RegisterClickCastFrame then GF.RegisterClickCastFrame(button) end
end
MSUF.ExportPublic("MSUF_GroupAdditionalUnitOnLoad", GF.AdditionalUnitOnLoad)

local function TickTargets(holder, elapsed)
    local wait = (holder._msufTickWait or 0) - elapsed
    if wait > 0 then
        holder._msufTickWait = wait
        return
    end
    holder._msufTickWait = TARGET_TICK
    for i = 1, 4 do
        local button = targetButtons[i]
        if button and button.unit and button:IsVisible() then PaintValue(button, "UNIT_MAXHEALTH") end
    end
end
local function Holder(key)
    local frame = holders[key]
    if not frame then
        frame = PixelLayoutRegion(CreateFrame("Frame", "MSUF_GroupAdditional_" .. key, UIParent))
        if key == "Targets" then frame:SetScript("OnUpdate", TickTargets) end
        holders[key] = frame
    end
    return frame
end
local function Place(holder, conf, prefix, width, height)
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", UIParent, "CENTER", Number(conf, prefix .. "X", DEFAULT_X[prefix] or 0, -2000, 2000),
        Number(conf, prefix .. "Y", DEFAULT_Y[prefix] or 0, -2000, 2000))
    holder:SetSize(width, height)
end
local function PetLimit(kind, conf, columns)
    local maximum = kind == "party" and 5 or 40
    local cap = floor(Number(conf, "petsMaxCount", 40, 1, maximum))
    local full = floor(cap / columns) * columns
    local remainder = cap - full
    return cap, cap < maximum and full > 0 and remainder > 0, full, remainder
end
local function Geometry(conf, prefix, count)
    local width = Number(conf, prefix .. "Width", 100, 20, 500)
    local height = Number(conf, prefix .. "Height", 24, 10, 200)
    local columns = floor(Number(conf, prefix .. "Columns", 1, 1, 8))
    return width, height, columns, min(columns, count) * (width + 2) - 2, math.ceil(count / columns) * (height + 2) - 2
end
-- Visual-only samples never join a secure header or subscribe to unit events.
function GF.GetAdditionalPreviewSpec(kind, prefix, count, options)
    if prefix ~= "pets" and prefix ~= "targets" and prefix ~= "friendlyBoss" and prefix ~= "healerMana" then return nil end
    if prefix == "friendlyBoss" and not BOSS_UNITS then return nil end
    local conf = GF.GetConf(kind)
    if not conf then return nil end
    if prefix == "targets" then count = conf.targetsIncludePlayer == true and 5 or 4
    elseif prefix == "friendlyBoss" then count = _G.MAX_BOSS_FRAMES or 5
    elseif prefix == "healerMana" then count = kind == "party" and 2 or 3
    else count = kind == "party" and 5 or floor(max(1, min(40, tonumber(count) or 20))) end
    local cap, split
    if prefix == "pets" then
        cap, split = PetLimit(kind, conf, floor(Number(conf, "petsColumns", 1, 1, 8)))
        count = min(count, cap)
    end
    if options and tonumber(options.sampleCount) then count = min(count, max(1, floor(tonumber(options.sampleCount)))) end
    local width, height, columns, totalW, totalH = Geometry(conf, prefix, count)
    if split and not (options and tonumber(options.sampleCount)) then _, _, _, totalW, totalH = Geometry(conf, prefix, cap) end
    if prefix == "healerMana" then columns, totalW, totalH = 1, width, count * (height + 2) - 2 end
    return {
        enabled = conf.enabled == true and conf[prefix .. "Enabled"] == true and (prefix ~= "targets" or kind == "party"),
        kind = kind, prefix = prefix, count = count, width = width, height = height, columns = columns,
        totalWidth = totalW, totalHeight = totalH, spacing = 2,
        point = "CENTER", relativePoint = "CENTER",
        x = Number(conf, prefix .. "X", DEFAULT_X[prefix], -2000, 2000), y = Number(conf, prefix .. "Y", DEFAULT_Y[prefix], -2000, 2000),
        textSize = Number(conf, prefix .. "TextSize", 11, 7, 32),
    }
end
function GF.HideAdditionalPreview(parent, prefix)
    local pools = previewPools[parent]
    if not pools then return end
    for key, holder in pairs(pools) do
        if not prefix or key == prefix then holder:Hide() end
    end
end
function GF.RenderAdditionalPreview(parent, kind, prefix, count, options)
    if not parent then return nil end
    local spec = GF.GetAdditionalPreviewSpec(kind, prefix, count, options)
    if not spec then return nil end
    if InCombat() or not spec.enabled then
        GF.HideAdditionalPreview(parent, prefix)
        return nil, spec
    end
    local pools = previewPools[parent]
    if not pools then
        pools = {}
        previewPools[parent] = pools
    end
    local holder = pools[prefix]
    if not holder then
        holder = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
        holder.buttons = {}
        pools[prefix] = holder
    end
    holder:SetSize(spec.totalWidth, spec.totalHeight)
    if not options or options.position ~= false then
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    end
    local conf = GF.GetConf(kind)
    for i = 1, spec.count do
        local button = holder.buttons[i]
        if not button then
            button = PixelLayoutRegion(CreateFrame("Frame", nil, holder))
            button.Health = PixelLayoutRegion(CreateFrame("StatusBar", nil, button))
            button.Health:SetAllPoints()
            local bg = PixelLayoutRegion(button.Health:CreateTexture(nil, "BACKGROUND"))
            button.bg = bg
            bg:SetAllPoints()
            bg:SetColorTexture(.04, .04, .04, .95)
            button.Name = PixelLayoutRegion(button.Health:CreateFontString(nil, "OVERLAY"))
            button.Name:SetPoint("LEFT", 3, 0)
            button.Name:SetPoint("RIGHT", -3, 0)
            holder.buttons[i] = button
        end
        StyleHealth(button, kind, conf, prefix)
        button:SetSize(spec.width, spec.height)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", holder, "TOPLEFT", ((i - 1) % spec.columns) * (spec.width + 2), -floor((i - 1) / spec.columns) * (spec.height + 2))
        button.Health:SetMinMaxValues(0, 100)
        button.Health:SetValue(80 - (i % 4) * 10)
        PaintColors(button, kind, prefix, "HUNTER", (80 - (i % 4) * 10) / 100)
        if prefix == "healerMana" then
            if not button.Value then
                button.Value = PixelLayoutRegion(button.Health:CreateFontString(nil, "OVERLAY"))
                button.Value:SetPoint("RIGHT", -3, 0)
            end
            local r, g, b = Number(conf, "healerManaTextR", 1, 0, 1), Number(conf, "healerManaTextG", 1, 0, 1), Number(conf, "healerManaTextB", 1, 0, 1)
            button.Name:ClearAllPoints()
            button.Name:SetPoint("LEFT", 3, 0)
            button.Name:SetJustifyH("LEFT")
            button.Name:SetWidth(spec.width * .62)
            button.Name:SetTextColor(r, g, b)
            button.Value:SetFont(GF.ResolveFontPath(kind), spec.textSize, GF.ResolveFontFlags(kind))
            button.Value:SetTextColor(r, g, b)
            button.Value:SetText(8000 - i * 1000)
            button.Value:SetShown(conf.healerManaShowValue ~= false)
            button.Name:SetText((_G.HEALER or "Healer") .. " " .. i)
        else
            button.Name:SetText((prefix == "pets" and (_G.PET or "Pet") or prefix == "friendlyBoss" and (_G.BOSS or "Boss") or (_G.TARGET
                or "Target")) .. " " .. i)
        end
        button:Show()
    end
    for i = spec.count + 1, #holder.buttons do holder.buttons[i]:Hide() end
    holder:Show()
    return holder, spec
end
local function RefreshScreenPreviews()
    for kind, count in pairs(previewRequests) do
        local parent = screenPreviews[kind]
        if not parent then
            parent = PixelLayoutRegion(CreateFrame("Frame", nil, UIParent))
            screenPreviews[kind] = parent
        end
        parent:SetFrameStrata("MEDIUM")
        local liveLevel = max(holders.Pets and holders.Pets:GetFrameLevel() or 0, holders.Targets and holders.Targets:GetFrameLevel() or 0)
        parent:SetFrameLevel(liveLevel + 10)
        parent:Show()
        for b = 1, #BLOCKS do
            local prefix = BLOCKS[b]
            local holder, spec = GF.RenderAdditionalPreview(parent, kind, prefix, count, {position = false})
            if holder then Place(holder, GF.GetConf(kind), prefix, spec.totalWidth, spec.totalHeight) end
        end
    end
end
function GF.GetAdditionalEditPreviewFrame(kind, prefix)
    local parent = screenPreviews[kind]
    local pools = parent and previewPools[parent]
    local holder = pools and pools[prefix]
    return holder and holder:IsShown() and holder or nil
end
-- Samples only: showing or hiding them never touches the secure live blocks.
function GF.ShowAdditionalGroupPreview(kind, count)
    if kind ~= "party" and kind ~= "raid" and kind ~= "mythicraid" then return false end
    if InCombat() then return false end
    previewRequests[kind] = count or (kind == "party" and 5 or 20)
    RefreshScreenPreviews()
    return true
end
function GF.HideAdditionalGroupPreview(kind)
    if previewRequests[kind] == nil then return end
    previewRequests[kind] = nil
    if screenPreviews[kind] then
        GF.HideAdditionalPreview(screenPreviews[kind])
        screenPreviews[kind]:Hide()
    end
end

local function StaticUnit(list, holder, index, unit, bind)
    local button = list[index]
    if not button then
        button = PixelLayoutRegion(CreateFrame("Button", nil, holder, "MSUF_GroupAdditionalUnitTemplate"))
        button:RegisterForClicks("AnyUp")
        button:SetAttribute("type1", "target")
        list[index] = button
    end
    -- The attribute hook binds a changed unit; an unchanged one is bound here.
    if button:GetAttribute("unit") ~= unit then button:SetAttribute("unit", unit)
    elseif bind and button.unit ~= unit then BindHealth(button, unit) end
    return button
end
local function PlaceButton(button, holder, index, width, height, columns)
    local x, y = ((index - 1) % columns) * (width + 2), -floor((index - 1) / columns) * (height + 2)
    if button._msufX == x and button._msufY == y and button._msufW == width and button._msufH == height then return end
    button:SetSize(width, height)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
    button._msufX, button._msufY, button._msufW, button._msufH = x, y, width, height
end
local function Restyle(button, kind, conf, prefix)
    if button._msufStyleSerial == styleSerial and button._msufAdditionalKind == kind then return end
    StyleHealth(button, kind, conf, prefix)
    button._msufStyleSerial = styleSerial
end
local function Watch(button, on)
    if (button._msufWatched == true) == on then return end
    if on then RegisterUnitWatch(button) else UnregisterUnitWatch(button) end
    button._msufWatched = on
end
local function SuspendButtons(list)
    for i = 1, #list do
        local button = list[i]
        Watch(button, false)
        if button._msufDriver then
            UnregisterStateDriver(button, "visibility")
            button._msufDriver = nil
        end
        button:UnregisterAllEvents()
        button._msufIdentityEvent = nil
        button:Hide()
        button.unit = nil
    end
end
local function ApplyTargets(kind, conf, enabled)
    local holder = Holder("Targets")
    holder._msufAdditionalKind, holder._msufAdditionalPrefix = kind, "targets"
    if not enabled or conf.targetsEnabled ~= true or kind ~= "party" or IsInRaid() then
        SuspendButtons(targetButtons)
        holder:Hide()
        return
    end
    local includePlayer = conf.targetsIncludePlayer == true
    local count = includePlayer and 5 or 4
    local width, height, columns, totalW, totalH = Geometry(conf, "targets", count)
    Place(holder, conf, "targets", totalW, totalH)
    for i = 1, 5 do
        local button = StaticUnit(targetButtons, holder, i, i == 5 and "target" or PARTY_TARGETS[i], i < 5 or includePlayer)
        Restyle(button, kind, conf, "targets")
        PlaceButton(button, holder, i, width, height, columns)
        if i < 5 then
            if button._msufIdentityEvent ~= "UNIT_TARGET" then
                button:RegisterUnitEvent("UNIT_TARGET", PARTY_UNITS[i])
                button._msufIdentityEvent = "UNIT_TARGET"
            end
            Watch(button, true)
        elseif includePlayer then
            if button._msufIdentityEvent ~= "PLAYER_TARGET_CHANGED" then
                button:RegisterEvent("PLAYER_TARGET_CHANGED")
                button._msufIdentityEvent = "PLAYER_TARGET_CHANGED"
            end
            Watch(button, true)
        else
            -- An excluded own-target slot listens to nothing at all.
            Watch(button, false)
            button:UnregisterEvent("PLAYER_TARGET_CHANGED")
            button._msufIdentityEvent = nil
            if button:IsShown() then button:Hide() end
            if button.unit then BindHealth(button, nil) end
        end
    end
    holder:Show()
end
local function PetHeader(key, name)
    local header = holders[key]
    if not header then
        header = PixelLayoutRegion(CreateFrame("Frame", name, UIParent, "SecureGroupPetHeaderTemplate"))
        holders[key] = header
    end
    return header
end
local CHILD_KEYS = {}
for i = 1, 40 do CHILD_KEYS[i] = "child" .. i end
local function ClearPetHeader(header)
    if not header then return end
    header:Hide()
    for i = 1, 40 do
        local child = header:GetAttribute(CHILD_KEYS[i])
        if child then
            child:UnregisterAllEvents()
            child.unit = nil
            child._msufAdditionalColorUnit = nil
        end
    end
end
local PET_ATTRIBUTES = { "template", "templateType", "showRaid", "showParty", "showPlayer", "showSolo", "sortMethod",
    "startingIndex", "point", "xOffset", "yOffset", "columnAnchorPoint", "columnSpacing", "unitsPerColumn", "maxColumns",
    "initialConfigFunction" }
local wanted = {}
-- startingIndex addresses the already filtered/sorted pet list. A second native
-- header owns only the partial final row; neither header needs visibility hooks.
-- Attributes are written only when they change, inside one _ignore window, so a
-- roster or settings pass that changes nothing leaves the header alone.
-- SecureGroupPetHeader_OnAttributeChanged returns for every write in that window
-- and for the closing write too, so one trailing write outside it runs the single
-- update a shown header needs (the main headers' layout nonce).
local function ConfigurePetHeader(header, kind, conf, width, height, units, rows, start)
    header._msufAdditionalKind, header._msufAdditionalPrefix = kind, "pets"
    wanted.template, wanted.templateType = "MSUF_GroupAdditionalUnitTemplate", "Button"
    wanted.showRaid, wanted.showParty, wanted.showPlayer = IsInRaid(), kind == "party", true
    wanted.showSolo, wanted.sortMethod, wanted.startingIndex = conf.showSolo == true, "INDEX", start
    wanted.point, wanted.xOffset, wanted.yOffset = "LEFT", 2, 0
    wanted.columnAnchorPoint, wanted.columnSpacing = "TOP", 2
    wanted.unitsPerColumn, wanted.maxColumns = units, rows
    wanted.initialConfigFunction = ("self:SetWidth(%d); self:SetHeight(%d); self:SetAttribute('type1','target')"):format(width, height)
    local cache = header._msufAttributes
    if not cache then
        cache = {}
        header._msufAttributes = cache
    end
    local changed = false
    for i = 1, #PET_ATTRIBUTES do
        local key = PET_ATTRIBUTES[i]
        if cache[key] ~= wanted[key] then
            if not changed then
                header:SetAttribute("_ignore", true)
                changed = true
            end
            header:SetAttribute(key, wanted[key])
            cache[key] = wanted[key]
        end
    end
    if changed then
        header:SetAttribute("_ignore", nil)
        header:SetAttribute("_msufLayoutNonce", (header:GetAttribute("_msufLayoutNonce") or 0) + 1)
    end
    for i = 1, 40 do
        local child = header:GetAttribute(CHILD_KEYS[i])
        if not child then break end
        if child._msufW ~= width or child._msufH ~= height then
            child:SetSize(width, height)
            child._msufW, child._msufH = width, height
        end
        Restyle(child, kind, conf, "pets")
        local unit = child:GetAttribute("unit")
        if child.unit ~= unit then BindHealth(child, unit) end
    end
    if not header:IsShown() then header:Show() end
end
local function ApplyPets(kind, conf, enabled)
    if not enabled or conf.petsEnabled ~= true then
        ClearPetHeader(holders.Pets)
        ClearPetHeader(holders.PetsRest)
        if holders.PetsBlock then holders.PetsBlock:Hide() end
        return
    end
    local width, height, columns = Geometry(conf, "pets", 1)
    local cap, split, full, remainder = PetLimit(kind, conf, columns)
    -- One fixed block sized for the whole cap; the header grows from its top
    -- left corner, so a pet summoned or lost never re-centres the column.
    local block = Holder("PetsBlock")
    local _, _, _, totalW, totalH = Geometry(conf, "pets", cap)
    Place(block, conf, "pets", totalW, totalH)
    block:Show()
    local header = PetHeader("Pets", "MSUF_GroupAdditional_Pets")
    if header._msufAnchor ~= block then
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
        header._msufAnchor = block
    end
    if split then
        ConfigurePetHeader(header, kind, conf, width, height, columns, full / columns, 1)
        local rest = PetHeader("PetsRest", "MSUF_GroupAdditional_PetsRest")
        if rest._msufAnchor ~= header then
            rest:ClearAllPoints()
            rest:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
            rest._msufAnchor = header
        end
        ConfigurePetHeader(rest, kind, conf, width, height, remainder, 1, full + 1)
    else
        ClearPetHeader(holders.PetsRest)
        local units = min(columns, cap)
        ConfigurePetHeader(header, kind, conf, width, height, units, math.ceil(cap / units), 1)
    end
end
-- A boss token can pass to another friendly NPC while its button stays shown:
-- no OnShow and no name event repaint it then. Blizzard's boss frames run a
-- full Update for both cases (TargetFrame.lua OnEvent: INSTANCE_ENCOUNTER_
-- ENGAGE_UNIT for every boss frame, UNIT_TARGETABLE_CHANGED for its own unit),
-- so the holder listens while the block is on and repaints the identity of
-- each shown button. Unit tokens are compared only when readable.
local BOSS_IDENTITY_EVENTS = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_TARGETABLE_CHANGED" }
local function RepaintBosses(_, event, unit)
    local targetable = event == "UNIT_TARGETABLE_CHANGED"
    if targetable and issecretvalue(unit) then return end
    for i = 1, #bossButtons do
        local button = bossButtons[i]
        if button.unit and button:IsShown() and (not targetable or button.unit == unit) then PaintIdentity(button, event) end
    end
end
local function ListenBossIdentity(holder, on)
    if (holder._msufIdentityEvents == true) == on then return end
    holder._msufIdentityEvents = on
    if not on then
        holder:UnregisterAllEvents()
        return
    end
    holder:SetScript("OnEvent", RepaintBosses)
    -- No client facts (a harness) is a client with the events, as BOSS_UNITS.
    local supports = Client and Client.SupportsEvent
    for i = 1, #BOSS_IDENTITY_EVENTS do
        local event = BOSS_IDENTITY_EVENTS[i]
        if not supports or supports(event) then holder:RegisterEvent(event) end
    end
end
local function ApplyBosses(kind, conf, enabled)
    local holder = Holder("FriendlyBosses")
    holder._msufAdditionalKind, holder._msufAdditionalPrefix = kind, "friendlyBoss"
    local healer = GF.GetUnitGroupRole("player") == "HEALER"
    if not BOSS_UNITS or not enabled or conf.friendlyBossEnabled ~= true or (conf.friendlyBossHealerOnly ~= false and not healer) then
        SuspendButtons(bossButtons)
        ListenBossIdentity(holder, false)
        holder:Hide()
        return
    end
    ListenBossIdentity(holder, true)
    local count = min(5, _G.MAX_BOSS_FRAMES or 5)
    local width, height, columns, totalW, totalH = Geometry(conf, "friendlyBoss", count)
    Place(holder, conf, "friendlyBoss", totalW, totalH)
    for i = 1, count do
        local button = StaticUnit(bossButtons, holder, i, BOSS_TOKENS[i], true)
        Restyle(button, kind, conf, "friendlyBoss")
        PlaceButton(button, holder, i, width, height, columns)
        if button._msufDriver ~= BOSS_DRIVERS[i] then
            RegisterStateDriver(button, "visibility", BOSS_DRIVERS[i])
            button._msufDriver = BOSS_DRIVERS[i]
        end
    end
    holder:Show()
end
-- The value path: mana changes many times a second on a healer, the maximum
-- only with UNIT_MAXPOWER and a new unit (PaintManaIdentity sets it there).
local function UpdateManaValue(row)
    local unit = row.unit
    if not unit then return end
    local mana = UnitPower(unit, 0)
    row.bar:SetValue(mana)
    row.value:SetText(mana)
end
local function UpdateMana(row, event, _, powerType)
    if event == "UNIT_NAME_UPDATE" then
        if row.unit then row.name:SetText(ReadDisplayName(row.unit)) end
        return
    end
    if powerType and powerType ~= "MANA" then return end
    if event == "UNIT_MAXPOWER" and row.unit then row.bar:SetMinMaxValues(0, UnitPowerMax(row.unit, 0)) end
    UpdateManaValue(row)
end
local function ManaRow(holder, index)
    local row = manaRows[index]
    if row then return row end
    row = PixelLayoutRegion(CreateFrame("Frame", nil, holder))
    row.bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, row))
    row.bar:SetAllPoints()
    row.bar:SetStatusBarColor(.15, .35, .8)
    row.name = PixelLayoutRegion(row.bar:CreateFontString(nil, "OVERLAY"))
    row.name:SetPoint("LEFT", 3, 0)
    row.name:SetJustifyH("LEFT")
    row.value = PixelLayoutRegion(row.bar:CreateFontString(nil, "OVERLAY"))
    row.value:SetPoint("RIGHT", -3, 0)
    row:SetScript("OnEvent", UpdateMana)
    manaRows[index] = row
    return row
end
-- Plain frames: this also runs in combat, so a roster change reshuffling raidN
-- tokens never leaves a row showing someone else's mana.
local RAID_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
-- A row listens to its own unit; rebinding happens only when the unit changes.
local function PaintManaIdentity(row)
    row.name:SetText(ReadDisplayName(row.unit))
    row.bar:SetMinMaxValues(0, UnitPowerMax(row.unit, 0))
    UpdateManaValue(row)
end
local function BindManaRow(row, unit)
    if row.unit == unit then return false end
    row:UnregisterAllEvents()
    row.unit = unit
    if unit then
        row:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
        row:RegisterUnitEvent("UNIT_MAXPOWER", unit)
        row:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
        PaintManaIdentity(row)
    end
    return true
end
local function ApplyMana(kind, conf, enabled, refreshIdentity)
    local holder = Holder("HealerMana")
    local rows = 0
    if enabled and conf.healerManaEnabled == true then
        local raid, count = IsInRaid(), GetNumGroupMembers()
        if count == 0 then count = 1 end
        local width, height = Geometry(conf, "healerMana", 1)
        for i = 1, count do
            local unit = raid and RAID_UNITS[i] or (i == count and "player" or PARTY_UNITS[i])
            if unit and GF.GetUnitGroupRole(unit) == "HEALER" then
                rows = rows + 1
                local row = ManaRow(holder, rows)
                -- Style before binding: binding writes the name and value, and a
                -- new row's font strings have no font until this sets one.
                if row._msufStyleSerial ~= styleSerial or row._msufKind ~= kind then
                    local font, size, flags = GF.ResolveFontPath(kind), Number(conf, "healerManaTextSize", 11, 7, 32), GF.ResolveFontFlags(kind)
                    local r, g, b = Number(conf, "healerManaTextR", 1, 0, 1), Number(conf, "healerManaTextG", 1, 0, 1), Number(conf, "healerManaTextB", 1, 0, 1)
                    row.bar:SetStatusBarTexture(GF.ResolveBarTexture(kind))
                    row.name:SetFont(font, size, flags)
                    row.value:SetFont(font, size, flags)
                    row.name:SetTextColor(r, g, b)
                    row.value:SetTextColor(r, g, b)
                    row.value:SetShown(conf.healerManaShowValue ~= false)
                    row._msufStyleSerial, row._msufKind = styleSerial, kind
                end
                local rebound = BindManaRow(row, unit)
                if refreshIdentity and not rebound then PaintManaIdentity(row) end
                local y = -(rows - 1) * (height + 2)
                if row._msufW ~= width or row._msufH ~= height or row._msufY ~= y then
                    row:SetSize(width, height)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
                    row.name:SetWidth(width * .62)
                    row._msufW, row._msufH, row._msufY = width, height, y
                end
                if not row:IsShown() then row:Show() end
            end
        end
        if rows > 0 then Place(holder, conf, "healerMana", width, max(1, rows * (height + 2) - 2)) end
    end
    for i = rows + 1, #manaRows do
        local row = manaRows[i]
        BindManaRow(row, nil)
        if row:IsShown() then row:Hide() end
    end
    holder:SetShown(rows > 0)
end
-- A name refresh (WoW Forever character names, the nickname providers) repaints
-- the group frames through GF.RefreshGroupNames, so the extra blocks repaint
-- their names with it. Names only, out of combat: both callers refuse combat.
local function RefreshButtonNames(list)
    for i = 1, #list do
        local button = list[i]
        if button.unit then button.Name:SetText(ReadDisplayName(button.unit)) end
    end
end
local function RefreshPetNames(header)
    if not header then return end
    for i = 1, 40 do
        local child = header:GetAttribute(CHILD_KEYS[i])
        if not child then break end
        if child.unit then child.Name:SetText(ReadDisplayName(child.unit)) end
    end
end
local RefreshEngineGroupNames = GF.RefreshGroupNames
function GF.RefreshGroupNames(unit)
    RefreshButtonNames(targetButtons)
    RefreshButtonNames(bossButtons)
    RefreshPetNames(holders.Pets)
    RefreshPetNames(holders.PetsRest)
    for i = 1, #manaRows do
        local row = manaRows[i]
        if row.unit then row.name:SetText(ReadDisplayName(row.unit)) end
    end
    return RefreshEngineGroupNames(unit)
end
function GF.RefreshAdditionalGroups(refreshIdentity)
    local combat = InCombat()
    if not combat then GF.EnsureDB() end
    local kind = GF.GetLiveGroupKind() or "party"
    local conf = GF.GetConf(kind)
    -- The same rule as the group runtime: a scope is on only when enabled is true.
    local enabled = conf.enabled == true and (IsInGroup() or conf.showSolo == true)
    ApplyMana(kind, conf, enabled, refreshIdentity)
    if combat then
        pending = true
        return
    end
    pending = false
    activeKind = kind
    -- Keep protected live holders and unit watches ready for combat. Visual-only
    -- samples overlay them OOC and can disappear safely at combat entry.
    ApplyTargets(kind, conf, enabled)
    ApplyPets(kind, conf, enabled)
    RefreshScreenPreviews()
    ApplyBosses(kind, conf, enabled)
end
-- Roster storms and settings changes fold into one pass on the next frame.
local function RunQueuedRefresh()
    refreshQueued = false
    local refreshIdentity = rosterRefreshQueued
    rosterRefreshQueued = false
    GF.RefreshAdditionalGroups(refreshIdentity)
end
local function RequestRefresh(refreshIdentity)
    if refreshIdentity then rosterRefreshQueued = true end
    if refreshQueued then return end
    refreshQueued = true
    local timer = _G.C_Timer
    if timer and timer.After then timer.After(0, RunQueuedRefresh) else RunQueuedRefresh() end
end
GF.RequestAdditionalGroupsRefresh = RequestRefresh
local function OnEvent(_, event)
    InCombat(event)
    if event == "PLAYER_REGEN_DISABLED" then
        for parent in pairs(previewPools) do GF.HideAdditionalPreview(parent) end
        pending = true
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then GF.RefreshAdditionalGroups() end
        return
    end
    RequestRefresh(event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD")
end
events:SetScript("OnEvent", OnEvent)
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
-- Settings and rebuilds restyle every button once on the next pass.
GF.RegisterRuntimeObserver("additional-groups", function()
    styleSerial = styleSerial + 1
    RequestRefresh()
end)
