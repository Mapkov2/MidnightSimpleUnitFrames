-- Assistant auto-coverage fallback registration.
--
-- Closes the raw-coverage gap mechanically: every safe scalar DB path that no
-- hand-written registry entry reaches gets a generated English setting with a
-- label and aliases derived from the key name, direct get/set into the DB, and
-- the broadest safe apply for its scope. Hand-written entries always win
-- (RegisterSetting dedupes by key; the covered-set check also honors
-- unit+attribute), so this layer only ever fills holes.
--
-- Generated entries are marked `generated = true` so the coverage audit,
-- knowledge dump, and future curation passes can tell them apart. They are the
-- floor, not the ceiling: /msufcoverage stubs <scope> still produces proper
-- stubs when a key deserves curated aliases and a precise apply.
--
-- Filled lazily on the first assistant parse (DB seeded, all domains
-- registered) and again on demand via /msufcoverage fill (e.g. after a profile
-- import materializes new keys). Re-running is idempotent.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Auto = A.AutoCoverage or {}
A.AutoCoverage = Auto

local UNIT_SCOPES = {
    player = true, target = true, targettarget = true, focustarget = true,
    focus = true, pet = true, boss = true,
}
local GROUP_SCOPES = { gf_party = "party", gf_raid = "raid", gf_mythicraid = "mythicraid" }
local FLAT_SCOPES = { general = true, bars = true, gameplay = true }

-- "Channel" keeps these distinct from color VALUE words ("set X color to red")
-- that the color parser owns.
local CHANNEL_WORDS = { R = "Red Channel", G = "Green Channel", B = "Blue Channel", A = "Alpha Channel" }

local function LabelFromKey(key)
    local label = key:gsub("(%l)(%u)", "%1 %2")
        -- Acronym boundary: "alphaBGOutOfCombat" -> "alpha BG Out Of Combat",
        -- not "alpha BGOut Of Combat".
        :gsub("(%u)(%u%l)", "%1 %2")
        :gsub("(%a)(%d)", "%1 %2"):gsub("_", " ")
    -- Trailing color channel letters make aliases ambiguous once text
    -- normalization drops single-character tokens; spell them out.
    label = label:gsub(" ([RGBA])$", function(c) return " " .. CHANNEL_WORDS[c] end)
    return (label:gsub("^%l", string.upper))
end

