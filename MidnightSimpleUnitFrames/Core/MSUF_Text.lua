-- Core/MSUF_Text.lua  Core text rendering (HP, power, name, level, separators)
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber, select = type, tonumber, select
local string_format = string.format

ns.Text._msufPatchD = ns.Text._msufPatchD or { version = "D1" }
function ns.Text.Set(fs, text, show)
    -- Secret-safe: do NOT compare strings. Pass-through to API only.
    if not fs then  return end
    if not show then
        if fs.Hide then fs:Hide() end
        -- Clearing to empty string is safe (non-secret).
        if fs.SetText then fs:SetText("") end
         return
    end
    if text == nil then text = "" end
    if fs.SetText then fs:SetText(text) end
    if fs.Show then fs:Show() end
 end
ns.Text._msufPatchE = ns.Text._msufPatchE or { version = "E1" }
-- Secret-safe: numeric clamps only; no text comparisons.
ns.Text._msufPatchG = ns.Text._msufPatchG or { version = "G1" }
function ns.Text.ClampSpacerValue(value, maxValue, enabled)
    if not enabled then  return 0 end
    local v = tonumber(value) or 0
    if v < 0 then v = 0 end
    local m = tonumber(maxValue) or 0
    if m < 0 then m = 0 end
    if v > m then v = m end
     return v
end
_G.MSUF_TEXTLAYOUT_VALID_KEYS = _G.MSUF_TEXTLAYOUT_VALID_KEYS or { player=true, target=true, focus=true, targettarget=true, pet=true, boss=true }
function _G.MSUF_NormalizeTextLayoutUnitKey(unitKey, fallbackKey)
    local k = unitKey
    if not k or k == "" then local _g = MSUF_DB and MSUF_DB.general; k = fallbackKey or (_g and _g.hpSpacerSelectedUnitKey) or "player" end
    if k == "tot" then k = "targettarget" end
    if type(k) == "string" then local ok, m = MSUF_FastCall(string.match, k, "^boss%d+$"); if ok and m then k = "boss" end end
    if not _G.MSUF_TEXTLAYOUT_VALID_KEYS[k] then k = "player" end
     return k
end
function ns.Text.SetFormatted(fs, show, fmt, ...)
    -- Secret-safe: do NOT compare results. Pass-through to FontString API.
    if not fs then  return end
    if not show then
        if fs.Hide then fs:Hide() end
        if fs.SetText then fs:SetText("") end
         return
    end
    if fs.SetFormattedText then
        fs:SetFormattedText(fmt, ...)
    else
        -- Fallback: avoid string.format on potentially secret args; just clear.
        if fs.SetText then fs:SetText("") end
    end
    if fs.Show then fs:Show() end
 end
function ns.Text.Clear(fs, hide)
    -- Secret-safe: do NOT compare strings.
    if not fs then  return end
    if fs.SetText then fs:SetText("") end
    if hide and fs.Hide then fs:Hide() end
 end
function ns.Text.ClearField(self, field)
    if not self then  return end
    local fs = self[field]
    if not fs then  return end
    ns.Text.Clear(fs, true)
 end
-- Patch O: central text renderers (HP/Power/Pct/ToT inline) - secret-safe (no string compares)
function ns.Text._SepToken(raw, fallback)
    -- Accept legacy/malformed values (e.g. false) safely.
    local sep = raw
    if sep == nil or sep == false then sep = fallback end
    if sep == nil or sep == false then sep = "" end
    if type(sep) ~= "string" then
        -- Treat non-string separators as "none" (prevents concat errors).
        sep = ""
    end
    if sep == "" then
         return " "
    end
    return " " .. sep .. " "
