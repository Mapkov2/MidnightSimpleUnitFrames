-- UF responsibility owner; dependencies bind once before runtime.
local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

MSUF.UFModuleFactories.TextName = function(
  ApplyNameTextColor, RefreshNameCenterClipFit, RegionShown, SetTextCached, Text, floor, issecretvalue, string_byte, string_sub, tonumber
)

function Text.UpdateNameColor(frame, event, unit)
  if RegionShown(frame and frame.nameText) then
    ApplyNameTextColor(frame, unit or frame.MSUFUnitKey)
    local rt = frame and frame._msufTextRuntime
    if rt and rt.inlineToT and frame._msufIdentityInlineToTScheduled ~= true then
      Text.UpdateInline(frame, event, unit)
    end
  end
end

-- Start of the UTF-8 character after the one at pos. File scope: a closure
-- here would be built again for every name update.
local function NextUtf8Byte(name, pos)
  -- Every caller stays within the counted byte string at a character start.
  local byte = string_byte(name, pos)
  if byte < 128 then return pos + 1 end
  if byte < 224 then return pos + 2 end
  if byte < 240 then return pos + 3 end
  return pos + 4
end

-- Native 5.73 Group Frames shortened the actual UTF-8 name and only added
-- dots when its character count exceeded the configured cap. Preserve that
-- behavior for migrated Group profiles instead of showing 6.0's separate
-- clip-marker FontString for every name while shortening is merely enabled.
local function TruncateName(name, maxChars, showDots, clipSide)
  maxChars = floor((tonumber(maxChars) or 0) + 0.5)
  -- maxChars is plain configuration, so the common path (no legacy
  -- truncation) still returns before the native predicate.
  if maxChars <= 0 or issecretvalue(name) == true or not name then return name end

  local count, pos, byteLength = 0, 1, #name
  while pos <= byteLength do
    count = count + 1
    pos = NextUtf8Byte(name, pos)
  end
  if count <= maxChars then return name end

  local dots = showDots == true and ".." or ""
  if clipSide == "LEFT" then
    pos = 1
    for _ = 1, count - maxChars do pos = NextUtf8Byte(name, pos) end
    return dots .. string_sub(name, pos)
  end

  count, pos = 0, 1
  while pos <= byteLength and count < maxChars do
    count = count + 1
    pos = NextUtf8Byte(name, pos)
  end
  return string_sub(name, 1, pos - 1) .. dots
end

-- Presets are plain configuration; missing or unknown values keep the old path.
local NAME_FORMATS = {
  FULL = { false, 0 }, ABBREV = { true, 0 }, CUT = { false, -1 }, ABBREV_CUT = { true, -1 },
  VERYSHORT = { false, 4 }, SHORT = { false, 10 }, MEDIUM = { false, 15 },
  ABBREV_VERYSHORT = { true, 4 }, ABBREV_SHORT = { true, 10 }, ABBREV_MEDIUM = { true, 15 },
}
local string_find = string.find

function Text.ResolveNameFormat(value)
  return NAME_FORMATS[value] and value or nil
end

-- Describe fixed legacy presets without changing their stored identities.
-- Editors can show the effective method and cap from this same registry.
function Text.DescribeNameFormat(mode, maxChars, showDots, side)
  local preset = NAME_FORMATS[mode]
  if not preset then return nil, maxChars, showDots, side end
  if preset[2] >= 0 then maxChars, showDots, side = preset[2], false, "RIGHT" end
  local limited = preset[2] ~= 0
  local method = preset[1] and (limited and "ABBREV_CUT" or "ABBREV") or (limited and "CUT" or "FULL")
  return method, maxChars, showDots, side
end

local function AbbreviateName(name)
  local first, last = string_find(name, "%S+")
  if not first then return name end
  local nextFirst, nextLast = string_find(name, "%S+", last + 1)
  if not nextFirst then return name end
  local result = ""
  while nextFirst do
    result = result .. string_sub(name, first, NextUtf8Byte(name, first) - 1) .. ". "
    first, last = nextFirst, nextLast
    nextFirst, nextLast = string_find(name, "%S+", last + 1)
  end
  return result .. string_sub(name, first, last)
end

local function FormattedName(name, maxChars, showDots, clipSide, frame, mode)
  -- Never inspect, compare or cache a secret, even when an earlier name was plain.
  if issecretvalue(name) == true then return name end
  if name == nil then return name end
  local preset = NAME_FORMATS[mode]
  if preset[2] >= 0 then
    maxChars, showDots, clipSide = preset[2], false, "RIGHT"
  else
    maxChars = floor((tonumber(maxChars) or 6) + 0.5)
    if maxChars < 1 then maxChars = 6 elseif maxChars > 40 then maxChars = 40 end
    showDots = showDots == true
    clipSide = clipSide == "LEFT" and "LEFT" or "RIGHT"
  end
  if frame._msufNameFormatInput == name and frame._msufNameFormatMode == mode
    and frame._msufNameFormatMax == maxChars and frame._msufNameFormatDots == showDots
    and frame._msufNameFormatSide == clipSide then
    return frame._msufNameFormatOutput
  end
  local value = name
  if preset[1] then value = AbbreviateName(value) end
  if maxChars > 0 then value = TruncateName(value, maxChars, showDots, clipSide) end
  frame._msufNameFormatMax, frame._msufNameFormatDots, frame._msufNameFormatSide = maxChars, showDots, clipSide
  frame._msufNameFormatInput, frame._msufNameFormatMode, frame._msufNameFormatOutput = name, mode, value
  return value
end

local function SetNameTextCached(frame, value)
  SetTextCached(frame.nameText, value)
  local proxy = frame._msufNameAnchorTextActive == true and frame._msufNameAnchorText
  if proxy then SetTextCached(proxy, value) end
  -- Any no-ellipsis clip window (side or centered) needs the warm fit: it
  -- tracks whether the name really overflows the window, which decides the
  -- NAMELEFT/NAMERIGHT status anchor target.
  if frame._msufNameInlineClip ~= nil and RefreshNameCenterClipFit then
    RefreshNameCenterClipFit(frame)
  end
  -- Aura Name Overlay effects copy this text (MSUF_Auras3_SpellIndicators_Effects.lua).
  local mirror = frame._msufNameTextMirror
  if mirror then mirror(frame) end
end

function Text.FormatName(frame, name, mode, maxChars, showDots, clipSide)
  return FormattedName(name, maxChars, showDots, clipSide, frame, mode)
end
Text.NameFormatter = FormattedName
Text.TruncateName = TruncateName

return SetNameTextCached, TruncateName
end
