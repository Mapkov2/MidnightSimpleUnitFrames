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
local C_Timer = M.MenuTimer or _G.C_Timer
local Theme = M.Theme or {}

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

local function SearchAnchorOwnership(wrapper, anchor)
    if not (wrapper and anchor and anchor.GetTop) then return false, nil end
    local node = anchor
    while node do
        if node == wrapper then return true, nil end
        if node._msuf2PageOwnerWrapper == wrapper then
            local record = node._msuf2StickyPageHeaderRecord
            local fixedRoot = record and record.active and not record.disposed
                and record.section == node and node or nil
            return true, fixedRoot
        end
        node = node.GetParent and node:GetParent() or nil
    end
    return false, nil
end

local function FindSearchAnchor(pageKey, query, fallback, preferredAnchor)
    local entry = M.cache and M.cache[pageKey]
    local wrapper = entry and entry.wrapper
    if not wrapper then return nil end
    if SearchAnchorOwnership(wrapper, preferredAnchor) then return preferredAnchor end

    local candidates = {}
    CollectSearchAnchorCandidates(wrapper, candidates, 1)
    -- Fixed Editing/Preview panels live in the shared header host, outside the
    -- wrapper's physical child tree. Include the active page-owned stack in the
    -- same search pass so plain-text and exact-control routing stay equivalent.
    local headers = entry and entry.pageHeaders
    if type(headers) == "table" then
        for i = 1, #headers do
            local record = headers[i]
            if record and record.active and record.section then
                CollectSearchAnchorCandidates(record.section, candidates, 1)
            end
        end
    end

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

local function ResolveExactSearchAnchor(pageKey, exactTarget)
    if type(exactTarget) ~= "table" then return nil, nil end
    local sectionId = tostring(exactTarget.sectionId or "")
    if sectionId ~= "" then
        local entry = M.cache and M.cache[pageKey]
        local sections = entry and entry.sections
        local section = sections and sections[sectionId]
        local visible = section and section.IsVisible and section:IsVisible()
        if not visible and entry and type(entry._msuf2ResolveMissingSection) == "function" then
            -- Some pages (currently Colors) build selector-owned section groups
            -- lazily. Activate/materialize the declared exact section before
            -- resolving its runtime control; otherwise a changelog/search link
            -- can fail on a cold page or resolve a widget under a hidden group.
            entry._msuf2ResolveMissingSection(sectionId)
        end
    end
    local controlId = tostring(exactTarget.controlId or "")
    local catalog = M.RuntimeControlCatalog
    if controlId ~= "" then
        if not (catalog and type(catalog.ResolveExactTarget) == "function") then return nil, false, true end
        local _, widget = catalog.ResolveExactTarget(pageKey, exactTarget)
        if widget then return widget, true, true end
        return nil, false, true
    end
    local settingKey = tostring(exactTarget.settingKey or "")
    if settingKey == "" or not (catalog and type(catalog.FindBySettingKey) == "function") then return nil, false, false end
    local _, widget = catalog.FindBySettingKey(settingKey, pageKey, exactTarget)
    if widget then
        if type(widget._msuf2PrepareExactSearchTarget) == "function" then
            widget:_msuf2PrepareExactSearchTarget(exactTarget)
        end
        return widget, true, true
    end
    return nil, false, true
end

local function FindCurrentSearchAnchor(pageKey, query, fallback, preferredAnchor, exactTarget)
    local exactAnchor, exactMatched, exactRequired = ResolveExactSearchAnchor(pageKey, exactTarget)
    if exactMatched then
        local wrapper = M.cache and M.cache[pageKey] and M.cache[pageKey].wrapper
        if SearchAnchorOwnership(wrapper, exactAnchor) then return exactAnchor, true end
        return nil, false
    end
    if exactRequired then return nil, false end
    return FindSearchAnchor(pageKey, query, fallback, preferredAnchor), exactMatched
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

local function RegionDescendsFrom(region, ancestor)
    local node = region
    while node do
        if node == ancestor then return true end
        node = node.GetParent and node:GetParent() or nil
    end
    return false
end

local function FixedPreviewExpanderForAnchor(region)
    local node = region
    while node do
        local expander = node._msuf2FixedPreviewExpanderRecord
        if not expander then
            local header = node._msuf2FixedPagePreviewRecord or node._msuf2StickyPageHeaderRecord
            expander = header and header.previewExpander
        end
        if expander and not expander.disposed then return expander end
        node = node.GetParent and node:GetParent() or nil
    end
    return nil