end
function ns.Text._ShouldSplitHP(self, conf, g, hpMode)
    if not self or not self.hpTextPct then  return false end
    if hpMode ~= "FULL_PLUS_PERCENT" and hpMode ~= "PERCENT_PLUS_FULL" then  return false end
    local on = (conf and conf.hpTextSpacerEnabled == true) or (not conf and g and g.hpTextSpacerEnabled == true)
    if not on then  return false end
    local x = (conf and tonumber(conf.hpTextSpacerX)) or (g and tonumber(g.hpTextSpacerX)) or 0
    x = tonumber(x) or 0
    return (x > 0)
end
-- File-scope helper: replaces per-call closure to avoid ~1,000 garbage closures/min.
-- Captures: hpText (fontstring), absorbText, absorbStyle passed as explicit params.
local function _SetWithAbsorb(hpText, absorbText, absorbStyle, fmtNo, fmtSpace, fmtParen, ...)
    local n = select('#', ...)
    local a1, a2, a3 = ...
    if absorbText then
        local fmt = (absorbStyle == "PAREN") and fmtParen or fmtSpace
        if n <= 0 then
            ns.Text.SetFormatted(hpText, true, fmt, absorbText)
        elseif n == 1 then
            ns.Text.SetFormatted(hpText, true, fmt, a1, absorbText)
        elseif n == 2 then
            ns.Text.SetFormatted(hpText, true, fmt, a1, a2, absorbText)
        else
            ns.Text.SetFormatted(hpText, true, fmt, a1, a2, a3, absorbText)
        end
    else
        if n <= 0 then
            ns.Text.SetFormatted(hpText, true, fmtNo)
        elseif n == 1 then
            ns.Text.SetFormatted(hpText, true, fmtNo, a1)
        elseif n == 2 then
            ns.Text.SetFormatted(hpText, true, fmtNo, a1, a2)
        else
            ns.Text.SetFormatted(hpText, true, fmtNo, a1, a2, a3)
        end
    end
end
function ns.Text.RenderHpMode(self, show, hpStr, hpPct, hasPct, conf, g, absorbText, absorbStyle)
    if not self or not self.hpText then  return end
    if not show then
        ns.Text.Set(self.hpText, "", false)
        ns.Text.ClearField(self, "hpTextPct")
         return
    end
    local useOverride = (conf and conf.hpPowerTextOverride == true)
    -- Per-unit override for HP text mode + separator (falls back to Shared if unset).
    local hpMode = (useOverride and conf and conf.hpTextMode) or (g and g.hpTextMode) or "FULL_PLUS_PERCENT"
    local sepRaw = (useOverride and conf and conf.hpTextSeparator)
    if sepRaw == nil then sepRaw = (g and g.hpTextSeparator) end
    local sep = ns.Text._SepToken(sepRaw, nil)
    -- Spacers inherit Shared unless per-unit override is enabled.
    local spacerConf = (useOverride and conf) or nil
    local split = (hasPct == true) and ns.Text._ShouldSplitHP(self, spacerConf, g, hpMode) or false
    local hpText = self.hpText
    if split then
        _SetWithAbsorb(hpText, absorbText, absorbStyle, "%s", "%s %s", "%s (%s)", hpStr or "")
        ns.Text.SetFormatted(self.hpTextPct, true, "%.1f%%", hpPct)
         return
    end
    ns.Text.ClearField(self, "hpTextPct")
    if not hasPct then
        _SetWithAbsorb(hpText, absorbText, absorbStyle, "%s", "%s %s", "%s (%s)", hpStr or "")
         return
    end
    if hpMode == "FULL_ONLY" then
        _SetWithAbsorb(hpText, absorbText, absorbStyle, "%s", "%s %s", "%s (%s)", hpStr or "")
    elseif hpMode == "PERCENT_ONLY" then
        _SetWithAbsorb(hpText, absorbText, absorbStyle, "%.1f%%", "%.1f%% %s", "%.1f%% (%s)", hpPct)
    elseif hpMode == "PERCENT_PLUS_FULL" then
        _SetWithAbsorb(hpText, absorbText, absorbStyle, "%.1f%%%s%s", "%.1f%%%s%s %s", "%.1f%%%s%s (%s)", hpPct, sep, hpStr or "")
    else
        _SetWithAbsorb(hpText, absorbText, absorbStyle, "%s%s%.1f%%", "%s%s%.1f%% %s", "%s%s%.1f%% (%s)", hpStr or "", sep, hpPct)
    end
 end
