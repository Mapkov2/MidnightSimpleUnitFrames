local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- GroupFrames assistant action domain.
-- Depends on MSUF_AssistantRegistry_GroupFrames.lua for status-icon helpers.
local ctx = A.GroupFramesRegistry and A.GroupFramesRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
M = ctx.M or M
MSUF = ctx.MSUF or MSUF
local UNIT_LABELS = ctx.UNIT_LABELS or {}
local ResolveGroupStatusIcon = ctx.ResolveGroupStatusIcon
local ResetGroupStatusIcon = ctx.ResetGroupStatusIcon
local GROUP_STATUS_ICON_SPECS = ctx.GROUP_STATUS_ICON_SPECS or {}

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(ResolveGroupStatusIcon) ~= "function" or type(ResetGroupStatusIcon) ~= "function" then return end

local function GroupLabel(scope)
    if A and type(A.DisplayGroupLabel) == "function" then return A.DisplayGroupLabel(scope) end
    local label = UNIT_LABELS[scope]
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    if scope == "mythicraid" then return "Mythic Raid" end
    if scope == "raid" then return "Raid" end
    return "Party"
end

Registry:RegisterAction({
    key = "reset_group_status_icon",
    label = "Reset Group Status Icon",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope = args and args.scope
        if scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        local spec = ResolveGroupStatusIcon(args and args.icon)
        if not spec then return false, "Which group status icon do you want me to reset?" end
        ResetGroupStatusIcon(scope, spec)
        return true, "Done. Reset " .. GroupLabel(scope) .. " " .. tostring(spec.label) .. " placement and icon pack."
    end,
})

Registry:RegisterAction({
    key = "reset_group_status_icons",
    label = "Reset Group Status Icons",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope = args and args.scope
        if scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        for i = 1, #GROUP_STATUS_ICON_SPECS do ResetGroupStatusIcon(scope, GROUP_STATUS_ICON_SPECS[i]) end
        return true, "Done. Reset " .. GroupLabel(scope) .. " status icon placement and icon packs."
    end,
})

Registry:RegisterAction({
    key = "preview_group_status_icon",
    label = "Preview Group Status Icon",
    type = "preview",
    combatSafe = true,
    aliases = {
        "preview group status icon", "preview group status indicator",
        "preview group indicator", "preview group indicators", "preview group status and indicators",
        "group status icon test mode", "group status indicator test mode",
        "group indicator test mode", "group indicators test mode", "group status and indicators test mode",
        "test group status icons", "test group status indicators", "test group indicators", "test group status and indicators",
        "show all group status icons", "show all group status indicators", "show all group indicators", "show all group status and indicators",
    },
    run = function(args)
        local mode = args and args.mode == "all" and "all" or "current"
        local spec = ResolveGroupStatusIcon(args and (args.icon or args.text))
        local gf = MSUF and MSUF.GF
        if gf and type(gf.SetPreviewFocus) == "function" then gf.SetPreviewFocus("sicons") end
        if gf and type(gf.SetStatusPreviewMode) == "function" then gf.SetStatusPreviewMode(mode) end
        if mode == "current" and spec and gf and type(gf._PreviewSelectStatusIcon) == "function" then gf._PreviewSelectStatusIcon(spec.value) end
        if mode == "all" then return true, "Done. Showing all group status icons in the preview." end
        return true, "Done. Previewing " .. tostring(spec and spec.label or "the current group status icon") .. "."
    end,
})

local GROUP_COPY_SCOPE_LABELS = {
    { key = "general", label = "Basics" },
    { key = "health", label = "Health & Bars" },
    { key = "text", label = "Text & Name" },
    { key = "font", label = "Font Override" },
    { key = "border", label = "Background & Opacity" },
    { key = "range", label = "Range Fade" },
    { key = "indicators", label = "Status & Indicators" },
    { key = "auras", label = "Auras" },
    { key = "highlight", label = "Highlight & Aggro" },
    { key = "dstripe", label = "Debuff Stripe" },
    { key = "features", label = "Corner/Spell" },
}

