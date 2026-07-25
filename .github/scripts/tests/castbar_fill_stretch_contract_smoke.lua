-- Castbar fill textures must stretch across the bar, never tile.
--
-- Beta 27 report: "Cast Bar Texture is not being streched correctly" — a hard
-- seam appeared near the right edge of the cast bar. Cause: the castbar status
-- bar fill was created with `SetHorizTile(true)`, so the art was drawn at its
-- native width and repeated instead of being scaled to the bar.
--
-- The shipped bar media in Media/Bars/ is 256px wide, while the default castbar
-- widths are castbarPlayerBarWidth = 271 and castbarTargetBarWidth = 272. Every
-- default player/target castbar therefore ran ~15-16px past one tile and showed
-- the start of a second copy of the texture. Narrower bars (focus = 175) were
-- cropped instead, so the right end of the gradient never rendered at all.
--
-- Health/power bars consume the same media via SetStatusBarTexture without ever
-- touching tiling, which is why only castbars looked wrong. This contract keeps
-- the two paths consistent: the flag had survived six castbar refactors before
-- it was caught, so assert it at the source level rather than trusting review.

_G = _G or _ENV

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
  -- The editor saves CRLF; normalize so line-oriented patterns behave locally
  -- and in CI alike.
  return (source:gsub("\r\n", "\n"))
end

local function CountMatches(source, pattern)
  local count = 0
  for _ in source:gmatch(pattern) do count = count + 1 end
  return count
end

--------------------------------------------------------------------------------
-- Part 1: no castbar source may re-enable horizontal tiling.
--------------------------------------------------------------------------------

-- Every castbar file that sets a status bar fill. Listed explicitly so a new
-- castbar module that reintroduces tiling has to be added here consciously.
local CASTBAR_SOURCES = {
  "Castbars/MSUF_CastbarFrames.lua",
  "Castbars/MSUF_Castbars.lua",
  "Castbars/MSUF_Castbars_Core.lua",
  "Castbars/MSUF_CastbarVisuals.lua",
  "Castbars/MSUF_CastbarStyle.lua",
  "Castbars/MSUF_CastbarUtils.lua",
  "Castbars/MSUF_BossCastbars.lua",
  "Castbars/MSUF_CastbarPreviews.lua",
  "Castbars/MSUF_BossCastbars_Preview.lua",
}

for _, relativePath in ipairs(CASTBAR_SOURCES) do
  local source = Read(relativePath)
  Check(
    not source:find("SetHorizTile%s*%(%s*true%s*%)"),
    relativePath .. ": castbar fill must not SetHorizTile(true) — tiling repeats "
      .. "the 256px art and seams on default 271/272px bars"
  )
  Check(
    not source:find("SetVertTile%s*%(%s*true%s*%)"),
    relativePath .. ": castbar fill must not SetVertTile(true) — bar art is 32px "
      .. "tall and must scale to the configured bar height"
  )
end

--------------------------------------------------------------------------------
-- Part 2: the stretch is asserted explicitly, not left to the WoW default.
--------------------------------------------------------------------------------

-- A StatusBar reuses one fill Texture object across SetStatusBarTexture swaps,
-- so tiling state set once would persist for the whole session. Forcing `false`
-- on the media-swap path is what guarantees a stale flag cannot survive.
local EXPECTED_STRETCH_SITES = {
  -- target/focus/boss builder + preview builder
  ["Castbars/MSUF_CastbarFrames.lua"] = 2,
  -- player castbar builder
  ["Castbars/MSUF_Castbars.lua"] = 1,
  -- UpdateTextureForFrame: runs on every texture/media change
  ["Castbars/MSUF_Castbars_Core.lua"] = 1,
}

for relativePath, expected in pairs(EXPECTED_STRETCH_SITES) do
  local source = Read(relativePath)
  local found = CountMatches(source, "SetHorizTile%s*%(%s*false%s*%)")
  Check(
    found >= expected,
    string.format(
      "%s: expected at least %d explicit SetHorizTile(false) call(s) on the "
        .. "castbar fill, found %d — dropping one lets a tiled fill persist "
        .. "across media swaps",
      relativePath, expected, found
    )
  )
end

--------------------------------------------------------------------------------
-- Part 3: the premise still holds — bar art is 256px, castbar defaults exceed it.
--------------------------------------------------------------------------------

-- If the shipped art ever became wider than every default castbar, the seam
-- would vanish on defaults and this bug would look "fixed" without the flag
-- being right. Pin the geometry that makes tiling observably wrong.
local function TgaWidth(relativePath)
  local file = assert(io.open(ADDON .. relativePath, "rb"), "missing art: " .. relativePath)
  file:seek("set", 12)
  local header = file:read(2)
  file:close()
  if not header or #header < 2 then return nil end
  return header:byte(1) + (header:byte(2) * 256)
end

local DEFAULT_TEXTURE = "Media/Bars/MSUF_Lucent_v2.tga"
local artWidth = TgaWidth(DEFAULT_TEXTURE)
Check(artWidth == 256, string.format(
  "%s: expected 256px-wide bar art, got %s — revisit the castbar tiling contract",
  DEFAULT_TEXTURE, tostring(artWidth)
))

local defaults = Read("State/MSUF_Defaults.lua")
for _, key in ipairs({ "castbarPlayerBarWidth", "castbarTargetBarWidth" }) do
  local width = tonumber(defaults:match(key .. "%s*=%s*(%d+)"))
  Check(width, "State/MSUF_Defaults.lua: could not read default " .. key)
  Check(width > artWidth, string.format(
    "default %s (%d) is no longer wider than the %dpx bar art; the tiling seam "
      .. "this contract guards would not reproduce on defaults",
    key, width, artWidth
  ))
end

print("castbar_fill_stretch_contract_smoke: OK")
