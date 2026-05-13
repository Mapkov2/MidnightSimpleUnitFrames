local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

M.Tr = M.Tr or function(text)
    if text == nil then return "" end
    local key = tostring(text)
    if type(ns.Translate) == "function" then
        local translated = ns.Translate(key)
        if translated ~= nil then return translated end
    end
    if type(ns.TR) == "function" then
        local translated = ns.TR(key)
        if translated ~= nil then return translated end
    end
    local locale = ns.L or _G.MSUF_L
    if type(locale) == "table" and locale[key] ~= nil then
        return locale[key]
    end
    return key
end

local T = M.Theme
local W = M.Widgets

M.pages = M.pages or {}
M.pageOrder = M.pageOrder or {}
M.cache = M.cache or {}

local floor = math.floor
local max = math.max
local min = math.min

local DEFAULT_WINDOW_W, DEFAULT_WINDOW_H = 900, 650
local MIN_WINDOW_W, MIN_WINDOW_H = 620, 400
local MAX_WINDOW_W, MAX_WINDOW_H = 1600, 1100
local WINDOW_W, WINDOW_H = DEFAULT_WINDOW_W, DEFAULT_WINDOW_H
local NAV_W = 174
local CONTENT_W = WINDOW_W - NAV_W - 24
local CONTENT_H = WINDOW_H - 74
local NAV_BUTTON_H = 20
local NAV_BUTTON_STEP = 23
local MENU_BASE_SCALE = 1.08

local NAV = {
    { key = "home", label = "Dashboard" },
    { header = "Unit Frames", id = "unitframes", defaultOpen = true },
    { key = "uf_player", label = "Player", group = "unitframes" },
    { key = "uf_target", label = "Target", group = "unitframes" },
    { key = "uf_targettarget", label = "Target of Target", group = "unitframes" },
    { key = "uf_focus", label = "Focus", group = "unitframes" },
    { key = "uf_boss", label = "Boss Frames", group = "unitframes" },
    { key = "uf_pet", label = "Pet", group = "unitframes" },
    { header = "Group Frames", id = "groupframes", defaultOpen = true },
    { key = "gf_layout", label = "Layout", group = "groupframes" },
    { key = "gf_bars", label = "Health & Text", group = "groupframes" },
    { key = "gf_auras", label = "Buffs & Debuffs", group = "groupframes" },
    { key = "gf_indicators", label = "Indicators", group = "groupframes" },
    { header = "Global Style", id = "globalstyle", defaultOpen = true },
    { key = "opt_bars", label = "Bars", group = "globalstyle" },
    { key = "opt_fonts", label = "Fonts", group = "globalstyle" },
    { key = "auras2", label = "Unit Auras", group = "globalstyle" },
    { key = "opt_castbar", label = "Castbar", group = "globalstyle" },
    { key = "opt_colors", label = "Colors", group = "globalstyle" },
    { key = "opt_misc", label = "Miscellaneous", group = "globalstyle" },
    { key = "classpower", label = "Class Resources" },
    { key = "gameplay", label = "Gameplay" },
    { header = "Modules", id = "modules", defaultOpen = false },
    { key = "modules", label = "Style", group = "modules" },
    { key = "profiles", label = "Profiles" },
}

local ALIASES = {
    [""] = "home",
    home = "home",
    menu = "home",
    main = "home",
    options = "home",
    opt = "home",
    player = "uf_player",
    target = "uf_target",
    tot = "uf_targettarget",
    targettarget = "uf_targettarget",
    focus = "uf_focus",
    boss = "uf_boss",
    pet = "uf_pet",
    bars = "opt_bars",
    fonts = "opt_fonts",
    auras = "auras2",
    auras2 = "auras2",
    castbar = "opt_castbar",
    colors = "opt_colors",
    colours = "opt_colors",
    misc = "opt_misc",
    classpower = "classpower",
    gameplay = "gameplay",
    profiles = "profiles",
    layout = "gf_layout",
    health = "gf_bars",
    group = "gf_layout",
    groupframes = "gf_layout",
    class = "classpower",
    modules = "modules",
    search = "search",
}

local SEARCH_KEYWORDS = {
    home = "dashboard start support links quick navigation reset positions ui scale menu scale profiles wago discord patreon github curseforge paypal",
    uf_player = "unit frame player frame basics health power portrait text castbar auras buffs debuffs range fade preview enable copy to edit mode size position scale color name hp power",
    uf_target = "unit frame target frame basics health power portrait text castbar auras buffs debuffs range fade preview enable copy to edit mode size position scale color name hp power",
    uf_targettarget = "unit frame target of target tot frame basics health power portrait text castbar auras buffs debuffs range fade preview enable copy to edit mode size position scale color name hp power",
    uf_focus = "unit frame focus frame basics health power portrait text castbar focus kick interrupt auras buffs debuffs range fade preview enable copy to edit mode size position scale color name hp power",
    uf_boss = "unit frame boss frames frame basics health power portrait text castbar boss range fade auras buffs debuffs preview enable copy to edit mode size position scale color name hp power",
    uf_pet = "unit frame pet frame basics health power portrait text castbar auras buffs debuffs range fade preview enable copy to edit mode size position scale color name hp power",
    gf_layout = "group frames party raid mythic raid layout growth direction sorting role order frame scaling transparency anchoring tooltip range fade preview show hide player solo enable width height spacing columns",
    gf_bars = "group frames health text power bar name hp text heal prediction absorb display range fade layout font size anchor offset opacity smooth fill show power tank healer damage",
    gf_auras = "group frames buffs debuffs defensives text coloring private auras cooldown style aura utilities filter anchor icon size max buffs max debuffs custom buffs custom debuffs cooldown swipe masque pandemic",
    gf_indicators = "group frames indicators status icons spell indicators corner indicators group number focus glow border dispel aggro threat role icon custom spells slots preview current show all",
    opt_bars = "global style bars textures gradient gradient direction hp power absorb display highlight borders outline border aggro purge boss target glow bar colors background tint dark mode shared texture opacity",
    opt_fonts = "global style fonts font family size outline shadow color text readability name hp power spell cooldown",
    auras2 = "global style unit auras buffs debuffs icon size caps rows spacing sorting cooldown tooltip private aura filter override",
    opt_castbar = "global style castbar textures outline shake fill direction empowered casts interrupt ready focus kick name shortening latency spark channel ticks",
    opt_colors = "global style colors class bar colors background tint unitframe colors npc type colors bar colors dispel castbar mouseover highlight gameplay superellipse color swatches",
    opt_misc = "global style miscellaneous misc language localization localisation locale translation range fade ui behavior tooltip combat settings general",
    classpower = "class resources combo points holy power soul shards chi maelstrom eclipse essence runes stagger resource prediction auto hide detached power bar alternative mana behavior style quick actions",
    gameplay = "gameplay combat crosshair click cast focus target modifier mouseover interaction targeting spells",
    modules = "modules style skins optional modules compatibility",
    profiles = "profiles profile management spec profiles specialization auto switch create copy delete reset import export legacy import wago active profile",
}

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value) or fallback or minValue
    if value < minValue then value = minValue elseif value > maxValue then value = maxValue end
    return floor(value + 0.5)
end

local function ClampScale(value)
    value = tonumber(value) or 1
    if value < 0.25 then value = 0.25 elseif value > 1.5 then value = 1.5 end
    return value
end

local function EffectiveMenuScale(value)
    return ClampScale(ClampScale(value) * MENU_BASE_SCALE)
end

local function WindowMaxBounds()
    local maxW, maxH = MAX_WINDOW_W, MAX_WINDOW_H
    local parent = _G.UIParent
    if parent and parent.GetWidth and parent.GetHeight then
        local scale = 1
        local g = M.GetGeneralDB and M.GetGeneralDB()
        if type(g) == "table" then scale = EffectiveMenuScale(g.slashMenuScale) end
        maxW = min(maxW, floor(((parent:GetWidth() or maxW) / scale) - 28))
        maxH = min(maxH, floor(((parent:GetHeight() or maxH) / scale) - 28))
    end
    return max(MIN_WINDOW_W, maxW), max(MIN_WINDOW_H, maxH)
end

local function ApplyWindowResizeBounds(frame)
    if not frame then return end
    local maxW, maxH = WindowMaxBounds()
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WINDOW_W, MIN_WINDOW_H, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(MIN_WINDOW_W, MIN_WINDOW_H) end
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
end