end

local function OpenHiddenFixedPreviewAnchor(region)
    local expander = FixedPreviewExpanderForAnchor(region)
    if not expander or expander.expanded or type(expander.Open) ~= "function" then return false end
    if expander.button and RegionDescendsFrom(region, expander.button) then return false end

    -- Compact presentation deliberately hides secondary preview controls. Only
    -- expand for one of those hidden/clipped targets; visible title/chrome
    -- results keep the user's compact state intact.
    local hidden = false
    local node = region
    while node do
        if node.IsShown and not node:IsShown() then
            hidden = true
            break
        end
        if node == expander.section then break end
        node = node.GetParent and node:GetParent() or nil
    end
    local box = expander.box
    if not hidden and box and RegionDescendsFrom(region, box)
        and region.GetTop and region.GetBottom and box.GetTop and box.GetBottom
    then
        local top, bottom = region:GetTop(), region:GetBottom()
        local boxTop, boxBottom = box:GetTop(), box:GetBottom()
        if top and bottom and boxTop and boxBottom and (bottom > boxTop or top < boxBottom) then hidden = true end
    end
    if not hidden then return false end
    return expander:Open("SEARCH_FIXED_PREVIEW_TARGET") == true
end

local function ClampScrollOffset(offset)
    offset = math.max(0, tonumber(offset) or 0)
    local childH = (M.scrollChild and M.scrollChild.GetHeight and M.scrollChild:GetHeight()) or ContentHeight()
    local frameH = (M.scrollFrame and M.scrollFrame.GetHeight and M.scrollFrame:GetHeight()) or ContentHeight()
    local maxScroll = math.max(0, childH - frameH)
    if offset > maxScroll then offset = maxScroll end
    return offset
end

local SEARCH_ANCHOR_TOP_INSET = 44

local function SearchAnchorOffset(wrapper, region, topInset)
    if not (wrapper and region and wrapper.GetTop and region.GetTop) then return nil end
    local wrapperTop = wrapper:GetTop()
    local regionTop = region:GetTop()
    if not (wrapperTop and regionTop) then return nil end
    return ClampScrollOffset((wrapperTop - regionTop) - (tonumber(topInset) or SEARCH_ANCHOR_TOP_INSET))
end

local function HighlightSearchAnchor(wrapper, region, fixedRoot)
    local owner = fixedRoot or wrapper
    if not (owner and region and owner.GetTop and region.GetTop) then return end
    local ownerTop = owner:GetTop()
    local regionTop = region:GetTop()
    if not (ownerTop and regionTop) then return end

    local offset = math.max(0, ownerTop - regionTop)
    local highlight = owner._msuf2SearchHighlight
    if not highlight then
        highlight = CreateFrame("Frame", nil, owner)
        highlight:SetFrameLevel((owner.GetFrameLevel and owner:GetFrameLevel() or 1) + 40)
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
        if Theme.TrackMenuAnimationGroup then Theme.TrackMenuAnimationGroup(highlight._msuf2Anim) end
        local fade = highlight._msuf2Anim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetStartDelay(0.75)
        fade:SetDuration(0.75)
        highlight._msuf2Anim:SetScript("OnFinished", function()
            if highlight then highlight:Hide() end
        end)
        owner._msuf2SearchHighlight = highlight
    end
    if highlight._msuf2Anim and highlight._msuf2Anim.Stop then highlight._msuf2Anim:Stop() end
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", owner, "TOPLEFT", 8, -math.max(0, offset - 8))
    highlight:SetSize(math.max(220, (owner.GetWidth and owner:GetWidth() or ContentWidth()) - 28), 32)
    highlight:SetAlpha(1)
    highlight:Show()
    if highlight._msuf2Anim and highlight._msuf2Anim.Play then highlight._msuf2Anim:Play() end
end

local function RunSoon(fn)
    if SearchCombatLocked() then
        fn()
        return
    end
    C_Timer.After(0, fn)
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

