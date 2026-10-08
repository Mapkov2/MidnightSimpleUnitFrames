-- Probe A: with "Auto-scale indicators on resize" on, the full group compile
-- scales the Group Number / Level / Threat text sizes by the resize ratio, but
-- the in-place font-domain refresh (GF.RefreshCompiledSpecDomains(kind, DIRTY_FONT))
-- rewrites them unscaled. Loads the real Group_Config.lua with minimal stubs.
local ROOT = assert(arg[1]) .. "/MidnightSimpleUnitFrames/"

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.MSUF_GetGeneralDB = function() return {} end
local function Num(v, f) v = tonumber(v) if v == nil then return f end return v end

local conf = {
  autoScaleIndicatorsOnResize = true,
  showGroupNumber = true, groupNumberSize = 10,
  levelText = true, levelTextSize = 10, levelTextDifficultyColor = false,
  threatText = true, threatTextSize = 9,
}

local ns = {
  ExportPublic = function(n, v) _G[n] = v return v end,
  Client = { Family = "Classic", IsVanilla = true, SupportsThreatText = true },
  GF = {
    DIRTY_FONT = 0x04, DIRTY_COLOR = 0x08, DIRTY_BORDER = 0x10, DIRTY_AGGRO = 0x20,
    -- e.g. Group frame scale 150 % or a size tier 1.5x the base size
    GetResizeScale = function() return 1.5 end,
    GetConf = function() return conf end,
  },
  UF = {
    NumberWithFallback = Num,
    Shared = {
      AddEvent = function(list, e) list = list or {} list[#list + 1] = e return list end,
      ResolveTextSlotFontSize = function(_, _, _, f) return f end,
      ResolveTextSlotHidePercentSymbol = function() return false end,
      ResolvePowerTextColorByType = function() return false end,
    },
  },
}
ns.Require = function(n) return _G[n] end
local GF = ns.GF

local chunk = assert(loadfile(ROOT .. "UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua"))
chunk("MidnightSimpleUnitFrames", ns)

local function up(fn, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not n then return nil end
    if n == name then return v end
    i = i + 1
  end
end
local CompileSpecUncached = up(GF.CompileSpec, "CompileSpecUncached")
local CompileStatus = up(CompileSpecUncached, "CompileStatus")

-- Same status table the full compile stores in the cached base spec.
local status = CompileStatus("raid", conf)
print("full compile : groupNumber=" .. status.raidGroup.size .. " level=" .. status.level.size .. " threat=" .. status.threat.size)

-- Install it as the cached base (exactly what GF.CompileSpec caches) and run
-- the in-place font refresh the menu uses for the Group Number Size slider
-- (MSUF_Menu2_GroupIndicators.lua:310 applies with mode "font").
GF._compiledSpec.raid = { status = status, text = {}, textColor = {}, _msufGFConf = conf, height = 32 }
GF.RefreshCompiledSpecDomains("raid", GF.DIRTY_FONT)
print("after font refresh: groupNumber=" .. status.raidGroup.size .. " level=" .. status.level.size .. " threat=" .. status.threat.size)
print("expected (same rule as full compile): groupNumber=15 level=15 threat=14")

assert(status.raidGroup.size == 15 and status.level.size == 15 and status.threat.size == 14, "font refresh lost resize scale")
