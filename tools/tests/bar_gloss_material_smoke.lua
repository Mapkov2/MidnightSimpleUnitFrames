-- Material topology must not regress to two flat half-bar rectangles.
-- Native pixel appearance still requires a WoW client; this checks the actual
-- painter's regions, bundled alpha art and cached configuration writes.
local root, flavor, sourceOverride = assert(arg[1]), arg[2] or "Mainline", arg[3]
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "home", beforeCore = function(world)
  if not sourceOverride then return end
  local load = world.LoadFile
  world.LoadFile = function(self, path, ...)
    if path:sub(-#"MSUF_UF_Elements_BarGloss.lua") == "MSUF_UF_Elements_BarGloss.lua" then path = sourceOverride end
    return load(self, path, ...)
  end
end })
local core, env = mw.core, mw.env
local Common = core.UFBarTextCommon
local checks = 0
local function Check(ok, label) checks = checks + 1 assert(ok, flavor .. ": " .. label) end
local frame = env.CreateFrame("Button", nil, env.UIParent)
local bar = env.CreateFrame("StatusBar", nil, frame)
bar:SetSize(180, 40)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
bar:SetStatusBarColor(0, 0, 0, 0.8)
Common.ApplyBarGloss(frame, bar, { enabled = true, strength = 1 }, "hpGloss", 1)
local gloss, target = assert(frame.hpGloss), bar:GetStatusBarTexture()
local function FullFill(region, label)
  local top, bottom = false, false
  for index = 1, region:GetNumPoints() do
    local point, anchor, relative = region:GetPoint(index)
    if point == "TOPLEFT" and anchor == target and relative == "TOPLEFT" then top = true end
    if point == "BOTTOMRIGHT" and anchor == target and relative == "BOTTOMRIGHT" then bottom = true end
    Check(relative ~= "LEFT" and relative ~= "RIGHT", label .. " retained a hard midpoint seam")
  end
  Check(top and bottom, label .. " does not span the entire native fill")
end
-- Sample the actual bundled alpha through the painter's UVs. Icon glints
-- that move diagonally across X must never be stretched across a wide bar.
local function AlphaAt(data, width, height, u, v)
  if u < 0 or u > 1 or v < 0 or v > 1 then return 0 end
  local x = math.max(0, math.min(width - 1, math.floor(u * width)))
  local y = math.max(0, math.min(height - 1, math.floor(v * height)))
  local topOrigin = math.floor(data:byte(18) / 32) % 2 == 1
  if not topOrigin then y = height - 1 - y end
  return data:byte(19 + data:byte(1) + (y * width + x) * 4 + 3)
end

