-- alpha_text_layer_smoke.lua <repo root> <flavor>
--
-- Bar opacity (hpBarAlpha) fades the frame's texts and portrait unless "exclude
-- text and portrait" is set. The Alpha element owns that text layer as a list
-- of frame fields; every status text the status element lays out like the
-- level text belongs on it, and so do the level badge behind the level text and
-- the threat text holder (Classic Era, TBC, WoW Forever). A status text also
-- carries the status opacity its layout wrote, so the bar opacity composes with
-- it instead of overwriting it, and the reset after a fade restores it.
-- Boots the flavor's shipped core through tools/tests/client_world.lua and
-- drives the real Alpha element with the real unit compile.
local root, flavor = assert(arg[1], "repository root argument missing"), arg[2] or "Forever"
local world = assert(loadfile(root .. "/tools/tests/client_world.lua"))().New(root, flavor)
local env, core = world.env, world.core
local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
world:Boot()
local failure = world:FirstFailure()
Check(not failure, failure and failure.message)
env.MSUF_InitProfiles(); env.MSUF_EnsureDB(true)
local UF = core.UF
local alpha = assert(UF.elements.Alpha, "the Alpha element is missing")
local conf = env.MSUF_DB.target
conf.rangeFadeEnabled, conf.oocFadeEnabled = false, false

local frame = env.CreateFrame("Frame", nil, env.UIParent)
frame:SetSize(240, 44); frame.MSUFUnitKey = "target"
frame.Health = env.CreateFrame("StatusBar", nil, frame); frame.Health:SetSize(240, 44)
frame.hpBar = frame.Health
local STATUS_ALPHA = 0.8
-- Regions the status layout owns, written at the status opacity as it does.
local STATUS_FIELDS = { "levelText", "statusIndicatorText", "raceText", "classStatusText", "stanceIndicatorText" }
for _, field in ipairs(STATUS_FIELDS) do
    local region = frame:CreateFontString(nil, "OVERLAY")
    region:SetAlpha(STATUS_ALPHA)
    region._msufStatusAlpha = STATUS_ALPHA
    frame[field] = region
end
for _, field in ipairs({ "levelBackdrop", "levelBackdropRing" }) do
    local region = frame:CreateTexture(nil, "OVERLAY")
    region:SetAlpha(STATUS_ALPHA)
    region._msufStatusAlpha = STATUS_ALPHA
    frame[field] = region
end
frame.nameText = frame:CreateFontString(nil, "OVERLAY")
local threatHolder = env.CreateFrame("Frame", nil, frame)
frame.threatIndicatorHolder = threatHolder
local threatNumber = threatHolder:CreateFontString(nil, "OVERLAY")
threatNumber:SetAlpha(STATUS_ALPHA)
frame.threatIndicatorText = threatNumber

local function Apply()
    UF.Config.Refresh()
    frame.MSUFSpec = UF.Config.GetSpec("target")
    alpha.Apply(frame, frame.MSUFSpec)
end
local ALL_STATUS = { "levelText", "statusIndicatorText", "raceText", "classStatusText", "stanceIndicatorText",
    "levelBackdrop", "levelBackdropRing" }

-- Bar opacity 50%: every status region fades and keeps its status opacity.
conf.hpBarAlpha, conf.alphaExcludeTextPortrait = 0.5, false
Apply()
for _, field in ipairs(ALL_STATUS) do
    Check(Near(frame[field]:GetAlpha(), 0.5 * STATUS_ALPHA), field .. " must fade with the bar opacity on top of the status opacity ("
        .. tostring(frame[field]:GetAlpha()) .. ")")
end
Check(Near(frame.nameText:GetAlpha(), 0.5), "the name text must fade with the bar opacity")
Check(Near(threatHolder:GetAlpha(), 0.5) and Near(threatNumber:GetAlpha(), STATUS_ALPHA),
    "the threat holder must fade while its number keeps the status opacity")

-- Excluded texts keep their own opacity.
conf.alphaExcludeTextPortrait = true
Apply()
for _, field in ipairs(ALL_STATUS) do
    Check(Near(frame[field]:GetAlpha(), STATUS_ALPHA), field .. " must keep the status opacity when texts are excluded")
end
Check(Near(threatHolder:GetAlpha(), 1), "an excluded threat holder must stay opaque")

-- Fade off again: the reset restores the status opacity, not 1.
conf.alphaExcludeTextPortrait = false
Apply()
conf.hpBarAlpha = 1
Apply()
for _, field in ipairs(ALL_STATUS) do
    Check(Near(frame[field]:GetAlpha(), STATUS_ALPHA), field .. " lost its status opacity when the bar opacity reset ("
        .. tostring(frame[field]:GetAlpha()) .. ")")
end
Check(Near(frame.nameText:GetAlpha(), 1) and Near(threatHolder:GetAlpha(), 1), "the reset must bring the text layer back to full opacity")
print("alpha_text_layer_smoke: OK (" .. flavor .. ")")
