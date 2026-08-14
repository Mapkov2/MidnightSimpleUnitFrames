--- Shell/Menu2/Assistant/MSUF_AssistantParser_Actions.lua
--- Action parser shard for concrete Assistant commands.
---
--- Returns action/changes plans rather than executing them, keeping undo,
--- confirmation, and combat gating in the downstream assistant runtime.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local P = A.Parser or {}
A.Parser = P
local Data = A.ParserData or {}
A.ParserData = Data
local ActionsData = Data.ACTIONS_PARSER or {}
local ActionsPhrases = ActionsData.PHRASES or {}
local Trim = P.Trim
local Normalize = P.Normalize
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local ALL_UNITFRAMES = P.ALL_UNITFRAMES
local PAGE_TEXT_TARGETS = P.PAGE_TEXT_TARGETS
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local DetectBoolean = P.DetectBoolean
local FirstNumber = P.FirstNumber
local Compact = P.Compact
local AliasRelationText = P.AliasRelationText
local TextMatchesAlias = P.TextMatchesAlias
local ExtractColor = P.ExtractColor
local DetectDirection = P.DetectDirection
local PageForText = P.PageForText
local WantsFullUnitCopy = P.WantsFullUnitCopy
local CopyScopesForText = P.CopyScopesForText
local WantsFullGroupCopy = P.WantsFullGroupCopy
local GroupCopyScopesForText = P.GroupCopyScopesForText
local ActionableText = P.ActionableText

local function UnitDisplayLabel(unit)
    if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(unit) end
    local label = (A.UnitLabels or {})[unit]
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    if unit == "targettarget" then return "Target of Target" end
    if unit == "focustarget" then return "Focus Target" end
    return tostring(unit or "Unit Frame")
end

local function GroupDisplayLabel(scope)
    if A and type(A.DisplayGroupLabel) == "function" then return A.DisplayGroupLabel(scope) end
    if scope == "mythicraid" then return "Mythic Raid" end
    if scope == "raid" then return "Raid" end
    if scope == "party" then return "Party" end
    return UnitDisplayLabel(scope)
end

local COPY_VERBS = { "copy", "use", "kopiere", "kopieren", "uebernehme", "uebernehmen" }
local COPY_LIKE_TERMS = {
    "copy", "use", "kopiere", "kopieren", "uebernehme", "uebernehmen",
    "look like", "looks like", "same as", "the same as", "match", "mirror", "clone",
}
local UNIT_COPY_PLACEMENT_TERMS = {
    "position", "positioning", "placement", "location", "anchor", "anchoring",
    "same position", "same placement", "same anchor",
}

local function HasCopyIntent(text)
    for i = 1, #COPY_LIKE_TERMS do
        if HasPhrase(text, COPY_LIKE_TERMS[i]) then return true end
    end
    return false
end

local function CopyCommandText(text)
    local normalized = Normalize(text)
    local padded = " " .. normalized .. " "
    local best
    for i = 1, #COPY_VERBS do
        local verb = COPY_VERBS[i]
        local startPos = padded:find(" " .. verb .. " ", 1, true)
        if startPos and (not best or startPos < best) then best = startPos end
    end
    if not best then return nil end
    return Trim(padded:sub(best + 1))
end

local function CopyTextParts(text)
    text = CopyCommandText(text)
    if not text then return nil, nil end
    local src, dst = text:match("^copy%s+.-%s+from%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^copy%s+from%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^copy%s+(.+)%s+over%s+to%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^copy%s+(.+)%s+onto%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^copy%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^use%s+.-%s+from%s+(.+)%s+for%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^use%s+(.+)%s+for%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^kopiere%s+.-%s+von%s+(.+)%s+nach%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^kopiere%s+(.+)%s+nach%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^kopieren%s+.-%s+von%s+(.+)%s+nach%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^kopieren%s+(.+)%s+nach%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^uebernehme%s+.-%s+von%s+(.+)%s+fuer%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^uebernehme%s+(.+)%s+fuer%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^uebernehmen%s+.-%s+von%s+(.+)%s+fuer%s+(.+)$")
    if src and dst then return src, dst end
    src, dst = text:match("^uebernehmen%s+(.+)%s+fuer%s+(.+)$")
    if src and dst then return src, dst end
    return nil, nil
end

local function LookLikeCopyTextParts(text)
    text = Normalize(text)
    local dst, src = text:match("^make%s+(.+)%s+look%s+like%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^make%s+(.+)%s+look%s+the%s+same%s+as%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^make%s+(.+)%s+the%s+same%s+as%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^make%s+(.+)%s+match%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^make%s+(.+)%s+mirror%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^match%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^mirror%s+(.+)%s+to%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^(.+)%s+look%s+like%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^(.+)%s+look%s+the%s+same%s+as%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^(.+)%s+match%s+(.+)$")
    if src and dst then return src, dst end
    dst, src = text:match("^(.+)%s+mirror%s+(.+)$")
    if src and dst then return src, dst end
    return nil, nil
end