local profiles = {
  upper = { "msuf_skin_gloss_top.tga", 0.125, 0.875, 0, 2, 0.65 },
  lower = { "msuf_skin_gloss_top.tga", 0.125, 0.875, 2, 0, 0.08 },
}
local reflection, regions = {}, {}
for _, band in ipairs({ "upper", "lower" }) do
  local region = assert(gloss[band])
  FullFill(region, band)
  local r, g, b, a = region:GetVertexColor()
  Check(r == g and g == b and r > 0 and r <= 1 and a > 0 and a <= 1, band .. " is not restrained neutral reflected light")
  Check(region.gradient == nil and region.colorTexture == nil, band .. " retained a flat gradient or solid-colour plate")
  local profile = profiles[band]
  local left, right, top, bottom = region:GetTexCoord()
  -- This widget fixture omits native Texture's default full-image coordinates.
  if left == nil and right == nil and top == nil and bottom == nil then left, right, top, bottom = 0, 1, 0, 1 end
  regions[band] = { region, left, right, top, bottom }
  local texture = region:GetTexture()
  Check(texture:sub(-#profile[1]) == profile[1], band .. " specular profile artwork differs")
  Check(type(texture) == "string" and texture:find("Media\\Skins\\msuf_skin_gloss_", 1, true),
    band .. " does not use bundled specular alpha artwork")
  local localPath = root .. "/MidnightSimpleUnitFrames/" .. texture:match("(Media\\Skins\\.+)$"):gsub("\\", "/")
  local file = assert(io.open(localPath, "rb"))
  local data = file:read("*a") file:close()
  local function Word(at) return data:byte(at) + 256 * data:byte(at + 1) end
  local width, height, depth = Word(13), Word(15), data:byte(17)
  Check(data:byte(3) == 2 and depth == 32 and width >= 32 and height >= 32, band .. " alpha artwork format changed")
  local first = 19 + data:byte(1)
  local unique, count, clear, lit = {}, 0, 0, 0
  for pixel = 0, width * height - 1 do
    local alpha = data:byte(first + pixel * 4 + 3)
    if not unique[alpha] then unique[alpha], count = true, count + 1 end
    if alpha == 0 then clear = clear + 1 end
    if alpha > 0 then lit = lit + 1 end
  end
  Check(count > 16 and clear > 0 and lit > 0, band .. " lost smooth transparent specular shape")
  local horizontal = true
  for row = 0, 64 do
    local v = top + (bottom - top) * row / 64
    local low, high = 255, 0
    for column = 0, 16 do
      local u = left + (right - left) * column / 16
      local alpha = AlphaAt(data, width, height, u, v)
      low, high = math.min(low, alpha), math.max(high, alpha)
    end
    if high - low > 1 then horizontal = false break end
  end
  Check(horizontal, band .. " reflection creates a diagonal streak across wide bars")
  -- Measure both real texture profiles together at the configured strength.
  -- A top reflection may glint; it must not turn the bar into a white plate.
  for row = 0, 255 do
    local v = top + (bottom - top) * (row + 0.5) / 256
    local alpha = AlphaAt(data, width, height, (left + right) / 2, v) / 255
    -- RGB carries material intensity; native opacity is applied exactly once.
    reflection[row + 1] = (reflection[row + 1] or 0) + alpha * r * region:GetAlpha()
  end
end
-- Bound both sides of the reported failure using the real artwork, not only
-- shader constants: max strength must show a distinct glint without washing
-- the body white. This rejects both the nearly invisible attenuation and the
-- older broad highlight. These are offline material bounds, not GPU proof.
local peak, total, bright, middle = 0, 0, 0, 0
for row, alpha in ipairs(reflection) do
  peak, total = math.max(peak, alpha), total + alpha
  if alpha > 0.12 then bright = bright + 1 end
  local position = (row - 0.5) / #reflection
  if position >= 0.2 and position <= 0.8 then middle = math.max(middle, alpha) end
end
Check(peak >= 0.25, "maximum strength has no visible specular glint")
Check(peak <= 0.5 and total / #reflection <= 0.055, "maximum strength over-whitens the native bar")
Check(bright / #reflection <= 0.17 and middle <= 0.02, "reflection remains a broad plate across the bar body")
for _, band in ipairs({ "upper", "lower" }) do
  local entry, profile = regions[band], profiles[band]
  Check(entry[1]:GetBlendMode() == "ADD", band .. " additive reflected-light blend changed")
  Check(entry[2] == profile[2] and entry[3] == profile[3] and entry[4] == profile[4] and entry[5] == profile[5],
    band .. " icon-endcap crop or compressed artwork coordinates changed")
  Check(math.abs(gloss[band]:GetVertexColor() - profile[6]) < 0.000001, band .. " material dose differs")
end
Common.ApplyBarGloss(frame, bar, { enabled = true, strength = 0.6 }, "hpGloss")
local br, bg, bb, ba = bar:GetStatusBarColor()
Check(br == 0 and bg == 0 and bb == 0 and ba == 0.8, "specular material changed dark-mode base colour or alpha")
bar:SetStatusBarColor(0.7, 0.2, 0.1, 0.8)
Common.ApplyBarGloss(frame, bar, { enabled = true, strength = 0.6 }, "hpGloss")
br, bg, bb, ba = bar:GetStatusBarColor()
Check(br == 0.7 and bg == 0.2 and bb == 0.1 and ba == 0.8, "specular material replaced class-coloured base or alpha")
local firstDose = { (gloss.upper:GetVertexColor()), (gloss.lower:GetVertexColor()) }
Common.ApplyBarGloss(frame, bar, { enabled = true, strength = 0.3 }, "hpGloss")
Check(gloss.upper:GetVertexColor() < firstDose[1]
  and gloss.lower:GetVertexColor() < firstDose[2], "strength does not scale both reflections")
Common.ApplyBarGloss(frame, bar, { enabled = true, strength = 1 }, "hpGloss")
Check(math.abs(gloss.upper:GetVertexColor() - 0.65) < 0.000001
  and math.abs(gloss.lower:GetVertexColor() - 0.08) < 0.000001,
  "100 percent strength does not retain the full visible reflection range")
Common.ApplyBarGloss(frame, bar, { enabled = true, strength = 0.3 }, "hpGloss")
local writes = 0
for _, region in ipairs({ gloss.upper, gloss.lower }) do
  for _, name in ipairs({ "SetTexture", "SetTexCoord", "SetBlendMode", "SetVertexColor", "SetPoint", "SetGradient", "SetGradientAlpha" }) do
    local original = region[name]
    if original then region[name] = function(self, ...) writes = writes + 1 return original(self, ...) end end
  end
end
for pass = 1, 20 do Common.ApplyBarGloss(frame, bar, { enabled = true, strength = 0.3 }, "hpGloss") end
Check(writes == 0 and frame.hpGloss == gloss, "unchanged material writes native artwork or replaces regions")
print("bar gloss material smoke: " .. flavor .. " PASS (" .. checks .. " checks; visible narrow specular art)")
