-- A castbar carries the MSUF Frame Scale (Castbars/MSUF_CastbarPreviews.lua
-- CreatePreview SetScale(msufUiScale); Runtime/MSUF_UIScaleRuntime.lua scales
-- the live castbars), and its saved offset is a SetPoint offset in the bar's
-- own units, so a stored offset change D moves it D * scale UIParent units.
-- Both castbar drags wrote the raw UIParent-space cursor delta into the
-- offset: at 125 % the bar ran 125 units for a 100-unit drag, while the unit
-- and resource drags in the same ticker convert by the bar's effective scale.
-- Covered: the Edit Mode ticker (OnUpdate) and the external-shell drag
-- (Shell/EditMode/MSUF_EditMode_Layout.lua), and the direct preview drag
-- (Castbars/MSUF_CastbarPreviewEdit.lua). At scale 1.0 the offset delta stays
-- the raw cursor delta. arg 1 = repo root.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local UI_EFF = 0.64 -- UIParent effective scale (1080p, UI scale 0.64)
local cursorX, cursorY = 0, 0
GetCursorPosition = function() return cursorX * UI_EFF, cursorY * UI_EFF end
IsMouseButtonDown = function() return true end
InCombatLockdown = function() return false end
GetTime = function() return 0 end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }

local function Frame()
    local frame = { scripts = {} }
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:Show() end
    function frame:Hide() end
    function frame:ClearAllPoints() end
    function frame:SetPoint() end
    return frame
end
-- Ticker.Start creates the drag ticker frame; keep it to run its OnUpdate.
local tickerFrame
CreateFrame = function(_, name)
    local frame = Frame()
    if name == "MSUF_EM2_TickerFrame" then tickerFrame = frame end
    return frame
end
UIParent = Frame()
function UIParent:GetEffectiveScale() return UI_EFF end
function UIParent:GetWidth() return 3000 end
function UIParent:GetHeight() return 1687.5 end

-- A region with UIParent-space center (cx, cy) and size (w, h) reports its
-- edges in its own coordinate space, as the client does.
local function Region(ratio, cx, cy, w, h)
    local region = Frame()
    region.ratio, region.cx, region.cy, region.w, region.h = ratio, cx, cy, w, h
    function region:GetEffectiveScale() return UI_EFF * self.ratio end
    function region:GetLeft() return (self.cx - self.w / 2) / self.ratio end
    function region:GetRight() return (self.cx + self.w / 2) / self.ratio end
    function region:GetTop() return (self.cy + self.h / 2) / self.ratio end
    function region:GetBottom() return (self.cy - self.h / 2) / self.ratio end
    function region:IsShown() return true end
    -- The mover is placed TOPLEFT on UIParent in UIParent units.
    function region:SetPoint(_, _, _, x, y)
        if self.ratio == 1 then
            self.cx = x + self.w / 2
            self.cy = 1687.5 + y - self.h / 2
        end
    end
    return region
end

-- The castbar is anchored at a fixed UIParent point and offset by its own
-- (scaled) units, exactly like PositionPreview's SetPoint.
local general = {}
local castBar
local ANCHOR_X, ANCHOR_Y = 800, 440
local function PlaceCastbar()
    castBar.cx = ANCHOR_X + (general.castbarPlayerOffsetX or 0) * castBar.ratio
    castBar.cy = ANCHOR_Y + (general.castbarPlayerOffsetY or 0) * castBar.ratio
    return true
end
MSUF_PositionCastbarPreviewUnit = function(unit)
    assert(unit == "player", "positioned the wrong castbar: " .. tostring(unit))
    return PlaceCastbar()
end
MSUF_ApplyCastbarUnitAndSync = function() PlaceCastbar() end
MSUF_SyncCastbarPositionPopup = function() end
MSUF_GetCastbarPrefix = function(unit) return "castbar" .. unit:sub(1, 1):upper() .. unit:sub(2) end
MSUF_GetGeneralDB = function() return general end
MSUF_EnsureCastbarGeneralDB = MSUF_GetGeneralDB