local function RemoveUnit(out, unit)
    if not unit then return out end
    local filtered = {}
    for i = 1, #(out or {}) do
        if out[i] ~= unit then filtered[#filtered + 1] = out[i] end
    end
    return filtered
end

local function CopyTargetsForText(text, source)
    if HasPhrase(text, "all") or HasPhrase(text, "all unitframes") or HasPhrase(text, "alle") or HasPhrase(text, "alle unitframes") then
        local targets = {}
        for i = 1, #ALL_UNITFRAMES do
            if ALL_UNITFRAMES[i] ~= source then targets[#targets + 1] = ALL_UNITFRAMES[i] end
        end
        return targets
    end
    return RemoveUnit(DetectUnits(text), source)
end

local function CopyGroupTargetsForText(text, source)
    if HasPhrase(text, "all") or HasPhrase(text, "all groups") or HasPhrase(text, "all group frames") or HasPhrase(text, "alle") or HasPhrase(text, "alle gruppenframes") then
        return RemoveUnit({ "party", "raid", "mythicraid" }, source)
    end
    return RemoveUnit(DetectGroups(text), source)
end

local function HasEnabledCopyScope(scopes)
    for _, value in pairs(scopes or {}) do
        if value == true then return true end
    end
    return false
end

local function ParseGroupCopy(text)
    if not HasCopyIntent(text) then return nil end
    local source, targets
    local srcText, dstText = CopyTextParts(text)
    if not (srcText and dstText) then
        srcText, dstText = LookLikeCopyTextParts(text)
    end
    if srcText and dstText then
        local srcGroups = DetectGroups(srcText)
        source = srcGroups[1]
        targets = CopyGroupTargetsForText(dstText, source)
    end
    if not source or not targets or #targets == 0 then
        local groups = DetectGroups(text)
        if #groups < 2 then
            if srcText and dstText then
                local srcUnits = DetectUnits(srcText)
                local srcGroups = DetectGroups(srcText)
                local dstUnits = DetectUnits(dstText)
                local dstGroups = DetectGroups(dstText)
                if (#srcUnits > 0 and #dstGroups > 0) or (#srcGroups > 0 and #dstUnits > 0) then return nil end
            end
            if ContainsAny(text, ActionsPhrases[1]) then
                return {
                    kind = "answer",
                    status = "info",
                    text = "Which source and target group frames do you want me to use? For example: copy party to raid, copy raid options to party, or copy just health and text options from party to raid.",
                    summary = "Asks which group-frame source or target to copy.",
                }
            end
            return nil
        end
        source = groups[1]
        targets = {}
        for i = 2, #groups do targets[#targets + 1] = groups[i] end
    end
    local action = Registry and Registry:GetAction("copy_group")
    if not action then return nil end
    local confirm = (WantsFullGroupCopy and WantsFullGroupCopy(text)) or ContainsAny(text, ActionsPhrases[2]) or #targets > 1
    local scopes = GroupCopyScopesForText(text)
    if not HasEnabledCopyScope(scopes) then
        return {
            kind = "answer",
            status = "info",
            summary = "Asks which group-frame parts to copy.",
            text = "Which group-frame parts do you want me to copy? For example: 'copy raid auras to party' or 'copy raid layout without auras to party'.",
        }
    end
    return {
        kind = "action",
        action = action,
        args = { source = source, targets = targets, scopes = scopes },
        confirmRequired = confirm,
        label = "Copy " .. GroupDisplayLabel(source) .. " group options",
        summary = "Copies group-frame options from one group to another.",
    }
end

local function ParseUnsupportedMixedCopy(text)
    if not HasCopyIntent(text) then return nil end
    local srcText, dstText = CopyTextParts(text)
    if not (srcText and dstText) then
        srcText, dstText = LookLikeCopyTextParts(text)
    end
    if not (srcText and dstText) then return nil end

    local srcUnits = DetectUnits(srcText)
    local srcGroups = DetectGroups(srcText)
    local dstUnits = DetectUnits(dstText)
    local dstGroups = DetectGroups(dstText)
    if #srcUnits > 0 and #dstGroups > 0 then
        return {
            kind = "answer",
            status = "info",
            text = "I can copy unit frame options to other unit frames, and group frame options to other group frames. Unit frames and group frames use different layout options, so ask for those copies separately. Examples: copy just text options from target to player, or copy just health and text options from party to raid.",
            summary = "Unit frames and group frames need separate copy requests.",
        }
    end
    if #srcGroups > 0 and #dstUnits > 0 then
        return {
            kind = "answer",
            status = "info",
            text = "I can copy group frame options to other group frames, and unit frame options to other unit frames. Group frames and unit frames use different layout options, so ask for those copies separately. Examples: copy just health and text options from party to raid, or copy just text options from target to player.",
            summary = "Group frames and unit frames need separate copy requests.",
        }
    end
    return nil
end

local function ParseCopy(text)
    if not HasCopyIntent(text) then return nil end
    local source, targets
    local srcText, dstText = CopyTextParts(text)
    if not (srcText and dstText) then
        srcText, dstText = LookLikeCopyTextParts(text)
    end
    if srcText and dstText then
        local srcUnits = DetectUnits(srcText)
        source = srcUnits[1]
        targets = CopyTargetsForText(dstText, source)
    end
    if not source or not targets or #targets == 0 then
        local units = DetectUnits(text)
        if #units < 2 then return nil end
        source = units[1]
        targets = {}
        for i = 2, #units do targets[#targets + 1] = units[i] end
    end
    -- Unit Copy To deliberately excludes placement and anchoring: copying
    -- those values can stack two secure frames exactly on top of each other.
    -- Never silently run the remaining/default categories when a request asks
    -- for an unsupported placement copy; that would turn a position-only
    -- sentence into a broad visual copy while still not moving the frame.
    if ContainsAny(text, UNIT_COPY_PLACEMENT_TERMS) then
        return {
            kind = "answer",
            status = "info",
            text = "Unit Frame Copy To does not copy position or anchoring, so I did not run a partial copy. Copy the visual categories you want separately, then place the target frame in MSUF Edit Mode.",
            summary = "Keeps unsupported unit-frame placement out of Copy To.",
        }
    end
    local action = Registry and Registry:GetAction("copy_unit")
    if not action then return nil end
    local confirm = (WantsFullUnitCopy and WantsFullUnitCopy(text)) or ContainsAny(text, ActionsPhrases[3]) or #targets > 2
    return {
        kind = "action",
        action = action,
        args = { source = source, targets = targets, scopes = CopyScopesForText(text) },
        confirmRequired = confirm,
        label = "Copy " .. UnitDisplayLabel(source) .. " options",
        summary = "Copies unit-frame options from one unit to another.",
    }
end

local function BuildContextReset(text, ctx)
    if not (ctx and type(ctx.lastUnit) == "string") then return nil end
    if not ContainsAny(text, ActionsPhrases[4]) then return nil end
    if not (HasPhrase(text, "it") or HasPhrase(text, "that") or HasPhrase(text, "das")) then return nil end
    local setting = ctx.lastSetting and Registry:GetSetting(ctx.lastSetting) or nil
    local isPosition = setting and (setting.attribute == "offsetX" or setting.attribute == "offsetY")
    local action = Registry and Registry:GetAction(isPosition and "reset_unit_position" or "reset_unit_page")
    return action and {
        kind = "action",
        action = action,
        args = { unit = ctx.lastUnit },
        confirmRequired = not isPosition,
        label = isPosition and "Reset previous frame position" or "Reset previous frame options",
        summary = "Continues with the last selected unit.",
    } or nil
end

local GROUP_STATUS_ICON_ALIASES = {
    { key = "roleIcon", size = "roleIconSize", anchor = "roleIconAnchor", x = "roleIconX", y = "roleIconY", layer = "roleIconLayer", style = "roleIconStyle", aliases = { "role icon", "role icons", "role indicator", "role indicators", "role symbol", "role symbols", "rollen icon", "rollen icons", "rollen indikator", "rollen symbol" } },
    { key = "leaderIcon", size = "leaderIconSize", anchor = "leaderIconAnchor", x = "leaderIconX", y = "leaderIconY", layer = "leaderIconLayer", style = "leaderIconStyle", aliases = { "leader icon", "leader icons", "leader indicator", "leader indicators", "leader symbol", "leader symbols", "gruppenleiter icon", "leiter icon", "anfuehrer icon" } },
    { key = "assistIcon", size = "assistIconSize", anchor = "assistIconAnchor", x = "assistIconX", y = "assistIconY", layer = "assistIconLayer", style = "assistIconStyle", aliases = { "assist icon", "assist icons", "assistant icon", "assistant icons", "assist indicator", "assist indicators", "assistant indicator", "assistant indicators", "assist symbol", "assist symbols", "assistant symbol", "assistant symbols" } },
    { key = "raidMarker", size = "raidMarkerSize", anchor = "raidMarkerAnchor", x = "raidMarkerX", y = "raidMarkerY", layer = "raidMarkerLayer", style = "raidMarkerStyle", aliases = { "raid marker", "raid marker icon", "raid marker indicator", "raid marker symbol", "target marker", "target marker icon", "target marker indicator", "target marker symbol", "raid markierung", "ziel markierung", "zielmarker" } },
    { key = "readyCheckIcon", size = "readyCheckSize", anchor = "readyCheckAnchor", x = "readyCheckX", y = "readyCheckY", layer = "readyCheckLayer", style = "readyCheckIconStyle", aliases = { "ready check", "ready check icon", "ready check indicator", "ready check symbol", "ready icon", "ready indicator", "ready symbol", "bereitschaftscheck", "bereitschaftscheck icon", "readycheck icon" } },
    { key = "summonIcon", size = "summonIconSize", anchor = "summonAnchor", x = "summonX", y = "summonY", layer = "summonLayer", style = "summonIconStyle", aliases = { "summon icon", "summon indicator", "summon symbol", "beschwoerung icon", "beschwoeren icon" } },
    { key = "resurrectIcon", size = "resurrectIconSize", anchor = "resurrectAnchor", x = "resurrectX", y = "resurrectY", layer = "resurrectLayer", style = "resurrectIconStyle", aliases = { "resurrect icon", "resurrect indicator", "resurrect symbol", "resurrection icon", "resurrection indicator", "resurrection symbol", "rez icon", "rez indicator", "rez symbol", "incoming resurrection", "incoming resurrection icon", "incoming resurrection indicator", "incoming resurrection symbol", "wiederbelebung icon", "wiederbelebungs icon", "eingehende wiederbelebung" } },
    { key = "pvpIcon", size = "pvpIconSize", anchor = "pvpIconAnchor", x = "pvpIconX", y = "pvpIconY", layer = "pvpIconLayer", style = "pvpIconStyle", aliases = { "pvp flag", "pvp icon", "pvp flag icon", "pvp indicator", "pvp flag indicator", "pvp status", "war mode indicator", "flagged indicator" } },
    { key = "phaseIcon", size = "phaseIconSize", anchor = "phaseAnchor", x = "phaseX", y = "phaseY", layer = "phaseLayer", style = "phaseIconStyle", aliases = { "phase icon", "phasing icon", "phase indicator", "phasing indicator", "phase symbol", "phasing symbol" } },
    { key = "statusText", size = "statusTextSize", anchor = "statusTextAnchor", x = "statusOffsetX", y = "statusOffsetY", layer = "statusTextLayer", aliases = { "dead text", "dead status text", "status text", "offline text", "offline status text", "offline indicator", "disconnected text", "connection text" } },
    { key = "statusGhostText", size = "statusGhostTextSize", anchor = "statusGhostTextAnchor", x = "statusGhostOffsetX", y = "statusGhostOffsetY", layer = "statusGhostTextLayer", aliases = { "ghost text", "ghost status text" } },
    { key = "statusAFKText", size = "statusAFKTextSize", anchor = "statusAFKTextAnchor", x = "statusAFKOffsetX", y = "statusAFKOffsetY", layer = "statusAFKTextLayer", aliases = { "afk text", "dnd text", "afk dnd text", "away text" } },
}

local GROUP_STATUS_ICON_PACK_ALIASES = {
    inherit = "DEFAULT",
    global = "DEFAULT",
    default = "DEFAULT",
    ["follow global"] = "DEFAULT",
    blizzard = "BLIZZARD",
    classic = "CLASSIC",
    old = "CLASSIC",
    midnight = "MIDNIGHT",
    msuf = "MIDNIGHT",
    ux = "UXPRO",
    uxpro = "UXPRO",
    ["ux pro"] = "UXPRO",
    glossy = "GLOSSY_ORBS",
    ["glossy orbs"] = "GLOSSY_ORBS",
    dark = "DARK_EMBOSS",
    ["dark emboss"] = "DARK_EMBOSS",
    glass = "GLASS_PANELS",
    ["glass panels"] = "GLASS_PANELS",
    neon = "NEON_OUTLINE",
    ["neon outline"] = "NEON_OUTLINE",
    ring = "RING_SYMBOLS",
    ["ring symbols"] = "RING_SYMBOLS",
    dots = "DOTS",
    shapes = "SHAPES",
    diamonds = "DIAMONDS",
    squares = "SQUARES",
}
local STATUS_ICON_PACK_VALUES = {
    "DEFAULT", "BLIZZARD", "CLASSIC", "MIDNIGHT", "UXPRO", "GLOSSY_ORBS", "DARK_EMBOSS",
    "GLASS_PANELS", "NEON_OUTLINE", "RING_SYMBOLS", "DOTS", "SHAPES", "DIAMONDS", "SQUARES",
}
local STATUS_CORNER_PRESET_TERMS = {
    "top left", "top right", "bottom left", "bottom right",
    "upper left", "upper right", "lower left", "lower right",
    "topleft", "topright", "bottomleft", "bottomright",
}

local function GroupStatusIconForText(text)
    for i = 1, #GROUP_STATUS_ICON_ALIASES do
        local row = GROUP_STATUS_ICON_ALIASES[i]
        if ContainsAny(text, row.aliases) then return row.key end
    end
    return nil
end

local function HasGroupStatusScopeIntent(text)
    if #DetectGroups(text) > 0 then return true end
    if ContainsAny(text, ActionsPhrases[5]) then return true end
    local icon = GroupStatusIconForText(text)
    return icon == "readyCheckIcon" or icon == "summonIcon" or icon == "phaseIcon"
end

local function GroupStatusIconSpecForText(text)
    local key = GroupStatusIconForText(text)
    if not key then return nil end
    for i = 1, #GROUP_STATUS_ICON_ALIASES do
        if GROUP_STATUS_ICON_ALIASES[i].key == key then return GROUP_STATUS_ICON_ALIASES[i] end
    end
    return nil
end

local GROUP_STATUS_ICON_TERMS = {
    "status icon", "status icons", "status indicator", "status indicators", "indicator", "indicators", "symbol", "symbols",
    "role icon", "role icons", "rollen icon", "leader icon", "leader icons", "gruppenleiter icon", "assist icon", "assist icons",
    "raid marker", "raid markers", "raid markierung", "ready check", "ready icon", "bereitschaftscheck", "summon", "summon icon", "beschwoerung icon",
    "resurrect", "resurrect icon", "resurrection", "resurrection icon", "incoming resurrection",
    "incoming resurrection icon", "incoming rez", "incoming rez icon", "rez icon", "wiederbelebung icon", "eingehende wiederbelebung",
    "pvp flag", "pvp icon", "pvp indicator", "phase icon", "dead text", "offline text", "disconnected text", "connection text", "ghost text", "afk text", "dnd text",
}

local GROUP_STATUS_MIDNIGHT_STYLE_TERMS = {
    "midnight style", "use midnight style", "midnight icon style", "midnight icons",
    "midnight status icons", "status icon midnight style", "status icons midnight style",
}

local function FirstGroupOrDefault(text)
    local groups = DetectGroups(text)
    return groups[1] or "party"
end

local function AliasValueForText(text, aliases, values)
    local compactText = Compact(text)
    if type(aliases) == "table" then
        local bestValue, bestLen
        for alias, value in pairs(aliases) do
            local compactAlias = Compact(alias)
            if HasPhrase(text, alias) or (#compactAlias >= 5 and compactText:find(compactAlias, 1, true)) then
                local len = #compactAlias
                if not bestLen or len > bestLen then bestValue, bestLen = value, len end
            end
        end
        if bestValue ~= nil then return bestValue end
    end
    for i = 1, #(values or {}) do
        local value = values[i]
        local compactValue = Compact(value)
        if HasPhrase(text, tostring(value)) or (#compactValue >= 5 and compactText:find(compactValue, 1, true)) then return value end
    end
    return nil
end

local GROUP_SPELL_PLACED_ALIASES = { none = "none", off = "none", disabled = "none", hide = "none", aus = "none", verstecken = "none", icon = "icon", symbol = "icon", square = "square", quadrat = "square", dot = "square", punkt = "square", bar = "bar", balken = "bar", number = "number", zahl = "number", text = "number" }
local GROUP_SPELL_FRAME_ALIASES = { none = "none", off = "none", disabled = "none", hide = "none", aus = "none", healthtint = "healthtint", ["health tint"] = "healthtint", tint = "healthtint", einfaerben = "healthtint", border = "border", outline = "border", rahmen = "border", rand = "border", glow = "glow", leuchten = "glow", pulse = "pulse", pulsieren = "pulse", namecolor = "namecolor", ["name color"] = "namecolor", namensfarbe = "namecolor" }
local GROUP_SPELL_GROWTH_ALIASES = { rightdown = "RIGHTDOWN", ["right down"] = "RIGHTDOWN", ["right then down"] = "RIGHTDOWN", ["rechts runter"] = "RIGHTDOWN", leftdown = "LEFTDOWN", ["left down"] = "LEFTDOWN", ["left then down"] = "LEFTDOWN", ["links runter"] = "LEFTDOWN", rightup = "RIGHTUP", ["right up"] = "RIGHTUP", ["right then up"] = "RIGHTUP", ["rechts hoch"] = "RIGHTUP", leftup = "LEFTUP", ["left up"] = "LEFTUP", ["left then up"] = "LEFTUP", ["links hoch"] = "LEFTUP" }
local GROUP_SPELL_ANCHOR_ALIASES = { topleft = "TOPLEFT", ["top left"] = "TOPLEFT", ["oben links"] = "TOPLEFT", topright = "TOPRIGHT", ["top right"] = "TOPRIGHT", ["oben rechts"] = "TOPRIGHT", bottomleft = "BOTTOMLEFT", ["bottom left"] = "BOTTOMLEFT", ["unten links"] = "BOTTOMLEFT", bottomright = "BOTTOMRIGHT", ["bottom right"] = "BOTTOMRIGHT", ["unten rechts"] = "BOTTOMRIGHT", center = "CENTER", centre = "CENTER", middle = "CENTER", mitte = "CENTER", top = "TOP", oben = "TOP", bottom = "BOTTOM", unten = "BOTTOM", left = "LEFT", links = "LEFT", right = "RIGHT", rechts = "RIGHT" }

local function StatusAnchorIntent(text)
    if ContainsAny(text, ActionsPhrases[6]) then return true end
    if ContainsAny(text, ActionsPhrases[7]) and ContainsAny(text, ActionsPhrases[8]) then
        return true
    end
    if ContainsAny(text, ActionsPhrases[9])
        and ContainsAny(text, ActionsPhrases[10])
        and ContainsAny(text, ActionsPhrases[11])
    then
        return true
    end
    return false
end

local function StatusAnchorValueForText(text, aliases, values)
    if not StatusAnchorIntent(text) then return nil end
    if ContainsAny(text, ActionsPhrases[12])
        or (ContainsAny(text, ActionsPhrases[13]) and ContainsAny(text, ActionsPhrases[14]))
    then
        return AliasValueForText("top", aliases, values) or AliasValueForText("top left", aliases, values)
    end
    if ContainsAny(text, ActionsPhrases[15])
        or (ContainsAny(text, ActionsPhrases[16]) and ContainsAny(text, ActionsPhrases[17]))
    then
        return AliasValueForText("bottom", aliases, values) or AliasValueForText("bottom left", aliases, values)
    end
    return AliasValueForText(text, aliases, values)
end

local function ParseGroupSpellIndicatorAction(text, raw)
    if not ContainsAny(text, ActionsPhrases[18]) then return nil end
    local scope = FirstGroupOrDefault(text)
    local spec = A.ResolveGroupSpellSpec and A.ResolveGroupSpellSpec(text) or nil

    if ContainsAny(text, ActionsPhrases[19]) and spec and spec ~= "auto" and spec ~= "multi" then
        local action = Registry and Registry:GetAction("set_group_spell_indicator_multi_spec")
        local value = DetectBoolean(text)
        if value == nil then value = not ContainsAny(text, ActionsPhrases[20]) end
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, spec = spec, value = value },
            label = "Set group spell indicator multi-spec",
            summary = "Toggles a concrete spec entry in Spell Indicators Multi-Spec mode.",
        } or nil
    end

    local aura, resolvedSpec
    if type(A.ResolveGroupSpellAura) == "function" then
        aura, resolvedSpec = A.ResolveGroupSpellAura(spec, text)
    end
    spec = spec or resolvedSpec
    if ContainsAny(text, ActionsPhrases[21]) then
        local action = Registry and Registry:GetAction("reset_group_spell_indicator_aura")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, spec = spec, aura = aura or text },
            label = "Reset group spell indicator aura",
            summary = "Resets one tracked spell indicator entry to its defaults.",
        } or nil
    end

    if ContainsAny(text, ActionsPhrases[22]) and aura then
        local action = Registry and Registry:GetAction("move_group_spell_indicator_order")
        local position = FirstNumber(text)
        if ContainsAny(text, ActionsPhrases[23]) then position = 1 end
        if ContainsAny(text, ActionsPhrases[24]) then position = 999 end
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, spec = spec, aura = aura, position = position or 1 },
            label = "Move group spell indicator order",
            summary = "Changes the tracked spell display order.",
        } or nil
    end

    local field, value
    if ContainsAny(text, ActionsPhrases[25]) then
        field, value = "onlyOwn", DetectBoolean(text)
        if value == nil then value = true end
    elseif ContainsAny(text, ActionsPhrases[26]) then
        field, value = "placedCooldownSize", FirstNumber(text)
    elseif ContainsAny(text, ActionsPhrases[27]) then
        field, value = "placedCooldownSwipe", DetectBoolean(text)
    elseif ContainsAny(text, ActionsPhrases[28]) then
        field, value = "placedCooldown", DetectBoolean(text)
    elseif ContainsAny(text, ActionsPhrases[29]) then
        field, value = "placedMissing", DetectBoolean(text)
        if value == nil then value = true end
    elseif ContainsAny(text, ActionsPhrases[30]) then
        field, value = "placedBarWidth", FirstNumber(text)
    elseif ContainsAny(text, ActionsPhrases[31]) then
        field, value = "placedGrowth", AliasValueForText(text, GROUP_SPELL_GROWTH_ALIASES, { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" })
    elseif ContainsAny(text, ActionsPhrases[32]) then
        local r, g, b, label = ExtractColor(raw, text)
        if r then field, value = "frameColor", { r = r, g = g, b = b, label = label } end
    elseif ContainsAny(text, ActionsPhrases[33]) then
        field, value = "frameType", AliasValueForText(text, GROUP_SPELL_FRAME_ALIASES, { "none", "healthtint", "border", "glow", "pulse", "namecolor" })
    elseif ContainsAny(text, ActionsPhrases[34]) then
        field, value = "framePriority", FirstNumber(text)
    elseif ContainsAny(text, ActionsPhrases[35]) then
        field, value = "frameAlpha", FirstNumber(text)
        if value and value > 1 then value = value / 100 end
    elseif ContainsAny(text, ActionsPhrases[36]) then
        field, value = "frameThickness", FirstNumber(text)
    elseif ContainsAny(text, ActionsPhrases[37]) then
        field, value = "placedType", AliasValueForText(text, GROUP_SPELL_PLACED_ALIASES, { "none", "icon", "square", "bar", "number" })
    elseif ContainsAny(text, ActionsPhrases[38]) then
        field, value = "placedAnchor", AliasValueForText(text, GROUP_SPELL_ANCHOR_ALIASES, { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT" })
    elseif ContainsAny(text, ActionsPhrases[39]) then
        field, value = "placedX", FirstNumber(text)
    elseif ContainsAny(text, ActionsPhrases[40]) then
        field, value = "placedY", FirstNumber(text)
    elseif ContainsAny(text, ActionsPhrases[41]) then
        field, value = "placedSize", FirstNumber(text)
    else
        value = DetectBoolean(text)
        if value ~= nil then field = "enabled" end
    end

    if not (field and value ~= nil and aura) then return nil end
    local action = Registry and Registry:GetAction("set_group_spell_indicator_aura")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope, spec = spec, aura = aura, field = field, value = value },
        label = "Set group spell indicator",
        summary = "Configures one tracked spell indicator entry.",
    } or nil
end

local function HasGroupCornerIndicatorContext(text)
    if ContainsAny(text, ActionsPhrases[42]) then return true end
    if not (A.ResolveGroupCornerSlot and A.ResolveGroupCornerSlot(text)) then return false end
    return ContainsAny(text, ActionsPhrases[43])
end

local function GroupCornerData()
    local data = A.GroupFramesRegistry and A.GroupFramesRegistry.SpellIndicatorData
    return type(data) == "table" and data or {}
end

local function CornerChange(key, value, label)
    local setting = Registry and Registry:GetSetting(key)
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = label or setting.label,
        summary = "Changes a Group Corner Indicator option.",
    } or nil
end

local function CornerSpellIdList(raw, text)
    local source = tostring(raw or text or "")
    local out = {}
    for id in source:gmatch("%d+") do out[#out + 1] = id end
    if #out == 0 then return nil end
    return table.concat(out, ",")
end

local function CornerFilterValue(text, data)
    local compactText = Compact(text)
    local compactFilterText = compactText:gsub("[^%w]", "")
    if compactFilterText:find("helpfulplayer", 1, true) then return "HELPFUL|PLAYER" end
    if compactFilterText:find("harmfulplayer", 1, true) then return "HARMFUL|PLAYER" end
    if HasPhrase(text, "helpful") and HasPhrase(text, "player") then return "HELPFUL|PLAYER" end
    if HasPhrase(text, "harmful") and HasPhrase(text, "player") then return "HARMFUL|PLAYER" end
    local value = AliasValueForText(text, data and data.CI_FILTER_ALIASES, data and data.CI_FILTER_VALUES)
    if value then return value end
    if compactText:find("helpful", 1, true) then return "HELPFUL" end
    if compactText:find("harmful", 1, true) then return "HARMFUL" end
    return nil
end

local function ParseGroupCornerIndicatorSetting(text, raw)
    if not HasGroupCornerIndicatorContext(text) then return nil end
    local scope = FirstGroupOrDefault(text)
    local data = GroupCornerData()
    local slot = A.ResolveGroupCornerSlot and A.ResolveGroupCornerSlot(text) or nil
    if slot then
        local prefix = "gf_" .. tostring(scope) .. "."
        if ContainsAny(text, ActionsPhrases[44]) then
            local value = CornerFilterValue(text, data)
            return value and CornerChange(prefix .. "ciCustom" .. tostring(slot.key) .. ".filter", value, "Set corner custom filter") or nil
        end
        if ContainsAny(text, ActionsPhrases[45]) then
            local value = AliasValueForText(text, data.CI_MODE_ALIASES, data.CI_MODE_VALUES)
            return value and CornerChange(prefix .. "ciCustom" .. tostring(slot.key) .. ".mode", value, "Set corner custom mode") or nil
        end
        if ContainsAny(text, ActionsPhrases[46]) then
            local value = CornerSpellIdList(raw, text)
            return value and CornerChange(prefix .. "ciCustom" .. tostring(slot.key) .. ".spells", value, "Set corner custom spell IDs") or nil
        end
        if ContainsAny(text, ActionsPhrases[47]) then
            local r, g, b, label = ExtractColor(raw, text)
            if r then
                return CornerChange(prefix .. "ciCustom" .. tostring(slot.key) .. ".color", { r = r, g = g, b = b, label = label }, "Set corner custom color")
            end
        end
        local category = AliasValueForText(text, data.CI_CATEGORY_ALIASES, data.CI_CATEGORY_VALUES)
        if category then
            return CornerChange(prefix .. "ciSlot" .. tostring(slot.key), category, "Set corner indicator slot")
        end
    end

    if ContainsAny(text, ActionsPhrases[48]) then
        local value = FirstNumber(text)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
        return CornerChange("gf_" .. tostring(scope) .. ".ciAlpha", value, "Set corner indicator opacity")
    end
    if ContainsAny(text, ActionsPhrases[49]) then
        local value = FirstNumber(text)
        return value and CornerChange("gf_" .. tostring(scope) .. ".ciSize", value, "Set corner indicator size") or nil
    end
    local bool = DetectBoolean(text)
    if bool ~= nil then
        return CornerChange("gf_" .. tostring(scope) .. ".ciEnabled", bool, "Toggle corner indicators")
    end
    return nil
end
local function ParseGroupCornerIndicatorReset(text)
    if not ContainsAny(text, ActionsPhrases[50]) then return nil end
    if not ContainsAny(text, ActionsPhrases[51]) then return nil end
    local scope = FirstGroupOrDefault(text)
    local slot = A.ResolveGroupCornerSlot and A.ResolveGroupCornerSlot(text) or nil
    if slot then
        local action = Registry and Registry:GetAction("reset_group_corner_indicator_slot")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, slot = slot.key },
            label = "Reset group corner indicator slot",
            summary = "Resets one corner indicator slot and clears its custom spell setup.",
        } or nil
    end
    local action = Registry and Registry:GetAction("reset_group_corner_indicators")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope },
        confirmRequired = true,
        label = "Reset group corner indicators",
        summary = "Resets all corner indicator slots for the selected group.",
    } or nil
