--- Menu2/Search/MSUF_Menu2_Search_Routing.lua
--- Search target routing, accordion state, and anchor scrolling.
local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

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

if not (NormalizeSearchText and BuildSearchQueryClauses and BuildSearchTokenList and SearchEditDistanceWithin and SearchCombatLocked and ContentWidth and ContentHeight) then return end

local function ScoreAnchorTextClauses(normalized, queryNorm, clauses)
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
    if preferredAnchor and preferredAnchor.GetTop then return preferredAnchor end

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
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, fn)
    else
        fn()
    end
end

local function SearchRouteHasAny(normalized, terms)
    if normalized == "" or type(terms) ~= "table" then return false end
    for i = 1, #terms do
        local term = NormalizeSearchText(terms[i])
        if term ~= "" and normalized:find(term, 1, true) then return true end
    end
    return false
end

local function SearchNewRoute()
    return { state = {}, accordion = {}, tables = {}, nestedTables = {}, general = {} }
end

local function SearchRouteIsEmpty(route)
    if type(route) ~= "table" then return true end
    for _ in pairs(route.state or {}) do return false end
    for _ in pairs(route.accordion or {}) do return false end
    for _ in pairs(route.general or {}) do return false end
    for _, values in pairs(route.tables or {}) do
        if type(values) == "table" then
            for _ in pairs(values) do return false end
        end
    end
    for _, firstLevel in pairs(route.nestedTables or {}) do
        if type(firstLevel) == "table" then
            for _, secondLevel in pairs(firstLevel) do
                if type(secondLevel) == "table" then
                    for _ in pairs(secondLevel) do return false end
                end
            end
        end
    end
    return true
end

local function SearchRouteOpenAccordion(route, pageKey, id)
    if not (route and pageKey and id) then return end
    route.accordion = route.accordion or {}
    route.accordion[tostring(pageKey) .. ":" .. tostring(id)] = true
end

local function SearchRouteSetState(route, field, value)
    if not (route and field) then return end
    route.state = route.state or {}
    route.state[field] = value
end

local function SearchRouteSetTable(route, tableName, key, value)
    if not (route and tableName and key ~= nil) then return end
    route.tables = route.tables or {}
    route.tables[tableName] = route.tables[tableName] or {}
    route.tables[tableName][key] = value
end

local function SearchRouteSetNestedTable(route, tableName, key1, key2, value)
    if not (route and tableName and key1 ~= nil and key2 ~= nil) then return end
    route.nestedTables = route.nestedTables or {}
    route.nestedTables[tableName] = route.nestedTables[tableName] or {}
    route.nestedTables[tableName][key1] = route.nestedTables[tableName][key1] or {}
    route.nestedTables[tableName][key1][key2] = value
end

local function SearchRouteSetGeneral(route, key, value)
    if not (route and key) then return end
    route.general = route.general or {}
    route.general[key] = value
end

local function SearchRouteApplySectionSpecs(route, pageKey, normalized, specs)
    if not (route and pageKey and type(specs) == "table") then return end
    for i = 1, #specs do
        local spec = specs[i]
        if spec and spec.id and SearchRouteHasAny(normalized, spec.terms) then
            SearchRouteOpenAccordion(route, pageKey, spec.id)
        end
    end
end

local function SearchGroupScopeForText(normalized)
    if SearchRouteHasAny(normalized, { "mythic raid", "mythicraid", "mythic" }) then return "mythicraid" end
    if SearchRouteHasAny(normalized, { "raid", "raids" }) then return "raid" end
    if SearchRouteHasAny(normalized, { "party", "group", "groups" }) then return "party" end
    return nil
end

