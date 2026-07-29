-- Dispel overlay preview contract.
--
-- The live overlay is drawn by Blizzard: MSUF registers a texture through
-- AddDispelTypeTexture and the native CustomAuraContainer owns both the
-- button's visibility and the dispel-type color. Nothing can force that on
-- without a real dispellable debuff, so the menu preview is a separate
-- MSUF-owned frame.
--
-- The value of the preview depends entirely on it NOT drifting from the live
-- visual. This pins the invariants that keep it honest:
--   * it is laid out by the same two helpers as the live sensor button,
--   * it is fed a sensor from the same compiler,
--   * it is re-stamped from the one funnel every spec apply passes through,
--   * it costs a single boolean read while switched off,
--   * it cannot be switched on in combat and clears itself when a page hides.
--
-- Usage from the repository root:
--   lua .github/scripts/tests/dispel_overlay_preview_smoke.lua <repoRoot>

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
local core = Read("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
local preview = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
local groupBars = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua")
local globalBars = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua")

-- === 1. Shared geometry: the anti-drift invariant ==========================
-- The preview must reuse the live sensor's layout helpers rather than
-- reimplementing FULL/TOP/BOTTOM/LEFT/RIGHT, strata and frame level. A private
-- copy is how a preview silently stops matching what a real debuff looks like
-- -- and it is exactly how the pre-native MSUF-drawn overlay behaved, which
-- could express neither the Effect Layer nor the strata setting.
local applyStart = auras:find("A3._ApplyDispelOverlayPreview = function", 1, true)
Check(applyStart ~= nil, "A3._ApplyDispelOverlayPreview is missing")
local applyBody = applyStart and auras:sub(applyStart, applyStart + 2600) or ""

Contains(applyBody, "LayoutDispelSensorButton(host, sensor, frame, 1)",
    "preview must position its host with the live LayoutDispelSensorButton (strata + frame level)")
Contains(applyBody, "LayoutDispelSensorOverlay(region, host, sensor, DispelSensorTarget(frame, sensor))",
    "preview must lay out its region with the live LayoutDispelSensorOverlay and the live target resolver")
Contains(applyBody, 'CompileDispelSensor(frame.MSUFUnitKey, frame.MSUFSpec, IsGroupFrame(frame), "overlay")',
    "preview must read the same compiled sensor as the live overlay, not a private config walk")

-- The helpers it leans on must still be the ones the live sensor button uses.
Contains(auras, "local function LayoutDispelSensorButton(button, sensor, parentFrame, index)",
    "LayoutDispelSensorButton must remain the shared live/preview positioning helper")
Contains(auras, "local function LayoutDispelSensorOverlay(region, button, sensor, visualTarget)",
    "LayoutDispelSensorOverlay must remain the shared live/preview region helper")
Contains(auras, "if not LayoutDispelSensorButton(button, sensor, parentFrame, index) then return false end",
    "the live sensor button must still route through LayoutDispelSensorButton")
Contains(auras, "if not LayoutDispelSensorOverlay(region, button, sensor, visualTarget) then",
    "the live sensor region must still route through LayoutDispelSensorOverlay")

-- === 2. Off costs one boolean read =========================================
-- Every re-stamp site is on a cold path, but they run on every spec apply and
-- every preview row build, so the flag has to gate them before any call.
Contains(core, "if _G.MSUF_DispelOverlayPreviewMode == true\n    and type(_G.MSUF_ApplyDispelOverlayPreviewToFrame) == \"function\" then",
    "the element-apply funnel must gate the preview re-stamp behind the flag")
Contains(preview, "if _G.MSUF_DispelOverlayPreviewMode == true\n    and type(_G.MSUF_ApplyDispelOverlayPreviewToFrame) == \"function\" then",
    "the group preview build must gate the preview re-stamp behind the flag")
Contains(applyBody, "if _G.MSUF_DispelOverlayPreviewMode ~= true then return A3._HideDispelOverlayPreview(frame) end",
    "the painter itself must bail on the flag before touching the frame")

-- ApplyElementSelection is the one funnel BOTH apply shapes reach:
--   * UF.ApplySpec           -- full spec apply (group refreshes, rebuilds)
--   * UF.ApplyElementsToFrame -- targeted element refresh, which is how the
--     unit-frame dispel overlay settings apply (RequestUnit -> auras opts ->
--     UF.RefreshElements). Hooking only UF.ApplySpec left unit frames stale.
-- The spec is installed by SetFrameSpec earlier in the same call, so the
-- re-stamp always reads post-write values.
local selection = core:match("local function ApplyElementSelection.-\nend\n")
Check(selection ~= nil, "ApplyElementSelection not found")
Contains(selection or "", "MSUF_ApplyDispelOverlayPreviewToFrame",
    "ApplyElementSelection must re-stamp the preview")
Contains(core, "ApplyElementSelection(frame, mask, spec, nil, true)",
    "UF.ApplySpec must route through ApplyElementSelection")
Contains(core, "return ApplyElementSelection(frame, names, spec, updateReason, false)",
    "UF.ApplyElementsToFrame must route through ApplyElementSelection")

-- === 3. Combat safety ======================================================
Contains(auras, "if active and _G.InCombatLockdown and _G.InCombatLockdown() then active = false end",
    "the preview setter must refuse to switch on in combat")
Contains(applyBody, "if _G.InCombatLockdown and _G.InCombatLockdown() then return false end",
    "the painter must not parent a fresh host frame onto a secure header in combat")

-- === 4. Preview rows past the first ========================================
-- Only group preview row 1 owns a native aura container (AurasElement.IsEnabled
-- returns false beyond it), so a preview keyed off the container would paint a
-- single row. Compiling from the frame spec is what makes every row light up.
Contains(auras, "A3._ForEachDispelOverlayPreviewFrame = function(fn)",
    "a walker over live and preview frames must exist")
Contains(auras, "local previews = gf._previewFrames",
    "the walker must reach group preview rows, which are not in GF.frameList")

-- === 5. Menu contract ======================================================
-- Ephemeral: the preview is runtime state, never a saved setting.
Contains(groupBars, 'ControlMeta(ctx, "field.dispelOverlayPreview", "ephemeral")',
    "the group preview toggle must be classified ephemeral")
Contains(globalBars, 'Meta("unit_dispel_overlay.preview", "ephemeral")',
    "the unit preview toggle must be classified ephemeral")

-- Auto-clear: a stand-in tint left burned onto live frames after the menu
-- closes is indistinguishable from a bug.
for _, page in ipairs({ { groupBars, "group" }, { globalBars, "unit" } }) do
    Contains(page[1], 'HookScript("OnHide", function(self)',
        page[2] .. " preview toggle must clear itself on hide")
    Contains(page[1], "local fn = _G.MSUF_SetDispelOverlayPreview",
        page[2] .. " preview toggle must drive the runtime through the public setter")
end

-- Gated on the master switch: previewing a disabled overlay would be a lie.
Contains(groupBars, "if not overlayOn and _G.MSUF_DispelOverlayPreviewMode == true then",
    "the group page must drop the preview when the overlay master goes off")
Contains(globalBars, "if not overlayOn and _G.MSUF_DispelOverlayPreviewMode == true then",
    "the unit page must drop the preview when the overlay master goes off")

-- === 6. Public surface =====================================================
for _, name in ipairs({
    "MSUF_SetDispelOverlayPreview",
    "MSUF_RefreshDispelOverlayPreview",
    "MSUF_ApplyDispelOverlayPreviewToFrame",
}) do
    Contains(auras, 'ExportPublic("' .. name .. '"',
        name .. " must be exported for the Options addon")
end

if failures > 0 then
    error(("dispel_overlay_preview_smoke: %d contract failure(s)"):format(failures), 0)
end

print("dispel_overlay_preview_smoke: ok")