local function SetWindowMetrics(width, height)
    local maxW, maxH = WindowMaxBounds()
    WINDOW_W = ClampNumber(width, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W)
    WINDOW_H = ClampNumber(height, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
    CONTENT_W = math.max(420, WINDOW_W - NAV_W - 24)
    CONTENT_H = math.max(320, WINDOW_H - 74)
end

local function RefreshWindowMetrics(frame)
    local width = (frame and frame.GetWidth and frame:GetWidth()) or WINDOW_W
    local height = (frame and frame.GetHeight and frame:GetHeight()) or WINDOW_H
    SetWindowMetrics(width, height)
end

local function ClampWindowSize(frame)
    if not frame then return end
    RefreshWindowMetrics(frame)
    if frame.SetSize then frame:SetSize(WINDOW_W, WINDOW_H) end
    ApplyWindowResizeBounds(frame)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
end

local function ReadSavedWindowSize()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return DEFAULT_WINDOW_W, DEFAULT_WINDOW_H end
    local maxW, maxH = WindowMaxBounds()
    return ClampNumber(g.msuf2WindowW, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W),
        ClampNumber(g.msuf2WindowH, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
end

local function SaveWindowSize(frame)
    RefreshWindowMetrics(frame)
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return end
    g.msuf2WindowW = WINDOW_W
    g.msuf2WindowH = WINDOW_H
end

local function ApplyScrollMetrics()
    if not M.scrollChild then return end
    local height = CONTENT_H
    local entry = M.activeKey and M.cache and M.cache[M.activeKey]
    if entry and tonumber(entry.height) then height = math.max(height, entry.height) end
    M.scrollChild:SetSize(CONTENT_W - 10, height)
    if entry and entry.wrapper then entry.wrapper:SetSize(CONTENT_W - 10, height) end
end

local function RebuildActivePageForResize(frame)
    local key = M.activeKey or "home"
    SaveWindowSize(frame)
    ApplyScrollMetrics()
    if M.InvalidatePage then M.InvalidatePage() end
    M.activeKey = nil
    if M.SelectPage and frame and frame:IsShown() then M.SelectPage(key) end
end

function M.RegisterPage(key, spec)
    if type(key) ~= "string" or type(spec) ~= "table" then return end
    if not M.pages[key] then
        M.pageOrder[#M.pageOrder + 1] = key
    end
    M.pages[key] = spec
end

local function HideAllCachedPages()
    for _, entry in pairs(M.cache) do
        if entry.wrapper and entry.wrapper.Hide then entry.wrapper:Hide() end
    end
end

local function SetTitle(key)
    local frame = M.frame
    if not frame then return end
    local spec = M.pages[key]
    local title = (spec and spec.title) or "MSUF"
    frame.title:SetText(M.Tr(title))
    if frame.subtitle then frame.subtitle:SetText("") end
    if frame.RefreshStatus then frame:RefreshStatus() end
end

local function UpdateNav(key)
    if not M.navButtons then return end
    local group = M.navGroupForKey and M.navGroupForKey[key]
    if group and M.navHeaderState and M.navHeaderState[group] == false then
        M.navHeaderState[group] = true
        if M.nav and M.nav._msuf2NavReflow then M.nav:_msuf2NavReflow() end
    end
    for pageKey, btn in pairs(M.navButtons) do
        if btn._msuf2RawLabel and btn.SetText then
            btn:SetText(M.Tr(btn._msuf2RawLabel))
        end
        if btn.SetActive then btn:SetActive(pageKey == key) end
    end
    if M.navHeaders then
        for _, btn in pairs(M.navHeaders) do
            if btn._msuf2RawLabel and btn.SetText then
                btn:SetText(string.upper(M.Tr(btn._msuf2RawLabel)))
            end
        end
    end
    if M.nav and M.nav.searchBox and M.nav.searchBox.Instructions then
        M.nav.searchBox.Instructions:SetText(M.Tr("Search settings..."))
    end
end

local function RunRefreshers(entry)
    if not entry or not entry.refreshers then return end
    for i = 1, #entry.refreshers do
        local fn = entry.refreshers[i]
        if type(fn) == "function" then pcall(fn) end
    end
end

local function BossPagePreviewInCombat()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function ApplyBossPagePreviewFallback(active, reason)
    _G.MSUF2_BossUnitframePreviewActive = active and true or nil
    if BossPagePreviewInCombat() then return end
    if type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then
        _G.MSUF_ApplyBossUnitframePreviewState(active and true or false, reason or "MSUF2_BOSS_PAGE")
        return
    end
    if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
        pcall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
    end
end

local IsEditModeActive

local function SyncBossPagePreviewForKey(key)
    local active = (key == "uf_boss")
        and M.frame and M.frame.IsShown and M.frame:IsShown()
    local fn = M.UnitPage and M.UnitPage.SetBossPagePreviewActive
    if type(fn) == "function" then
        local ok = pcall(fn, active and true or false)
        if ok then
            if active and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" and not BossPagePreviewInCombat() then
                _G.MSUF_ApplyBossUnitframePreviewState(true, "MSUF2_BOSS_PAGE_CORE")
            end
        else
            ApplyBossPagePreviewFallback(active and true or false, "MSUF2_BOSS_PAGE_FALLBACK")
        end
        return
    end
    ApplyBossPagePreviewFallback(active and true or false, "MSUF2_BOSS_PAGE_FALLBACK")
end

local GF_PAGE_KEYS = {
    gf_layout = true,
    gf_bars = true,
    gf_auras = true,
    gf_indicators = true,
}

local function IsGroupPageKey(key)
    return GF_PAGE_KEYS[key or ""] == true
end

local function CurrentGFMenuScope()
    local scope = M.gfScope
    if scope == "party" or scope == "raid" or scope == "mythicraid" then return scope end
    return "party"
end

local function GFPreviewCount(kind)
    if kind == "mythicraid" then return 20 end
    if kind == "raid" then return 30 end
    return 5
end

local function SetGFPagePreviewFlag(active, kind)
    _G.MSUF2_GFPagePreviewActive = active and true or nil
    _G.MSUF2_GFPagePreviewKind = active and kind or nil
end

local function HideGFHeaders(gf)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    if not (gf and gf.headers) then return end
    if gf.headers.party then gf.headers.party:Hide() end
    if gf.headers.raid then gf.headers.raid:Hide() end
end

local function RestoreGFHeaders(gf)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    if gf and type(gf.UpdateGroupVisibility) == "function" then gf.UpdateGroupVisibility() end
end

local function SyncGroupPagePreviewForKey(key)
    local frameVisible = M.frame and M.frame.IsShown and M.frame:IsShown()
    local active = frameVisible and IsGroupPageKey(key)
    local gf = ns and ns.GF
    local kind = CurrentGFMenuScope()

    if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then
        _G.MSUF_GF_EM2_SetActivePreviewKind(active and kind or nil)
    end

    if IsEditModeActive() then
        SetGFPagePreviewFlag(false)
        return
    end

    if not (gf and type(gf.ShowPreview) == "function" and type(gf.HidePreview) == "function") then
        SetGFPagePreviewFlag(active, kind)
        return
    end

    if not active then
        SetGFPagePreviewFlag(false)
        local classicPanel = _G.MSUF_GFOptionsPanel
        if classicPanel and classicPanel.IsShown and classicPanel:IsShown() then return end
        gf.HidePreview("party")
        gf.HidePreview("raid")
        gf.HidePreview("mythicraid")
        if gf.SetPreviewAnchor then
            gf.SetPreviewAnchor("party", nil)
            gf.SetPreviewAnchor("raid", nil)
            gf.SetPreviewAnchor("mythicraid", nil)
        end
        RestoreGFHeaders(gf)
        return
    end

    SetGFPagePreviewFlag(true, kind)
    HideGFHeaders(gf)
    if gf.SetPreviewAnchor then
        gf.SetPreviewAnchor("party", nil)
        gf.SetPreviewAnchor("raid", nil)
        gf.SetPreviewAnchor("mythicraid", nil)
    end
    if kind ~= "party" then gf.HidePreview("party") end
    if kind ~= "raid" then gf.HidePreview("raid") end
    if kind ~= "mythicraid" then gf.HidePreview("mythicraid") end
    gf.ShowPreview(kind, GFPreviewCount(kind))
    if type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout(kind) end
end

M.SyncGFPagePreviewForKey = SyncGroupPagePreviewForKey

IsEditModeActive = function()
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active ~= nil then
        return st.active == true
    end

    local em2 = rawget(_G, "MSUF_EM2")
    local state = em2 and em2.State
    if state and type(state.IsActive) == "function" then
        return state.IsActive() and true or false
    end

    local fn = rawget(_G, "MSUF_IsMSUFEditModeActive")
        or rawget(_G, "MSUF_IsInEditMode")
        or rawget(_G, "MSUF_IsEditModeActive")
    if type(fn) == "function" then
        local ok, result = pcall(fn)
        if ok then return result and true or false end
    end

    return rawget(_G, "MSUF_UnitEditModeActive") == true
        or rawget(_G, "MSUF_EDITMODE_ACTIVE") == true
end

local function IsEditModeCombatLocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function RefreshDashboardEditModeButton()
    local btn = M.dashboardEditModeButton
    if not btn then return end

    local active = IsEditModeActive()
    local combatLocked = IsEditModeCombatLocked() and true or false
    if active then
        btn:SetText("Edit Mode: On")
    elseif combatLocked then
        btn:SetText("Edit Mode: Off (Combat)")
    else
        btn:SetText("Edit Mode: Off")
    end

    if btn.SetEnabled then btn:SetEnabled(active or not combatLocked) end
    if btn.SetActive then btn:SetActive(active) end
end

local editModeUIHooked = false
local function EnsureEditModeUIHook()
    if editModeUIHooked then return end
    local register = rawget(_G, "MSUF_RegisterAnyEditModeListener")
    if type(register) ~= "function" then return end

    register(function()
        local frame = M.frame
        if frame and frame:IsShown() then
            if frame.RefreshStatus then frame:RefreshStatus() end
            if M.Refresh then M.Refresh() end
            SyncGroupPagePreviewForKey(M.activeKey)
        else
            RefreshDashboardEditModeButton()
        end
    end)
    editModeUIHooked = true
end

local function CreateContext(key, wrapper, entry)
    local ctx = {
        key = key,
        wrapper = wrapper,
        refreshers = entry.refreshers,
        width = CONTENT_W - 34,
    }
    function ctx:SetContentHeight(height)
        height = math.max(CONTENT_H, tonumber(height) or CONTENT_H)
        entry.height = height
        if wrapper.SetHeight then wrapper:SetHeight(height) end
        if M.scrollChild and M.scrollChild.SetHeight then M.scrollChild:SetHeight(height) end
    end
    function ctx:AddRefresher(fn)
        M.AddRefresher(ctx, fn)
    end
    return ctx
end

local function BuildPlaceholderPage(ctx, requestedKey)
    local b = W.PageBuilder(ctx)
    local sec = b:Section("Native page missing", 130)
    W.Text(sec, "This native page is not implemented yet.", 14, -42, ctx.width - 28, T.colors.muted)
    W.Text(sec, M.Format("Requested page: %s", tostring(requestedKey or "unknown")), 14, -68, ctx.width - 28, T.colors.dim)
    ctx:SetContentHeight(210)
end

local function TrimText(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ShortLabel(text, limit)
    text = TrimText(text)
    limit = tonumber(limit) or 22
    if #text <= limit then return text end
    return text:sub(1, math.max(1, limit - 3)) .. "..."
end

local function NormalizeSearchText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("[/\\_%-%.:;,%(%)]", " ")
    text = string.lower(text)
    text = text:gsub("[^%w%s]+", " ")
    text = text:gsub("%s+", " ")
    return TrimText(text)
end

local function AddSearchText(parts, text)
    if text == nil then return end
    text = tostring(text)
    if text == "" then return end
    parts[#parts + 1] = text
    local translated = M.Tr(text)
    if translated and translated ~= text then parts[#parts + 1] = translated end
end

local function AddRawSearchText(parts, text)
    if text == nil then return end
    text = tostring(text)
    if text ~= "" then parts[#parts + 1] = text end
end

local function CollectCachedPageText(frame, parts, depth)
    if not frame or depth > 5 then return end
    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
                AddSearchText(parts, region:GetText())
            end
        end
    end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            CollectCachedPageText(children[i], parts, depth + 1)
        end
    end
end

local function BuildSearchRecords()
    local groupLabels = {}
    for i = 1, #NAV do
        local item = NAV[i]
        if item.header then groupLabels[item.id or item.header] = item.header end
    end

    local records, seen = {}, {}
    local function AddRecord(key, label, group)
        if not key or key == "search" or seen[key] then return end
        seen[key] = true
        local spec = M.pages[key]
        local parts = {}
        AddSearchText(parts, label or key)
        AddSearchText(parts, group)
        if spec then AddSearchText(parts, spec.title) end
        AddRawSearchText(parts, SEARCH_KEYWORDS[key])
        local cached = M.cache and M.cache[key]
        if cached and cached.wrapper then CollectCachedPageText(cached.wrapper, parts, 1) end

        local displayLabel = M.Tr(label or (spec and spec.title) or key)
        local displayGroup = group and M.Tr(group) or ""
        local displayTitle = M.Tr((spec and spec.title) or label or key)
        local haystack = NormalizeSearchText(table.concat(parts, " "))
        records[#records + 1] = {
            key = key,
            label = displayLabel,
            group = displayGroup,
            title = displayTitle,
            labelNorm = NormalizeSearchText(displayLabel),
            groupNorm = NormalizeSearchText(displayGroup),
            titleNorm = NormalizeSearchText(displayTitle),
            haystack = haystack,
        }
    end

    for i = 1, #NAV do
        local item = NAV[i]
        if item.key then
            AddRecord(item.key, item.label, item.group and groupLabels[item.group] or nil)
        end
    end
    for i = 1, #(M.pageOrder or {}) do
        local key = M.pageOrder[i]
        local spec = M.pages[key]
        AddRecord(key, spec and spec.title or key, nil)
    end
    return records
end

local function SearchPages(query)
    query = TrimText(query)
    local normalized = NormalizeSearchText(query)
    local words = {}
    for word in normalized:gmatch("%S+") do
        words[#words + 1] = word
    end
    if #words == 0 then return {} end

    local results = {}
    local records = BuildSearchRecords()
    for i = 1, #records do
        local rec = records[i]
        local haystack = rec.haystack or ""
        local score = 0
        local matched = true
        for w = 1, #words do
            local word = words[w]
            if not haystack:find(word, 1, true) then
                matched = false
                break
            end
            if rec.labelNorm == word or rec.titleNorm == word then score = score + 180 end
            if rec.labelNorm:sub(1, #word) == word or rec.titleNorm:sub(1, #word) == word then score = score + 90 end
            if rec.labelNorm:find(word, 1, true) then score = score + 70 end
            if rec.titleNorm:find(word, 1, true) then score = score + 55 end
            if rec.groupNorm:find(word, 1, true) then score = score + 35 end
            score = score + 10
        end
        if matched then
            if rec.labelNorm == normalized or rec.titleNorm == normalized then score = score + 260 end
            if rec.labelNorm:sub(1, #normalized) == normalized then score = score + 130 end
            rec.score = score
            results[#results + 1] = rec
        end
    end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return tostring(a.label) < tostring(b.label)
    end)
    return results
end

local function OpenSearchResults(query)
    M.searchQuery = TrimText(query)
    M.searchResults = SearchPages(M.searchQuery)
    M.searchResultsQuery = M.searchQuery
    M.InvalidatePage("search")
    if M.activeKey ~= "search" then M.searchReturnKey = M.activeKey or M.searchReturnKey or "home" end
    M.SelectPage("search")
end

local function SearchWords(query)
    local normalized = NormalizeSearchText(query)
    local words = {}
    for word in normalized:gmatch("%S+") do
        words[#words + 1] = word
    end
    return normalized, words
end

local function ScoreAnchorText(text, query, fallback)
    local normalized = NormalizeSearchText(text)
    if normalized == "" then return 0 end
    local queryNorm, words = SearchWords(query)
    if #words == 0 and fallback then queryNorm, words = SearchWords(fallback) end
    if #words == 0 then return 0 end

    local score, matched = 0, 0
    if queryNorm ~= "" then
        if normalized == queryNorm then score = score + 900 end
        if normalized:find(queryNorm, 1, true) then score = score + 260 end
    end
    for i = 1, #words do
        local word = words[i]
        if normalized == word then
            score = score + 220
            matched = matched + 1
        elseif normalized:sub(1, #word) == word then
            score = score + 130
            matched = matched + 1
        elseif normalized:find(word, 1, true) then
            score = score + 70
            matched = matched + 1
        end
    end
    if matched == 0 then return 0 end
    if matched == #words then score = score + 180 else score = score - ((#words - matched) * 35) end
    if #normalized <= 42 then score = score + 30 end
    if #normalized > 120 then score = score - 40 end
    return score
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

local function FindSearchAnchor(pageKey, query, fallback)
    local entry = M.cache and M.cache[pageKey]
    local wrapper = entry and entry.wrapper
    if not wrapper then return nil end
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
    local childH = (M.scrollChild and M.scrollChild.GetHeight and M.scrollChild:GetHeight()) or CONTENT_H
    local frameH = (M.scrollFrame and M.scrollFrame.GetHeight and M.scrollFrame:GetHeight()) or CONTENT_H
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
    highlight:SetSize(math.max(220, (wrapper.GetWidth and wrapper:GetWidth() or CONTENT_W) - 28), 32)
    highlight:SetAlpha(1)
    highlight:Show()
    if highlight._msuf2Anim and highlight._msuf2Anim.Play then highlight._msuf2Anim:Play() end
end

local function RunSoon(fn)
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, fn)
    else
        fn()
    end
end

local function ScrollToSearchAnchor(pageKey, query, fallback)
    if M.activeKey ~= pageKey then return end
    local entry = M.cache and M.cache[pageKey]
    local wrapper = entry and entry.wrapper
    if not wrapper then return end

    local region = FindSearchAnchor(pageKey, query, fallback)
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

local function OpenSearchTarget(pageKey, query, fallback)
    if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
    M.SelectPage(pageKey)
    RunSoon(function() ScrollToSearchAnchor(pageKey, query, fallback) end)
end

local function BuildSearchPage(ctx)
    local root = ctx.wrapper
    local width = ctx.width
    local query = TrimText(M.searchQuery or "")
    local results = M.searchResults
    if M.searchResultsQuery ~= query then
        results = SearchPages(query)
        M.searchResults = results
        M.searchResultsQuery = query
    end

    local b = W.PageBuilder(ctx)
    b:Header("Search", query ~= "" and M.Format("Results for \"%s\"", query) or "Type in the search box on the left.", 78)

    local maxVisible = 32
    local visible = math.min(#results, maxVisible)
    local columns = width >= 760 and 2 or 1
    local gap = 12
    local colW = math.floor((width - 24 - gap * (columns - 1)) / columns)
    local rows = math.max(3, math.ceil(math.max(visible, 1) / columns))
    local sectionH = math.max(160, 74 + rows * 30)
    local sec = b:Section("Search Results", sectionH)

    if query == "" then
        W.Text(sec, "Start typing to search every MSUF2 menu page.", 14, -44, width - 28, T.colors.muted)
    elseif #results == 0 then
        W.Text(sec, M.Format("No results for \"%s\".", query), 14, -44, width - 28, T.colors.muted)
        W.Text(sec, "Try a page name like bars, profiles, auras, castbar, colors, group, or target.", 14, -70, width - 28, T.colors.dim)
    else
        W.Text(sec, M.Format("%d result(s). Press Enter to open the first match.", #results), 14, -44, width - 28, T.colors.muted)
        for i = 1, visible do
            local rec = results[i]
            local col = (i - 1) % columns
            local row = math.floor((i - 1) / columns)
            local x = 14 + col * (colW + gap)
            local y = -70 - row * 30
            local text = rec.group ~= "" and (rec.group .. " > " .. rec.label) or rec.label
            local btn = T.Button(sec, text, colW, 22)
            btn:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            local pageKey = rec.key
            local fallback = rec.title or rec.label
            btn:SetScript("OnClick", function()
                OpenSearchTarget(pageKey, query, fallback)
            end)
        end
        if #results > maxVisible then
            W.Text(sec, M.Format("Showing first %d matches. Keep typing to narrow the list.", maxVisible), 14, -70 - rows * 30, width - 28, T.colors.dim)
        end
    end

    local quick = b:Section("Common Searches", 94)
    local shortcuts = {
        { "Profiles", "profiles" },
        { "Group Frames", "gf_layout" },
        { "Bars", "opt_bars" },
        { "Colors", "opt_colors" },
        { "Castbar", "opt_castbar" },
        { "Unit Auras", "auras2" },
    }
    local buttonW = math.floor((width - 56) / 3)
    for i = 1, #shortcuts do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local pageKey = shortcuts[i][2]
        local btn = T.Button(quick, shortcuts[i][1], buttonW, 22)
        btn:SetPoint("TOPLEFT", quick, "TOPLEFT", 14 + col * (buttonW + 14), -38 - row * 28)
        btn:SetScript("OnClick", function()
            if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
            M.SelectPage(pageKey)
        end)
    end

    ctx:SetContentHeight(math.max(CONTENT_H, math.abs(b.y) + 42))
end

function M.SelectPage(key)
    key = ALIASES[key or ""] or key or "home"
    local spec = M.pages[key]
    local cached = M.cache[key]
    local specVersion = spec and spec.version
    if cached and specVersion and cached.version ~= specVersion then
        M.InvalidatePage(key)
        cached = nil
        if M.activeKey == key then M.activeKey = nil end
    end
    if key == M.activeKey and cached then
        RunRefreshers(cached)
        SyncBossPagePreviewForKey(key)
        SyncGroupPagePreviewForKey(key)
        return true
    end

    HideAllCachedPages()
    SyncBossPagePreviewForKey(nil)
    SyncGroupPagePreviewForKey(IsGroupPageKey(key) and key or nil)

    local entry = M.cache[key]
    if not entry then
        local wrapper = CreateFrame("Frame", nil, M.scrollChild)
        wrapper:SetPoint("TOPLEFT", M.scrollChild, "TOPLEFT", 0, 0)
        wrapper:SetSize(CONTENT_W - 10, CONTENT_H)
        entry = { wrapper = wrapper, refreshers = {}, height = CONTENT_H, version = specVersion }
        M.cache[key] = entry

        local ctx = CreateContext(key, wrapper, entry)
        if spec and type(spec.build) == "function" then
            local ok, result = pcall(spec.build, ctx)
            if ok and tonumber(result) then ctx:SetContentHeight(result) end
        else
            BuildPlaceholderPage(ctx, key)
        end
    end

    M.activeKey = key
    if M.frame then M.frame._msufCurrentKey = key end
    if M.scrollFrame and M.scrollFrame.SetVerticalScroll then
        M.scrollFrame:SetVerticalScroll(0)
    end
    if M.scrollChild then
        M.scrollChild:SetHeight(entry.height or CONTENT_H)
    end
    entry.wrapper:Show()
    RunRefreshers(entry)
    SetTitle(key)
    UpdateNav(key)
    SyncBossPagePreviewForKey(key)
    SyncGroupPagePreviewForKey(key)
    return true
end

local function CreateNavButton(parent, key, label, indent)
    local btn = T.Button(parent, M.Tr(label), NAV_W - 24 - (indent or 0), NAV_BUTTON_H)
    btn:SetScript("OnClick", function() M.SelectPage(key) end)
    btn._msuf2SkipHistoryCheckpoint = true
    btn._msuf2NavIndent = indent or 0
    btn._msuf2RawLabel = label
    if T.AttachNavIcon then T.AttachNavIcon(btn, key, (indent or 0) > 0) end
    M.navButtons[key] = btn
    return btn
end

local function AttachHistoryTooltip(btn, getTitle, getText)
    if not btn then return end
    btn:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local title = type(getTitle) == "function" and getTitle(self) or getTitle
        local text = type(getText) == "function" and getText(self) or getText
        GameTooltip:AddLine(M.Tr(title or ""), 1, 1, 1)
        if text and text ~= "" then GameTooltip:AddLine(M.Tr(text), 0.72, 0.78, 0.92, true) end
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function HistoryTooltipText(kind)
    local s = M.GetHistoryState and M.GetHistoryState() or {}
    local label = (kind == "undo") and s.undoLabel or s.redoLabel
    local canUse = (kind == "undo") and s.canUndo or s.canRedo
    if canUse and label then
        local text = M.Format("%s\nUndo: %d   Redo: %d", ShortLabel(label, 36), tonumber(s.undoCount) or 0, tonumber(s.redoCount) or 0)
        if kind == "undo" and s.canResetAll then
            text = text .. "\n" .. M.Tr("Shift-click: reset all MSUF2 menu changes from this open session.")
        end
        return text
    end
    return M.Format("No %s action in this MSUF2 menu session.\nUndo: %d   Redo: %d",
        kind == "undo" and "undo" or "redo",
        tonumber(s.undoCount) or 0,
        tonumber(s.redoCount) or 0)
end

local function CreateHistoryControls(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(NAV_W - 24, 26)

    local undo = T.Button(row, "", 62, 22)
    T.SkinDangerButton(undo)
    undo._msuf2SkipHistoryCheckpoint = true
    undo._msuf2HistorySource = "history:undo"
    undo._msuf2HistoryLabel = "Undo"
    undo:SetPoint("LEFT", row, "LEFT", 9, 0)
    if undo._msuf2Label then undo._msuf2Label:Hide() end
    local undoIcon = undo:CreateTexture(nil, "ARTWORK", nil, 5)
    undoIcon:SetTexture(T.media.historyUndo)
    undoIcon:SetSize(17, 17)
    undoIcon:SetPoint("CENTER", undo, "CENTER", 0, 0)
    undo._msuf2HistoryIcon = undoIcon
    undo:SetScript("OnClick", function()
        if _G.IsShiftKeyDown and _G.IsShiftKeyDown() and M.ResetHistorySession then
            M.ResetHistorySession()
        elseif M.Undo then
            M.Undo()
        end
    end)

    local redo = T.Button(row, "", 62, 22)
    T.SkinSuccessButton(redo)
    redo._msuf2SkipHistoryCheckpoint = true
    redo._msuf2HistorySource = "history:redo"
    redo._msuf2HistoryLabel = "Redo"
    redo:SetPoint("LEFT", undo, "RIGHT", 8, 0)
    if redo._msuf2Label then redo._msuf2Label:Hide() end
    local redoIcon = redo:CreateTexture(nil, "ARTWORK", nil, 5)
    redoIcon:SetTexture(T.media.historyRedo)
    redoIcon:SetSize(17, 17)
    redoIcon:SetPoint("CENTER", redo, "CENTER", 0, 0)
    redo._msuf2HistoryIcon = redoIcon
    redo:SetScript("OnClick", function()
        if M.Redo then M.Redo() end
    end)

    AttachHistoryTooltip(undo, function()
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        return s.undoLabel and ("Undo: " .. ShortLabel(s.undoLabel, 28)) or "Undo"
    end, function() return HistoryTooltipText("undo") end)
    AttachHistoryTooltip(redo, function()
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        return s.redoLabel and ("Redo: " .. ShortLabel(s.redoLabel, 28)) or "Redo"
    end, function() return HistoryTooltipText("redo") end)

    row.undo = undo
    row.redo = redo
    M.historyControls = row

    function M.RefreshHistoryControls()
        local controls = M.historyControls
        if not controls then return end
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        local canUndo = s.canUndo and true or false
        local canRedo = s.canRedo and true or false
        local canResetAll = s.canResetAll and true or false
        if controls.undo and controls.undo.SetEnabled then controls.undo:SetEnabled(canUndo or canResetAll) end
        if controls.redo and controls.redo.SetEnabled then controls.redo:SetEnabled(canRedo) end
        if controls.undo and controls.undo._msuf2HistoryIcon then controls.undo._msuf2HistoryIcon:SetAlpha((canUndo or canResetAll) and 1 or 0.34) end
        if controls.redo and controls.redo._msuf2HistoryIcon then controls.redo._msuf2HistoryIcon:SetAlpha(canRedo and 1 or 0.34) end
    end

    M.RefreshHistoryControls()
    return row
end

local function BuildNav(parent)
    M.navButtons = {}
    M.navHeaders = {}
    M.navGroupForKey = {}
    M.navHeaderState = M.navHeaderState or {}
    local search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
    search:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8)
    search:SetHeight(20)
    search:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 20)
    search:EnableMouse(true)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search:SetTextInsets(6, 22, 0, 0)
    T.SkinEditBox(search)
    if search.Instructions then search.Instructions:SetText(M.Tr("Search settings...")) end
    parent.searchBox = search
    search:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self:SetFocus() end
    end)
    search:HookScript("OnEditFocusGained", function(self)
        if self.HighlightText then self:HighlightText() end
    end)
    search:HookScript("OnEditFocusLost", function(self)
        if self.HighlightText then self:HighlightText(0, 0) end
    end)
    search:SetScript("OnTextChanged", function(self)
        if self._msuf2SearchInternal then return end
        local query = TrimText(self:GetText() or "")
        M.searchQuery = query
        M.searchResults = SearchPages(query)
        M.searchResultsQuery = query
        if query ~= "" then
            if M.activeKey ~= "search" then M.searchReturnKey = M.activeKey or M.searchReturnKey or "home" end
            M.InvalidatePage("search")
            M.SelectPage("search")
        elseif M.activeKey == "search" then
            M.InvalidatePage("search")
            M.SelectPage(M.searchReturnKey or "home")
        end
    end)
    search:SetScript("OnEnterPressed", function(self)
        local query = TrimText(self:GetText() or "")
        if query == "" then
            self:ClearFocus()
            return
        end
        M.searchQuery = query
        M.searchResults = SearchPages(query)
        M.searchResultsQuery = query
        if M.searchResults and M.searchResults[1] then
            local first = M.searchResults[1]
            OpenSearchTarget(first.key, query, first.title or first.label)
        else
            OpenSearchResults(query)
        end
    end)
    search:SetScript("OnEscapePressed", function(self)
        self._msuf2SearchInternal = true
        self:SetText("")
        self._msuf2SearchInternal = nil
        self:ClearFocus()
        M.searchQuery = ""
        M.searchResults = {}
        M.searchResultsQuery = ""
        if M.activeKey == "search" then M.SelectPage(M.searchReturnKey or "home") end
    end)

    local clear = CreateFrame("Button", nil, parent)
    clear:SetSize(16, 16)
    clear:SetFrameLevel(search:GetFrameLevel() + 1)
    clear:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    local clearText = T.Font(clear, "GameFontDisableSmall", "x", T.colors.dim)
    clearText:SetPoint("CENTER", clear, "CENTER", 0, 0)
    clear:Hide()
    clear:SetScript("OnClick", function()
        search._msuf2SearchInternal = true
        search:SetText("")
        search._msuf2SearchInternal = nil
        M.searchQuery = ""
        M.searchResults = {}
        M.searchResultsQuery = ""
        clear:Hide()
        if M.activeKey == "search" then M.SelectPage(M.searchReturnKey or "home") end
        search:SetFocus()
    end)
    search:HookScript("OnTextChanged", function(self)
        clear:SetShown(TrimText(self:GetText() or "") ~= "")
    end)

    local created = {}
    for i = 1, #NAV do
        local item = NAV[i]
        if item.header then
            local id = item.id or item.header
            if M.navHeaderState[id] == nil then M.navHeaderState[id] = item.defaultOpen ~= false end
            local btn = T.Button(parent, string.upper(M.Tr(item.header)), NAV_W - 24, NAV_BUTTON_H)
            btn._msuf2NavHeaderId = id
            btn._msuf2RawLabel = item.header
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("LEFT", 24, 0)
            btn._msuf2Label:SetPoint("RIGHT", -8, 0)
            btn._msuf2Label:SetJustifyH("LEFT")
            btn._msuf2Label:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.88)
            local arrow = btn:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(10, 10)
            arrow:SetPoint("LEFT", btn, "LEFT", 5, 0)
            arrow:SetTexture(T.media.collapseArrow)
            arrow:SetVertexColor(0.45, 0.55, 0.72, 1)
            btn._msuf2NavArrow = arrow
            btn:SetScript("OnClick", function(self)
                local groupId = self._msuf2NavHeaderId
                M.navHeaderState[groupId] = not M.navHeaderState[groupId]
                if parent._msuf2NavReflow then parent:_msuf2NavReflow() end
            end)
            btn._msuf2SkipHistoryCheckpoint = true
            M.navHeaders[id] = btn
            created[#created + 1] = { kind = "header", id = id, button = btn }
        elseif item.key then
            local indent = item.group and 12 or 0
            local btn = CreateNavButton(parent, item.key, item.label, indent)
            if item.group then M.navGroupForKey[item.key] = item.group end
            created[#created + 1] = { kind = "page", group = item.group, button = btn }
            if item.key == "profiles" then
                created[#created + 1] = { kind = "history", frame = CreateHistoryControls(parent) }
            end
        end
    end
    function parent:_msuf2NavReflow()
        local y = -38
        for i = 1, #created do
            local item = created[i]
            local btn = item.button
            if item.kind == "header" then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
                if btn._msuf2NavArrow then
                    btn._msuf2NavArrow:SetRotation(M.navHeaderState[item.id] and (math.pi * 0.5) or 0)
                    btn._msuf2NavArrow:SetVertexColor(0.45, 0.55, 0.72, 1)
                end
                y = y - NAV_BUTTON_STEP
            elseif item.kind == "history" then
                local frame = item.frame
                frame:Show()
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y - 2)
                y = y - 32
            elseif not item.group or M.navHeaderState[item.group] then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 12 + (btn._msuf2NavIndent or 0), y)
                y = y - NAV_BUTTON_STEP
            else
                if btn then btn:Hide() end
                if item.frame then item.frame:Hide() end
            end
        end
        if M.RefreshHistoryControls then M.RefreshHistoryControls() end
    end
    parent:_msuf2NavReflow()
end

local function BuildWindow()
    if M.frame then return M.frame end

    SetWindowMetrics(ReadSavedWindowSize())
    local f = T.Panel(UIParent, "MSUF2_Window", T.colors.bg, T.colors.border)
    _G.MSUF_StandaloneOptionsWindow = f
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER", UIParent, "CENTER", -60, 10)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    ApplyWindowResizeBounds(f)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetScript("OnSizeChanged", function(self)
        RefreshWindowMetrics(self)
        ApplyScrollMetrics()
    end)
    f:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "MSUF2_Window")
    end

    local title = T.Font(f, "GameFontDisableSmall", "MSUF", T.colors.accent)
    title:SetPoint("TOPLEFT", 12, -6)
    title:SetAlpha(0.50)
    f.title = title

    local subtitle = T.Font(f, "GameFontDisableSmall", "", T.colors.muted)
    subtitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -48, -14)
    subtitle:SetJustifyH("RIGHT")
    subtitle:Hide()
    f.subtitle = subtitle

    local close = T.CloseButton(f)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and f.StartSizing then
            ApplyWindowResizeBounds(f)
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function()
        if f.StopMovingOrSizing then f:StopMovingOrSizing() end
        ClampWindowSize(f)
        RebuildActivePageForResize(f)
    end)
    grip:SetScript("OnHide", function()
        if f.StopMovingOrSizing then f:StopMovingOrSizing() end
    end)
    f.resizeGrip = grip

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -30)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    f.content = content

    local nav = T.Panel(content, nil, T.colors.panelNav or T.colors.panel, T.colors.borderSoft)
    nav:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    nav:SetWidth(NAV_W)
    f.nav = nav
    f._msufNavRail = nav
    f._msufNavStack = nav
    M.nav = nav
    BuildNav(nav)

    local host = T.Panel(content, nil, T.colors.panel, T.colors.borderSoft)
    host:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    f.host = host
    f._msufMirrorHost = host
    if T.ApplyMenuAtmosphere then T.ApplyMenuAtmosphere(f, host, nav) end

    local status = T.Panel(host, nil, T.colors.header, T.colors.borderSoft)
    status:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    status:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    status:SetHeight(22)
    local statusTopLine = status:CreateTexture(nil, "ARTWORK", nil, 6)
    statusTopLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    statusTopLine:SetHeight(1)
    statusTopLine:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 0)
    statusTopLine:SetPoint("TOPRIGHT", status, "TOPRIGHT", 0, 0)
    statusTopLine:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.25)

    local sbProfile = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
    sbProfile:SetPoint("LEFT", status, "LEFT", 10, 0)
    sbProfile:SetJustifyH("LEFT")
    local sbEdit = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
    sbEdit:SetPoint("LEFT", sbProfile, "RIGHT", 14, 0)
    sbEdit:SetJustifyH("LEFT")
    local sbCombat = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
    sbCombat:SetPoint("LEFT", sbEdit, "RIGHT", 14, 0)
    sbCombat:SetJustifyH("LEFT")
    local sbVersion = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
    sbVersion:SetPoint("RIGHT", status, "RIGHT", -10, 0)
    sbVersion:SetJustifyH("RIGHT")
    sbVersion:SetAlpha(0.50)

    status.profileText = sbProfile
    status.editText = sbEdit
    status.combatText = sbCombat
    status.versionText = sbVersion
    status.text = sbProfile
    f.status = status
    function f:RefreshStatus()
        local profile = tostring(_G.MSUF_ActiveProfile or "Default")
        local edit = IsEditModeActive() and "On" or "Off"
        sbProfile:SetText("|cff4a90d9" .. M.Tr("Profile:") .. "|r |cffccd8e8" .. profile .. "|r  |cff3a4a66\194\183|r")
        if edit == "On" then
            sbEdit:SetText("|cff4ade80" .. M.Tr("Edit: On") .. "|r  |cff3a4a66\194\183|r")
        else
            sbEdit:SetText("|cff5a6a88" .. M.Tr("Edit: Off") .. "|r  |cff3a4a66\194\183|r")
        end
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            sbCombat:SetText("|cffef4444" .. M.Tr("In Combat") .. "|r")
        else
            sbCombat:SetText("|cff22c55e" .. M.Tr("Out of Combat") .. "|r")
        end
        local ver = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
        if type(ver) == "string" and ver ~= "" then
            sbVersion:SetText((ver:sub(1, 1) == "v") and ver or ("v" .. ver))
        else
            sbVersion:SetText("v5.0 Beta 1")
        end
        RefreshDashboardEditModeButton()
    end
    local function RegisterStatusEvents()
        if status._msuf2EventsRegistered then return end
        status._msuf2EventsRegistered = true
        status:RegisterEvent("PLAYER_REGEN_DISABLED")
        status:RegisterEvent("PLAYER_REGEN_ENABLED")
        status:RegisterEvent("GROUP_ROSTER_UPDATE")
        status:RegisterEvent("PLAYER_ENTERING_WORLD")
        status:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    end
    local function UnregisterStatusEvents()
        if not status._msuf2EventsRegistered then return end
        status._msuf2EventsRegistered = nil
        status:UnregisterEvent("PLAYER_REGEN_DISABLED")
        status:UnregisterEvent("PLAYER_REGEN_ENABLED")
        status:UnregisterEvent("GROUP_ROSTER_UPDATE")
        status:UnregisterEvent("PLAYER_ENTERING_WORLD")
        status:UnregisterEvent("PLAYER_DIFFICULTY_CHANGED")
    end
    status:SetScript("OnEvent", function()
        if not (f and f:IsShown()) then
            UnregisterStatusEvents()
            return
        end
        f:RefreshStatus()
        if M.Refresh then M.Refresh() end
        SyncGroupPagePreviewForKey(M.activeKey)
    end)
    f:SetScript("OnShow", function(self)
        if M.StartHistorySession then M.StartHistorySession() end
        RegisterStatusEvents()
        EnsureEditModeUIHook()
        if self.RefreshStatus then self:RefreshStatus() end
        SyncBossPagePreviewForKey(M.activeKey)
        SyncGroupPagePreviewForKey(M.activeKey)
    end)
    f:SetScript("OnHide", function()
        UnregisterStatusEvents()
        if W and type(W.CloseDropdown) == "function" then W.CloseDropdown() end
        if M.EndHistorySession then M.EndHistorySession() end
        SyncBossPagePreviewForKey(nil)
        SyncGroupPagePreviewForKey(nil)
    end)

    local scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 0)
    f.scrollFrame = scroll
    M.scrollFrame = scroll

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CONTENT_W - 10, CONTENT_H)
    scroll:SetScrollChild(child)
    M.scrollChild = child

    M.frame = f
    return f
end

local function BuildDashboard(ctx)
    local root = ctx.wrapper
    local width = ctx.width
    local gap = 14
    local x0 = 12
    local y = -12
    local colW = math.floor((width - gap) / 2)

    local function Card(title, x, top, w, h)
        local card = T.Panel(root, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
        card:SetPoint("TOPLEFT", root, "TOPLEFT", x, top)
        card:SetSize(w, h)
        local label = T.Font(card, "GameFontNormal", title or "", T.colors.text)
        label:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -12)
        card._msuf2Title = label
        return card
    end

    local function AddButton(parent, text, x, top, w, h, onClick)
        local btn = T.Button(parent, text, w, h or 22)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
        if onClick then btn:SetScript("OnClick", onClick) end
        return btn
    end

    local tip = Card("Dashboard", x0, y, width, 98)
    W.Text(tip, "Tip: Quick reset: If something feels off, try /msuf reset for frame positions.", 14, -42, width - 28, T.colors.muted)
    local actionW = math.floor((width - 40) / 2)
    local editMode = AddButton(tip, "Edit Mode: Off", 14, -64, actionW, 24, function()
        local active = IsEditModeActive()
        if (not active) and IsEditModeCombatLocked() then
            RefreshDashboardEditModeButton()
            if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
            return
        end
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            _G.MSUF_SetMSUFEditModeDirect(not active)
        end
        RefreshDashboardEditModeButton()
        if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    end)
    M.dashboardEditModeButton = editMode
    if T.SkinPrimaryButton then T.SkinPrimaryButton(editMode) end
    RefreshDashboardEditModeButton()
    M.AddRefresher(ctx, RefreshDashboardEditModeButton)
    local reset = AddButton(tip, "Reset Positions", 26 + actionW, -64, actionW, 24, function()
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], "reset")
        end
    end)
    T.SkinDangerButton(reset)

    y = y - 110
    local quick = Card("Quick Navigation", x0, y, colW, 108)
    W.Text(quick, "Jump into the most-used MSUF sections.", 14, -36, colW - 28, T.colors.muted)
    local qW = math.floor((colW - 40) / 2)
    AddButton(quick, "Colors", 14, -62, qW, 20, function() M.SelectPage("opt_colors") end)
    AddButton(quick, "Gameplay", 26 + qW, -62, qW, 20, function() M.SelectPage("gameplay") end)
    AddButton(quick, "Unit Auras", 14, -88, qW, 20, function() M.SelectPage("auras2") end)
    AddButton(quick, "Class Resources", 26 + qW, -88, qW, 20, function() M.SelectPage("classpower") end)

    local profile = Card("Active Profile", x0 + colW + gap, y, colW, 108)
    local prof = tostring(_G.MSUF_ActiveProfile or "Default")
    local pText = T.Font(profile, "GameFontNormalLarge", prof, T.colors.text)
    pText:SetPoint("TOPLEFT", profile, "TOPLEFT", 14, -40)
    W.Text(profile, "Use the Profiles page for switching, export and import.", 14, -68, colW - 140, T.colors.muted)
    AddButton(profile, "Manage", colW - 114, -34, 100, 22, function() M.SelectPage("profiles") end)
    M.AddRefresher(ctx, function()
        pText:SetText(tostring(_G.MSUF_ActiveProfile or "Default"))
    end)

    y = y - 120
    local scaleCardH = 448
    local scale = Card("UI Scale", x0, y, colW, scaleCardH)
    local wago = Card("Wago Profiles", x0 + colW + gap, y, colW, scaleCardH)

    local function Clamp(v, minV, maxV)
        v = tonumber(v) or minV
        if v < minV then return minV end
        if v > maxV then return maxV end
        return v
    end

    local function SnapPct(value, minPct, maxPct, stepPct)
        stepPct = stepPct or 1
        local pct = math.floor((tonumber(value) or 100) / stepPct + 0.5) * stepPct
        return Clamp(pct, minPct or 25, maxPct or 150)
    end

    local function SetSliderValueSafe(slider, value)
        if not (slider and slider.SetValue) then return end
        slider._msuf2Refreshing = true
        slider:SetValue(value)
        if slider.editBox and slider._msuf2FormatValue then slider.editBox:SetText(slider._msuf2FormatValue(value)) end
        if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        slider._msuf2Refreshing = nil
    end

    local function HideSliderValueBox(slider)
        if slider and slider.editBox then slider.editBox:Hide() end
        if slider and slider._msuf2StepButtons then
            for i = 1, #slider._msuf2StepButtons do
                slider._msuf2StepButtons[i]:Hide()
            end
        end
        if slider and slider._msuf2Title and slider._msuf2Title.SetFontObject then
            slider._msuf2Title:SetFontObject("GameFontHighlight")
        end
    end

    local function EnablePercentWheel(slider, minPct, maxPct, stepPct)
        if not slider then return end
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            if not delta then return end
            local value = tonumber((self.GetValue and self:GetValue()) or 100) or 100
            value = value + ((delta > 0) and stepPct or -stepPct)
            self:SetValue(SnapPct(value, minPct, maxPct, stepPct))
        end)
    end

    local function PixelScale()
        if type(_G.MSUF_GetPixelPerfectScale) == "function" then
            local ok, v = pcall(_G.MSUF_GetPixelPerfectScale)
            if ok and tonumber(v) then return Clamp(v, 0.3, 1.5) end
        end
        if type(GetPhysicalScreenSize) == "function" then
            local _, h = GetPhysicalScreenSize()
            h = tonumber(h)
            if h and h > 0 then return Clamp(768 / h, 0.3, 1.5) end
        end
        return 1
    end

    local function GlobalState()
        local g = M.GetGeneralDB()
        g.UIScale = (type(g.UIScale) == "table") and g.UIScale or { Enabled = false, Scale = 1 }
        local ui = g.UIScale
        ui.Enabled = ui.Enabled == true
        ui.Scale = Clamp(ui.Scale, 0.3, 1.5)
        return g, ui
    end

    local pendingGlobalEnabled, pendingGlobalScale
    local globalStatus = W.Text(scale, "", 14, -54, colW - 28, T.colors.muted)
    local globalScale = W.Slider(scale, "Global UI Scale", 30, 150, 1, colW - 54)
    HideSliderValueBox(globalScale)
    globalScale:ClearAllPoints()
    globalScale:SetPoint("TOPLEFT", scale, "TOPLEFT", 14, -72)
    globalScale:SetPoint("RIGHT", scale, "RIGHT", -26, 0)
    globalScale._msuf2Title:ClearAllPoints()
    globalScale._msuf2Title:SetPoint("TOPLEFT", scale, "TOPLEFT", 14, -34)
    EnablePercentWheel(globalScale, 30, 150, 1)

    local function RefreshGlobalScale()
        local _, ui = GlobalState()
        local selectedEnabled = (pendingGlobalEnabled ~= nil) and pendingGlobalEnabled or ui.Enabled
        local selectedScale = Clamp(pendingGlobalScale or ui.Scale, 0.3, 1.5)
        local applied = ui.Enabled and (math.floor(ui.Scale * 100 + 0.5) .. "%") or "Off"
        local selected = selectedEnabled and (math.floor(selectedScale * 100 + 0.5) .. "%") or "Off"
        globalStatus:SetText(M.Format("Applied: %s   Selected: %s", applied, selected))
        SetSliderValueSafe(globalScale, SnapPct(selectedScale * 100, 30, 150, 1))
    end

    globalScale:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        local pct = SnapPct(value, 30, 150, 1)
        if pct ~= value then
            SetSliderValueSafe(self, pct)
        end
        pendingGlobalEnabled = true
        pendingGlobalScale = Clamp(pct / 100, 0.3, 1.5)
        RefreshGlobalScale()
    end)

    local function ApplyGlobalScale(enabled, value, preset)
        local g, ui = GlobalState()
        ui.Enabled = enabled == true
        ui.Scale = Clamp(value or ui.Scale, 0.3, 1.5)
        g.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
        g.globalUiScaleValue = ui.Enabled and ui.Scale or nil
        pendingGlobalEnabled, pendingGlobalScale = nil, nil
        if ui.Enabled and type(_G.MSUF_SetGlobalUiScale) == "function" then
            pcall(_G.MSUF_SetGlobalUiScale, ui.Scale, true)
        elseif (not ui.Enabled) and type(_G.MSUF_ResetGlobalUiScale) == "function" then
            pcall(_G.MSUF_ResetGlobalUiScale, true)
        end
        M.RequestGeneralApply("MSUF2_DASH_GLOBAL_SCALE", { preview = true, applyAll = false })
        RefreshGlobalScale()
    end

    AddButton(scale, "1080p", 14, -104, 62, 18, function() ApplyGlobalScale(true, 768 / 1080, "1080p") end)
    AddButton(scale, "1440p", 82, -104, 62, 18, function() ApplyGlobalScale(true, 768 / 1440, "1440p") end)
    AddButton(scale, "4K", 150, -104, 48, 18, function() ApplyGlobalScale(true, 768 / 2160, "4k") end)
    AddButton(scale, "Pixel", 204, -104, 62, 18, function() ApplyGlobalScale(true, PixelScale(), "pixel") end)
    AddButton(scale, "Apply", 14, -128, 72, 20, function()
        local _, ui = GlobalState()
        local enabled = (pendingGlobalEnabled ~= nil) and pendingGlobalEnabled or ui.Enabled
        ApplyGlobalScale(enabled, pendingGlobalScale or ui.Scale, enabled and "custom" or "auto")
    end)
    AddButton(scale, "Revert", 94, -128, 72, 20, function()
        pendingGlobalEnabled, pendingGlobalScale = nil, nil
        RefreshGlobalScale()
    end)
    AddButton(scale, "Off", 174, -128, 58, 20, function()
        pendingGlobalEnabled = false
        RefreshGlobalScale()
    end)
    AddButton(scale, "UI Off", 240, -128, 72, 20, function() ApplyGlobalScale(false, nil, "auto") end)

    local pendingMsufScale
    local msufStatus = W.Text(scale, M.Format("Applied: %d%%  Selected: %d%%", 100, 100), 14, -168, colW - 28, T.colors.muted)
    scale._msuf2CursorY = -146
    local msufScale = W.Slider(scale, "MSUF Frame Scale", 25, 150, 5, colW - 54)
    HideSliderValueBox(msufScale)
    msufScale:ClearAllPoints()
    msufScale:SetPoint("TOPLEFT", msufStatus, "BOTTOMLEFT", 0, -8)
    msufScale:SetPoint("RIGHT", scale, "RIGHT", -26, 0)
    msufScale._msuf2Title:ClearAllPoints()
    msufScale._msuf2Title:SetPoint("TOPLEFT", scale, "TOPLEFT", 14, -146)
    EnablePercentWheel(msufScale, 25, 150, 5)

    local msufApply, msufRevert
    local function AppliedMsufScale()
        local g = M.GetGeneralDB()
        return Clamp(tonumber(g.msufUiScale) or 1, 0.25, 1.5)
    end
    local function PendingMsufScale()
        return Clamp(pendingMsufScale or AppliedMsufScale(), 0.25, 1.5)
    end
    local function RefreshMsufScale()
        local applied = AppliedMsufScale()
        local pending = PendingMsufScale()
        local changed = math.abs(applied - pending) > 0.001
        msufStatus:SetText(M.Format("Applied: %d%%  Selected: %d%%", math.floor(applied * 100 + 0.5), math.floor(pending * 100 + 0.5)))
        SetSliderValueSafe(msufScale, SnapPct(pending * 100, 25, 150, 5))
        if msufApply then
            if changed then msufApply:Enable() else msufApply:Disable() end
            if msufApply.SetActive then msufApply:SetActive(changed) end
        end
        if msufRevert then
            if changed then msufRevert:Enable() else msufRevert:Disable() end
        end
    end
    msufScale:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        local pct = SnapPct(value, 25, 150, 5)
        if pct ~= value then SetSliderValueSafe(self, pct) end
        pendingMsufScale = pct / 100
        RefreshMsufScale()
    end)
    msufApply = AddButton(scale, "Apply", 14, -214, 72, 20, function()
        local g = M.GetGeneralDB()
        local scaleValue = PendingMsufScale()
        g.msufUiScale = scaleValue
        pendingMsufScale = nil
        M.RequestGeneralApply("MSUF2_DASH_SCALE", { preview = true, applyAll = false })
        if type(_G.ApplyAllSettings) == "function" then pcall(_G.ApplyAllSettings) end
        RefreshMsufScale()
    end)
    msufRevert = AddButton(scale, "Revert", 94, -214, 72, 20, function()
        pendingMsufScale = nil
        RefreshMsufScale()
    end)
    M.AddRefresher(ctx, RefreshMsufScale)

    local pendingMenuScale
    local menuStatus = W.Text(scale, M.Format("Applied: %d%%  Selected: %d%%", 100, 100), 14, -286, colW - 28, T.colors.muted)
    scale._msuf2CursorY = -268
    local menuScale = W.Slider(scale, "MSUF Slash Menu Scale", 25, 150, 5, colW - 54)
    HideSliderValueBox(menuScale)
    menuScale:ClearAllPoints()
    menuScale:SetPoint("TOPLEFT", menuStatus, "BOTTOMLEFT", 0, -8)
    menuScale:SetPoint("RIGHT", scale, "RIGHT", -26, 0)
    menuScale._msuf2Title:ClearAllPoints()
    menuScale._msuf2Title:SetPoint("TOPLEFT", scale, "TOPLEFT", 14, -268)
    EnablePercentWheel(menuScale, 25, 150, 5)

    local menuApply, menuRevert
    local function AppliedMenuScale()
        local g = M.GetGeneralDB()
        return Clamp(tonumber(g.slashMenuScale) or 1, 0.25, 1.5)
    end
    local function PendingMenuScale()
        return Clamp(pendingMenuScale or AppliedMenuScale(), 0.25, 1.5)
    end
    local function RefreshMenuScale()
        local applied = AppliedMenuScale()
        local pending = PendingMenuScale()
        local changed = math.abs(applied - pending) > 0.001
        menuStatus:SetText(M.Format("Applied: %d%%  Selected: %d%%", math.floor(applied * 100 + 0.5), math.floor(pending * 100 + 0.5)))
        SetSliderValueSafe(menuScale, SnapPct(pending * 100, 25, 150, 5))
        if menuApply then
            if changed then menuApply:Enable() else menuApply:Disable() end
            if menuApply.SetActive then menuApply:SetActive(changed) end
        end
        if menuRevert then
            if changed then menuRevert:Enable() else menuRevert:Disable() end
        end
    end
    menuScale:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        local pct = SnapPct(value, 25, 150, 5)
        if pct ~= value then SetSliderValueSafe(self, pct) end
        pendingMenuScale = pct / 100
        RefreshMenuScale()
    end)
    menuApply = AddButton(scale, "Apply", 14, -330, 72, 20, function()
        local g = M.GetGeneralDB()
        local scaleValue = PendingMenuScale()
        g.slashMenuScale = scaleValue
        pendingMenuScale = nil
        if M.frame and M.frame.SetScale then M.frame:SetScale(EffectiveMenuScale(scaleValue)) end
        RefreshMenuScale()
    end)
    menuRevert = AddButton(scale, "Revert", 94, -330, 72, 20, function()
        pendingMenuScale = nil
        RefreshMenuScale()
    end)
    RefreshGlobalScale()
    M.AddRefresher(ctx, RefreshGlobalScale)
    RefreshMsufScale()
    RefreshMenuScale()
    M.AddRefresher(ctx, RefreshMenuScale)

    W.Text(wago, "Browse shared MSUF imports on Wago.", 14, -36, colW - 28, T.colors.muted)
    local browse = AddButton(wago, "Browse Wago Profiles", 14, -64, colW - 42, 34, function()
        if type(_G.MSUF_ShowCopyLink) == "function" then
            _G.MSUF_ShowCopyLink("Wago Profiles", "https://wago.io/search/imports/wow/msuf")
        end
    end)
    if browse._msuf2Label then browse._msuf2Label:SetFontObject("GameFontNormal") end
    if T.SkinPrimaryButton then T.SkinPrimaryButton(browse) end
    W.Text(wago, "Copies the Wago link so you can open it in your browser.", 14, -106, colW - 28, T.colors.muted)

    local function AddIconTooltip(frame, title, text)
        if type(_G.MSUF_AddTooltip) == "function" then
            _G.MSUF_AddTooltip(frame, title, text)
            return
        end
        frame:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine(M.Tr(title or ""), 1, 1, 1)
            if text and text ~= "" then GameTooltip:AddLine(M.Tr(text), 0.85, 0.85, 0.85, true) end
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    local iconDir = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    local links = {
        patreon = "https://www.patreon.com/cw/MidnightSimpleUnitframes",
        paypal = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ",
        kofi = "https://ko-fi.com/midnightsimpleunitframes#linkModal",
        github = "https://github.com/Mapkov2/MidnightSimpleUnitFrames",
    }
    local support = T.Font(wago, "GameFontDisableSmall", "Support MSUF Development", T.colors.muted)
    support:SetPoint("BOTTOMLEFT", wago, "BOTTOMLEFT", 14, 14)
    support:SetWidth(max(120, colW - 198))
    support:SetJustifyH("LEFT")
    local aboutVer
    if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then
        aboutVer = _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
    end
    local aboutText = M.Tr("by Mapko")
    if type(aboutVer) == "string" and aboutVer ~= "" then
        aboutText = M.Format("v%s  -  by Mapko  -  with help from R41z0r", aboutVer)
    end
    local about = T.Font(wago, "GameFontDisableSmall", aboutText, T.colors.muted)
    about:SetPoint("BOTTOMLEFT", support, "TOPLEFT", 0, 4)
    about:SetWidth(max(120, colW - 28))
    about:SetJustifyH("LEFT")

    local iconRow = CreateFrame("Frame", nil, wago)
    iconRow:SetSize(160, 24)
    iconRow:SetPoint("BOTTOMRIGHT", wago, "BOTTOMRIGHT", -12, 12)
    local function CreateSupportIcon(texture, title, tooltip, url)
        local button = CreateFrame("Button", nil, iconRow)
        button:SetSize(22, 22)
        local tex = button:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(iconDir .. texture)
        local hover = button:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.10)
        button:SetScript("OnClick", function()
            if type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink(title, url)
            end
        end)
        AddIconTooltip(button, title, tooltip)
        return button
    end
    local icons = {
        { texture = "Patreon.png", title = "Patreon", tooltip = "Click to copy the Patreon support link.", url = links.patreon },
        { texture = "PayPal.png", title = "PayPal", tooltip = "Click to copy the PayPal support link.", url = links.paypal },
        { texture = "Ko-Fi.png", title = "Ko-fi", tooltip = "Click to copy the Ko-fi link.", url = links.kofi },
        { texture = "GitHub.png", title = "GitHub", tooltip = "Click to copy the GitHub repository link.", url = links.github },
    }
    local previous
    for i = 1, #icons do
        local data = icons[i]
        local icon = CreateSupportIcon(data.texture, data.title, data.tooltip, data.url)
        if previous then
            icon:SetPoint("RIGHT", previous, "LEFT", -7, 0)
        else
            icon:SetPoint("RIGHT", iconRow, "RIGHT", 0, 0)
        end
        previous = icon
    end

    y = y - (scaleCardH + 12)
    local advanced = Card("Advanced", x0, y, width, 76)
    W.Text(advanced, "Fast access to recovery and support tools.", 14, -34, width - 28, T.colors.muted)
    AddButton(advanced, "Print Help", 14, -54, 100, 20, function()
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], "help")
        end
    end)
    local factory = AddButton(advanced, "Factory Reset", 122, -54, 112, 20, function()
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], "fullreset confirm")
        end
    end)
    T.SkinDangerButton(factory)
    AddButton(advanced, "Profiles", 242, -54, 100, 20, function() M.SelectPage("profiles") end)
    AddButton(advanced, "Discord", 350, -54, 100, 20, function()
        if type(_G.MSUF_ShowCopyLink) == "function" then
            _G.MSUF_ShowCopyLink("Discord", "https://discord.gg/JQnhZXnTAK")
        end
    end)

    ctx:SetContentHeight(math.abs(y) + 100)
