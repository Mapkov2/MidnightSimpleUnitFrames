-- Classic dispel symbol chain contract.
--
-- Retail renders dispel symbols through the native 12.1 AuraContainer
-- (AddDispelTypeTexture + per-type candidate filters). Classic clients have no
-- such API and use a completely separate scan renderer, so
-- `.github/scripts/tests/dispel_symbol_indicator_smoke.lua` cannot cover them --
-- pointed at the Classic shadows it fails on every native assertion. That left
-- the Classic chain, for unit *and* group frames, with no coverage at all.
--
-- This pins the parts that decide whether a dispel symbol can appear when the
-- frame shows no aura icons, which is how the feature is normally used.

loadstring = loadstring or load

local root = assert(arg[1], "repository root argument missing")

local function Check(value, message)
  if not value then error(message or "check failed", 2) end
end

local function Read(relative)
  local path = root .. "/" .. relative
  local handle = assert(io.open(path, "rb"), "cannot open " .. path)
  local text = handle:read("*a") or ""
  handle:close()
  -- The editor saves CRLF; normalize so line-anchored patterns behave.
  return (text:gsub("\r\n", "\n"))
end

local runtime = Read("MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua")
local visuals = Read("MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Visuals.lua")
local unitConfig = Read("MidnightSimpleUnitFrames/Game/Classic/UnitFrames/MSUF_UF_Config.lua")
local groupConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")

--- 1. The symbol alone must be enough to start a scan. Without this the feature
--- silently needs the debuff icon lane to be on as well.
Check(runtime:find("local needsScan = borderEnabled == true or overlayEnabled == true or stripeEnabled == true or symbolEnabled == true", 1, true),
  "the compiled aura visual no longer starts a scan for a symbol-only setup")
Check(runtime:find("local directVisualEligible = stripeEnabled ~= true and symbolEnabled ~= true", 1, true),
  "the direct-visual shortcut no longer excludes the symbol")
Check(runtime:find("symbol = symbolEnabled and {", 1, true),
  "the compiled aura visual no longer carries the symbol table")

--- 2. Both lane gates must admit a scan-only debuff lane, so the symbol works
--- with every icon cap at 0.
Check(runtime:find("local needDebuffScan = visual and visual.enabled == true", 1, true),
  "the lane gate no longer derives a scan from the aura visual")
Check(runtime:find("if auraIconsEnabled or needDebuffScan then", 1, true),
  "the unit lane gate no longer admits a symbol-only scan")
Check(runtime:find("local debuff = (sourceEnabled and source.showDebuffs == true or needDebuffScan)", 1, true),
  "the group lane gate no longer admits a symbol-only scan")

--- 3. Every exit from the frame visual update must own the symbol host. The
--- direct branch used to skip it: turning the symbol off flips
--- directVisualEligible on, so that branch takes over and the last rendered
--- symbol stayed frozen on the frame forever.
local body = runtime:match("\nlocal function UpdateFrameAuraVisualState%(frame, state, cfg, unit%)\n(.-)\nend\n")
Check(body, "UpdateFrameAuraVisualState is no longer recognisable")
local directBranch = body:match("(if cfg and cfg%.visualDirect == true then.-\n    end)")
Check(directBranch, "the direct-visual branch is no longer recognisable")
Check(directBranch:find("HideDispelSymbols", 1, true),
  "the direct-visual branch leaves a stale dispel symbol on the frame")
Check(body:find("A3._UpdateClassicDispelSymbols(frame, lane, visual, unit)", 1, true),
  "the lane path no longer updates dispel symbols")

