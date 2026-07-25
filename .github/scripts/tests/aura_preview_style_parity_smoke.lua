local root = arg and arg[1] or "."
root = root:gsub("\\", "/"):gsub("/$", "")

local function Read(rel)
    local file = assert(io.open(root .. "/" .. rel, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local function Check(value, message)
    assert(value, message)
end

local model = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua")
Check(model:find('buffShowDurationBar = Model.ReadLaneStyleBool(unit, "buff", "showDurationBar", false)', 1, true)
    and model:find('buffDurationBarDisplay = Model.ReadLaneDurationBarDisplay(unit, "buff")', 1, true)
    and model:find('debuffShowDurationBar = Model.ReadLaneStyleBool(unit, "debuff", "showDurationBar", false)', 1, true)
    and model:find('debuffDurationBarDirection = Model.ReadLaneDurationBarDirection(unit, "debuff")', 1, true),
    "unit preview config lost lane-specific duration-bar styling")

local unitPreview = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua")
Check(unitPreview:find('fs:SetPoint(anchor, icon, anchor, x, y)', 1, true)
    and unitPreview:find('PlaceAuraText(icon.timer, icon, cdAnchor, cdX, cdY)', 1, true)
    and unitPreview:find('PlaceAuraText(icon.stack, icon, stackAnchor, stackX, stackY)', 1, true),
    "unit-frame dummy aura text no longer follows its configured anchor")
-- The placement helper reads textCfg.cooldownAnchor, so pinning the helper alone
-- passes even when the lane config never carries the key -- which is exactly how
-- buff/debuff timers silently stayed centred. Pin the data contract too.
Check(unitPreview:find('cooldownAnchor = NormalizeAnchor(cfg.buffCooldownAnchor or cfg.cooldownAnchor, "CENTER")', 1, true)
    and unitPreview:find('cooldownAnchor = NormalizeAnchor(cfg.debuffCooldownAnchor or cfg.cooldownAnchor, "CENTER")', 1, true)
    and unitPreview:find('stackAnchor = NormalizeAnchor(cfg.buffStackAnchor or cfg.stackAnchor, "TOPRIGHT")', 1, true)
    and unitPreview:find('stackAnchor = NormalizeAnchor(cfg.debuffStackAnchor or cfg.stackAnchor, "TOPRIGHT")', 1, true),
    "unit-frame dummy buff/debuff lanes no longer read their configured text anchors")
Check(unitPreview:find('cooldownAnchor = NormalizeAnchor(placed.cooldownAnchor, "CENTER")', 1, true),
    "custom-container dummy aura lost its cooldown anchor")
-- Lane-wide text state must stay hoisted out of the per-icon loop, and the font
-- cache must expire with the addon-wide font epoch -- the pre-cache code re-stamped
-- every repaint, so only the epoch keeps a late font switch reaching the dummies.
Check(unitPreview:find('local stackFont = ResolveAuraFont(_stackFontState, stackSize)', 1, true)
    and unitPreview:find('local timerFont = ResolveAuraFont(_timerFontState, cooldownSize)', 1, true),
    "unit-frame dummy aura font resolve fell back into the per-icon loop")
Check(unitPreview:find('out.epoch = tonumber(_G.MSUF_FontApplyEpoch) or 0', 1, true)
    and unitPreview:find('fs._msufAuraFontEpoch ~= font.epoch', 1, true),
    "unit-frame dummy aura font cache no longer expires with the font epoch")
Check(unitPreview:find('decimalThreshold = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3', 1, true),
    "unit-frame dummy aura lost the configured decimal threshold")

local editPreview = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode.lua")
Check(editPreview:find('showStackCount = ReadLaneTextBool(shared, ls, kind, "showStackCount", true)', 1, true)
    and editPreview:find('showCooldownText = ReadLaneTextBool(shared, ls, kind, "showCooldownText", true)', 1, true)
    and editPreview:find('showCooldownSwipe = ReadLaneTextBool(shared, ls, kind, "showCooldownSwipe", true)', 1, true)
    and editPreview:find('cooldownSwipeReverse = ReadLaneTextBool(shared, ls, kind, "cooldownSwipeReverse", false)', 1, true),
    "Edit Mode dummy auras lost the active lane text/swipe style")
Check(editPreview:find('LayoutPreviewSwipe(icon, textCfg, auraState and auraState.remainingFrac)', 1, true)
    and editPreview:find('LayoutPreviewDispelBorder(icon, cfg)', 1, true)
    and editPreview:find('DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[cfg.debuffBorderMode]', 1, true),
    "Edit Mode dummy auras lost swipe or debuff-border rendering")
Check(editPreview:find('tostring(textCfg and textCfg.cooldownSwipeReverse)', 1, true)
    and editPreview:find('tostring(textCfg and textCfg.debuffBorderMode)', 1, true)
    and editPreview:find('tostring(textCfg and textCfg.cooldownDecimalSeconds)', 1, true),
    "Edit Mode refresh signature no longer invalidates on Aura style changes")
Check(editPreview:find('cooldownDecimalSeconds = "buffCooldownDecimalSeconds"', 1, true)
    and editPreview:find('cooldownDecimalSeconds = "debuffCooldownDecimalSeconds"', 1, true)
    and editPreview:find('decimalThreshold = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3', 1, true),
    "Edit Mode dummy aura lost its lane-specific decimal threshold")

local auraMenu = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua")
local queueStart = assert(auraMenu:find("local function QueueGroupScope", 1, true))
local queueEnd = assert(auraMenu:find("local function GFAurasRoot", queueStart, true))
local queueBody = auraMenu:sub(queueStart, queueEnd)
Check(queueBody:find("RefreshGFPreview()", 1, true),
    "group Aura writes no longer request an immediate menu-preview repaint")

local groupPreview = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
Check(groupPreview:find("local function OverlayRawAuraPreviewStyle", 1, true)
    and groupPreview:find("OverlayRawAuraPreviewStyle(scene.buffCfg, rawAuras.buff)", 1, true)
    and groupPreview:find("OverlayRawAuraPreviewStyle(scene.debuffCfg, rawAuras.debuff)", 1, true),
    "group-frame dummy auras no longer overlay freshly written Aura styles")
Check(groupPreview:find("tonumber(rawAuras.iconZoom) or tonumber(scene.runtimeAuras and scene.runtimeAuras.iconZoom)", 1, true),
    "group-frame dummy Aura zoom can fall back to stale compiled styling")
Check(groupPreview:find('decimalThreshold = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3', 1, true),
    "group-frame dummy aura lost the configured decimal threshold")

local animationSource = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_PreviewAnimation.lua")
Check(animationSource:find("elseif decimalThreshold > 0 and remaining < decimalThreshold then", 1, true)
    and animationSource:find("options.decimalThreshold ~= nil and options.decimalThreshold or options.decimalSeconds", 1, true),
    "shared preview animation lost numeric decimal-threshold support")

local previewNamespace = {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_PreviewAnimation.lua"))(
    "MidnightSimpleUnitFrames", previewNamespace)
local buildAuraState = assert(_G.MSUF_BuildPreviewAnimationAuraState)
local decimalState, wholeState
for elapsed = 0, 120, 0.25 do
    local candidate = buildAuraState("buff", 1, {}, { decimalThreshold = 30 }, elapsed)
    if candidate.remaining >= 3 and candidate.remaining < 30 then
        decimalState = candidate
        wholeState = buildAuraState("buff", 1, {}, { decimalThreshold = 0 }, elapsed)
        break
    end
end
Check(decimalState and decimalState.text:find("%.")
    and wholeState and not wholeState.text:find("%."),
    "preview animation does not honor numeric and zero decimal thresholds")

print("PASS aura preview style parity: menu, unit, Edit Mode, and group-frame dummies")
