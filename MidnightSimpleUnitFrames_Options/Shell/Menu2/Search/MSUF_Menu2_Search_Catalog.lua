-- Search static catalog, client availability and external providers.
local _, MSUF = ...
local Parts = MSUF.SearchIndexParts
local AddControlQuestionSearchText = Parts.AddControlQuestionSearchText
local AddSearchRecord = Parts.AddSearchRecord
local AddSearchText = Parts.AddSearchText
local AddToggleQuestionSearchText = Parts.AddToggleQuestionSearchText
local BuildSearchPageInfoForKey = Parts.BuildSearchPageInfoForKey
local CatalogSearchIdentity = Parts.CatalogSearchIdentity
local DASHBOARD_ROUTE_CHANGELOG = Parts.DASHBOARD_ROUTE_CHANGELOG
local DASHBOARD_ROUTE_RECOVERY = Parts.DASHBOARD_ROUTE_RECOVERY
local DASHBOARD_ROUTE_SCALING = Parts.DASHBOARD_ROUTE_SCALING
local DisplaySearchText = Parts.DisplaySearchText
local EMPTY_SEARCH_RECORDS = Parts.EMPTY_SEARCH_RECORDS
local IsSearchableDisplayText = Parts.IsSearchableDisplayText
local M = Parts.M
local MarkSearchIndexDirty = Parts.MarkSearchIndexDirty
local NormalizeSearchText = Parts.NormalizeSearchText
local SEARCH_BLIZZARD_DISPEL_KEYWORDS = Parts.SEARCH_BLIZZARD_DISPEL_KEYWORDS
local SEARCH_CONTROL_HAYSTACK_MAX_LEN = Parts.SEARCH_CONTROL_HAYSTACK_MAX_LEN
local SEARCH_CONTROL_MAX_TOKENS = Parts.SEARCH_CONTROL_MAX_TOKENS
local SEARCH_DASHBOARD_CHANGELOG_KEYWORDS = Parts.SEARCH_DASHBOARD_CHANGELOG_KEYWORDS
local SEARCH_DASHBOARD_DISCORD_KEYWORDS = Parts.SEARCH_DASHBOARD_DISCORD_KEYWORDS
local SEARCH_DASHBOARD_RECOVERY_KEYWORDS = Parts.SEARCH_DASHBOARD_RECOVERY_KEYWORDS
local SEARCH_DASHBOARD_SCALING_KEYWORDS = Parts.SEARCH_DASHBOARD_SCALING_KEYWORDS
local SEARCH_DASHBOARD_SUPPORT_KEYWORDS = Parts.SEARCH_DASHBOARD_SUPPORT_KEYWORDS
local SEARCH_DASHBOARD_WAGO_KEYWORDS = Parts.SEARCH_DASHBOARD_WAGO_KEYWORDS
local SEARCH_DEBUFF_STRIPE_KEYWORDS = Parts.SEARCH_DEBUFF_STRIPE_KEYWORDS
local SEARCH_DISPEL_DEBUFF_KEYWORDS = Parts.SEARCH_DISPEL_DEBUFF_KEYWORDS
local SEARCH_DISPEL_OVERLAY_KEYWORDS = Parts.SEARCH_DISPEL_OVERLAY_KEYWORDS
local SEARCH_HIGHLIGHT_BORDER_KEYWORDS = Parts.SEARCH_HIGHLIGHT_BORDER_KEYWORDS
local SEARCH_STATE = Parts.SEARCH_STATE
local SEARCH_TEXT_MAX_LEN = Parts.SEARCH_TEXT_MAX_LEN
local SEARCH_UNIT_AURA_DISPEL_KEYWORDS = Parts.SEARCH_UNIT_AURA_DISPEL_KEYWORDS
local Search = Parts.Search
local SearchCombatLocked = Parts.SearchCombatLocked
local SearchData = Parts.SearchData
local SearchIgnoreQueryWord = Parts.SearchIgnoreQueryWord
local SearchKeywordList = Parts.SearchKeywordList
local SearchMenuClosed = Parts.SearchMenuClosed
local SearchText = Parts.SearchText
local byte = Parts.byte
local SearchIndexBuild
local STATIC_ROW_CLIENT_CAPABILITY = {
    ["id\031uf_player\031menu2%2Euf_player%2Eunit%2Estatus%2Epvp%2Ecountdown"] = "IsForever",
    -- Unit Frames > Pet > Status: Pet Happiness (MSUF_Menu2_UnitStatusSection*.lua).
    ["id\031uf_pet\031menu2%2Euf_pet%2Eunit%2Estatus%2Eindicator%2Epet_happiness"] = "SupportsPetHappiness",
    -- Unit Frames > Target, Focus and Boss > Status: Threat % (same files).
    ["id\031uf_target\031menu2%2Euf_target%2Eunit%2Estatus%2Eindicator%2Ethreat"] = "SupportsThreatText",
    ["id\031uf_focus\031menu2%2Euf_focus%2Eunit%2Estatus%2Eindicator%2Ethreat"] = "SupportsThreatText",
    ["id\031uf_boss\031menu2%2Euf_boss%2Eunit%2Estatus%2Eindicator%2Ethreat"] = "SupportsThreatText",
    ["id\031uf_target\031menu2%2Euf_target%2Eunit%2Estatus%2Ethreat%2Ecolor_curve"] = "SupportsThreatText",
    ["id\031uf_focus\031menu2%2Euf_focus%2Eunit%2Estatus%2Ethreat%2Ecolor_curve"] = "SupportsThreatText",
    ["id\031uf_boss\031menu2%2Euf_boss%2Eunit%2Estatus%2Ethreat%2Ecolor_curve"] = "SupportsThreatText",
    ["id\031opt_colors\031menu2%2Eopt%2Ecolors%2Eadvanced%2Ethreat%2Ecurve%2Elow"] = "SupportsThreatText",
    ["id\031opt_colors\031menu2%2Eopt%2Ecolors%2Eadvanced%2Ethreat%2Ecurve%2Emid"] = "SupportsThreatText",
    ["id\031opt_colors\031menu2%2Eopt%2Ecolors%2Eadvanced%2Ethreat%2Ecurve%2Ehigh"] = "SupportsThreatText",
    ["id\031gf_indicators\031menu2%2Egf_indicators%2Egroup%2Efield%2Ethreattextcolorcurve"] = "SupportsThreatText",
    ["id\031uf_target\031menu2%2Euf_target%2Eunit%2Estatus%2Ethreat%2Ebackground"] = "SupportsThreatText",
    ["id\031uf_focus\031menu2%2Euf_focus%2Eunit%2Estatus%2Ethreat%2Ebackground"] = "SupportsThreatText",
    ["id\031uf_boss\031menu2%2Euf_boss%2Eunit%2Estatus%2Ethreat%2Ebackground"] = "SupportsThreatText",
    ["id\031gf_indicators\031menu2%2Egf_indicators%2Egroup%2Efield%2Ethreattextbackground"] = "SupportsThreatText",
    -- Group Frames > Layout > Buff coverage, built on WoW Forever only
    -- (MSUF_Menu2_GroupLayoutAdditional.lua); Midnight shares the index file.
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageenabled"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoveragewild"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoveragethorns"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageintellect"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessings"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingpriorities"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingtank1"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingtank2"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingtank3"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessinghealer1"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessinghealer2"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessinghealer3"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingdps1"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingdps2"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingdps3"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingwarrior"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingpaladin"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessinghunter"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingrogue"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingpriest"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingshaman"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingmage"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingwarlock"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageblessingdruid"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoveragestamina"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoveragespirit"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoveragethornstankonly"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageglow"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoveragecombat"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoveragesize"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoverageanchor"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoveragex"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoveragey"] = "IsForever",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ebuffcoveragelayer"] = "IsForever",
    -- Miscellaneous > Blizzard Frames: native Player resource pings need the ping
    -- system, which only the Mainline family (Midnight and WoW Forever) has; the
    -- page builds the switch there only (MSUF_Menu2_GlobalMisc.lua).
    ["id\031opt_misc\031menu2%2Eopt%2Emisc%2Eglobal%2Esetting%2Eplayer%2Eresource%2Eping%2Eenabled"] = "IsRetail",
    -- Castbar > Empowered Casts, built on Midnight only (MSUF_Menu2_GlobalCastbars.lua);
    -- WoW Forever shares the index file.
    ["id\031opt_castbar\031menu2%2Eopt%2Ecastbar%2Eglobal%2Eempowered%2Eempower%2Ecolor%2Estages"] = "HasEmpoweredCasts",
    ["id\031opt_castbar\031menu2%2Eopt%2Ecastbar%2Eglobal%2Eempowered%2Eempower%2Estage%2Eblink"] = "HasEmpoweredCasts",
    ["id\031opt_castbar\031menu2%2Eopt%2Ecastbar%2Eglobal%2Eempowered%2Eempower%2Estage%2Eblink%2Etime"] = "HasEmpoweredCasts",
    -- Colors > Unit colors: the tagged-mob color and its toggle, built where mobs
    -- can be tagged (MSUF_Menu2_AdvancedColors.lua); Midnight shares the index file.
    ["id\031opt_colors\031menu2%2Eopt%2Ecolors%2Eadvanced%2Enpc%2Ecolor%2Etapped"] = "SupportsTapDenied",
    ["id\031opt_colors\031menu2%2Eopt%2Ecolors%2Eadvanced%2Enpc%2Etap%2Edenied%2Egray"] = "SupportsTapDenied",
    -- Fonts > Name shortening: Character names, built where characters carry a
    -- surname (MSUF_Menu2_GlobalFonts.lua); Midnight shares the index file.
    ["id\031opt_fonts\031menu2%2Eopt%2Efonts%2Eglobal%2Ename%2Eshortening%2Echaracter%2Ename%2Eparts"] = "HasCharacterSurnames",
}
-- Rows of controls a client builds only where it has the unit or group scope
-- (M.SupportsFrameScope): Group Frames > Layout > Friendly bosses needs boss
-- units (MSUF_Menu2_GroupLayoutAdditional.lua), the Mythic raid group cap the
-- Mythic Raid scope (MSUF_Menu2_GroupLayout.lua).
local STATIC_ROW_FRAME_SCOPE = {
    ["id\031icon_skins\031menu2%2Eicon_skins%2Eicon_skins%2Ecastbar_shape%2Efocus"] = "focus",
    ["id\031icon_skins\031menu2%2Eicon_skins%2Eicon_skins%2Ecastbar_shape%2Eboss"] = "boss",
    ["id\031icon_skins\031menu2%2Eicon_skins%2Eicon_skins%2Ecastbar_shape%2Earena"] = "arena",
    ["id\031icon_skins\031menu2%2Eicon_skins%2Eicon_skins%2Efocus_kick_shape"] = "focus",
    ["id\031icon_skins\031menu2%2Eicon_skins%2Eunit%2Etrinket_shape"] = "arena",
    ["id\031opt_bars\031menu2%2Eopt%2Ebars%2Eglobal%2Ehighlight%2Epreview%2Eboss%2Etarget"] = "boss",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Efriendlybossenabled"] = "boss",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Efriendlybosshealeronly"] = "boss",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Efriendlybosswidth"] = "boss",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Efriendlybossheight"] = "boss",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Efriendlybossx"] = "boss",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Efriendlybossy"] = "boss",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Efriendlybosscolumns"] = "boss",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Efriendlybosstextsize"] = "boss",
    ["id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2Ehidemythicgroupsfivetoeight"] = "mythicraid",
    -- Castbar > Interrupt Ready: one toggle per castbar unit, and Focus Kick
    -- (MSUF_Menu2_GlobalCastbars.lua).
    ["id\031opt_castbar\031menu2%2Eopt%2Ecastbar%2Eglobal%2Einterrupt%2Eready%2Ekick%2Eready%2Eshow%2Efocus"] = "focus",
    ["id\031opt_castbar\031menu2%2Eopt%2Ecastbar%2Eglobal%2Einterrupt%2Eready%2Ekick%2Eready%2Eshow%2Eboss"] = "boss",
    ["id\031opt_castbar\031menu2%2Eopt%2Ecastbar%2Eglobal%2Einterrupt%2Eready%2Ekick%2Eready%2Eshow%2Earena"] = "arena",
    ["id\031opt_castbar\031menu2%2Eopt%2Ecastbar%2Eglobal%2Efocus%2Ekick%2Ereset%2Eposition"] = "focus",
}
local staticRowsWithoutClientSupport

