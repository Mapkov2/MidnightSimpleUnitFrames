local root = assert(arg[1], "repository root required")
local path = root .. "/MidnightSimpleUnitFrames/Game/Forever/SwingTimer.lua"
local chunk = assert(loadfile(path))
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public = true
local ns = { Client = { IsForever = false } }
chunk("MidnightSimpleUnitFrames", ns)
assert(ns.SwingTimer == nil, "other clients must have no module or events")

local now, combat, native = 100, false, true
local editModeChanged
_G.MSUF_RegisterAnyEditModeListener = function(callback) editModeChanged = callback end
local offSpeed, rangedSpeed = 2.5, 2.8
local objects, named, driver = {}, {}
local function noop() end
local methods = {}
for _, name in ipairs({
    "SetMovable", "SetClampedToScreen", "RegisterForDrag", "SetAllPoints",
    "SetJustifyH", "SetBackdropBorderColor", "ClearAllPoints", "SetTextColor",
    "StopMovingOrSizing", "StartMoving", "SetUpdateInterval", "SetExpiredText", "SetZeroDurationText",
    "SetTexCoord", "SetClipsChildren", "RegisterForClicks",
    "SetColorTexture", "SetBackdropColor",
}) do methods[name] = noop end
function methods:SetMinMaxValues(a,b) self.minimum,self.maximum=a,b end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(v) self.level=v end
function methods:SetOrientation(v) self.orientation=v end
function methods:SetRotatesTexture(v) self.rotatesTexture=v end
function methods:SetHorizTile(v) self.horizTile=v end
function methods:SetVertTile(v) self.vertTile=v end
function methods:GetStatusBarTexture() return self end
function methods:IsVisible() return self:IsShown() and (not self.parent or self.parent:IsVisible()) end
function methods:GetParent() return self.parent end
function methods:GetWidth() return self.width or 1 end
function methods:SetSize(w,h) self.width, self.height = w,h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetScale(v) self.scale = v end
function methods:GetScale() return self.scale or 1 end
function methods:SetAlpha(v) self.alpha = v end
function methods:GetAlpha() return self.alpha or 1 end
function methods:GetCenter() return self.centerX or 500, self.centerY or 400 end
function methods:SetPoint(...) self.point = {...} end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetFont(...) self.font = {...}; return true end
function methods:SetStatusBarColor(...) self.color = {...} end
function methods:SetStatusBarTexture(v) self.texture = v end
function methods:SetTexture(v) self.texture = v end
function methods:SetBlendMode(v) self.blendMode = v end
function methods:SetVertexColor(...) self.vertexColor = {...} end
function methods:SetReverseFill(v) self.reverse = v end
function methods:SetText(v) self.text = v end
function methods:GetStringWidth() return #(self.text or "") * 7 end
function methods:SetValue(v) self.value = v end
function methods:EnableMouse(v) self.mouse = v end
function methods:SetScript(k,v)
    assert(k ~= "OnUpdate", "no Lua animation/polling driver")
    self.scripts[k] = v
end
function methods:GetScript(k) return self.scripts[k] end
function methods:HookScript(k,v)
    local prior = self.hooks[k]
    self.hooks[k] = prior and function(...) prior(...) v(...) end or v
end
local function Pack(...) return { n = select("#", ...), ... } end
local function FireButton(self, name, ...)
    local handler = self.scripts[name]
    local result = handler and Pack(handler(self, ...))
    if self.hooks[name] then self.hooks[name](self, ...) end
    if result then return unpack(result, 1, result.n) end
end
function methods:Click(button, down)
    if self.enabled == false then return end
    button, down = button or "LeftButton", down == true
    FireButton(self, "PreClick", button, down)
    local result = Pack(FireButton(self, "OnClick", button, down))
    FireButton(self, "PostClick", button, down)
    return unpack(result, 1, result.n)
end
function methods:Show()
    local was = self.shown
    self.shown = true
    if not was and self.hooks.OnShow then self.hooks.OnShow(self) end
end
function methods:Hide() self.shown = false end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown == true end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:RegisterUnitEvent(e,u) assert(u == "player" or u == "target"); self.events[e] = true end
function methods:UnregisterEvent(e) self.events[e] = nil end
function methods:UnregisterAllEvents() self.events = {} end
function methods:SetTimerDuration(d, interpolation, direction)
    self.timer = self.timer or {}
    self.timer.endTime, self.timer.total, self.timer.direction = d.endTime, d.total, direction