function ns.Text.GetUnitPowerPercent(unit)
    if type(UnitPowerPercent) == "function" then
        local pType
        if type(UnitPowerType) == "function" then
            pType = UnitPowerType(unit)
        end
        if CurveConstants and CurveConstants.ScaleTo100 then
            return UnitPowerPercent(unit, pType, false, CurveConstants.ScaleTo100)
        else
            return UnitPowerPercent(unit, pType, false, true)
        end
    end
     return nil
end
_G.MSUF_GetUnitPowerPercent = _G.MSUF_GetUnitPowerPercent or ns.Text.GetUnitPowerPercent
function ns.Text._ShouldSplitPower(self, pMode, hasPct)
    if not self or not hasPct or not self.powerTextPct then  return false end
    if pMode ~= "FULL_PLUS_PERCENT" and pMode ~= "PERCENT_PLUS_FULL" then  return false end
    if not MSUF_DB then if type(EnsureDB) == "function" then EnsureDB() end end
    local key = self.msufConfigKey
    local udb = (key and MSUF_DB and MSUF_DB[key]) or nil
    local gen = (MSUF_DB and MSUF_DB.general) or nil
    -- Spacers inherit Shared unless per-unit override is enabled.
    local useOverride = (udb and udb.hpPowerTextOverride == true)
    local on = (useOverride and udb and udb.powerTextSpacerEnabled == true) or ((not useOverride) and gen and gen.powerTextSpacerEnabled == true)
    if not on then  return false end
    local x = (useOverride and udb and tonumber(udb.powerTextSpacerX)) or ((gen and tonumber(gen.powerTextSpacerX)) or 0)
    x = tonumber(x) or 0
    if x <= 0 then  return false end
    if key then
        local maxP = tonumber(_G.MSUF_GetPowerSpacerMaxForUnitKey(key)) or 0
        if x < 0 then x = 0 end
        if x > maxP then x = maxP end
    end
    return (x > 0)
end
function ns.Text._NormalizePowerMode(mode)
    -- Supports legacy enum keys and Unhalted-style tag strings (curpp/maxpp/perpp).
    if mode == nil then return "curpp:perpp" end
    if type(mode) ~= "string" then return "curpp:perpp" end

    -- Already in tag format?
    if string.find(mode, "curpp", 1, true) or string.find(mode, "perpp", 1, true) or string.find(mode, "maxpp", 1, true) then
        return mode
    end

    -- Legacy enums
    if mode == "FULL_SLASH_MAX" then return "curpp:maxpp" end
    if mode == "FULL_ONLY" then return "curpp" end
    if mode == "FULL_PLUS_PERCENT" then return "curpp:perpp" end
    if mode == "PERCENT_PLUS_FULL" then return "perpp:curpp" end
    if mode == "PERCENT_ONLY" then return "perpp" end

    return "curpp:perpp"
end

local function _MSUF_FormatPowerValue(v)
    if v == nil then return nil end
    -- Do NOT tonumber/compare; value may be secret.
    if AbbreviateLargeNumbers then
        return AbbreviateLargeNumbers(v)
    end
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(v)
    end
    return tostring(v)
end

local function _MSUF_SafePowerPercent(unit)
    -- Midnight 12.0: Percent can be a secret number. We must NOT compare/format it numerically.
    -- Return it as-is (best effort). Caller will use tostring(pct) .. "%%" with no numeric ops.
    if type(UnitPowerPercent) ~= "function" then return nil end

    local pType
    if type(UnitPowerType) == "function" then
        pType = UnitPowerType(unit)
    end

    -- Prefer ScaleTo100 curve if available so we can display without multiplying.
    local curve = (type(CurveConstants) == "table" and CurveConstants.ScaleTo100) or nil

    local pct = UnitPowerPercent(unit, pType, false, curve)
    if pct == nil then
        pct = UnitPowerPercent(unit, pType)
    end
    if pct == nil then
        pct = UnitPowerPercent(unit)
    end
    return pct