end

local function ParseGroupStatusIconReset(text)
    if not ContainsAny(text, ActionsPhrases[52]) then return nil end
    if not ContainsAny(text, GROUP_STATUS_ICON_TERMS) then return nil end
    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    if #explicitUnits > 0 and #explicitGroups == 0 then return nil end
    if #explicitGroups == 0 and not HasGroupStatusScopeIntent(text) then return nil end
    if #explicitGroups == 0 and ContainsAny(text, ActionsPhrases[53]) then return nil end
    local scope = FirstGroupOrDefault(text)
    local icon = GroupStatusIconForText(text)
    if icon then
        local action = Registry and Registry:GetAction("reset_group_status_icon")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, icon = icon },
            label = "Reset group status icon",
            summary = "Resets placement and icon style for one group status icon.",
        } or nil
    end
    local action = Registry and Registry:GetAction("reset_group_status_icons")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope },
        confirmRequired = true,
        label = "Reset group status icons",
        summary = "Resets placement and icon styles for all group status icons in the selected group.",
    } or nil
end

local function ParseGroupStatusPreview(text)
    if not ContainsAny(text, ActionsPhrases[54]) then return nil end
    if not ContainsAny(text, GROUP_STATUS_ICON_TERMS) then return nil end
    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    if #explicitUnits > 0 and #explicitGroups == 0 then return nil end
    if #explicitGroups == 0 and not HasGroupStatusScopeIntent(text) then return nil end
    if #explicitGroups == 0 and ContainsAny(text, ActionsPhrases[55]) then return nil end
    local scope = FirstGroupOrDefault(text)
    local icon = GroupStatusIconForText(text)
    local mode = ContainsAny(text, ActionsPhrases[56]) and "all" or "current"
    local action = Registry and Registry:GetAction("preview_group_status_icon")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope, icon = icon, mode = mode, text = text },
        label = mode == "all" and "Show all group status icons" or "Preview group status icon",
        summary = "Changes the group-frame status icon preview mode.",
    } or nil
end

local function RelativeLayerDeltaForText(text)
    local amount = FirstNumber(text) or 1
    if ContainsAny(text, ActionsPhrases[57]) then
        return -amount
    end
    if ContainsAny(text, ActionsPhrases[58]) then
        return amount
    end
    return nil
end

local function GroupStatusScopesForText(text)
    local scopes = {}
    if ContainsAny(text, ActionsPhrases[59]) then
        scopes[1], scopes[2], scopes[3] = "party", "raid", "mythicraid"
        return scopes
    end
    local groups = DetectGroups(text)
    if #groups > 0 then return groups end
    scopes[1] = FirstGroupOrDefault(text)
    return scopes
end

local function BuildGroupStatusChanges(scopes, dbKey, value, relativeDelta)
    local changes = {}
    for i = 1, #(scopes or {}) do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[i]) .. "." .. tostring(dbKey or ""))
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
    end
    return changes
end

local RAID_MARKER_SYMBOL_WORDS = {
    "star", "circle", "diamond", "triangle", "moon", "square", "cross", "x", "skull",
    "raid star", "raid circle", "raid diamond", "raid triangle", "raid moon", "raid square", "raid cross", "raid skull",
}

local function HasStatusOffsetIntent(text)
    return ContainsAny(text, ActionsPhrases[60])
        or HasPhrase(text, "x")
        or HasPhrase(text, "y")
end

local function HasGlobalUnitStatusTextStateIntent(text)
    return ContainsAny(text, ActionsPhrases[61])
end

local function RaidMarkerSymbolAnswer()
    return {
        kind = "answer",
        status = "info",
        text = "Raid Marker shows the actual WoW raid target marker. MSUF can show, hide, move, resize, anchor, and layer that indicator, but choosing Star/Circle/Skull is done on the unit in WoW.",
        summary = "Raid marker icons are chosen in WoW, not in MSUF.",
    }
end

local function ParseGroupStatusIconDetail(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    local hasGroupStatus = ContainsAny(text, GROUP_STATUS_ICON_TERMS)
    if not hasGroupStatus and not ContainsAny(text, GROUP_STATUS_MIDNIGHT_STYLE_TERMS) then return nil end

    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    if #explicitUnits > 0 and #explicitGroups == 0 then return nil end
    if #explicitGroups == 0 and HasGlobalUnitStatusTextStateIntent(text) then return nil end
    if #explicitGroups == 0 and ContainsAny(text, GROUP_STATUS_MIDNIGHT_STYLE_TERMS)
        and ContainsAny(text, ActionsPhrases[62])
    then
        return nil
    end
    if ContainsAny(text, ActionsPhrases[63])
        and not ContainsAny(text, ActionsPhrases[64])
    then
        return nil
    end

    local scopes = GroupStatusScopesForText(text)
    if ContainsAny(text, ActionsPhrases[65]) then
        local roleKey
        if ContainsAny(text, ActionsPhrases[66]) then
            roleKey = "roleIconShowTank"
        elseif ContainsAny(text, ActionsPhrases[67]) then
            roleKey = "roleIconShowHealer"
        elseif ContainsAny(text, ActionsPhrases[68]) then
            roleKey = "roleIconShowDPS"
        end
        if roleKey then
            local value = DetectBoolean(text)
            if value == nil then value = true end
            local changes = BuildGroupStatusChanges(scopes, roleKey, value)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Role Icon Visibility",
                    bulkSafe = #changes > 1,
                    summary = "Changes role-specific Group Frame role-icon visibility.",
                }
            end
        end
    end
    if ContainsAny(text, GROUP_STATUS_MIDNIGHT_STYLE_TERMS) then
        local value = DetectBoolean(text)
        if value == nil then
            if ContainsAny(text, ActionsPhrases[69]) then
                value = false
            elseif ContainsAny(text, ActionsPhrases[70]) then
                value = true
            end
        end
        if value ~= nil then
            local changes = BuildGroupStatusChanges(scopes, "useMidnightIcons", value)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icons Use Midnight Style",
                    bulkSafe = #changes > 1,
                    summary = "Changes the group-frame Midnight status icon style without changing individual icon visibility.",
                }
            end
        end
    end

    local iconSpec = GroupStatusIconSpecForText(text)
    if not iconSpec then return nil end
    -- "Raid marker" names the indicator, so DetectGroups deliberately removes
    -- that phrase before looking for an explicit group scope.  When no unit or
    -- group was named, use the Raid workspace instead of the generic Party
    -- fallback; explicit scopes such as "party raid marker" still win.
    if #explicitUnits == 0
        and #explicitGroups == 0
        and iconSpec.key == "raidMarker"
        and HasPhrase(text, "raid marker")
    then
        scopes = { "raid" }
    end
    if iconSpec.key == "raidMarker" and ContainsAny(text, RAID_MARKER_SYMBOL_WORDS)
        and not HasStatusOffsetIntent(text)
        and FirstNumber(text) == nil
    then
        return RaidMarkerSymbolAnswer()
    end
    local anchorIntent = StatusAnchorIntent(text)

    local enabledKey = iconSpec.enabled or iconSpec.key
    if enabledKey and not anchorIntent then
        local value = DetectBoolean(text)
        if value == nil then
            if ContainsAny(text, ActionsPhrases[71]) then
                value = false
            elseif ContainsAny(text, ActionsPhrases[72]) then
                value = true
            end
        end
        if value ~= nil then
            local changes = BuildGroupStatusChanges(scopes, enabledKey, value)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon Visibility",
                    bulkSafe = #changes > 1,
                    summary = "Changes the selected group status icon visibility toggle.",
                }
            end
        end
    end

    if ContainsAny(text, ActionsPhrases[73])
        and type(iconSpec.style) == "string" and iconSpec.style ~= ""
    then
        local setting = Registry and Registry:GetSetting(
            "gf_" .. tostring(scopes[1] or "") .. "." .. tostring(iconSpec.style))
        local value = AliasValueForText(text, GROUP_STATUS_ICON_PACK_ALIASES, STATUS_ICON_PACK_VALUES)
        if value == nil and setting and setting.type == "string" and P.ValueForRegistrySetting then
            value = P.ValueForRegistrySetting(setting, text, text)
        end
        if value ~= nil then
            local changes = BuildGroupStatusChanges(scopes, iconSpec.style, value)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group " .. tostring(iconSpec.key or "Status") .. " Icon Pack",
                    bulkSafe = #changes > 1,
                    summary = "Changes the icon pack for the selected group status indicator without changing its visibility.",
                }
            end
        end
    end

    if anchorIntent and iconSpec.anchor
        and not (ContainsAny(text, ActionsPhrases[74]) and DetectDirection(text)
            and not ContainsAny(text, ActionsPhrases[75])
            and not ContainsAny(text, STATUS_CORNER_PRESET_TERMS))
    then
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[1] or "") .. "." .. tostring(iconSpec.anchor))
        local value = setting and StatusAnchorValueForText(text, GROUP_SPELL_ANCHOR_ALIASES, setting.values or { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT" })
        if value ~= nil then
            local changes = BuildGroupStatusChanges(scopes, iconSpec.anchor, value)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon Anchor",
                    bulkSafe = #changes > 1,
                    summary = "Changes the selected group status icon anchor.",
                }
            end
        end
    end

    local offsetKey
    local offsetLabel
    if ContainsAny(text, ActionsPhrases[76]) or HasPhrase(text, "x") then
        offsetKey = iconSpec.x
        offsetLabel = "X Offset"
    elseif ContainsAny(text, ActionsPhrases[77]) or HasPhrase(text, "y") then
        offsetKey = iconSpec.y
        offsetLabel = "Y Offset"
    end
    if type(offsetKey) == "string" and offsetKey ~= "" then
        local value = FirstNumber(text)
        if value ~= nil then
            local changes = BuildGroupStatusChanges(scopes, offsetKey, value)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon " .. offsetLabel,
                    bulkSafe = #changes > 1,
                    summary = "Changes the X/Y offset for the selected group status icon.",
                }
            end
        end
    end

    if ContainsAny(text, ActionsPhrases[78]) then
        local direction = DetectDirection(text)
        local moveKey = direction and ((direction == "left" or direction == "right") and iconSpec.x or iconSpec.y)
        if type(moveKey) == "string" and moveKey ~= "" then
            local amount = FirstNumber(text) or 10
            if direction == "left" or direction == "down" then amount = -amount end
            local changes = BuildGroupStatusChanges(scopes, moveKey, nil, amount)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon Position",
                    bulkSafe = #changes > 1,
                    summary = "Moves the selected group status icon with its X/Y offset.",
                }
            end
        end
    end

    if ContainsAny(text, ActionsPhrases[79]) then
        local relativeDelta = RelativeLayerDeltaForText(text)
        local value
        if relativeDelta == nil then value = FirstNumber(text) end
        if value ~= nil or relativeDelta ~= nil then
            local changes = BuildGroupStatusChanges(scopes, iconSpec.layer, value, relativeDelta)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon Layer",
                    bulkSafe = #changes > 1,
                    summary = "Changes the selected group status icon layer.",
                }
            end
        end
    end

    if ContainsAny(text, ActionsPhrases[80]) then
        if ContainsAny(text, ActionsPhrases[81]) and DetectDirection(text) then return nil end
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[1] or "") .. "." .. tostring(iconSpec.size))
        local relativeDelta = P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text, 1) or nil
        local value
        if relativeDelta == nil then value = FirstNumber(text) end
        if value ~= nil or relativeDelta ~= nil then
            local changes = BuildGroupStatusChanges(scopes, iconSpec.size, value, relativeDelta)
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Group Status Icon Size",
                    bulkSafe = #changes > 1,
                    summary = "Changes the selected group status icon size.",
                }
            end
        end
    end

    return nil