end
local function object(name,parent)
    local o = setmetatable({ scripts={}, hooks={}, events={}, name=name, parent=parent, shown=true }, {__index=methods})
    objects[#objects+1] = o
    if name then named[name] = o end
    return o
end
function methods:CreateTexture() return object(nil,self) end
function methods:CreateFontString() return object(nil,self) end
_G.CreateFrame = function(kind,name,parent)
    local o=object(name,parent)
    if kind=="Frame" and not name and not parent then driver=o end
    return o
end
_G.UIParent = object("UIParent")
_G.GetTime = function() return now end
_G.InCombatLockdown = function() return combat end
_G.UnitAffectingCombat = function() return combat end
_G.UnitAttackSpeed = function() return 2, offSpeed, rangedSpeed end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.STANDARD_TEXT_FONT = "test-font"
_G.MSUF_GetFontPath = function() return "global-font" end
_G.GetCVarBool = function(key) assert(key=="showSwingTimer"); return native end
_G.Enum = {
    PlayerSwingType={MainHand=0,OffHand=1,Ranged=2},
    StatusBarTimerDirection={ElapsedTime=0,RemainingTime=1}, StatusBarInterpolation={Immediate=0},
    NumericRuleFormatRounding={Nearest=0}, DurationTextBindingProperty={RemainingDuration=0},
}
_G.C_DurationUtil = {
    CreateDuration=function()
        return { Reset=function(self) self.endTime,self.total=0,0 end,
            SetTimeFromEnd=function(self,e,t) self.endTime,self.total=e,t end }
    end,
    CreateDurationTextBinding=function()
        local b=object()
        function b:SetEnabled(v) self.enabled=v end
        function b:SetFontString(v) self.fontString=v end
        function b:SetDuration(v) self.duration=v end
        function b:SetTextFormat(format,components)
            assert(format=="{}" and components[1].property==0)
        end
        return b
    end,
}
_G.C_StringUtil = { CreateNumericRuleFormatter=function() return {SetBreakpoints=noop} end }
-- Native Forever surfaces used by the range/queued-attack presentation.
local attackable, targetDead, knowsShoot = true, false, true
local nativeMain, nativeOff, nativeRanged
local nativeMeleeCalls = 0
local spellRange, spellRangeCalls = false, 0
local meleeRange, meleeRangeCalls = false, 0
local equippedRangedItem, rangedSubclass, playerClass = 1000, 19, "WARRIOR"
local rangeTicker
_G.INVSLOT_RANGED = 18
_G.Enum.ItemClass = { Weapon = 2 }
_G.Enum.ItemWeaponSubclass = { Bows = 2, Guns = 3, Thrown = 16, Crossbow = 18, Wand = 19 }
_G.GetInventoryItemID = function(unit, slot)
    assert(unit == "player" and slot == INVSLOT_RANGED)
    return equippedRangedItem
end
_G.C_Item = { GetItemInfoInstant = function(id)
    assert(id == equippedRangedItem)
    return nil, nil, nil, nil, nil, 2, rangedSubclass
end }
_G.C_SpellBook = { IsSpellKnown = function() return knowsShoot end }
_G.CheckInteractDistance = function(target, interaction)
    assert(target == "target" and interaction == 3)
    meleeRangeCalls = meleeRangeCalls + 1
    return meleeRange
end
_G.UnitCanAttack = function() return attackable end
_G.UnitIsDeadOrGhost = function() return targetDead end
_G.UnitClass = function() return playerClass, playerClass end
_G.C_Timer = { NewTicker = function(interval, callback)
    assert(interval >= 0.2 and (not rangeTicker or rangeTicker.cancelled), "at most one bounded range ticker")
    rangeTicker = { Tick = callback, Cancel = function(self) self.cancelled = true end }
    return rangeTicker
end }
local nativeRangeChecks={}
_G.C_SwingTimer={
    EnableRangeCheck=function(hand,enabled) nativeRangeChecks[hand]=enabled end,
    IsTargetWithinSwingRange=function(hand)
        if hand < 2 then
            nativeMeleeCalls = nativeMeleeCalls + 1
            if hand == 0 then return nativeMain end
            return nativeOff
        end
        if hand == 2 then return nativeRanged end
    end,
}
_G.C_Spell={
    IsSpellInRange=function(id)
        local expected = playerClass == "HUNTER" and 75 or (rangedSubclass == 19 and 5019 or 7918)
        assert(id == expected, "range fallback must use the attack for the equipped ranged weapon")
        spellRangeCalls = spellRangeCalls + 1
        return spellRange
    end,
    GetSpellName=function(id) return ({[78]="Heroic Strike",[845]="Cleave",[6807]="Maul"})[id] end,
    IsCurrentSpell=function() return false end,
}
local nativeFrames={}
for _, name in ipairs({"MainHand","OffHand","Ranged"}) do
    local frame=object()
    function frame:UpdateShownStateAndRegistration() self:SetShown(native); self.receivingSwings=native end
    _G["SwingTimer"..name.."Frame"]=frame
    frame:UpdateShownStateAndRegistration()
    nativeFrames[#nativeFrames+1]=frame
end
local function event(e,...)
    if driver and driver.events[e] then driver.scripts.OnEvent(driver,e,...) end
end
_G.SetCVar = function(key,value)
    assert(key=="showSwingTimer")
    native=value=="1"
    for _, frame in ipairs(nativeFrames) do frame:UpdateShownStateAndRegistration() end
    event("CVAR_UPDATE",key,value)
end
ns.Client.IsForever=true
local textures={
    ["MSUF Smooth"]="Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\MSUF_Smooth.tga",
    Custom="Interface\\AddOns\\SharedMedia\\Custom.tga",
}
ns.LSM={
    Fetch=function(_,kind,key) return kind=="statusbar" and textures[key] or nil end,
    List=function(_,kind) return kind=="statusbar" and {"MSUF Smooth","Custom"} or {} end,
    HashTable=function(_,kind) return kind=="statusbar" and textures or {} end,
    RegisterCallback=function() end,
}
ns.ExportPublic=function(key,value) _G[key]=value end
-- Kernel/MSUF_Util.lua's pixel layout, which SwingTimer requires: fixtures lay out no pixels.
_G.MSUF_PixelLayoutRegion=function(region,policy,...)
    if type(policy)=="string" then return region[policy](region,...) end
    return region
end
assert(loadfile(root.."/tools/tests/runtime_media_fixture.lua"))().LoadFonts(root, ns)
assert(loadfile(root.."/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))("MSUF",ns)
assert(loadfile(root.."/MidnightSimpleUnitFrames/Kernel/MSUF_Modules.lua"))("MSUF",ns)
_G.MSUF_DB={}
chunk("MSUF",ns)
local swing=assert(ns.SwingTimer)
assert(swing.GetEnabled(), "migrate existing native master switch")
assert(not ns.MSUF_ModulesByKey.SwingTimers.__msufEnabled and not named.MSUF_SwingTimer_main,
    "registration and a checked saved preference do not start the module")
assert(driver.events.PLAYER_ENTERING_WORLD, "login must arrange its own module start")
event("PLAYER_ENTERING_WORLD")
assert(ns.MSUF_ModulesByKey.SwingTimers.__msufEnabled, "world entry starts the saved-enabled module without any menu action")
assert(not native, "native manager must stop receiving swings")
local main,off,ranged=named.MSUF_SwingTimer_main,named.MSUF_SwingTimer_off,named.MSUF_SwingTimer_ranged
assert(main:IsShown() and off:IsShown() and not ranged:IsShown(), "both hands by default")
assert(off.Lane == nil, "the off-hand lane is built only when it is chosen")
for _,frame in ipairs(nativeFrames) do
    assert(not frame:IsShown() and not frame.receivingSwings, "all Blizzard bars suppressed")
    -- SwingTimerMixin:SetIsInEditMode sets the field, then shows the bar.
    -- MSUF never hides a Blizzard bar (its OnHide lays out the bottom managed
    -- container tainted); it makes the bar invisible instead.
    frame.isInEditMode = true
    frame:Show()
    assert(frame:IsShown() and frame.alpha == 0, "Edit Mode cannot make a native bar visible")
    -- Edit Mode exit: Blizzard hides the bar itself (the CVar is off).
    frame.isInEditMode = nil
    frame:UpdateShownStateAndRegistration()
    assert(not frame:IsShown(), "harness: Edit Mode exit hides the native bar")
end
event("PLAYER_SWING",2,0)
event("PLAYER_SWING",3,1)
assert(main.Bar.timer.endTime==102 and off.Bar.timer.endTime==103, "hands retain independent durations")
assert(main.binding.enabled and off.binding.enabled)
assert(main.duration~=off.duration)
local oldMain=main.Bar.timer.endTime
assert(swing.Set("off","enabled",false))
assert(main:IsShown() and not off:IsShown() and not native, "main-only still owns every native bar")
event("PLAYER_SWING",8,1)
assert(off.endsAt==nil and main.endsAt==oldMain, "disabled hand ignores swings")
assert(swing.Set("off","enabled",true))
event("PLAYER_SWING",3,1)
offSpeed=nil
event("WEAPON_SLOT_CHANGED")
assert(not off:IsShown() and off.endsAt==nil, "shield/no offhand clears stale timer")
offSpeed=2.5
event("UNIT_ATTACK_SPEED","player")
assert(off:IsShown())
assert(swing.Set("main","visibility","combat"))
assert(not main:IsShown())
event("PLAYER_SWING",2,0)
assert(main.endsAt==102, "first swing is retained before combat visibility")
combat=true
event("PLAYER_IN_COMBAT_CHANGED")
assert(main:IsShown() and main.binding.enabled)
assert(not swing.SetEnabled(false) and not swing.SetPreview(true), "restricted controls fail in combat")
combat=false
event("PLAYER_IN_COMBAT_CHANGED")
assert(not main:IsShown())
assert(swing.Set("ranged","enabled",true))
assert(ranged:IsShown())
-- Native Forever range can be unavailable with a valid idle target.
assert(swing.Set("ranged","reachOpacity",25))
assert(swing.Set("ranged","reachCheck",true))
assert(nativeRangeChecks[2] and ranged.alpha == 0.25 and ranged.Time.text == "0.0",
    "an idle ranged bar fades when the equipped Shoot spell is out of range")
assert(rangeTicker and not rangeTicker.cancelled, "track movement with an unknown native swing range")
local ticker = rangeTicker
spellRange = true
rangeTicker:Tick()
assert(ranged.alpha == 1 and rangeTicker == ticker, "walking into range restores opacity without a target change")
spellRange = false
rangeTicker:Tick()
assert(ranged.alpha == 0.25, "walking out of range fades the whole bar again")
nativeRanged = true
event("PLAYER_SWING_RANGE_UPDATE",2,true,true)
assert(ranged.alpha == 1 and ticker.cancelled, "a valid swing range takes precedence and stops fallback polling")
nativeRanged = nil
event("PLAYER_SWING_RANGE_UPDATE",2,false,false)
assert(ranged.alpha == 0.25 and not rangeTicker.cancelled, "invalid swing events fall back to the equipped spell")
attackable = false
local lastCalls = spellRangeCalls
event("PLAYER_TARGET_CHANGED")
assert(ranged.alpha == 1 and rangeTicker.cancelled and spellRangeCalls == lastCalls, "skip friendly or cleared targets")
attackable, targetDead = true, true
event("PLAYER_TARGET_CHANGED")
assert(ranged.alpha == 1 and rangeTicker.cancelled and spellRangeCalls == lastCalls, "skip dead targets")
targetDead = false
event("UNIT_FLAGS","target")
assert(ranged.alpha == 0.25 and not rangeTicker.cancelled, "the same target reviving restarts fallback")
attackable = false
event("UNIT_FACTION","target")
assert(ranged.alpha == 1 and rangeTicker.cancelled, "the same target becoming friendly stops fallback")
attackable = true
event("UNIT_FACTION","target")
assert(ranged.alpha == 0.25 and not rangeTicker.cancelled, "the same target becoming hostile restarts fallback")
spellRange = nil
rangeTicker:Tick()
assert(ranged.alpha == 1, "an unknown spell range is neutral")
spellRange = false
local secret = Secrets.New("boolean")
local stopWatching = Secrets.Watch(path, { strict = true })
spellRange = secret
rangeTicker:Tick()
assert(ranged.alpha == 1, "a secret spell range is neutral")
spellRange = false
attackable = secret
event("UNIT_FACTION","target")
assert(ranged.alpha == 1 and rangeTicker.cancelled, "a secret reaction does not drive the fade")
attackable = true
targetDead = secret
event("UNIT_FLAGS","target")
assert(ranged.alpha == 1 and rangeTicker.cancelled, "a secret death state does not drive the fade")
targetDead = false
nativeRanged = secret
event("PLAYER_SWING_RANGE_UPDATE",2,secret,true)
assert(ranged.alpha == 1 and rangeTicker.cancelled, "a secret native range is neutral")
nativeRanged = nil
local violations = stopWatching()
assert(#violations == 0, table.concat(violations, "\n"))
knowsShoot = false
event("SPELLS_CHANGED")
assert(ranged.alpha == 1 and rangeTicker.cancelled, "skip an unlearned ranged attack")
knowsShoot = true
event("SPELLS_CHANGED")
assert(ranged.alpha == 0.25 and not rangeTicker.cancelled, "recheck when the shot becomes known")
rangedSubclass = 3
event("PLAYER_EQUIPMENT_CHANGED",INVSLOT_RANGED,true)
assert(ranged.alpha == 0.25, "a weapon change uses its own shot")
playerClass = "HUNTER"
event("WEAPON_SLOT_CHANGED")
assert(ranged.alpha == 0.25, "Hunter uses Auto Shot for a gun")
rangedSpeed, equippedRangedItem = nil, nil
event("WEAPON_SLOT_CHANGED")
assert(not ranged:IsShown() and rangeTicker.cancelled and not nativeRangeChecks[2], "unequipping stops fallback")
rangedSpeed, equippedRangedItem = 2.8, 1000
event("WEAPON_SLOT_CHANGED")
assert(ranged:IsShown() and ranged.alpha == 0.25 and not rangeTicker.cancelled, "equipping reseeds fallback")
assert(swing.SetPreview(true))
assert(rangeTicker.cancelled and ranged.alpha == 1, "in-world preview suspends live range checks")
assert(swing.SetPreview(false))
assert(ranged.alpha == 0.25 and not rangeTicker.cancelled, "exiting preview restores live range checks")
assert(swing.Set("ranged","visibility","combat"))
assert(rangeTicker.cancelled and not ranged:IsShown(), "combat-only bar does no fallback work while hidden")
combat = true
event("PLAYER_IN_COMBAT_CHANGED")
assert(ranged:IsShown() and ranged.alpha == 0.25, "combat-only bar seeds range on show")
combat = false
event("PLAYER_IN_COMBAT_CHANGED")
assert(swing.Set("ranged","visibility","always"))
assert(swing.Set("ranged","reachCheck",false))
assert(rangeTicker.cancelled and not nativeRangeChecks[2] and ranged.alpha == 1, "disabling fade stops both checks")
-- A staff-wielding Priest needs a melee check without a class melee spell.
playerClass, rangedSubclass, offSpeed = "PRIEST", 19, nil
event("WEAPON_SLOT_CHANGED")
assert(swing.Set("main","visibility","always"))
assert(swing.Set("main","reachOpacity",25))
assert(swing.Set("main","reachCheck",true))
assert(main.alpha == 0.25 and not off:IsShown() and not rangeTicker.cancelled,
    "an idle Priest with a staff fades against a target outside melee range")
local meleeTicker = rangeTicker
meleeRange = true
meleeTicker:Tick()
assert(main.alpha == 1 and rangeTicker == meleeTicker, "entering melee range restores the staff bar")
meleeRange = false

-- Dual-wield and a ranged weapon share a timer and have separate range probes.
playerClass, rangedSubclass, offSpeed = "WARRIOR", 3, 2.5
event("WEAPON_SLOT_CHANGED")
assert(swing.Set("off","reachOpacity",40))
assert(swing.Set("off","reachCheck",true))
assert(swing.Set("ranged","reachCheck",true))
local previousMeleeCalls, previousSpellCalls = meleeRangeCalls, spellRangeCalls
rangeTicker:Tick()
assert(main.alpha == 0.25 and off.alpha == 0.4 and ranged.alpha == 0.25
    and meleeRangeCalls == previousMeleeCalls + 1 and spellRangeCalls == previousSpellCalls + 1
    and rangeTicker == meleeTicker, "both melee bars share one target probe and the ranged ticker")
previousMeleeCalls, previousSpellCalls = meleeRangeCalls, spellRangeCalls
event("PLAYER_SWING_RANGE_UPDATE",0,false,false)
event("PLAYER_SWING_RANGE_UPDATE",1,false,false)
assert(meleeRangeCalls == previousMeleeCalls and spellRangeCalls == previousSpellCalls,
    "repeat invalid native events do not resample an already pending range")
do
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 10000 do meleeTicker:Tick() end
    local growth = collectgarbage("count") - before
    collectgarbage("restart")
    assert(growth < 1, "stable fallback polls allocated " .. growth .. " KiB")
    assert(meleeRangeCalls == previousMeleeCalls + 10000 and spellRangeCalls == previousSpellCalls + 10000,
        "each stable tick issues only one melee probe and one ranged probe")
    print("Swing range fallback allocation smoke: 10000 ticks, " .. growth .. " KiB growth (offline stubs)")
end
nativeMain = true
event("PLAYER_SWING_RANGE_UPDATE",0,true,true)
assert(main.alpha == 1 and off.alpha == 0.4 and not rangeTicker.cancelled,
    "a readable main-hand result wins while the off-hand still needs fallback")
nativeOff = false
event("PLAYER_SWING_RANGE_UPDATE",1,false,true)
previousMeleeCalls = meleeRangeCalls
rangeTicker:Tick()
assert(off.alpha == 0.4 and meleeRangeCalls == previousMeleeCalls,
    "the ranged timer must not sample melee when both native results are readable")
assert(swing.Set("ranged","reachCheck",false))
assert(rangeTicker.cancelled, "readable native results stop the last fallback ticker")

nativeMain, nativeOff = nil, nil
event("PLAYER_TARGET_CHANGED")
assert(main.alpha == 0.25 and off.alpha == 0.4 and not rangeTicker.cancelled)
previousMeleeCalls = meleeRangeCalls
attackable = false
event("UNIT_FACTION","target")
assert(main.alpha == 1 and off.alpha == 1 and rangeTicker.cancelled and meleeRangeCalls == previousMeleeCalls,
    "the same target becoming friendly stops both melee fallbacks")
attackable, targetDead = true, true
event("UNIT_FLAGS","target")
assert(main.alpha == 1 and off.alpha == 1 and meleeRangeCalls == previousMeleeCalls, "skip dead targets")
targetDead = false
event("UNIT_FLAGS","target")
assert(main.alpha == 0.25 and off.alpha == 0.4 and not rangeTicker.cancelled, "reviving resumes melee fallback")

meleeRange = nil
rangeTicker:Tick()
assert(main.alpha == 1 and off.alpha == 1 and rangeTicker.cancelled,
    "a missing melee result is neutral and stops the fallback ticker")
meleeRange = false
event("PLAYER_TARGET_CHANGED")
assert(not rangeTicker.cancelled, "recheck melee range after changing targets")
stopWatching = Secrets.Watch(path, { strict = true })
meleeRange = secret
rangeTicker:Tick()
assert(main.alpha == 1 and off.alpha == 1 and rangeTicker.cancelled,
    "a secret melee result is neutral and stops the fallback ticker")
meleeRange, nativeMain, nativeOff = false, secret, secret
previousMeleeCalls = meleeRangeCalls
event("PLAYER_TARGET_CHANGED")
assert(main.alpha == 1 and off.alpha == 1 and rangeTicker.cancelled and meleeRangeCalls == previousMeleeCalls,
    "secret native melee results must not fall back")
violations = stopWatching()
assert(#violations == 0, table.concat(violations, "\n"))
nativeMain, nativeOff = nil, nil
assert(swing.Set("main","visibility","combat"))
assert(swing.Set("off","visibility","combat"))
previousMeleeCalls = meleeRangeCalls
local previousNativeMeleeCalls = nativeMeleeCalls
event("PLAYER_TARGET_CHANGED")
assert(not main:IsShown() and not off:IsShown() and rangeTicker.cancelled
    and meleeRangeCalls == previousMeleeCalls and nativeMeleeCalls == previousNativeMeleeCalls,
    "hidden melee bars do neither native nor fallback polling")
combat = true
event("PLAYER_IN_COMBAT_CHANGED")
assert(main.alpha == 0.25 and off.alpha == 0.4 and not rangeTicker.cancelled,
    "combat-only melee bars seed their range when shown")
combat = false
event("PLAYER_IN_COMBAT_CHANGED")
assert(swing.Set("main","reachCheck",false))
assert(swing.Set("off","reachCheck",false))
assert(swing.Set("off","visibility","always"))
assert(rangeTicker.cancelled and not nativeRangeChecks[0] and not nativeRangeChecks[1],
    "disabled melee checks leave no polling")

assert(swing.Set("main","visibility","always"))
assert(swing.Set("main","offhandLane",true))
assert(swing.Set("off","reachColor",{0.1,0.2,0.3}))
assert(swing.Set("off","reachCheck",true))
assert(not off:IsShown() and off.Lane:IsShown() and nativeRangeChecks[1]
    and main.alpha == 1 and off.Lane:GetAlpha() == 0.4 and off.Lane.color[1] == 0.1,
    "the visible off-hand lane warns independently of the main hand")
assert(swing.Set("off","visibility","combat"))
assert(not combat and main:IsShown() and not off:IsShown() and not off.Lane:IsShown(),
    "an embedded combat-only off-hand timer must stay hidden out of combat")
assert(not nativeRangeChecks[1] and rangeTicker.cancelled, "a hidden combat-only lane must stop its range checks")
combat = true
event("PLAYER_IN_COMBAT_CHANGED")
assert(off.Lane:IsShown() and not off:IsShown() and nativeRangeChecks[1] and not rangeTicker.cancelled,
    "combat starts the selected off-hand lane and its range checks")
combat = false
event("PLAYER_IN_COMBAT_CHANGED")
assert(not off.Lane:IsShown() and not nativeRangeChecks[1], "leaving combat must hide just the off-hand lane")
assert(swing.Set("off","visibility","always"))
assert(off.Lane:IsShown() and nativeRangeChecks[1] and not rangeTicker.cancelled,
    "changing the off-hand timer back to always restores the lane and its range checks")
meleeRange = true
rangeTicker:Tick()
assert(off.Lane:GetAlpha() == 1 and off.Lane.color[1] == off.config.color[1],
    "the off-hand lane restores its normal opacity and color when in range")
meleeRange = false
assert(swing.Set("off","reachCheck",false))
assert(swing.Set("main","offhandLane",false))
assert(off:IsShown() and not off.Lane:IsShown() and rangeTicker.cancelled)

playerClass, rangedSubclass = "WARRIOR", 19
event("PLAYER_SWING",4,2)
assert(ranged.endsAt==104)
assert(swing.Set("main","visibility","always"))
assert(swing.Set("main","texture","Custom"))
assert(swing.Set("main","color",{0.1,0.2,0.3}))
assert(swing.Set("main","font","my-font"))
assert(swing.Set("main","fontSize",16))
assert(swing.Set("main","fill","remaining"))
assert(swing.Set("main","direction","LEFT"))
event("PLAYER_SWING",2,0)
assert(main.Bar.texture==textures.Custom and main.Bar.color[2]==0.2)
assert(main.Title.font[1]=="my-font" and main.Time.font[2]==16)
assert(main.Bar.timer.direction==1 and main.Bar.reverse)
assert(swing.Set("off","font",""))
_G.MSUF_GetFontPath=function() return "changed-global-font" end
swing.ApplyFonts()
assert(main.Title.font[1]=="my-font" and off.Title.font[1]=="changed-global-font", "global fonts update only followers")

assert(not swing.Set("main","width",0) and not swing.Set("main","visibility","bogus"))
assert(not swing.Set("main","color",{0/0,0,0}))
assert(swing.SetPreview(true) and main.mouse and main.PreviewBar.value==0.35)
assert(main.PreviewBar:IsVisible() and not main.Bar:IsShown() and not main.PreviewBar.timer,
    "static preview must never inherit the native duration driver")
assert(not driver.events.PLAYER_SWING, "no swing event work while previewing")
assert(main.Time:IsVisible() and main.Time.text=="1.2", "preview text is independent of live bar visibility")
assert(swing.Set("main","fill","elapsed") and main.PreviewBar.value==0.65)
assert(swing.Set("main","texture","Solid"))
assert(main.PreviewBar.texture=="Interface\\Buttons\\WHITE8X8", "built-in choices resolve without Castbars or LSM registration")
assert(swing.Set("main","backgroundTexture","Custom"))
assert(main.PreviewBar.Background.texture==textures.Custom and main.Bar.Background.texture==textures.Custom)
assert(swing.Set("main","backgroundTexture",""))
assert(main.PreviewBar.Background.texture==main.PreviewBar.texture, "background can follow foreground again")
for _,case in ipairs({{"RIGHT","HORIZONTAL",false},{"LEFT","HORIZONTAL",true},{"UP","VERTICAL",false},{"DOWN","VERTICAL",true}}) do
    assert(swing.Set("main","direction",case[1]))
    assert(main.Bar.orientation==case[2] and main.Bar.reverse==case[3])
    assert(main.Bar.rotatesTexture==(case[2]=="VERTICAL"))
    assert(main.PreviewBar.orientation==case[2] and main.PreviewBar.reverse==case[3])
end
assert(not swing.Set("main","direction","invalid") and not swing.Set("main","display","invalid"))
assert(swing.Set("main","time",false))
assert(swing.Set("main","display","text"))
assert(main.Time:IsVisible() and not main.Title:IsVisible() and main.backdrop==nil,
    "number-only overrides hidden remaining time and removes the title and border")
assert(not main.Bar:IsVisible() and not main.PreviewBar:IsVisible(), "number-only removes both bar surfaces and backgrounds")
assert(main.Time.point[1]=="CENTER", "number-only centers the number by default")
assert(swing.Set("main","textAlign","LEFT") and swing.Set("main","textX",7) and swing.Set("main","textY",9))
assert(main.Time.point[1]=="LEFT" and main.Time.point[4]==7 and main.Time.point[5]==9)
assert(swing.SetPreview(false))
local oldBarEnd=main.Bar.timer.endTime
assert(driver.events.PLAYER_SWING)
event("PLAYER_SWING",4,0)
assert(main.binding.enabled and main.duration.endTime==104 and main.Bar.timer.endTime==oldBarEnd,
    "number-only runs only the native text binding")
assert(swing.Set("main","display","bar") and main.Bar.timer.endTime==104)
assert(main.Bar:IsVisible() and not main.Time:IsShown() and main.Title:IsVisible(), "bar mode restores existing title/time choices")
assert(swing.Set("main","time",true))
assert(not swing.GetPreview())
editModeChanged(true)
assert(main.mouse and main.PreviewBar:IsShown() and not driver.events.PLAYER_SWING,
    "Edit Mode must show the static draggable Swing preview")
assert(not swing.GetPreview(), "automatic preview must not change the manual toggle")
assert(swing.SetPreview(false) and main.mouse, "closing Swing settings must keep the Edit Mode preview")
editModeChanged(false)
assert(not main.mouse and driver.events.PLAYER_SWING, "leaving Edit Mode must resume gameplay")
editModeChanged(true)
assert(swing.Set("main","scale",150))
main.centerX,main.centerY=400,300
main.scripts.OnDragStart(main)
main.scripts.OnDragStop(main)
assert(swing.Get("main","x")==100 and swing.Get("main","y")==50, "drag persists screen offsets at custom scale")

assert(swing.SetPreview(true))
editModeChanged(false)
assert(swing.GetPreview() and main.mouse, "leaving Edit Mode must keep a requested manual preview")
assert(swing.SetPreview(false) and not main.mouse and driver.events.PLAYER_SWING,
    "turning off manual preview must resume gameplay")
editModeChanged(true)
assert(swing.SetPreview(true))
-- A drag still running when combat starts: the drop is not saved, so the bar
-- stops moving and goes back to its saved place instead of staying dropped.
main.StartMoving = function(self) self.moving = true; self.point = { "DRAGGED" } end
main.StopMovingOrSizing = function(self) self.moving = false end
main.scripts.OnDragStart(main)
assert(main.moving, "a preview drag did not start")
combat=true
event("PLAYER_REGEN_DISABLED")
assert(not swing.GetPreview() and not main.mouse, "combat ends interactive preview")
main.scripts.OnDragStop(main)
assert(not main.moving, "combat start left the bar following the cursor")
assert(swing.Get("main","x")==100 and swing.Get("main","y")==50, "a drop after combat started was saved")
assert(main.point[1]=="CENTER" and math.abs(main.point[4]-100/1.5)<1e-9 and math.abs(main.point[5]-50/1.5)<1e-9,
    "a bar dropped after combat started stays where it was dropped instead of its saved place")
combat=false
-- All three disabled: no PLAYER_SWING subscriber, while ownership remains active.
for _,hand in ipairs({"main","off","ranged"}) do assert(swing.Set(hand,"enabled",false)) end
assert(not driver.events.PLAYER_SWING and not native)
assert(swing.Set("main","enabled",true) and driver.events.PLAYER_SWING)
-- Warm native objects are reused. The modeled event boundary itself allocates nothing.
event("PLAYER_SWING",2,0)
collectgarbage("collect")
collectgarbage("stop")
local before=collectgarbage("count")
for i=1,10000 do event("PLAYER_SWING",2,0) end
local growth=collectgarbage("count")-before
collectgarbage("restart")
assert(growth < 1, "swing hot path allocated "..growth.." KiB")
print("Swing dispatcher allocation smoke: 10000 events, "..growth.." KiB growth (offline stubs)")
local priorDB=_G.MSUF_DB
_G.MSUF_DB={swingTimers={enabled=true,main={width=411,reverse=true}}}
swing.RefreshSettings()
assert(main.width==411 and main.config~=priorDB.swingTimers.main, "enabled-to-enabled profile change rebinds configuration")
assert(main.config.direction=="LEFT" and main.Bar.reverse, "legacy reverse preference migrates once")
_G.MSUF_DB={swingTimers={enabled=false}}
swing.RefreshSettings()
assert(native and next(driver.events)==nil, "profile disabling releases events and restores native preference")
assert(not main:IsShown() and not main.binding.enabled)
for _,frame in ipairs(nativeFrames) do
    assert(frame:IsShown() and frame:GetAlpha() == 1, "release restores the native bars and their alpha")
end
-- An originally hidden native UI must remain hidden on release.
_G.SetCVar("showSwingTimer","0")
assert(swing.SetEnabled(true))
_G.SetCVar("showSwingTimer","1")
assert(not native, "native CVar changes cannot create duplicate bars")
assert(swing.SetEnabled(false) and not native)
_G.SetCVar("showSwingTimer","1")
assert(swing.SetEnabled(true))
event("PLAYER_LOGOUT")
assert(native, "reload restores the original account CVar")
local source=assert(io.open(path,"rb")):read("*a")
assert(not source:find('OnUpdate',1,true), "native duration animation only")
local profile=assert(io.open(root.."/MidnightSimpleUnitFrames/State/MSUF_ProfileRuntime.lua","rb")):read("*a")
assert(profile:find("MSUF.SwingTimer.Apply()",1,true), "profile fanout includes enabled modules")
print("PASS Forever Swing Timer module: simultaneous hands, native ownership, equipment, native timers, appearance and profile lifecycle")

assert(swing.SetEnabled(false) and swing.SetEnabled(true))
local controls,sections,shortcuts={}, {}, {}
local function bind(_,widget,get,set,meta)
    widget.get,widget.set=get,set
    controls[meta.path]=widget
end
local W={}
function W.PageBuilder()
    return { width=800,y=-100, RequestRelayoutCollapsibles=noop, CollapsibleSection=function(_,id,title)
        local section=object(); sections[id]=section
        local entry={outer=object(),body=section,header=object()}
        entry.header._msuf2RuntimeControlRecord={controlId="menu2.swingtimers.section."..id..".expanded",
            kind="toggle",label=(title or id).." section",command={get=function() return entry.open==true end,
                set=function(value) entry.open=value end}}
        section._msuf2CollapsibleEntry=entry
        return section
    end }
end
function W.Toggle() return object() end
W.SectionSwitch=W.Toggle
function W.Segment() local widget=object();widget._msuf2Title=object();return widget end
function W.FixedPreviewSection() return object(), object() end
function W.Slider(_, _, min, max, step)
    local widget = object()
    widget.min, widget.max, widget.step = min, max, step
    return widget
end
function W.Dropdown(_,_,values) local widget=object(); widget.values=values; return widget end
function W.TextInput(parent,label,width)
    local widget=object(nil,parent)
    widget.label=label
    widget:SetWidth(width)
    return widget
end
function W.MoveWidget(widget,parent,x,y,width)
    widget:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    if width then widget:SetWidth(width) end
    return widget
end
function W.Color() error("inline swing color widgets must not be allocated") end
function W.AttachContextColorShortcut(section,options) shortcuts[section]=options end
local page
local kernelRequire=ns.Require
ns.Require=function(name,...)
    if name=="MSUF_NormalizeProfileDefaults" then
        return function() error("Swing defaults must remain owned by SwingTimer") end
    end
    -- ClassPower/MSUF_CP_ExtraAuras.lua requires the font owner's getters
    -- (Runtime/MSUF_Fonts.lua, loaded above).
    if name=="MSUF_GetFontPath" or name=="MSUF_GetFontFlags" then return kernelRequire(name,...) end
    assert(name=="MSUF_PixelLayoutRegion")
    return function(region) return region end
end
ns.MSUF2={
    Widgets=W, Theme={colors={accent={0.2,0.5,1}}, Button=function() return object() end,
        Font=function(parent) return parent:CreateFontString() end},
    Tr=function(label) return label end,
    AlphaLabel=function(label) return label end,
    PreviewHelpers={
        LayerChipButtonOpts=function(_,_,_,opts) return opts end,
        PreviewChromePalette=function() return {} end,
        CreateLayerButton=function() local chip=object(); chip.Refresh=noop; return chip end,
        FlowLayerChips=function() return 24 end,
        ApplyPreviewChrome=noop,
        ApplyPreviewLayerRail=noop,
        StylePreviewPillButton=function(button) button.MSUF2RefreshPreviewPill=noop end,
    },
    UnitSectionsShared={MakeScopeCopyPopup=function() return {Show=noop,Hide=noop} end},
    AdvancedPage={MoveWidget=noop, RegisterControl=noop, ControlMeta=function(_,_,path,classification,options)
        return {path=path,controlId="menu2.swingtimers.swing."..path, classification=classification, settingKey=options.settingKey}
    end},
    RegisterControlMetadata=noop,
    StatusBarTextureItems=ns.UI.StatusBarTextureItems,
    GlobalPage={FontValues=function() return {} end},
    ValueTextList=function(...) local list={}; local args={...}; for i=1,#args,2 do list[#list+1]={value=args[i],text=args[i+1]} end; return list end,
    BindBoolWidget=bind,BindDropdownWidget=bind,BindSegment=bind,
    BindTextInput=function(ctx,widget,get,set,commitOnBlur,meta)
        widget.commitOnBlur=commitOnBlur
        bind(ctx,widget,get,set,meta)
    end,
    BindDropdownAt=function(ctx,parent,label,x,y,values,width,get,set,meta)
        local widget=W.Dropdown(parent,label,values,width)
        bind(ctx,widget,get,set,meta)
        return widget
    end,
    TrackRefresh=function(_,refresh) refresh() end,
    BindTextInputAt=function(ctx,parent,label,x,y,width,get,set,commitOnBlur,meta)
        local widget=object(nil,parent);widget.label,widget.commitOnBlur=label,commitOnBlur
        widget:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);widget:SetWidth(width)
        bind(ctx,widget,get,set,meta);return widget
    end,
    BindNumberWidget=function(ctx,widget,get,set,_,meta) bind(ctx,widget,get,set,meta) end,
    Format=function(text,...) return string.format(text,...) end,
    RegisterPage=function(key,spec) assert(key=="swingtimers"); page=spec end,
    Refresh=noop,
}
-- Partial standalone fixtures load the production owners rather than inventing defaults/adapters.
assert(loadfile(root.."/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_ExtraAuras.lua"))("MSUF",ns)
local Slice=assert(loadfile(root.."/.github/scripts/msuf_source_slice.lua"))()
local supportPath=root.."/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua"
local supportFile=assert(io.open(supportPath,"rb"))
local supportSource=supportFile:read("*a") supportFile:close()
assert(loadstring("local M=...\n"..Slice.Function(supportSource,"function M.BindTextInputWidget",supportPath)))(ns.MSUF2)
assert(loadfile(root.."/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua"))("MSUF",ns)
assert(loadfile(root.."/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_SwingTimersPreview.lua"))("MSUF",ns)
assert(loadfile(root.."/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_SwingTimers.lua"))("MSUF",ns)
local swingContext = { SetContentHeight = noop }
page.build(swingContext)
local swingPreview = assert(swingContext._msuf2SwingTimerPreview)
for _, hand in ipairs({ "main", "off", "ranged" }) do
    local width, height = controls[hand .. ".width"], controls[hand .. ".height"]
    assert(width.min == 4 and width.max == 1200 and width.step == 1, hand .. " width slider range")
    assert(height.min == 4 and height.max == 400 and height.step == 1, hand .. " height slider range")

    local oldWidth, oldHeight = width.get(), height.get()
    local oldDirection = swing.Get(hand, "direction")
    assert(swingPreview.SelectHand(hand))
    assert(swing.Set(hand, "direction", "UP"))
    width.set(width.min)
    height.set(height.max)
    local live, sample = named["MSUF_SwingTimer_" .. hand], swingPreview.samples[hand]
    assert(width.get() == 4 and height.get() == 400, hand .. " saves a tall, narrow bar")
    assert(live.width == 4 and live.height == 400 and live.Bar.orientation == "VERTICAL")
    assert(sample.width == 4 and sample.height == 400 and sample.Bar.orientation == "VERTICAL")
    assert(sample:GetScale() > 0 and sample.height * sample:GetScale() <= swingPreview.canvasHeight,
        hand .. " preview fits a tall bar")
    assert(not swing.Set(hand, "width", 3) and not swing.Set(hand, "height", 401))
    assert(width.get() == 4 and height.get() == 400, "out-of-range settings preserve saved dimensions")

    if hand == "main" then
        local oldBorder = swing.Get(hand, "borderSize")
        assert(live.Cue.height == 100, "a tall bar keeps the cue icon bounded")
        assert(swing.Set(hand, "borderSize", 8) and swing.Set(hand, "offhandLane", true))
        assert(off.Lane.width > 0 and off.Lane.width < live.width - 2 * live.inset,
            "a vertical off-hand strip leaves room for the main-hand fill")
        assert(swing.Set(hand, "direction", "RIGHT"))
        height.set(height.min)
        assert(off.Lane.height > 0 and off.Lane.height < live.height - 2 * live.inset,
            "a horizontal off-hand strip leaves room for the main-hand fill")
        assert(swing.Set(hand, "offhandLane", false) and swing.Set(hand, "borderSize", oldBorder))
    end
    width.set(oldWidth)
    height.set(oldHeight)
    assert(swing.Set(hand, "direction", oldDirection))
end
swingPreview.SelectHand("main")
local copyButton
for _, widget in ipairs(objects) do
    local spec = widget._msuf2ControlSchema
    if spec and spec.id == "menu2.swingtimers.swing.copy.button" then copyButton = widget break end
end
assert(copyButton, "minimal fixture lost actual Copy To owner")
assert(copyButton._msuf2ControlSchema.owner == copyButton, "Copy To action must have its real button owner")
local copyHooks = 0
copyButton:HookScript("OnClick", function(self) assert(self == copyButton); copyHooks = copyHooks + 1 end)
copyButton:SetScript("OnClick", function(self, button, down) return self, button, down end)
local copySelf, copyMouse, copyDown = copyButton._msuf2ControlSchema.action({}, "RightButton", true)
assert(copySelf == copyButton and copyMouse == "RightButton" and copyDown == true and copyHooks == 1,
    "minimal current native action lost owner, inputs, returns or separate hook")
for _,hand in ipairs({"main","off","ranged"}) do
    local targets=shortcuts[sections["swing_"..hand.."_appearance"]].getTargets()
    assert(#targets==3, "appearance context owns bar, background and border colors")
    assert(#shortcuts[sections["swing_"..hand.."_text"]].getTargets()==1, "text context owns text color")
    assert(#shortcuts[sections["swing_"..hand.."_reach"]].getTargets()==1, "reach context owns warning color")
    targets[1].setRGB(.2,.4,.6)
    assert(swing.Get(hand,"color")[2]==.4)
    assert(targets[1].getRGB()==.2, "context color roundtrip")
    local texture=controls[hand..".texture"]
    for _,item in ipairs(texture.values()) do
        assert(item.value==item.texturePreview, "selected texture is the exact preview asset")
        texture.set(item.value)
        assert(texture.get()==item.value and swing.ResolveTexture(swing.Get(hand,"texture"))==item.texturePreview)
        assert(named["MSUF_SwingTimer_"..hand].Bar.texture==item.texturePreview, "menu selection reaches the live surface")
    end
    local background=controls[hand..".backgroundTexture"]
    assert(background.values()[1].value=="", "foreground-follow choice is retained")
    assert(controls[hand..".display"] and controls[hand..".direction"] and controls[hand..".textAlign"])
end
for _,key in ipairs({"offhandLane","nextSwingCue"}) do
    local control=assert(controls["main."..key], key .. " control missing")
    control.set(false);assert(control.get()==false and swing.Get("main",key)==false, key .. " roundtrip")
    control.set(true);assert(control.get()==true, key .. " roundtrip")
end
for _,hand in ipairs({"main","off","ranged"}) do
    for _,key in ipairs({"reachCheck","reachOpacity"}) do
        assert(controls[hand.."."..key], hand .. " " .. key .. " control missing")
    end
end
-- The cue text switch and one text per next-swing attack, labelled with the
-- client's spell name (the attack's spell ID where the client has no name).
local cueText=assert(controls["main.nextSwingText"], "the cue text switch is missing")
cueText.set(true);assert(cueText.get()==true and swing.Get("main","nextSwingText")==true, "cue text switch roundtrip")
cueText.set(false)
for id,name in pairs({[78]="Heroic Strike",[845]="Cleave",[6807]="Maul",[2973]="2973"}) do
    local input=assert(controls["main.nextSwingLabel"..id], "the cue text for "..id.." is missing")
    assert(input.label:find(name,1,true) and input.commitOnBlur==true, "the cue text for "..id.." is not labelled with its attack")
    input.set("Go");assert(input.get()=="Go" and swing.Get("main","nextSwingLabel"..id)=="Go", "cue text roundtrip "..id)
    input.set("");assert(swing.Get("main","nextSwingLabel"..id)=="", "clearing a cue text "..id)
end
assert(#shortcuts[sections.swing_next].getTargets()==1, "main-hand cue context owns its color")
print("PASS Swing menu: scoped appearance, text, reach and main-hand cue color menus, real shared media paths, number-only/direction, off-hand lane, reach, next-swing and per-attack cue text controls")

local function CheckSizeHistory()
    local statePath = root .. "/MidnightSimpleUnitFrames/State/"
    assert(loadfile(statePath .. "MSUF_ProfileFields.lua"))("MSUF", ns)
    ns.Util = { DeepCopy = ns.ProfileFields.CopySnapshot }
    ns.ApplyService = { UnitKeys = {} }
    ns.Public.IsConfigCombatLocked = InCombatLockdown
    ns.PublicGlobals.MSUF_GetCharKey = noop
    ns.PublicGlobals.MSUF_EM_RefreshHistoryControls = noop
    ns.PublicGlobals.MSUF_EM_RefreshAfterHistoryRestore = noop
    ns.PublicGlobals.MSUF_ApplySpecProfileIfEnabled = noop
    ns.Castbars = { Backend = { Resolve = noop }, Config = { Invalidate = noop } }
    _G.MSUF_DB.general = {}
    _G.MSUF_ActiveProfile = "Swing test"
    _G.MSUF_GlobalDB = { profiles = { [_G.MSUF_ActiveProfile] = _G.MSUF_DB } }
    assert(loadfile(statePath .. "MSUF_HistoryProviders.lua"))("MSUF", ns)
    assert(loadfile(statePath .. "MSUF_History.lua"))("MSUF", ns)
    local history = ns.History
    history.AttachUI(function(action)
        if action == "RepaintActivePage" then
            swingPreview.Paint()
            return true
        end
    end)
    assert(history.StartHistorySession("menu"))
    for _, hand in ipairs({ "main", "off", "ranged" }) do
        assert(swingPreview.SelectHand(hand))
        local live = named["MSUF_SwingTimer_" .. hand]
        local sample = swingPreview.samples[hand]
        for _, key in ipairs({ "width", "height" }) do
            local control = controls[hand .. "." .. key]
            local original, changed = control.get(), control.min
            history.CaptureHistory(key, "swingtimers:slider:" .. key, function()
                return control.set(changed)
            end, "swingTimers." .. hand .. "." .. key)
            assert(live[key] == changed and sample[key] == changed, hand .. " menu resize: " .. key)
            assert(history.Undo() and control.get() == original and sample[key] == original,
                hand .. " saved setting and preview undo: " .. key)
            assert(live[key] == original, hand .. " runtime undo: " .. key)
            assert(history.Redo() and control.get() == changed and sample[key] == changed,
                hand .. " saved setting and preview redo: " .. key)
            assert(live[key] == changed, hand .. " runtime redo: " .. key)
        end
    end
    assert(history.EndHistorySession("menu"))
end
CheckSizeHistory()
print("PASS Swing history: width and height follow undo and redo in the live bars and menu preview")

-- A fresh login with the feature disabled must leave no subscriber behind.
assert(swing.SetEnabled(false))
local disabledNS={Client={IsForever=true},LSM=ns.LSM,UI=ns.UI}
assert(loadfile(root.."/tools/tests/require_fixture.lua"))().InstallKernel(root,disabledNS)
assert(loadfile(root.."/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))("MSUF",disabledNS)
assert(loadfile(root.."/MidnightSimpleUnitFrames/Kernel/MSUF_Modules.lua"))("MSUF",disabledNS)
_G.MSUF_DB={swingTimers={enabled=false}}
chunk("MSUF",disabledNS)
local disabledDriver=driver
local beforeWorldObjects=#objects
assert(disabledDriver.events.PLAYER_ENTERING_WORLD)
event("PLAYER_ENTERING_WORLD")
assert(next(disabledDriver.events)==nil and not disabledDriver.scripts.OnEvent,
    "disabled login removes the one-shot startup handler")
assert(#objects==beforeWorldObjects, "disabled login does not build bars, bindings or formatters")
assert(not disabledNS.MSUF_ModulesByKey.SwingTimers.__msufEnabled)
assert(disabledNS.SwingTimer.SetEnabled(true) and driver==disabledDriver,
    "enabling later reuses the startup driver")
assert(driver.events.PLAYER_SWING and named.MSUF_SwingTimer_main:IsShown() and not native)
assert(disabledNS.SwingTimer.SetEnabled(false))
print("PASS Swing login: saved-enabled starts on world entry; saved-disabled has no bars or idle events; later enable reuses driver")