end


local function _MSUF_TokenizeMode(mode)
    local t = {}
    local n = 0
    for part in string.gmatch(mode, "([^:]+)") do
        if part and part ~= "" then
            n = n + 1
            t[n] = part
        end
    end
    return t, n
end

function ns.Text.RenderPowerText(self)
    if not self or not self.unit or not self.powerText then return end

    local unit = self.unit
    local showPower = self.showPowerText
    if showPower == nil then showPower = true end
    if not showPower then
        ns.Text.Set(self.powerText, "", false)
        ns.Text.ClearField(self, "powerTextPct")
        return
    end

    local gPower = (MSUF_DB and MSUF_DB.general) or {}
    local colorByType = (gPower.colorPowerTextByType == true)

    -- Per-unit override for Power text mode + separators.
    local key = self.msufConfigKey or self._msufConfigKey or self._msufUnitKey or self.unitKey
    local udb = (key and MSUF_DB and MSUF_DB[key]) or nil
    local useOverride = (udb and udb.hpPowerTextOverride == true)

    local rawMode = (useOverride and udb and udb.powerTextMode) or gPower.powerTextMode
    local mode = ns.Text._NormalizePowerMode(rawMode)

    -- Power separator: prefer explicit power sep; else fall back to HP sep.
    local rawPowerSep
    if useOverride and udb then
        if udb.powerTextSeparator ~= nil then
            rawPowerSep = udb.powerTextSeparator
        elseif udb.hpTextSeparator ~= nil then
            rawPowerSep = udb.hpTextSeparator
        end
    else
        rawPowerSep = gPower.powerTextSeparator
    end
    local rawHpSep = (useOverride and udb and udb.hpTextSeparator) or gPower.hpTextSeparator
    local powerSep = ns.Text._SepToken(rawPowerSep, rawHpSep)

    -- Fetch power values for ANY unit (player, NPC, boss, pet, etc).
    -- Use current displayed power type implicitly (UnitPower default uses UnitPowerType).
    local curValue = (F.UnitPower and F.UnitPower(unit)) or (UnitPower and UnitPower(unit))
    local maxValue = (F.UnitPowerMax and F.UnitPowerMax(unit)) or (UnitPowerMax and UnitPowerMax(unit))

    local curText = _MSUF_FormatPowerValue(curValue)
    local maxText = _MSUF_FormatPowerValue(maxValue)

    local pct = _MSUF_SafePowerPercent(unit)

    -- Optional split display (uses the same spacer logic as before).
    local hasPct = (pct ~= nil)
    local split = ns.Text._ShouldSplitPower(self, mode, hasPct)

    -- Build output based on token order (Unhalted-style).
    local parts, n = _MSUF_TokenizeMode(mode)
    if n <= 0 then parts, n = {"curpp","perpp"}, 2 end

    -- Determine whether we are outputting 2 lines (split).
    if split and hasPct then
        -- powerText holds the first "value" token and powerTextPct holds percent.
        -- If mode begins with perpp, still place percent into powerTextPct to match HP split UX.
        local firstToken = parts[1]
        if firstToken == "perpp" then
            ns.Text.Set(self.powerText, curText or "", true)
            ns.Text.Set(self.powerTextPct, tostring(pct) .. "%", true)
        else
            ns.Text.Set(self.powerText, curText or "", true)
            ns.Text.Set(self.powerTextPct, tostring(pct) .. "%", true)
        end
        ns.Text.ApplyPowerTextColorByType(self, unit, colorByType)
        return
    end

    ns.Text.ClearField(self, "powerTextPct")

    -- Single-line assembly.
    local out = nil
    local wrote = false
    for i = 1, n do
        local tok = parts[i]
        local piece = nil
        if tok == "curpp" then
            piece = curText
        elseif tok == "maxpp" then
            piece = maxText
        elseif tok == "perpp" then
            if hasPct then
                piece = tostring(pct) .. "%"
            end
        end
		-- Midnight 12.0: `piece` may be a secret string (e.g. formatted from secret numbers).
		-- NEVER compare secret strings (even against ""). Only nil-check.
		if piece then
            if not wrote then
                out = piece
                wrote = true
            else
                out = out .. powerSep .. piece
            end
        end
    end

    if not wrote then
        out = ""
    end

    ns.Text.Set(self.powerText, out, wrote)
    ns.Text.ApplyPowerTextColorByType(self, unit, colorByType)