local function SearchRouteHasWord(normalized, word)
    normalized, word = NormalizeSearchText(normalized), NormalizeSearchText(word)
    if normalized == "" or word == "" then return false end
    return (" " .. normalized .. " "):find(" " .. word .. " ", 1, true) ~= nil
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
advanced=text layer|advanced text|name layer|hp layer|power layer
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
statusGhostText=ghost|ghost text
statusAFKText=afk|afk text
statusAFKTimer=afk timer|afk duration|afk time
statusDNDText=dnd|dnd text|do not disturb
stance=stance|stance text|stance indicator|shapeshift form|warrior stance|druid form|paladin aura
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
statusAFKText=afk
statusAFKTimer=afk timer|afk duration
statusDNDText=dnd|do not disturb
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

local function SearchAuraStyleContainer(normalized)
    if SearchRouteHasAny(normalized, "dots on target|target dots|dot tracker") then return "targetDots" end
    if SearchRouteHasAny(normalized,
        "player defensive|player defensives|defensive buff|defensive buffs|defensive tracker")
    then
        return "playerDefensives"
    end
    for index = 1, 4 do
        if SearchRouteHasAny(normalized, "custom " .. index .. "|custom" .. index) then
            return "custom" .. index
        end
    end
    if SearchRouteHasAny(normalized, "custom aura|custom display|whitelist") then return "custom1" end
    if SearchRouteHasAny(normalized, "debuff|debuffs") then return "debuff" end
    if SearchRouteHasAny(normalized, "buff|buffs") then return "buff" end
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

local SEARCH_AURA_ROUTE_PAGES = KeySetFromWords "auras3 auras3_buffs auras3_debuffs auras3_custom auras3_rendering auras3_styling"

