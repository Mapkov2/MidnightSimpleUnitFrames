-- Detaching the power bar must not take ownership of the unit's own appearance.
--
-- Beta 25 reports: the "Power bar border" toggle and "Border thickness" slider
-- were inert while the power bar was detached, and detaching alone repainted the
-- bar. Both came from the same defect: the detached bar read the global
-- `bars.detached*` keys instead of the per-unit power settings.

_G = _G or _ENV

table.wipe = table.wipe or function(tbl)
  for key in pairs(tbl) do tbl[key] = nil end
  return tbl
end
_G.wipe = _G.wipe or table.wipe

local function Check(value, message)
  if not value then error(message or "check failed", 2) end
end

local function Exists(path)
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local ADDON = Exists("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua")
  and "MidnightSimpleUnitFrames/" or ""

local function Read(relativePath)
  local file = assert(io.open(ADDON .. relativePath, "rb"), "missing source: " .. relativePath)
  local source = file:read("*a")
  file:close()
  return source
end

--------------------------------------------------------------------------------
-- Part 1: the live border follows the per-unit toggle/thickness when detached.
--------------------------------------------------------------------------------

local function NewRegion(parent)
  local region = { parent = parent, shown = true, points = {}, frameLevel = 1 }
  function region:GetParent() return self.parent end
  function region:SetParent(value) self.parent = value end
  function region:EnableMouse() end
  function region:Show() self.shown = true end
  function region:Hide() self.shown = false end
  function region:IsShown() return self.shown end
  function region:ClearAllPoints() self.points = {} end
  function region:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function region:SetAllPoints(value) self.allPoints = value or true end
  function region:SetSize(width, height) self.width, self.height = width, height end
  function region:SetWidth(width) self.width = width end
  function region:SetHeight(height) self.height = height end
  function region:GetWidth() return self.width or 275 end
  function region:GetHeight() return self.height or 40 end
  function region:SetFrameLevel(level) self.frameLevel = level end
  function region:GetFrameLevel() return self.frameLevel end
  function region:SetMinMaxValues() end
  function region:SetValue(value) self.value = value end
  function region:SetStatusBarTexture(texture) self.statusTexture = texture end
  function region:SetStatusBarColor() end
  function region:SetReverseFill() end
  function region:SetOrientation(value) self.orientation = value end
  function region:SetTexture(texture) self.texture = texture end
  function region:SetColorTexture(...) self.colorTexture = { ... } end
  function region:SetVertexColor() end
  function region:SetAlpha() end
  function region:CreateTexture() return NewRegion(self) end
  function region:SetScript(kind, callback) self.scripts[kind] = callback end
  function region:GetScript(kind) return self.scripts[kind] end
  function region:HookScript(kind, callback) self.scripts[kind] = callback end
  function region:RegisterEvent() end
  function region:RegisterUnitEvent() end
  function region:UnregisterEvent() end
  function region:UnregisterAllEvents() end
  function region:IsVisible() return self.shown end
  region.scripts = {}
  return region
end

local registered
local elementUF = { RegisterElement = function(name, element) if name == "Power" then registered = element end end }
local elementMSUF = {
  UF = elementUF,
  UFBarTextCommon = {
    UF = elementUF,
    CreateFrame = function(_, _, parent) return NewRegion(parent) end,
    UnitPowerType = function() return 0, "MANA" end,
    PowerColor = function() return 0, 0.4, 1 end,
    WHITE = "white",
    POWER_EVENTS = { "UNIT_POWER_UPDATE" },
    ApplyBackgrounds = function() end,
    ApplyBarGradient = function() end,
    HideBarGradient = function() end,
    InCombatLockdown = function() return false end,
  },
}
_G.MSUF_NS = elementMSUF
_G.issecretvalue = function() return false end

assert(loadfile(ADDON .. "UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua"))("MidnightSimpleUnitFrames", elementMSUF)
local Power = assert(registered, "Power element was not registered")

local frame = NewRegion(nil)
frame.MSUFUnitKey = "player"
frame.frameLevel = 10

local function ApplyPower(overrides)
  local power = {
    enabled = true, height = 6, embed = true, shape = "BAR",
    texture = "power-fill", backgroundTexture = "power-bg",
    mode = "static", r = 0.1, g = 0.35, b = 0.95, alpha = 1,
    borderR = 0, borderG = 0, borderB = 0, borderA = 1,
  }
  for key, value in pairs(overrides) do power[key] = value end
  local spec = { power = power, texture = "fallback-fill", backgroundAlpha = 0.7 }
  frame.MSUFSpec = spec
  Power.Apply(frame, spec)
  return frame.targetPowerBar
