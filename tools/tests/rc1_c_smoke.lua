-- rc1_c_smoke.lua <repoRoot>
--
-- rc1 package C: castbars, interrupt readiness and one aura effect.
--
-- A. DR1-1 Interrupt readiness accepts an active override on the player's
--    spell bank, as Blizzard's own interrupt list does
--    (Blizzard_CooldownBroadcaster.lua:133 IsSpellKnownOrInSpellBook). A
--    Demonology warlock's Axe Toss (119914) is Command Demon's override while
--    the Felguard is out; C_SpellBook.IsSpellKnown never reports it. A priest
--    without Silence still tracks nothing, the Felhunter's Spell Lock is still
--    asked of the pet bank only, and a client without IsSpellKnownOrInSpellBook
--    keeps the IsSpellKnown answer.
-- B. DR1-2 The castbar glow overlay (a white texture over the fill) is masked
--    with the rounded or slanted castbar surface: when rounded is applied after
--    the overlay exists, when rounded is applied before the first glowing cast
--    (the overlay is built then, out of combat, so an in-combat first cast is
--    already masked), and when the glow is turned on later. Turning rounded off
--    removes the mask. Glow ticks after that add no regions and no masks.
-- C. CX3-03 A Custom aura "Name Overlay" frame effect copies the unit frame's
--    name. The native slot builds its AuraButton once and reuses it, so after a
--    target change the overlay showed the previous unit's name. The real name
--    writer (MSUF_UF_Text_Runtime.lua) now refreshes it. The button is sealed
--    after initializeFrame and refuses descendant writes while auras are
--    secret: then nothing is written and the frame waits for the restriction to
--    end. Secret names are passed through opaquely (strict secret watch).
--
-- The spell book stub follows ui\ptr2 SpellBookDocumentation.lua:684-716
-- (IsSpellKnown has no override argument; IsSpellKnownOrInSpellBook(spellID,
-- spellBank = Player, includeOverrides = true)). The sealed AuraButton follows
-- Blizzard_AuraContainerFrameProviders.lua:79-85 (initializer, then access
-- restrictions) and Blizzard_AuraContainerShared.lua:108
-- (DenyTaintedAccessWhenAurasAreSecret).
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local core = root .. "/MidnightSimpleUnitFrames/"

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

local function Load(relative, ns)
    return assert(loadfile(core .. relative))("MidnightSimpleUnitFrames", ns)
end

local function ExportInto(ns)
    ns.ExportPublic = function(name, value)
        _G[name] = value
        ns.Public[(name:gsub("^MSUF_", ""))] = value
        return value
    end
end

---------------------------------------------------------------------------
-- A. DR1-1 interrupt readiness and spell-book overrides
---------------------------------------------------------------------------
local function SpellBook(model, withOverrideApi)
    local function Bank(bank)
        Check(bank == nil or bank == 0 or bank == 1, "unknown spell bank " .. tostring(bank))
        return bank == 1 and model.pet or model.learned
    end
    local book = {}
    function book.IsSpellKnown(spellID, bank, extra)
        Check(type(spellID) == "number" and extra == nil, "IsSpellKnown takes (spellID, spellBank)")
        if bank == 1 then model.petReads = model.petReads + 1 end
        return Bank(bank)[spellID] == true
    end
    if withOverrideApi then
        function book.IsSpellKnownOrInSpellBook(spellID, bank, includeOverrides)
            Check(type(spellID) == "number", "IsSpellKnownOrInSpellBook needs a spell ID")
            if bank == 1 then model.petOverrideReads = model.petOverrideReads + 1 end
            local learned = Bank(bank)
            if learned[spellID] then return true end
            -- The player book also lists unlearned off-spec spells
            -- (ui\ptr2 Blizzard_SpellBookCategory.lua:197-214 isOffSpec).
            if bank ~= 1 and model.inBook[spellID] then return true end
            if includeOverrides == false or bank == 1 then return false end
            for base, override in pairs(model.overrides) do
                if override == spellID and learned[base] then return true end
            end
            return false
        end
    end
    return book
end