local function StaticRowsWithoutClientSupport()
    if staticRowsWithoutClientSupport then return staticRowsWithoutClientSupport end
    local client = MSUF.Client
    staticRowsWithoutClientSupport = {}
    for identity, capability in pairs(STATIC_ROW_CLIENT_CAPABILITY) do
        if not (type(client) == "table" and client[capability] == true) then
            staticRowsWithoutClientSupport[identity] = true
        end
    end
    local castbarUtils = MSUF.Castbars and MSUF.Castbars.Utils
    if castbarUtils and not castbarUtils.PlayerSpellRanksSupported then
        staticRowsWithoutClientSupport["id\031uf_player\031menu2%2Euf_player%2Eunit%2Ecastbar%2Eshow_spell_rank"] = true
    end
    local supportsScope = M.SupportsFrameScope
    if type(supportsScope) == "function" then
        for identity, scope in pairs(STATIC_ROW_FRAME_SCOPE) do
            if not supportsScope(scope) then staticRowsWithoutClientSupport[identity] = true end
        end
    end
    -- Class resource rows follow the client's resource capabilities; the
    -- client-only resource extras follow the list their page builds. A page
    -- the client never registers (Swing Timers off Forever) loses its rows
    -- in SearchProviders.FilterAvailable.
    local supportsSetting = client and client.SupportsClassResourceSetting
    local extras = M.ResourceExtrasPage
    local clientOnly, built = {}, {}
    if extras and extras.ClientOnlySettings then clientOnly, built = extras.ClientOnlySettings() end
    -- The Castbar page's GCD Bar section follows the page's own capability
    -- probe (the Duration API, and the GCD spell on WoW Forever).
    local gcdProbe = M.CastbarGCDBarSupported
    local gcdHidden = gcdProbe ~= nil and not gcdProbe()
    -- Its interrupt indicator's nameplate switch is shown only where the MSUF
    -- Suite has nameplates (the same page's probe).
    staticRowsWithoutClientSupport.config = {
        clientOnly = clientOnly, built = built, supportsSetting = supportsSetting,
        gcdHidden = gcdHidden,
    }
    return staticRowsWithoutClientSupport
end

--- Static inventory for controls whose page has never been built. A live widget
--- record for the exact same semantic route always wins: it carries the real
--- anchor and exact identity. Equal labels on different controls stay intact.
local function AddStaticIndexSearchRecords(job, deadline)
    local staticIndex = Search.StaticIndex
    local staticRecords = staticIndex.GetRecords()
    local unsupported = StaticRowsWithoutClientSupport()
    local config = unsupported.config
    if job.nameplatesHidden == nil then
        local probe = M.CastbarSuiteNameplatesSupported
        job.nameplatesHidden = probe ~= nil and not probe() or false
        job.nameplateFontsHidden = not MSUF.SuiteLink.HasNameplateFonts()
    end
    local records, covered = job.records, job.covered
    for i = job.index, #staticRecords do
        local rec = staticRecords[i]
        local identity, key = rec.searchIdentity, staticIndex.TargetField(rec, "settingKey")
        local hidden = (key and config.clientOnly[key] and not config.built[key])
            or (config.gcdHidden and rec.key == "opt_castbar" and staticIndex.TargetField(rec, "sectionId") == "castbar_gcd")
            or (job.nameplatesHidden and key == "general.kickReadyShowNameplates")
            or (job.nameplateFontsHidden and key and key:match("^nameplates%."))
            or (config.supportsSetting and not config.supportsSetting(key))
        if not covered[identity] and not unsupported[identity] and not hidden
            and M.SupportsSearchTarget(rec.key, key, staticIndex.TargetField(rec, "prepareKind"), staticIndex.TargetField(rec, "prepareValue")) then
            rec.order = #records + 1
            records[#records + 1] = rec
        end
        if deadline and debugprofilestop() >= deadline then job.index = i + 1 return false end
    end
    return true
end

-- All callers share one queued build; a getter never finishes it synchronously.
-- The 1 ms work deadline leaves headroom below the 4 ms per-frame contract.
local SearchProviders = {
    KINDS = M.KeySetFromWords "faq section toggle dropdown segment slider color button textinput control",
    ROW_LIMIT = 4000,
    KEYWORD_LIMIT = 96,
    HELP_MAX_LEN = 600,
}

function SearchProviders.Text(value, maxLen)
    if type(value) ~= "string" then return nil end
    value = DisplaySearchText(value)
    if value == "" or #value > (maxLen or SEARCH_TEXT_MAX_LEN) then return nil end
    return value
end

function SearchProviders.Keywords(out, keywords)
    local count = 0
    local function Add(keyword)
        if count < SearchProviders.KEYWORD_LIMIT and type(keyword) == "string" and keyword ~= "" then
            count = count + 1
            out[#out + 1] = keyword
        end
    end
    if type(keywords) == "string" then
        for keyword in keywords:gmatch("[^|]+") do Add(keyword) end
    elseif type(keywords) == "table" then
        for i = 1, math.min(#keywords, SearchProviders.KEYWORD_LIMIT) do Add(keywords[i]) end
    end
end

function SearchProviders.Record(row, info)
    local label = SearchProviders.Text(row.label)
    if not (label and IsSearchableDisplayText(label)) then return nil end
    local kind = SearchProviders.KINDS[row.kind or "control"] and (row.kind or "control") or nil
    if not kind then return nil end
    local controlId = row.controlId
    if controlId ~= nil and (type(controlId) ~= "string" or #controlId < 3 or #controlId > 160
        or not controlId:match("^[%w_%.:/%-]+$")) then return nil end
    local settingKey = SearchProviders.Text(row.settingKey)
    local sectionId = SearchProviders.Text(row.sectionId)
    local help = SearchProviders.Text(row.help, SearchProviders.HELP_MAX_LEN)
    local anchorText = SearchProviders.Text(row.anchorText)
    if kind == "faq" then
        local extra = { help, anchorText }
        SearchProviders.Keywords(extra, row.keywords)
        local rec = AddSearchRecord(nil, nil, info, label, nil, "faq", extra)
        if rec then
            rec.answer, rec.anchorFallback, rec.priority, rec.faq = help, anchorText or label, 0, true
            rec.providerRow = row
            rec.sectionId, rec.controlId = sectionId, controlId
            if controlId or settingKey or sectionId then
                rec.exactTarget = { pageKey = info.key, controlId = controlId, settingKey = settingKey,
                    sectionId = sectionId, label = label }
            end
            if sectionId then rec.route = { accordion = { [info.key .. ":" .. sectionId] = true } } end
        end
        return rec
    end
    local labelNorm = NormalizeSearchText(label)
    local section = SearchProviders.Text(row.section)
    local hint = SearchProviders.Text(row.hint)
    if not hint then
        hint = info.group ~= "" and (info.group .. " > " .. info.label) or info.title
        if section and NormalizeSearchText(section) ~= labelNorm then hint = hint .. " > " .. section end
    end
    local parts = { label, hint, info.label, info.group, info.title }
    if kind == "toggle" then AddToggleQuestionSearchText(parts, label) end
    AddControlQuestionSearchText(parts, label, kind, nil)
    SearchProviders.Keywords(parts, row.keywords)
    parts[#parts + 1] = help
    local haystack = {}
    for i = 1, #parts do AddSearchText(haystack, parts[i]) end
    local haystackText = table.concat(haystack, " ")
    if #haystackText > SEARCH_CONTROL_HAYSTACK_MAX_LEN then
        haystackText = SearchText.Utf8BytePrefix(haystackText, SEARCH_CONTROL_HAYSTACK_MAX_LEN)
    end
    local rec = {
        key = info.key, label = label, kind = kind, hint = hint, title = info.title, group = info.group,
        labelNorm = labelNorm, titleNorm = "", groupNorm = NormalizeSearchText(info.group),
        hintNorm = NormalizeSearchText(hint), haystack = NormalizeSearchText(haystackText),
        tokenLimit = SEARCH_CONTROL_MAX_TOKENS, answer = help, provided = true,
        anchorFallback = anchorText or label,
        providerRow = row, sectionId = sectionId, controlId = controlId,
    }
    rec.searchIdentity = controlId and CatalogSearchIdentity("id", info.key, controlId)
        or CatalogSearchIdentity("provided", info.key, settingKey or kind, labelNorm, hint)
    if controlId or settingKey or sectionId then
        rec.exactTarget = { pageKey = info.key, controlId = controlId, settingKey = settingKey,
            sectionId = sectionId, label = label, prepareKind = row.prepareKind, prepareValue = row.prepareValue }
    end
    if sectionId then rec.route = { accordion = { [info.key .. ":" .. sectionId] = true } } end
    return rec
end

SearchProviders.QUERY_PHRASE_LIMIT, SearchProviders.QUERY_PHRASE_MIN_LEN, SearchProviders.QUERY_PHRASE_MAX_LEN = 12, 6, 96

--- row.queryPhrases: curated natural wordings that name the row's setting
--- outright, unlike keywords, which only add haystack text. A phrase needs two
--- words, or CJK text. The same phrase on different settings promotes neither;
--- the false entry keeps a third repeat ambiguous as well.
function SearchProviders.QueryPhrases(cache, phrases, settingKey)
    if type(phrases) ~= "table" or not settingKey then return end
    local target
    for i = 1, math.min(#phrases, SearchProviders.QUERY_PHRASE_LIMIT) do
        local phrase = phrases[i]
        local normalized = type(phrase) == "string" and #phrase <= SearchProviders.QUERY_PHRASE_MAX_LEN
            and NormalizeSearchText(phrase)
        if normalized and #normalized >= SearchProviders.QUERY_PHRASE_MIN_LEN
            and (normalized:find(" ", 1, true) or normalized:find("[\227-\237]")) then
            local targets = cache.queryTargets
            if not targets then
                targets = {}
                cache.queryTargets = targets
            end
            local known = targets[normalized]
            if known == nil then
                target = target or { settingKey = settingKey }
                targets[normalized] = target
            elseif known and known.settingKey ~= settingKey then
                targets[normalized] = false
            end
        end
    end
end

-- Optional provider vocabulary for Korean or Chinese queries. Each row requires
-- every concept in its own list (two or three). All other text must consist of
-- the supplied particles or question words; an unknown qualifier declines.
local function CompileQueryConcepts(compact, concepts, settingKey)
    if type(concepts) ~= "table" or #concepts < 3 or #concepts > 4 then return end
    local words, lengths = {}, {}
    for group = 1, #concepts do
        local list = concepts[group]
        if type(list) ~= "string" or #list == 0 or #list > 1536 then return end
        for word in list:gmatch("%S+") do
            if #word > 48 then return end
            local known = words[word]
            if known and known > 1 and known ~= group then return end
            words[word] = group
            lengths[#word] = true
        end
    end
    local widths = {}
    for length in pairs(lengths) do widths[#widths + 1] = length end
    table.sort(widths, function(a, b) return a > b end)
    compact[#compact + 1] = { words = words, widths = widths, groups = #concepts,
        target = { settingKey = settingKey } }
end

local function MatchesQueryConcepts(rule, text)
    local pos, second, third, fourth = 1, false, false, rule.groups == 3
    while pos <= #text do
        local found
        for _, width in ipairs(rule.widths) do
            if pos + width - 1 <= #text then
                local group = rule.words[text:sub(pos, pos + width - 1)]
                if group then
                    if group == 2 then second = true elseif group == 3 then third = true
                    elseif group == 4 then fourth = true end
                    pos, found = pos + width, true
                    break
                end
            end
        end
        if not found then return false end
    end
    return second and third and fourth
end

function SearchProviders.CompactTarget(cache, normalized)
    local rules = cache and cache.compact
    if not rules or #normalized < 6 or #normalized > 240 or not normalized:find("[\227-\237]") then return end
    local text = normalized:gsub("%s+", "")
    local match
    for _, rule in ipairs(rules) do
        if MatchesQueryConcepts(rule, text) then
            if match and match.settingKey ~= rule.target.settingKey then return false end
            match = rule.target
        end
    end
    return match
end


function SearchProviders.AddRow(cache, row, pageInfoByKey)
    if type(row) ~= "table" then return false end
    local pageKey = row.pageKey
    if type(pageKey) ~= "string" or pageKey == "" or pageKey == "search"
        or not (M.pages and M.pages[pageKey])
        or (M.SupportsUnitPage and M.SupportsUnitPage(pageKey) == false) then
        return false
    end
    if row.kind ~= "page" then
        local rec = SearchProviders.Record(row, pageInfoByKey[pageKey] or BuildSearchPageInfoForKey(pageKey))
        if not rec then return false end
        cache.records[#cache.records + 1] = rec
        cache.pageKeys[pageKey] = true
        if row.queryPhrases and rec.exactTarget then
            SearchProviders.QueryPhrases(cache, row.queryPhrases, rec.exactTarget.settingKey)
        end
        if row.queryConcepts and rec.exactTarget and rec.exactTarget.settingKey and cache.compact ~= false then
            local rules = cache.compact or {}
            cache.compact = rules
            if #rules < 12 then
                CompileQueryConcepts(rules, row.queryConcepts, rec.exactTarget.settingKey)
            else
                cache.compact = false
            end
        end
        return true
    end
    local page = cache.pages[pageKey]
    if not page then
        page = { parts = {} }
        cache.pages[pageKey] = page
    end
    SearchProviders.Keywords(page.parts, row.keywords)
    local help = SearchProviders.Text(row.help, SearchProviders.HELP_MAX_LEN)
    local hint = SearchProviders.Text(row.hint)
    page.parts[#page.parts + 1] = help
    page.parts[#page.parts + 1] = hint
    page.answer = page.answer or help
    page.hint = hint or page.hint
    return true
end

--- Calls every provider once and caches the result until a provider changes or
--- the menu language does. A provider that raised on its last call is skipped
--- until it registers again, so one broken provider cannot break search.
--- With a build job and a deadline it stops once the deadline passes and returns
--- nil, keeping its place in job.collect; the next call continues there.
function SearchProviders.Collect(pageInfoByKey, job, deadline)
    if SearchCombatLocked() or SearchMenuClosed() then return { pages = {}, records = {}, pageKeys = {} } end
    local cache = SEARCH_STATE.providerCache
    if cache then return cache end
    local walk = job and job.collect
    if not walk then
        walk = { cache = { pages = {}, records = {}, pageKeys = {}, rows = 0, skipped = 0 }, names = {}, n = 1 }
        walk.serial = SEARCH_STATE.dirtySerial
        walk.due = function() return SearchIndexBuild.Due(walk.deadline) end
        for name in pairs(SEARCH_STATE.providers) do walk.names[#walk.names + 1] = name end
        table.sort(walk.names)
        if job then job.collect = walk end
    end
    cache, walk.deadline = walk.cache, deadline
    while walk.n <= #walk.names do
        if not walk.rows then
            local entry = SEARCH_STATE.providers[walk.names[walk.n]]
            local rows, done
            if entry and not entry.failed then
                entry.failed = true
                if entry.begin then
                    walk.step = walk.step or entry.begin()
                    if type(walk.step) == "function" then rows, done = walk.step(walk.due)
                    else done = true end
                else
                    rows, done = entry.collect(), true
                end
                entry.failed = nil
            else
                done = true
            end
            -- A producer can itself invalidate the provider. Let the outer
            -- generation restart before any part of that snapshot is published.
            if walk.serial ~= SEARCH_STATE.dirtySerial then return nil end
            walk.rows = type(rows) == "table" and rows or EMPTY_SEARCH_RECORDS
            local remaining = walk.remaining or SearchProviders.ROW_LIMIT
            walk.i, walk.last = 1, math.min(#walk.rows, remaining)
            walk.remaining = remaining - walk.last
            walk.done = done or walk.remaining == 0
            if deadline and SearchIndexBuild.Due(deadline) then return nil end
        end
        while walk.i <= walk.last do
            if SearchProviders.AddRow(cache, walk.rows[walk.i], pageInfoByKey) then
                cache.rows = cache.rows + 1
            else
                cache.skipped = cache.skipped + 1
            end
            walk.i = walk.i + 1
            if deadline and SearchIndexBuild.Due(deadline) then return nil end
        end
        walk.rows = nil
        if walk.done then
            walk.step, walk.remaining, walk.n = nil, nil, walk.n + 1
        elseif deadline and (walk.last == 0 or SearchIndexBuild.Due(deadline)) then
            return nil
        end
    end
    if job then job.collect = nil end
    SEARCH_STATE.providerCache = cache
    return cache
end

--- Provider records join after the static rows. A live widget registered for the
--- exact control ID, same setting, or otherwise same kind and label on the page wins:
--- it carries the real anchor and exact identity, exactly like static rows.
function SearchProviders.Append(records, cache, job, deadline)
    local list = cache.records
    if #list == 0 then return true end
    local live = job.providerLive or {}
    job.providerLive = live
    if not job.providerAppend then
        for i = job.index, #records do
            local record = records[i]
            if record.anchor and cache.pageKeys[record.key] then
                local target = record.exactTarget
                if target and target.controlId and target.controlId ~= "" then
                    live[record.key .. "\031id\031" .. target.controlId] = i
                end
                if target and target.settingKey and target.settingKey ~= "" then
                    live[record.key .. "\031" .. target.settingKey] = i
                end
                live[record.key .. "\031" .. record.kind .. "\031" .. record.labelNorm] = i
            end
            if deadline and i % 16 == 0 and SearchIndexBuild.Due(deadline) then job.index = i + 1 return false end
        end
        job.providerAppend = 1
    end
    for i = job.providerAppend, #list do
        local rec = list[i]
        local target = rec.exactTarget
        local liveKey = target and target.controlId and (rec.key .. "\031id\031" .. target.controlId)
            or target and target.settingKey and (rec.key .. "\031" .. target.settingKey)
            or (rec.key .. "\031" .. rec.kind .. "\031" .. rec.labelNorm)
        local index = live[liveKey]
        if index then
            -- Keep the live identity/anchor and the provider's localized words
            -- and ownership. Copy before merging: cached widget records must
            -- not retain provider terms after a feature is disabled or renamed.
            local merged = {}
            for key, value in pairs(records[index]) do merged[key] = value end
            -- The live words come first: provider text first, cut at the
            -- record budget, could drop all of them. The budget stays one
            -- record's, so the provider's tail is what a long merge cuts.
            merged.haystack = SearchText.Utf8BytePrefix((merged.haystack or "") .. " " .. (rec.haystack or ""),
                SEARCH_CONTROL_HAYSTACK_MAX_LEN)
            merged.tokens = nil
            merged.providerRow = rec.providerRow
            if rec.providerRow and rec.providerRow.inactive then
                merged.hint, merged.hintNorm = rec.hint, rec.hintNorm
            end
            merged.answer = merged.answer or rec.answer
            records[index] = merged
        else
            rec.order = #records + 1
            records[#records + 1] = rec
        end
        if deadline and i % 8 == 0 and SearchIndexBuild.Due(deadline) then job.providerAppend = i + 1 return false end
    end
    job.providerLive, job.providerAppend = nil, nil
    return true
end

-- Third-party registrations can omit optional callbacks or unregister with nil.
local function OptionalCallback(value)
    return value == nil or type(value) == "function"
end

--- Registers, replaces (same name) or with a nil function removes a provider.
--- An optional begin() returns step(due), which returns a row batch or nil
--- and a completion flag. Batches share the original per-provider row cap.
--- Abandoning a build releases its step; a new build calls begin() again.
function M.RegisterSearchProvider(name, collect, contextChanged, begin)
    if type(name) ~= "string" or name == "" then return false end
    if not (OptionalCallback(collect) and OptionalCallback(contextChanged) and OptionalCallback(begin)) then return false end
    SEARCH_STATE.providers[name] = collect and { collect = collect, contextChanged = contextChanged, begin = begin } or nil
    SEARCH_STATE.providerCache = nil
    MarkSearchIndexDirty()
    return true
end

--- Availability applies to every record source, including widgets on pages that
--- have already been visited. Predicates run only when rebuilding the index;
--- providers invalidate after module/configuration changes, never from a ticker.
--- The record retains providerRow for companion-specific ownership metadata.
function M.RegisterSearchAvailability(name, isAvailable)
    if type(name) ~= "string" or name == "" then return false end
    if not OptionalCallback(isAvailable) then return false end
    SEARCH_STATE.availability[name] = isAvailable
    MarkSearchIndexDirty()
    return true
end

function M.InvalidateSearchProvider(name)
    if name ~= nil and (type(name) ~= "string" or not SEARCH_STATE.providers[name]) then return false end
    SEARCH_STATE.providerCache = nil
    MarkSearchIndexDirty()
    return true
end

function SearchProviders.FilterAvailable(records, job, deadline)
    local write = job and job.filterWrite or 0
    local predicates = {}
    for _, isAvailable in pairs(SEARCH_STATE.availability) do predicates[#predicates + 1] = isAvailable end
    for read = job and job.index or 1, #records do
        local rec = records[read]
        local available = rec.easterEgg or (M.pages and M.pages[rec.key]) ~= nil
        if available and not rec.easterEgg then
            local settingKey = Search.StaticIndex.TargetField(rec, "settingKey")
            for p = 1, #predicates do
                if predicates[p](rec.key, settingKey, rec) == false then
                    available = false
                    break
                end
            end
        end
        if available then
            write = write + 1
            rec.order = write
            records[write] = rec
        end
        if deadline and SearchIndexBuild.Due(deadline) then
            job.index, job.filterWrite = read + 1, write
            return false
        end
    end
    for i = #records, write + 1, -1 do records[i] = nil end
    return true
end

--- Whether search would offer a page, without building the index: registered,
--- supported by this client and allowed by every availability predicate. The
--- predicates get the page key and a page-shaped record, as for page records.
local pageAvailabilityProbe = { kind = "page" }
local function IsSearchPageAvailable(pageKey)
    if type(pageKey) ~= "string" or not (M.pages and M.pages[pageKey]) then return false end
    if M.SupportsUnitPage and not M.SupportsUnitPage(pageKey) then return false end
    pageAvailabilityProbe.key = pageKey
    for _, isAvailable in pairs(SEARCH_STATE.availability) do
        if isAvailable(pageKey, nil, pageAvailabilityProbe) == false then return false end
    end
    return true
end

local SEARCH_FAQ
-- Home needs no FAQ records. Keep one catalog after its first search reader.
local function GetFAQRecords()
    if SEARCH_FAQ then return SEARCH_FAQ end
    SEARCH_FAQ = SearchData.BuildFAQ and SearchData.BuildFAQ({
        SearchKeywordList = SearchKeywordList,
        DASHBOARD_ROUTE_RECOVERY = DASHBOARD_ROUTE_RECOVERY,
        DASHBOARD_ROUTE_SCALING = DASHBOARD_ROUTE_SCALING,
        DASHBOARD_ROUTE_CHANGELOG = DASHBOARD_ROUTE_CHANGELOG,
        SEARCH_DISPEL_DEBUFF_KEYWORDS = SEARCH_DISPEL_DEBUFF_KEYWORDS,
        SEARCH_HIGHLIGHT_BORDER_KEYWORDS = SEARCH_HIGHLIGHT_BORDER_KEYWORDS,
        SEARCH_DISPEL_OVERLAY_KEYWORDS = SEARCH_DISPEL_OVERLAY_KEYWORDS,
        SEARCH_DEBUFF_STRIPE_KEYWORDS = SEARCH_DEBUFF_STRIPE_KEYWORDS,
        SEARCH_BLIZZARD_DISPEL_KEYWORDS = SEARCH_BLIZZARD_DISPEL_KEYWORDS,
        SEARCH_UNIT_AURA_DISPEL_KEYWORDS = SEARCH_UNIT_AURA_DISPEL_KEYWORDS,
        SEARCH_DASHBOARD_RECOVERY_KEYWORDS = SEARCH_DASHBOARD_RECOVERY_KEYWORDS,
        SEARCH_DASHBOARD_DISCORD_KEYWORDS = SEARCH_DASHBOARD_DISCORD_KEYWORDS,
        SEARCH_DASHBOARD_SUPPORT_KEYWORDS = SEARCH_DASHBOARD_SUPPORT_KEYWORDS,
        SEARCH_DASHBOARD_WAGO_KEYWORDS = SEARCH_DASHBOARD_WAGO_KEYWORDS,
        SEARCH_DASHBOARD_SCALING_KEYWORDS = SEARCH_DASHBOARD_SCALING_KEYWORDS,
        SEARCH_DASHBOARD_CHANGELOG_KEYWORDS = SEARCH_DASHBOARD_CHANGELOG_KEYWORDS,
    }) or {}
    return SEARCH_FAQ
end

local SEARCH_EASTER_EGGS = SearchData.EASTER_EGGS or {}

--- What a query names beyond its clause words: a page whose name other page names
--- contain, or a control's whole label in context. (One table: the chunk's locals
--- are budgeted.)
local SearchNaming = {}

--- The short, translated page names that overlap ("Target" in "Focus Target",
--- "Pet Target", "Target of Target"), space-padded for whole-word matching and
--- longest first, so the page a query names is the longest name in it. Names no
--- other page shares stay out: "Castbar" in "castbar color" names no page choice.
--- Built with the records, so it follows the language.
function SearchNaming.BuildPageNames(pageInfos)
    local names = {}
    for i = 1, #pageInfos do
        local key = pageInfos[i].key
        local spec = M.pages[key]
        local sources = { M.navSubpageLabels[key], spec and spec.title }
        for k = 1, 2 do
            local source = sources[k]
            local short = source and NormalizeSearchText((M.Tr(source):gsub("^MSUF[%s%-]+", ""))) or ""
            if short ~= "" then names[#names + 1] = { key = key, padded = " " .. short .. " " } end
            local english = source and NormalizeSearchText((source:gsub("^MSUF[%s%-]+", ""))) or ""
            if key:match("^uf_") and english ~= "" and english ~= short then
                names[#names + 1] = { key = key, padded = " " .. english .. " " }
            end
        end
    end
    local overlapping = {}
    for i = 1, #names do
        for k = 1, #names do
            local inner, outer = names[i], names[k]
            if inner.key ~= outer.key and #outer.padded > #inner.padded and outer.padded:find(inner.padded, 1, true) then
                overlapping[inner], overlapping[outer] = true, true
            end
        end
    end
    local kept = { byKey = {} }
    for i = 1, #names do
        local name = names[i]
        kept.byKey[name.key] = (kept.byKey[name.key] or "") .. name.padded
        if overlapping[names[i]] or names[i].key:match("^uf_") then kept[#kept + 1] = names[i] end
    end
    table.sort(kept, function(a, b)
        if #a.padded ~= #b.padded then return #a.padded > #b.padded end
        return a.key < b.key
    end)
    return kept
end

--- The page whose short name is the longest phrase in the query, so "Target Size"
--- prefers the Target page over Focus Target, Pet Target and Target of Target.
function SearchNaming.Page(normalized)
    local names = SEARCH_STATE.pageNames
    if not names then return nil end
    local padded = " " .. normalized .. " "
    for i = 1, #names do
        if padded:find(names[i].padded, 1, true) then return names[i].key end
    end
    return nil
end

--- "<page or section> <whole label>" ("Player Enable", "Target In group"): the
--- record's entire label is whole words of the query and every other query word
--- names its page, breadcrumb or nav group. Labels made of stop words ("Enable",
--- "Visible") leave no clause that prefers the control, so this is what does.
--- Allocates only for a record whose label occurs in the query.
function SearchNaming.Label(rec, normalized)
    local label = rec.labelNorm
    if rec.sourceLabelNorm and not normalized:find(label, 1, true) then label = rec.sourceLabelNorm end
    if label == "" or label == normalized then return false end
    local pageNames = SEARCH_STATE.pageNames
    local pageContext = pageNames and pageNames.byKey and pageNames.byKey[rec.key]
    local offset = 1
    while true do
        local first, last = normalized:find(label, offset, true)
        if not first then return false end
        offset = first + 1
        if (first == 1 or byte(normalized, first - 1) == 32)
            and (last == #normalized or byte(normalized, last + 1) == 32) then
            local contextWords, valid = 0, true
            for word in (normalized:sub(1, first - 1) .. " " .. normalized:sub(last + 1)):gmatch("%S+") do
                if not SearchIgnoreQueryWord(word) then
                    if not (rec.titleNorm:find(word, 1, true) or (rec.hintNorm or ""):find(word, 1, true)
                        or rec.groupNorm:find(word, 1, true)
                        or (pageContext and pageContext:find(" " .. word .. " ", 1, true))) then
                        valid = false
                        break
                    end
                    contextWords = contextWords + 1
                end
            end
            if valid and contextWords > 0 then return true end
        end
    end
end


function SearchProviders.ReleaseStaticRows()
    staticRowsWithoutClientSupport = nil
end

Parts.AddStaticIndexSearchRecords = AddStaticIndexSearchRecords
Parts.IsSearchPageAvailable = IsSearchPageAvailable
Parts.SEARCH_EASTER_EGGS = SEARCH_EASTER_EGGS
Parts.GetFAQRecords = GetFAQRecords
Parts.SearchNaming = SearchNaming
Parts.SearchProviders = SearchProviders
function Parts.Bind3()
    SearchIndexBuild = Parts.SearchIndexBuild
end