end

local UNIT_STATUS_RESET_TERMS = {
    "status indicator", "status indicators", "status icon", "status icons", "status symbol", "status symbols", "indicator position", "level indicator", "level text",
    "leader icon", "leader indicator", "leader symbol", "assist icon", "assist indicator", "assist symbol",
    "raid marker", "raid marker icon", "raid marker indicator", "raid marker symbol", "raid icon", "raid indicator", "raid symbol", "raid group", "raid group name",
    "elite icon", "elite indicator", "elite symbol", "rare icon", "rare indicator", "rare symbol",
    "dead text", "status text", "combat indicator", "combat icon", "combat symbol", "combat state symbol",
    "rested indicator", "resting indicator", "rested icon", "resting icon", "rested symbol", "resting symbol",
    "incoming rez", "incoming rez indicator", "incoming rez symbol", "incoming resurrection", "incoming resurrection indicator", "incoming resurrection symbol",
    "resurrection icon", "resurrection indicator", "resurrection symbol",
    "pvp flag", "pvp indicator", "pvp icon", "pvp flag indicator", "pvp flag icon", "pvp status", "war mode indicator",
}

local UNIT_STATUS_RUNTIME_TEXT_TERMS = {
    "offline text", "offline indicator", "offline status", "offline status text", "offline status indicator",
    "disconnected text", "disconnected indicator", "disconnected status", "disconnected status text",
    "connection text", "connection indicator", "connection status", "connection status text",
    "ghost text", "ghost indicator", "ghost status", "ghost status text", "ghost status indicator",
    "afk text", "afk indicator", "afk status", "afk status text", "afk status indicator",
    "dnd text", "dnd indicator", "dnd status", "dnd status text", "dnd status indicator",
    "away text", "away indicator", "away status", "afk dnd text", "afk dnd indicator",
}

local UNIT_STATUS_TEXT_STATE_TERMS = {
    {
        key = "showDead",
        label = "Dead/Offline Text",
        terms = {
            "dead text dead units", "status text dead units", "show dead text for dead",
            "offline text", "offline indicator", "offline status", "offline status text", "offline status indicator",
            "disconnected text", "disconnected indicator", "disconnected status", "disconnected status text",
            "connection text", "connection indicator", "connection status", "connection status text",
        },
    },
    {
        key = "showGhost",
        label = "Ghost Text",
        terms = { "ghost text", "ghost indicator", "ghost status", "ghost status text", "ghost status indicator" },
    },
    {
        key = "showAFK",
        label = "AFK Text",
        terms = { "afk text", "afk indicator", "afk status", "afk status text", "afk status indicator", "away text", "away indicator", "away status" },
    },
    {
        key = "showDND",
        label = "DND Text",
        terms = { "dnd text", "dnd indicator", "dnd status", "dnd status text", "dnd status indicator" },
    },
}

local UNIT_STATUS_SIZE_TERMS = {
    "size", "font size", "text size", "icon size", "indicator size", "symbol size", "scale",
    "bigger", "larger", "smaller", "increase", "decrease", "reduce", "raise", "lower", "grow", "shrink",
    "groesse", "groesser", "kleiner", "erhoehe", "erhoehen", "reduziere", "verringere",
}

local UNIT_STATUS_MIDNIGHT_STYLE_TERMS = {
    "midnight style", "use midnight style", "midnight icon style", "midnight icons",
    "midnight status style", "midnight status icon", "midnight status icons",
    "status icon midnight style", "status icons midnight style",
    "status indicator midnight style", "status indicators midnight style",
    "classic style", "use classic style", "classic icon style", "classic icons",
    "classic status style", "classic status icon", "classic status icons",
    "status icon classic style", "status icons classic style",
    "status indicator classic style", "status indicators classic style",
}

local UNIT_STATUS_ICON_PACK_ALIASES = {
    blizzard = "BLIZZARD",
    default = "BLIZZARD",
    classic = "CLASSIC",
    old = "CLASSIC",
    midnight = "MIDNIGHT",
    msuf = "MIDNIGHT",
    ux = "UXPRO",
    uxpro = "UXPRO",
    ["ux pro"] = "UXPRO",
    glossy = "GLOSSY_ORBS",
    ["glossy orbs"] = "GLOSSY_ORBS",
    dark = "DARK_EMBOSS",
    ["dark emboss"] = "DARK_EMBOSS",
    glass = "GLASS_PANELS",
    ["glass panels"] = "GLASS_PANELS",
    neon = "NEON_OUTLINE",
    ["neon outline"] = "NEON_OUTLINE",
    ring = "RING_SYMBOLS",
    ["ring symbols"] = "RING_SYMBOLS",
    dots = "DOTS",
    shapes = "SHAPES",
    diamonds = "DIAMONDS",
    squares = "SQUARES",
}

local UNIT_STATUS_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    upperleft = "TOPLEFT",
    ["upper left"] = "TOPLEFT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    upperright = "TOPRIGHT",
    ["upper right"] = "TOPRIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    lowerleft = "BOTTOMLEFT",
    ["lower left"] = "BOTTOMLEFT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
    lowerright = "BOTTOMRIGHT",
    ["lower right"] = "BOTTOMRIGHT",
    center = "CENTER",
    centre = "CENTER",
    middle = "CENTER",
    top = "TOP",
    bottom = "BOTTOM",
    left = "LEFT",
    right = "RIGHT",
    nameright = "NAMERIGHT",
    ["name right"] = "NAMERIGHT",
    ["right of name"] = "NAMERIGHT",
    ["right to name"] = "NAMERIGHT",
    nameleft = "NAMELEFT",
    ["name left"] = "NAMELEFT",
    ["left of name"] = "NAMELEFT",
    ["left to name"] = "NAMELEFT",
}

local function UnitStatusHasIntent(text)
    return ContainsAny(text, UNIT_STATUS_RESET_TERMS) or ContainsAny(text, UNIT_STATUS_RUNTIME_TEXT_TERMS)
end

local function UnitStatusTextStateForText(text)
    for i = 1, #UNIT_STATUS_TEXT_STATE_TERMS do
        local spec = UNIT_STATUS_TEXT_STATE_TERMS[i]
        if ContainsAny(text, spec.terms) then return spec end
    end
    return nil
end

local function ResolveUnitStatusSpecForText(unit, text)
    local resolver = A.ResolveUnitStatusSpec
    local spec = resolver and resolver(unit, text) or nil
    if spec then return spec end
    if ContainsAny(text, UNIT_STATUS_RUNTIME_TEXT_TERMS) then
        return resolver and resolver(unit, "status text") or nil
    end
    return nil
end

local function UnitStatusUnitsOrCurrent(text)
    local units = DetectUnits(text)
    if #units == 0 then
        local currentPageUnit = P.CurrentPageUnit
        local currentUnit = type(currentPageUnit) == "function" and currentPageUnit() or nil
        if currentUnit then units = { currentUnit } end
    end
    return units
end

local function CurrentUnitStatusValue(unit)
    local selection = M and M.unitStatusSelection
    if type(selection) == "table" and type(selection[unit]) == "string" and selection[unit] ~= "" then
        return selection[unit]
    end
    return nil
end

local function ResolveUnitStatusSpecOrSelected(unit, text)
    local spec = ResolveUnitStatusSpecForText(unit, text)
    if spec then return spec end
    if ContainsAny(text, ActionsPhrases[82]) then
        local selected = CurrentUnitStatusValue(unit)
        if selected then return ResolveUnitStatusSpecForText(unit, selected) end
    end
    return nil
end

local function UnitStatusNeedsUnitContext(text)
    return ContainsAny(text, ActionsPhrases[83])
end

local function ParseUnitStatusIndicatorReset(text, ctx)
    if not ContainsAny(text, ActionsPhrases[84]) then return nil end
    if not UnitStatusHasIntent(text) then return nil end
    local units = UnitStatusUnitsOrCurrent(text)
    if #units == 0 and ctx and ctx.lastUnit then units = { ctx.lastUnit } end
    local action = Registry and Registry:GetAction("reset_unit_status_indicator")
    if #units == 0 and UnitStatusNeedsUnitContext(text) then
        return action and {
            kind = "action",
            action = action,
            args = { text = text },
            label = "Reset unit status indicator",
            summary = "Asks which unit frame or selected status indicator to reset.",
        } or nil
    end
    if #units == 0 then return nil end
    local unit = units[1]
    local spec = ResolveUnitStatusSpecOrSelected(unit, text)
    if not spec and UnitStatusNeedsUnitContext(text) then
        return action and {
            kind = "action",
            action = action,
            args = { unit = unit, text = text },
            label = "Reset unit status indicator",
            summary = "Asks which status indicator to reset.",
        } or nil
    end
    if not spec then return nil end
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit, status = spec.value, text = text },
        label = "Reset " .. UnitDisplayLabel(unit) .. " " .. tostring(spec.label or "status indicator"),
        summary = "Resets placement and style for one unit-frame status indicator.",
    } or nil
end

local function ParseUnitStatusPreview(text, ctx)
    if not ContainsAny(text, ActionsPhrases[85]) then return nil end
    if not UnitStatusHasIntent(text) then return nil end
    local units = UnitStatusUnitsOrCurrent(text)
    local unit = units[1] or (ctx and ctx.lastUnit) or "player"
    local spec = ResolveUnitStatusSpecOrSelected(unit, text)
    local mode = ContainsAny(text, ActionsPhrases[86]) and "all" or "current"
    local action = Registry and Registry:GetAction("preview_unit_status_indicator")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit, status = spec and spec.value, mode = mode, text = text },
        label = mode == "all" and "Show all status indicators" or "Preview status indicator",
        summary = "Changes the unit-frame status indicator preview mode.",
    } or nil
end

local function ParseUnitStatusIconStyle(text)
    if not ContainsAny(text, UNIT_STATUS_MIDNIGHT_STYLE_TERMS) then return nil end
    if not UnitStatusHasIntent(text) and not ContainsAny(text, ActionsPhrases[87]) then return nil end

    local value = DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, ActionsPhrases[88]) then
            value = false
        elseif ContainsAny(text, ActionsPhrases[89]) then
            value = true
        end
    end
    if value == nil then return nil end

    local setting = Registry and Registry:GetSetting("general.statusIconsUseMidnightStyle")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Status Icons Use Midnight Style",
        summary = "Changes the unit-frame status icon Midnight style without changing indicator visibility.",
    } or nil
end

