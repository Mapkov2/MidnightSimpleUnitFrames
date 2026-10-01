-- group_additional_runtime_smoke.lua <repoRoot>
--
-- Runtime contracts of the extra group blocks
-- (GroupFrames/MSUF_GroupFrames_Additional.lua):
--   * party-target bars keep updating from a 0.2 s ticker (their compound
--     tokens raise no unit events) and register no dead unit events;
--   * health events take the value path (no name, max or colour work unless the
--     colour follows the value), identity events repaint everything;
--   * an unchanged refresh writes no secure attribute, no state driver and does
--     not hide/show the pet header; previews never run the secure apply; roster
--     storms fold into one pass;
--   * the default pet column grows from its fixed block's top left corner;
--   * mana rows follow the roster in combat without any protected write;
--   * an excluded own-target slot and disabled allied bosses listen to nothing;
--   * defaults put every block on its own spot; no boss units means no boss
--     block; a nil scope enable is off;
--   * Edit Mode registers the extra movers in one batch with translated labels.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg[1], "usage: group_additional_runtime_smoke.lua <root>"):gsub("\\", "/")
local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"), "missing " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local combat, raid, group, size = false, false, true, 3
local counters = {}
local function Count(name) counters[name] = (counters[name] or 0) + 1 end
local function Reset() counters = {} end

