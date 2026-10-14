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

Text.TruncateName = TruncateName

return SetNameTextCached, TruncateName
end