local function SearchGlobalScopeForText(normalized)
    if SearchRouteHasAny(normalized, { "shared scope", "shared style", "global scope", "global style", "baseline" }) then return "shared" end
    if SearchRouteHasAny(normalized, { "raid frame", "raid frames", "raid unit", "raid units", "raid font", "raid fonts", "raid texture", "raid textures", "raid health", "raid text", "raid power", "raid bar", "raid bars" }) then return "gf_raid" end
    if SearchRouteHasAny(normalized, { "party frame", "party frames", "party unit", "party units", "party font", "party fonts", "party texture", "party textures", "party health", "party text", "party power", "party bar", "party bars", "group frame", "group frames", "group font", "group text" }) then return "gf_party" end
    if SearchRouteHasAny(normalized, { "target of target", "targettarget", "target target", "tot frame", "tot font", "tot text", "tot bar" }) then return "targettarget" end
    if SearchRouteHasAny(normalized, { "focus target", "focustarget", "focus target frame", "focus target font", "focus target text", "focus target bar" }) then return "focustarget" end
    if SearchRouteHasAny(normalized, { "player frame", "player unit", "player font", "player text", "player health", "player power", "player bar", "player bars" }) then return "player" end
    if SearchRouteHasAny(normalized, { "target frame", "target unit", "target font", "target text", "target health", "target power", "target bar", "target bars" }) then return "target" end
    if SearchRouteHasAny(normalized, { "focus frame", "focus unit", "focus font", "focus text", "focus health", "focus power", "focus bar", "focus bars" }) then return "focus" end
    if SearchRouteHasAny(normalized, { "pet frame", "pet unit", "pet font", "pet text", "pet health", "pet power", "pet bar", "pet bars" }) then return "pet" end
    if SearchRouteHasAny(normalized, { "boss frame", "boss frames", "boss unit", "boss units", "boss font", "boss text", "boss health", "boss power", "boss bar", "boss bars" }) then return "boss" end
    return nil
end

local function SearchTextKindForText(normalized)
    if SearchRouteHasAny(normalized, { "hp text", "health text", "hp slot", "health slot", "show hp", "percent hp", "hp percent", "left hp", "center hp", "right hp", "hp left", "hp center", "hp right", "left health", "center health", "right health", "health left", "health center", "health right" }) then
        return "hp"
    end
    if SearchRouteHasAny(normalized, { "power text", "power slot", "mana text", "energy text", "rage text", "show power", "left power", "center power", "right power", "power left", "power center", "power right" }) then
        return "power"
    end
    if SearchRouteHasAny(normalized, { "text layer", "draw order", "advanced text", "name layer", "hp layer", "power layer" }) then
        return "advanced"
    end
    if SearchRouteHasAny(normalized, { "name text", "show name", "name position", "name anchor", "raid group name", "left name", "center name", "right name" }) then
        return "name"
    end
    return nil
end

local function SearchTextSlotForText(normalized)
    if SearchRouteHasAny(normalized, { "left slot", "slot left", "left hp", "left health", "left power", "hp left", "health left", "power left" }) then return "left" end
    if SearchRouteHasAny(normalized, { "right slot", "slot right", "right hp", "right health", "right power", "hp right", "health right", "power right" }) then return "right" end
    if SearchRouteHasAny(normalized, { "center slot", "middle slot", "slot center", "slot middle", "center hp", "middle hp", "center health", "center power", "middle power", "hp center", "power center" }) then return "center" end
    return nil
end

local function SearchRouteTextState(route, tabTable, slotTable, scopeKey, normalized)
    local textKind = SearchTextKindForText(normalized)
    if not textKind then return end
    SearchRouteSetTable(route, tabTable, scopeKey, textKind)
    if textKind == "hp" or textKind == "power" then
        local slot = SearchTextSlotForText(normalized)
        if slot then SearchRouteSetNestedTable(route, slotTable, scopeKey, textKind, slot) end
    end
end