end

M.RegisterPage("search", { title = "Search", build = BuildSearchPage, version = 1 })
M.RegisterPage("home", { title = "MSUF Menu", build = BuildDashboard, version = 3 })

local function ApplyMenuFrameScale(frame)
    if not (frame and frame.SetScale) then return end
    local g = M.GetGeneralDB()
    frame:SetScale(EffectiveMenuScale(g.slashMenuScale))
    ApplyWindowResizeBounds(frame)
    ClampWindowSize(frame)
end

M.GetEffectiveMenuScale = EffectiveMenuScale

function M.Open(pageKey)
    if M.ApplyLocaleSelection then M.ApplyLocaleSelection() end
    local f = BuildWindow()
    ApplyMenuFrameScale(f)
    f:Show()
    M.SelectPage(pageKey or M.activeKey or "home")
end

function M.Toggle(pageKey)
    local f = BuildWindow()
    if f:IsShown() and (not pageKey or pageKey == M.activeKey) then
        f:Hide()
    else
        M.Open(pageKey)
    end
end

function M.InvalidatePage(key)
    if key then
        local entry = M.cache[key]
        if entry and entry.wrapper then
            entry.wrapper:Hide()
            entry.wrapper:SetParent(nil)
        end
        M.cache[key] = nil
    else
        for k in pairs(M.cache) do M.InvalidatePage(k) end
    end