local SEARCH_ROUTE_SECTION_ROWS = {
    unit = [[
preview=preview|hide preview
auras=auras|aura|buff|buffs|debuff|debuffs|blacklist|whitelist|aura filter|custom aura
unit_dispel_overlay=unitframe dispel overlay|unit frame dispel overlay|dispel overlay
unit_dispel_symbol=unitframe dispel symbol|unit frame dispel symbol|dispel symbol
frame_basics=frame basics|enable|disable|width|height|scale|frame size|smooth fill|health animation
anchoring=anchoring|anchor|position|x offset|y offset|custom anchor|global anchor
text=text|name text|hp text|health text|power text|font size|text anchor|text position|text layer
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
portrait=portrait|class icon|2d portrait|avatar|face
text=text|name text|health text|hp text|power text|font size|text slot|delimiter|hide percent
power=resource bar|power bar|mana bar|role power|smooth fill|tank power|healer power|dps power
range=range fade|range check|distance check|out of range
layout=layout|growth|direction|spacing|columns|rows|width|height
sorting=sorting|sort|role order|player first|groups first
scaling=frame scaling|scale|smooth health fill|smooth fill|party smooth fill|raid smooth fill
border=transparency|alpha|opacity|fade
anchor=anchoring|anchor|position|move party|move raid|x offset|y offset
]],
    gf_bars = [[
dispel=dispel overlay|overlay style|overlay detects|overlay priority|health bar tint
dstripe=debuff stripe|stripe edge|stripe height|stripe opacity
]],
    gf_auras = [[
buffs=buffs|buff|hots|own buffs|healer buffs|buff position|buff size|buff layer
debuffs=debuffs|debuff|boss debuff|raid debuff|debuff position|debuff size|debuff layer
si=spell indicators|custom spell|spell id|indicator spell|healer hots indicators|placed spell icons
si_style=spell icon style|spell indicator style|spell icon zoom|spell icon scale|spell icon shape|spell icon opacity|spell icon tooltip|spell icon cooldown|spell icon swipe|spell icon duration bar|spell icon stack
]],
    gf_indicators = [[
indicators=indicators|focus glow|frame effects
sicons=status icons|status icon|dead icon|ghost text|offline icon|afk|dnd|ready check|summon|resurrect|phase|leader icon|assist icon|role icon|raid marker|advanced status|advanced x offset|advanced y offset|advanced placement|extended x offset|extended y offset
ci=corner indicators|corner dots|corner indicator|custom spell editor|slot assignments
]],
    gf_priority = [[
overview=priority frames|enable priority|disable priority|important players|priority group frames|priority party frames|duplicate party frames|duplicate raid frames|extra party frames|extra raid frames|dungeon priority frames
who_appears=pin player|pinned players|manual pins|automatic tanks|auto tanks|visible slots|hover hotkey|keybind|remove pin|clear pins
placement=priority placement|attach priority|right of group|left of group|above group|below group|right of party|left of party|right of raid|left of raid|free position|growth|spacing|attachment gap|alignment offset|priority mover|edit mode
]],
    profiles = [[
profiles_management=profile management|active profile|rename|copy profile|reset profile
profiles_specs=spec profiles|specialization|auto switch
profiles_io=export|import|wago|legacy import|profile string|backup|share profile
]],
    opt_bars = [[
bars_textures=textures|texture|gradient|bar texture|background texture
bars_absorb=absorb|heal prediction|incoming heals|shield
bars_outline=frame outline|outline|bar outline|border thickness|outline texture|border texture
bars_rounded=rounded|round corners|rounded texture|rounded frames
bars_highlight=highlight borders|highlight border|dispel border|dispel overlay|aggro border|purge border|boss target border|priority order
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
castbar_interrupt_ready=interrupt ready|demon hunter|devour|consume magic|disrupt|kick ready|unavailable fill|unavailable cast fill|kick unavailable|interrupt cooldown fill
]],
    opt_misc = [[
misc_language=language|locale|translation|localization|localisation
misc_menu_behavior=menu behavior|menu snap|edge snap|window snap|menu resize|navigation icons|nav icons|navigation symbols|nav symbols|navi symbole|navigationssymbole
misc_startup=startup|welcome|welcome message|version check|versioncheck|notices
misc_mouseover_highlight=mouseover highlight|hover highlight|hover gradient|hover border|highlight style|highlight size
misc_tooltips=tooltips|tooltip|unitframe tooltips|group frame tooltips|mouseover tooltip|modifier tooltip
misc_blizzard_frames=blizzard frames|default frames
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
    auras3_custom = [[
Displays=custom aura|custom display|new display|tracked aura|unitframe aura
Detection=spell id|spellid|exact spell|only mine|buff type|debuff type
Icon & Placement=icon|square|bar|number|hidden sensor|anchor|offset|layer|strata
Full-Frame Effect=full frame|health tint|border|glow|pulse|name overlay|effect strata|priority
]],
    auras3_default = [[
Aura Type=buffs|debuffs|buff|debuff|back|style
Unit Aura Text=stack size|cooldown size|stack anchor|timer text|unit aura text
Group Frame Styling=group frame aura style|stack font|cooldown font|cooldown swipe|tooltip|sort by duration|prefer player|aura behavior
]],
    opt_colors = [[
colors_font=global font color|font color
colors_classes=class bar colors|class color|class colored
colors_background=bar background tint|background color|backdrop|missing health|dark mode|preserve hp color
colors_appearance=unitframe global coloring|appearance|dark mode
colors_unit=unitframe colors|unit frame colors|reaction color
colors_npc_type=npc type colors|npc color
colors_bar_colors=bar colors|health color|hp color
colors_castbar=castbar colors|castbar color|spell color
colors_highlight=mouseover highlight color|hover highlight color|highlight colors
colors_gameplay=gameplay|crosshair|target sound
colors_power=power bar colors|power bar color|mana color|rage color|energy color|focus power|runic power|insanity color|fury color|pain color|essence color|astral power|lunar power|maelstrom color
colors_class_power=class power colors|combo point color|holy power color|soul shard|chi color|arcane charges|runes color|essence color|soul fragments|maelstrom weapon|astral power|eclipse|stagger|icicles|ebon might
colors_auras=auras|aura colors|buff color|debuff color|timer color|cooldown text color|stack color|own buff|own debuff|safe warning urgent|pandemic
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

local function SearchRoutePortraitTab(route, unit, normalized)
    if not SearchRouteHasAny(normalized, "portrait|class icon|avatar|face") then return end
    local tab
    if SearchRouteHasAny(normalized,
        "class portrait style|class icon|portrait background|cast spell icon|portraitclassstyle|portraitbgenabled|portraitcastspellicon")
    then
        tab = "advanced"
    elseif SearchRouteHasAny(normalized,
        "shape|border|square|circle|rounded|diamond|portraitshape|portraitborderstyle|portraitborderart|portraitborderdirection|portraitborderthickness|portraitfillborder")
    then
        tab = "border"
    elseif SearchRouteHasAny(normalized,
        "placement|detached|attach to frame|anchor point|overlay alignment|layer offset|portrait opacity|portraitplacement|portraitdetachedpoint|portraitdetachedto|portraitoverlayalign|portraitleveloffset|portraitalpha")
    then
        tab = "placement"
    elseif SearchRouteHasAny(normalized,
        "size override|width override|height override|portrait x|portrait y|portrait zoom|zoom center|portraitsizeoverride|portraitwidth|portraitheight|portraitoffsetx|portraitoffsety|portraitzoom|portraitpanx|portraitpany")
    then
        tab = "geometry"
    else
        tab = "general"
    end
    SearchRouteSetTable(route, "unitPortraitTabSelection", unit, tab)
end

local function SearchRouteUnitPage(route, pageKey, normalized)
    local unit = SEARCH_UNIT_BY_PAGE[pageKey]
    if not unit then return end
    if SearchTextKindForText(normalized) then SearchRouteOpenAccordion(route, pageKey, "text") end
    SearchRouteTextState(route, "unitTextTabSelection", "unitTextSlotSelection", unit, normalized)
    SearchRoutePortraitTab(route, unit, normalized)
    SearchRouteStatusTab(route, "unitStatusTabSelection", unit, normalized,
        "advanced status|status icon advanced|advanced x offset|advanced y offset|extended x offset|extended y offset|wide x offset|wide y offset",
        "status icons|status icon|indicator|level|raid group|group number|raid marker|leader|assist|elite|rare|dead|offline|combat icon|rested|incoming rez")
    SearchRouteUnitStatusSelection(route, unit, normalized)
    local auraQuery = SearchRouteHasAny(normalized,
        "aura|auras|buff|buffs|debuff|debuffs|defensive|defensives|dot|dots|blacklist|whitelist|filter|custom display|custom aura|spell id|style|appearance|pandemic|stack|cooldown|timer|duration|tooltip|opacity|icon zoom|icon shape|swipe|full frame|effect")
    if auraQuery then
        local container
        if SearchRouteHasAny(normalized, "dots on target|target dots|dot tracker") then container = "custom4" end
        if unit == "player" and SearchRouteHasAny(normalized,
            "defensive buff|defensive buffs|player defensive|player defensives|defensive tracker")
        then
            container = "custom4"
        end
        for index = 1, 4 do
            if SearchRouteHasAny(normalized, "custom " .. index .. "|custom" .. index) then container = "custom" .. index; break end
        end
        if not container and SearchRouteHasAny(normalized, "custom aura|custom display|whitelist") then container = "custom1" end
        if not container and SearchRouteHasAny(normalized, "debuff|debuffs") then container = "debuff" end
        if not container and SearchRouteHasAny(normalized, "buff|buffs") then container = "buff" end
        container = container or (type(M.unitAuraTabSelection) == "table" and M.unitAuraTabSelection[unit]) or "buff"
        local custom = tostring(container):match("^custom") ~= nil
        local tool
        if container == "custom4" then
            if SearchRouteHasAny(normalized,
                "style|appearance|pandemic|stack|cooldown|timer|duration|tooltip|opacity|icon zoom|icon shape|swipe|full frame|effect")
            then tool = "style"
            elseif SearchRouteHasAny(normalized, "layout|position|anchor|offset|size|strata")
                or SearchRouteHasWord(normalized, "layer")
            then tool = "layout"
            elseif unit == "player" and SearchRouteHasAny(normalized,
                "defensive|defensives|spell|track|list")
            then tool = "defensives"
            elseif SearchRouteHasAny(normalized, "dot|dots|spell|track|list") then tool = "dots"
            else tool = "setup" end
        elseif custom then
            if SearchRouteHasAny(normalized,
                "style|appearance|stack|cooldown|timer|duration|tooltip|opacity|icon zoom|icon shape|swipe|full frame|effect")
            then tool = "style"
            elseif SearchRouteHasAny(normalized, "whitelist|allow list|allowlist") then tool = "whitelist"
            elseif SearchRouteHasAny(normalized, "filter|only mine|hide permanent") then tool = "filters"
            -- `layer` must be a whole word: substring matching also finds it in
            -- `player`, which incorrectly routed "player custom aura setup" to
            -- the Layout workspace.
            elseif SearchRouteHasAny(normalized, "layout|position|anchor|offset|size|strata")
                or SearchRouteHasWord(normalized, "layer")
            then tool = "layout"
            else tool = "setup" end
        else
            if SearchRouteHasAny(normalized, "blacklist|ignore list|block list") then tool = "blacklist"
            elseif SearchRouteHasAny(normalized, "filter|only mine|dispellable|stealable|boss aura|hide permanent|no timer|no duration") then tool = "filters"
            elseif SearchRouteHasAny(normalized,
                "style|appearance|stack|cooldown|timer|duration|tooltip|opacity|icon zoom|icon shape|swipe|full frame|effect")
            then tool = "style"
            else tool = "layout" end
        end
        SearchRouteSetTable(route, "unitAuraTabSelection", unit, container)
        SearchRouteSetNestedTable(route, "unitAuraToolSelection", unit, container, tool)
    end
end

local function SearchRouteGroupPage(route, pageKey, normalized)
    local scope = pageKey ~= "gf_priority" and SearchGroupScopeForText(normalized) or nil
    if scope then SearchRouteSetState(route, "gfScope", scope) end
    if pageKey == "gf_layout" then
        if SearchTextKindForText(normalized) then SearchRouteOpenAccordion(route, pageKey, "text") end
        SearchRouteTextState(route, "gfTextTabSelection", "gfTextSlotSelection", scope or M.gfScope or "party", normalized)
        if SearchRouteHasAny(normalized, "portrait|class icon|2d portrait|avatar|face") then
            SearchRouteOpenAccordion(route, pageKey, "portrait")
            SearchRouteSetState(route, "gfScope", "party")
            SearchRoutePortraitTab(route, "gf_party", normalized)
        end
    elseif pageKey == "gf_indicators" then
        local tabScope = scope or M.gfScope or "party"
        SearchRouteStatusTab(route, "gfStatusIconTabSelection", tabScope, normalized,
            "advanced status|status icon advanced|advanced x offset|advanced y offset|advanced placement|extended x offset|extended y offset|layer",
            "status icons|status icon|ready check|summon|resurrect|phase|dead|ghost|offline|afk|dnd|leader icon|assist icon|role icon|raid marker")
        SearchRouteGroupStatusSelection(route, normalized)
        local cornerSlot = SearchFirstMatch(normalized, CORNER_SLOT_TERMS)
        if cornerSlot then SearchRouteSetState(route, "gfCornerSlotSelection", cornerSlot) end
    elseif pageKey == "gf_auras" and SearchRouteHasAny(normalized,
        "aura|auras|buff|buffs|debuff|debuffs|blacklist|filter|layout|position|anchor|growth|icon size|external defensive|external defensives|externals|layer|style|appearance|stack|cooldown|timer|duration|tooltip|opacity|icon zoom|icon shape|swipe")
    then
        local activeScope = scope or M.gfScope or "party"
        local lane = SearchRouteHasAny(normalized, "external defensives|external defensive|externals") and "externals"
            or (SearchRouteHasAny(normalized, "debuff|debuffs") and "debuff"
            or (SearchRouteHasAny(normalized, "buff|buffs") and "buff" or nil))
        lane = lane or (type(M.gfAuraLaneSelection) == "table" and M.gfAuraLaneSelection[activeScope]) or "buff"
        -- "Auto-blacklist from Buffs" is the External Defensive duplicate
        -- handling toggle on Layout, not an entry in the lane's blacklist.
        local externalAutoBlacklist = lane == "externals"
            and SearchRouteHasAny(normalized, "auto-blacklist from buffs|autoblacklist from buffs")
        local tool = not externalAutoBlacklist
            and SearchRouteHasAny(normalized, "blacklist|ignore list|block list") and "blacklist"
            or (SearchRouteHasAny(normalized, "filter|only mine|dispellable|stealable|boss aura|hide permanent|no timer|no duration") and "filters" or "layout")
        if tool == "layout" and SearchRouteHasAny(normalized,
            "style|appearance|stack|cooldown|timer|duration|tooltip|opacity|icon zoom|icon shape|swipe")
        then
            tool = "style"
        end
        SearchRouteSetTable(route, "gfAuraLaneSelection", activeScope, lane)
        SearchRouteSetNestedTable(route, "gfAuraToolSelection", activeScope, lane, tool)
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
        local container = SearchAuraStyleContainer(normalized)
        if pageKey == "auras3_buffs" then container = "buff"
        elseif pageKey == "auras3_debuffs" then container = "debuff" end
        -- Global Aura Style exposes four preview contexts. Reserved products
        -- are preview-only here; their Deep Style controls still route through
        -- the owning UnitFrame search records.
        if container ~= "buff" and container ~= "debuff"
            and container ~= "playerDefensives" and container ~= "targetDots"
        then
            container = nil
        end
        if container then
            SearchRouteSetState(route, "auraStyleContainer", container)
            SearchRouteSetState(route, "auraAppearanceContainer", container)
            if container == "buff" or container == "debuff" then
                SearchRouteSetState(route, "auraStyleGFLane", container)
            end
        end
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
        -- Exact Search/Assistant navigation resolves its control immediately
        -- after opening the page. Remember only the explicitly opened lazy
        -- sections so their page build can materialize those controls in the
        -- same call; ordinary cold page builds remain shell-only.
        M._msuf2SearchRouteOpenSections = M._msuf2SearchRouteOpenSections or {}
        for key, value in pairs(accordion) do
            if value == true then M._msuf2SearchRouteOpenSections[key] = true end
        end
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
local function ScrollToSearchAnchor(pageKey, query, fallback, preferredAnchor, exactTarget)
    if SearchCombatLocked() then return end
    if M.frame and M.frame.IsShown and not M.frame:IsShown() then return end
    if M.activeKey ~= pageKey then return end
    local entry = M.cache and M.cache[pageKey]
    local wrapper = entry and entry.wrapper
    if not wrapper then return end
    local region = FindCurrentSearchAnchor(pageKey, query, fallback, preferredAnchor, exactTarget)
    if not region then return end
    local opened = OpenAnchorCollapsibles(region)
    if OpenHiddenFixedPreviewAnchor(region) then opened = true end
    local reservedInset = SEARCH_ANCHOR_TOP_INSET
    local function finish()
        -- Zero-delay/0.05 callbacks can cross a combat transition or outlive
        -- the options window. Do no resolver, layout, scroll, or highlight
        -- work once either condition becomes true.
        if SearchCombatLocked() then return end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return end
        if M.activeKey ~= pageKey then return end
        local currentEntry = M.cache and M.cache[pageKey]
        wrapper = currentEntry and currentEntry.wrapper
        if not wrapper then return end
        region = FindCurrentSearchAnchor(pageKey, query, fallback, preferredAnchor, exactTarget)
        if not region then return end
        if OpenHiddenFixedPreviewAnchor(region) then
            RunSoon(finish)
            return
        end
        local _, fixedRoot = SearchAnchorOwnership(wrapper, region)
        if not fixedRoot then
            local offset = SearchAnchorOffset(wrapper, region, reservedInset)
            if offset and M.scrollFrame and M.scrollFrame.SetVerticalScroll then
                M.scrollFrame:SetVerticalScroll(offset)
            end
        end
        HighlightSearchAnchor(wrapper, region, fixedRoot)
    end
    if opened then RunSoon(finish) else finish() end
    -- Recheck on the existing bounded 0/0.05-second cycle so accordion growth
    -- and the structural fixed-header stack have both settled. The ScrollFrame
    -- already begins below that stack, so no preview-height inset is needed.
    RunSoon(finish)
    if not SearchCombatLocked() and C_Timer and C_Timer.After then C_Timer.After(0.05, finish) end
    return true
end
local function OpenSearchTarget(pageKey, query, fallback, preferredAnchor, route, exactTarget)
    if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
    local routingFallback = fallback
    if type(exactTarget) == "table" and type(exactTarget.settingKey) == "string" then
        routingFallback = tostring(fallback or "") .. " " .. exactTarget.settingKey
    end
    route = route or SearchRouteForTarget(pageKey, query, routingFallback)
    local routeChanged = ApplySearchRoute(pageKey, route)
    if routeChanged then preferredAnchor = nil end
    local selected = M.SelectPage(pageKey)
    local region, exactMatched
    if selected ~= false and M.activeKey == pageKey then
        local entry = M.cache and M.cache[pageKey]
        if entry and entry.wrapper then
            region, exactMatched = FindCurrentSearchAnchor(pageKey, query, fallback, preferredAnchor, exactTarget)
        end
    end
    RunSoon(function() ScrollToSearchAnchor(pageKey, query, fallback, preferredAnchor, exactTarget) end)
    return selected ~= false and M.activeKey == pageKey, region ~= nil, exactMatched
end

Search._RoutingAPI = {
    OpenSearchTarget = OpenSearchTarget,
    ScrollToSearchAnchor = ScrollToSearchAnchor,
    SearchRouteForTarget = SearchRouteForTarget,
    ApplySearchRoute = ApplySearchRoute,
}