end
 -- Resolve helper color lookups used by ToT inline.
 -- These are global functions defined in MidnightSimpleUnitFrames.lua (loaded before this file).
 local MSUF_GetNPCReactionColor = _G.MSUF_GetNPCReactionColor or function(kind) return 1, 1, 1 end
 local MSUF_GetClassBarColor    = _G.MSUF_GetClassBarColor    or function(tok)  return 1, 1, 1 end

 function ns.Text.RenderToTInline(targetFrame, totConf)
    if not targetFrame or not targetFrame.nameText then  return end
    local sep = targetFrame._msufToTInlineSep
    local txt = targetFrame._msufToTInlineText
    if not sep or not txt then  return end
    local enabled = (totConf and totConf.showToTInTargetName) and true or false
    if not enabled or not (F.UnitExists and F.UnitExists("target")) or not (F.UnitExists and F.UnitExists("targettarget")) then
        ns.Util.SetShown(sep, false)
        ns.Util.SetShown(txt, false)
         return
    end
    local sepToken = (totConf and totConf.totInlineSeparator) or "|"
    if type(sepToken) ~= "string" or sepToken == "" then sepToken = "|" end
    sep:SetText(" " .. sepToken .. " ")
    -- Match target name font (no secret ops).
    local font, size, flags = targetFrame.nameText:GetFont()
    if font and sep.SetFont then
        sep:SetFont(font, size, flags)
        txt:SetFont(font, size, flags)
    end
    -- Clamp ToT inline width (secret-safe, no string width math).
    local frameWidth = (targetFrame.GetWidth and targetFrame:GetWidth()) or 0
    local maxW = 120
    if frameWidth and frameWidth > 0 then
        maxW = math.floor(frameWidth * 0.32)
        if maxW < 80 then maxW = 80 end
        if maxW > 180 then maxW = 180 end
    end
    txt:SetWidth(maxW)
    local r, gCol, b = 1, 1, 1
    if F.UnitIsPlayer and F.UnitIsPlayer("targettarget") then
        local useClass = false
        local g = MSUF_DB and MSUF_DB.general
        if g and g.nameClassColor then useClass = true end
        if useClass then
            local _, classToken = F.UnitClass("targettarget")
            r, gCol, b = MSUF_GetClassBarColor(classToken)
        else
            r, gCol, b = 1, 1, 1
    end
    else
        if F.UnitIsDeadOrGhost and F.UnitIsDeadOrGhost("targettarget") then
            do
                local fastNPC = _G.MSUF_UFCore_GetNPCReactionColorFast
                if type(fastNPC) == "function" then
                    r, gCol, b = fastNPC("dead")
                else
                    r, gCol, b = MSUF_GetNPCReactionColor("dead")
                end
            end
        else
            local reaction = F.UnitReaction and F.UnitReaction("player", "targettarget")
            if reaction then
                if reaction >= 5 then
                    do
                        local fastNPC = _G.MSUF_UFCore_GetNPCReactionColorFast
                        if type(fastNPC) == "function" then
                            r, gCol, b = fastNPC("friendly")
                        else
                            r, gCol, b = MSUF_GetNPCReactionColor("friendly")
                        end
                    end
                elseif reaction == 4 then
                    do
                        local fastNPC = _G.MSUF_UFCore_GetNPCReactionColorFast
                        if type(fastNPC) == "function" then
                            r, gCol, b = fastNPC("neutral")
                        else
                            r, gCol, b = MSUF_GetNPCReactionColor("neutral")
                        end
                    end
                else
                    do
                        local fastNPC = _G.MSUF_UFCore_GetNPCReactionColorFast
                        if type(fastNPC) == "function" then
                            r, gCol, b = fastNPC("enemy")
                        else
                            r, gCol, b = MSUF_GetNPCReactionColor("enemy")
                        end
                    end
                end
            else
                r, gCol, b = MSUF_GetNPCReactionColor("enemy")
            end
    end
    end
    sep:SetTextColor(0.7, 0.7, 0.7)
    txt:SetTextColor(r, gCol, b)
    local totName = F.UnitName and F.UnitName("targettarget")
    txt:SetText(totName or "")
    ns.Util.SetShown(sep, true)
    ns.Util.SetShown(txt, true)
 end