end

_G.MSUF2_Open = function(pageKey) M.Open(pageKey) end
_G.MSUF2_Toggle = function(pageKey) M.Toggle(pageKey) end

_G.MSUF_OpenStandaloneOptionsWindow = function(pageKey) M.Open(pageKey or "home") end
_G.MSUF_ShowStandaloneOptionsWindow = function(pageKey) M.Open(pageKey or "home") end
_G.MSUF_HideStandaloneOptionsWindow = function()
    if M.frame and M.frame.Hide then M.frame:Hide() end
end
_G.MSUF_OpenOptionsMenu = function() M.Open("home") end
_G.MSUF_OpenPage = function(pageKey) return M.SelectPage(pageKey or "home") end
_G.MSUF_SwitchMirrorPage = function(pageKey) return M.SelectPage(pageKey or "home") end
_G.MSUF_GetCurrentMirrorPage = function() return M.activeKey or "home" end
_G.MSUF_GetMirrorPages = function() return M.pages end

SLASH_MSUF2OPTIONS1 = "/msuf"
SlashCmdList["MSUF2OPTIONS"] = function(msg)
    msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = msg:lower()
    local cmd = msg:match("^(%S+)") or ""
    if cmd == "versiontest" then
        if type(_G.MSUF_VersionCheck_DebugFakeUpdate) == "function" then
            pcall(_G.MSUF_VersionCheck_DebugFakeUpdate)
        else
            print("|cffffd700MSUF:|r Version test helper is not loaded.")
        end
        return
    end
    if cmd == "help" or cmd == "reset" or cmd == "fullreset" or cmd == "absorb" or cmd == "analytics" then
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], msg)
        end
        return
    end
    if msg == "locale" or msg == "locales" or msg == "loc" then
        local total, missing = 0, 0
        if type(M.GetLocaleCoverage) == "function" then
            total, missing = M.GetLocaleCoverage()
        end
        local locale = ns.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
        print(string.format("|cff00b7ebMSUF2|r locale %s: %d keys seen, %d missing translations.", locale, total or 0, missing or 0))
        return
    end
    M.Open(ALIASES[msg] or msg or "home")
end

SLASH_MSUFOPTIONS1 = SLASH_MSUFOPTIONS1 or "/msufoptions"
SlashCmdList["MSUFOPTIONS"] = SlashCmdList["MSUFOPTIONS"] or function(msg)
    M.Open(ALIASES[tostring(msg or ""):lower()] or "home")
end
