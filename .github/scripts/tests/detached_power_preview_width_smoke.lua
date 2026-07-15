-- Regression coverage for detached Player Power preview/live width parity.

_G = _G or _ENV

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

local function ResolveRepositoryRoot()
    for _, root in ipairs({ ".", "..", "../..", "../../.." }) do
        if Exists(Join(root, "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua")) then return root end
    end
    error("repository root not found")
end

local ROOT = ResolveRepositoryRoot()
local MSUF = { MSUF2 = {} }
local helperPath = Join(ROOT, "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua")
local chunk, err = loadfile(helperPath)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local ResolveWidth = assert(MSUF.MSUF2.ClassPowerPreview.ResolveDetachedPowerWidth)
local cooldown = {
    shown = true,
    GetWidth = function(self) return 218 end,
    IsShown = function(self) return self.shown end,
}
_G.MSUF_GetEffectiveCooldownFrame = function(name)
    if name == "EssentialCooldownViewer" then return cooldown end
end

assert(ResolveWidth({
    shape = "BAR", syncClass = false, classWidth = 280,
    widthMode = "cooldown", manualWidth = 333, frameWidth = 350,
}) == 218, "cooldown width mode incorrectly reused the Class Resource width")

assert(ResolveWidth({
    shape = "BAR", syncClass = true, classWidth = 280,
    widthMode = "cooldown", manualWidth = 333, frameWidth = 350,
}) == 280, "explicit Class Resource sync lost precedence")

assert(ResolveWidth({
    shape = "BAR", syncClass = true, classWidth = 0, classFallbackWidth = 346,
    widthMode = "cooldown", manualWidth = 333, frameWidth = 350,
}) == 346, "unavailable Class Resource width did not use its runtime fallback")

assert(ResolveWidth({
    shape = "BAR", syncClass = false, classWidth = 280,
    widthMode = "manual", manualWidth = 333, frameWidth = 350,
}) == 333, "manual detached width was not preserved")

cooldown.shown = false
assert(ResolveWidth({
    shape = "BAR", syncClass = false, widthMode = "cooldown",
    manualWidth = 333, frameWidth = 350,
}) == 333, "hidden cooldown frame did not fall back to manual width")

assert(ResolveWidth({
    shape = "ORB", orbSize = 999, syncClass = true,
    classWidth = 280, widthMode = "cooldown", manualWidth = 333,
}) == 160, "orb size must remain independent and clamped to its runtime range")

print("detached power preview width smoke: ok")