local function ParseUnitStatusIndicatorDetail(text)
    if not UnitStatusHasIntent(text) then return nil end

    local units = UnitStatusUnitsOrCurrent(text)
    local unit = units[1]
    local visible = DetectBoolean(text)
    local textState = visible ~= nil and UnitStatusTextStateForText(text) or nil
    if textState then
        local changes = {}
        local globalStateIntent = ContainsAny(text, {
            "global", "globally", "all unit frames", "all unitframes",
            "every unit frame", "every unitframe", "shared",
        })
        local stateSpecificToggle = textState.key == "showAFK" or textState.key == "showDND"
        -- A scoped disable must hide the unit's Dead/Ghost/Offline text
        -- container, not turn that status off for every frame. Enabling a
        -- scoped state still needs both the global state and local container,
        -- while an explicitly global command changes only the shared state.
        if stateSpecificToggle or visible == true or not unit or globalStateIntent then
            local stateSetting = Registry and Registry:GetSetting("general.statusIndicators." .. textState.key)
            if stateSetting then
                changes[#changes + 1] = { setting = stateSetting, value = visible }
            end
        end
        if unit and not globalStateIntent and not stateSpecificToggle then
            local showSetting = Registry and Registry:GetSetting(unit .. ".statusTextEnabled")
            if showSetting then
                changes[#changes + 1] = { setting = showSetting, value = visible }
            end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = "Status Text " .. tostring(textState.label or "State"),
                bulkSafe = #changes > 1,
                summary = visible and "Enables the requested status text state and the unit Dead Text indicator when a unit was named." or "Disables the requested global status text state without hiding the whole Dead Text indicator.",
            }
        end
    end
    if #units == 0 then return nil end
    local spec = ResolveUnitStatusSpecOrSelected(unit, text)
    if not spec then return nil end
    if spec.value == "raidmarker" and ContainsAny(text, RAID_MARKER_SYMBOL_WORDS) and not HasStatusOffsetIntent(text) then
        return RaidMarkerSymbolAnswer()
    end

    if visible ~= nil and type(spec.show) == "string" and spec.show ~= "" then
        local changes, seen = {}, {}
        for i = 1, #units do
            local scopeUnit = tostring(units[i] or "")
            if scopeUnit ~= "" and not seen[scopeUnit] then
                seen[scopeUnit] = true
                local scopeSpec = ResolveUnitStatusSpecForText(scopeUnit, text)
                local showKey = scopeSpec and scopeSpec.show
                local setting = type(showKey) == "string" and showKey ~= ""
                    and Registry and Registry:GetSetting(scopeUnit .. "." .. showKey) or nil
                if setting then changes[#changes + 1] = { setting = setting, value = visible } end
            end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = #changes == 1
                    and (UnitDisplayLabel(unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Visibility")
                    or (tostring(spec.label or "Status Indicator") .. " Visibility"),
                bulkSafe = #changes > 1,
                summary = "Changes the visibility toggle for one unit-frame status indicator.",
            }
        end
    end

    -- Per-indicator icon packs are enum settings. Keep this distinct from
    -- general.statusIconsUseMidnightStyle above: "turn on Midnight style"
    -- toggles the global compatibility switch, while an explicit "icon
    -- pack/style/design" request selects the pack for the named indicator.
    if ContainsAny(text, ActionsPhrases[90])
        and type(spec.iconStyle) == "string" and spec.iconStyle ~= ""
    then
        local setting = Registry and Registry:GetSetting(unit .. "." .. spec.iconStyle)
        local values = setting and setting.values
            or (A.UnitframeRegistryData and A.UnitframeRegistryData.STATUS_ICON_PACK_FALLBACK_VALUES)
        local value = AliasValueForText(text, UNIT_STATUS_ICON_PACK_ALIASES, values)
        if value == nil and setting and setting.type == "string" and P.ValueForRegistrySetting then
            value = P.ValueForRegistrySetting(setting, text, text)
        end
        if setting and value ~= nil then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = UnitDisplayLabel(unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Icon Pack",
                summary = "Changes the icon pack for one unit-frame status indicator without changing its visibility.",
            }
        end
    end

    if (ContainsAny(text, ActionsPhrases[91]) or StatusAnchorIntent(text))
        and not (ContainsAny(text, ActionsPhrases[92]) and DetectDirection(text)
            and not ContainsAny(text, ActionsPhrases[93])
            and not ContainsAny(text, STATUS_CORNER_PRESET_TERMS))
        and type(spec.anchor) == "string" and spec.anchor ~= ""
    then
        local setting = Registry and Registry:GetSetting(unit .. "." .. spec.anchor)
        local value = setting and StatusAnchorValueForText(text, UNIT_STATUS_ANCHOR_ALIASES, setting.values or {
            "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "NAMERIGHT", "NAMELEFT",
        }) or nil
        if setting and value ~= nil then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = UnitDisplayLabel(unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Anchor",
                summary = "Changes the anchor for one unit-frame status indicator.",
            }
        end
    end

    if ContainsAny(text, ActionsPhrases[94])
        and type(spec.layer) == "string" and spec.layer ~= ""
    then
        local setting = Registry and Registry:GetSetting(unit .. "." .. spec.layer)
        local relativeDelta = RelativeLayerDeltaForText(text)
        local value
        if relativeDelta == nil then value = FirstNumber(text) end
        if setting and (value ~= nil or relativeDelta ~= nil) then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
                label = UnitDisplayLabel(unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Layer",
                summary = "Changes the layer for one unit-frame status indicator.",
            }
        end
    end

    local offsetKey
    local offsetLabel
    if ContainsAny(text, ActionsPhrases[95]) then
        offsetKey = spec.x
        offsetLabel = "X Offset"
    elseif ContainsAny(text, ActionsPhrases[96]) then
        offsetKey = spec.y
        offsetLabel = "Y Offset"
    end
    if type(offsetKey) == "string" and offsetKey ~= "" then
        local value = FirstNumber(text)
        local setting = value ~= nil and Registry and Registry:GetSetting(unit .. "." .. offsetKey) or nil
        if setting then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = UnitDisplayLabel(unit) .. " " .. tostring(spec.label or "Status Indicator") .. " " .. offsetLabel,
                summary = "Changes the X/Y offset for one unit-frame status indicator.",
            }
        end
    end

    if ContainsAny(text, UNIT_STATUS_SIZE_TERMS) and type(spec.size) == "string" and spec.size ~= "" then
        if ContainsAny(text, ActionsPhrases[97]) and DetectDirection(text) then return nil end
        local setting = Registry and Registry:GetSetting(unit .. "." .. spec.size)
        if not setting then return nil end

        local relativeDelta = P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text, 1) or nil
        local value
        if relativeDelta == nil then
            if not ContainsAny(text, ActionsPhrases[98]) then return nil end
            value = FirstNumber(text)
        end
        if value == nil and relativeDelta == nil then return nil end

        return {
            kind = "changes",
            changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
            label = UnitDisplayLabel(unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Size",
            summary = "Changes the size for one unit-frame status indicator.",
        }
    end

    return nil
end

local function ParseUnitStatusIndicatorMove(text)
    if not ContainsAny(text, ActionsPhrases[99]) then return nil end
    local direction = DetectDirection(text)
    if not direction then return nil end
    if not UnitStatusHasIntent(text) then return nil end
    local units = UnitStatusUnitsOrCurrent(text)
    if #units == 0 then return nil end
    local unit = units[1]
    local spec = ResolveUnitStatusSpecForText(unit, text)
    if not spec then return nil end
    local key = (direction == "left" or direction == "right") and spec.x or spec.y
    if type(key) ~= "string" or key == "" then return nil end
    local setting = Registry and Registry:GetSetting(unit .. "." .. key)
    if not setting then return nil end
    local amount = FirstNumber(text) or 10
    if direction == "left" or direction == "down" then amount = -amount end
    return {
        kind = "changes",
        changes = { { setting = setting, relativeDelta = amount, direction = direction } },
        label = UnitDisplayLabel(unit) .. " " .. tostring(spec.label or "Status Indicator") .. " Position",
        summary = "Moves a unit-frame status indicator with its X/Y offset.",
    }
end

local function ParseCustomAnchorWorkflow(text)
    if not ContainsAny(text, ActionsPhrases[100]) then return nil end
    if ContainsAny(text, ActionsPhrases[101]) then
        local action = Registry and Registry:GetAction("cancel_custom_anchor_picker")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Cancel custom anchor picker",
            summary = "Closes the custom anchor picker if it is active.",
        } or nil
    end
    if ContainsAny(text, ActionsPhrases[102]) then
        local action = Registry and Registry:GetAction("custom_anchor_picker_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show custom anchor picker status",
            summary = "Reports whether the custom anchor picker overlay is active.",
        } or nil
    end
    if not ContainsAny(text, ActionsPhrases[103]) then return nil end
    local groups = DetectGroups(text)
    if groups[1] then
        local action = Registry and Registry:GetAction("start_group_custom_anchor_picker")
        return action and {
            kind = "action",
            action = action,
            args = { scope = groups[1] },
            label = "Start group custom anchor picker",
            summary = "Starts the custom anchor picker for a group frame.",
        } or nil
    end
    local units = DetectUnits(text)
    local currentPageUnit = P.CurrentPageUnit
    local unit = units[1] or (type(currentPageUnit) == "function" and currentPageUnit() or nil)
    if not unit then
        local groupResolver = P.GroupScopesOrCurrentPage
        groups = type(groupResolver) == "function" and groupResolver(text) or {}
        if groups[1] then
            local action = Registry and Registry:GetAction("start_group_custom_anchor_picker")
            return action and {
                kind = "action",
                action = action,
                args = { scope = groups[1] },
                label = "Start group custom anchor picker",
                summary = "Starts the custom anchor picker for a group frame.",
            } or nil
        end
        if ContainsAny(text, ActionsPhrases[104]) then
            return {
                kind = "answer",
                status = "info",
                text = "Pick a concrete MSUF frame or open a Unit/Group page for the custom anchor picker. Examples: open player custom anchor picker, open target custom anchor picker, open raid custom anchor picker, or set target custom anchor to Cooldown Manager.",
                summary = "Shows how to start the custom anchor picker without guessing a frame.",
            }
        end
        return nil
    end
    local action = Registry and Registry:GetAction("start_unit_custom_anchor_picker")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit },
        label = "Start unit custom anchor picker",
        summary = "Starts the custom anchor picker for a unit frame.",
    } or nil
end

local function CleanCustomAnchorFrameName(name)
    name = Trim(tostring(name or ""))
    name = name:gsub("[\"'`]", "")
    name = name:gsub("^frame%s+", "")
    name = name:gsub("^name%s+", "")
    name = name:gsub("^named%s+", "")
    name = name:gsub("^called%s+", "")
    name = name:gsub("^to%s+", "")
    name = name:gsub("^as%s+", "")
    name = name:gsub("[%s%.%,;:!%?]+$", "")
    name = Trim(name)
    if name == "" then return nil end
    local lower = Normalize(name)
    if lower == "none" or lower == "free" or lower == "clear" or lower == "default" or lower == "global" then return "" end
    return name
end

local function RawCustomAnchorFrameName(raw)
    raw = tostring(raw or "")
    local lower = raw:lower()
    local asStart = lower:find("%s+as%s+", 5)
    if lower:find("^use%s+") and asStart and lower:sub(asStart):find("custom%s+anchor") then
        return CleanCustomAnchorFrameName(raw:sub(5, asStart - 1))
    end
    local connectors = { " to ", " as ", " named ", " called ", " frame ", " name " }
    local bestEnd
    for i = 1, #connectors do
        local start = 1
        while true do
            local s, e = lower:find(connectors[i], start, true)
            if not s then break end
            if not bestEnd or e > bestEnd then bestEnd = e end
            start = e + 1
        end
    end
    if bestEnd then return CleanCustomAnchorFrameName(raw:sub(bestEnd + 1)) end
    return nil
end

local function ParseCustomAnchorSet(text, raw)
    if not ContainsAny(text, ActionsPhrases[105]) then return nil end
    if not ContainsAny(text, ActionsPhrases[106]) then return nil end
    local frameName = (P.CooldownManagerAnchorValueForText and P.CooldownManagerAnchorValueForText(text)) or RawCustomAnchorFrameName(raw)
    if frameName == nil then return nil end

    local groups = DetectGroups(text)
    if #groups > 0 then
        local changes = {}
        for i = 1, #groups do
            local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. ".customAnchorFrame")
            if setting then changes[#changes + 1] = { setting = setting, value = frameName } end
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            label = "Set group custom anchor frame",
            summary = "Writes the Group Layout custom anchor frame name directly, matching the custom anchor text box result.",
        }
    end

    local units = DetectUnits(text)
    if #units == 0 then return nil end
    local setting = Registry and Registry:GetSetting(units[1] .. ".anchorFrameName")
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = frameName } },
        label = "Set unit custom anchor frame",
        summary = "Sets the custom anchor frame name to match the text box.",
    }
end

local function ParseCustomAnchorClear(text)
    if not ContainsAny(text, ActionsPhrases[107]) then return nil end
    if not ContainsAny(text, ActionsPhrases[108]) then return nil end
    local groups = DetectGroups(text)
    if groups[1] then
        local action = Registry and Registry:GetAction("clear_group_custom_anchor")
        return action and {
            kind = "action",
            action = action,
            args = { scope = groups[1] },
            label = "Clear " .. GroupDisplayLabel(groups[1]) .. " custom anchor",
            summary = "Clears the group-frame custom anchor frame name.",
        } or nil
    end
    local units = DetectUnits(text)
    local currentPageUnit = P.CurrentPageUnit
    local unit = units[1] or (type(currentPageUnit) == "function" and currentPageUnit() or nil)
    if not unit then
        local groupResolver = P.GroupScopesOrCurrentPage
        groups = type(groupResolver) == "function" and groupResolver(text) or {}
        if groups[1] then
            local action = Registry and Registry:GetAction("clear_group_custom_anchor")
            return action and {
                kind = "action",
                action = action,
                args = { scope = groups[1] },
                label = "Clear " .. GroupDisplayLabel(groups[1]) .. " custom anchor",
                summary = "Clears the group-frame custom anchor frame name.",
            } or nil
        end
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which custom anchor do you want me to clear? Name a unit frame such as Player or Target, or a group frame such as Party, Raid, or Mythic Raid. I kept MSUF unchanged.",
            summary = "Asks which frame should clear its custom anchor before execution.",
            actionInputClarification = true,
        }
    end
    local action = Registry and Registry:GetAction("clear_unit_custom_anchor")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit },
        label = "Clear " .. UnitDisplayLabel(unit) .. " custom anchor",
        summary = "Clears the unit-frame custom anchor frame name.",
    } or nil
end

