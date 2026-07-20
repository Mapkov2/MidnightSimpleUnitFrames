-- Regression coverage for Unit Preview focal-point and drag geometry.

local function Exists(path)
    local handle = io.open(path, "r")
    if not handle then return false end
    handle:close()
    return true
end

local addonRoot = arg[1] or "MidnightSimpleUnitFrames"
if Exists(addonRoot .. "/MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua") then
    addonRoot = addonRoot .. "/MidnightSimpleUnitFrames"
end
local renderPath = addonRoot .. "/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua"
local modelPath = addonRoot .. "/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Model.lua"
local viewPath = addonRoot .. "/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua"
local statusPath = addonRoot .. "/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Status.lua"

local namespace = {}
local chunk, err = loadfile(renderPath)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", namespace)

local resolve = assert(namespace.UFPreviewRender and namespace.UFPreviewRender.ResolvePreviewBodyOffsets,
    "Unit Preview offset resolver missing")

-- Fit mode still centers the complete footprint, including intentionally
-- distant aura/castbar layouts.
local fitX, fitY = resolve(400, -500, 2, nil, nil, nil)
assert(fitX == -800 and fitY == 1000, "fit mode lost full-footprint centering")

-- Manual zoom must keep the actual unit body visible even when an auxiliary
-- element is hundreds of layout pixels away.
local manualX, manualY = resolve(400, -500, 2, 2, nil, nil)
assert(manualX == 0 and manualY == 0, "manual zoom let an outlier displace the unit body")

-- Recomputed footprint bounds must not move the preview origin underneath an
-- active drag; that feedback loop makes name/text movement appear inverted.
local frozenX, frozenY = resolve(-900, 750, 2, nil, 37, -19)
assert(frozenX == 37 and frozenY == -19, "active drag did not preserve its preview origin")

local modelNamespace = {
    MSUF2 = {
        KeySetFromWords = function(words)
            local out = {}
            for word in words:gmatch("%S+") do out[word] = true end
            return out
        end,
        WordList = function(words)
            local out = {}
            for word in words:gmatch("%S+") do out[#out + 1] = word end
            return unpack(out)
        end,
        AssignNamedValues = function(target, names, ...)
            local index = 0
            for name in names:gmatch("%S+") do
                index = index + 1
                target[name] = select(index, ...)
            end
        end,
    },
}
local modelChunk, modelError = loadfile(modelPath)
assert(modelChunk, modelError)
modelChunk("MidnightSimpleUnitFrames", modelNamespace)
local nameDelta = assert(modelNamespace.UFPreview and modelNamespace.UFPreview.Model
    and modelNamespace.UFPreview.Model.ResolveNameOffsetDelta, "name offset delta resolver missing")
local rightX, rightY = nameDelta("RIGHT", 12, -3)
assert(rightX == -12 and rightY == -3, "right-anchored name drag remains inverted")
local leftX, leftY = nameDelta("LEFT", 12, -3)
assert(leftX == 12 and leftY == -3, "left-anchored name drag changed direction")

local handle = assert(io.open(viewPath, "r"))
local source = handle:read("*a")
handle:close()
assert(source:find("preview._dragFrozenBaseOffsetX = tonumber(preview._mockBaseOffsetX) or 0", 1, true),
    "Unit Preview drag does not capture its horizontal origin")
assert(source:find("preview._dragFrozenBaseOffsetY = tonumber(preview._mockBaseOffsetY) or 0", 1, true),
    "Unit Preview drag does not capture its vertical origin")
assert(source:find("preview._dragFrozenBaseOffsetX = nil", 1, true)
    and source:find("preview._dragFrozenBaseOffsetY = nil", 1, true),
    "Unit Preview drag does not release its frozen origin")
assert(source:find("dx, dy = StoredHandleDelta(h, dx, dy)", 1, true)
    and source:find("resolveOffsetDelta = NameHandleOffsetDelta", 1, true),
    "right-name delta resolver is not wired into direct manipulation")

local statusNamespace = {
    UFPreview = { Model = { MakeFS = function() end, FontColor = function() return 1, 1, 1 end } },
}
local statusChunk, statusError = loadfile(statusPath)
assert(statusChunk, statusError)
statusChunk("MidnightSimpleUnitFrames", statusNamespace)
local statusPreviewText = assert(statusNamespace.UFPreviewStatus
    and statusNamespace.UFPreviewStatus.StatusTextPreviewText, "status preview text resolver missing")
local enabledStates = { showDead = true, showGhost = true, showAFK = true, showDND = true }
assert(statusPreviewText(enabledStates, "AFK") == "AFK",
    "Unit Preview does not prefer the AFK state currently shown by runtime")
assert(statusPreviewText(enabledStates, "DND") == "DND",
    "Unit Preview does not prefer the DND state currently shown by runtime")
assert(statusPreviewText({ showDead = true, showAFK = false }, "AFK") == "DEAD",
    "Unit Preview showed a runtime AFK state disabled by preview configuration")

local renderHandle = assert(io.open(renderPath, "r"))
local renderSource = renderHandle:read("*a")
renderHandle:close()
assert(renderSource:find("frame._msufStatusTextValue", 1, true)
    and renderSource:find("statusCfg, box._previewStatusText", 1, true),
    "Unit Preview does not pass the current runtime status text into its renderer")

print("UNIT PREVIEW GEOMETRY SMOKE PASS - fit/manual/outlier/drag origin/right-name direction/runtime status text")
