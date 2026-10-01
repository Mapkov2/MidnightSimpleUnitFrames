local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- GroupFrames/MSUF_GroupFrames_DB_Textures.lua
--- Group-frame textures: highlight and outline values, bar and border
--- textures, and the status icon packs (built-in, add-on, SharedMedia).
--- Split by cohesion from MSUF_GroupFrames_DB.lua (2026-10-01). Loads right
--- after it (UFCore_Group.xml and the Classic GroupFrames.xml manifests) and
--- shares the one MSUF.GF table; see that file for the module's API surface.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

MSUF.GF = MSUF.GF or {}
local GF = MSUF.GF
local ExportPublic = MSUF.ExportPublic

local math_floor = math.floor
local tonumber = tonumber
local tostring = tostring
local type = type
local pairs = pairs
local ipairs = ipairs

--- Resolve a unified highlight value with scope override support.
--- GF-local (gf_party/gf_raid) can override general.hl* keys via hlOverride=true.
--- Falls through to MSUF_DB.general.hl* baseline.
local _HL_OUTLINE_MODE_KEYS = {
    hlAggroEnabled  = "aggroOutlineMode",
    hlDispelEnabled = "dispelOutlineMode",
}

local function OutlineModeToEnabled(mode)
    if mode == nil then return nil end
    if mode == true or mode == false then return mode end
    local n = tonumber(mode)
    if n ~= nil then return n == 1 end
    return nil
end

function GF.GetHighlightVal(kind, key)
    local conf = GF.GetConf(kind)
    local modeKey = _HL_OUTLINE_MODE_KEYS[key]
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if conf.hlOverride then
        if modeKey then
            local enabled = OutlineModeToEnabled(conf[modeKey])
            if enabled ~= nil then return enabled end
        end
        if conf[key] ~= nil then
            if modeKey then
                local enabled = OutlineModeToEnabled(conf[key])
                if enabled ~= nil then return enabled end
            end
            return conf[key]
        end
    end
    if gen then
        if modeKey then
            local enabled = OutlineModeToEnabled(gen[modeKey])
            if enabled ~= nil then return enabled end
        end
        if gen[key] ~= nil then
            if modeKey then
                local enabled = OutlineModeToEnabled(gen[key])
                if enabled ~= nil then return enabled end
            end
            return gen[key]
        end
    end
    return nil
end
-- Public DB-config bridge (stable ABI, see MSUF_GroupFrames_DB.lua).
ExportPublic("MSUF_GF_GetHighlightVal", GF.GetHighlightVal)

--- Resolve outline thickness with scope override support.
--- GF-local (gf_party/gf_raid) can override bars.barOutlineThickness via hlOverride=true.
function GF.GetBarOutlineThickness(kind)
    local conf = GF.GetConf(kind)
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local raw = nil
    if conf and conf.hlOverride and conf.barOutlineThickness ~= nil then
        raw = conf.barOutlineThickness
    elseif bars then
        raw = bars.barOutlineThickness
    end
    local t = tonumber(raw)
    if type(t) ~= "number" then t = 2 end
    t = math_floor(t + 0.5)
    if t < 0 then t = 0 elseif t > 8 then t = 8 end
    return t
end

--- The statusbar texture exports of Castbars/MSUF_Castbars_Core.lua, which loads
--- before the group DB. Resolved once, on first use, so a fixture that never
--- resolves a texture need not stub them.
local ResolveTextureKey, GetBarTexture, GetBarBackgroundTexture

local function TextureExports()
    if not ResolveTextureKey then
        local file = "GroupFrames/MSUF_GroupFrames_DB_Textures.lua"
        ResolveTextureKey = MSUF.Require("MSUF_ResolveStatusbarTextureKey", file)
        GetBarTexture = MSUF.Require("MSUF_GetBarTexture", file)
        GetBarBackgroundTexture = MSUF.Require("MSUF_GetBarBackgroundTexture", file)
    end
    return ResolveTextureKey, GetBarTexture, GetBarBackgroundTexture
end

--- Resolve bar texture path (falls through to global MSUF bar texture)
function GF.ResolveBarTexture(kind)
    local conf = GF.GetConf(kind)
    local key = conf and conf.hlOverride == true and conf.barTexture or nil
    local resolve, barTexture = TextureExports()
    if key and key ~= "" then return resolve(key) end
    return barTexture()
end

--- Resolve bar background texture path
function GF.ResolveBarBgTexture(kind)
    local conf = GF.GetConf(kind)
    local key
    if conf and conf.hlOverride == true then
        key = conf.barBackgroundTexture
        if key == nil then key = conf.barBgTexture end
    end
    local resolve, _, backgroundTexture = TextureExports()
    if key ~= nil then
        if key == "" then return GF.ResolveBarTexture(kind) end
        return resolve(key)
    end
    return backgroundTexture()
end