end

local bar = ApplyPower({ detached = false, borderEnabled = true, borderThickness = 4, detachedOutline = 1 })
Check(bar.MSUFPowerBorderHost.shown == true and bar._msufPowerBorderThickness == 4,
  "attached power border lost its configured thickness")

bar = ApplyPower({ detached = true, borderEnabled = true, borderThickness = 6, detachedOutline = 1 })
Check(bar.MSUFPowerBorderHost.shown == true, "detached power border was hidden while the unit toggle was on")
Check(bar._msufPowerBorderThickness == 6,
  "detached power border used the global outline instead of the unit thickness")

bar = ApplyPower({ detached = true, borderEnabled = false, borderThickness = 6, detachedOutline = 8 })
Check(bar.MSUFPowerBorderHost.shown == false,
  "detached power border ignored the unit border toggle being off")

bar = ApplyPower({ detached = true, borderEnabled = true, borderThickness = 0, detachedOutline = 8 })
Check(bar.MSUFPowerBorderHost.shown == false,
  "detached power border resurrected itself at thickness 0")

--------------------------------------------------------------------------------
-- Part 2: detaching alone must not repaint the bar.
--------------------------------------------------------------------------------

local FG, BG = "tex/global-fg", "tex/global-bg"
_G.MSUF_GetBarTexture = function() return FG end
_G.MSUF_GetBarBackgroundTexture = function() return BG end
_G.MSUF_ResolveStatusbarTextureKey = function(key) return "tex/" .. tostring(key) end

_G.CreateFrame = function() return NewRegion(nil) end
_G.InCombatLockdown = function() return false end
_G.UnitPowerType = function() return 0, "MANA" end
_G.issecretvalue = function() return false end

local configMSUF = {
  UF = {},
  Apply = {},
  Secrets = {
    IsSecret = function() return false end,
    IsNil = function(value) return value == nil end,
    UnitMissing = function() return false end,
    SafeNumber = tonumber,
  },
}
function configMSUF.ExportPublic(name, value) configMSUF[name] = value; return value end
_G.MSUF_NS = configMSUF

for _, relativePath in ipairs({
  "MSUF_UF_Metadata.lua",
  "MSUF_UF_Core.lua",
  "Elements/MSUF_UF_Elements_BarsCommon.lua",
  "Elements/MSUF_UF_Text_Common.lua",
  "Elements/MSUF_UF_Text_Format.lua",
  "Elements/MSUF_UF_Text_Runtime.lua",
  "Elements/MSUF_UF_Elements_Power.lua",
  "MSUF_UF_Config.lua",
}) do
  assert(loadfile(ADDON .. "UnitFrames/Engine/" .. relativePath))("MidnightSimpleUnitFrames", configMSUF)
end

local Config = assert(configMSUF.UF.Config, "UF.Config was not built")

local function Compile(unit, conf, bars)
  _G.MSUF_DB = { general = {}, bars = bars or {}, [unit] = conf or {} }
  Config.specs[unit] = nil
  return assert(Config.RefreshUnit(unit))
end

-- Shipped defaults pair a textured bar with a flat background, so borrowing the
-- foreground on detach was immediately visible.
local DEFAULT_BARS = { detachedPowerBarTexture = "", detachedPowerBarBgTexture = "", detachedPowerBarOutline = 1 }

local spec = Compile("player", { showPowerBar = true, powerBarDetached = false }, DEFAULT_BARS)
Check(spec.power.texture == FG and spec.power.backgroundTexture == BG,
  "attached power bar did not use the global bar textures")

spec = Compile("player", { showPowerBar = true, powerBarDetached = true }, DEFAULT_BARS)
Check(spec.power.texture == FG,
  "unset detached foreground texture drifted from the global bar texture")
Check(spec.power.backgroundTexture == BG,
  "unset detached background texture borrowed the foreground art")

spec = Compile("target", { showPowerBar = true, powerBarDetached = true }, DEFAULT_BARS)
Check(spec.power.texture == FG and spec.power.backgroundTexture == BG,
  "non-player detached bar drifted from the global bar textures")

