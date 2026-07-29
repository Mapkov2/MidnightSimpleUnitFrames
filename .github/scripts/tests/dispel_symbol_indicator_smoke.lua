-- Dispel-type symbol indicator contract.
--
-- The symbol names WHICH debuff type is on a unit. Everything that makes that
-- safe and cheap lives in invariants that are easy to break by accident:
--
--   * MSUF must never read the aura's dispelName. The type is resolved by
--     Blizzard inside its secure partition; MSUF only hands over a texture and
--     an options table (AddDispelTypeTexture) or a candidate filter.
--   * The preview is MSUF-owned (Blizzard owns the live button's visibility),
--     so it must borrow the LIVE geometry helper or it will drift from what a
--     real debuff looks like.
--   * ALL mode costs one native aura slot per dispel type. TOP must stay the
--     default, and the per-type filter tables must not be reallocated per
--     compile.
--   * The group config cache keys off a signature that is stamped where the
--     settings are read, not rebuilt on the per-frame resolve path.
--
-- Usage from the repository root:
--   lua .github/scripts/tests/dispel_symbol_indicator_smoke.lua <repoRoot>

-- Captured here: the main chunk is vararg, nested functions are not.
local SUPPLIED_ROOT = ...

local function Exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end

local function Join(left, right)
    left = tostring(left or ""):gsub("[/\\]+$", "")
    right = tostring(right or ""):gsub("^[/\\]+", "")
    return left == "." and "./" .. right or left .. "/" .. right
end

local MARKER = "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"

local function ResolveRepositoryRoot()
    if SUPPLIED_ROOT and Exists(Join(SUPPLIED_ROOT, MARKER)) then return SUPPLIED_ROOT end
    for _, root in ipairs({ ".", "..", "../..", "../../.." }) do
        if Exists(Join(root, MARKER)) then return root end
    end
    error("repository root not found")
end

local ROOT = ResolveRepositoryRoot()

-- The editor saves CRLF; contract patterns are written with "\n".
local function Read(relative)
    local path = Join(ROOT, relative)
    local file, err = io.open(path, "rb")
    assert(file, path .. ": " .. tostring(err))
    local content = file:read("*a") or ""
    file:close()
    return (content:gsub("\r\n", "\n"))
end

local failures = 0
local function Check(condition, message)
    if condition then return true end
    failures = failures + 1
    io.write("FAIL: ", tostring(message), "\n")
    return false
end

local function Contains(haystack, needle, message)
    return Check(haystack:find(needle, 1, true) ~= nil, message)
end

local auras = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
local unitConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua")
local groupConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
local core = Read("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
local groupPreview = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
local globalBars = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua")
local groupBars = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua")

-- === 1. Secret safety: the type is never read on the MSUF side ==============
-- Reading auraData.dispelName from insecure code is the failure this whole
-- design exists to avoid. The symbol must be expressed purely as native options.
-- Comment lines are stripped first: the design is explained in prose that names
-- the field, and that prose must not be what keeps this check honest.
local function StripComments(source)
    local out = {}
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        if not line:match("^%s*%-%-") then out[#out + 1] = line end
    end
    return table.concat(out, "\n")
end
Check(not StripComments(auras):find("dispelName", 1, true),
    "Auras3 reads dispelName -- the dispel type is secret and must stay inside Blizzard's partition")
Contains(auras, "button:AddDispelTypeTexture(region, DS.Options(sensor.style))",
    "the symbol region is no longer bound through AddDispelTypeTexture")
for _, style in ipairs({ "CustomAsset", "BorderWithIcon", "Border", "Icon" }) do
    Contains(auras, "styles." .. style,
        "symbol options no longer reference the " .. style .. " texture style")
end
-- PreserveAsset would keep MSUF art and only tint it, which cannot express a
-- per-type symbol. It must remain the border/overlay path only.
Check(not auras:find("DS.options.style = styles and styles.PreserveAsset", 1, true),
    "symbol options fell back to PreserveAsset, which cannot show a per-type symbol")

-- === 2. All five 12.1 dispel types, including Bleed ========================
-- Bleed is new in 12.1; a set that silently omits it shows nothing for bleeds.
for _, dispelType in ipairs({ "Magic", "Curse", "Disease", "Poison", "Bleed" }) do
    Contains(auras, "RaidFrame-Icon-Debuff" .. dispelType,
        "Blizzard symbol atlas missing for " .. dispelType)
    Contains(auras, "        " .. dispelType .. " = { includeDispelTypes = { " .. dispelType .. " = true } },",
        "per-type candidate filter missing for " .. dispelType)
end

-- === 3. MSUF's own art actually ships ======================================
-- A CustomAsset map pointing at a missing file renders nothing, and nothing is
-- indistinguishable from "no debuff" -- the worst possible failure for this
-- indicator.
for _, set in ipairs({ "Letters", "Shapes", "Glyphs", "Minimal" }) do
    Contains(auras, set .. '",', "symbol set " .. set .. " is not registered in DS.folders")
    for _, file in ipairs({ "magic", "curse", "disease", "poison", "bleed" }) do
        Check(Exists(Join(ROOT, "MidnightSimpleUnitFrames/Media/Icons/DispelTypes/" .. set .. "/" .. file .. ".tga")),
            "missing shipped art: Media/Icons/DispelTypes/" .. set .. "/" .. file .. ".tga")
    end
end

-- === 4. Preview cannot drift from the live visual ==========================
-- The live symbol only appears with a real debuff, so the preview is the only
-- thing users configure against. It has to reuse the live geometry helper and
-- the live compiler, exactly like the dispel-overlay preview does.
Contains(auras, "if not DS.LayoutButton(host, sensor, frame, 1) then",
    "the symbol preview no longer lays itself out with the live DS.LayoutButton helper")
Contains(auras, 'CompileDispelSensor(frame.MSUFUnitKey, frame.MSUFSpec, IsGroupFrame(frame), "symbol")',
    "the symbol preview no longer compiles its sensor with the live compiler")
Contains(auras, "DS.PreviewArt(tile.Texture, style,",
    "the symbol preview no longer draws the per-type art tables the runtime uses")
-- Re-stamped from both funnels a spec apply can take, or preview rows go stale.
Contains(core, "_G.MSUF_ApplyDispelSymbolPreviewToFrame(frame)",
    "unit-frame apply funnel no longer re-stamps the symbol preview")
Contains(groupPreview, "_G.MSUF_ApplyDispelSymbolPreviewToFrame(frame)",
    "group preview rebuild no longer re-stamps the symbol preview")
-- One boolean read while the preview is off, on both funnels.
Contains(core, "if _G.MSUF_DispelSymbolPreviewMode == true",
    "unit-frame funnel no longer gates the symbol preview behind a single boolean")
Contains(groupPreview, "if _G.MSUF_DispelSymbolPreviewMode == true",
    "group preview no longer gates the symbol preview behind a single boolean")
-- Never created onto a secure header mid-combat.
Contains(auras, "if _G.InCombatLockdown and _G.InCombatLockdown() then return false end",
    "the symbol preview host may now be created in combat")

-- === 5. Drag-to-place writes through the normal setters ====================
-- Dragging must land in the same DB path as the Offset sliders, or undo/redo
-- and profile writes diverge from what the user sees.
Contains(auras, "A3.DispelSymbolPreviewMoveHandler",
    "the preview drag handler hook is gone")
Contains(auras, "host:RegisterForDrag(\"LeftButton\")",
    "the symbol preview is no longer draggable")
Contains(groupBars, 'Set(CurrentScope(), "dispelSymbolX"',
    "group drag no longer writes dispelSymbolX through the scope setter")
Contains(globalBars, 'BarScopeSet("unitDispelSymbolX"',
    "unit drag no longer writes unitDispelSymbolX through the bars scope setter")
-- The dragged tile is one slot of the row; its own step has to come back out
-- or ALL mode walks away from the anchor on every drag.
Contains(auras, "x = x - (tonumber(slot.x) or 0)",
    "drag no longer subtracts the dragged slot's own growth step from the stored base")

-- === 6. Cost model: TOP default, ALL is opt-in, filters are shared =========
-- Slot count is the one MSUF-side lever on Blizzard's aura cost, so a silent
-- flip to ALL would multiply native slot work by five on every frame.
Contains(unitConfig, '"unitDispelSymbolMode", "TOP"',
    "unit frames no longer default the symbol mode to TOP")
Contains(groupConfig, 'mode = conf.dispelSymbolMode or "TOP"',
    "group frames no longer default the symbol mode to TOP")
Contains(unitConfig, '"unitDispelSymbolEnabled", false',
    "the unit-frame symbol is no longer off by default")
Contains(groupConfig, "enabled = conf.dispelSymbolEnabled == true",
    "the group symbol is no longer off by default")
Contains(auras, "candidateFilters = DS.filters[dispelType],",
    "ALL mode allocates a fresh candidate-filter table per compile instead of sharing DS.filters")
Contains(auras, "maxCount = symbolSlots and #symbolSlots or 1",
    "symbol slot count no longer follows the compiled slot list")

-- === 7. Group config cache: signature stamped at read time =================
-- ReplaceTableContents preserves table identity, so identity alone cannot
-- detect an edit. The signature must be built where settings are read (once per
-- spec compile), never on the per-frame resolve path.
Contains(groupConfig, "out.signature = table.concat({",
    "the group symbol signature is no longer stamped by the config compiler")
Contains(auras, "local symbolSignature = (spec and spec.dispelSymbol and spec.dispelSymbol.signature) or \"-\"",
    "the resolve path rebuilds the symbol signature instead of reading the stamped one")
Contains(auras, "and frame._msufA3NativeGroupSymbolSignature == symbolSignature",
    "the per-frame group config cache no longer keys off the symbol signature")
Contains(auras, "and shared.cornerSource == cornerSource and shared.symbolSignature == symbolSignature",
    "the shared spec config cache no longer keys off the symbol signature")

-- === 8. Wired into both scopes =============================================
-- The sensor is the one dispel visual that is not group-only.
Contains(auras, 'CompileDispelSensor(unit, frameSpec, false, "symbol")',
    "unit frames no longer compile a symbol sensor")
Contains(auras, 'CompileDispelSensor(unit, spec, true, "symbol")',
    "group frames no longer compile a symbol sensor")
Contains(auras, '"dispelBorder", "dispelOverlay", "dispelCorner", "dispelSymbol"',
    "the symbol sensor is not in DISPEL_SENSOR_ORDER, so its root config is never built")
-- Enabling only the symbol still has to bring up the aura container.
Contains(unitConfig, "or (out.dispelSymbol and out.dispelSymbol.enabled == true)",
    "a symbol-only unit frame no longer enables its aura container")
Contains(groupConfig, "or conf.dispelSymbolEnabled == true",
    "a symbol-only group frame no longer enables its aura container")

-- === 9. Preview is ephemeral and self-clearing =============================
Contains(groupBars, 'ControlMeta(ctx, "field.dispelSymbolPreview", "ephemeral")',
    "group symbol preview toggle is no longer ephemeral")
Contains(globalBars, 'Meta("unit_dispel_symbol.preview", "ephemeral")',
    "unit symbol preview toggle is no longer ephemeral")
for _, page in ipairs({ { groupBars, "group" }, { globalBars, "unit" } }) do
    Contains(page[1], 'preview:HookScript("OnHide", function(self)',
        page[2] .. " symbol preview no longer clears itself when the page hides")
end

if failures > 0 then
    io.write("dispel_symbol_indicator_smoke: ", tostring(failures), " failure(s)\n")
    os.exit(1)
end
io.write("dispel_symbol_indicator_smoke: ok\n")