--- Resolve highlight border edge texture (LSM key - path, nil - WHITE8x8)
function GF.ResolveHighlightTexture(lsmKey)
    if not lsmKey or lsmKey == "" then return "Interface\\Buttons\\WHITE8x8" end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local p = LSM:Fetch("border", lsmKey, true)
        if p then return p end
    end
    return "Interface\\Buttons\\WHITE8x8"
end

---
--- Icon style resolver
---
local MEDIA_PREFIX = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Icons\\"

local BLIZZARD_ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local BLIZZARD_ROLE_COORDS = {
    TANK    = { 0,    19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64,  20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}
local BLIZZARD_LEADER_TEX = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local BLIZZARD_ASSIST_TEX = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
local BLIZZARD_RAID_MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local BLIZZARD_READY_TEXTURES = {
    ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local BLIZZARD_SUMMON_TEXTURES = {
    pending = "Interface\\RaidFrame\\Raid-Icon-SummonPending",
    accepted = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted",
    declined = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined",
}
local BLIZZARD_REZ_TEXTURE = "Interface\\RaidFrame\\Raid-Icon-Rez"
local BLIZZARD_PHASE_TEXTURE = "Interface\\TargetingFrame\\UI-PhasingIcon"
local BLIZZARD_STATE_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"
local BLIZZARD_PVP_TEXTURES = {
    Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
    Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
    FFA = "Interface\\TargetingFrame\\UI-PVP-Alliance",
}

local CUSTOM_STYLES = {
    CLASSIC       = "Classic",
    MIDNIGHT      = "Midnight",
    MSUF_ROLES    = "MSUFRoles",
    UXPRO         = "UXPro",
    GLOSSY_ORBS   = "GlossyOrbs",
    NEON_OUTLINE  = "NeonOutline",
    RING_SYMBOLS  = "RingSymbols",
    GLASS_PANELS  = "GlassPanels",
    DARK_EMBOSS   = "DarkEmboss",
    DOTS          = "Dots",
    SHAPES        = "Shapes",
    DIAMONDS      = "Diamonds",
    SQUARES       = "Squares",
}

local CUSTOM_STYLES_NO_MIDNIGHT_SUFFIX = {
    CLASSIC    = true,
    MIDNIGHT   = true,
    MSUF_ROLES = true,
}

local ROLE_ONLY_CUSTOM_STYLES = {
    MSUF_ROLES = true,
}

local ROLE_ONLY_ICON_FILES = {
    tank = true,
    healer = true,
    dps = true,
}

local STANDALONE_STATUS_ICON_FOLDERS = {
    { label = "Custom Glyphs", folder = "CustomGlyphs" },
    { label = "Custom Badges", folder = "CustomBadges" },
}

local ROLE_MAP = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local RAID_MARKER_FILES = {
    [1] = "raid_star",
    [2] = "raid_circle",
    [3] = "raid_diamond",
    [4] = "raid_triangle",
    [5] = "raid_moon",
    [6] = "raid_square",
    [7] = "raid_cross",
    [8] = "raid_skull",
}
local READY_FILES = {
    ready = "ready_ready",
    notready = "ready_notready",
    waiting = "ready_waiting",
}
local SUMMON_FILES = {
    [1] = "summon_pending",
    [2] = "summon_accepted",
    [3] = "summon_declined",
    pending = "summon_pending",
    accepted = "summon_accepted",
    declined = "summon_declined",
}
local PVP_FILES = {
    Alliance = "pvp_alliance",
    Horde = "pvp_horde",
    FFA = "pvp_ffa",
    alliance = "pvp_alliance",
    horde = "pvp_horde",
    ffa = "pvp_ffa",
}
local SIMPLE_STATUS_ICON_FILES = {
    incomingRes = "resurrect",
    resurrect = "resurrect",
    pvp = "pvp_alliance",
    phase = "phase",
    combat = "combat",
    resting = "resting",
    elite = "elite_elite",
    rare = "elite_rare",
    boss = "elite_boss",
}
local ADDON_ICON_STYLE_PREFIX = "ADDON:"
local REGISTERED_ICON_STYLE_PREFIX = "REGISTERED:"
local LSM_ICON_STYLE_PREFIX = "LSM:"
local ROLE_ICON_FILES = { "tank", "healer", "dps", "leader", "assist" }
local NON_ROLE_ICON_FILES = {
    "raid_star", "raid_circle", "raid_diamond", "raid_triangle",
    "raid_moon", "raid_square", "raid_cross", "raid_skull",
    "ready_ready", "ready_notready", "ready_waiting",
    "summon_pending", "summon_accepted", "summon_declined",
    "resurrect", "pvp_alliance", "pvp_horde", "pvp_ffa", "phase",
    "combat", "resting", "elite_elite", "elite_rare", "elite_boss",
}
local _externalIconPacks
local _externalIconPackOrder
local _registeredIconPacks = {}
local _statusIconAssetItemsCache = {}
local _textureProbeHost
local _textureProbe
local _textureProbeReliable
local _texturePathExistsCache = {}

local function NormalizeIconFolderPath(path)
    if type(path) ~= "string" or path == "" then return nil end
    path = path:gsub("/", "\\"):gsub("\\+$", "")
    return path ~= "" and path or nil
end

local function TextureProbeRaw(path)
    if type(path) ~= "string" or path == "" or type(CreateFrame) ~= "function" then return false end
    if not _textureProbe then
        _textureProbeHost = CreateFrame("Frame")
        if _textureProbeHost.Hide then _textureProbeHost:Hide() end
        _textureProbe = PixelLayoutRegion(_textureProbeHost:CreateTexture(nil, "ARTWORK"), true)
    end
    if not (_textureProbe and _textureProbe.SetTexture) then return false end
    _textureProbe:SetTexture(nil)
    local applied = _textureProbe:SetTexture(path)
    if applied == false then
        _textureProbe:SetTexture(nil)
        return false
    end
    if _textureProbe.GetTexture then
        local tex = _textureProbe:GetTexture()
        _textureProbe:SetTexture(nil)
        return tex ~= nil and tex ~= ""
    end
    _textureProbe:SetTexture(nil)
    return applied == true
end

local function TextureProbeReliable()
    if _textureProbeReliable ~= nil then return _textureProbeReliable end
    _textureProbeReliable = TextureProbeRaw("Interface\\AddOns\\MidnightSimpleUnitFrames\\__msuf_missing_texture_probe__") == false
    return _textureProbeReliable
end

local function TexturePathExists(path)
    path = NormalizeIconFolderPath(path)
    if not path then return false end
    if _texturePathExistsCache[path] ~= nil then return _texturePathExistsCache[path] end
    local exists = TextureProbeReliable() and (TextureProbeRaw(path) or TextureProbeRaw(path .. ".tga") or TextureProbeRaw(path .. ".blp"))
    _texturePathExistsCache[path] = exists and true or false
    return _texturePathExistsCache[path]
end

local function IconFolderLooksComplete(folder)
    folder = NormalizeIconFolderPath(folder)
    if not folder then return false end
    local roleComplete = true
    for _, file in ipairs(ROLE_ICON_FILES) do
        if not TexturePathExists(folder .. "\\" .. file) then
            roleComplete = false
            break
        end
    end
    if roleComplete then return true end
    local statusComplete = true
    for _, file in ipairs(NON_ROLE_ICON_FILES) do
        if not TexturePathExists(folder .. "\\" .. file) then
            statusComplete = false
            break
        end
    end
    return statusComplete
end

local function AddExternalIconPack(key, label, folder, noMidnightSuffix, hasMidnightSuffix, files)
    folder = NormalizeIconFolderPath(folder)
    local hasFiles = type(files) == "table" and next(files) ~= nil
    if type(key) ~= "string" or key == "" or (not folder and not hasFiles) then return end
    if _externalIconPacks[key] then return end
    local pack = {
        key = key,
        label = (type(label) == "string" and label ~= "" and label) or key,
        folder = folder,
        files = files,
        noMidnightSuffix = noMidnightSuffix == true,
        hasMidnightSuffix = hasMidnightSuffix == true,
    }
    _externalIconPacks[key] = pack
    _externalIconPackOrder[#_externalIconPackOrder + 1] = pack
end

local function NormalizeStatusIconFileKey(file)
    if type(file) ~= "string" or file == "" then return nil end
    file = file:gsub("\\", "/"):match("([^/]+)$") or file
    file = file:gsub("%.[%a%d]+$", "")
    file = file:gsub("%s+", "_"):gsub("[^%w_%-]", "_"):lower()
    return file ~= "" and file or nil
end

local LSM = _G.MSUF_GetSharedMedia

local function ParseLSMStatusIconName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local a, b = name:match("^MSUF%s+Status%s+Icon%s+Pack:%s*(.-)%s*:%s*([%w_%-%.%s]+)%s*$")
    if a and b then return a, NormalizeStatusIconFileKey(b) end
    a, b = name:match("^MSUF%s+StatusIcon:%s*(.-)%s*:%s*([%w_%-%.%s]+)%s*$")
    if a and b then return a, NormalizeStatusIconFileKey(b) end
    a, b = name:match("^MSUF:StatusIcon:(.-):([%w_%-%.%s]+)%s*$")
    if a and b then return a, NormalizeStatusIconFileKey(b) end
    return nil
end

local function AddSharedMediaIconPacks()
    local lsm = LSM()
    if not (lsm and type(lsm.HashTable) == "function") then return end
    local packs, labels = {}, {}
    for _, mediaType in ipairs({ "msuf_statusicon", "background", "statusbar" }) do
        local hash = lsm:HashTable(mediaType)
        if type(hash) == "table" then
            for name, path in pairs(hash) do
                local label, file = ParseLSMStatusIconName(name)
                if label and file and type(path) == "string" and path ~= "" then
                    local key = label:gsub("%s+", "_"):gsub("[^%w_%-]", "_")
                    if key ~= "" then
                        packs[key] = packs[key] or {}
                        packs[key][file] = path
                        labels[key] = label
                    end
                end
            end
        end
    end
    local keys = {}
    for key in pairs(packs) do keys[#keys + 1] = key end
    table.sort(keys)
    for i = 1, #keys do
        local key = keys[i]
        local files = packs[key]
        AddExternalIconPack(LSM_ICON_STYLE_PREFIX .. key, labels[key], nil, false, true, files)
    end
end

local function GetAddonInfoName(index)
    local c = _G.C_AddOns
    if c and type(c.GetAddOnInfo) == "function" then
        local name, title = c.GetAddOnInfo(index)
        return name, title
    end
    if type(_G.GetAddOnInfo) == "function" then
        local name, title = _G.GetAddOnInfo(index)
        return name, title
    end
end

local function GetAddonCount()
    local c = _G.C_AddOns
    if c and type(c.GetNumAddOns) == "function" then return tonumber(c.GetNumAddOns()) or 0 end
    if type(_G.GetNumAddOns) == "function" then return tonumber(_G.GetNumAddOns()) or 0 end
    return 0
end

local function GetAddonMetadata(addonName, field)
    local c = _G.C_AddOns
    if c and type(c.GetAddOnMetadata) == "function" then
        return c.GetAddOnMetadata(addonName, field)
    end
    if type(_G.GetAddOnMetadata) == "function" then return _G.GetAddOnMetadata(addonName, field) end
end

local function IsTruthyMetadata(value)
    if value == true then return true end
    if type(value) ~= "string" then return false end
    value = value:lower()
    return value == "1" or value == "true" or value == "yes" or value == "y"
end

local function ExternalIconPackByKey(style)
    if type(style) ~= "string" or style == "" then return nil end
    GF.RefreshExternalStatusIconPacks()
    return _externalIconPacks and _externalIconPacks[style]
end

function GF.RefreshExternalStatusIconPacks(force)
    if _externalIconPacks and not force then return _externalIconPacks end
    _externalIconPacks = {}
    _externalIconPackOrder = {}
    _statusIconAssetItemsCache = {}

    for key, pack in pairs(_registeredIconPacks) do
        AddExternalIconPack(key, pack.label, pack.folder, pack.noMidnightSuffix, pack.hasMidnightSuffix)
    end

    AddSharedMediaIconPacks()

    local count = GetAddonCount()
    for i = 1, count do
        local addonName, title = GetAddonInfoName(i)
        if type(addonName) == "string" and addonName ~= "" then
            local marked = IsTruthyMetadata(GetAddonMetadata(addonName, "X-MSUF-StatusIconPack"))
                or IsTruthyMetadata(GetAddonMetadata(addonName, "X-MSUF-IconPack"))
            local metadataFolder = NormalizeIconFolderPath(GetAddonMetadata(addonName, "X-MSUF-IconFolder"))
            local label = GetAddonMetadata(addonName, "X-MSUF-IconPack-Name") or title or addonName
            local noMidnight = IsTruthyMetadata(GetAddonMetadata(addonName, "X-MSUF-NoMidnightSuffix"))
            local hasMidnight = IsTruthyMetadata(GetAddonMetadata(addonName, "X-MSUF-HasMidnightSuffix"))
            local iconFolders = metadataFolder and { metadataFolder } or { "Media\\Icons", "Icons" }
            local fallbackFolder
            for _, iconFolder in ipairs(iconFolders) do
                local folder = "Interface\\AddOns\\" .. addonName .. "\\" .. iconFolder
                if not fallbackFolder then fallbackFolder = folder end
                if IconFolderLooksComplete(folder) then
                    AddExternalIconPack(ADDON_ICON_STYLE_PREFIX .. addonName, label, folder, noMidnight, hasMidnight)
                    fallbackFolder = nil
                    break
                end
            end
            if marked and fallbackFolder then
                AddExternalIconPack(ADDON_ICON_STYLE_PREFIX .. addonName, label, fallbackFolder, noMidnight, hasMidnight)
            end
        end
    end

    return _externalIconPacks
end

function GF.RegisterStatusIconPack(key, label, folder, opts)
    key = (type(key) == "string" and key ~= "" and key) or nil
    folder = NormalizeIconFolderPath(folder)
    if not (key and folder) then return nil end
    if key:sub(1, #ADDON_ICON_STYLE_PREFIX) ~= ADDON_ICON_STYLE_PREFIX
        and key:sub(1, #REGISTERED_ICON_STYLE_PREFIX) ~= REGISTERED_ICON_STYLE_PREFIX
    then
        key = REGISTERED_ICON_STYLE_PREFIX .. key
    end
    _registeredIconPacks[key] = {
        label = label,
        folder = folder,
        noMidnightSuffix = type(opts) == "table" and opts.noMidnightSuffix == true,
        hasMidnightSuffix = type(opts) == "table" and opts.hasMidnightSuffix == true,
    }
    _externalIconPacks = nil
    _externalIconPackOrder = nil
    _statusIconAssetItemsCache = {}
    return key
end

-- Public extension point: other addons register/refresh custom status-icon
-- packs through these globals. No internal callers by design -- keep exported.
ExportPublic("MSUF_RegisterStatusIconPack", function(key, label, folder, opts)
    return GF.RegisterStatusIconPack(key, label, folder, opts)
end)
ExportPublic("MSUF_RefreshStatusIconPacks", function()
    _texturePathExistsCache = {}
    _statusIconAssetItemsCache = {}
    return GF.RefreshExternalStatusIconPacks(true)
end)

local INDICATOR_STYLE_KEYS = {
    roleIcon       = "roleIconStyle",
    leaderIcon     = "leaderIconStyle",
    assistIcon     = "assistIconStyle",
    raidMarker     = "raidMarkerStyle",
    readyCheckIcon = "readyCheckIconStyle",
    summonIcon     = "summonIconStyle",
    resurrectIcon  = "resurrectIconStyle",
    pvpIcon        = "pvpIconStyle",
    phaseIcon      = "phaseIconStyle",
}

--- Midnight art is a "_midnight" file variant of a pack, not a pack of its own, so it used to
--- ride on the scope-wide useMidnightIcons flag. The flag now travels inside the per-indicator
--- style value ("UXPRO@MIDNIGHT") instead, which lets one dropdown per indicator cover every
--- icon type. Splitting happens in the texture entry points, so any caller that just forwards a
--- stored style value keeps working. useMidnightIcons stays as the fallback for older profiles.
local MIDNIGHT_STYLE_SUFFIX = "@MIDNIGHT"

local function SplitIconStyle(style)
    if type(style) ~= "string" then return nil, false end
    local base = style:match("^(.+)@MIDNIGHT$")
    if base then return base, true end
    return style, false
end

local function JoinIconStyle(style, useMidnight)
    if type(style) ~= "string" or style == "" or useMidnight ~= true then return style end
    return style .. MIDNIGHT_STYLE_SUFFIX
end

local function NormalizeIconStyle(style, fallback)
    style = (SplitIconStyle(style))
    if type(style) ~= "string" or style == "" or style == "DEFAULT" then
        style = (SplitIconStyle(fallback)) or "BLIZZARD"
    end
    if style == "BLIZZARD" or CUSTOM_STYLES[style] then return style end
    if ExternalIconPackByKey(style) then return style end
    return "BLIZZARD"
end

local function IndicatorIconStyle(conf, indicatorKey)
    conf = (type(conf) == "table") and conf or {}
    local styleKey = INDICATOR_STYLE_KEYS[indicatorKey]
    local style, midnight = SplitIconStyle(styleKey and conf[styleKey] or nil)
    if type(style) ~= "string" or style == "" or style == "DEFAULT" then
        style, midnight = SplitIconStyle(conf.iconStyle or "MSUF_ROLES")
        if not midnight then midnight = conf.useMidnightIcons == true end
    end
    return NormalizeIconStyle(style, "BLIZZARD"), midnight == true
end

--- Per-indicator override wins over the stored indicator style; both may carry the suffix.
local function ResolveIndicatorIconStyle(conf, indicatorKey, styleOverride)
    local base, midnight = SplitIconStyle(styleOverride)
    if type(base) == "string" and base ~= "" and base ~= "DEFAULT" then
        return NormalizeIconStyle(base, "BLIZZARD"), midnight == true
    end
    return IndicatorIconStyle(conf, indicatorKey)
end

local function CustomIconPath(style, file, useMidnight)
    local folder = CUSTOM_STYLES[style]
    if not folder then return nil end
    if ROLE_ONLY_CUSTOM_STYLES[style] and not ROLE_ONLY_ICON_FILES[file] then return nil end
    if useMidnight and not CUSTOM_STYLES_NO_MIDNIGHT_SUFFIX[style] then
        file = file .. "_midnight"
    end
    return MEDIA_PREFIX .. folder .. "\\" .. file
end

local function StatusIconFile(iconType, variant)
    iconType = tostring(iconType or "")
    if iconType == "role" then return ROLE_MAP[variant] or "dps" end
    if iconType == "leader" then return "leader" end
    if iconType == "assist" then return "assist" end
    if iconType == "raidMarker" or iconType == "raidmarker" then
        return RAID_MARKER_FILES[tonumber(variant) or variant] or "raid_skull"
    end
    if iconType == "readyCheck" or iconType == "readycheck" then
        return READY_FILES[tostring(variant or "")] or "ready_waiting"
    end
    if iconType == "summon" then
        return SUMMON_FILES[tonumber(variant) or variant] or "summon_pending"
    end
    if iconType == "pvp" then
        return PVP_FILES[variant] or PVP_FILES[tostring(variant or ""):lower()] or "pvp_alliance"
    end
    if iconType == "elite" then
        variant = tostring(variant or ""):upper()
        if variant == "BOSS" or variant == "WORLDBOSS" then return "elite_boss" end
        if variant == "RARE" or variant == "RAREELITE" then return "elite_rare" end
        return "elite_elite"
    end
    return SIMPLE_STATUS_ICON_FILES[iconType]
end

local function RaidMarkerTexCoord(index)
    index = tonumber(index) or 8
    if index < 1 or index > 8 then index = 8 end
    local col = (index - 1) % 4
    local row = math_floor((index - 1) / 4)
    local size = 0.25
    return col * size, (col + 1) * size, row * size, (row + 1) * size
end

local function BuiltinStatusIconTexture(iconType, variant)
    iconType = tostring(iconType or "")
    if iconType == "leader" then return BLIZZARD_LEADER_TEX, 0, 1, 0, 1 end
    if iconType == "assist" then return BLIZZARD_ASSIST_TEX, 0, 1, 0, 1 end
    if iconType == "role" then
        local c = BLIZZARD_ROLE_COORDS[variant] or BLIZZARD_ROLE_COORDS.DAMAGER
        return BLIZZARD_ROLE_TEX, c[1], c[2], c[3], c[4]
    end
    if iconType == "raidMarker" or iconType == "raidmarker" then
        local l, r, t, b = RaidMarkerTexCoord(variant)
        return BLIZZARD_RAID_MARKER_TEX, l, r, t, b
    end
    if iconType == "readyCheck" or iconType == "readycheck" then
        return BLIZZARD_READY_TEXTURES[tostring(variant or "")] or BLIZZARD_READY_TEXTURES.waiting, 0, 1, 0, 1
    end
    if iconType == "summon" then
        local key = SUMMON_FILES[tonumber(variant) or variant]
        if key == "summon_accepted" then return BLIZZARD_SUMMON_TEXTURES.accepted, 0, 1, 0, 1 end
        if key == "summon_declined" then return BLIZZARD_SUMMON_TEXTURES.declined, 0, 1, 0, 1 end
        return BLIZZARD_SUMMON_TEXTURES.pending, 0, 1, 0, 1
    end
    if iconType == "incomingRes" or iconType == "resurrect" then return BLIZZARD_REZ_TEXTURE, 0, 1, 0, 1 end
    if iconType == "phase" then return BLIZZARD_PHASE_TEXTURE, 0, 1, 0, 1 end
    if iconType == "pvp" then
        return BLIZZARD_PVP_TEXTURES[variant] or BLIZZARD_PVP_TEXTURES[tostring(variant or "")] or BLIZZARD_PVP_TEXTURES.Alliance, 0, 1, 0, 1
    end
    if iconType == "combat" then return BLIZZARD_STATE_TEXTURE, 0.5, 1, 0, 0.5 end
    if iconType == "resting" then return BLIZZARD_STATE_TEXTURE, 0, 0.5, 0, 0.5 end
    if iconType == "elite" then return "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", 0, 1, 0, 1 end
    return nil
end

local function ExternalIconPath(pack, file, useMidnight)
    if not (pack and file) then return nil end
    if type(pack.files) == "table" then
        if useMidnight == true and pack.files[file .. "_midnight"] then
            return pack.files[file .. "_midnight"]
        end
        return pack.files[file]
    end
    if type(pack.folder) ~= "string" or pack.folder == "" then return nil end
    local path = pack.folder .. "\\" .. file
    if useMidnight == true and not pack.noMidnightSuffix then
        local midnightPath = pack.folder .. "\\" .. file .. "_midnight"
        if pack.hasMidnightSuffix or TexturePathExists(midnightPath) then path = midnightPath end
    end
    if TexturePathExists(path) then return path end
    return nil
end

local function StatusIconAssetCacheKey(iconType, variant, includeDefault, includeStyleSets)
    return tostring(iconType or "") .. "\031" .. tostring(variant or "") .. "\031" .. (includeDefault and "1" or "0") .. "\031" .. (includeStyleSets and "1" or "0")
end

local function AddStatusIconAssetItem(out, used, value, text)
    if type(value) ~= "string" or value == "" or used[value] then return end
    used[value] = true
    out[#out + 1] = {
        value = value,
        text = text or value,
        texture = value,
        texturePreview = value,
        previewKind = "icon",
    }
end

local function AddSharedMediaIconAssetItems(out, used)
    local lsm = LSM()
    if not (lsm and type(lsm.HashTable) == "function") then return end
    for _, mediaType in ipairs({ "msuf_statusicon", "background", "statusbar" }) do
        local hash = lsm:HashTable(mediaType)
        if type(hash) == "table" then
            local names = {}
            for name in pairs(hash) do names[#names + 1] = name end
            table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
            for i = 1, #names do
                local name = names[i]
                local path = hash[name]
                local packLabel, file = ParseLSMStatusIconName(name)
                local isIconMedia = mediaType == "msuf_statusicon" or (packLabel ~= nil and file ~= nil)
                if isIconMedia and type(path) == "string" and path ~= "" then
                    AddStatusIconAssetItem(out, used, path, "SharedMedia: " .. tostring(name))
                end
            end
        end
    end
end

function GF.GetStatusIconAssetItems(iconType, variant, includeDefault, includeStyleSets)
    includeStyleSets = includeStyleSets == true
    local cacheKey = StatusIconAssetCacheKey(iconType, variant, includeDefault == true, includeStyleSets)
    if _statusIconAssetItemsCache[cacheKey] then return _statusIconAssetItemsCache[cacheKey] end
    local out, used = {}, {}
    if includeDefault == true then
        out[#out + 1] = { value = "", text = "Use default icon" }
        used[""] = true
    end
    local file = StatusIconFile(iconType, variant)
    if file then
        if includeStyleSets then
            for i = 1, #GF.ICON_STYLE_ITEMS do
                local item = GF.ICON_STYLE_ITEMS[i]
                local style = item.value or item.key
                local label = item.text or item.label or style
                local path = CustomIconPath(style, file, false)
                if path then AddStatusIconAssetItem(out, used, path, tostring(label) .. ": " .. file) end
                if path and not CUSTOM_STYLES_NO_MIDNIGHT_SUFFIX[style] then
                    local midnightPath = CustomIconPath(style, file, true)
                    AddStatusIconAssetItem(out, used, midnightPath, tostring(label) .. " Midnight: " .. file)
                end
            end
        end
        for i = 1, #STANDALONE_STATUS_ICON_FOLDERS do
            local item = STANDALONE_STATUS_ICON_FOLDERS[i]
            AddStatusIconAssetItem(out, used, MEDIA_PREFIX .. item.folder .. "\\" .. file, item.label .. ": " .. file)
        end
        if includeStyleSets then
            GF.RefreshExternalStatusIconPacks()
            for i = 1, #(_externalIconPackOrder or {}) do
                local pack = _externalIconPackOrder[i]
                local path = ExternalIconPath(pack, file, false)
                if path then AddStatusIconAssetItem(out, used, path, tostring(pack.label or pack.key) .. ": " .. file) end
                local midnightPath = ExternalIconPath(pack, file, true)
                if midnightPath and midnightPath ~= path then
                    AddStatusIconAssetItem(out, used, midnightPath, tostring(pack.label or pack.key) .. " Midnight: " .. file)
                end
            end
        end
    end
    AddSharedMediaIconAssetItems(out, used)
    _statusIconAssetItemsCache[cacheKey] = out
    return out
end

function GF.GetStatusIconTexture(style, iconType, variant, useMidnight)
    local base, midnight = SplitIconStyle(style)
    useMidnight = (useMidnight == true) or midnight
    style = NormalizeIconStyle(base, "BLIZZARD")
    local file = StatusIconFile(iconType, variant)
    local folder = CUSTOM_STYLES[style]
    if folder and file then
        local path = CustomIconPath(style, file, useMidnight == true)
        if path then return path, 0, 1, 0, 1 end
    end
    local external = ExternalIconPackByKey(style)
    if external and file then
        local path = ExternalIconPath(external, file, useMidnight == true)
        if path then return path, 0, 1, 0, 1 end
    end
    return BuiltinStatusIconTexture(iconType, variant)
end

function GF.StatusIconPackSupports(style, iconType, variant, useMidnight)
    local base, midnight = SplitIconStyle(style)
    useMidnight = (useMidnight == true) or midnight
    style = base
    if type(style) ~= "string" or style == "" or style == "DEFAULT" then return true end
    style = NormalizeIconStyle(style, "BLIZZARD")
    if style == "BLIZZARD" then return BuiltinStatusIconTexture(iconType, variant) ~= nil end
    local file = StatusIconFile(iconType, variant)
    if not file then return false end
    if CUSTOM_STYLES[style] then return file ~= nil and CustomIconPath(style, file, useMidnight == true) ~= nil end
    local external = ExternalIconPackByKey(style)
    if external then return ExternalIconPath(external, file, useMidnight == true) ~= nil end
    return false
end

function GF.GetIndicatorIconStyle(kind, indicatorKey)
    local conf = GF.GetConf(kind)
    return IndicatorIconStyle(conf, indicatorKey)
end

function GF.GetRoleTexture(kind, role, styleOverride)
    local conf = GF.GetConf(kind)
    local style, useMidnight = ResolveIndicatorIconStyle(conf, "roleIcon", styleOverride)
    return GF.GetStatusIconTexture(style, "role", role, useMidnight)
end

function GF.GetLeaderTexture(kind, styleOverride)
    local conf = GF.GetConf(kind)
    local style, useMidnight = ResolveIndicatorIconStyle(conf, "leaderIcon", styleOverride)
    return GF.GetStatusIconTexture(style, "leader", nil, useMidnight)
end

function GF.GetAssistTexture(kind, styleOverride)
    local conf = GF.GetConf(kind)
    local style, useMidnight = ResolveIndicatorIconStyle(conf, "assistIcon", styleOverride)
    return GF.GetStatusIconTexture(style, "assist", nil, useMidnight)
end

GF.ICON_STYLE_ITEMS = {
    { key = "BLIZZARD",      label = "Blizzard (Default)" },
    { key = "MSUF_ROLES",    label = "MSUF Roles"         },
    { key = "CLASSIC",       label = "Classic"            },
    { key = "MIDNIGHT",      label = "Midnight"           },
    { key = "UXPRO",         label = "UX Pro"             },
    { key = "GLOSSY_ORBS",   label = "Glossy Orbs"        },
    { key = "DARK_EMBOSS",   label = "Dark Emboss"        },
    { key = "GLASS_PANELS",  label = "Glass Panels"       },
    { key = "NEON_OUTLINE",  label = "Neon Outline"       },
    { key = "RING_SYMBOLS",  label = "Ring Symbols"       },
    { key = "DOTS",          label = "Dots"               },
    { key = "SHAPES",        label = "Shapes"             },
    { key = "DIAMONDS",      label = "Diamonds"           },
    { key = "SQUARES",       label = "Squares"            },
}

--- includeMidnight appends the "_midnight" art of every pack that ships one as its own entry,
--- so a single dropdown covers all icon types instead of pairing a style list with a separate
--- Midnight toggle. Packs without midnight art (and BLIZZARD) contribute one entry only.
function GF.GetIconStyleItems(includeDefault, includeMidnight)
    local out = {}
    local seenValues, seenLabels = {}, {}
    local function LabelKey(label)
        if type(label) ~= "string" then return nil end
        label = label:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "):lower()
        return label ~= "" and label or nil
    end
    local function AddStyleItem(value, text, hasMidnight)
        value = type(value) == "string" and value or nil
        text = type(text) == "string" and text or value
        if not value or value == "" then return end
        local lk = LabelKey(text)
        if seenValues[value] or (lk and seenLabels[lk]) then return end
        seenValues[value] = true
        if lk then seenLabels[lk] = true end
        out[#out + 1] = { value = value, text = text }
        if not (includeMidnight and hasMidnight) then return end
        local midnightValue = JoinIconStyle(value, true)
        local midnightText = text .. " (Midnight)"
        local mlk = LabelKey(midnightText)
        if seenValues[midnightValue] or (mlk and seenLabels[mlk]) then return end
        seenValues[midnightValue] = true
        if mlk then seenLabels[mlk] = true end
        out[#out + 1] = { value = midnightValue, text = midnightText }
    end
    if includeDefault then
        AddStyleItem("DEFAULT", "Follow global style")
    end
    for i = 1, #GF.ICON_STYLE_ITEMS do
        local item = GF.ICON_STYLE_ITEMS[i]
        local key = item.value or item.key
        AddStyleItem(key, item.text or item.label or key,
            CUSTOM_STYLES[key] ~= nil and not CUSTOM_STYLES_NO_MIDNIGHT_SUFFIX[key])
    end
    GF.RefreshExternalStatusIconPacks()
    for i = 1, #(_externalIconPackOrder or {}) do
        local pack = _externalIconPackOrder[i]
        AddStyleItem(pack.key, pack.label, pack.noMidnightSuffix ~= true)
    end
    return out
end

--- Options/EditMode need the same encoding to show a stored style in a dropdown.
GF.SplitIconStyle = SplitIconStyle
GF.JoinIconStyle = JoinIconStyle

ExportPublic("MSUF_GetStatusIconPackValues", function(includeDefault, includeMidnight)
    return GF.GetIconStyleItems(includeDefault == true, includeMidnight == true)
end)

ExportPublic("MSUF_SplitStatusIconStyle", SplitIconStyle)

ExportPublic("MSUF_GetStatusIconTexture", function(style, iconType, variant, useMidnight)
    return GF.GetStatusIconTexture(style, iconType, variant, useMidnight == true)
end)

ExportPublic("MSUF_StatusIconPackSupports", function(style, iconType, variant, useMidnight)
    return GF.StatusIconPackSupports(style, iconType, variant, useMidnight == true)
end)

ExportPublic("MSUF_GetStatusIconAssetValues", function(iconType, variant, includeDefault, includeStyleSets)
    return GF.GetStatusIconAssetItems(iconType, variant, includeDefault == true, includeStyleSets == true)
end)

ExportPublic("MSUF_GetRoleStatusIconTexture", function(style, role, useMidnight)
    return GF.GetStatusIconTexture(style, "role", role, useMidnight == true)
end)

ExportPublic("MSUF_GetLeaderStatusIconTexture", function(style, useMidnight)
    return GF.GetStatusIconTexture(style, "leader", nil, useMidnight == true)
end)

ExportPublic("MSUF_GetAssistStatusIconTexture", function(style, useMidnight)
    return GF.GetStatusIconTexture(style, "assist", nil, useMidnight == true)
end)