function ns.Text.ApplyPowerTextColorByType(self, unit, enabled)
    -- Secret-safe & pass-through: avoid extra comparisons/caching; just apply resolved color.
    if not enabled then  return end
    if not (self and self.powerText and UnitPowerType) then  return end
    local okPT, pType, pTok = MSUF_FastCall(UnitPowerType, unit)
    if not okPT then  return end
    if type(MSUF_GetResolvedPowerColor) ~= "function" then  return end
    local pr, pg, pb = MSUF_GetResolvedPowerColor(pType, pTok)
    if not pr then  return end
    self.powerText:SetTextColor(pr, pg, pb, 1)
    self._msufPTColorByPower = true
    self._msufPTColorType = pType
    self._msufPTColorTok = pTok
 end
function ns.Text.ApplyName(frame, unit, overrideText)
    -- Secret-safe: do NOT compare name strings. Use API pass-through only.
    if not frame or not frame.nameText then  return end
    local show = (frame.showName ~= false)
    local txt = overrideText
    if txt == nil and show and unit and F.UnitName then
        txt = F.UnitName(unit)
    end
    if txt == nil then
        show = false
        txt = ""
    end
    ns.Text.Set(frame.nameText, txt, show)
 end
function ns.Text.ApplyLevel(frame, unit, conf, overrideText, forceShow)
    -- Secret-safe: do NOT compare strings for emptiness.
    if not frame or not frame.levelText then  return end
    local showLevel = true
    if conf and conf.showLevelIndicator == false then
        showLevel = false
    end
    if forceShow ~= nil then
        showLevel = (forceShow == true)
    end
    local txt = ""
    if overrideText ~= nil then
        txt = overrideText
    elseif showLevel and unit and F.UnitExists and F.UnitExists(unit) then
        txt = (MSUF_GetUnitLevelText and MSUF_GetUnitLevelText(unit)) or ""
    end
    ns.Text.Set(frame.levelText, txt, showLevel)
    if MSUF_ClampNameWidth then
        MSUF_ClampNameWidth(frame, conf)
    end
 end
function ns.Text.ApplyBossTestName(frame, unit)
    if not frame then  return end
    local txt = "Test Boss"
    local idx
    if type(unit) == "string" then
        idx = unit:match("boss(%d+)")
    end
    if idx then
        txt = "Test Boss " .. idx
    end
    ns.Text.ApplyName(frame, unit, txt)
 end
function ns.Text.ApplyBossTestLevel(frame, conf)
    if not frame or not frame.levelText then  return end
    local show = (frame.showName ~= false)
    ns.Text.Set(frame.levelText, "??", show)
    if MSUF_ClampNameWidth then
        MSUF_ClampNameWidth(frame, conf)
    end
 end