-- Shell/EditMode/MSUF_EditMode_Core.lua Util.Round and Kernel/MSUF_Util.lua RoundOffset.
local function Round(n) return n + (2 ^ 52 + 2 ^ 51) - (2 ^ 52 + 2 ^ 51) end
MSUF_RoundOffset = function(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end
MSUF_EM2 = {
    Util = {
        Round = Round,
        IsConfigCombatLocked = function() return false end,
        ThemeColor = function(_, fallback) return fallback end,
        RefreshUFPreview = function() end,
        ApplySettingsForKeySafe = function() return true end,
        RefreshGroupGeometryScoped = function() end,
    },
}

local ns = { ExportPublic = function(name, value) _G[name] = value; return value end }
local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
RequireFixture.Install(root, ns)
for _, file in ipairs({ "MSUF_EditMode_Layout_Snap.lua", "MSUF_EditMode_Layout_Nudge.lua", "MSUF_EditMode_Layout.lua" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/" .. file))("MidnightSimpleUnitFrames", ns)
end
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarPreviewEdit.lua"))("MidnightSimpleUnitFrames", ns)
local Ticker = assert(MSUF_EM2.Ticker, "Edit Mode drag ticker missing")
MSUF_EM2.Snap.IsEnabled = function() return false end

local MOVE_X, MOVE_Y = 100, 40
local cfg = {
    popupType = "castbar", castbarUnit = "player",
    getFrame = function() return castBar end,
    getConf = function() return general end,
}

-- Returns the stored offset delta and the bar's on-screen move for one drag.
local function Drag(ratio, mode)
    general = { castbarPlayerOffsetX = 0, castbarPlayerOffsetY = 5, castbarPlayerPreviewEnabled = true }
    castBar = Region(ratio, 0, 0, 250, 18)
    PlaceCastbar()
    local startCX, startCY = castBar.cx, castBar.cy
    local mover = Region(1, startCX, startCY, castBar.w * ratio, castBar.h * ratio)
    cursorX, cursorY = startCX, startCY
    if mode == "ticker" then
        Ticker.Start()
        assert(Ticker.BeginDrag(mover, "castbar_player", cfg), "the ticker refused the castbar drag")
        cursorX, cursorY = startCX + MOVE_X, startCY + MOVE_Y
        local onUpdate = assert(tickerFrame and tickerFrame.scripts.OnUpdate, "ticker OnUpdate missing")
        onUpdate(tickerFrame, 0.06)
        Ticker.Stop()
    elseif mode == "external" then
        local drag = assert(Ticker.BeginExternalDrag(mover, "castbar_player", cfg), "the external castbar drag did not start")
        mover.cx, mover.cy = startCX + MOVE_X, startCY + MOVE_Y
        assert(Ticker.ApplyExternalDrag(drag), "the external castbar drag did not apply")
        Ticker.EndExternalDrag(drag, false)
    else
        MSUF_UnitEditModeActive = true
        MSUF_EM_UndoBeginChange = function() return true end
        MSUF_EM_UndoCommitChange = function() end
        castBar.SetClampedToScreen, castBar.SetFrameStrata, castBar.EnableMouse = function() end, function() end, function() end
        MSUF_SetupCastbarPreviewEditHandlers(castBar, "player")
        castBar.scripts.OnMouseDown(castBar, "LeftButton")
        cursorX, cursorY = startCX + MOVE_X, startCY + MOVE_Y
        castBar.scripts.OnUpdate(castBar, 0.06)
        castBar.isDragging = false
    end
    return general.castbarPlayerOffsetX, general.castbarPlayerOffsetY - 5, castBar.cx - startCX, castBar.cy - startCY
end

for _, mode in ipairs({ "ticker", "external", "preview" }) do
    for _, ratio in ipairs({ 1.25, 0.8, 1 }) do
        local dx, dy, screenX, screenY = Drag(ratio, mode)
        local label = string.format("%s drag at MSUF Frame Scale %.2f", mode, ratio)
        if ratio == 1 then
            Check(dx == MOVE_X and dy == MOVE_Y, label .. string.format(
                ": offset moved %s, %s, expected the cursor delta %d, %d", tostring(dx), tostring(dy), MOVE_X, MOVE_Y))
        end
        Check(math.abs(screenX - MOVE_X) <= 0.5 * ratio + 1e-9 and math.abs(screenY - MOVE_Y) <= 0.5 * ratio + 1e-9,
            label .. string.format(": the castbar moved %.2f, %.2f UI units for a %d, %d drag (offset %s, %s)",
                screenX, screenY, MOVE_X, MOVE_Y, tostring(dx), tostring(dy)))
    end
end

if #failures > 0 then
    error("Edit Mode castbar drag scale smoke failed:\n  " .. table.concat(failures, "\n  "), 0)
end
print("Edit Mode castbar drag scale smoke passed")
