--- Shell/Menu2/Search/MSUF_Menu2_Search_Routing.lua
--- Search target routing, accordion state, and anchor scrolling.
---
--- Search routing is UI navigation only: it may expand sections and scroll to anchors, but it
--- should not change the setting value behind the matched control. Combat checks stay here so
--- routing does not try to focus protected edit-mode surfaces at unsafe times.
local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Search = M.Search or {}
M.Search = Search
local C = Search._RoutingContext or {}

M = C.M or M
local NormalizeSearchText = C.NormalizeSearchText
local BuildSearchQueryClauses = C.BuildSearchQueryClauses
local BuildSearchTokenList = C.BuildSearchTokenList
local SearchEditDistanceWithin = C.SearchEditDistanceWithin
local SearchCombatLocked = C.SearchCombatLocked
local ContentWidth = C.ContentWidth
local ContentHeight = C.ContentHeight
local DASHBOARD_ROUTE_RECOVERY = C.DASHBOARD_ROUTE_RECOVERY
local DASHBOARD_ROUTE_SCALING = C.DASHBOARD_ROUTE_SCALING
local DASHBOARD_ROUTE_CHANGELOG = C.DASHBOARD_ROUTE_CHANGELOG
local Lines = M.Lines or function(rows) return tostring(rows or ""):gmatch("[^\r\n]+") end
local KeySetFromWords = M.KeySetFromWords or function(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do out[word] = true end
    return out
end

if not (NormalizeSearchText and BuildSearchQueryClauses and BuildSearchTokenList and SearchEditDistanceWithin and SearchCombatLocked and ContentWidth and ContentHeight) then return end

local function ScoreAnchorTextClauses(normalized, queryNorm, clauses)
    -- Anchor scoring favors exact page-control text first, then prefix/contains/fuzzy matches.
    -- This keeps search useful for typos while still sending precise queries to the right row.
    if normalized == "" or type(clauses) ~= "table" or #clauses == 0 then return 0 end
    local score, matched = 0, 0
    if queryNorm ~= "" then
        if normalized == queryNorm then score = score + 900 end
        if normalized:find(queryNorm, 1, true) then score = score + 260 end
    end
    local tokens = BuildSearchTokenList(normalized)
    for i = 1, #clauses do
        local clause = clauses[i]
        local best = 0
        for k = 1, #clause.terms do
            local term = clause.terms[k]
            if normalized == term then
                best = math.max(best, 220)
            elseif normalized:sub(1, #term) == term then
                best = math.max(best, 130)
            elseif normalized:find(term, 1, true) then
                best = math.max(best, 70)
            elseif #term >= 5 and not term:find(" ", 1, true) then
                local maxDistance = (#term >= 8) and 2 or 1
                for t = 1, #tokens do
                    if math.abs(#tokens[t] - #term) <= maxDistance and SearchEditDistanceWithin(tokens[t], term, maxDistance) then
                        best = math.max(best, 24)
                        break
                    end
                end
            end
        end
        if best > 0 then
            score = score + best
            matched = matched + 1
        end
    end
    if matched == 0 then return 0 end
    if matched == #clauses then score = score + 180 else score = score - ((#clauses - matched) * 35) end
    if #normalized <= 42 then score = score + 30 end
    if #normalized > 120 then score = score - 40 end
    return score
end

local function ScoreAnchorText(text, query, fallback)
    local normalized = NormalizeSearchText(text)
    if normalized == "" then return 0 end
    local queryNorm, clauses = BuildSearchQueryClauses(query)
    local queryScore = ScoreAnchorTextClauses(normalized, queryNorm, clauses)

    local fallbackScore = 0
    if fallback and fallback ~= query then
        local fallbackNorm, fallbackClauses = BuildSearchQueryClauses(fallback)
        fallbackScore = ScoreAnchorTextClauses(normalized, fallbackNorm, fallbackClauses)
    end

    if queryScore > 0 and fallbackScore > 0 then
        return queryScore + math.floor(fallbackScore * 0.25)
    end
    return math.max(queryScore, math.floor(fallbackScore * 0.75))
end

local function CollectSearchAnchorCandidates(frame, out, depth)
    if not frame or depth > 16 then return end
    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
                local text = region:GetText()
                if text and text ~= "" then
                    out[#out + 1] = { region = region, text = text }
                end
            end
        end
    end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            CollectSearchAnchorCandidates(children[i], out, depth + 1)
        end
    end
end

local function FindSearchAnchor(pageKey, query, fallback, preferredAnchor)
    local entry = M.cache and M.cache[pageKey]
    local wrapper = entry and entry.wrapper
    if not wrapper then return nil end
    if preferredAnchor and preferredAnchor.GetTop then
        local node = preferredAnchor
        while node do
            if node == wrapper then return preferredAnchor end
            node = node.GetParent and node:GetParent() or nil
        end
    end

    local candidates = {}
    CollectSearchAnchorCandidates(wrapper, candidates, 1)

    local best, bestScore
    for i = 1, #candidates do
        local candidate = candidates[i]
        local score = ScoreAnchorText(candidate.text, query, fallback)
        if score > 0 and (not bestScore or score > bestScore) then
            best, bestScore = candidate, score
        end
    end
    return best and best.region or nil
end

local function OpenAnchorCollapsibles(region)
    local entries, seen = {}, {}
    local parent = region and region.GetParent and region:GetParent()
    while parent do
        local entry = parent._msuf2CollapsibleEntry
        if entry and not seen[entry] then
            seen[entry] = true
            entries[#entries + 1] = entry
        end
        parent = parent.GetParent and parent:GetParent() or nil
    end

    local opened = false
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry and not entry.open and entry.header and entry.header.Click then
            entry.header:Click()
            opened = true
        end
    end
    return opened
end

local function ClampScrollOffset(offset)
    offset = math.max(0, tonumber(offset) or 0)
    local childH = (M.scrollChild and M.scrollChild.GetHeight and M.scrollChild:GetHeight()) or ContentHeight()
    local frameH = (M.scrollFrame and M.scrollFrame.GetHeight and M.scrollFrame:GetHeight()) or ContentHeight()
    local maxScroll = math.max(0, childH - frameH)
    if offset > maxScroll then offset = maxScroll end
    return offset
end

local function SearchAnchorOffset(wrapper, region)
    if not (wrapper and region and wrapper.GetTop and region.GetTop) then return nil end
    local wrapperTop = wrapper:GetTop()
    local regionTop = region:GetTop()
    if not (wrapperTop and regionTop) then return nil end
    return ClampScrollOffset((wrapperTop - regionTop) - 42)
end

local function HighlightSearchAnchor(wrapper, region)
    if not (wrapper and region and wrapper.GetTop and region.GetTop) then return end
    local wrapperTop = wrapper:GetTop()
    local regionTop = region:GetTop()
    if not (wrapperTop and regionTop) then return end

    local offset = math.max(0, wrapperTop - regionTop)
    local highlight = wrapper._msuf2SearchHighlight
    if not highlight then
        highlight = CreateFrame("Frame", nil, wrapper)
        highlight:SetFrameLevel((wrapper.GetFrameLevel and wrapper:GetFrameLevel() or 1) + 40)
        local fill = highlight:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(0.20, 0.58, 1.00, 0.16)
        local top = highlight:CreateTexture(nil, "ARTWORK")
        top:SetHeight(1)
        top:SetPoint("TOPLEFT")
        top:SetPoint("TOPRIGHT")
        top:SetColorTexture(0.38, 0.78, 1.00, 0.65)
        local bottom = highlight:CreateTexture(nil, "ARTWORK")
        bottom:SetHeight(1)
        bottom:SetPoint("BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT")
        bottom:SetColorTexture(0.38, 0.78, 1.00, 0.45)
        highlight._msuf2Anim = highlight:CreateAnimationGroup()
        local fade = highlight._msuf2Anim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetStartDelay(0.75)
        fade:SetDuration(0.75)
        highlight._msuf2Anim:SetScript("OnFinished", function()
            if highlight then highlight:Hide() end
        end)
        wrapper._msuf2SearchHighlight = highlight
    end
    if highlight._msuf2Anim and highlight._msuf2Anim.Stop then highlight._msuf2Anim:Stop() end
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 8, -math.max(0, offset - 9))
    highlight:SetSize(math.max(220, (wrapper.GetWidth and wrapper:GetWidth() or ContentWidth()) - 28), 32)
    highlight:SetAlpha(1)
    highlight:Show()
    if highlight._msuf2Anim and highlight._msuf2Anim.Play then highlight._msuf2Anim:Play() end
end

local function RunSoon(fn)
    if SearchCombatLocked() then
        fn()
        return
    end
    _G.C_Timer.After(0, fn)
end

local function SearchRouteHasAny(normalized, terms)
    if normalized == "" then return false end
    if type(terms) == "string" then
        for rawTerm in terms:gmatch("[^|]+") do
            local term = NormalizeSearchText(rawTerm)
            if term ~= "" and normalized:find(term, 1, true) then return true end
        end
        return false
    end
    if type(terms) ~= "table" then return false end
    for i = 1, #terms do
        local term = NormalizeSearchText(terms[i])
        if term ~= "" and normalized:find(term, 1, true) then return true end
    end
    return false
end

local function SearchNewRoute()
    return { state = {}, accordion = {}, tables = {}, nestedTables = {}, general = {} }
end

local function TableHasValues(t, depth)
    if type(t) ~= "table" then return false end
    for _, v in pairs(t) do
        if not depth or depth <= 0 or type(v) ~= "table" then return true end
        if TableHasValues(v, depth - 1) then return true end
    end
    return false
end

local function SearchRouteIsEmpty(route)
    if type(route) ~= "table" then return true end
    return not (TableHasValues(route.state) or TableHasValues(route.accordion)
        or TableHasValues(route.general) or TableHasValues(route.tables, 1)
        or TableHasValues(route.nestedTables, 2))
end

local function RouteBucket(route, name)
    local bucket = route[name] or {}
    route[name] = bucket
    return bucket
end

local function SearchRouteOpenAccordion(route, pageKey, id)
    if not (route and pageKey and id) then return end
    RouteBucket(route, "accordion")[tostring(pageKey) .. ":" .. tostring(id)] = true
end

local function SearchRouteSetState(route, field, value)
    if not (route and field) then return end
    RouteBucket(route, "state")[field] = value
end

local function SearchRouteSetTable(route, tableName, key, value)
    if not (route and tableName and key ~= nil) then return end
    local tables = RouteBucket(route, "tables")
    tables[tableName] = tables[tableName] or {}
    tables[tableName][key] = value
end

local function SearchRouteSetNestedTable(route, tableName, key1, key2, value)
    if not (route and tableName and key1 ~= nil and key2 ~= nil) then return end
    local nestedTables = RouteBucket(route, "nestedTables")
    nestedTables[tableName] = nestedTables[tableName] or {}
    nestedTables[tableName][key1] = nestedTables[tableName][key1] or {}
    nestedTables[tableName][key1][key2] = value
end

local function SearchRouteSetGeneral(route, key, value)
    if not (route and key) then return end
    RouteBucket(route, "general")[key] = value
end

local function SearchRouteApplySectionSpecs(route, pageKey, normalized, specs)
    if not (route and pageKey and type(specs) == "table") then return end
    for i = 1, #specs do
        local spec = specs[i]
        local id = spec and (spec.id or spec[1])
        local terms = spec and (spec.terms or spec[2])
        if id and SearchRouteHasAny(normalized, terms) then
            SearchRouteOpenAccordion(route, pageKey, id)
        end
    end
end

local SECTION_ROW_CACHE = {}
local function SearchRouteApplySectionRows(route, pageKey, normalized, rows)
    local specs = SECTION_ROW_CACHE[rows]
    if not specs then
        specs = {}
        for line in Lines(rows) do
            local id, terms = line:match("^%s*([^=]+)=(.+)$")
            if id and terms then
                id = id:gsub("^%s+", ""):gsub("%s+$", "")
                specs[#specs + 1] = { id, terms }
            end
        end
        SECTION_ROW_CACHE[rows] = specs
    end
    SearchRouteApplySectionSpecs(route, pageKey, normalized, specs)
end

local function SearchFirstMatch(normalized, specs)
    for i = 1, #(specs or {}) do
        local spec = specs[i]
        if SearchRouteHasAny(normalized, spec[2]) then return spec[1] end
    end
end

local function SearchTermRows(text)
    local rows = {}
    local function Value(v)
        if v == "true" then return true end
        if v == "false" then return false end
        return v
    end
    for line in Lines(text) do
        local first, rest = line:match("^([^=]+)=(.*)$")
        if first then
            local second, third = rest:match("^([^=]*)=(.*)$")
            rows[#rows + 1] = { Value(first), second or rest, third }
        end
    end
    return rows
end

local GROUP_SCOPE_TERMS = SearchTermRows [[
mythicraid=mythic raid|mythicraid|mythic
raid=raid|raids
party=party|group|groups
]]

local GLOBAL_SCOPE_TERMS = SearchTermRows [[
shared=shared scope|shared style|global scope|global style|baseline
gf_raid=raid frame|raid frames|raid unit|raid units|raid font|raid fonts|raid texture|raid textures|raid health|raid text|raid power|raid bar|raid bars
gf_party=party frame|party frames|party unit|party units|party font|party fonts|party texture|party textures|party health|party text|party power|party bar|party bars|group frame|group frames|group font|group text
targettarget=target of target|targettarget|target target|tot frame|tot font|tot text|tot bar
focustarget=focus target|focustarget|focus target frame|focus target font|focus target text|focus target bar
player=player frame|player unit|player font|player text|player health|player power|player bar|player bars
target=target frame|target unit|target font|target text|target health|target power|target bar|target bars
focus=focus frame|focus unit|focus font|focus text|focus health|focus power|focus bar|focus bars
pet=pet frame|pet unit|pet font|pet text|pet health|pet power|pet bar|pet bars
boss=boss frame|boss frames|boss unit|boss units|boss font|boss text|boss health|boss power|boss bar|boss bars
]]

local TEXT_KIND_TERMS = SearchTermRows [[
hp=hp text|health text|hp slot|health slot|show hp|percent hp|hp percent|left hp|center hp|right hp|hp left|hp center|hp right|left health|center health|right health|health left|health center|health right
power=power text|power slot|mana text|energy text|rage text|show power|left power|center power|right power|power left|power center|power right
advanced=text layer|draw order|advanced text|name layer|hp layer|power layer
name=name text|show name|name position|name anchor|raid group name|left name|center name|right name
]]

local TEXT_SLOT_TERMS = SearchTermRows [[
left=left slot|slot left|left hp|left health|left power|hp left|health left|power left
right=right slot|slot right|right hp|right health|right power|hp right|health right|power right
center=center slot|middle slot|slot center|slot middle|center hp|middle hp|center health|center power|middle power|hp center|power center
]]

local function SearchGroupScopeForText(normalized) return SearchFirstMatch(normalized, GROUP_SCOPE_TERMS) end
local function SearchGlobalScopeForText(normalized) return SearchFirstMatch(normalized, GLOBAL_SCOPE_TERMS) end
local function SearchTextKindForText(normalized) return SearchFirstMatch(normalized, TEXT_KIND_TERMS) end
local function SearchTextSlotForText(normalized) return SearchFirstMatch(normalized, TEXT_SLOT_TERMS) end

local function SearchRouteTextState(route, tabTable, slotTable, scopeKey, normalized)
    local textKind = SearchTextKindForText(normalized)
    if not textKind then return end
    SearchRouteSetTable(route, tabTable, scopeKey, textKind)
    if textKind == "hp" or textKind == "power" then
        local slot = SearchTextSlotForText(normalized)
        if slot then SearchRouteSetNestedTable(route, slotTable, scopeKey, textKind, slot) end
    end
end

local UNIT_STATUS_TERMS = SearchTermRows [[
statusIncomingRes=incoming rez|incoming res|incoming resurrect|incoming resurrection|ress|resurrect
statusPvp=pvp|pvp flag|pvp icon|pvp indicator|pvp status|war mode|flagged
statusResting=rested|resting|rest icon
statusCombat=combat icon|combat state|in combat icon
statusText=dead text|dead status|offline text|status text
eliteicon=elite|rare|elite icon|rare icon
raidgroupname=raid group|group number|subgroup
level=level|level text|level indicator
raidmarker=raid marker|marker
leader=leader|assist|leader assist|leader / assist
]]

local GROUP_STATUS_TERMS = SearchTermRows [[
readyCheckIcon=ready check
summonIcon=summon|summoning
resurrectIcon=resurrect|resurrection|rez|ress
pvpIcon=pvp|pvp flag|pvp icon|pvp indicator|pvp status|war mode|flagged
phaseIcon=phase|phased
statusGhostText=ghost
leaderIcon=leader
assistIcon=assist
raidMarker=raid marker|marker
statusText=dead|offline
statusAFKText=afk|dnd
roleIcon=role icon|tank|healer|dps
]]

local POWER_COLOR_TERMS = SearchTermRows [[
RAGE=rage
ENERGY=energy
FOCUS=focus power|hunter focus
RUNIC_POWER=runic power
INSANITY=insanity
FURY=fury
PAIN=pain
ESSENCE=essence
LUNAR_POWER=astral power|lunar power
MAELSTROM=maelstrom
MANA=mana
]]

local CLASS_POWER_TERMS = SearchTermRows [[
HOLY_POWER=holy power
SOUL_SHARDS=soul shards|soul shard
CHI=chi
ARCANE_CHARGES=arcane charges|arcane charge
RUNES=runes
CHARGED=empowered|charged
SOUL_FRAGMENTS_VENG=soul fragments vengeance|vengeance fragments
SOUL_FRAGMENTS_META=soul fragments void|void meta
SOUL_FRAGMENTS=soul fragments|soul fragment
MAELSTROM_ABOVE_5=maelstrom weapon 5
MAELSTROM=maelstrom weapon
AP_PREDICTION=astral prediction
ASTRAL_POWER=astral power
ECLIPSE_SOLAR=solar eclipse|eclipse solar
ECLIPSE_LUNAR=lunar eclipse|eclipse lunar
ECLIPSE_CA=celestial alignment
STAGGER_GREEN=stagger light|green stagger
STAGGER_YELLOW=stagger moderate|yellow stagger
STAGGER_RED=stagger heavy|red stagger
INSANITY=insanity
MAELSTROM_POWER=maelstrom power
WHIRLWIND=whirlwind
TIP_OF_THE_SPEAR=tip of the spear
ICICLES=icicles
EBON_MIGHT=ebon might
RESOURCE_TEXT=resource text
ESSENCE=essence
COMBO_POINTS=combo points|combo point
]]

local CORNER_SLOT_TERMS = SearchTermRows [[
TL=top left|tl
TR=top right|tr
BL=bottom left|bl
BR=bottom right|br
C=center|middle
]]

local PROFILE_EXPORT_TERMS = SearchTermRows [[
unitframe=export unitframe|export unitframes|unitframe export|unitframes export
castbar=export castbar|export castbars|castbar export|castbars export
colors=export colors|export colours|colors export|colours export
gameplay=export gameplay|gameplay export
groupframe=export group|export group frames|group frames export|groupframe export
all=full profile|export full|full export|complete profile
]]

local PROFILE_IMPORT_TERMS = SearchTermRows [[
true=import create new|import new profile|create new profile|import and create new profile
false=import current profile|import to current|current profile import
]]

local AURA_SCOPE_TERMS = SearchTermRows [[
player=player
target=target
focus=focus
boss=boss
party=party=party
raid=raid|mythic=raid
shared=shared|global
]]

local DASHBOARD_ROUTE_TERMS = {
    { DASHBOARD_ROUTE_RECOVERY, "discord|factory reset|fullreset|print help|display recovery|recovery tools|recover menu|reset all|help reset|copy discord|support discord" },
    { DASHBOARD_ROUTE_SCALING, "scaling|ui scale|menu scale|msuf frame scale|msuf menu scale|make menu bigger|make menu smaller|options too big|options too small|resize window|groesser|kleiner|skalierung" },
    { DASHBOARD_ROUTE_CHANGELOG, "changelog|change log|release notes|patch notes|version notes|what changed|latest changes|aenderungen|anderungen" },
}

local function SearchRouteUnitStatusSelection(route, unit, normalized)
    local value = SearchFirstMatch(normalized, UNIT_STATUS_TERMS)
    if value then SearchRouteSetTable(route, "unitStatusSelection", unit, value) end
end

local function SearchRouteGroupStatusSelection(route, normalized)
    local value = SearchFirstMatch(normalized, GROUP_STATUS_TERMS)
    if value then SearchRouteSetState(route, "gfStatusIconSelection", value) end
end

local function SearchPowerColorTokenForText(normalized) return SearchFirstMatch(normalized, POWER_COLOR_TERMS) end
local function SearchClassPowerTokenForText(normalized) return SearchFirstMatch(normalized, CLASS_POWER_TERMS) end

local function SearchRouteAuraScope(route, normalized)
    for i = 1, #AURA_SCOPE_TERMS do
        local spec = AURA_SCOPE_TERMS[i]
        if SearchRouteHasAny(normalized, spec[2]) then
            SearchRouteSetState(route, "auraScope", spec[1])
            if spec[3] then SearchRouteSetState(route, "auraStyleGFScope", spec[3]) end
            return
        end
    end
end

local SEARCH_UNIT_BY_PAGE = {
    uf_player = "player",
    uf_target = "target",
    uf_targettarget = "targettarget",
    uf_focustarget = "focustarget",
    uf_focus = "focus",
    uf_pet = "pet",
    uf_boss = "boss",
}

local SEARCH_AURA_ROUTE_PAGES = KeySetFromWords "auras3 auras3_buffs auras3_debuffs auras3_rendering auras3_styling"

local SEARCH_ROUTE_SECTION_ROWS = {
    unit = [[
preview=preview|hide preview
frame_basics=frame basics|enable|disable|width|height|scale|frame size|smooth fill|health animation
anchoring=anchoring|anchor|position|x offset|y offset|custom anchor|global anchor
text=text|name text|hp text|health text|power text|font size|text anchor|text position|draw order|text layer
inline_text=inline text|inline color|target of target text|tot text|tot color|npc color|npc type color
transparency=transparency|transparent|alpha|opacity|fade|in combat alpha|out of combat alpha
portrait=portrait|class icon|2d portrait|3d portrait|avatar|face
power_bar=power bar|mana bar|energy bar|rage bar|power height|power smooth fill
castbar=castbar|cast bar|spell name|cast icon|cast time
status_icons=status icons|status icon|indicator|level|level text|raid group|group number|raid marker|leader|assist|elite|rare|dead|offline|combat icon|rested|incoming rez|advanced status|advanced x offset|advanced y offset|extended x offset|extended y offset
load_conditions=load conditions|visibility conditions|show conditions|hide conditions|when to show|when to hide
boss_layout=boss layout|boss preview|boss frames
]],
    gf_layout = [[
general=general|enable|disable|turn off|off|hide group frames|hide raid frames|hide party frames|group frames off|raid frames off|party frames off|use msuf group frames|show player|show solo|solo|visibility|party frames not showing|raid frames not showing|ausschalten|deaktivieren|ausblenden
layout=layout|growth|direction|spacing|columns|rows|width|height
sorting=sorting|sort|role order|player first|groups first
scaling=frame scaling|scale|smooth health fill|smooth fill|party smooth fill|raid smooth fill
border=transparency|alpha|opacity|fade
anchor=anchoring|anchor|position|move party|move raid|x offset|y offset
]],
    gf_bars = [[
hcolor=health colors|health color|class color|hp color
bars=bars custom|health bar|bar texture|bar height
power=power bar|mana bar|power text|smooth fill
text=text|name text|health text|hp text|power text|font size
dispel=dispel overlay|overlay style|overlay detects|overlay priority|health bar tint
dstripe=debuff stripe|stripe edge|stripe height|stripe opacity
range=range fade|range check|distance check|out of range
]],
    gf_auras = [[
buffs=buffs|buff|hots|own buffs|healer buffs|buff position|buff size|buff layer
debuffs=debuffs|debuff|boss debuff|raid debuff|debuff position|debuff size|debuff layer
]],
    gf_indicators = [[
indicators=indicators|spell indicators|placed indicators|focus glow|frame effects
sicons=status icons|status icon|dead icon|ghost text|offline icon|afk|dnd|ready check|summon|resurrect|phase|leader icon|assist icon|role icon|raid marker|advanced status|advanced x offset|advanced y offset|advanced placement|extended x offset|extended y offset
si=spell indicators|custom spell|spell id|indicator spell|healer hots indicators
ci=corner indicators|corner dots|corner indicator|custom spell editor|slot assignments
]],
    profiles = [[
profiles_management=profile management|active profile|rename|copy profile|reset profile
profiles_specs=spec profiles|specialization|auto switch
profiles_io=export|import|wago|legacy import|profile string|backup|share profile
]],
    opt_bars = [[
bars_textures=textures|texture|gradient|bar texture|background texture
bars_absorb=absorb|heal prediction|incoming heals|shield
bars_outline=frame outline|outline|bar outline|border thickness
bars_rounded=rounded|round corners|rounded texture|rounded frames
bars_highlight=highlight borders|highlight border|dispel border|dispel overlay|aggro border|purge border|boss target border|priority order
bars_unit_dispel_overlay=unitframe dispel overlay|unit frame dispel overlay|overlay detects|overlay priority|unit dispel overlay
bars_power=bar animation|text accuracy|smooth fill|power animation
]],
    opt_fonts = [[
fonts_global_font=global font|font family|font|font dropdown|sharedmedia|change font|change fonts|where to change font|where change font
fonts_text_style=text style|outline|shadow|font size
fonts_name_power_colors=name colors|power colors|name color|power color
fonts_name_shortening=name shortening|short names|realm names|truncate|names too long
]],
    opt_castbar = [[
castbar_behavior=shake|fill direction|castbar direction|castbar behavior
castbar_textures=textures|texture|outline|castbar texture
castbar_empowered=empowered casts|evoker|empower|stage blink|hold cast|release cast
castbar_name_shortening=name shortening|spell name|cast name|max name length
castbar_focus_kick=focus kick|target kick|interrupt focus|kick cooldown
castbar_interrupt_ready=interrupt ready|demon hunter|devour|consume magic|disrupt|kick ready
]],
    opt_misc = [[
misc_language=language|locale|translation|localization|localisation
misc_menu_behavior=menu behavior|menu snap|edge snap|window snap|menu resize
misc_startup=startup|welcome|welcome message|version check|versioncheck|notices
misc_tooltips=tooltips|tooltip|unitframe tooltips|group frame tooltips|mouseover tooltip|modifier tooltip
misc_blizzard_frames=blizzard frames|default frames|hide blizzard|disable blizzard
misc_range_fade=range fade|range check|distance check|out of range
]],
    classpower = [[
classpower_display=layout|display|combo points|holy power|soul shards|chi|essence|runes
classpower_behavior=behavior|prediction|quick actions
classpower_visuals=style|visual|texture|spacing|colors
classpower_visibility=auto hide|visibility|hide empty
classpower_detached_power=detached power|detached power bar|alternate power|dual resource
classpower_player_hp=player hp bar|second player hp bar|duplicate hp|duplicate health|class resource hp|class resources hp|shared hp text|smooth fill|hp shape|follow player power|orb size|hp orb|health orb|hp color|class color|dark mode|hp gradient
classpower_alt_mana=alternative mana|alt mana|mana bar
]],
    auras3_filters = [[
Filter Rules=filters|inclusive filter|exclusive filter|only mine|own buffs|own debuffs|dispellable|stealable|buff filter|debuff filter
Blacklist=blacklist|ignore list|spell id|blacklist presets
Group Frame Filters=inclusive filter|exclusive filter|base filter|category blacklist|declassified
]],
    auras3_default = [[
Aura Type=buffs|debuffs|buff|debuff|back|style
Unit Aura Text=stack size|cooldown size|stack anchor|timer text|unit aura text
Group Frame Styling=group frame aura style|stack font|cooldown font|cooldown swipe|tooltip|sort by duration|prefer player|aura behavior
Colors=timer color|cooldown text color|stack color|own buff|own debuff|safe warning urgent
]],
    opt_colors = [[
colors_font=global font color|font color
colors_classes=class bar colors|class color|class colored
colors_background=bar background tint|background color|backdrop|missing health|dark mode|preserve hp color
colors_appearance=unitframe global coloring|appearance|dark mode
colors_unit=unitframe colors|unit frame colors|reaction color
colors_npc_type=npc type colors|npc color
colors_bar_colors=bar colors|health color|hp color
colors_dispel=dispel|magic color|curse color|poison color|disease color
colors_castbar=castbar colors|castbar color|spell color
colors_highlight=mouseover highlight|hover highlight
colors_gameplay=gameplay|crosshair|target sound
colors_power=power bar colors|power bar color|mana color|rage color|energy color|focus power|runic power|insanity color|fury color|pain color|essence color|astral power|lunar power|maelstrom color
colors_class_power=class power colors|combo point color|holy power color|soul shard|chi color|arcane charges|runes color|essence color|soul fragments|maelstrom weapon|astral power|eclipse|stagger|icicles|ebon might
colors_auras=auras|buff color|debuff color
colors_portrait=portrait colors|portrait color
]],
    gameplay = [[
gameplay_timer=combat timer|timer
gameplay_state=combat enter|combat leave|enter combat|leave combat
gameplay_class_specific=class-specific|class specific|demon hunter|interrupt|devour
gameplay_crosshair=combat crosshair|crosshair|targeting|mouse
]],
}

local function SearchRouteApplyPageRows(route, pageKey, normalized)
    local rows = SEARCH_ROUTE_SECTION_ROWS[SEARCH_UNIT_BY_PAGE[pageKey] and "unit" or pageKey]
        or (SEARCH_AURA_ROUTE_PAGES[pageKey] and SEARCH_ROUTE_SECTION_ROWS.auras3_default)
    if rows then SearchRouteApplySectionRows(route, pageKey, normalized, rows) end
end

local function SearchRouteStatusTab(route, tableName, scope, normalized, advancedTerms, basicTerms)
    local value = SearchRouteHasAny(normalized, advancedTerms) and "advanced" or (SearchRouteHasAny(normalized, basicTerms) and "basic" or nil)
    if value then SearchRouteSetTable(route, tableName, scope, value) end
end

local function SearchRouteUnitPage(route, pageKey, normalized)
    local unit = SEARCH_UNIT_BY_PAGE[pageKey]
    if not unit then return end
    if SearchTextKindForText(normalized) then SearchRouteOpenAccordion(route, pageKey, "text") end
    SearchRouteTextState(route, "unitTextTabSelection", "unitTextSlotSelection", unit, normalized)
    SearchRouteStatusTab(route, "unitStatusTabSelection", unit, normalized,
        "advanced status|status icon advanced|advanced x offset|advanced y offset|extended x offset|extended y offset|wide x offset|wide y offset",
        "status icons|status icon|indicator|level|raid group|group number|raid marker|leader|assist|elite|rare|dead|offline|combat icon|rested|incoming rez")
    SearchRouteUnitStatusSelection(route, unit, normalized)
end

local function SearchRouteGroupPage(route, pageKey, normalized)
    local scope = SearchGroupScopeForText(normalized)
    if scope then SearchRouteSetState(route, "gfScope", scope) end
    if pageKey == "gf_bars" then
        if SearchTextKindForText(normalized) then SearchRouteOpenAccordion(route, pageKey, "text") end
        SearchRouteTextState(route, "gfTextTabSelection", "gfTextSlotSelection", scope or M.gfScope or "party", normalized)
    elseif pageKey == "gf_indicators" then
        local tabScope = scope or M.gfScope or "party"
        SearchRouteStatusTab(route, "gfStatusIconTabSelection", tabScope, normalized,
            "advanced status|status icon advanced|advanced x offset|advanced y offset|advanced placement|extended x offset|extended y offset|draw order",
            "status icons|status icon|ready check|summon|resurrect|phase|dead|ghost|offline|afk|dnd|leader icon|assist icon|role icon|raid marker")
        SearchRouteGroupStatusSelection(route, normalized)
        local cornerSlot = SearchFirstMatch(normalized, CORNER_SLOT_TERMS)
        if cornerSlot then SearchRouteSetState(route, "gfCornerSlotSelection", cornerSlot) end
    end
end

local function SearchRouteGlobalPage(route, pageKey, normalized)
    if pageKey == "profiles" then
        local exportKind = SearchFirstMatch(normalized, PROFILE_EXPORT_TERMS)
        if exportKind then SearchRouteSetState(route, "profileExportKind", exportKind) end
        local importCreateNew = SearchFirstMatch(normalized, PROFILE_IMPORT_TERMS)
        if importCreateNew ~= nil then SearchRouteSetState(route, "profileImportCreateNew", importCreateNew) end
    elseif pageKey == "modules" then
        SearchRouteOpenAccordion(route, pageKey, "modules_style")
    elseif pageKey == "opt_bars" then
        local scope = SearchGlobalScopeForText(normalized)
        if scope then SearchRouteSetGeneral(route, "hpPowerTextSelectedKey", scope) end
    elseif pageKey == "opt_fonts" then
        local scope = SearchGlobalScopeForText(normalized)
        if scope then SearchRouteSetGeneral(route, "_fontScopeKey", scope) end
        if not scope and SearchRouteHasAny(normalized, "font|fonts|global font|font family|font dropdown|sharedmedia|change font|change fonts|where to change font|where change font|schriftart|schriftart aendern|schrift aendern") then
            SearchRouteSetGeneral(route, "_fontScopeKey", "shared")
        end
    elseif SEARCH_AURA_ROUTE_PAGES[pageKey] then
        SearchRouteAuraScope(route, normalized)
    elseif pageKey == "opt_colors" then
        local powerToken = SearchPowerColorTokenForText(normalized)
        if powerToken then SearchRouteSetState(route, "colorsPowerToken", powerToken) end
        local classPowerToken = SearchClassPowerTokenForText(normalized)
        if classPowerToken then SearchRouteSetState(route, "colorsCPToken", classPowerToken) end
        if powerToken or (SearchRouteHasAny(normalized, "power color|power colors") and not classPowerToken) then
            SearchRouteOpenAccordion(route, pageKey, "colors_power")
        end
        if classPowerToken then SearchRouteOpenAccordion(route, pageKey, "colors_class_power") end
    end
end
local function SearchRouteForTarget(pageKey, query, fallback)
    local normalized = NormalizeSearchText((query or "") .. " " .. (fallback or ""))
    if normalized == "" then return nil end
    if pageKey == "home" then
        return SearchFirstMatch(normalized, DASHBOARD_ROUTE_TERMS)
    end
    local route = SearchNewRoute()
    SearchRouteApplyPageRows(route, pageKey, normalized)
    SearchRouteUnitPage(route, pageKey, normalized)
    SearchRouteGroupPage(route, pageKey, normalized)
    SearchRouteGlobalPage(route, pageKey, normalized)
    return SearchRouteIsEmpty(route) and nil or route
end

local function ApplyRouteValues(target, values, setter)
    if type(target) ~= "table" or type(values) ~= "table" then return false end
    local changed = false
    for key, value in pairs(values) do
        if target[key] ~= value then
            if setter then setter(key, value) else target[key] = value end
            changed = true
        end
    end
    return changed
end

local function ApplySearchRoute(pageKey, route)
    if type(route) ~= "table" then return false end
    local changed = false
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local state = route.state
    if type(state) == "table" then
        changed = ApplyRouteValues(M, state, M.SetMenuStateValue) or changed
    end
    local accordion = route.accordion
    if type(accordion) == "table" then
        local target
        if type(M.GetPersistentMenuStateTable) == "function" then
            target = M.GetPersistentMenuStateTable("accordionState")
        end
        if type(target) ~= "table" then
            M.accordionState = M.accordionState or {}
            target = M.accordionState
        end
        local normalizedAccordion = {}
        for key, value in pairs(accordion) do normalizedAccordion[key] = value and true or false end
        if ApplyRouteValues(target, normalizedAccordion) then
            changed = true
        end
    end
    local tables = route.tables
    if type(tables) == "table" then
        for tableName, values in pairs(tables) do
            if type(tableName) == "string" and type(values) == "table" then
                local target = M[tableName]
                if type(target) ~= "table" then
                    target = {}
                    M[tableName] = target
                end
                if ApplyRouteValues(target, values) then changed = true end
            end
        end
    end
    local nestedTables = route.nestedTables
    if type(nestedTables) == "table" then
        for tableName, firstLevel in pairs(nestedTables) do
            if type(tableName) == "string" and type(firstLevel) == "table" then
                local target = M[tableName]
                if type(target) ~= "table" then
                    target = {}
                    M[tableName] = target
                end
                for key1, secondLevel in pairs(firstLevel) do
                    if type(secondLevel) == "table" then
                        local nested = target[key1]
                        if type(nested) ~= "table" then
                            nested = {}
                            target[key1] = nested
                            changed = true
                        end
                        for key2, value in pairs(secondLevel) do
                            if nested[key2] ~= value then
                                nested[key2] = value
                                changed = true
                            end
                        end
                    end
                end
            end
        end
    end
    local general = route.general
    if type(general) == "table" then
        local db
        if type(M.GetGeneralDB) == "function" then
            db = M.GetGeneralDB()
        elseif type(M.EnsureDB) == "function" then
            local root = M.EnsureDB()
            if type(root) == "table" then
                root.general = type(root.general) == "table" and root.general or {}
                db = root.general
            end
        end
        if type(db) ~= "table" then
            ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
            _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
            db = _G.MSUF_DB.general
        end
        if ApplyRouteValues(db, general) then changed = true end
    end
    if changed and pageKey and type(M.InvalidatePage) == "function" then
        M.InvalidatePage(pageKey)
    end
    return changed
end
local function ScrollToSearchAnchor(pageKey, query, fallback, preferredAnchor)
    if M.activeKey ~= pageKey then return end
    local entry = M.cache and M.cache[pageKey]
    local wrapper = entry and entry.wrapper
    if not wrapper then return end
    local region = FindSearchAnchor(pageKey, query, fallback, preferredAnchor)
    if not region then return end
    local opened = OpenAnchorCollapsibles(region)
    local function finish()
        local offset = SearchAnchorOffset(wrapper, region)
        if offset and M.scrollFrame and M.scrollFrame.SetVerticalScroll then
            M.scrollFrame:SetVerticalScroll(offset)
        end
        HighlightSearchAnchor(wrapper, region)
    end
    if opened then RunSoon(finish) else finish() end
end
local function OpenSearchTarget(pageKey, query, fallback, preferredAnchor, route)
    if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
    route = route or SearchRouteForTarget(pageKey, query, fallback)
    local routeChanged = ApplySearchRoute(pageKey, route)
    if routeChanged then preferredAnchor = nil end
    M.SelectPage(pageKey)
    RunSoon(function() ScrollToSearchAnchor(pageKey, query, fallback, preferredAnchor) end)
end

Search._RoutingAPI = {
    OpenSearchTarget = OpenSearchTarget,
    ScrollToSearchAnchor = ScrollToSearchAnchor,
    SearchRouteForTarget = SearchRouteForTarget,
    ApplySearchRoute = ApplySearchRoute,
}