local function ResolveInterrupt(case)
    local model = { learned = case.learned or {}, pet = case.pet or {}, overrides = case.overrides or {},
        inBook = case.inBook or {}, petReads = 0, petOverrideReads = 0 }
    _G.MSUF_DB = { general = { kickReadyShowTarget = true, kickReadyShowFocus = false, kickReadyShowBoss = false,
        kickReadyShowArena = false, enableFocusKickIcon = false, kickReadyStyle = "border" } }
    _G.MSUF_EnsureDB = function() end
    _G.UnitClass = function() return case.class, case.class end
    _G.C_SpecializationInfo = case.spec and {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return case.spec end,
    } or nil
    _G.GetSpecialization, _G.GetSpecializationInfo = nil, nil
    _G.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
    _G.C_SpellBook = SpellBook(model, case.overrideApi ~= false)
    _G.IsSpellKnown, _G.IsPlayerSpell = nil, nil
    _G.GetTime = function() return 100 end
    _G.issecretvalue = function() return false end
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.C_CurveUtil = {
        EvaluateColorFromBoolean = function(value, ifTrue, ifFalse) return value and ifTrue or ifFalse end,
        EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse) return value and ifTrue or ifFalse end,
    }
    _G.C_Timer = { After = function() end }
    local function Cooldown()
        return { GetRemainingDuration = function() return 0 end, IsZero = function() return true end,
            GetEndTime = function() return 0 end }
    end
    _G.C_Spell = { GetSpellCooldownDuration = function() return Cooldown() end,
        IsSpellUsable = function() return true, false end }
    _G.CreateFrame = function()
        local widget = {}
        for _, method in ipairs({ "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents", "SetScript", "Show",
            "SetSize", "SetAlpha", "SetDrawSwipe", "SetDrawEdge", "SetDrawBling", "SetHideCountdownNumbers", "Clear",
            "SetCooldownFromDurationObject" }) do
            widget[method] = function() end
        end
        return widget
    end
    _G.geterrorhandler = function() return error end
    _G.MSUF_ApplyCastbarOutline = function() end
    local ns = { Public = {}, Client = case.client or {} }
    ExportInto(ns)
    ns.Scheduler = { ScheduleAfter = function() end }
    ns.Util = { InCombat = function() return false end }
    ns.Public.GetCastbarTexture = function() return "Interface\\MSUF\\Lucent" end
    for _, file in ipairs({ "Kernel/MSUF_Boundary.lua", "Runtime/MSUF_HostAPI.lua", "Castbars/MSUF_CastbarUtils.lua",
        "Castbars/MSUF_InterruptReady.lua" }) do
        Load(file, ns)
    end
    _G.MSUF_KickReady_RefreshAll()
    return _G.MSUF_KickReady_GetSpellID(), ns.KickReady.SlotCount(), model
end

local COMMAND_DEMON, AXE_TOSS, SPELL_LOCK, SILENCE = 119898, 119914, 19647, 15487

local spell, slots = ResolveInterrupt({ class = "WARLOCK", spec = 266,
    learned = { [COMMAND_DEMON] = true }, overrides = { [COMMAND_DEMON] = AXE_TOSS } })
Check(spell == AXE_TOSS and slots == 1,
    ("Demonology Axe Toss (Command Demon override) not tracked: spell=%s slots=%s"):format(tostring(spell), tostring(slots)))

spell, slots = ResolveInterrupt({ class = "WARLOCK", spec = 266, learned = { [COMMAND_DEMON] = true } })
Check(spell == nil and slots == 0, "Demonology without the Felguard override tracks a spell it cannot cast")

spell, slots = ResolveInterrupt({ class = "PRIEST", spec = 258 })
Check(spell == nil and slots == 0, "a priest without Silence shows interrupt readiness")
spell, slots = ResolveInterrupt({ class = "PRIEST", spec = 258, learned = { [SILENCE] = true } })
Check(spell == SILENCE and slots == 1, "a priest with Silence lost interrupt readiness")

local model
spell, slots, model = ResolveInterrupt({ class = "WARLOCK", spec = 265, learned = { [SPELL_LOCK] = true } })
Check(spell == nil and slots == 0, "Spell Lock in the player's book admitted without a Felhunter")
Check(model.petReads > 0 and model.petOverrideReads == 0, "the Felhunter check left the pet bank's IsSpellKnown")
spell, slots = ResolveInterrupt({ class = "WARLOCK", spec = 265, pet = { [SPELL_LOCK] = true } })
Check(spell == SPELL_LOCK and slots == 1, "the current Felhunter's Spell Lock is missing")