spec = Compile("player", { showPowerBar = true, powerBarDetached = true }, {
  detachedPowerBarTexture = "Flat", detachedPowerBarBgTexture = "Solid",
})
Check(spec.power.texture == "tex/Flat" and spec.power.backgroundTexture == "tex/Solid",
  "explicit detached texture overrides stopped applying")

--------------------------------------------------------------------------------
-- Power bars carry their own art: shared bars value, per-unit override, and the
-- Class Resources detached art as the most specific layer. Applies to every unit
-- and to attached bars, not just the detached Player bar.
--------------------------------------------------------------------------------

spec = Compile("target", { showPowerBar = true }, { powerBarTexture = "Flat", powerBarBgTexture = "Solid" })
Check(spec.power.texture == "tex/Flat" and spec.power.backgroundTexture == "tex/Solid",
  "shared power texture did not reach an attached non-player bar")
Check(spec.health.texture == FG, "power texture leaked onto the health bar")

spec = Compile("target", { showPowerBar = true, powerBarTexture = "Glaze", powerBarBgTexture = "Smooth" },
  { powerBarTexture = "Flat", powerBarBgTexture = "Solid" })
Check(spec.power.texture == "tex/Glaze" and spec.power.backgroundTexture == "tex/Smooth",
  "per-unit power texture did not override the shared bars value")

spec = Compile("player", { showPowerBar = true, powerBarDetached = true, powerBarTexture = "Glaze" },
  { powerBarTexture = "Flat", detachedPowerBarTexture = "Dragon" })
Check(spec.power.texture == "tex/Dragon",
  "Class Resources detached art lost to the per-unit power texture")

spec = Compile("player", { showPowerBar = true, powerBarDetached = true, powerBarTexture = "Glaze" },
  { powerBarTexture = "Flat" })
Check(spec.power.texture == "tex/Glaze",
  "detached Player bar dropped the per-unit power texture when Class Resources art is unset")

spec = Compile("player", { showPowerBar = true, powerBarDetached = false }, DEFAULT_BARS)
Check(spec.power.texture == FG,
  "unset power textures stopped following the frame bar texture")

-- The per-unit border must survive the detach compile untouched.
spec = Compile("target", {
  showPowerBar = true, powerBarDetached = true,
  powerBarBorderEnabled = true, powerBarBorderThickness = 5,
}, DEFAULT_BARS)
Check(spec.power.borderEnabled == true and spec.power.borderThickness == 5,
  "detached compile overwrote the per-unit power border")

--------------------------------------------------------------------------------
-- Part 3: the remaining writers agree with the compiled spec.
--------------------------------------------------------------------------------

-- The compiler owns the whole power-texture precedence now (shared bars value ->
-- per-unit override -> Class Resources detached art), so the global refresh must
-- read the finished spec instead of re-applying the detached override itself.
-- That keeps the original guarantee -- the detached value never leaks onto other
-- units -- without a Player special case or a second texture-key resolve.
local textureRuntime = Read("Runtime/MSUF_TextureRuntime.lua")
Check(not textureRuntime:find("texDPB", 1, true),
  "global texture refresh still re-applies the detached override instead of the compiled spec")
Check(textureRuntime:find("spec.power and spec.power.texture", 1, true),
  "global texture refresh no longer reads the compiled per-unit power texture")

local barBackground = Read("Runtime/MSUF_BarBackgroundRuntime.lua")
Check(barBackground:find('frame.MSUFUnitKey == "player"', 1, true),
  "detached background override is not scoped to the Player frame")
Check(not barBackground:find("dpbBgTex = _DPB.ResolveFg()", 1, true),
  "detached background still falls back to the foreground texture")

local rounded = Read("UnitFrames/Effects/MSUF_UF_RoundedFrames.lua")
Check(not rounded:find("bars.detachedPowerBarOutline", 1, true),
  "rounded detached power edge still reads the global outline")
Check(rounded:find("if power.borderEnabled ~= true then return 0 end", 1, true),
  "rounded detached power edge ignores the unit power border toggle")

local classPowerPage = Read("Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua")
Check(classPowerPage:find('SetControlEnabled(self.dpbTextures.outline, playerDetached and playerShape ~= "BAR")', 1, true),
  "Class Resources outline slider is not gated to the detached shapes it still owns")
Check(classPowerPage:find('TextureValues("Use global background texture")', 1, true),
  "detached background dropdown still advertises the foreground fallback")

print("detached power border/texture smoke: ok")
