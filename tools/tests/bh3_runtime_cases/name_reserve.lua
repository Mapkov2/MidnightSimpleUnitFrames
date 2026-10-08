-- Probe: does Text.Apply re-run the name clip width when only a NAMERIGHT
-- status setting (level / raid group) changes? Loads the real Text_Layout file.
local ROOT = arg[1] .. "/MidnightSimpleUnitFrames/"

local widthCalls = {}
local function NewRegion(kind, name)
  local r = { _kind = kind, _name = name, _shown = true, _text = nil }
  local methods = {}
  function methods.GetParent(self) return self._parent end
  function methods.SetParent(self, p) self._parent = p end
  function methods.GetText(self) return self._text end
  function methods.SetText(self, t) self._text = t end
  function methods.GetFont(self) return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
  function methods.GetStringWidth(self) return 52 * 7 end -- 7px per glyph
  function methods.IsShown(self) return self._shown end
  function methods.Show(self) self._shown = true end
  function methods.Hide(self) self._shown = false end
  function methods.SetShown(self, v) self._shown = v and true or false end
  function methods.GetFrameLevel(self) return 5 end
  function methods.GetWidth(self) return 150 end
  function methods.SetWidth(self, w)
    if self._name == "nameText" then widthCalls[#widthCalls + 1] = w end
  end
  function methods.CreateFontString(self, n)
    local fs = NewRegion("FontString", "fs") ; fs._parent = self ; return fs
  end
  function methods.IsMouseOver() return false end
  setmetatable(r, { __index = function(t, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:match("^%u") and not k:match("^MSUF") then return function() end end
    return nil
  end })
  return r
end

_G.UIParent = NewRegion("Frame", "UIParent")
local function CreateFrame(kind, name, parent)
  local f = NewRegion(kind, name or "frame"); f._parent = parent; return f
end
_G.CreateFrame = CreateFrame

local Text = {}
Text.CreateFrame = CreateFrame
Text.UF = { Layers = {} }
Text.tonumber = tonumber
Text.floor = math.floor
Text.max = math.max
Text.EMPTY_EVENTS = {}
Text.DrawSubLayer = function(l, d) return tonumber(l) or d end
Text.ClampFrameLayer = function(l, d) return tonumber(l) or d end
Text.GetLayerBaseLevel = function() return 5 end
Text.SetFrameLevelCached = function() end
Text.SetShownCached = function(o, v) if o then o._msufShown = v and true or false end end
Text.SetTextCached = function(o, v) if o then o._text = v end end
Text.SetFont = function() return true end
Text.ApplyNameTextColor = function() end
Text.ResolveHealthTextModes = function() return "NONE", "NONE", "NONE" end
Text.CompileTextRuntime = function(frame) frame._msufTextRuntime = frame._msufTextRuntime or {} ; return frame._msufTextRuntime end
Text.SetHealthTextColor = function() end
Text.UpdateHealthTextColor = function() end
local MSUF = { UFText = Text }
_G.issecretvalue = function() return false end

local chunk = assert(loadfile(ROOT .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

local frame = CreateFrame("Button", "MSUF_target")
frame.MSUFUnitKey = "target"
local nameText = NewRegion("FontString", "nameText")
nameText._parent = frame
frame.nameText = nameText

local function Spec(levelEnabled)
  return {
    key = "target", width = 150, showName = true, showHealthText = false, showPowerText = false,
    text = { nameShorten = true, nameShortenMax = 20, nameShortenDots = true, nameAnchor = "TOPLEFT" },
    status = { level = { enabled = levelEnabled, anchor = "NAMERIGHT" } },
  }
end

Text.Apply(frame, Spec(false))
print("apply 1 (level off): nameText SetWidth calls = " .. table.concat(widthCalls, ","))
widthCalls = {}
Text.Apply(frame, Spec(true))
assert(widthCalls[1] == 94, "name reservation not invalidated")
print("apply 2 (level on NAMERIGHT): nameText SetWidth calls = " .. (#widthCalls > 0 and table.concat(widthCalls, ",") or "<none>"))
print("expected: apply 2 narrows the name window by 26px to 94 (120 - 26)")
-- control: a fresh frame with level on from the start
local frame2 = CreateFrame("Button", "MSUF_target2")
frame2.MSUFUnitKey = "target"
local nt2 = NewRegion("FontString", "nameText") ; nt2._parent = frame2 ; frame2.nameText = nt2
widthCalls = {}
Text.Apply(frame2, Spec(true))
print("control fresh frame, level on: nameText SetWidth calls = " .. table.concat(widthCalls, ","))
