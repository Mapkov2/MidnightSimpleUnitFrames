-- rc1 package F: Group Frames > Corner Indicators > a slot set to Custom Spell
-- with "When: Show when missing" (GF.CI_CUSTOM_MODES, saved as
-- conf.ciCustom<slot>.mode = "missing") on the Classic aura backend.
-- C15-A7 / R6-C4-M1 / H-C4-7: the mode reached the compiled corner item as
-- item.mode and nothing on Classic read it, so the corner lit while the aura
-- was PRESENT and stayed dark while it was missing, the reverse of the setting.
--
-- Runs the real Classic backend chain of one flavor in its TOC order with the
-- real group corner compiler (MSUF_UF_Group_Config_Indicators.lua):
--   * missing mode lights the corner (its own colour, no aura behind it) while
--     no matching aura is up and darkens it while one is, through full scans
--     and through UNIT_AURA add/remove deltas;
--   * the slot's Filter decides presence exactly as in present mode: "cast by
--     me" ignores another caster's copy, buff and debuff filters stay apart;
--   * present mode is unchanged;
--   * switching a frame's slot from present to missing re-renders it;
--   * a unit that does not exist shows no indicator;
--   * the missing render allocates nothing.
-- Arguments: repository root, flavor (Vanilla, TBC or Mists).
--
-- With "menu" as a third argument it instead boots the flavor's whole core and
-- Options graph (tools/tests/bh3_menu_page_fixture.lua, any client matrix
-- Suffix or Forever) and builds Group Status & Indicators. Retail 12.x and WoW
-- Forever cannot show a corner while its aura is missing: a native AuraContainer
-- slot never tells MSUF that its aura is absent, and Retail's Buff Reminder
-- placeholder is covered while the aura is up instead of hidden. There the When
-- dropdown offers Show when missing disabled with a visible reason, refuses to
-- write it from any other path, and keeps a stored "missing" (a profile from a
-- Classic client) as it is. Classic clients keep the choice.
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local flavor = assert(arg[2], "flavor argument missing")
local CORNER_MISSING_NOTICE = "Show when missing is unavailable on this client. Saved settings are kept; the slot shows when present."
if arg[3] == "menu" then
    local h = assert(loadfile(root .. "/tools/tests/bh3_menu_page_fixture.lua"))()
    local M, MSUF = h.M, h.MSUF
    local GF = assert(MSUF.GF, flavor .. ": group frames runtime missing")
    local classic = MSUF.Client.IsClassic == true
    local menuFailures = {}
    local function MenuCheck(condition, message)
        if not condition then menuFailures[#menuFailures + 1] = flavor .. ": " .. message end
    end
    -- A profile that chose Show when missing on a Classic client.
    GF.EnsureDB()
    local conf = GF.GetConf("party")
    conf.ciEnabled, conf.ciSlotTL = true, "custom"
    conf.ciCustomTL = { spells = "21562", mode = "missing", filter = "HELPFUL", r = 1, g = 0.2, b = 0.1 }
    M.SetMenuStateValue("gfScope", "party")
    M.SetMenuStateValue("gfCornerSlotSelection", "TL")
    local W = M.Widgets
    local Dropdown, Text = W.Dropdown, W.Text
    local whenDrop, texts = nil, {}
    W.Dropdown = function(section, label, values, width)
        local widget = Dropdown(section, label, values, width)
        if label == "When" then whenDrop = widget end
        return widget
    end
    W.Text = function(...)
        local fs = Text(...)
        texts[#texts + 1] = fs
        return fs
    end
    local entry = h.BuildPage("gf_indicators")
    h.RunRefreshers(entry)
    W.Dropdown, W.Text = Dropdown, Text
    assert(whenDrop, flavor .. ": the corner Custom Spell editor built no When dropdown")
    local values = whenDrop.values
    if type(values) == "function" then values = values() end
    local missingItem
    for i = 1, #(values or {}) do
        if values[i].value == "missing" then missingItem = values[i] end
    end
    assert(missingItem, flavor .. ": the When dropdown lost its Show when missing entry")
    local noticeShown = false
    for i = 1, #texts do
        local fs = texts[i]
        if fs:GetText() == CORNER_MISSING_NOTICE and fs:IsShown() ~= false then noticeShown = true end
    end
    if classic then
        MenuCheck(missingItem.disabled ~= true, "Classic offers Show when missing disabled")
        MenuCheck(not noticeShown, "Classic shows the unavailable notice")
    else
        MenuCheck(missingItem.disabled == true, "Show when missing is selectable where no runtime can show it")
        MenuCheck(noticeShown, "the corner editor does not say why Show when missing is unavailable")
    end
    local shared = GF.CI_CUSTOM_MODES
    for i = 1, #(shared or {}) do
        MenuCheck(shared[i].disabled == nil, "the shared GF.CI_CUSTOM_MODES list was changed")
    end
    -- The stored choice stays as it is and the closed dropdown names it.
    MenuCheck(conf.ciCustomTL.mode == "missing", "building the page changed the stored When")
    MenuCheck(whenDrop.value == "missing", "the When dropdown does not show the stored Show when missing")
    -- Any other write path (search, keyboard, a command) goes through the setter.
    conf.ciCustomTL.mode = "present"
    whenDrop._msuf2OnValueChanged("missing")
    if classic then
        MenuCheck(conf.ciCustomTL.mode == "missing", "Classic refused Show when missing")
    else
        MenuCheck(conf.ciCustomTL.mode == "present", "the setter wrote Show when missing where it cannot work")
    end
    -- The reason is a whole translated sentence in every pack.
    for _, locale in ipairs({ "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
        local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua", "rb"))
        local source = file:read("*a")
        file:close()
        local key = 'L["' .. CORNER_MISSING_NOTICE .. '"] = "'
        local at = source:find(key, 1, true)
        MenuCheck(at ~= nil, locale .. " lacks the unavailable notice")
        if at and not locale:find("^en") then
            local value = source:sub(at + #key, at + #key + #CORNER_MISSING_NOTICE - 1)
            MenuCheck(value ~= CORNER_MISSING_NOTICE, locale .. " keeps the unavailable notice in English")
        end
    end
    if #menuFailures > 0 then
        error("rc1 F (corner Show when missing menu):\n  " .. table.concat(menuFailures, "\n  "))
    end
    print("rc1_f_smoke: ok (" .. flavor .. " menu: Show when missing is "
        .. (classic and "offered" or "disabled with its reason") .. ")")
    return
end
local PROJECT_IDS = { Vanilla = 2, TBC = 5, Mists = 19 }
assert(PROJECT_IDS[flavor], "unknown Classic flavor: " .. tostring(flavor))
_G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 2
_G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, _G.WOW_PROJECT_MISTS_CLASSIC = 5, 19
_G.WOW_PROJECT_ID = PROJECT_IDS[flavor]
_G.C_AddOns = { GetAddOnMetadata = function(_, field)
    if field == "X-MSUF-Client" then return flavor end
    return nil
end }
_G.C_EventUtils = { IsEventValid = function() return true end }

local registered
local namespace = {
    MSUF_Auras3 = {},
    UF = { RegisterElement = function(_, element) registered = element end },
    ExportPublic = function(name, value) _G[name] = value; return value end,
    MSUF_GetGlobalFontSettings = function() return "Fonts\\FRIZQT__.TTF", "OUTLINE", 1, 1, 1, nil, false end,
}
_G.MSUF_NS, _G.MSUF = namespace, namespace
-- Classic aura data is never secret.
_G.issecretvalue = function() return false end
-- Read by the group corner compiler.
_G.MSUF_GetGeneralDB = function() return {} end
_G.MSUF_NormalizeFrameStrata = function(value, fallback) return value or fallback end

-- Widget stub: frames and textures remember visibility and vertex colour -------------------
local Widget = {}
Widget.__index = Widget
function Widget:Show() self._shown = true end
function Widget:Hide() self._shown = false end
function Widget:SetShown(shown) self._shown = shown == true end
function Widget:IsShown() return self._shown == true end
function Widget:IsVisible() return self._shown == true end
function Widget:IsForbidden() return false end
function Widget:SetParent(parent) self._parent = parent end
function Widget:GetParent() return self._parent end
function Widget:SetFrameLevel(level) self._frameLevel = level end
function Widget:GetFrameLevel() return self._frameLevel or 1 end
function Widget:SetScript(name, handler) self._scripts = self._scripts or {}; self._scripts[name] = handler end
function Widget:HookScript(name, handler) self:SetScript(name, handler) end
function Widget:GetObjectType() return self._objectType or "Frame" end
function Widget:SetVertexColor(r, g, b, a) self._r, self._g, self._b, self._a = r, g, b, a end
function Widget:SetTexture(texture) self._texture = texture end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
function Widget:GetNumRegions() return 0 end
function Widget:GetRegions() return nil end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self, _objectType = "Texture" }, Widget) end
Widget.CreateMaskTexture = Widget.CreateTexture
function Widget:CreateFontString() return setmetatable({ _shown = true, _parent = self, _objectType = "FontString" }, Widget) end
for _, name in ipairs({
    "RegisterEvent", "UnregisterEvent", "RegisterUnitEvent", "SetAllPoints", "EnableMouse", "SetSize", "SetPoint",
    "ClearAllPoints", "SetWidth", "SetHeight", "SetAlpha", "SetDrawSwipe", "SetHideCountdownNumbers", "SetCooldown",
    "SetSwipeColor", "SetDrawEdge", "SetTexCoord", "SetJustifyH", "SetJustifyV", "SetFont", "SetTextColor",
    "SetShadowOffset", "SetDesaturated", "SetBlendMode", "SetMinMaxValues", "SetValue", "SetStatusBarTexture",
    "SetStatusBarColor", "SetColorTexture", "SetReverse", "SetReverseFill", "SetMouseClickEnabled",
    "SetMouseMotionEnabled", "SetCountdownMillisecondsThreshold", "SetSwipeTexture", "SetFrameStrata", "SetOwner",
    "Clear", "SetAtlas", "AddMaskTexture", "RemoveMaskTexture", "SetText",
}) do
    Widget[name] = Widget[name] or function() end
end
_G.CreateFrame = function(frameType, _, parent)
    return setmetatable({ _shown = true, _parent = parent, _objectType = frameType,
        _frameLevel = parent and parent:GetFrameLevel() + 1 or 1 }, Widget)
end
_G.Enum = { StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 } }

-- Aura API stub: Classic filter semantics, |PLAYER keeps the player's own casts ------------
local world, exists = {}, {}
local function UnitList(unit) world[unit] = world[unit] or {}; return world[unit] end
local function Matches(aura, filter)
    if filter:find("HARMFUL", 1, true) then
        if aura.isHarmful ~= true then return false end
    elseif aura.isHelpful ~= true then
        return false
    end
    if filter:find("|PLAYER", 1, true) and aura.mine ~= true then return false end
    return true
end
_G.UnitExists = function(unit) return exists[unit] ~= false end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitInRange = function() return true, true end
_G.UnitCanAssist = function() return true end
_G.UnitGUID = function(unit) return "GUID-" .. unit end
_G.GetTime = function() return 50 end
_G.InCombatLockdown = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GameTooltip = setmetatable({}, Widget)
_G.C_Timer = {}
_G.GetSpellInfo = function(spellID) return "Spell" .. tostring(spellID) end
_G.C_UnitAuras = {
    GetAuraSlots = function(unit, filter)
        local list, out = UnitList(unit), {}
        for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = i end end
        return nil, unpack(out)
    end,
    GetAuraDataBySlot = function(unit, slot) return UnitList(unit)[slot] end,
    GetAuraDataByAuraInstanceID = function(unit, id)
        for _, aura in ipairs(UnitList(unit)) do if aura.auraInstanceID == id then return aura end end
        return nil
    end,
    GetAuraDataByIndex = function(unit, index, filter)
        local n = 0
        for _, aura in ipairs(UnitList(unit)) do
            if Matches(aura, filter) then n = n + 1; if n == index then return aura end end
        end
        return nil
    end,
}
_G.AuraUtil = {}
_G.MSUF_DB = { general = {}, auras3 = { enabled = true, shared = {}, perUnit = {} } }

local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
manifest.LoadSelected(root, flavor, namespace, {
    "Game/Shared/Initialize.lua",
    "State/MSUF_AuraDefaults.lua",
    "Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua", "Game/Classic/Auras/MSUF_Auras3_DataShared.lua",
    "Game/Classic/Auras/MSUF_Auras3_Visuals.lua", "Game/Classic/Auras/MSUF_Auras3_Features.lua",
    "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    "Game/Classic/Auras/MSUF_Auras3_Buttons.lua", "Game/Classic/Auras/MSUF_Auras3_Filters.lua",
    "Game/Classic/Auras/MSUF_Auras3_FrameVisuals.lua", "Game/Classic/Auras/MSUF_Auras3_Lanes.lua",
    "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua", "Game/Classic/Auras/MSUF_Auras3_Requests.lua",
    "UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua",
})
assert(registered, "the Classic aura element did not register")
local A3 = namespace.MSUF_Auras3
local GF = assert(namespace.GF and namespace.GF.CompileCornerIndicators, "group corner compiler missing") and namespace.GF
local Lanes = assert(A3._ClassicBackend and A3._ClassicBackend.Lanes, "Classic lane module missing")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = flavor .. ": " .. message end
end

-- Fixtures --------------------------------------------------------------------------------
local function Aura(id, spellId, helpful, mine)
    return { auraInstanceID = id, spellId = spellId, name = "Spell" .. spellId, icon = id, duration = 1800,
        expirationTime = 1850, isHelpful = helpful, isHarmful = not helpful, mine = mine,
        sourceUnit = mine and "player" or "party2", isFromPlayerOrPlayerPet = mine }
end
local function SetAuras(unit, auras)
    local list = UnitList(unit)
    for i = #list, 1, -1 do list[i] = nil end
    for i = 1, #auras do list[i] = auras[i] end
end
local function Corners(mode, filter, spells)
    return GF.CompileCornerIndicators({
        ciEnabled = true, ciSlotTL = "custom", ciSlotTR = "none", ciSlotBL = "none", ciSlotBR = "none", ciSlotC = "none",
        ciCustomTL = { spells = spells, mode = mode, filter = filter, r = 1, g = 0.2, b = 0.1 },
    }, "party")
end
local function GroupFrame(unit, corners)
    local frame = setmetatable({ _shown = true, MSUFUnitKey = unit, _msufIsGroupFrame = true,
        _msufGFKind = "party", MSUFSpec = { scope = "group", cornerIndicators = corners } }, Widget)
    registered.Create(frame)
    registered.Apply(frame)
    assert(registered.Enable(frame) == true, "the group aura element did not enable for " .. unit)
    return frame
end
local function Lane(frame)
    return assert(frame._msufA3State.lanes.cornerIndicator1, "the corner Custom Spell lane did not compile")
end
-- The corner square on screen: the lane's first button, shown, with its colour swatch.
local function Lit(frame)
    local lane = Lane(frame)
    local button = lane[1]
    local swatch = button and button._msufA3ClassicIndicatorSwatch
    return button ~= nil and lane.visible == 1 and button._msufA3Shown == true and button._shown == true
        and swatch ~= nil and swatch._shown == true
end
local function Added(aura) return { addedAuras = { aura } } end
local function Removed(id) return { removedAuraInstanceIDs = { id } } end
local function UnitAura(frame, unit, payload) registered.Update(frame, "UNIT_AURA", unit, payload) end

-- 1. Show when missing, Buff (any caster) ---------------------------------------------------
-- Power Word: Fortitude (21562): the corner must light while the member lacks it.
SetAuras("party1", { Aura(31, 6673, true, false) })
local missingAny = GroupFrame("party1", Corners("missing", "HELPFUL", "21562"))
local lane = Lane(missingAny)
Check(lane.config.showWhenMissing == true, "the compiled corner lane does not carry When: Show when missing")
Check(lane.config.naturalOrder ~= true, "a missing-mode corner lane would render inline from its scan")
Check(Lit(missingAny), "Show when missing: the corner stayed dark while the member lacks the buff")
local button = lane[1]
Check(button and button.auraInstanceID == nil, "the missing indicator claims an aura (tooltip of an absent aura)")
local swatch = button and button._msufA3ClassicIndicatorSwatch
Check(swatch and swatch._r == 1 and swatch._g == 0.2 and swatch._b == 0.1,
    "the missing indicator does not wear the slot's Custom Color")
-- The buff lands (UNIT_AURA delta): the corner goes dark.
local fort = Aura(32, 21562, true, false)
SetAuras("party1", { Aura(31, 6673, true, false), fort })
UnitAura(missingAny, "party1", Added(fort))
Check(not Lit(missingAny), "Show when missing: the corner stayed lit after the buff was applied (delta)")
-- An unrelated aura change keeps it dark.
local other = Aura(33, 1243, true, false)
SetAuras("party1", { Aura(31, 6673, true, false), fort, other })
UnitAura(missingAny, "party1", Added(other))
Check(not Lit(missingAny), "Show when missing: an unrelated aura relit the corner while the buff is up")
-- The buff falls off (UNIT_AURA delta): the corner lights again.
SetAuras("party1", { Aura(31, 6673, true, false), other })
UnitAura(missingAny, "party1", Removed(32))
Check(Lit(missingAny), "Show when missing: the corner stayed dark after the buff fell off (delta)")
-- Full rescans agree with the deltas.
SetAuras("party1", { fort })
A3.RenderFrame(missingAny)
Check(not Lit(missingAny), "Show when missing: a full scan lit the corner while the buff is up")
SetAuras("party1", {})
A3.RenderFrame(missingAny)
Check(Lit(missingAny), "Show when missing: a full scan left the corner dark with no aura at all")

-- 2. The Filter decides presence exactly as in present mode ----------------------------------
-- Buff (cast by me): another priest's Fortitude does not count as mine.
SetAuras("party2", { Aura(41, 21562, true, false) })
local missingMine = GroupFrame("party2", Corners("missing", "HELPFUL|PLAYER", "21562"))
Check(Lit(missingMine), "Buff (cast by me): another caster's copy hid the missing indicator")
local ownFort = Aura(42, 21562, true, true)
SetAuras("party2", { Aura(41, 21562, true, false), ownFort })
UnitAura(missingMine, "party2", Added(ownFort))
Check(not Lit(missingMine), "Buff (cast by me): the player's own buff did not hide the missing indicator (delta)")
SetAuras("party2", { Aura(41, 21562, true, false) })
UnitAura(missingMine, "party2", Removed(42))
Check(Lit(missingMine), "Buff (cast by me): the indicator stayed dark after the player's buff fell off")
-- Debuff (cast by me): a buff with the same ID is not the debuff, another caster's debuff is not mine.
SetAuras("party3", { Aura(51, 589, true, true), Aura(52, 589, false, false) })
local missingDebuff = GroupFrame("party3", Corners("missing", "HARMFUL|PLAYER", "589"))
Check(Lit(missingDebuff), "Debuff (cast by me): a buff or another caster's debuff hid the missing indicator")
SetAuras("party3", { Aura(51, 589, true, true), Aura(52, 589, false, false), Aura(53, 589, false, true) })
A3.RenderFrame(missingDebuff)
Check(not Lit(missingDebuff), "Debuff (cast by me): the player's own debuff did not hide the missing indicator")

-- 3. Present mode is unchanged ------------------------------------------------------------
SetAuras("party4", {})
local present = GroupFrame("party4", Corners("present", "HELPFUL", "21562"))
Check(Lane(present).config.showWhenMissing ~= true, "a present-mode corner lane carries Show when missing")
Check(not Lit(present), "Show when present: the corner lit with no aura")
local fort4 = Aura(61, 21562, true, false)
SetAuras("party4", { fort4 })
UnitAura(present, "party4", Added(fort4))
Check(Lit(present) and Lane(present)[1].auraInstanceID == 61, "Show when present: the corner did not light for the buff")

-- 4. Switching the slot from present to missing re-renders the frame ------------------------
present.MSUFSpec = { scope = "group", cornerIndicators = Corners("missing", "HELPFUL", "21562") }
A3.RenderFrame(present)
Check(not Lit(present), "present -> missing: the corner stayed lit while the buff is up")
SetAuras("party4", {})
UnitAura(present, "party4", Removed(61))
Check(Lit(present), "present -> missing: the corner did not light when the buff fell off")
Check(Lane(present)[1].auraInstanceID == nil, "present -> missing: the indicator kept the old aura's ID")

-- 5. A unit that does not exist shows no indicator -----------------------------------------
exists.party5 = false
local gone = GroupFrame("party5", Corners("missing", "HELPFUL", "21562"))
Check(not Lit(gone), "Show when missing: a corner lit on a unit that does not exist")

-- 6. The missing render allocates nothing --------------------------------------------------
local missingLane = Lane(missingAny)
Lanes.RenderLane(missingLane, "party1")
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 50 do
    Lanes.RenderLane(missingLane, "party1")
    Lanes.ClearLane(missingLane)
end
Lanes.RenderLane(missingLane, "party1")
local allocated = (collectgarbage("count") - before) * 1024
collectgarbage("restart")
Check(allocated == 0, string.format("the missing render allocated %d bytes over 51 renders", allocated))
Check(Lit(missingAny), "precondition: the allocation loop did not end on a lit corner")

if #failures > 0 then
    error("rc1 F (corner Show when missing on Classic):\n  " .. table.concat(failures, "\n  "))
end
print("rc1_f_smoke: ok (" .. flavor .. ": corner Custom Spell Show when missing follows the slot's Filter)")