local function LabelFromPath(path)
    local labels = {}
    for segment in tostring(path or ""):gmatch("[^.]+") do
        labels[#labels + 1] = LabelFromKey(segment)
    end
    return table.concat(labels, " ")
end

local function ScopeLabel(scope)
    local RC = A.RegistryCore
    local labels = RC and RC.UNIT_LABELS or {}
    if GROUP_SCOPES[scope] then return labels[GROUP_SCOPES[scope]] or LabelFromKey(GROUP_SCOPES[scope]) end
    return labels[scope] or LabelFromKey(scope)
end

local function KeyHas(lkey, needle)
    return lkey:find(needle, 1, true) ~= nil
end

local function KeyHasAny(lkey, list)
    for i = 1, #list do
        if KeyHas(lkey, list[i]) then return true end
    end
    return false
end

local function KeyIsDetachedPower(lkey)
    return KeyHas(lkey, "detachedpower") or KeyHas(lkey, "powerbardetached")
end

local COLOR_KEY_TERMS = {
    "color", "colour", "tint",
}
local CASTBAR_KEY_TERMS = {
    "castbar", "focuskick", "kickready", "kicknotready",
}
local CLASSPOWER_KEY_TERMS = {
    "classpower", "combo", "runeshow", "altmana", "ebonmight", "maelstrom",
}
local AURA_KEY_TERMS = {
    "aura", "buff", "debuff", "pandemic",
}
local FONT_KEY_TERMS = {
    "font", "text", "name", "label",
}
local ALPHA_KEY_TERMS = {
    "alpha", "opacity", "fade", "transparency", "rangefade",
}
local BAR_KEY_TERMS = {
    "bar", "border", "outline", "texture", "gradient", "smooth", "absorb", "healprediction", "healabsorb",
}
local GROUP_GEOMETRY_KEY_TERMS = {
    "growth", "sort",
    "width", "height", "scale", "spacing", "padding", "offset", "layout",
    "columns", "rows", "perrow", "percolumn", "unitsper", "groupsper",
}
local GROUP_REBUILD_EXACT_KEYS = {
    enabled = true,
    showSolo = true,
    showParty = true,
    showRaid = true,
    showInRaid = true,
    showInParty = true,
    hideInClientScene = true,
    hideInHousing = true,
    hideInCombat = true,
    hideOutOfCombat = true,
    hideInInstance = true,
}
local GROUP_VISUAL_KEY_TERMS = {
    "raidmarker", "groupnumber", "roleicon", "leadericon", "assisticon",
    "readycheck", "summon", "resurrect", "pvpicon", "phaseicon",
    "statustext", "iconstyle", "customicon", "icon", "indicator",
    "cornerindicator", "spellindicator", "cienabled", "cislot", "cisize", "cialpha", "cicustom",
    "hlfocus", "hltarget", "highlight", "healthfade", "health", "power",
}
local GROUP_BORDER_KEY_TERMS = {
    "border", "outline", "aggro", "dispel", "purge", "stripe",
}
local MENU_ONLY_KEY_TERMS = {
    "tooltip", "locale", "menu", "navhover", "dropdownstyle", "blizzard",
}

local function CallApply(fn, reason)
    if type(fn) ~= "function" then return nil end
    return function() fn(reason) end
end

local function CurrentApplyService()
    return (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
end

local function CastbarUnitForKey(key)
    key = tostring(key or "")
    local castbars = A.CastbarsRegistry
    local tables = {
        castbars and castbars.CASTBAR_KEYS,
        castbars and castbars.CASTBAR_DETAIL_FIELDS,
        A.RegistryCore and A.RegistryCore.CASTBAR_KEYS,
        A.RegistryCore and A.RegistryCore.CASTBAR_DETAIL_FIELDS,
    }
    for i = 1, #tables do
        local byUnit = tables[i]
        if type(byUnit) == "table" then
            for unit, keys in pairs(byUnit) do
                if type(keys) == "table" then
                    for _, dbKey in pairs(keys) do
                        if dbKey == key then return unit end
                    end
                end
            end
        end
    end
    local lkey = key:lower()
    if lkey:find("playercast", 1, true) or lkey:find("castbarplayer", 1, true) then return "player" end
    if lkey:find("targetcast", 1, true) or lkey:find("castbartarget", 1, true) then return "target" end
    if lkey:find("focuscast", 1, true) or lkey:find("castbarfocus", 1, true) or lkey:find("focuskick", 1, true) then return "focus" end
    if lkey:find("bosscast", 1, true) or lkey:find("castbarboss", 1, true) then return "boss" end
    return nil
end

local function GeneralFlagApply(RC, reason, opts)
    return function()
        RC.ApplyGeneral(reason, opts)
    end
end

local function GeneralScopeApply(RC, key)
    local reason = "MSUF_ASSISTANT_AUTO_" .. key
    local keyText = tostring(key or "")
    local lkey = keyText:lower()
    local isColor = KeyHasAny(lkey, COLOR_KEY_TERMS) or keyText:match("[RGBA]$") ~= nil
    local isCastbar = KeyHasAny(lkey, CASTBAR_KEY_TERMS)
    local isClassPower = KeyHasAny(lkey, CLASSPOWER_KEY_TERMS)
    local isAura = KeyHasAny(lkey, AURA_KEY_TERMS)
    local isPortrait = KeyHas(lkey, "portrait")

    local castbarUnit = isCastbar and CastbarUnitForKey(keyText) or nil

    if isCastbar and isColor then
        if type(RC.ApplyCastbarColors) == "function" then return function() RC.ApplyCastbarColors(reason, castbarUnit) end end
        if type(RC.ApplyCastbar) == "function" then return function() RC.ApplyCastbar(reason, castbarUnit) end end
        return GeneralFlagApply(RC, reason, { preview = true, applyAll = false, castbar = true, castbarTextures = true })
    end
    if isClassPower and isColor then return CallApply(RC.ApplyClassPowerColors, reason) or CallApply(RC.ApplyClassPower, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, classpower = true }) end
    if isAura and isColor then return CallApply(RC.ApplyAuraColors, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, colors = true }) end
    if isPortrait and isColor then return CallApply(RC.ApplyPortraitColors, reason) or CallApply(RC.ApplyColors, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, colors = true }) end
    if isColor then return CallApply(RC.ApplyColors, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, colors = true }) end
    if isCastbar then
        if type(RC.ApplyCastbar) == "function" then return function() RC.ApplyCastbar(reason, castbarUnit) end end
        return GeneralFlagApply(RC, reason, { preview = true, applyAll = false, castbar = true, castbarTextures = true })
    end
    if isClassPower then return CallApply(RC.ApplyClassPower, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, classpower = true }) end
    if isAura and type(RC.ApplyAura) == "function" then
        return function() RC.ApplyAura("shared", reason) end
    end
    if isPortrait then return CallApply(RC.ApplyPortraitColors, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, visual = true }) end
    if KeyHasAny(lkey, FONT_KEY_TERMS) then return CallApply(RC.ApplyFonts, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, fonts = true }) end
    if KeyHasAny(lkey, ALPHA_KEY_TERMS) then
        return GeneralFlagApply(RC, reason, { preview = true, applyAll = false, alpha = true, bars = true })
    end
    if KeyHas(lkey, "power") then
        return GeneralFlagApply(RC, reason, { preview = true, applyAll = false, power = true, bars = true })
    end
    if KeyHasAny(lkey, BAR_KEY_TERMS) then return CallApply(RC.ApplyBars, reason) or GeneralFlagApply(RC, reason, { preview = true, applyAll = false, bars = true }) end
    if KeyHasAny(lkey, MENU_ONLY_KEY_TERMS) then
        return GeneralFlagApply(RC, reason, { preview = false, applyAll = false, notify = false })
    end
    return GeneralFlagApply(RC, reason, { preview = true, applyAll = false, visual = true })