local function GroupCopyScopeSummary(scopes)
    if type(scopes) ~= "table" then return "" end
    local selected, total = {}, 0
    for i = 1, #GROUP_COPY_SCOPE_LABELS do
        local row = GROUP_COPY_SCOPE_LABELS[i]
        total = total + 1
        if scopes[row.key] == true then selected[#selected + 1] = row.label end
    end
    if #selected == 0 then return " Which group-frame parts do you want me to copy?" end
    if #selected == total then return " Categories: all group-frame parts." end
    return " Categories: " .. table.concat(selected, ", ") .. "."
end


local function WordList(words)
    local out = {}
    for word in tostring(words or ""):gmatch("%S+") do out[#out + 1] = word end
    return out
end

local function WordSet(words)
    local out = {}
    for _, word in ipairs(WordList(words)) do out[word] = true end
    return out
end

local GROUP_COPY_EXCLUDE = WordSet("offsetX offsetY point positionMode _hlMigrated")
local GROUP_COPY_CATEGORIES = {
    { key = "general", keys = WordList("enabled blizzardFallbackMode showPlayer showSolo clickCastEnabled width height spacing growth groupFilter sortMode sortByRole roleOrder playerFirstInRole unitsPerColumn maxColumns preserveRaidGroups reverseFill smoothFill hideInClientScene hideInHousing hideOfflineEnabled hideOfflineInCombat hideOfflineDelay frameScaleMode frameScaleManual scaleAt10 scaleAt20 scaleAt25 scaleOver25") },
    { key = "health", keys = WordList("gfBarMode healthColorMode healthCustomR healthCustomG healthCustomB gfDarkR gfDarkG gfDarkB gfUnifiedR gfUnifiedG gfUnifiedB barTexture barBgTexture powerBarEnabled powerHeight showPower showPowerText powerTextLeft powerTextCenter powerTextRight powerTextDelimiter powerFontSize powerOffsetX powerOffsetY powerTextLayer powerSmoothFill powerShowTank powerShowHealer powerShowDamager dispelOverlayEnabled dispelOverlayStyle dispelOverlayOnHealth dispelOverlayAlpha dispelOverlayTrigger healthFadeEnabled healthFadeThreshold healthFadeAlpha deadBgEnabled deadBgOffline deadBgR deadBgG deadBgB deadBgA") },
    { key = "text", keys = WordList("showName hideNameOnDeadOffline nameFontSize nameAnchor nameOffsetX nameOffsetY nameTextLayer nameColorMode nameColorR nameColorG nameColorB nameShortenEnabled nameClipSide nameMaxChars nameNoEllipsis showHPText hpFontSize textLeft textCenter textRight textDelimiter hpTextReverse healthTextDecimals hpOffsetX hpOffsetY textLayer") },
    { key = "font", keys = WordList("fontOverride fontOutline useGlobalFontColor fontR fontG fontB") },
    { key = "border", keys = WordList("bgR bgG bgB hpBarAlpha hpBgAlpha alphaExcludeTextPortrait") },
    { key = "range", keys = WordList("rangeFadeEnabled rangeFadeAlpha rangeFadeLayerMode offlineAlpha") },
    { key = "indicators", keys = WordList("pvpIcon statusText statusGhostText statusAFKText showGroupNumber groupNumberSize groupNumberAnchor groupNumberX groupNumberY groupBorderEnabled groupBorderSize groupBorderPadding groupBorderR groupBorderG groupBorderB groupBorderA iconStyle useMidnightIcons roleIconStyle leaderIconStyle assistIconStyle"), prefix = WordList("si_ statusIcon indicator") },
    { key = "auras", tables = WordList("auras") },
    { key = "highlight", keys = WordList("targetIndicator targetR targetG targetB"), prefix = WordList("hl dispel") },
    { key = "dstripe", prefix = WordList("debuffStripe") },
    { key = "features", keys = WordList("ciEnabled ciAlpha"), tables = WordList("spellIndicators"), prefix = WordList("ci") },
}

local function NewGroupCopyScopesFallback()
    local scopes = {}
    for i = 1, #GROUP_COPY_CATEGORIES do scopes[GROUP_COPY_CATEGORIES[i].key] = true end
    return scopes
end

local function DeepCopyLocal(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        out[DeepCopyLocal(key, seen)] = DeepCopyLocal(item, seen)
    end
    return out
end

local function DeepCopyGroupValue(value)
    if type(value) ~= "table" then return value end
    if type(_G.MSUF_DeepCopy) == "function" then return _G.MSUF_DeepCopy(value) end
    if M and type(M.DeepCopy) == "function" then return M.DeepCopy(value) end
    return DeepCopyLocal(value)
end

local function GroupConfig(kind)
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    return db["gf_" .. tostring(kind)]
end

local function RefreshGroupCopyRuntime()
    local gf = MSUF and (MSUF.GF or MSUF.GroupFrames)
    if gf and type(gf.RefreshAll) == "function" then gf.RefreshAll(); return end
    if gf and type(gf.RebuildAll) == "function" then gf.RebuildAll(); return end
    if gf and type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout() end
end

local function CopyGroupSettingsFallback(srcKind, dstKind, scopes)
    local srcConf = GroupConfig(srcKind)
    local dstConf = GroupConfig(dstKind)
    if not (srcConf and dstConf and srcKind and dstKind) or srcKind == dstKind then return false end
    scopes = (type(scopes) == "table") and scopes or NewGroupCopyScopesFallback()
    local allowKeys, allowPrefixes, allowTables = {}, {}, {}
    for i = 1, #GROUP_COPY_CATEGORIES do
        local cat = GROUP_COPY_CATEGORIES[i]
        if scopes[cat.key] == true then
            for j = 1, #(cat.keys or {}) do allowKeys[cat.keys[j]] = true end
            for j = 1, #(cat.prefix or {}) do allowPrefixes[#allowPrefixes + 1] = cat.prefix[j] end
            for j = 1, #(cat.tables or {}) do allowTables[cat.tables[j]] = true end
        end
    end
    for key, value in pairs(srcConf) do
        if not GROUP_COPY_EXCLUDE[key] then
            local copy = allowKeys[key] or allowTables[key]
            if (not copy) and type(key) == "string" then
                for i = 1, #allowPrefixes do
                    local prefix = allowPrefixes[i]
                    if key:sub(1, #prefix) == prefix then
                        copy = true
                        break
                    end
                end
            end
            if copy then dstConf[key] = DeepCopyGroupValue(value) end
        end
    end
    RefreshGroupCopyRuntime()
    return true
end
Registry:RegisterAction({
    key = "copy_group",
    label = "Copy Group Frame Options",
    type = "copy",
    combatSafe = false,
    captureSnapshot = true,
    aliases = { "copy party to raid", "copy group frame settings", "copy group settings", "copy raid settings" },
    run = function(args)
        local GP = M and M.GroupPage
        local copyFn = GP and type(GP.CopyGroupSettings) == "function" and GP.CopyGroupSettings or CopyGroupSettingsFallback
        if type(copyFn) ~= "function" then
            return false, "I could not find the Group Frames copy helper."
        end        local src = args and args.source
        if src ~= "raid" and src ~= "mythicraid" then src = "party" end
        local targets = args and args.targets
        if type(targets) ~= "table" or #targets == 0 then
            local target = args and args.target
            targets = target and { target } or {}
        end
        if #targets == 0 then return false, "Which group frame should receive the copied options?" end
        local scopes = args and args.scopes
        if type(scopes) ~= "table" then
            if GP and type(GP.NewGFCopyScopes) == "function" then
                scopes = GP.NewGFCopyScopes()
            else
                scopes = NewGroupCopyScopesFallback()
            end
        end
        local count = 0
        local copiedLabels = {}
        for i = 1, #targets do
            local dst = targets[i]
            if dst ~= "raid" and dst ~= "mythicraid" then dst = "party" end
            if dst ~= src and copyFn(src, dst, scopes) then
                count = count + 1
                copiedLabels[#copiedLabels + 1] = GroupLabel(dst)
            end
        end
        if count == 0 then return false, "I did not copy any group-frame options. Pick a different source and destination." end
        return true, "Done. I copied " .. GroupLabel(src) .. " group-frame options to " .. table.concat(copiedLabels, ", ") .. "." .. GroupCopyScopeSummary(scopes)
    end,
})