local function ParseReset(text)
    -- Profile names such as "Default" overlap the broad reset vocabulary. A
    -- copy/duplicate sentence must reach the profile workflow parser instead
    -- of being converted into a destructive profile reset confirmation.
    if text:match("^copy%s+")
        or text:match("^duplicate%s+")
        or text:match("^clone%s+")
        or text:match("^dupe%s+")
        or text:match("^backup%s+")
        or text:match("^kopiere%s+")
        or text:match("^dupliziere%s+")
        or text:match("^sichere%s+")
    then
        return nil
    end
    -- "Restore my backup profile" is a profile-selection/import workflow,
    -- not permission to wipe the currently active profile. Let the Profiles
    -- parser ask for the exact backup name or import string.
    if ContainsAny(text, { "backup", "backup profile", "profile backup", "last backup" }) then
        return nil
    end
    if not ContainsAny(text, ActionsPhrases[109]) then return nil end
    if ContainsAny(text, ActionsPhrases[110]) then
        local action = Registry and Registry:GetAction("factory_reset_all")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Factory reset all MSUF options",
            summary = "Opens confirmation for a full MSUF factory reset.",
        } or nil
    end
    if ContainsAny(text, ActionsPhrases[111]) then
        -- "default" reaches this parser as a reset word, but it is also an
        -- ordinary adjective: "set new character default profile" and "default
        -- profile for new characters" are about which profile new characters
        -- start on, and were answered by offering to wipe the active profile.
        -- Resetting a profile is destructive, so it needs a real reset verb.
        if not ContainsAny(text, {
            "reset", "restore", "zuruecksetzen", "zurucksetzen",
            "werksreset", "werkseinstellungen", "vollreset",
        }) then
            return nil
        end
        local action = Registry and Registry:GetAction("reset_profile")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Reset active profile",
            summary = "Resets the active profile.",
        } or nil
    end
    if ContainsAny(text, ActionsPhrases[112])
        and ContainsAny(text, ActionsPhrases[113])
    then
        local action = Registry and Registry:GetAction("reset_focus_kick_position")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = action.label or "Reset Focus Kick position",
            summary = "Resets the Focus Kick on-screen tracker offsets.",
        } or nil
    end
    if ContainsAny(text, ActionsPhrases[114]) then
        local action = Registry and Registry:GetAction("reset_all_unit_positions")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Reset all unit-frame positions",
            summary = "Restores default unit-frame anchors and offsets.",
        } or nil
    end
    local units = DetectUnits(text)
    if #units == 0 then return nil end
    local unit = units[1]
    if ContainsAny(text, ActionsPhrases[115]) then
        local action = Registry and Registry:GetAction("reset_unit_position")
        return action and {
            kind = "action",
            action = action,
            args = { unit = unit },
            label = "Reset " .. UnitDisplayLabel(unit) .. " position",
            summary = "Restores default anchor and offsets.",
        } or nil
    end
    -- Whole-page reset is the fallback for "reset player settings". A sentence
    -- that names a narrower subject is not a request to wipe every option on
    -- that page: "reset target aura overrides" was answered by offering to
    -- reset the entire Target page, behind a confirmation whose wording did not
    -- describe that. Stand down and let a narrower lane -- or a clarification --
    -- answer instead.
    if ContainsAny(text, ActionsPhrases[159]) then return nil end
    local action = Registry and Registry:GetAction("reset_unit_page")
    return action and {
        kind = "action",
        action = action,
        args = { unit = unit },
        confirmRequired = true,
        label = "Reset " .. UnitDisplayLabel(unit) .. " options",
        summary = "Resets all options on that unit page.",
    } or nil
end

local function ParseOpen(text, raw)
    local explicit = ContainsAny(text, ActionsPhrases[116])
    local shortcut = false
    if not explicit and DetectBoolean(text) == nil and FirstNumber(text) == nil then
        -- "edit target auras" asks to be taken somewhere just as plainly as
        -- "open target auras", and answered with the aura fallback article
        -- until now. Behind the same no-value guard, so "edit target buff size
        -- to 30" still applies 30 instead of opening a page.
        explicit = ContainsAny(text, ActionsPhrases[158])
        shortcut = ContainsAny(text, ActionsPhrases[117])
        if not shortcut then
            for i = 1, #PAGE_TEXT_TARGETS do
                local spec = PAGE_TEXT_TARGETS[i]
                for j = 1, #(spec.terms or {}) do
                    if text == Normalize(spec.terms[j]) then
                        shortcut = true
                        break
                    end
                end
                if shortcut then break end
            end
        end
    end
    if not explicit and not shortcut then return nil end
    local page, label = PageForText(text)
    if not page then return nil end
    local action = Registry and Registry:GetAction("open_page")
    return action and {
        kind = "action",
        action = action,
        args = { page = page, label = label, query = raw or text },
        label = "Open " .. label,
        summary = "Navigates the Dashboard.",
    } or nil
end

local function DashboardPanelForText(text)
    if ContainsAny(text, ActionsPhrases[118]) then return "recovery", "recovery tools" end
    if ContainsAny(text, ActionsPhrases[119]) then return "scaling", "scaling tools" end
    if ContainsAny(text, ActionsPhrases[120]) then return "changelog", "changelog" end
    return nil, nil
end

local function ParseDashboardPanelAction(text)
    local panel, label = DashboardPanelForText(text)
    local explicit = ContainsAny(text, ActionsPhrases[121])
        or (panel ~= nil and P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text))
    if not explicit then return nil end
    if not panel and ContainsAny(text, ActionsPhrases[122]) then
        local open
        if ContainsAny(text, ActionsPhrases[123]) then
            open = false
        elseif ContainsAny(text, ActionsPhrases[124]) then
            open = nil
        else
            open = true
        end
        local panelArg = open == false and "all" or nil
        local action = Registry and Registry:GetAction("set_dashboard_panel")
        return action and {
            kind = "action",
            action = action,
            args = { panel = panelArg, open = open },
            label = "Set Dashboard panel",
            summary = "Asks which Dashboard panel to open, such as recovery tools, scaling tools, or changelog.",
        } or nil
    end
    if not panel then return nil end
    local open
    if ContainsAny(text, ActionsPhrases[125]) then
        open = false
    elseif ContainsAny(text, ActionsPhrases[126]) then
        open = nil
    else
        open = true
    end
    local action = Registry and Registry:GetAction("set_dashboard_panel")
    return action and {
        kind = "action",
        action = action,
        args = { panel = panel, open = open },
        label = (open == false and "Close " or (open == nil and "Toggle " or "Open ")) .. label,
        summary = "Changes whether that Dashboard panel is open or closed.",
    } or nil
end

local NAV_SECTION_TEXT_TARGETS = {
    { section = "groupframes", label = "Group Frames", terms = { "group frames", "groupframes", "raid frames", "party frames", "group frame", "groups", "gruppenframes", "gruppen frames", "gruppen", "schlachtzug frames", "gruppen sektion" } },
    { section = "unitframes", label = "Frames", terms = { "frames", "unitframes", "unit frames", "unit frame", "frame list", "einheitenframes", "unitframe sektion", "frames sektion", "frame liste" } },
    { section = "globalstyle", label = "Appearance", terms = { "appearance", "global style", "globalstyle", "style section", "look section", "darstellung", "aussehen", "stil sektion", "optik bereich" } },
    { section = "modules", label = "Advanced", terms = { "advanced", "modules", "module section", "advanced menu", "erweitert", "module", "modul sektion", "erweitert sektion" } },
    { section = "auras", label = "Auras", terms = { "auras", "aura section", "buffs section", "debuffs section", "auren", "auren sektion", "buff sektion", "debuff sektion" } },
}

local function NavSectionForText(text)
    for i = 1, #NAV_SECTION_TEXT_TARGETS do
        local spec = NAV_SECTION_TEXT_TARGETS[i]
        if ContainsAny(text, spec.terms) then return spec.section, spec.label end
    end
    return nil, nil
end

local function ParseNavRailAction(text)
    if ContainsAny(text, ActionsPhrases[127]) then
        local command
        if ContainsAny(text, ActionsPhrases[128]) then
            command = "seen"
        elseif ContainsAny(text, ActionsPhrases[129]) then
            command = "reset"
        elseif ContainsAny(text, ActionsPhrases[130]) then
            command = "show"
        end
        if not command then return nil end
        local action = Registry and Registry:GetAction("set_nav_search_intro")
        return action and {
            kind = "action",
            action = action,
            args = { command = command },
            label = "Set search intro",
            summary = "Shows or hides the menu search intro.",
        } or nil
    end

    if not ContainsAny(text, ActionsPhrases[131]) then return nil end
    if not ContainsAny(text, ActionsPhrases[132]) then return nil end
    local section, label = NavSectionForText(text)
    local open
    if ContainsAny(text, ActionsPhrases[133]) then
        open = false
    elseif ContainsAny(text, ActionsPhrases[134]) then
        open = nil
    else
        open = true
    end
    local action = Registry and Registry:GetAction("set_nav_section")
    if not section then
        return action and {
            kind = "action",
            action = action,
            args = { open = open },
            label = "Set navigation section",
            summary = "Asks which navigation section to use, such as Frames, Group Frames, Appearance, or Advanced.",
        } or nil
    end
    return action and {
        kind = "action",
        action = action,
        args = { section = section, open = open },
        label = (open == false and "Close " or (open == nil and "Toggle " or "Open ")) .. label .. " navigation section",
        summary = "Expands or collapses a menu section.",
    } or nil
end

local function ParseMenuWindowAction(text)
    if ContainsAny(text, ActionsPhrases[135]) then return nil end
    if not ContainsAny(text, ActionsPhrases[136]) then return nil end
    local actionKey
    local label
    if ContainsAny(text, ActionsPhrases[137]) then
        actionKey = "menu_window_restore"
        label = "Restore MSUF menu"
    elseif ContainsAny(text, ActionsPhrases[138]) then
        actionKey = "menu_window_minimize"
        label = "Minimize MSUF menu"
    elseif ContainsAny(text, ActionsPhrases[139]) then
        actionKey = "menu_window_maximize"
        label = "Maximize MSUF menu"
    elseif ContainsAny(text, ActionsPhrases[140]) then
        actionKey = "menu_window_close"
        label = "Close MSUF menu"
    end
    local action = actionKey and Registry and Registry:GetAction(actionKey)
    return action and {
        kind = "action",
        action = action,
        args = {},
        label = label,
        summary = "Opens, closes, or toggles the MSUF menu.",
    } or nil
end

function A._ParseMenuHistoryAction(text)
    text = tostring(text or "")
    if not (text:find("history", 1, true) or text:find("change", 1, true)
        or text:find("session", 1, true) or text:find("navrail", 1, true)
        or text:find("verlauf", 1, true) or text:find("aenderung", 1, true)
        or text:find("sitzung", 1, true)) then
        return nil
    end
    if not ContainsAny(text, ActionsPhrases[141]) then return nil end
    local actionKey
    local label
    local summary
    local confirmRequired
    if ContainsAny(text, ActionsPhrases[142])
        and ContainsAny(text, ActionsPhrases[143])
    then
        actionKey = "assistant.action.history.redo"
        label = "Redo Assistant change"
        summary = "Reapplies the last undone Assistant change."
    elseif ContainsAny(text, ActionsPhrases[144])
        and ContainsAny(text, ActionsPhrases[145])
    then
        actionKey = "assistant.action.history.undo"
        label = "Undo Assistant change"
        summary = "Undoes the last Assistant-made change."
    elseif ContainsAny(text, ActionsPhrases[146]) then
        actionKey = "menu_history_reset_session"
        label = "Reset menu session changes"
        summary = "Clears this MSUF menu change history."
        confirmRequired = true
    elseif ContainsAny(text, ActionsPhrases[147]) then
        actionKey = "menu_history_redo"
        label = "Redo menu change"
        summary = "Reapplies the last undone MSUF menu change."
    elseif ContainsAny(text, ActionsPhrases[148]) then
        actionKey = "menu_history_undo"
        label = "Undo menu change"
        summary = "Undoes the last MSUF menu change."
    end
    local action = actionKey and Registry and Registry:GetAction(actionKey)
    return action and {
        kind = "action",
        action = action,
        args = {},
        confirmRequired = confirmRequired,
        label = label,
        summary = summary,
    } or nil
end

local function RegistryActionAliasScore(action, text)
    if type(action) ~= "table" then return 0 end
    if type(action.parseAliasArgs) ~= "function" and action.aliasNoArgs ~= true then return 0 end
    local aliases = action.aliases
    if type(aliases) ~= "table" or #aliases == 0 then return 0 end
    local relationText = AliasRelationText(text)
    local best = 0
    for i = 1, #aliases do
        local alias = aliases[i]
        if TextMatchesAlias and TextMatchesAlias(text, relationText, alias) then
            local score = #Compact(alias)
            if score > best then best = score end
        elseif HasPhrase(text, alias) then
            local score = #Compact(alias)
            if score > best then best = score end
        end
    end
    return best
end

local ACTION_ALIAS_COMMON_TOKENS = {
    a = true,
    an = true,
    ["and"] = true,
    assistant = true,
    bit = true,
    bitte = true,
    brauche = true,
    can = true,
    could = true,
    danke = true,
    du = true,
    ["for"] = true,
    fuer = true,
    help = true,
    hey = true,
    hi = true,
    ich = true,
    im = true,
    ["in"] = true,
    just = true,
    kannst = true,
    koenntest = true,
    like = true,
    maybe = true,
    mir = true,
    moechte = true,
    msuf = true,
    my = true,
    need = true,
    of = true,
    on = true,
    please = true,
    pls = true,
    really = true,
    the = true,
    to = true,
    wanna = true,
    want = true,
    will = true,
    with = true,
    would = true,
    you = true,
}

local ACTION_ALIAS_FUZZY_CANDIDATE_LIMIT = 180
local ACTION_ALIAS_FUZZY_TOKEN_CACHE_LIMIT = 1024