local function SearchRouteUnitStatusSelection(route, unit, normalized)
    if SearchRouteHasAny(normalized, { "incoming rez", "incoming res", "incoming resurrect", "incoming resurrection", "ress", "resurrect" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "statusIncomingRes")
    elseif SearchRouteHasAny(normalized, { "rested", "resting", "rest icon" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "statusResting")
    elseif SearchRouteHasAny(normalized, { "combat icon", "combat state", "in combat icon" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "statusCombat")
    elseif SearchRouteHasAny(normalized, { "dead text", "dead status", "offline text", "status text" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "statusText")
    elseif SearchRouteHasAny(normalized, { "elite", "rare", "elite icon", "rare icon" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "eliteicon")
    elseif SearchRouteHasAny(normalized, { "raid group", "group number", "subgroup" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "raidgroupname")
    elseif SearchRouteHasAny(normalized, { "level", "level text", "level indicator" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "level")
    elseif SearchRouteHasAny(normalized, { "raid marker", "marker" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "raidmarker")
    elseif SearchRouteHasAny(normalized, { "leader", "assist", "leader assist", "leader / assist" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "leader")
    end
end

local function SearchRouteGroupStatusSelection(route, normalized)
    if SearchRouteHasAny(normalized, { "ready check" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "readyCheckIcon")
    elseif SearchRouteHasAny(normalized, { "summon", "summoning" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "summonIcon")
    elseif SearchRouteHasAny(normalized, { "resurrect", "resurrection", "rez", "ress" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "resurrectIcon")
    elseif SearchRouteHasAny(normalized, { "phase", "phased" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "phaseIcon")
    elseif SearchRouteHasAny(normalized, { "ghost" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "statusGhostText")
    elseif SearchRouteHasAny(normalized, { "leader" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "leaderIcon")
    elseif SearchRouteHasAny(normalized, { "assist" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "assistIcon")
    elseif SearchRouteHasAny(normalized, { "raid marker", "marker" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "raidMarker")
    elseif SearchRouteHasAny(normalized, { "dead", "offline" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "statusText")
    elseif SearchRouteHasAny(normalized, { "afk", "dnd" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "statusAFKText")
    elseif SearchRouteHasAny(normalized, { "role icon", "tank", "healer", "dps" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "roleIcon")
    end
end

local function SearchPowerColorTokenForText(normalized)
    if SearchRouteHasAny(normalized, { "rage" }) then return "RAGE" end
    if SearchRouteHasAny(normalized, { "energy" }) then return "ENERGY" end
    if SearchRouteHasAny(normalized, { "focus power", "hunter focus" }) then return "FOCUS" end
    if SearchRouteHasAny(normalized, { "runic power" }) then return "RUNIC_POWER" end
    if SearchRouteHasAny(normalized, { "insanity" }) then return "INSANITY" end
    if SearchRouteHasAny(normalized, { "fury" }) then return "FURY" end
    if SearchRouteHasAny(normalized, { "pain" }) then return "PAIN" end
    if SearchRouteHasAny(normalized, { "essence" }) then return "ESSENCE" end
    if SearchRouteHasAny(normalized, { "astral power", "lunar power" }) then return "LUNAR_POWER" end
    if SearchRouteHasAny(normalized, { "maelstrom" }) then return "MAELSTROM" end
    if SearchRouteHasAny(normalized, { "mana" }) then return "MANA" end
    return nil
end

local function SearchClassPowerTokenForText(normalized)
    if SearchRouteHasAny(normalized, { "holy power" }) then return "HOLY_POWER" end
    if SearchRouteHasAny(normalized, { "soul shards", "soul shard" }) then return "SOUL_SHARDS" end
    if SearchRouteHasAny(normalized, { "chi" }) then return "CHI" end
    if SearchRouteHasAny(normalized, { "arcane charges", "arcane charge" }) then return "ARCANE_CHARGES" end
    if SearchRouteHasAny(normalized, { "runes" }) then return "RUNES" end
    if SearchRouteHasAny(normalized, { "empowered", "charged" }) then return "CHARGED" end
    if SearchRouteHasAny(normalized, { "soul fragments vengeance", "vengeance fragments" }) then return "SOUL_FRAGMENTS_VENG" end
    if SearchRouteHasAny(normalized, { "soul fragments void", "void meta" }) then return "SOUL_FRAGMENTS_META" end
    if SearchRouteHasAny(normalized, { "soul fragments", "soul fragment" }) then return "SOUL_FRAGMENTS" end
    if SearchRouteHasAny(normalized, { "maelstrom weapon 5" }) then return "MAELSTROM_ABOVE_5" end
    if SearchRouteHasAny(normalized, { "maelstrom weapon" }) then return "MAELSTROM" end
    if SearchRouteHasAny(normalized, { "astral prediction" }) then return "AP_PREDICTION" end
    if SearchRouteHasAny(normalized, { "astral power" }) then return "ASTRAL_POWER" end
    if SearchRouteHasAny(normalized, { "solar eclipse", "eclipse solar" }) then return "ECLIPSE_SOLAR" end
    if SearchRouteHasAny(normalized, { "lunar eclipse", "eclipse lunar" }) then return "ECLIPSE_LUNAR" end
    if SearchRouteHasAny(normalized, { "celestial alignment" }) then return "ECLIPSE_CA" end
    if SearchRouteHasAny(normalized, { "stagger light", "green stagger" }) then return "STAGGER_GREEN" end
    if SearchRouteHasAny(normalized, { "stagger moderate", "yellow stagger" }) then return "STAGGER_YELLOW" end
    if SearchRouteHasAny(normalized, { "stagger heavy", "red stagger" }) then return "STAGGER_RED" end
    if SearchRouteHasAny(normalized, { "insanity" }) then return "INSANITY" end
    if SearchRouteHasAny(normalized, { "maelstrom power" }) then return "MAELSTROM_POWER" end
    if SearchRouteHasAny(normalized, { "whirlwind" }) then return "WHIRLWIND" end
    if SearchRouteHasAny(normalized, { "tip of the spear" }) then return "TIP_OF_THE_SPEAR" end
    if SearchRouteHasAny(normalized, { "icicles" }) then return "ICICLES" end
    if SearchRouteHasAny(normalized, { "ebon might" }) then return "EBON_MIGHT" end
    if SearchRouteHasAny(normalized, { "resource text" }) then return "RESOURCE_TEXT" end
    if SearchRouteHasAny(normalized, { "essence" }) then return "ESSENCE" end
    if SearchRouteHasAny(normalized, { "combo points", "combo point" }) then return "COMBO_POINTS" end
    return nil
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
local function SearchRouteUnitPage(route, pageKey, normalized)
    local unit = SEARCH_UNIT_BY_PAGE[pageKey]
    if not unit then return end
    SearchRouteApplySectionSpecs(route, pageKey, normalized, {
        { id = "preview", terms = { "preview", "hide preview" } },
        { id = "frame_basics", terms = { "frame basics", "enable", "disable", "width", "height", "scale", "frame size", "smooth fill", "health animation" } },
        { id = "anchoring", terms = { "anchoring", "anchor", "position", "x offset", "y offset", "custom anchor", "global anchor" } },
        { id = "text", terms = { "text", "name text", "hp text", "health text", "power text", "font size", "text anchor", "text position", "draw order", "text layer" } },
        { id = "inline_text", terms = { "inline text", "inline color", "target of target text", "tot text", "tot color", "npc color", "npc type color" } },
        { id = "transparency", terms = { "transparency", "transparent", "alpha", "opacity", "fade", "in combat alpha", "out of combat alpha" } },
        { id = "portrait", terms = { "portrait", "class icon", "2d portrait", "3d portrait", "avatar", "face" } },
        { id = "power_bar", terms = { "power bar", "mana bar", "energy bar", "rage bar", "power height", "power smooth fill" } },
        { id = "castbar", terms = { "castbar", "cast bar", "spell name", "cast icon", "cast time" } },
        { id = "status_icons", terms = { "status icons", "status icon", "indicator", "level", "level text", "raid group", "group number", "raid marker", "leader", "assist", "elite", "rare", "dead", "offline", "combat icon", "rested", "incoming rez", "advanced status", "advanced x offset", "advanced y offset", "extended x offset", "extended y offset" } },
        { id = "load_conditions", terms = { "load conditions", "visibility conditions", "show conditions", "hide conditions", "when to show", "when to hide" } },
        { id = "boss_layout", terms = { "boss layout", "boss preview", "boss frames" } },
    })
    if SearchTextKindForText(normalized) then SearchRouteOpenAccordion(route, pageKey, "text") end
    SearchRouteTextState(route, "unitTextTabSelection", "unitTextSlotSelection", unit, normalized)
    if SearchRouteHasAny(normalized, { "advanced status", "status icon advanced", "advanced x offset", "advanced y offset", "extended x offset", "extended y offset", "wide x offset", "wide y offset" }) then
        SearchRouteSetTable(route, "unitStatusTabSelection", unit, "advanced")
    elseif SearchRouteHasAny(normalized, { "status icons", "status icon", "indicator", "level", "raid group", "group number", "raid marker", "leader", "assist", "elite", "rare", "dead", "offline", "combat icon", "rested", "incoming rez" }) then
        SearchRouteSetTable(route, "unitStatusTabSelection", unit, "basic")
    end
    SearchRouteUnitStatusSelection(route, unit, normalized)
end
local function SearchRouteGroupPage(route, pageKey, normalized)
    local scope = SearchGroupScopeForText(normalized)
    if scope then SearchRouteSetState(route, "gfScope", scope) end
    if pageKey == "gf_layout" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "general", terms = { "general", "enable", "disable", "turn off", "off", "hide group frames", "hide raid frames", "hide party frames", "group frames off", "raid frames off", "party frames off", "use msuf group frames", "show player", "show solo", "solo", "visibility", "party frames not showing", "raid frames not showing", "ausschalten", "deaktivieren", "ausblenden" } },
            { id = "layout", terms = { "layout", "growth", "direction", "spacing", "columns", "rows", "width", "height" } },
            { id = "sorting", terms = { "sorting", "sort", "role order", "player first", "groups first" } },
            { id = "scaling", terms = { "frame scaling", "scale", "smooth health fill", "smooth fill", "party smooth fill", "raid smooth fill" } },
            { id = "border", terms = { "transparency", "alpha", "opacity", "fade" } },
            { id = "anchor", terms = { "anchoring", "anchor", "position", "move party", "move raid", "x offset", "y offset" } },
            { id = "tooltip", terms = { "tooltip", "tooltips", "mouseover tooltip" } },
        })
    elseif pageKey == "gf_bars" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "hcolor", terms = { "health colors", "health color", "class color", "hp color" } },
            { id = "bars", terms = { "bars custom", "health bar", "bar texture", "bar height" } },
            { id = "power", terms = { "power bar", "mana bar", "power text", "smooth fill" } },
            { id = "text", terms = { "text", "name text", "health text", "hp text", "power text", "font size" } },
            { id = "dispel", terms = { "dispel overlay", "overlay style", "overlay detects", "overlay priority", "health bar tint" } },
            { id = "dstripe", terms = { "debuff stripe", "stripe edge", "stripe height", "stripe opacity" } },
            { id = "range", terms = { "range fade", "range check", "distance check", "out of range" } },
        })
        if SearchTextKindForText(normalized) then SearchRouteOpenAccordion(route, pageKey, "text") end
        SearchRouteTextState(route, "gfTextTabSelection", "gfTextSlotSelection", scope or M.gfScope or "party", normalized)
    elseif pageKey == "gf_auras" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "buffs", terms = { "buffs", "buff", "hots", "own buffs", "healer buffs", "buff position", "buff size", "buff layer" } },
            { id = "debuffs", terms = { "debuffs", "debuff", "boss debuff", "raid debuff", "debuff position", "debuff size", "debuff layer" } },
        })
    elseif pageKey == "gf_indicators" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "indicators", terms = { "indicators", "spell indicators", "placed indicators", "focus glow", "frame effects" } },
            { id = "sicons", terms = { "status icons", "status icon", "dead icon", "ghost text", "offline icon", "afk", "dnd", "ready check", "summon", "resurrect", "phase", "leader icon", "assist icon", "role icon", "raid marker", "advanced status", "advanced x offset", "advanced y offset", "advanced placement", "extended x offset", "extended y offset" } },
            { id = "si", terms = { "spell indicators", "custom spell", "spell id", "indicator spell", "healer hots indicators" } },
            { id = "ci", terms = { "corner indicators", "corner dots", "corner indicator", "custom spell editor", "slot assignments" } },
        })
        local tabScope = scope or M.gfScope or "party"
        if SearchRouteHasAny(normalized, { "advanced status", "status icon advanced", "advanced x offset", "advanced y offset", "advanced placement", "extended x offset", "extended y offset", "draw order" }) then
            SearchRouteSetTable(route, "gfStatusIconTabSelection", tabScope, "advanced")
        elseif SearchRouteHasAny(normalized, { "status icons", "status icon", "ready check", "summon", "resurrect", "phase", "dead", "ghost", "offline", "afk", "dnd", "leader icon", "assist icon", "role icon", "raid marker" }) then
            SearchRouteSetTable(route, "gfStatusIconTabSelection", tabScope, "basic")
        end
        SearchRouteGroupStatusSelection(route, normalized)
        if SearchRouteHasAny(normalized, { "top left", "tl" }) then
            SearchRouteSetState(route, "gfCornerSlotSelection", "TL")
        elseif SearchRouteHasAny(normalized, { "top right", "tr" }) then
            SearchRouteSetState(route, "gfCornerSlotSelection", "TR")
        elseif SearchRouteHasAny(normalized, { "bottom left", "bl" }) then
            SearchRouteSetState(route, "gfCornerSlotSelection", "BL")
        elseif SearchRouteHasAny(normalized, { "bottom right", "br" }) then
            SearchRouteSetState(route, "gfCornerSlotSelection", "BR")
        elseif SearchRouteHasAny(normalized, { "center", "middle" }) then
            SearchRouteSetState(route, "gfCornerSlotSelection", "C")
        end
    end
end
local function SearchRouteGlobalPage(route, pageKey, normalized)
    if pageKey == "profiles" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "profiles_management", terms = { "profile management", "active profile", "rename", "copy profile", "reset profile" } },
            { id = "profiles_specs", terms = { "spec profiles", "specialization", "auto switch" } },
            { id = "profiles_io", terms = { "export", "import", "wago", "legacy import", "profile string", "backup", "share profile" } },
        })
        if SearchRouteHasAny(normalized, { "export unitframe", "export unitframes", "unitframe export", "unitframes export" }) then
            SearchRouteSetState(route, "profileExportKind", "unitframe")
        elseif SearchRouteHasAny(normalized, { "export castbar", "export castbars", "castbar export", "castbars export" }) then
            SearchRouteSetState(route, "profileExportKind", "castbar")
        elseif SearchRouteHasAny(normalized, { "export colors", "export colours", "colors export", "colours export" }) then
            SearchRouteSetState(route, "profileExportKind", "colors")
        elseif SearchRouteHasAny(normalized, { "export gameplay", "gameplay export" }) then
            SearchRouteSetState(route, "profileExportKind", "gameplay")
        elseif SearchRouteHasAny(normalized, { "export group", "export group frames", "group frames export", "groupframe export" }) then
            SearchRouteSetState(route, "profileExportKind", "groupframe")
        elseif SearchRouteHasAny(normalized, { "full profile", "export full", "full export", "complete profile" }) then
            SearchRouteSetState(route, "profileExportKind", "all")
        end
        if SearchRouteHasAny(normalized, { "import create new", "import new profile", "create new profile", "import and create new profile" }) then
            SearchRouteSetState(route, "profileImportCreateNew", true)
        elseif SearchRouteHasAny(normalized, { "import current profile", "import to current", "current profile import" }) then
            SearchRouteSetState(route, "profileImportCreateNew", false)
        end
    elseif pageKey == "modules" then
        SearchRouteOpenAccordion(route, pageKey, "modules_style")
    elseif pageKey == "opt_bars" then
        local scope = SearchGlobalScopeForText(normalized)
        if scope then SearchRouteSetGeneral(route, "hpPowerTextSelectedKey", scope) end
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "bars_textures", terms = { "textures", "texture", "gradient", "bar texture", "background texture" } },
            { id = "bars_absorb", terms = { "absorb", "heal prediction", "incoming heals", "shield" } },
            { id = "bars_outline", terms = { "frame outline", "outline", "bar outline", "border thickness" } },
            { id = "bars_rounded", terms = { "rounded", "round corners", "rounded texture", "rounded frames" } },
            { id = "bars_highlight", terms = { "highlight borders", "highlight border", "dispel border", "dispel overlay", "aggro border", "purge border", "boss target border", "priority order" } },
            { id = "bars_unit_dispel_overlay", terms = { "unitframe dispel overlay", "unit frame dispel overlay", "overlay detects", "overlay priority", "unit dispel overlay" } },
            { id = "bars_power", terms = { "bar animation", "text accuracy", "smooth fill", "power animation" } },
        })
    elseif pageKey == "opt_fonts" then
        local scope = SearchGlobalScopeForText(normalized)
        if scope then SearchRouteSetGeneral(route, "_fontScopeKey", scope) end
        if not scope and SearchRouteHasAny(normalized, {
            "font", "fonts", "global font", "font family", "font dropdown", "sharedmedia",
            "change font", "change fonts", "where to change font", "where change font",
            "schriftart", "schriftart aendern", "schrift aendern",
        }) then
            SearchRouteSetGeneral(route, "_fontScopeKey", "shared")
        end
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "fonts_global_font", terms = { "global font", "font family", "font", "font dropdown", "sharedmedia", "change font", "change fonts", "where to change font", "where change font" } },
            { id = "fonts_text_style", terms = { "text style", "outline", "shadow", "font size" } },
            { id = "fonts_name_power_colors", terms = { "name colors", "power colors", "name color", "power color" } },
            { id = "fonts_name_shortening", terms = { "name shortening", "short names", "realm names", "truncate", "names too long" } },
        })
    elseif pageKey == "opt_castbar" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "castbar_behavior", terms = { "shake", "fill direction", "castbar direction", "castbar behavior" } },
            { id = "castbar_textures", terms = { "textures", "texture", "outline", "castbar texture" } },
            { id = "castbar_empowered", terms = { "empowered casts", "evoker", "empower", "stage blink", "hold cast", "release cast" } },
            { id = "castbar_name_shortening", terms = { "name shortening", "spell name", "cast name", "max name length" } },
            { id = "castbar_focus_kick", terms = { "focus kick", "target kick", "interrupt focus", "kick cooldown" } },
            { id = "castbar_interrupt_ready", terms = { "interrupt ready", "demon hunter", "devour", "consume magic", "disrupt", "kick ready" } },
        })
    elseif pageKey == "opt_misc" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "misc_language", terms = { "language", "locale", "translation", "localization", "localisation" } },
            { id = "misc_menu_behavior", terms = { "menu behavior", "menu snap", "edge snap", "window snap", "menu resize" } },
            { id = "misc_updates", terms = { "update intervals", "performance", "lag", "fps", "cooldown text performance" } },
            { id = "misc_tooltips", terms = { "tooltips", "tooltip", "unitframe tooltips", "mouseover tooltip" } },
            { id = "misc_blizzard_frames", terms = { "blizzard frames", "default frames", "hide blizzard", "disable blizzard" } },
            { id = "misc_range_fade", terms = { "range fade", "range check", "distance check", "out of range" } },
        })
    elseif pageKey == "classpower" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "classpower_display", terms = { "layout", "display", "combo points", "holy power", "soul shards", "chi", "essence", "runes" } },
            { id = "classpower_behavior", terms = { "behavior", "prediction", "quick actions" } },
            { id = "classpower_visuals", terms = { "style", "visual", "texture", "spacing", "colors" } },
            { id = "classpower_visibility", terms = { "auto hide", "visibility", "hide empty" } },
            { id = "classpower_detached_power", terms = { "detached power", "detached power bar", "alternate power", "dual resource" } },
            { id = "classpower_alt_mana", terms = { "alternative mana", "alt mana", "mana bar" } },
        })
    elseif pageKey == "auras3" or pageKey == "auras3_rendering" or pageKey == "auras3_filters" or pageKey == "auras3_styling" then
        if pageKey == "auras3_rendering" then
            SearchRouteApplySectionSpecs(route, pageKey, normalized, {
                { id = "Auras", terms = { "buffs", "debuffs", "enable auras", "visibility", "visible auras" } },
            })
        elseif pageKey == "auras3_filters" then
            SearchRouteApplySectionSpecs(route, pageKey, normalized, {
                { id = "Filters", terms = { "filters", "inclusive filter", "exclusive filter", "only mine", "own buffs", "own debuffs", "dispellable", "stealable" } },
                { id = "Blacklist", terms = { "blacklist", "ignore list", "spell id", "blacklist presets" } },
                { id = "Group Frame Filters", terms = { "inclusive filter", "exclusive filter", "base filter", "category blacklist", "declassified" } },
            })
        elseif pageKey == "auras3_styling" then
            SearchRouteApplySectionSpecs(route, pageKey, normalized, {
                { id = "Unit Aura Text", terms = { "stack size", "cooldown size", "stack anchor", "timer text", "unit aura text" } },
                { id = "Group Frame Styling", terms = { "group frame aura style", "stack font", "cooldown font", "cooldown swipe", "tooltip", "sort by duration", "prefer player", "aura behavior" } },
                { id = "Colors", terms = { "timer color", "cooldown text color", "stack color", "own buff", "own debuff", "safe warning urgent" } },
            })
        else
            SearchRouteApplySectionSpecs(route, pageKey, normalized, {
                { id = "Auras", terms = { "buffs", "debuffs", "enable auras", "visible units", "active scope" } },
            })
        end
        if SearchRouteHasAny(normalized, { "player" }) then
            SearchRouteSetState(route, "auraScope", "player")
        elseif SearchRouteHasAny(normalized, { "target" }) then
            SearchRouteSetState(route, "auraScope", "target")
        elseif SearchRouteHasAny(normalized, { "focus" }) then
            SearchRouteSetState(route, "auraScope", "focus")
        elseif SearchRouteHasAny(normalized, { "boss" }) then
            SearchRouteSetState(route, "auraScope", "boss")
        elseif SearchRouteHasAny(normalized, { "party" }) then
            SearchRouteSetState(route, "auraScope", "party")
            SearchRouteSetState(route, "auraStyleGFScope", "party")
        elseif SearchRouteHasAny(normalized, { "raid", "mythic" }) then
            SearchRouteSetState(route, "auraScope", "raid")
            SearchRouteSetState(route, "auraStyleGFScope", "raid")
        elseif SearchRouteHasAny(normalized, { "shared", "global" }) then
            SearchRouteSetState(route, "auraScope", "shared")
        end
    elseif pageKey == "opt_colors" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "colors_font", terms = { "global font color", "font color" } },
            { id = "colors_classes", terms = { "class bar colors", "class color", "class colored" } },
            { id = "colors_background", terms = { "bar background tint", "background color", "backdrop", "missing health", "dark mode", "preserve hp color" } },
            { id = "colors_appearance", terms = { "unitframe global coloring", "appearance", "dark mode" } },
            { id = "colors_unit", terms = { "unitframe colors", "unit frame colors", "reaction color" } },
            { id = "colors_npc_type", terms = { "npc type colors", "npc color" } },
            { id = "colors_bar_colors", terms = { "bar colors", "health color", "hp color" } },
            { id = "colors_dispel", terms = { "dispel", "magic color", "curse color", "poison color", "disease color" } },
            { id = "colors_castbar", terms = { "castbar colors", "castbar color", "spell color" } },
            { id = "colors_highlight", terms = { "mouseover highlight", "hover highlight" } },
            { id = "colors_gameplay", terms = { "gameplay", "crosshair", "target sound" } },
            { id = "colors_power", terms = { "power bar colors", "power bar color", "mana color", "rage color", "energy color", "focus power", "runic power", "insanity color", "fury color", "pain color", "essence color", "astral power", "lunar power", "maelstrom color" } },
            { id = "colors_class_power", terms = { "class power colors", "combo point color", "holy power color", "soul shard", "chi color", "arcane charges", "runes color", "essence color", "soul fragments", "maelstrom weapon", "astral power", "eclipse", "stagger", "icicles", "ebon might" } },
            { id = "colors_auras", terms = { "auras", "buff color", "debuff color" } },
            { id = "colors_portrait", terms = { "portrait colors", "portrait color" } },
        })
        local powerToken = SearchPowerColorTokenForText(normalized)
        if powerToken then SearchRouteSetState(route, "colorsPowerToken", powerToken) end
        local classPowerToken = SearchClassPowerTokenForText(normalized)
        if classPowerToken then SearchRouteSetState(route, "colorsCPToken", classPowerToken) end
        if powerToken or (SearchRouteHasAny(normalized, { "power color", "power colors" }) and not classPowerToken) then
            SearchRouteOpenAccordion(route, pageKey, "colors_power")
        end
        if classPowerToken then SearchRouteOpenAccordion(route, pageKey, "colors_class_power") end
    elseif pageKey == "gameplay" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "gameplay_timer", terms = { "combat timer", "timer" } },
            { id = "gameplay_state", terms = { "combat enter", "combat leave", "enter combat", "leave combat" } },
            { id = "gameplay_class_specific", terms = { "class-specific", "class specific", "demon hunter", "interrupt", "devour" } },
            { id = "gameplay_crosshair", terms = { "combat crosshair", "crosshair", "targeting", "mouse" } },
        })
    end