spell, slots = ResolveInterrupt({ class = "ROGUE", client = { IsVanilla = true, IsClassic = true }, overrideApi = false,
    learned = { [1766] = true } })
Check(spell == 1766 and slots == 1, "a client without IsSpellKnownOrInSpellBook lost the IsSpellKnown answer")
spell, slots = ResolveInterrupt({ class = "ROGUE", client = { IsVanilla = true, IsClassic = true }, overrideApi = false })
Check(spell == nil and slots == 0, "an unlearned Kick shows readiness on a client without the override API")
spell, slots = ResolveInterrupt({ class = "WARRIOR", client = { IsForever = true }, learned = { [6552] = true } })
Check(spell == 6552 and slots == 1, "WoW Forever Pummel missing")
-- Only the spec-keyed primary accepts overrides: off-spec spells in the book
-- (Avenger's Shield for a Retribution paladin, Silence for a Holy priest)
-- and Classic clients keep the learned-only answer.
local REBUKE, AVENGERS_SHIELD = 96231, 31935
spell, slots = ResolveInterrupt({ class = "PALADIN", spec = 70, learned = { [REBUKE] = true },
    inBook = { [AVENGERS_SHIELD] = true } })
Check(spell == REBUKE and slots == 1, ("an off-spec Avenger's Shield in the book counted as a second interrupt: slots=%s"):format(tostring(slots)))
spell, slots = ResolveInterrupt({ class = "PRIEST", spec = 257, inBook = { [SILENCE] = true } })
Check(spell == nil and slots == 0, "an unlearned off-spec Silence in the book showed interrupt readiness")
spell, slots = ResolveInterrupt({ class = "ROGUE", client = { IsMists = true, IsClassic = true }, inBook = { [1766] = true } })
Check(spell == nil and slots == 0, "a Classic client admitted an unlearned Kick from the book")
print("rc1_c_smoke A (DR1-1): Demonology Axe Toss tracked; Silence, Felhunter and Classic fallbacks kept")

---------------------------------------------------------------------------
-- B. DR1-2 castbar glow overlay and the rounded/slanted surface mask
---------------------------------------------------------------------------
local counts = { textures = 0, masks = 0, adds = 0 }
local inCombat = false
local Region = {}
Region.__index = Region
local function NewRegion(kind, parent)
    return setmetatable({ kind = kind, parent = parent, shown = true, alpha = 1, masks = {}, points = {} }, Region)
end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:IsShown() return self.shown end
function Region:SetAlpha(alpha) self.alpha = alpha end
function Region:GetParent() return self.parent end
function Region:SetTexture(path) self.texture = path end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints(target) self.points = { all = target } end
function Region:GetFrameLevel() return 5 end
for _, method in ipairs({ "SetColorTexture", "SetBlendMode", "SetVertexColor", "SetPoint", "SetSnapToPixelGrid",
    "SetTexelSnappingBias", "SetTextureSliceMargins", "SetTextureSliceMode", "EnableMouse", "SetFrameLevel",
    "SetBackdrop", "SetStatusBarTexture" }) do
    Region[method] = function() end
end
function Region:CreateTexture()
    Check(self.kind ~= "texture", "a texture cannot own regions")
    counts.textures = counts.textures + 1
    return NewRegion("texture", self)
end
function Region:CreateMaskTexture()
    Check(self.kind ~= "texture", "a texture cannot own a mask")
    counts.masks = counts.masks + 1
    return NewRegion("mask", self)
end
function Region:AddMaskTexture(mask)
    Check(self.kind == "texture" and mask.kind == "mask", "masks go on textures")
    Check(not self.masks[mask], "the same mask was added twice")
    counts.adds = counts.adds + 1
    self.masks[mask] = true
end
function Region:RemoveMaskTexture(mask)
    Check(self.masks[mask], "removed a mask the texture does not carry")
    self.masks[mask] = nil
end
function Region:GetStatusBarTexture() return self.fill end

local function MaskOf(texture)
    local found
    for mask in pairs(texture.masks) do
        Check(found == nil, "a castbar texture carries two masks")
        found = mask
    end
    return found
end

local function SurfaceMasked(frame, texture)
    local mask = texture and MaskOf(texture)
    local fillMask = MaskOf(frame.statusBar.fill)
    return mask ~= nil and fillMask ~= nil and mask.points.all == frame.statusBar
        and mask.texture == fillMask.texture
end

local function NewCastbar()
    local frame = NewRegion("frame")
    local statusBar = NewRegion("statusbar", frame)
    statusBar.fill = NewRegion("texture", statusBar)
    frame.statusBar = statusBar
    frame.backgroundBar = NewRegion("texture", frame)
    frame.latencyBar = NewRegion("texture", statusBar)
    frame.unit = "player"
    return frame
end

do
    _G.MSUF_DB = { general = { castbarShowGlow = true }, bars = { roundedFramesEnabled = true, roundedCastbars = true } }
    _G.MSUF__castTimeGlobalRev = 1
    _G.MSUF_EnsureDB = function() end
    _G.issecretvalue = function() return false end
    _G.InCombatLockdown = function() return inCombat end
    _G.GetTime = function() return 100 end
    _G.GetTimePreciseSec = nil
    _G.C_Timer = { After = function() end }
    _G.Enum = {}
    _G.CreateFrame = function(_, _, parent) return NewRegion("frame", parent) end
    _G.MSUF_ApplyCastbarOutline = function() end
    _G.MSUF_PixelLayoutRegion = nil
    local ns = { Public = {} }
    ExportInto(ns)
    Load("UnitFrames/Effects/MSUF_UF_RoundedSurface.lua", ns)
    Load("Castbars/MSUF_CastbarUtils.lua", ns)
    Load("Castbars/MSUF_CastbarRounded.lua", ns)
    local ApplyAll, Glow = ns.RoundedCastbarsApplyAll, _G.MSUF_ApplyCastbarGlowFade
    local function SetGlow(enabled)
        _G.MSUF_DB.general.castbarShowGlow = enabled
        _G.MSUF__castTimeGlobalRev = _G.MSUF__castTimeGlobalRev + 1
    end

    -- 1. The overlay exists (a glowing cast before rounded was on), then the
    --    rounded castbar pass runs (MSUF.RoundedCastbarsApplyAll per castbar).
    local first = NewCastbar()
    _G.MSUF_PlayerCastbar = first
    Glow(first, 0.5, 5)
    local overlay = Check(first.statusBar._msufGlowOverlay, "the glow overlay was not created")
    Check(overlay.shown and overlay.points.all == first.statusBar.fill, "the glow overlay does not cover the fill")
    ApplyAll(true)
    Check(SurfaceMasked(first, first.statusBar.fill), "the rounded fill is not masked")
    Check(SurfaceMasked(first, overlay), "rounded castbar: the glow overlay spills past the rounded surface")

    -- 2. Rounded is applied before the first glowing cast: the overlay is
    --    built then (out of combat), so a first cast in combat is masked.
    ApplyAll(false)
    local second = NewCastbar()
    _G.MSUF_PlayerCastbar = second
    ApplyAll(true)
    inCombat = true
    Glow(second, 0.5, 5)
    overlay = Check(second.statusBar._msufGlowOverlay, "no glow overlay on an in-combat cast")
    Check(overlay.shown and SurfaceMasked(second, overlay), "a first glowing cast in combat is not masked")
    local before = { counts.textures, counts.masks, counts.adds }
    for tick = 1, 50 do Glow(second, 5 - tick * 0.1, 5) end
    Check(counts.textures == before[1] and counts.masks == before[2] and counts.adds == before[3],
        "glow ticks built regions or masks")
    inCombat = false

    -- 3. Glow off when rounded is applied: nothing is built. Glow turned on
    --    later: the overlay joins the mask when the first cast builds it.
    ApplyAll(false)
    SetGlow(false)
    local third = NewCastbar()
    _G.MSUF_PlayerCastbar = third
    ApplyAll(true)
    Check(third.statusBar._msufGlowOverlay == nil, "a glow overlay was built while the glow is off")
    SetGlow(true)
    Glow(third, 0.5, 5)
    overlay = Check(third.statusBar._msufGlowOverlay, "no glow overlay after the glow was turned on")
    Check(SurfaceMasked(third, overlay), "an overlay built after the rounded pass is not masked")

    -- 3b. Glow switched on after the rounded pass: the menu runs the castbar
    --     texture pass (Castbars_Core UpdateCastbarTextures), which builds and
    --     masks the overlay before the first cast, even while the cast-time
    --     revision that refreshes the glow cache has not been bumped yet.
    SetGlow(false)
    local thirdB = NewCastbar()
    _G.MSUF_PlayerCastbar = thirdB
    ApplyAll(true)
    Check(thirdB.statusBar._msufGlowOverlay == nil, "a glow overlay was built while the glow is off")
    _G.MSUF_DB.general.castbarShowGlow = true
    local refreshRoundedGlow = Check(ns.Castbars and ns.Castbars.RefreshRoundedGlow,
        "the rounded castbar module exports no glow refresh for the castbar texture pass")
    if refreshRoundedGlow then refreshRoundedGlow() end
    overlay = Check(thirdB.statusBar._msufGlowOverlay, "the castbar texture pass did not build the glow overlay")
    Check(overlay and SurfaceMasked(thirdB, overlay),
        "glow switched on after the rounded pass: the overlay is not masked before the first cast")
    inCombat = true
    Glow(thirdB, 0.5, 5)
    Check(overlay and SurfaceMasked(thirdB, overlay), "a first in-combat cast after switching the glow on is not masked")
    inCombat = false
    local coreSource = assert(io.open(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Core.lua", "rb")):read("*a")
    local textureFn = coreSource:match("local function UpdateCastbarTextures%(%)(.-)ExportPublic%(\"MSUF_UpdateCastbarTextures\"")
    Check(textureFn and textureFn:find("RefreshRoundedGlow", 1, true),
        "the castbar texture pass does not refresh the rounded glow overlay")
    _G.MSUF_PlayerCastbar = third
    overlay = third.statusBar._msufGlowOverlay
    SetGlow(true)

    -- 4. Rounded off: every castbar mask, the overlay's included, comes off.
    ApplyAll(false)
    Check(next(overlay.masks) == nil and next(third.statusBar.fill.masks) == nil, "rounded off left a mask behind")
    Glow(third, 0.1, 5)
    Check(overlay.shown, "the square castbar lost its glow")

    -- 5. Slanted castbars use their own mask; the overlay follows it.
    _G.MSUF_DB.bars.roundedFramesEnabled, _G.MSUF_DB.bars.roundedCastbars = false, false
    _G.MSUF_DB.bars.slantedCastbars = true
    local fourth = NewCastbar()
    _G.MSUF_PlayerCastbar = fourth
    ApplyAll(true)
    overlay = Check(fourth.statusBar._msufGlowOverlay, "slanted castbar: no glow overlay")
    Check(SurfaceMasked(fourth, overlay), "slanted castbar: the glow overlay spills past the slanted surface")
    Check(tostring(MaskOf(overlay).texture):find("slanted", 1, true), "slanted castbar: overlay not on the slanted mask")
    ApplyAll(false)
    Check(next(overlay.masks) == nil, "slanted off left the overlay masked")
    _G.MSUF_PlayerCastbar = nil
end
print("rc1_c_smoke B (DR1-2): castbar glow overlay masked on rounded and slanted castbars, unmasked when off")

---------------------------------------------------------------------------
-- C. CX3-03 Name Overlay follows the unit frame's name writer
---------------------------------------------------------------------------
do
    local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
    Secrets.Install()
    local aurasSecret, supportsRestrictionEvent = false, true
    local topFrames = {}
    local W = {}
    W.__index = W
    -- DenyTaintedAccessWhenAurasAreSecret: once sealed, the button and every
    -- descendant refuse addon access while aura data is secret.
    local function Restricted(region)
        local owner = region
        while owner do
            if owner.sealed and aurasSecret then return true end
            owner = owner.parent
        end
        return false
    end
    local function Guard(region, method)
        if Restricted(region) then error(method .. " on a restricted AuraButton descendant", 3) end
    end
    local function Widget(kind, parent)
        return setmetatable({ kind = kind, parent = parent, shown = true, text = "", events = {}, scripts = {} }, W)
    end
    for _, method in ipairs({ "EnableMouse", "SetClipsChildren", "ClearAllPoints", "SetAllPoints", "SetPoint",
        "SetTextColor", "SetAlpha", "SetFrameLevel", "SetFrameStrata", "SetFont", "SetTexture", "SetVertexColor",
        "SetBlendMode", "SetJustifyH", "SetJustifyV", "SetShadowColor", "SetShadowOffset" }) do
        W[method] = function(self) Guard(self, method) end
    end
    function W:Show() Guard(self, "Show"); self.shown = true end
    function W:Hide() Guard(self, "Hide"); self.shown = false end
    function W:SetShown(shown) Guard(self, "SetShown"); self.shown = shown end
    function W:IsShown() return self.shown end
    function W:SetText(text) Guard(self, "SetText"); self.text = text end
    function W:GetText() Guard(self, "GetText"); return self.text end
    function W:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
    function W:GetParent() return self.parent end
    function W:GetFrameLevel() return 10 end
    function W:GetFrameStrata() return "MEDIUM" end
    function W:CanBeAccessedInContext() return not Restricted(self) end
    function W:CreateFontString() Guard(self, "CreateFontString"); return Widget("fontstring", self) end
    function W:CreateTexture() Guard(self, "CreateTexture"); return Widget("texture", self) end
    function W:SetScript(script, callback)
        local owner = self
        while owner do
            Check(not owner.sealed, "SetScript on a sealed AuraButton tree")
            owner = owner.parent
        end
        self.scripts[script] = callback
    end
    function W:RegisterEvent(event) self.events[event] = true end
    function W:UnregisterEvent(event) self.events[event] = nil end
    function W:UnregisterAllEvents() for event in pairs(self.events) do self.events[event] = nil end end
    _G.CreateFrame = function(_, _, parent)
        local frame = Widget("frame", parent)
        if parent == nil then topFrames[#topFrames + 1] = frame end
        return frame
    end
    _G.MSUF_SetFontChecked = function(region, ...) region:SetFont(...) return true end
    _G.MSUF_ApplyResolvedFont = nil
    _G.MSUF_AuraReadParentFrameStrata = function(frame) return frame:GetFrameStrata() end
    _G.MSUF_AuraSyncFrameStrata = function(frame, strata) frame:SetFrameStrata(strata) end
    _G.MSUF_RoundedUF_OnSpellIndicatorEdge = nil
    _G.MSUF_DB = { general = {} }

    local names = { target = "Alice", focus = "Dana" }
    local UF = { elements = {}, Layers = {} }
    function UF.RegisterElement(name, element) UF.elements[name] = element end
    local Text = {
        tonumber = tonumber, type = type, format = string.format, floor = math.floor, max = math.max,
        REVERSE_HEALTH_MODE = {}, ABSORB_HEALTH_MODE_BASE = {}, EMPTY_EVENTS = {}, POWER_EVENTS = {},
        POWER_EVENTS_FREQUENT = {}, SCALE_100 = 100,
        UnitName = function(unit) return names[unit] end,
        ApplyNameTextColor = function() end,
        SetShownCached = function(region, shown)
            if region and region._msufShown ~= shown then
                region:SetShown(shown)
                region._msufShown = shown
            end
        end,
    }
    local ns = { UF = UF, UFText = Text, Public = {}, MSUF_Auras3 = { SpellIndicators = {} },
        NumberFormat = { Register = function() end },
        Client = { SupportsEvent = function(event)
            return event == "ADDON_RESTRICTION_STATE_CHANGED" and supportsRestrictionEvent
        end } }
    ExportInto(ns)
    local runtimePath = core .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua"
    local effectsPath = core .. "Auras3/MSUF_Auras3_SpellIndicators_Effects.lua"
    Load("Libs/MSUFUnitFrames/MSUF_UF_Apply.lua", ns)
    Load("UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua", ns)
    Load("UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua", ns)
    Load("Auras3/MSUF_Auras3_SpellIndicators_Config.lua", ns)
    Load("Auras3/MSUF_Auras3_SpellIndicators_Effects.lua", ns)
    local A3 = ns.MSUF_Auras3
    local effects = A3.SpellIndicatorModules.Effects(A3.SpellIndicatorModules.Config())
    local NameText = Check(UF.elements.NameText, "the real NameText element did not register")

    local function UnitFrame(unit)
        local frame = Widget("frame")
        frame.MSUFUnitKey = unit
        frame.nameText = Widget("fontstring", frame)
        frame.hpBar = Widget("frame", frame)
        frame.hpBar.GetStatusBarTexture = function(bar) return bar end
        NameText.Update(frame, "PLAYER_TARGET_CHANGED", unit)
        return frame
    end
    -- Blizzard_AuraContainerFrameProviders.lua:79-85: initializer, then seal.
    local function NativeButton(frame, effect)
        local button = Widget("aurabutton", Widget("frame", frame))
        Check(effects.ApplyAlwaysButtonFrameEffect(button, { frameEffect = effect }, frame), "effect not applied")
        button.sealed = true
        return button
    end
    local NAME_OVERLAY = { type = "namecolor", color = { 1, 0.2, 0.2, 1 } }

    local target = UnitFrame("target")
    Check(target.nameText.text == "Alice", "the name writer did not run")
    local button = NativeButton(target, NAME_OVERLAY)
    local overlay = Check(button._msufA3SpellIndicatorNameOverlay, "no Name Overlay")
    Check(overlay.text == "Alice" and overlay.shown, "the Name Overlay did not copy the name")

    -- The same aura on the next target: the slot keeps its button (no initializer).
    names.target = "Bob"
    NameText.Update(target, "PLAYER_TARGET_CHANGED", "target")
    Check(overlay.text == "Bob", "Name Overlay kept the previous target's name: " .. tostring(overlay.text))

    -- A secret name reaches the overlay untouched (strict watch on both files).
    local stop = Secrets.Watch({ effectsPath, runtimePath }, { strict = true })
    local secretName = Secrets.New("string")
    names.target = secretName
    NameText.Update(target, "PLAYER_TARGET_CHANGED", "target")
    local violations = stop()
    Check(#violations == 0, "secret name misused:\n" .. table.concat(violations, "\n"))
    Check(rawequal(overlay.text, secretName), "the secret name did not reach the Name Overlay")

    -- Auras secret: the sealed button refuses the write. Nothing is written,
    -- no error, and the frame waits for the restriction to end.
    aurasSecret = true
    names.target = "Carol"
    NameText.Update(target, "PLAYER_TARGET_CHANGED", "target")
    Check(rawequal(overlay.text, secretName), "a restricted Name Overlay was written")
    local retry = Check(topFrames[#topFrames], "no retry after a refused Name Overlay write")
    Check(retry.events.ADDON_RESTRICTION_STATE_CHANGED and retry.scripts.OnEvent, "the retry does not wait for the restriction")
    retry.scripts.OnEvent(retry, "ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
    Check(rawequal(overlay.text, secretName) and retry.events.ADDON_RESTRICTION_STATE_CHANGED,
        "the retry gave up while the restriction holds")
    aurasSecret = false
    retry.scripts.OnEvent(retry, "ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
    Check(overlay.text == "Carol", "the Name Overlay missed the name after the restriction ended")
    Check(next(retry.events) == nil, "the retry stayed registered")

    -- A client without the restriction event retries after combat instead.
    supportsRestrictionEvent = false
    local focus = UnitFrame("focus")
    local focusOverlay = NativeButton(focus, NAME_OVERLAY)._msufA3SpellIndicatorNameOverlay
    aurasSecret = true
    names.focus = "Eve"
    NameText.Update(focus, "PLAYER_FOCUS_CHANGED", "focus")
    Check(focusOverlay.text == "Dana" and retry.events.PLAYER_REGEN_ENABLED, "no PLAYER_REGEN_ENABLED retry")
    aurasSecret = false
    retry.scripts.OnEvent(retry, "PLAYER_REGEN_ENABLED")
    Check(focusOverlay.text == "Eve" and next(retry.events) == nil, "the combat-end retry missed the name")

    -- Effect turned off: the next name write drops the mirror; frames that
    -- never had a Name Overlay carry none.
    effects.ApplyAlwaysButtonFrameEffect(button, { frameEffect = nil }, target)
    Check(target._msufNameTextMirror ~= nil, "the mirror was dropped before the next name write")
    names.target = "Finn"
    NameText.Update(target, "PLAYER_TARGET_CHANGED", "target")
    Check(target._msufNameTextMirror == nil and overlay.text == "Carol", "a removed Name Overlay is still mirrored")
    Check(UnitFrame("target")._msufNameTextMirror == nil, "a frame without a Name Overlay carries a mirror")
end
print("rc1_c_smoke C (CX3-03): Name Overlay follows target changes, secret names and the aura restriction")