local function ActionAliasTokens(text)
    local out = {}
    for token in Normalize(text):gmatch("%S+") do out[#out + 1] = token end
    return out
end

local function AddActionAliasBucket(index, token, action)
    if token == "" or ACTION_ALIAS_COMMON_TOKENS[token] then return false end
    local bucket = index.byToken[token]
    if not bucket then
        bucket = {}
        index.byToken[token] = bucket
    end
    bucket[#bucket + 1] = action
    if #token >= 4 and token:match("^[a-z]+$") then
        local first = token:sub(1, 1)
        index.fuzzyBuckets[first] = index.fuzzyBuckets[first] or {}
        index.fuzzyBuckets[first][#token] = index.fuzzyBuckets[first][#token] or {}
        local fuzzyBucket = index.fuzzyBuckets[first][#token]
        if fuzzyBucket[token] ~= true then
            fuzzyBucket[#fuzzyBucket + 1] = token
            fuzzyBucket[token] = true
        end
    end
    return true
end

local function EnsureRegistryActionAliasIndex(actions)
    actions = actions or {}
    if P._registryActionAliasActions == actions
        and P._registryActionAliasCount == #actions
        and type(P._registryActionAliasIndex) == "table" then
        return P._registryActionAliasIndex
    end

    local index = { byToken = {}, fuzzyBuckets = {}, fuzzyTokenCache = {}, fuzzyTokenOrder = {}, fuzzyTokenHead = 1, always = {} }
    for i = 1, #actions do
        local action = actions[i]
        if type(action) == "table"
            and (type(action.parseAliasArgs) == "function" or action.aliasNoArgs == true)
            and type(action.aliases) == "table" then
            local indexed = false
            for j = 1, #action.aliases do
                for _, token in ipairs(ActionAliasTokens(action.aliases[j])) do
                    indexed = AddActionAliasBucket(index, token, action) or indexed
                end
            end
            if not indexed then index.always[#index.always + 1] = action end
        end
    end

    P._registryActionAliasActions = actions
    P._registryActionAliasCount = #actions
    P._registryActionAliasIndex = index
    return index
end

P._EnsureRegistryActionAliasIndex = EnsureRegistryActionAliasIndex

function P.ClearActionAliasFuzzyCache()
    local index = P._registryActionAliasIndex
    if type(index) ~= "table" then return end
    index.fuzzyTokenCache = {}
    index.fuzzyTokenOrder = {}
    index.fuzzyTokenHead = 1
end

local function RememberActionFuzzyToken(index, token, value)
    index.fuzzyTokenCache = index.fuzzyTokenCache or {}
    index.fuzzyTokenOrder = index.fuzzyTokenOrder or {}
    local cache, order = index.fuzzyTokenCache, index.fuzzyTokenOrder
    local head = tonumber(index.fuzzyTokenHead) or 1
    if cache[token] == nil then
        order[#order + 1] = token
        if #order - head + 1 > ACTION_ALIAS_FUZZY_TOKEN_CACHE_LIMIT then
            cache[order[head]] = nil
            head = head + 1
            if head > ACTION_ALIAS_FUZZY_TOKEN_CACHE_LIMIT and head > (#order / 2) then
                local compact = {}
                for i = head, #order do compact[#compact + 1] = order[i] end
                order, head = compact, 1
                index.fuzzyTokenOrder = order
            end
        end
    end
    cache[token] = value
    index.fuzzyTokenHead = head
    return value
end

local function AddActionAliasCandidates(candidateSet, index, tokens)
    for i = 1, #(tokens or {}) do
        local bucket = index.byToken[tokens[i]]
        if bucket then
            for j = 1, #bucket do candidateSet[bucket[j]] = true end
        end
    end
end

local function FuzzyActionAliasTokenCandidates(index, token)
    token = Normalize(token)
    if token == "" or #token < 4 or ACTION_ALIAS_COMMON_TOKENS[token] or not token:match("^[a-z]+$") then return nil end
    local fuzzyWordMatch = P.FuzzyWordMatch or (A and A.FuzzyWordMatch)
    if type(fuzzyWordMatch) ~= "function" then return nil end
    index.fuzzyTokenCache = index.fuzzyTokenCache or {}
    local cached = index.fuzzyTokenCache[token]
    if cached ~= nil then return cached ~= false and cached or nil end

    local firstBuckets = index.fuzzyBuckets and index.fuzzyBuckets[token:sub(1, 1)]
    if type(firstBuckets) ~= "table" then
        RememberActionFuzzyToken(index, token, false)
        return nil
    end

    local out, seenActions, seenTokens = {}, {}, {}
    local len = #token
    for delta = -1, 1 do
        local bucket = firstBuckets[len + delta]
        for i = 1, #(bucket or {}) do
            local indexedToken = bucket[i]
            if not seenTokens[indexedToken] and fuzzyWordMatch(token, indexedToken) then
                seenTokens[indexedToken] = true
                local actions = index.byToken and index.byToken[indexedToken]
                for j = 1, #(actions or {}) do
                    local action = actions[j]
                    if action and not seenActions[action] then
                        seenActions[action] = true
                        out[#out + 1] = action
                        if #out > ACTION_ALIAS_FUZZY_CANDIDATE_LIMIT then
                            RememberActionFuzzyToken(index, token, false)
                            return nil
                        end
                    end
                end
            end
        end
    end

    RememberActionFuzzyToken(index, token, #out > 0 and out or false)
    return #out > 0 and out or nil
end

local function AddActionAliasFuzzyCandidates(candidateSet, index, tokens)
    for i = 1, #(tokens or {}) do
        local token = tokens[i]
        if not (index.byToken and index.byToken[token]) then
            local actions = FuzzyActionAliasTokenCandidates(index, token)
            for j = 1, #(actions or {}) do candidateSet[actions[j]] = true end
        end
    end
end

local function RegistryActionAliasCandidates(actions, text, allowFuzzy)
    local index = EnsureRegistryActionAliasIndex(actions)
    local candidateSet = {}
    local tokens = ActionAliasTokens(text)
    AddActionAliasCandidates(candidateSet, index, tokens)
    if allowFuzzy then AddActionAliasFuzzyCandidates(candidateSet, index, tokens) end
    local relationText = AliasRelationText(text)
    if relationText ~= text then
        local relationTokens = ActionAliasTokens(relationText)
        AddActionAliasCandidates(candidateSet, index, relationTokens)
        if allowFuzzy then AddActionAliasFuzzyCandidates(candidateSet, index, relationTokens) end
    end
    for i = 1, #(index.always or {}) do candidateSet[index.always[i]] = true end

    local out = {}
    for i = 1, #actions do
        local action = actions[i]
        if candidateSet[action] then out[#out + 1] = action end
    end
    P._lastRegistryActionAliasCandidateCount = #out
    P._lastRegistryActionAliasTotalCount = #actions
    return out
end
P.RegistryActionAliasCandidates = RegistryActionAliasCandidates

local EXACT_ACTION_PREFIXES = {
    "run ", "execute ", "start ", "show ", "use ", "apply ", "check ",
}

local function ExactActionPhraseText(text)
    text = Normalize(text)
    if text == "" then return "" end
    for i = 1, #EXACT_ACTION_PREFIXES do
        local prefix = EXACT_ACTION_PREFIXES[i]
        if text:sub(1, #prefix) == prefix then
            return Trim(text:sub(#prefix + 1))
        end
    end
    return text
end

local function AddExactActionPhrase(index, phrase, action)
    phrase = ExactActionPhraseText(phrase)
    if phrase == "" or #phrase < 4 then return end
    local existing = index[phrase]
    if existing == nil then
        index[phrase] = action
    elseif type(existing) == "table" and existing.key then
        if tostring(existing.key or "") == tostring(action and action.key or "") then return end
        index[phrase] = { existing, action }
    elseif type(existing) == "table" then
        local actionKey = tostring(action and action.key or "")
        for i = 1, #existing do
            if tostring(existing[i] and existing[i].key or "") == actionKey then return end
        end
        existing[#existing + 1] = action
    end
end

local function EnsureExactActionPhraseIndex(actions)
    actions = actions or {}
    if P._exactActionPhraseActions == actions
        and P._exactActionPhraseCount == #actions
        and type(P._exactActionPhraseIndex) == "table" then
        return P._exactActionPhraseIndex
    end

    local index = {}
    for i = 1, #actions do
        local action = actions[i]
        if type(action) == "table" then
            AddExactActionPhrase(index, action.label, action)
            if type(action.aliases) == "table" then
                for j = 1, #action.aliases do
                    local alias = Normalize(action.aliases[j])
                    if alias:sub(1, 5) ~= "open " then AddExactActionPhrase(index, action.aliases[j], action) end
                end
            end
        end
    end

    P._exactActionPhraseActions = actions
    P._exactActionPhraseCount = #actions
    P._exactActionPhraseIndex = index
    return index
end

P._EnsureExactActionPhraseIndex = EnsureExactActionPhraseIndex

function P.ParseExactActionPhraseShortcut(text, raw)
    local phrase = ExactActionPhraseText(raw or text)
    if phrase == "" then return nil end
    local actions = Registry and Registry:AllActions() or {}
    local index = EnsureExactActionPhraseIndex(actions)
    local match = index[phrase]
    if not match and ActionableText then
        local actionablePhrase = ExactActionPhraseText(ActionableText(raw or text))
        if actionablePhrase ~= "" and actionablePhrase ~= phrase then match = index[actionablePhrase] end
    end
    if not match then return nil end
    if type(match) == "table" and not match.key then
        local choices = {}
        for i = 1, #match do
            local action = match[i]
            choices[#choices + 1] = {
                kind = "action",
                action = action,
                args = {},
                confirmRequired = action.confirmRequired == true,
                label = type(A.DisplayActionLabel) == "function" and A.DisplayActionLabel(action) or action.label or "Assistant shortcut",
                summary = "Runs the matching Assistant shortcut.",
            }
        end
        return #choices > 0 and {
            kind = "choice",
            status = "needs_choice",
            summary = "Multiple Assistant shortcuts matched.",
            text = "Which Assistant shortcut do you want to run?",
            choices = choices,
        } or nil
    end
    local action = match
    local args, meta = {}, nil
    if type(action.parseAliasArgs) == "function" then
        local parsedArgs, parsedMeta = action.parseAliasArgs(Normalize(raw or text), raw, action)
        if parsedArgs == false then return nil end
        args = type(parsedArgs) == "table" and parsedArgs or {}
        meta = type(parsedMeta) == "table" and parsedMeta or nil
    end
    return {
        kind = "action",
        action = action,
        args = args,
        confirmRequired = action.confirmRequired == true or (meta and meta.confirmRequired == true),
        label = (meta and meta.label)
            or (type(A.DisplayActionLabel) == "function" and A.DisplayActionLabel(action) or action.label or "Assistant shortcut"),
        summary = (meta and meta.summary) or "Runs the matching Assistant shortcut.",
    }
end

local ACTION_EXPLAIN_PREFIXES = {
    "explain ", "describe ", "tell me about ", "what is ", "what are ",
    "what does ", "why use ", "why should i use ", "why would i use ",
    "why should i run ", "why would i run ",
}

-- Action labels need a lossless exact-match lane. The general parser
-- intentionally folds phrases such as "status icons" to "status icon" so
-- ordinary setting requests match both forms, but that would make two real
-- action names (Reset Group Status Icon / Icons) indistinguishable here.
local function NormalizeActionExplainExact(text)
    text = tostring(text or ""):lower()
    text = text:gsub("\195\164", "ae"):gsub("\195\182", "oe"):gsub("\195\188", "ue"):gsub("\195\159", "ss")
    text = text:gsub("[\"'`,;:!?%(%)]", " ")
    text = text:gsub("[_%.%-]+", " "):gsub("%s+", " ")
    return Trim(text)
end

local function ActionExplainTargetText(text, rawText)
    text = Normalize(text)
    local exactText = NormalizeActionExplainExact(rawText or text)
    if text == "" and exactText == "" then return nil end
    for i = 1, #ACTION_EXPLAIN_PREFIXES do
        local prefix = ACTION_EXPLAIN_PREFIXES[i]
        if exactText:sub(1, #prefix) == prefix then
            local exactTarget = Trim(exactText:sub(#prefix + 1))
            exactTarget = exactTarget:gsub("%s+do$", ""):gsub("%s+mean$", ""):gsub("%s+help with$", "")
            exactTarget = Trim(exactTarget)
            return Normalize(exactTarget), exactTarget
        end
        if text:sub(1, #prefix) == prefix then
            local target = Trim(text:sub(#prefix + 1))
            target = target:gsub("%s+do$", ""):gsub("%s+mean$", ""):gsub("%s+help with$", "")
            target = Trim(target)
            return target, NormalizeActionExplainExact(target)
        end
    end
    return nil
end

local function ActionExplainMatchScore(action, target, exactTarget)
    if type(action) ~= "table" or target == "" then return 0 end
    local best = 0
    local function consider(value, sourceRank)
        local exactValue = NormalizeActionExplainExact(value)
        value = Normalize(value)
        if value == "" then return end
        if exactTarget ~= "" and exactValue == exactTarget then
            -- Preserve the actual public spelling before plural/domain folds.
            local score = (tonumber(sourceRank) or 1) * 100000 + #Compact(exactValue)
            if score > best then best = score end
        elseif value == target then
            -- An exact public label is the canonical way to name an action.
            -- Aliases intentionally overlap (for example a dashboard-panel
            -- setter aliases "Open Recovery Tools"), so they must not tie a
            -- primary-label match and make an exact explanation ambiguous.
            local score = (tonumber(sourceRank) or 1) * 10000 + #Compact(value)
            if score > best then best = score end
        elseif HasPhrase(target, value) or HasPhrase(value, target) then
            local score = (tonumber(sourceRank) or 1) * 1000 + #Compact(value)
            if score > best then best = score end
        end
    end
    consider(action.label, 4)
    if type(A.DisplayActionLabel) == "function" then
        consider(A.DisplayActionLabel(action), 4)
    end
    if action.key ~= nil then
        consider((tostring(action.key):gsub("[_%.-]+", " ")), 3)
    end
    for i = 1, #(action.aliases or {}) do consider(action.aliases[i], 2) end
    return best
end

function P.ParseRegistryActionExplainShortcut(text, rawText)
    local target, exactTarget = ActionExplainTargetText(text, rawText)
    if not target or target == "" then return nil end
    local actions = Registry and Registry:AllActions() or {}
    local bestAction
    local bestActions = {}
    local bestScore = 0
    for i = 1, #actions do
        local action = actions[i]
        local score = ActionExplainMatchScore(action, target, exactTarget or "")
        if score > bestScore then
            bestAction = action
            bestActions = { action }
            bestScore = score
        elseif score > 0 and score == bestScore then
            bestActions[#bestActions + 1] = action
        end
    end
    if not bestAction or bestScore == 0 then return nil end
    if #bestActions > 1 then
        local lines = { "I found more than one Assistant action with that wording. I did not run anything." }
        for i = 1, #bestActions do
            local action = bestActions[i]
            local label = type(A.DisplayActionLabel) == "function" and A.DisplayActionLabel(action) or action.label or action.key or "Assistant action"
            lines[#lines + 1] = tostring(i) .. ". " .. tostring(label)
        end
        lines[#lines + 1] = "Ask with the exact action name, or use a result number after searching."
        return {
            kind = "answer",
            status = "ambiguous",
            label = "Multiple Assistant Actions",
            text = table.concat(lines, "\n"),
            summary = "Asks which action to explain instead of running an ambiguous action.",
        }
    end

    local label = type(A.DisplayActionLabel) == "function" and A.DisplayActionLabel(bestAction) or bestAction.label or bestAction.key or "Assistant action"
    local lines = {}
    lines[#lines + 1] = tostring(label)
    if type(bestAction.description) == "string" and bestAction.description ~= "" then
        lines[#lines + 1] = bestAction.description
    else
        lines[#lines + 1] = "This is an MSUF Assistant task, not a saved setting value."
    end
    local details = {}
    if bestAction.type then details[#details + 1] = "type: " .. tostring(bestAction.type) end
    if bestAction.page then details[#details + 1] = "page: " .. tostring(bestAction.page) end
    if bestAction.confirmRequired == true then details[#details + 1] = "requires confirmation" end
    if bestAction.combatSafe == false then details[#details + 1] = "not combat-safe" end
    if #details > 0 then lines[#lines + 1] = table.concat(details, ", ") .. "." end
    lines[#lines + 1] = "I did not run it from this explanation question."
    return {
        kind = "answer",
        status = "info",
        label = tostring(label),
        text = table.concat(lines, "\n"),
        summary = "Explains a registry action without running it.",
    }
end

local function LooksLikeNumericSettingChange(text)
    if FirstNumber(text) == nil then return false end
    if ContainsAny(text, ActionsPhrases[149]) then return false end
    if not ContainsAny(text, ActionsPhrases[150]) then
        return false
    end
    return ContainsAny(text, ActionsPhrases[151])
end

function P.ParseRegistryActionAliasShortcut(text, raw)
    if LooksLikeNumericSettingChange(text) then return nil end
    if ContainsAny(text, ActionsPhrases[152])
        and ContainsAny(text, ActionsPhrases[153])
        and ContainsAny(text, ActionsPhrases[154])
    then
        return nil
    end
    if ContainsAny(text, ActionsPhrases[155])
        and ContainsAny(text, ActionsPhrases[156])
        and (FirstNumber(text) ~= nil or ContainsAny(text, ActionsPhrases[157]))
    then
        return nil
    end
    local actions = Registry and Registry:AllActions() or {}
    local function scan(matchText, allowFuzzy)
        local previousFuzzy = P._allowFuzzyAliasMatch
        if allowFuzzy then P._allowFuzzyAliasMatch = true end
        local function run()
            local bestAction, bestArgs, bestMeta, bestScore
            local candidates = RegistryActionAliasCandidates(actions, matchText, allowFuzzy)
            for i = 1, #candidates do
                local action = candidates[i]
                local score = RegistryActionAliasScore(action, matchText)
                if score > 0 and (not bestScore or score > bestScore) then
                    local args, meta
                    if type(action.parseAliasArgs) == "function" then
                        local parsedArgs, parsedMeta = action.parseAliasArgs(matchText, raw, action)
                        if parsedArgs ~= false then
                            args = type(parsedArgs) == "table" and parsedArgs or {}
                            meta = type(parsedMeta) == "table" and parsedMeta or nil
                        end
                    elseif action.aliasNoArgs == true then
                        args = {}
                    end
                    if args then
                        bestAction, bestArgs, bestMeta, bestScore = action, args, meta, score
                    end
                end
            end
            return bestAction, bestArgs, bestMeta, bestScore
        end
        if not allowFuzzy then return run() end
        local ok, bestAction, bestArgs, bestMeta, bestScore = pcall(run)
        P._allowFuzzyAliasMatch = previousFuzzy
        if not ok then error(bestAction) end
        return bestAction, bestArgs, bestMeta, bestScore
    end

    local bestAction, bestArgs, bestMeta, bestScore
    bestAction, bestArgs, bestMeta, bestScore = scan(text, false)
    local actionable = ActionableText and ActionableText(text) or text
    if not bestAction and actionable ~= "" and actionable ~= text then
        bestAction, bestArgs, bestMeta, bestScore = scan(actionable, false)
    end
    if not bestAction then
        local fallbackText = (actionable ~= "" and actionable) or text
        bestAction, bestArgs, bestMeta, bestScore = scan(fallbackText, true)
    end
    if not bestAction then return nil end
    return {
        kind = "action",
        action = bestAction,
        args = bestArgs or {},
        confirmRequired = bestAction.confirmRequired == true or (bestMeta and bestMeta.confirmRequired == true),
        label = (bestMeta and bestMeta.label) or (type(A.DisplayActionLabel) == "function" and A.DisplayActionLabel(bestAction) or bestAction.label or "Assistant shortcut"),
        summary = (bestMeta and bestMeta.summary) or "Runs the matched Assistant shortcut.",
    }
end

function P.ParseExactActionKeyShortcut(text, raw)
    local hay = tostring(raw or text or ""):lower()
    if not hay:find("_", 1, true) and not hay:find(".", 1, true) then return nil end
    if not hay:find("[%a_][%w_%.]*", 1) then return nil end
    local actions = Registry and Registry:AllActions() or {}
    local bestAction
    local bestKeyLen = 0
    for i = 1, #actions do
        local action = actions[i]
        local key = tostring(action and action.key or "")
        local keyLower = key:lower()
        local startPos = keyLower ~= "" and hay:find(keyLower, 1, true) or nil
        local before = startPos == nil or startPos == 1 or not hay:sub(startPos - 1, startPos - 1):match("[%w_%.]")
        local afterIndex = startPos and (startPos + #keyLower) or nil
        local after = afterIndex == nil or afterIndex > #hay or not hay:sub(afterIndex, afterIndex):match("[%w_%.]")
        if startPos and before and after then
            local combined = (keyLower .. " " .. tostring(action.label or ""):lower() .. " " .. tostring(action.type or ""):lower())
            if not combined:find("aura", 1, true)
                and not combined:find("shape", 1, true)
                and not combined:find("rounded", 1, true)
            then
                if #keyLower > bestKeyLen then
                    bestAction = action
                    bestKeyLen = #keyLower
                end
            end
        end
    end
    if not bestAction then return nil end
    return {
        kind = "action",
        action = bestAction,
        args = {},
        confirmRequired = bestAction.confirmRequired == true,
        label = type(A.DisplayActionLabel) == "function" and A.DisplayActionLabel(bestAction) or bestAction.label or "Assistant shortcut",
        summary = "Runs the matching Assistant shortcut.",
    }
end

-- Frame-recovery intent. "I don't see my frames" and its many variants are a
-- problem report, not a concept question, so this must run before the generic
-- unit-frame help so the user gets an actionable rescue (offer to run the
-- "/msuf reset" position/visibility reset) instead of a description.
--
-- Two signal groups keep it precise: a symptom ("can't see", "gone",
-- "off-screen", "everything moved") combined with a frame/UI subject; plus a
-- few standalone SOS phrases that are unambiguous on their own. A confirm is
-- always required because the reset moves every frame.
local FRAME_RECOVERY_SYMPTOM_TERMS = {
    "dont see", "don't see", "do not see", "cant see", "can't see", "cannot see",
    "not see", "not showing", "not shown", "not visible", "no longer see",
    "cant find", "can't find", "cannot find", "not find", "where are my", "where is my",
    "disappeared", "disappear", "vanished", "vanish", "gone", "missing", "lost",
    "off screen", "offscreen", "off-screen", "out of screen", "outside the screen",
    "moved away", "moved off", "everything moved", "all messed up", "messed up",
    "broken layout", "layout broken", "cant reach", "can't reach",
    "nicht mehr", "nicht sichtbar", "verschwunden", "weg", "verloren",
    "finde nicht", "sehe nicht", "sehe keine", "sehe keinen", "sehe kein",
    "ausserhalb", "vom bildschirm", "verschoben", "kaputt",
}
local FRAME_RECOVERY_SUBJECT_TERMS = {
    "frame", "frames", "unitframe", "unitframes", "unit frame", "unit frames",
    "player frame", "target frame", "focus frame", "pet frame", "boss frame",
    "group frame", "group frames", "party frame", "raid frame",
    "health bar", "health bars", "hp bar", "power bar",
    "my ui", "the ui", "msuf", "everything", "anything", "all my frames",
    "the bars", "my bars", "gesundheitsleiste", "leiste", "leisten", "rahmen",
    "alles", "meine frames", "die frames", "oberflaeche",
}
-- Standalone recovery phrases: unambiguous rescue requests. Exact
-- "reset [all] frame positions" phrases are intentionally excluded because the
-- dedicated reset_all_unit_positions action already owns those explicit
-- commands. Broad collective wording such as "all my frames" instead owns the
-- full recovery action because it includes group frames and visibility, just
-- like /msuf reset.
local FRAME_RECOVERY_STANDALONE_TERMS = {
    "reset my frames", "reset all frames", "reset frames to screen", "reset to screen",
    "bring my frames back", "bring back my frames", "bring frames back",
    "get my frames back", "restore my frames", "recover my frames", "recover frames",
    "frames back to center", "frames to the middle", "frames to middle",
    "center my frames", "recenter frames",
    "i lost my frames", "i cant see my frames", "i can't see my frames",
    "help i cant see", "help i can't see", "nothing is showing", "nothing shows",
    "frames verschwunden", "frames weg", "rahmen weg",
    "frames zuruecksetzen", "frames zurucksetzen", "rahmen zuruecksetzen",
    "frames zentrieren", "frames zur mitte",
}
local FRAME_RECOVERY_POSITION_RESET_TERMS = {
    "reset", "restore", "recover", "recenter",
    "zuruecksetzen", "zurucksetzen", "wiederherstellen", "zentrieren",
}
local FRAME_RECOVERY_POSITION_TERMS = {
    "position", "positions", "placement", "layout", "anchor", "anchors",
    "positionen", "platzierung", "anker",
}
local FRAME_RECOVERY_ALL_FRAMES_TERMS = {
    "all my frames", "all of my frames", "all frames", "every frame",
    "every unit frame", "every unitframe", "all msuf frames",
    "all unit and group frames", "alle meine frames", "alle frames",
    "alle rahmen", "jeden rahmen",
}
-- Guard: these clearly ask about a single setting or a "how do I" concept and
-- should stay on their normal paths, not trigger a full reset offer.
local FRAME_RECOVERY_BLOCK_TERMS = {
    "how do i", "how can i", "how to", "wie kann ich", "wie mache ich",
    "what is", "what are", "explain", "was ist", "was sind",
    "size", "width", "height", "color", "colour", "font", "opacity", "texture",
}

local function ParseFrameRecovery(text)
    text = Normalize(text)
    if text == "" then return nil end
    local action = Registry and Registry:GetAction("recover_frames")
    if not action then return nil end

    local broadPositionRecovery = ContainsAny(text, FRAME_RECOVERY_POSITION_RESET_TERMS)
        and ContainsAny(text, FRAME_RECOVERY_POSITION_TERMS)
        and ContainsAny(text, FRAME_RECOVERY_ALL_FRAMES_TERMS)
        and not ContainsAny(text, FRAME_RECOVERY_BLOCK_TERMS)
    local standalone = broadPositionRecovery or ContainsAny(text, FRAME_RECOVERY_STANDALONE_TERMS)
    if not standalone then
        if ContainsAny(text, FRAME_RECOVERY_BLOCK_TERMS) then return nil end
        if not ContainsAny(text, FRAME_RECOVERY_SYMPTOM_TERMS) then return nil end
        if not ContainsAny(text, FRAME_RECOVERY_SUBJECT_TERMS) then return nil end
    end

    return {
        kind = "action",
        action = action,
        args = {},
        confirmRequired = true,
        label = "Reset frame positions & visibility",
        summary = "Offers to reset all MSUF frame positions and visibility to the on-screen defaults.",
        confirmText = "It looks like your MSUF frames may be off-screen or hidden. I can reset every unit-frame and group-frame position and visibility back to the on-screen defaults (near the middle of the screen). Do you want me to do that?",
    }
end

P.ParseFrameRecovery = ParseFrameRecovery
P.FRAME_RECOVERY_SYMPTOM_TERMS = FRAME_RECOVERY_SYMPTOM_TERMS
P.FRAME_RECOVERY_SUBJECT_TERMS = FRAME_RECOVERY_SUBJECT_TERMS
P.FRAME_RECOVERY_STANDALONE_TERMS = FRAME_RECOVERY_STANDALONE_TERMS

P.CopyTextParts = CopyTextParts
P.RemoveUnit = RemoveUnit
P.CopyTargetsForText = CopyTargetsForText
P.CopyGroupTargetsForText = CopyGroupTargetsForText
P.ParseGroupCopy = ParseGroupCopy
P.ParseUnsupportedMixedCopy = ParseUnsupportedMixedCopy
P.ParseCopy = ParseCopy
P.BuildContextReset = BuildContextReset
P.GROUP_STATUS_ICON_ALIASES = GROUP_STATUS_ICON_ALIASES
P.GroupStatusIconForText = GroupStatusIconForText
P.GROUP_STATUS_ICON_TERMS = GROUP_STATUS_ICON_TERMS
P.FirstGroupOrDefault = FirstGroupOrDefault
P.AliasValueForText = AliasValueForText
P.GROUP_SPELL_PLACED_ALIASES = GROUP_SPELL_PLACED_ALIASES
P.GROUP_SPELL_FRAME_ALIASES = GROUP_SPELL_FRAME_ALIASES
P.GROUP_SPELL_GROWTH_ALIASES = GROUP_SPELL_GROWTH_ALIASES
P.GROUP_SPELL_ANCHOR_ALIASES = GROUP_SPELL_ANCHOR_ALIASES
P.ParseGroupSpellIndicatorAction = ParseGroupSpellIndicatorAction
P.ParseGroupCornerIndicatorSetting = ParseGroupCornerIndicatorSetting
P.ParseGroupCornerIndicatorReset = ParseGroupCornerIndicatorReset
P.ParseGroupStatusIconReset = ParseGroupStatusIconReset
P.ParseGroupStatusPreview = ParseGroupStatusPreview
P.ParseGroupStatusIconDetail = ParseGroupStatusIconDetail
P.UNIT_STATUS_RESET_TERMS = UNIT_STATUS_RESET_TERMS
P.ParseUnitStatusIndicatorReset = ParseUnitStatusIndicatorReset
P.ParseUnitStatusPreview = ParseUnitStatusPreview
P.ParseUnitStatusIconStyle = ParseUnitStatusIconStyle
P.ParseUnitStatusIndicatorDetail = ParseUnitStatusIndicatorDetail
P.ParseUnitStatusIndicatorMove = ParseUnitStatusIndicatorMove
P.ParseCustomAnchorWorkflow = ParseCustomAnchorWorkflow
P.CleanCustomAnchorFrameName = CleanCustomAnchorFrameName
P.RawCustomAnchorFrameName = RawCustomAnchorFrameName
P.ParseCustomAnchorSet = ParseCustomAnchorSet
P.ParseCustomAnchorClear = ParseCustomAnchorClear
P.ParseReset = ParseReset
P.ParseOpen = ParseOpen
P.DashboardPanelForText = DashboardPanelForText
P.ParseDashboardPanelAction = ParseDashboardPanelAction
P.NAV_SECTION_TEXT_TARGETS = NAV_SECTION_TEXT_TARGETS
P.NavSectionForText = NavSectionForText
P.ParseNavRailAction = ParseNavRailAction
P.ParseMenuWindowAction = ParseMenuWindowAction