end
local function SearchRouteForTarget(pageKey, query, fallback)
    local normalized = NormalizeSearchText((query or "") .. " " .. (fallback or ""))
    if normalized == "" then return nil end
    if pageKey == "home" then
        if SearchRouteHasAny(normalized, {
            "discord", "factory reset", "fullreset", "print help", "display recovery", "recovery tools",
            "recover menu", "reset all", "help reset", "copy discord", "support discord",
        }) then
            return DASHBOARD_ROUTE_RECOVERY
        end
        if SearchRouteHasAny(normalized, {
            "scaling", "ui scale", "menu scale", "msuf frame scale", "msuf menu scale",
            "make menu bigger", "make menu smaller", "options too big", "options too small",
            "resize window", "groesser", "kleiner", "skalierung",
        }) then
            return DASHBOARD_ROUTE_SCALING
        end
        if SearchRouteHasAny(normalized, {
            "changelog", "change log", "release notes", "patch notes", "version notes",
            "what changed", "latest changes", "aenderungen", "anderungen",
        }) then
            return DASHBOARD_ROUTE_CHANGELOG
        end
        return nil
    end
    local route = SearchNewRoute()
    SearchRouteUnitPage(route, pageKey, normalized)
    SearchRouteGroupPage(route, pageKey, normalized)
    SearchRouteGlobalPage(route, pageKey, normalized)
    return SearchRouteIsEmpty(route) and nil or route
end
local function ApplySearchRoute(pageKey, route)
    if type(route) ~= "table" then return false end
    local changed = false
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local state = route.state
    if type(state) == "table" then
        for field, value in pairs(state) do
            if M[field] ~= value then
                if type(M.PersistMenuStateValue) == "function" then
                    M.PersistMenuStateValue(field, value)
                else
                    M[field] = value
                end
                changed = true
            end
        end
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
        for key, value in pairs(accordion) do
            local open = value and true or false
            if target[key] ~= open then
                target[key] = open
                changed = true
            end
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
                for key, value in pairs(values) do
                    if target[key] ~= value then
                        target[key] = value
                        changed = true
                    end
                end
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
            _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
            _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
            db = _G.MSUF_DB.general
        end
        for key, value in pairs(general) do
            if db[key] ~= value then
                db[key] = value
                changed = true
            end
        end
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