end

local function GroupModeForKey(key)
    local keyText = tostring(key or "")
    local lkey = keyText:lower()
    if KeyHasAny(lkey, AURA_KEY_TERMS) then return "auras" end
    if KeyHasAny(lkey, FONT_KEY_TERMS) then return "fonts" end
    if KeyHasAny(lkey, GROUP_BORDER_KEY_TERMS) then return "border" end
    if KeyHasAny(lkey, COLOR_KEY_TERMS) or keyText:match("[RGBA]$") ~= nil then return "colors" end
    if KeyHasAny(lkey, GROUP_VISUAL_KEY_TERMS) then return "visual" end
    if GROUP_REBUILD_EXACT_KEYS[keyText] then return "rebuild" end
    if KeyHasAny(lkey, GROUP_GEOMETRY_KEY_TERMS) then return "geometry" end
    if KeyHasAny(lkey, BAR_KEY_TERMS) or KeyHasAny(lkey, ALPHA_KEY_TERMS) then return "visual" end
    return "visual"
end

local function UnitApplyOptsForKey(key)
    local keyText = tostring(key or "")
    local lkey = keyText:lower()
    local opts = { preview = true }
    if KeyHasAny(lkey, FONT_KEY_TERMS) then opts.text = true end
    if KeyIsDetachedPower(lkey) then
        opts.power = true
        opts.detachedPowerBar = true
    elseif KeyHas(lkey, "power") then
        opts.power = true
    end
    if KeyHasAny(lkey, ALPHA_KEY_TERMS) then opts.alpha = true end
    if KeyHasAny(lkey, CASTBAR_KEY_TERMS) then opts.castbar = true end
    if KeyHasAny(lkey, AURA_KEY_TERMS) then opts.auras = true end
    return opts
end

local function DirtyMaskForGroupMode(gf, mode)
    if type(gf) ~= "table" then return nil end
    if mode == "fonts" or mode == "font" then return gf.DIRTY_FONT end
    if mode == "colors" or mode == "color" then return gf.DIRTY_COLOR end
    if mode == "border" or mode == "borders" then return gf.DIRTY_BORDER end
    if mode == "auras" then return gf.DIRTY_AURAS end
    if mode == "geometry" then
        local dirty = tonumber(gf.DIRTY_GEOMETRY) or 0
        local layout = tonumber(gf.DIRTY_LAYOUT) or 0
        dirty = dirty + layout
        return dirty ~= 0 and dirty or gf.DIRTY_VISUAL
    end
    return gf.DIRTY_VISUAL
end

