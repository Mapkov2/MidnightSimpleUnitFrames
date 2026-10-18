-- Native health-bar queries absent from the permissive widget fixture: an anchored size and a new child's level.
-- Resolve the actual anchor graph, without a spec, expected value or preview-specific layout painter.
local Fixture = {}
local function Factor(point, axis)
 if axis == "width" then
  if point:find("LEFT", 1, true) then return 0 end
  if point:find("RIGHT", 1, true) then return 1 end
 else
  if point:find("BOTTOM", 1, true) then return 0 end
  if point:find("TOP", 1, true) then return 1 end
 end
 return 0.5
end
local function Dimension(region, axis, depth)
 if type(region) ~= "table" or (depth or 0) > 20 then return 0 end
 if region.allPoints then return Dimension(region.allPoints, axis, (depth or 0) + 1) end
 local points = region.points or {}
 for i = 1, #points do
  local a = points[i]
  for j = i + 1, #points do
   local b = points[j]
   local af, bf = Factor(a.point, axis), Factor(b.point, axis)
   if af ~= bf and a.relativeTo == b.relativeTo and a.relativeTo ~= region then
    local relative = a.relativeTo or region.parent
    local size = Dimension(relative, axis, (depth or 0) + 1)
    local ratio = relative and relative:GetEffectiveScale() / region:GetEffectiveScale() or 1
    local offset = axis == "width" and "x" or "y"
    return math.abs(((Factor(b.relativePoint or b.point, axis) - Factor(a.relativePoint or a.point, axis)) * size * ratio
     + (b[offset] or 0) - (a[offset] or 0)) / (bf - af))
   end
  end
 end
 return rawget(region, axis) or 0
end
local function Decorate(bar)
 if not bar or bar._unitSceneRegionFixture then return end
 bar._unitSceneRegionFixture = true
 bar.GetWidth = function(self) return Dimension(self, "width") end
 bar.GetHeight = function(self) return Dimension(self, "height") end
 -- WoW gives a new child its parent's level + 1; the shared fixture defaults every frame to 1.
 if bar:GetFrameLevel() == 1 and bar:GetParent() then bar.frameLevel = bar:GetParent():GetFrameLevel() + 1 end
end
function Fixture.Install(core)
 local health = assert(core.UF.elements.Health)
 if health._unitSceneRegionFixture then return end
 health._unitSceneRegionFixture = true
 local create = health.Create
 health.Create = function(frame, ...)
  local result = create(frame, ...)
  if frame._msufPreviewScene and frame._msufSceneUnit then Decorate(frame.hpBar) end
  return result
 end
end
return Fixture
