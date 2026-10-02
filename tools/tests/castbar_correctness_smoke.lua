-- castbar_correctness_smoke.lua <repoRoot>
--
-- Behavioural pins for castbar correctness fixes (quality program wave 3).
-- Each section loads the real castbar file(s) it covers into a strict fake
-- client: widget methods the client does not have raise, so a stub cannot be
-- more lenient than the game. Every section fails on the pre-fix code.
--
-- Plain Lua 5.1, repo root as arg 1.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function WipeAddonGlobals()
    local names = {}
    for key in pairs(_G) do
        if type(key) == "string" and key:find("MSUF", 1, true) then names[#names + 1] = key end
    end
    for index = 1, #names do _G[names[index]] = nil end
end

local function NewNamespace()
    local namespace = { Castbars = {} }
    function namespace.ExportPublic(name, value)
        _G[name] = value
        return value
    end
    return namespace
end

local function LoadAddonFile(relativePath, namespace)
    local chunk, loadError = loadfile(root .. "/MidnightSimpleUnitFrames/" .. relativePath)
    Check(chunk ~= nil, loadError)
    chunk("MidnightSimpleUnitFrames", namespace)
    return namespace
end

-- Strict widgets: only the methods a region of that kind has in the client.
-- An unknown method raises instead of answering nil.
local STRICT_MT = {
    __index = function(self, key)
        local methods = rawget(self, "_methods")
        local method = methods and methods[key]
        if method then return method end
        if type(key) == "string" and key:match("^%u") then
            error("fake client: " .. tostring(rawget(self, "_kind")) .. " has no method " .. key, 2)
        end
        return nil
    end,
}

local REGION = {}
function REGION.ClearAllPoints(self) self.points = {} end
function REGION.SetPoint(self, point, relativeTo, relativePoint, x, y)
    self.points = self.points or {}
    self.points[#self.points + 1] = { point, relativeTo, relativePoint, x, y }
end
function REGION.SetAllPoints(self, target) self.allPoints = target end
function REGION.Show(self) self.shown = true end
function REGION.Hide(self) self.shown = false end
function REGION.SetShown(self, shown) self.shown = shown and true or false end
function REGION.IsShown(self) return self.shown == true end
function REGION.SetAlpha(self, alpha) self.alpha = alpha end
function REGION.GetAlpha(self) return self.alpha or 1 end
function REGION.GetWidth(self) return self.width or 0 end
function REGION.GetHeight(self) return self.height or 0 end
function REGION.SetWidth(self, width) self.width = width end
function REGION.SetHeight(self, height) self.height = height end
function REGION.SetSize(self, width, height) self.width, self.height = width, height end
function REGION.GetRect(self) return 0, 0, self.width or 0, self.height or 0 end
function REGION.GetParent(self) return self.parent end
function REGION.SetParent(self, parent) self.parent = parent end
function REGION.GetName(self) return self.name end
function REGION.GetEffectiveScale() return 1 end

local FRAME = setmetatable({}, { __index = REGION })
function FRAME.EnableMouse() end
function FRAME.SetFrameLevel(self, level) self.level = level end
function FRAME.GetFrameLevel(self) return self.level or 1 end
function FRAME.SetBackdrop(self, backdrop) self.backdrop = backdrop end
function FRAME.SetBackdropColor() end
function FRAME.SetBackdropBorderColor() end

local STATUSBAR = setmetatable({}, { __index = FRAME })
function STATUSBAR.SetStatusBarTexture(self, texture) self.texture = texture end
function STATUSBAR.SetStatusBarColor(self, r, g, b, a) self.color = { r, g, b, a } end

local TEXTURE = setmetatable({}, { __index = REGION })
function TEXTURE.SetTexCoord(self, ...) self.texCoord = { ... } end
function TEXTURE.SetDrawLayer(self, layer, sub) self.layer, self.subLayer = layer, sub end
function TEXTURE.SetTexture(self, texture) self.textureFile = texture end
function TEXTURE.SetVertexColor() end

local FONTSTRING = setmetatable({}, { __index = REGION })
function FONTSTRING.SetText(self, text) self.text = text end
function FONTSTRING.GetText(self) return self.text end
function FONTSTRING.SetFont(self, path, size, flags) self.font = { path, size, flags } return true end
function FONTSTRING.GetFont(self) local f = self.font or {} return f[1], f[2], f[3] end
function FONTSTRING.SetTextColor(self, r, g, b, a) self.textColor = { r, g, b, a } end
function FONTSTRING.SetShadowColor() end
function FONTSTRING.SetShadowOffset() end
function FONTSTRING.SetMaxLines() end
function FONTSTRING.SetWordWrap() end
function FONTSTRING.SetNonSpaceWrap() end
function FONTSTRING.SetJustifyH(self, justify) self.justify = justify end
function FONTSTRING.GetStringWidth(self) return self.stringWidth or 30 end

local function NewWidget(kind, methods, fields)
    local widget = fields or {}
    widget._kind = kind
    widget._methods = methods
    widget.shown = widget.shown ~= false
    return setmetatable(widget, STRICT_MT)
end

local function InstallCreateFrame()
    _G.CreateFrame = function(_, name, parent)
        return NewWidget("Frame", FRAME, { name = name, parent = parent })
    end
end

-- A live pool castbar frame as MSUF_CastbarFrames builds it.
local function NewCastbarFrame(name, unit)
    local frame = NewWidget("Frame", FRAME, { name = name, unit = unit, width = 200, height = 18 })
    frame.statusBar = NewWidget("StatusBar", STATUSBAR, { parent = frame, width = 200, height = 18 })
    frame.icon = NewWidget("Texture", TEXTURE, { parent = frame })
    frame.castText = NewWidget("FontString", FONTSTRING, { parent = frame.statusBar })
    frame.timeText = NewWidget("FontString", FONTSTRING, { parent = frame.statusBar })
    return frame
end

local function LastPoint(region)
    local points = region.points or {}
    return points[#points]
end

---------------------------------------------------------------------------
-- 1. Arena castbar "Show icon", "Show spell name" and "Show cast time" follow
--    the keys the Unit page and Defaults_Bars.lua write
--    (showArenaCastIcon/showArenaCastName/showArenaCastTime), the same way the
--    boss castbar follows showBossCast*. Before the fix the live arena bar read
--    arenaCastShowIcon/arenaCastShowSpellName (never written) and had no
--    arena time branch, so all three toggles did nothing.
---------------------------------------------------------------------------
do
    WipeAddonGlobals()
    InstallCreateFrame()
    _G.issecretvalue = function() return false end
    _G.MSUF_CastbarFrameInset = function() return 0 end
    _G.MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end
    _G.MSUF_SetFontChecked = function(fs, path, size, flags) return fs:SetFont(path, size, flags) end
    _G.MSUF_GetFontPath = function() return "Fonts\\FRIZQT__.TTF" end
    _G.MSUF_GetFontFlags = function() return "OUTLINE" end
    _G.MSUF_DB = { general = {} }
    local MSUF = LoadAddonFile("Castbars/MSUF_CastbarVisuals.lua", NewNamespace())
    local apply = MSUF.Castbars.Visuals.ApplyDetailLayout
    Check(type(apply) == "function", "Visuals.ApplyDetailLayout missing")
    Check(_G.MSUF_ApplyCastbarDetailLayout == apply, "MSUF_ApplyCastbarDetailLayout alias missing")

    local function General(overrides)
        local g = {
            castbarShowIcon = true,
            castbarShowSpellName = true,
            showBossCastIcon = true, showBossCastName = true, showBossCastTime = true,
            showArenaCastIcon = true, showArenaCastName = true, showArenaCastTime = true,
            bossCastTimeOffsetX = 0, arenaCastTimeOffsetX = 0,
            fontSize = 12,
        }
        for key, value in pairs(overrides or {}) do g[key] = value end
        return g
    end

    for _, case in ipairs({ { unit = "boss", name = "MSUF_BossCastbar1", flag = "_msufIsBossCastbar", key = "Boss" },
                            { unit = "arena", name = "MSUF_ArenaCastbar1", flag = "_msufIsArenaCastbar", key = "Arena" } }) do
        local label = case.unit .. ": "
        -- Every toggle on: icon shown, both texts visible.
        local frame = NewCastbarFrame(case.name, case.unit .. "1")
        frame[case.flag] = true
        apply(frame, case.unit, General())
        Equal(frame.icon.shown, true, label .. "icon hidden with Show icon on")
        Equal(frame.castText.alpha, 1, label .. "spell name hidden with Show spell name on")
        Equal(frame.timeText.alpha, 1, label .. "time hidden with Show cast time on")

        -- Each flat key alone turns its element off. The legacy per-prefix
        -- names are set to the opposite value to prove they are not read.
        local off = {}
        off["show" .. case.key .. "CastIcon"] = false
        off["show" .. case.key .. "CastName"] = false
        off["show" .. case.key .. "CastTime"] = false
        off[case.unit .. "CastShowIcon"] = true
        off[case.unit .. "CastShowSpellName"] = true
        frame = NewCastbarFrame(case.name, case.unit .. "1")
        frame[case.flag] = true
        apply(frame, case.unit, General(off))
        Equal(frame.icon.shown, false, label .. "Show icon off left the icon visible")
        Equal(frame.castText.alpha, 0, label .. "Show spell name off left the name visible")
        Equal(frame.castText.text, "", label .. "Show spell name off kept text")
        Equal(frame.timeText.alpha, 0, label .. "Show cast time off left the time visible")
        Equal(frame.timeText.text, "", label .. "Show cast time off kept text")

        -- The unit-generic fallbacks apply only when the flat key is unset.
        frame = NewCastbarFrame(case.name, case.unit .. "1")
        frame[case.flag] = true
        local unset = General({ castbarShowIcon = false, castbarShowSpellName = false })
        unset["show" .. case.key .. "CastIcon"] = nil
        unset["show" .. case.key .. "CastName"] = nil
        apply(frame, case.unit, unset)
        Equal(frame.icon.shown, false, label .. "unset Show icon ignored castbarShowIcon")
        Equal(frame.castText.alpha, 0, label .. "unset Show spell name ignored castbarShowSpellName")
    end

    -- Boss and arena time offsets sit on the same -2 base the Unit preview
    -- and its drag handle use (MSUF_Menu2_UnitPreview_Render.lua: timeX =
    -- -2 + <kind>CastTimeOffsetX), and never fall back to the player offset.
    for _, case in ipairs({ { unit = "boss", name = "MSUF_BossCastbar1" },
                            { unit = "arena", name = "MSUF_ArenaCastbar1" } }) do
        local offsets = General({ castbarPlayerTimeOffsetX = 9, castbarPlayerTimeOffsetY = 7 })
        offsets[case.unit .. "CastTimeOffsetX"] = 5
        offsets[case.unit .. "CastTimeOffsetY"] = 3
        local frame = NewCastbarFrame(case.name, case.unit .. "1")
        apply(frame, case.unit, offsets)
        local point = LastPoint(frame.timeText)
        Check(point ~= nil, case.unit .. ": time text not anchored")
        Equal(point[4], 3, case.unit .. ": time X offset not on the -2 base")
        Equal(point[5], 3, case.unit .. ": time Y offset")
        offsets[case.unit .. "CastTimeOffsetX"] = nil
        offsets[case.unit .. "CastTimeOffsetY"] = nil
        frame = NewCastbarFrame(case.name, case.unit .. "1")
        apply(frame, case.unit, offsets)
        point = LastPoint(frame.timeText)
        Equal(point[4], -2, case.unit .. ": unset time X fell back to the player offset")
        Equal(point[5], 0, case.unit .. ": unset time Y fell back to the player offset")
    end

    -- Unit castbars keep their per-prefix keys.
    local target = NewCastbarFrame("MSUF_TargetCastBar", "target")
    apply(target, "target", General({ castbarTargetShowIcon = false, castbarTargetShowSpellName = false,
        showTargetCastTime = false }))
    Equal(target.icon.shown, false, "target: castbarTargetShowIcon ignored")
    Equal(target.castText.alpha, 0, "target: castbarTargetShowSpellName ignored")
    Equal(target.timeText.alpha, 0, "target: showTargetCastTime ignored")
end

print("castbar correctness smoke: ok")