local function ApplyLegacyGroupScope(groupScope, mode, dirty)
    if type(groupScope) ~= "string" or groupScope == "" then return false end
    local did = false
    if mode == "rebuild" then
        if type(_G.MSUF_GF_RefreshGeometry) == "function" then _G.MSUF_GF_RefreshGeometry(groupScope); did = true end
        if type(_G.MSUF_GF_RefreshUnitBindings) == "function" then _G.MSUF_GF_RefreshUnitBindings(groupScope); did = true end
        if type(_G.MSUF_GF_RefreshVisuals) == "function" then _G.MSUF_GF_RefreshVisuals(groupScope, dirty); did = true end
        return did
    end
    if mode == "geometry" then
        if type(_G.MSUF_GF_RefreshGeometry) == "function" then _G.MSUF_GF_RefreshGeometry(groupScope); did = true end
        if type(_G.MSUF_GF_RefreshVisuals) == "function" then _G.MSUF_GF_RefreshVisuals(groupScope, dirty); did = true end
        return did
    end
    if type(_G.MSUF_GF_RefreshVisuals) == "function" then
        _G.MSUF_GF_RefreshVisuals(groupScope, dirty)
        return true
    end
    return false
end

local function FallbackFlatApplyOptions(scope, key)
    local opts = { preview = true, applyAll = false }
    local keyText = tostring(key or "")
    local lkey = keyText:lower()
    if KeyIsDetachedPower(lkey) then
        opts.power = true
        opts.detachedPowerBar = true
        opts.classpower = true
    elseif scope == "bars" or KeyHasAny(lkey, BAR_KEY_TERMS) then
        opts.bars = true
    elseif KeyHasAny(lkey, COLOR_KEY_TERMS) or keyText:match("[RGBA]$") ~= nil then
        opts.colors = true
    elseif KeyHasAny(lkey, CASTBAR_KEY_TERMS) then
        opts.castbar = true
        opts.castbarTextures = true
    elseif KeyHasAny(lkey, CLASSPOWER_KEY_TERMS) then
        opts.classpower = true
    elseif KeyHasAny(lkey, FONT_KEY_TERMS) then
        opts.fonts = true
    elseif KeyHasAny(lkey, ALPHA_KEY_TERMS) then
        opts.alpha = true
    elseif KeyHas(lkey, "power") then
        opts.power = true
        opts.bars = true
    elseif KeyHasAny(lkey, MENU_ONLY_KEY_TERMS) then
        opts.preview = false
        opts.notify = false
    end
    return opts
end