local methods = {}
local frames = {}
local function Frame(kind, name, parent, template)
    local f = setmetatable({ kind = kind, name = name, parent = parent, attrs = {}, scripts = {}, hooks = {}, events = {},
        units = {}, shown = true, regions = {} }, { __index = methods })
    frames[#frames + 1] = f
    return f
end
function methods:SetScript(k, v) self.scripts[k] = v end
function methods:HookScript(k, v) local list = self.hooks[k] or {}; self.hooks[k] = list; list[#list + 1] = v end
function methods:Fire(k, ...)
    if self.scripts[k] then self.scripts[k](self, ...) end
    for _, hook in ipairs(self.hooks[k] or {}) do hook(self, ...) end
end
function methods:RegisterEvent(k) self.events[k] = true end
function methods:RegisterUnitEvent(k, u) Count("RegisterUnitEvent"); self.events[k] = true; self.units[k] = u end
function methods:UnregisterEvent(k) self.events[k] = nil; self.units[k] = nil end
function methods:UnregisterAllEvents() self.events, self.units = {}, {} end
function methods:SetAttribute(k, v)
    assert(not combat, "protected attribute write in combat: " .. tostring(k))
    if k ~= "_ignore" then Count("SetAttribute") end
    self.attrs[k] = v
    self:Fire("OnAttributeChanged", k, v)
end
function methods:GetAttribute(k) return self.attrs[k] end
function methods:GetParent() return self.parent end
function methods:SetPoint(...) if self.secure then assert(not combat, "secure SetPoint in combat") end; self.point = { ... } end
function methods:ClearAllPoints() self.point = nil end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:Show() if self.secure then assert(not combat, "secure Show in combat") end; if not self.shown then Count("Show:" .. tostring(self.name)) end; self.shown = true; self:Fire("OnShow") end
function methods:Hide() if self.secure then assert(not combat, "secure Hide in combat") end; if self.shown then Count("Hide:" .. tostring(self.name)) end; self.shown = false end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetValue(v) self.value = v end
function methods:SetMinMaxValues(_, v) self.maxValue = v end
-- As in the client, a FontString without a font refuses SetText ("Font not set").
function methods:SetText(v)
    if self.kind == "FontString" then assert(self.font, "FontString:SetText(): Font not set") end
    Count("SetText"); self.text = v
end
function methods:CreateFontString() local r = Frame("FontString", nil, self); self.regions[#self.regions + 1] = r; return r end
function methods:CreateTexture(_, layer) Count("CreateTexture"); local r = Frame("Texture", nil, self); r.layer = layer; return r end
function methods:SetFont(path, size, flags) self.font = { path, size, flags } end
function methods:SetStatusBarTexture(texture) self.texture = texture end
function methods:SetStatusBarColor(r, g, b) Count("SetStatusBarColor"); self.color = { r, g, b } end
function methods:GetStatusBarColor() return unpack(self.color or { .1, .2, .3 }) end
function methods:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function methods:SetColorTexture(r, g, b, a) self.bgColor = { r, g, b, a } end
function methods:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function methods:SetTexture(texture) self.textureFile = texture end
function methods:SetAllPoints() end
function methods:SetJustifyH() end
function methods:SetWidth(w) self.width = w end
function methods:SetFrameStrata() end
function methods:SetFrameLevel(level) self.level = level end
function methods:GetFrameLevel() return self.level or 1 end
function methods:RegisterForClicks() end
function methods:EnableMouse() end

UIParent = Frame("Frame", "UIParent")
local MSUF = { GF = {} }
local GF = MSUF.GF
local XML = Read("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_Additional.xml")
local ONLOAD = assert(XML:match('<OnLoad function="([%w_]+)"/>'))
function CreateFrame(kind, name, parent, template)
    local f = Frame(kind, name, parent, template)
    if name then _G[name] = f end
    if template == "MSUF_GroupAdditionalUnitTemplate" or template == "SecureGroupPetHeaderTemplate" then f.secure = true end
    if template == "SecureGroupPetHeaderTemplate" then
        -- SecureGroupHeaders.lua SecureGroupPetHeader_OnAttributeChanged: writes inside
        -- the "_ignore" window, and the closing write itself, never update the header.
        f.scripts.OnAttributeChanged = function(self, key)
            if key == "_ignore" or self.attrs._ignore then return end
            if self:IsVisible() then Count("PetHeaderUpdate:" .. tostring(self.name)) end
        end
    end
    if template == "MSUF_GroupAdditionalUnitTemplate" then
        f.Health = Frame("StatusBar", nil, f)
        f.Health.Background = Frame("Texture", nil, f.Health)
        f.Health.Name = Frame("FontString", nil, f.Health)
        -- The template's Name inherits GameFontHighlightSmall.
        f.Health.Name.font = { "Fonts\\FRIZQT__.TTF", 10, "" }
        _G[ONLOAD](f)
    end
    return f
end
function InCombatLockdown() return combat end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers() local due = timers; timers = {}; for _, fn in ipairs(due) do fn() end end
local health = { party1target = 70, target = 50, pet = 30, partypet1 = 40 }
function UnitHealth(unit) Count("UnitHealth"); return health[unit] or 100 end
function UnitHealthMax(unit) Count("UnitHealthMax"); return 100 end
function UnitName(unit) Count("UnitName"); return unit end
function UnitClass() return "Hunter", "HUNTER" end
function UnitPower(unit) return "MANA:" .. unit end
function UnitPowerMax() return 1000 end
local roles = { player = "HEALER", party1 = "DAMAGER", party2 = "HEALER" }
function RegisterUnitWatch(b) assert(not combat, "unit watch in combat"); b.watched = true end
function UnregisterUnitWatch(b) assert(not combat, "unit watch in combat"); b.watched = false end
function RegisterStateDriver(b, _, v) assert(not combat); Count("RegisterStateDriver"); b.driver = v end
function UnregisterStateDriver(b) assert(not combat); Count("UnregisterStateDriver"); b.driver = nil end
function IsInRaid() return raid end
function IsInGroup() return group end
function GetNumGroupMembers() return size end
function MSUF.ExportPublic(k, v) _G[k] = v end
local conf = { enabled = true, targetsEnabled = true, targetsIncludePlayer = false, petsEnabled = true, friendlyBossEnabled = true,
    friendlyBossHealerOnly = true, healerManaEnabled = true, petsColumns = 1, petsMaxCount = 40 }
local spec = { health = { mode = "class", background = {} } }
function GF.GetConf() return conf end
function GF.EnsureDB() Count("EnsureDB") end
function GF.GetLiveGroupKind() return raid and "raid" or "party" end
function GF.ResolveBarTexture() return "bar" end
function GF.ResolveFontPath() return "font" end
function GF.ResolveFontFlags() return "" end
function GF.GetCompiledSpec() return spec end
function GF.ResolveNameColor() return 1, 1, 1 end
function GF.GetUnitGroupRole(unit) return roles[unit] or "DAMAGER" end
function GF.RegisterRuntimeObserver(_, cb) GF.observer = cb end
MSUF.UFBarTextCommon = { ApplyHealthStatusColor = function(bar) Count("Paint"); bar:SetStatusBarColor(.1, .2, .3) end }

local function Load(client)
    MSUF.Client = client
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_Additional.lua"))("MSUF", MSUF)
end
Load({ SupportsUnit = function() return true end })

---------------------------------------------------------------------------
-- Defaults: every block has its own start spot (P3-1)
---------------------------------------------------------------------------
local defaults = Read("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua")
local seen = {}
for _, prefix in ipairs(GF.ADDITIONAL_BLOCKS) do
    local x = assert(tonumber(defaults:match("\n    " .. prefix .. "X = (%-?%d+),")), "no X default for " .. prefix)
    local y = assert(tonumber(defaults:match("\n    " .. prefix .. "Y = (%-?%d+),")), "no Y default for " .. prefix)
    assert(x == GF.ADDITIONAL_DEFAULT_X[prefix] and y == GF.ADDITIONAL_DEFAULT_Y[prefix], prefix .. " runtime fallback differs from the DB default")
    assert(not seen[x .. "," .. y], prefix .. " starts on another block's spot")
    seen[x .. "," .. y] = true
end

---------------------------------------------------------------------------
-- Party targets: ticker values, no dead unit events (P0-1, P2-10)
---------------------------------------------------------------------------
GF.RefreshAdditionalGroups()
local targets = MSUF_GroupAdditional_Targets
local buttons = {}
for _, f in ipairs(frames) do if f.attrs.unit and f.parent == targets then buttons[f.attrs.unit] = f end end
local member, own = assert(buttons.party1target), assert(buttons.target)
assert(member.events.UNIT_TARGET and member.units.UNIT_TARGET == "party1", "party target lost its identity event")
assert(not member.events.UNIT_HEALTH and not member.events.UNIT_MAXHEALTH, "compound token registered unit events that never fire")
assert(next(own.events) == nil and own.unit == nil and not own.watched, "excluded own-target slot still listens")
assert(member.Health.value == 70, "party target not painted on bind")
assert(targets.scripts.OnUpdate, "party targets have no value ticker")
combat = true
targets.scripts.OnUpdate(targets, 0.01)
health.party1target = 25
targets.scripts.OnUpdate(targets, 0.05)
assert(member.Health.value == 70, "ticker ran faster than its interval")
targets.scripts.OnUpdate(targets, 0.2)
assert(member.Health.value == 25, "party target health froze in combat")
Reset()
targets.scripts.OnUpdate(targets, 0.25)
assert((counters.UnitName or 0) == 0 and (counters.Paint or 0) == 0, "ticker repainted identity")
combat = false
conf.targetsIncludePlayer = true
GF.RefreshAdditionalGroups()
assert(own.unit == "target" and own.events.UNIT_HEALTH and own.events.PLAYER_TARGET_CHANGED and own.watched, "own target slot not bound when included")
conf.targetsIncludePlayer = false
GF.RefreshAdditionalGroups()
assert(next(own.events) == nil and own.unit == nil, "own target slot kept listening after exclusion")

---------------------------------------------------------------------------
-- Value path vs identity path (P2-4)
---------------------------------------------------------------------------
local pets = MSUF_GroupAdditional_Pets
local pet = CreateFrame("Button", nil, pets, "MSUF_GroupAdditionalUnitTemplate")
assert(pet.bg == pet.Health.Background, "template background was not reused")
pet:SetAttribute("unit", "partypet1")
Reset()
pet.scripts.OnEvent(pet, "UNIT_HEALTH", "partypet1")
assert(counters.UnitHealth == 1 and not counters.UnitHealthMax and not counters.UnitName and not counters.Paint,
    "health tick did more than the value path")
pet.scripts.OnEvent(pet, "UNIT_MAXHEALTH", "partypet1")
assert(counters.UnitHealthMax == 1 and not counters.UnitName, "max health did more than the value path")
spec = { health = { mode = "gradient", background = {} } }
pet.scripts.OnEvent(pet, "UNIT_NAME_UPDATE", "partypet1")
Reset()
pet.scripts.OnEvent(pet, "UNIT_HEALTH", "partypet1")
assert(counters.Paint == 1 and not counters.UnitName, "gradient colour did not follow the value")
spec = { health = { mode = "class", background = {} } }
pet.scripts.OnEvent(pet, "UNIT_NAME_UPDATE", "partypet1")
Reset()
health.partypet1 = 0
pet.scripts.OnEvent(pet, "UNIT_HEALTH", "partypet1")
assert(counters.Paint == 1, "an emptied bar kept its living colour")
pet.scripts.OnEvent(pet, "UNIT_HEALTH", "partypet1")
assert(counters.Paint == 1, "an empty bar repainted on every tick")
Reset()
pet.scripts.OnEvent(pet, "UNIT_CONNECTION", "partypet1")
assert(counters.UnitName == 1 and counters.Paint == 1, "identity event skipped the repaint")

---------------------------------------------------------------------------
-- Idempotent refresh, previews, coalescing (P2-5) and the pet anchor (P2-6)
---------------------------------------------------------------------------
GF.RefreshAdditionalGroups()
local block = MSUF_GroupAdditional_PetsBlock
assert(pets.point[1] == "TOPLEFT" and pets.point[2] == block, "default pet column is not anchored to its fixed block")
Reset()
GF.RefreshAdditionalGroups()
assert(not counters.SetAttribute and not counters.RegisterStateDriver, "an unchanged refresh rewrote secure attributes or drivers")
assert(not counters["Hide:MSUF_GroupAdditional_Pets"] and not counters["Show:MSUF_GroupAdditional_Pets"], "an unchanged refresh tore the pet header down")
assert(not counters.RegisterUnitEvent, "an unchanged refresh re-registered unit events")
Reset()
GF.ShowAdditionalGroupPreview("party", 5)
GF.HideAdditionalGroupPreview("party")
assert(not counters.SetAttribute and not counters.EnsureDB, "a preview ran the secure apply")
for _ = 1, 10 do for _, f in ipairs(frames) do if f.events.GROUP_ROSTER_UPDATE and f.scripts.OnEvent then f.scripts.OnEvent(f, "GROUP_ROSTER_UPDATE") end end end
assert(#timers == 1, "a roster storm queued more than one pass")
conf.petsWidth = 140
RunTimers()
-- The template size plus one trailing write outside the _ignore window.
assert(counters.SetAttribute and counters.SetAttribute <= 2, "a width change rewrote more than the template size")
assert(counters["PetHeaderUpdate:MSUF_GroupAdditional_Pets"] == 1,
    "a settings change on the shown pet header ran " .. tostring(counters["PetHeaderUpdate:MSUF_GroupAdditional_Pets"])
    .. " secure updates; the _ignore window swallows every write, one trailing write must run exactly one")

---------------------------------------------------------------------------
-- Mana rows follow the roster in combat (P2-9)
---------------------------------------------------------------------------
local mana = MSUF_GroupAdditional_HealerMana
local function ManaUnits()
    local out = {}
    for _, f in ipairs(frames) do if f.parent == mana and f.bar and f.shown then out[#out + 1] = f.unit end end
    table.sort(out)
    return table.concat(out, ",")
end
assert(ManaUnits() == "party2,player", "healer rows wrong: " .. ManaUnits())
combat = true
roles.party2, roles.party1 = "DAMAGER", "HEALER"
for _, f in ipairs(frames) do if f.events.GROUP_ROSTER_UPDATE and f.scripts.OnEvent then f.scripts.OnEvent(f, "GROUP_ROSTER_UPDATE") end end
RunTimers()
assert(ManaUnits() == "party1,player", "mana rows froze in combat: " .. ManaUnits())
combat = false
for _, f in ipairs(frames) do if f.events.PLAYER_REGEN_ENABLED and f.scripts.OnEvent then f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED") end end

---------------------------------------------------------------------------
-- Allied bosses: drivers released on disable; none without boss units (P2-15, P3-2)
---------------------------------------------------------------------------
local bosses = {}
for _, f in ipairs(frames) do if f.parent == MSUF_GroupAdditional_FriendlyBosses and f.attrs.unit then bosses[#bosses + 1] = f end end
assert(#bosses == 5 and bosses[1].driver == "[@boss1,help,exists] show; hide", "allied boss drivers missing")
Reset()
GF.RefreshAdditionalGroups()
assert(not counters.RegisterStateDriver, "boss drivers re-registered on an unchanged refresh")
roles.player = "DAMAGER"
GF.RefreshAdditionalGroups()
assert(counters.UnregisterStateDriver == 5 and bosses[1].driver == nil and not bosses[1].shown, "boss drivers kept running after the block turned off")
roles.player = "HEALER"

---------------------------------------------------------------------------
-- A nil scope enable is off, like the group runtime (P3-7)
---------------------------------------------------------------------------
conf.enabled = nil
GF.RefreshAdditionalGroups()
assert(not MSUF_GroupAdditional_Targets.shown and not MSUF_GroupAdditional_HealerMana.shown and not MSUF_GroupAdditional_PetsBlock.shown,
    "blocks ran with the scope enable unset")
conf.enabled = true

-- No boss units on the client: no allied boss block at all.
frames, timers = {}, {}
for _, name in ipairs({ "Targets", "Pets", "PetsRest", "PetsBlock", "FriendlyBosses", "HealerMana" }) do _G["MSUF_GroupAdditional_" .. name] = nil end
MSUF.GF = {}
GF = MSUF.GF
for k, v in pairs({ GetConf = function() return conf end, EnsureDB = function() end, GetLiveGroupKind = function() return "party" end,
    ResolveBarTexture = function() return "bar" end, ResolveFontPath = function() return "font" end, ResolveFontFlags = function() return "" end,
    GetCompiledSpec = function() return spec end, ResolveNameColor = function() return 1, 1, 1 end,
    GetUnitGroupRole = function(unit) return roles[unit] or "DAMAGER" end, RegisterRuntimeObserver = function() end }) do GF[k] = v end
Load({ SupportsUnit = function(unit) return unit ~= "boss1" end })
Reset()
GF.RefreshAdditionalGroups()
assert(not counters.RegisterStateDriver and GF.GetAdditionalPreviewSpec("party", "friendlyBoss") == nil
    and GF.ADDITIONAL_HAS_BOSS_UNITS == false, "allied bosses ran on a client without boss units")

---------------------------------------------------------------------------
-- Edit Mode: one batch, translated names, no boss mover without boss units (P3-6)
---------------------------------------------------------------------------
local em2 = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua")
local body = assert(em2:match("\n(local ADDITIONAL_BLOCK_NAMES = .-\nend)\n\nlocal function RegisterGF"), "RegisterAdditionalMovers moved")
local registered, batches = {}, 0
local api = { RegisterElements = function(owner, list) batches = batches + 1; assert(owner == "msuf_group_extras"); for _, e in ipairs(list) do registered[#registered + 1] = e end return true end,
    RegisterElement = function() error("extra movers registered one at a time") end }
local factory = assert(loadstring("return function(MSUF, GF, GetConf, ConfigLocked, LABELS, GROUP_KINDS, max, min) " .. body .. " return RegisterAdditionalMovers end"))()
local register = factory({ EditModeAPI = api, Translate = function(text) return "T:" .. text end },
    function() return GF end, function() return conf end, function() return false end,
    { party = "Group: Party", raid = "Group: Raid" }, { "party", "raid" }, math.max, math.min)
register()
assert(batches == 1, "extra movers were not registered in one batch")
local ids = {}
for _, e in ipairs(registered) do
    ids[#ids + 1] = e.id
    assert(e.label:find("T:", 1, true) and e.extraControls[1].label == "T:Width", "mover labels are not translated")
end
table.sort(ids)
assert(table.concat(ids, ",") == "party_healerMana,party_pets,party_targets,raid_healerMana,raid_pets",
    "unexpected extra movers: " .. table.concat(ids, ","))

print("group_additional_runtime_smoke: PASS")