--- 4. Cross-file contract: every renderer entry point the runtime calls has to
--- exist in the Classic visuals module. Derived, not hardcoded, so a renamed
--- renderer function cannot silently no-op the feature (the runtime guards each
--- call with a type check and returns false).
local called, missing = {}, {}
for name in runtime:gmatch("renderer%.([A-Za-z]+)") do called[name] = true end
for name in runtime:gmatch("directRenderer%.([A-Za-z]+)") do called[name] = true end
local calledCount = 0
for name in pairs(called) do
  calledCount = calledCount + 1
  if not visuals:find("function V." .. name .. "(", 1, true) then
    missing[#missing + 1] = name
  end
end
Check(calledCount > 0, "no renderer entry points found in the Classic aura runtime")
Check(#missing == 0,
  "Classic visuals is missing renderer entry points the runtime calls: " .. table.concat(missing, ", "))

--- 5. Symbol art: all seven sets the menus offer must resolve, and the atlas
--- path must stay guarded -- an unknown atlas on an older client has to fall
--- through rather than blank the texture unnoticed.
Check(visuals:find("function V.SetDispelSymbolArt(texture, style, dispelType, tinted)", 1, true),
  "the Classic symbol art resolver is gone")
Check(visuals:find("AtlasKnown(atlas)", 1, true),
  "the Classic symbol art resolver no longer guards unknown atlases")
local STYLES = { "BLIZZARD", "BLIZZARD_RING", "BLIZZARD_BORDER",
  "MSUF_LETTERS", "MSUF_SHAPES", "MSUF_GLYPHS", "MSUF_MINIMAL" }
for i = 1, #STYLES do
  Check(visuals:find(STYLES[i], 1, true),
    "the Classic symbol art resolver no longer knows the " .. STYLES[i] .. " set")
end
local TYPES = { "Magic", "Curse", "Disease", "Poison", "Bleed" }
for i = 1, #TYPES do
  Check(visuals:find("        " .. TYPES[i] .. " = ", 1, true) or visuals:find(TYPES[i] .. " = \"", 1, true),
    "the Classic Blizzard symbol set no longer covers " .. TYPES[i])
end

--- 6. Both config sides must still compile the settings the runtime reads.
Check(unitConfig:find("out.dispelSymbol = symbol", 1, true)
  and unitConfig:find('UnitDispelValue("unitDispelSymbolEnabled", false)', 1, true),
  "the Classic unit config no longer compiles the dispel symbol")
Check(groupConfig:find("dispelSymbol", 1, true),
  "the group config no longer compiles the dispel symbol")
Check(runtime:find("local symbol = group and group.dispelSymbol or spec.dispelSymbol", 1, true),
  "the Classic aura runtime no longer reads both the unit and the group symbol config")

--- 7. Parity with Retail on older clients. A missing 12.1 debuff atlas used to
--- blank the texture, which produced a correctly sized but completely invisible
--- symbol row. It must fall back to MSUF art, which ships with the addon.
Check(not visuals:find("texture:SetTexture(nil)", 1, true),
  "the symbol art resolver still blanks the texture instead of falling back")
local fallbackFolder = visuals:match('local DISPEL_ART_FALLBACK_FOLDER = "([A-Za-z]+)"')
Check(fallbackFolder, "the symbol art fallback set is gone")
Check(visuals:find('%s*' .. fallbackFolder .. ' = "', 1, false) or visuals:find(fallbackFolder, 1, true),
  "the symbol art fallback names a set the resolver does not know")
for i = 1, #TYPES do
  local file = root .. "/MidnightSimpleUnitFrames/Media/Icons/DispelTypes/"
    .. fallbackFolder .. "/" .. TYPES[i]:lower() .. ".tga"
  local handle = io.open(file, "rb")
  Check(handle, "the symbol art fallback set is missing " .. TYPES[i] .. ".tga")
  handle:close()
end

--- 8. Colour overrides. Retail redirects an overridden dispel type to the
--- Tintable variant so it can be repainted; Classic has to repaint it itself.
Check(visuals:find("Tintable", 1, true),
  "the Classic symbol renderer no longer reaches the tintable art")
Check(visuals:find("tile:SetVertexColor(tint[1], tint[2], tint[3])", 1, true),
  "the Classic symbol renderer no longer applies an overridden dispel colour")
Check(visuals:find("tile:SetVertexColor(1, 1, 1)", 1, true),
  "the Classic symbol renderer no longer clears a stale tint")
Check(visuals:find("tile:Hide()", 1, true),
  "a symbol tile whose art failed to resolve is still shown")
for i = 1, #TYPES do
  local file = root .. "/MidnightSimpleUnitFrames/Media/Icons/DispelTypes/Tintable/"
    .. fallbackFolder .. "/" .. TYPES[i]:lower() .. ".tga"
  local handle = io.open(file, "rb")
  Check(handle, "the tintable fallback set is missing " .. TYPES[i] .. ".tga")
  handle:close()
end

--- The tint signature must be stamped by the compile. Rebuilding it in the
--- renderer would run per frame per aura event.
Check(runtime:find("tintKey = symbolTintKey,", 1, true),
  "the compile no longer stamps a dispel tint signature")
Check(visuals:find('tostring(cfg.tintKey or "")', 1, true),
  "the symbol cache signature ignores the dispel tint, so overrides never repaint")
Check(not visuals:find("symbolTintKey", 1, true),
  "the renderer rebuilds the dispel tint signature instead of using the stamped one")

print("classic_dispel_symbol_chain_smoke: ok")