local function FallbackScopeApply(scope, key)
    if UNIT_SCOPES[scope] then
        local reason = "MSUF_ASSISTANT_AUTO_" .. tostring(key or scope)
        return function()
            if M and type(M.RequestUnitApply) == "function" then
                return M.RequestUnitApply(scope, reason, UnitApplyOptsForKey(key))
            end
            local apply = (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
            if apply and type(apply.RequestUnit) == "function" then
                return apply.RequestUnit(scope, reason, UnitApplyOptsForKey(key))
            end
            if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
                return _G.MSUF_UFCore_NotifyConfigChanged(scope, true, true, reason)
            end
        end
    end
    if GROUP_SCOPES[scope] then
        local groupScope = GROUP_SCOPES[scope]
        local mode = GroupModeForKey(key)
        return function()
            local apply = CurrentApplyService()
            local gf = MSUF and MSUF.GF
            local dirty = DirtyMaskForGroupMode(gf, mode)
            local reason = "MSUF_ASSISTANT_AUTO_" .. tostring(key or groupScope)
            if mode ~= "rebuild" and mode ~= "reset" and dirty and apply and type(apply.RequestGroupDirtyMask) == "function" then
                return apply.RequestGroupDirtyMask(groupScope, dirty, reason)
            end
            if apply and type(apply.RequestGroup) == "function" then
                return apply.RequestGroup(groupScope, mode, reason)
            end
            if dirty and apply and type(apply.RequestGroupDirtyMask) == "function" then
                return apply.RequestGroupDirtyMask(groupScope, dirty, reason)
            end
            local GP = M and M.GroupPage
            if GP and type(GP.QueueGF) == "function" then
                return GP.QueueGF(groupScope, mode)
            end
            if ApplyLegacyGroupScope(groupScope, mode, dirty) then return true end
            if mode == "rebuild" and type(_G.MSUF_GF_RefreshAll) == "function" then return _G.MSUF_GF_RefreshAll() end
        end
    end
    if FLAT_SCOPES[scope] then
        local reason = "MSUF_ASSISTANT_AUTO_" .. tostring(key or scope)
        local opts = FallbackFlatApplyOptions(scope, key)
        return function()
            local apply = CurrentApplyService()
            if M and type(M.RequestGeneralApply) == "function" then
                return M.RequestGeneralApply(reason, opts)
            end
            if apply and type(apply.RequestGeneral) == "function" then
                return apply.RequestGeneral(reason, opts)
            end
            if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
                return _G.MSUF_UFCore_NotifyConfigChanged(nil, true, true, reason)
            end
        end
    end
    return function()
        local reason = "MSUF_ASSISTANT_AUTO_" .. tostring(key or scope or "fallback")
        if M and type(M.RequestGeneralApply) == "function" then
            return M.RequestGeneralApply(reason, { preview = true, applyAll = true, frames = true })
        end
        local apply = CurrentApplyService()
        if apply and type(apply.RequestGeneral) == "function" then
            return apply.RequestGeneral(reason, { preview = true, applyAll = true, frames = true })
        end
        if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
            return _G.MSUF_UFCore_NotifyConfigChanged(nil, true, true, reason)
        end
    end
end

local function ScopeApply(scope, key)
    local RC = A.RegistryCore
    if not RC then return FallbackScopeApply(scope, key) end
    if UNIT_SCOPES[scope] and type(RC.ApplyUnit) == "function" then
        local reason = "MSUF_ASSISTANT_AUTO_" .. key
        return function() RC.ApplyUnit(scope, reason, UnitApplyOptsForKey(key)) end
    end
    if GROUP_SCOPES[scope] and type(RC.ApplyGroup) == "function" then
        local groupScope = GROUP_SCOPES[scope]
        local mode = GroupModeForKey(key)
        return function() RC.ApplyGroup(groupScope, mode) end
    end
    if scope == "general" and type(RC.ApplyGeneral) == "function" then
        return GeneralScopeApply(RC, key)
    end
    local flat = {
        bars = RC.ApplyBars,
        gameplay = RC.ApplyGameplay,
    }
    local fn = flat[scope]
    if type(fn) == "function" then
        local reason = "MSUF_ASSISTANT_AUTO_" .. key
        return function() fn(reason) end
    end
    return FallbackScopeApply(scope, key)
end

local function ScopeTable(scope, create)
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    local tbl = db[scope]
    if type(tbl) ~= "table" and create then
        tbl = {}
        db[scope] = tbl
    end
    return type(tbl) == "table" and tbl or nil
end

local MAX_NESTED_DEPTH = 8

local function PathSegments(path)
    local out = {}
    for segment in tostring(path or ""):gmatch("[^.]+") do
        if segment == "" or segment:sub(1, 1) == "_" or segment:match("^%d+$") then return nil end
        out[#out + 1] = segment
        if #out > MAX_NESTED_DEPTH then return nil end
    end
    return #out > 0 and out or nil
end

local function PathValue(root, path)
    local segments = type(path) == "table" and path or PathSegments(path)
    if type(root) ~= "table" or not segments then return nil, false end
    local node = root
    for i = 1, #segments - 1 do
        node = node[segments[i]]
        if type(node) ~= "table" then return nil, false end
    end
    local value = node[segments[#segments]]
    return value, value ~= nil
end

local function WritePath(root, path, value, create)
    local segments = type(path) == "table" and path or PathSegments(path)
    if type(root) ~= "table" or not segments then return false end
    local node = root
    for i = 1, #segments - 1 do
        local child = node[segments[i]]
        if type(child) ~= "table" then
            if not create or child ~= nil then return false end
            child = {}
            node[segments[i]] = child
        end
        node = child
    end
    node[segments[#segments]] = value
    return true
end

local function IsSafePath(Audit, scope, path)
    local segments = PathSegments(path)
    if not segments then return false end
    if Audit and type(Audit.IsIgnored) == "function" then
        if Audit.IsIgnored(scope, segments[1]) or Audit.IsIgnored(scope, path) then return false end
    end
    return true
end

local SortedKeys

local function WalkScalarPaths(root, callback)
    if type(root) ~= "table" or type(callback) ~= "function" then return end
    local active = {}
    local function walk(node, prefix, depth)
        if type(node) ~= "table" or active[node] or depth > MAX_NESTED_DEPTH then return end
        active[node] = true
        local keys = SortedKeys(node)
        for i = 1, #keys do
            local key = keys[i]
            if type(key) == "string" and key ~= "" and key:sub(1, 1) ~= "_" and not key:match("^%d+$") then
                local path = prefix and (prefix .. "." .. key) or key
                local value = node[key]
                local valueType = type(value)
                if valueType == "table" then
                    walk(value, path, depth + 1)
                elseif valueType == "boolean" or valueType == "number" or valueType == "string" then
                    callback(path, value)
                end
            end
        end
        active[node] = nil
    end
    walk(root, nil, 1)
end

local function ManifestDefaults()
    local manifest = A.AutoCoverageManifest
    if type(manifest) ~= "table" then return nil end
    if type(manifest.defaults) == "table" then return manifest.defaults end
    return manifest
end

-- Word-level synonyms so generated settings answer to human phrasing, not just
-- the camelCase-derived label ("hp bg alpha" -> "health background opacity").
-- Keys are single lowercase label words; each maps to alternative words.
-- English only. Kept small on purpose: every synonym multiplies alias variants.
local WORD_SYNONYMS = {
    alpha = { "opacity", "transparency" },
    bg = { "background" },
    background = { "bg" },
    tex = { "texture" },
    hp = { "health", "health bar" },
    pos = { "position" },
    dist = { "distance" },
    sep = { "separator" },
    icon = { "symbol" },
    -- no "colour": text normalization canonicalizes it to "color" anyway, so
    -- the variant would only duplicate index entries.
}
local MAX_GENERATED_ALIASES = 12

local function AddAliasVariants(aliases, seen, base)
    local function add(text)
        if #aliases >= MAX_GENERATED_ALIASES then return end
        if text ~= "" and not seen[text] then
            seen[text] = true
            aliases[#aliases + 1] = text
        end
    end
    add(base)
    -- One-word substitutions: replace each synonym-bearing word once so variant
    -- count stays linear, not combinatorial.
    for word in base:gmatch("%S+") do
        local subs = WORD_SYNONYMS[word]
        if subs then
            for i = 1, #subs do
                add((base:gsub("%f[%w]" .. word .. "%f[%W]", subs[i], 1)))
            end
        end
    end
end

-- Legacy mirror keys ("portraitBgColorR" alongside "portraitBackgroundColorR")
-- collapse into one generated setting; set() keeps every mirror in sync since
-- we cannot know statically which spelling the runtime reads.
local function WriteMirrors(spec, tbl, v)
    local mirrors = spec and spec.mirrorKeys
    if mirrors and tbl then
        for i = 1, #mirrors do WritePath(tbl, mirrors[i], v, true) end
    end
end

local function BuildSpec(scope, key, value, fromManifest)
    local valueType = type(value)
    local label = LabelFromPath(key)
    local scopeLabel = ScopeLabel(scope)
    local fullLabel = scopeLabel .. " " .. label
    local aliasBase = label:lower()
    local aliases, seen = {}, {}
    if FLAT_SCOPES[scope] then
        -- Flat scopes have no unit word in the sentence to disambiguate them;
        -- lead with the scope-prefixed phrase so "gameplay font size" and
        -- "general font size" stay distinct for prompt generation.
        AddAliasVariants(aliases, seen, fullLabel:lower())
        AddAliasVariants(aliases, seen, aliasBase)
    else
        AddAliasVariants(aliases, seen, aliasBase)
        AddAliasVariants(aliases, seen, fullLabel:lower())
    end
    local unit = UNIT_SCOPES[scope] and scope or GROUP_SCOPES[scope] or nil
    local spec = {
        key = scope .. "." .. key,
        label = fullLabel,
        category = scopeLabel .. " / Auto (generated)",
        unit = unit,
        frameType = GROUP_SCOPES[scope] and "group" or (UNIT_SCOPES[scope] and "unitframe" or scope),
        attribute = key,
        dbPath = key,
        generatedNested = key:find(".", 1, true) ~= nil,
        aliases = aliases,
        generated = true,
        manifestDefault = fromManifest and value or nil,
        combatSafe = false,
        apply = ScopeApply(scope, key),
        description = fromManifest
            and ("Auto-generated from the default manifest; controls '" .. key .. "' directly.")
            or ("Auto-generated from saved settings; controls '" .. key .. "' directly."),
    }
    if valueType == "boolean" then
        spec.type = "boolean"
        spec.get = function()
            local tbl = ScopeTable(scope)
            local v, exists = PathValue(tbl, key)
            if not exists then return value and true or false end
            return v and true or false
        end
        spec.set = function(v)
            local tbl = ScopeTable(scope, true)
            if tbl then
                WritePath(tbl, key, v and true or false, true)
                WriteMirrors(spec, tbl, v and true or false)
            end
        end
    elseif valueType == "number" then
        spec.type = "number"
        if value >= 0 and value <= 1 then
            spec.min, spec.max, spec.step, spec.percent = 0, 1, 0.05, true
        else
            spec.step = 1
        end
        spec.get = function()
            local tbl = ScopeTable(scope)
            local raw = PathValue(tbl, key)
            local v = tonumber(raw)
            if v == nil then return value end
            return v
        end
        spec.set = function(v)
            v = tonumber(v)
            if v == nil then return end
            if spec.min and v < spec.min then v = spec.min end
            if spec.max and v > spec.max then v = spec.max end
            local tbl = ScopeTable(scope, true)
            if tbl then
                WritePath(tbl, key, v, true)
                WriteMirrors(spec, tbl, v)
            end
        end
    else
        spec.type = "string"
        spec.get = function()
            local tbl = ScopeTable(scope)
            local v, exists = PathValue(tbl, key)
            if not exists then return value end
            return tostring(v)
        end
        spec.set = function(v)
            local tbl = ScopeTable(scope, true)
            if tbl then
                WritePath(tbl, key, tostring(v), true)
                WriteMirrors(spec, tbl, tostring(v))
            end
        end
    end
    return spec
end

SortedKeys = function(map)
    local out = {}
    if type(map) ~= "table" then return out end
    for key in pairs(map) do
        if type(key) == "string" then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

local function LuaString(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\"):gsub("\r", "\\r"):gsub("\n", "\\n"):gsub('"', '\\"')
    return '"' .. value .. '"'
end

local function LuaKey(key)
    key = tostring(key or "")
    if key:match("^[%a_][%w_]*$") then return key end
    return "[" .. LuaString(key) .. "]"
end

local function LuaValue(value)
    local valueType = type(value)
    if valueType == "boolean" then return value and "true" or "false" end
    if valueType == "number" then return tostring(value) end
    return LuaString(value)
end

local function AllManifestScopes()
    local scopes = {}
    for scope in pairs(UNIT_SCOPES) do scopes[#scopes + 1] = scope end
    for scope in pairs(GROUP_SCOPES) do scopes[#scopes + 1] = scope end
    for scope in pairs(FLAT_SCOPES) do scopes[#scopes + 1] = scope end
    table.sort(scopes)
    return scopes
end

function Auto.BuildManifestText()
    local Audit = A.CoverageAudit
    local lines = {
        "-- Paste into MSUF_AssistantRegistry_AutoCoverage_Manifest.lua.",
        "-- Source: freshly seeded profile DB safe scalar paths.",
        "Manifest.defaults = {",
    }
    local scopes = AllManifestScopes()
    local total = 0
    for i = 1, #scopes do
        local scope = scopes[i]
        local tbl = ScopeTable(scope)
        local wroteScope = false
        WalkScalarPaths(tbl, function(key, value)
            if IsSafePath(Audit, scope, key) then
                if not wroteScope then
                    lines[#lines + 1] = "    " .. LuaKey(scope) .. " = {"
                    wroteScope = true
                end
                -- Dotted keys keep the export compact and remain backwards
                -- compatible with the existing flat manifest format.
                lines[#lines + 1] = "        " .. LuaKey(key) .. " = " .. LuaValue(value) .. ","
                total = total + 1
            end
        end)
        if wroteScope then lines[#lines + 1] = "    }," end
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("-- safe scalar paths: %d"):format(total)
    return table.concat(lines, "\n"), total
end

function Auto.StoreManifestExport(text, total)
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then return end
    gdb.assistantAutoCoverageManifest = {
        time = date("%Y-%m-%d %H:%M:%S"),
        total = tonumber(total) or 0,
        text = tostring(text or ""),
    }
end

--- Registers generated settings for every uncovered safe scalar DB path.
--- Returns the number of settings added (0 when everything is covered or
--- prerequisites are missing). Safe to call repeatedly.
function Auto.Fill()
    local startedMs = _G.debugprofilestop and _G.debugprofilestop() or nil
    local Registry = A.Registry
    if not (Registry and type(Registry.RegisterSetting) == "function") then return 0 end
    local Audit = A.CoverageAudit
    if not (Audit and type(Audit.BuildCoveredSets) == "function") then return 0 end
    local covered = Audit.BuildCoveredSets()
    local added = 0
    local nestedAdded = 0
    local IsCoveredKey = Audit.IsCoveredKey or function(set, k) return set[k] end
    local NormalizeKey = Audit.NormalizeCoverageKey or function(k) return k end
    -- normKey -> generated spec, per scope: legacy mirror spellings of the
    -- same field collapse into one setting instead of colliding as aliases.
    local generatedByNorm = {}
    local function RegisterGenerated(scope, key, value, coveredSet, fromManifest)
        local valueType = type(value)
        if type(key) == "string"
            and IsSafePath(Audit, scope, key)
            and not IsCoveredKey(coveredSet, key)
            and (valueType == "boolean" or valueType == "number" or valueType == "string")
        then
            local fullKey = scope .. "." .. key
            local existing = type(Registry.GetSetting) == "function" and Registry:GetSetting(fullKey) or nil
            if existing then
                coveredSet[key] = existing
                return
            end
            local normMap = generatedByNorm[scope]
            if not normMap then
                normMap = {}
                generatedByNorm[scope] = normMap
            end
            local norm = NormalizeKey(key)
            local twin = normMap[norm]
            if twin then
                twin.mirrorKeys = twin.mirrorKeys or {}
                twin.mirrorKeys[#twin.mirrorKeys + 1] = key
                coveredSet[key] = twin
                return
            end
            local registered = Registry:RegisterSetting(BuildSpec(scope, key, value, fromManifest))
            if registered then
                coveredSet[key] = registered
                normMap[norm] = registered
                added = added + 1
                if registered.generatedNested then nestedAdded = nestedAdded + 1 end
            end
        end
    end

    local function FillScope(scope)
        local tbl = ScopeTable(scope)
        if not tbl then return end
        local coveredSet = covered[scope] or {}
        covered[scope] = coveredSet
        WalkScalarPaths(tbl, function(key, value)
            RegisterGenerated(scope, key, value, coveredSet, false)
        end)
    end

    local function FillManifestScope(scope)
        local manifest = ManifestDefaults()
        local manifestScope = type(manifest) == "table" and manifest[scope] or nil
        if type(manifestScope) ~= "table" then return end
        local live = ScopeTable(scope)
        local coveredSet = covered[scope] or {}
        covered[scope] = coveredSet
        WalkScalarPaths(manifestScope, function(key, value)
            local _, exists = PathValue(live, key)
            if not exists then
                RegisterGenerated(scope, key, value, coveredSet, true)
            end
        end)
    end
    for scope in pairs(UNIT_SCOPES) do FillScope(scope) end
    for scope in pairs(GROUP_SCOPES) do FillScope(scope) end
    for scope in pairs(FLAT_SCOPES) do FillScope(scope) end
    for scope in pairs(UNIT_SCOPES) do FillManifestScope(scope) end
    for scope in pairs(GROUP_SCOPES) do FillManifestScope(scope) end
    for scope in pairs(FLAT_SCOPES) do FillManifestScope(scope) end
    Auto.lastFillCount = added
    Auto.lastNestedFillCount = nestedAdded
    Auto._fillComplete = true
    if type(A.RecordSlowPerfSample) == "function" then
        A.RecordSlowPerfSample("assistant.autocoverage.fill", startedMs, tostring(added), 25)
    end
    return added
end

--- Avoid building generated aliases for players who never use the assistant.
--- Failed early attempts are not latched, so a caller can retry after the
--- registry/audit modules become available.
function Auto.EnsureFilled()
    if Auto._fillComplete == true then return 0 end
    return Auto.Fill()
end
