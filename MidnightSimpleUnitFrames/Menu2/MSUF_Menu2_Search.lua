local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme
local W = M.Widgets
local Search = M.Search or {}
M.Search = Search
local NAV_ITEMS = M.navItems or {}

local floor = math.floor
local max = math.max
local min = math.min

local function ContentMetrics()
    local w, h = 720, 520
    if type(M.GetContentMetrics) == "function" then
        local ok, cw, ch = pcall(M.GetContentMetrics)
        if ok then
            w = tonumber(cw) or w
            h = tonumber(ch) or h
        end
    end
    return w, h
end

local function ContentWidth()
    local w = ContentMetrics()
    return w
end

local function ContentHeight()
    local _, h = ContentMetrics()
    return h
end

local SEARCH_KEYWORDS = {
    home = "dashboard start support links quick navigation edit mode move drag frames unitframe unit frames reset positions ui scale menu scale msuf frame scale profiles wago discord discord link patreon github curseforge paypal ko-fi slash command addon options minimap help recover recovery display recovery factory reset print help support search changelog release notes scaling",
    uf_player = "unit frame unitframe player frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level player level anchor level position level layer",
    uf_target = "unit frame unitframe target frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level target level anchor level position level layer",
    uf_targettarget = "unit frame unitframe target of target tot frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level target of target level anchor level position level layer",
    uf_focustarget = "unit frame unitframe focus target focus target frame focustarget ft frame basics enable disable hide show width height scale size health portrait text range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp status icons status indicators indicator selected indicator level level indicator level text show level focus target level anchor level position level layer child focus frame",
    uf_focus = "unit frame unitframe focus frame basics enable disable hide show width height scale size health power portrait text castbar focus kick interrupt auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level focus level anchor level position level layer",
    uf_boss = "unit frame unitframe boss frames bossframe bossframes frame basics enable disable hide show width height scale size health power portrait text castbar boss range fade range check distance check out of range transparency alpha auras buffs debuffs preview anchoring anchor boss layout copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level boss level anchor level position level layer",
    uf_pet = "unit frame unitframe pet frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level pet level anchor level position level layer",
    gf_layout = "group frames groupframes party raid mythic raid layout growth direction sorting role order frame scaling scale transparency alpha opacity anchoring anchor position move drag tooltip range fade preview show hide player solo enable width height spacing columns rows sorting role group number visibility",
    gf_bars = "group frames groupframes party raid health text power bar name hp text heal prediction absorb display range fade range check distance check out of range layout font size anchor offset opacity alpha smooth fill show power tank healer damage incoming heals shields debuff stripe dispel overlay priority order border priority any debuff dispel type",
    gf_auras = "group frames groupframes party raid buffs debuffs defensives externals text coloring private auras cooldown style aura utilities filter anchor icon size max buffs max debuffs custom buffs custom debuffs cooldown swipe masque pandemic dispel dispel border dispel glow blizzard rendering own buffs hots healer buffs raid debuffs boss debuffs",
    gf_indicators = "group frames groupframes party raid indicators status icons spell indicators corner indicators group number focus glow border dispel aggro threat role icon custom spells slots preview current show all marker raid marker ready check leader assist dead ghost offline afk dnd",
    opt_bars = "global style bars textures texture gradient gradient direction hp power absorb display heal prediction incoming heals highlight priority prio display overlay highlight borders outline border aggro purge boss target glow dispel overlay unitframe unit frame debuff tint any debuff dispellable rounded round corners rounded texture rounded frames rounded frame texture rounded unit frames rounded group frames rounded power bars rounded mouseover highlights mouseover bar colors background tint backdrop bg dark mode shared texture opacity alpha health texture power texture frame outline abgerundet abrundung runde kanten ecken abrunden einschalten ausschalten",
    opt_fonts = "global style fonts font family size outline shadow color text readability name hp power health spell cooldown bigger smaller text size name shortening realm names truncate font color",
    auras2 = "global style unit auras buffs debuffs icon size caps rows spacing sorting cooldown timer text tooltip private aura filter override dispel stealable only mine own buffs own debuffs pandemic reminders click through clickthrough aura position aura size",
    opt_castbar = "global style castbar textures outline shake fill direction empowered casts empower stages evoker augmentation devastation preservation hold release interrupt ready focus kick kick cooldown demon hunter demonhunter dh havoc vengeance devour consume magic disrupt counterspell pummel rebuke wind shear mind freeze skull bash muzzle spear hand strike counter shot quell silence name shortening latency spark channel ticks gcd global cooldown boss castbar target castbar focus castbar player castbar",
    opt_colors = "global style colors class bar colors background backgrond backround bg backdrop tint opacity alpha unitframe colors npc type colors bar colors bar outline border color unit frame border group frame border dispel castbar mouseover highlight gameplay superellipse color swatches portrait colors power colors font color health color reaction color aura colors crosshair colors dark mode custom color missing health white background bar background tint preserve hp color hp track black mana rage energy focus runic power insanity fury pain essence astral power lunar power maelstrom combo points holy power soul shards chi arcane charges runes stagger class power",
    opt_misc = "global style miscellaneous misc language localization localisation locale translation range fade range check range checker distance check out of range unit frame range check ui behavior tooltip tooltips combat settings general blizzard frames default frames hide blizzard disable blizzard update intervals performance minimap minimap icon target sounds version check menu behavior snap edge snap",
    classpower = "class resources combo points holy power soul shards chi maelstrom eclipse essence evoker runes runic power stagger brewmaster resource prediction auto hide detached power bar alternative mana behavior style quick actions class power resource bar alternate mana monk druid rogue paladin warlock death knight",
    gameplay = "gameplay combat crosshair click cast click cast clickthrough click-through focus target modifier mouseover interaction targeting spells mouse buttons keybind modifier ctrl shift alt fadenkreuz melee range spell target sound target lost mouseover heal click casting",
    modules = "modules style skins optional modules compatibility portrait decoration minimap compartment addon compartment",
    profiles = "profiles profile management spec profiles specialization auto switch create copy delete reset import export legacy import wago active profile share string profile string backup restore",
}


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


local function SearchPlaceholderText()
    local text = M.Tr("Search")
    if type(text) ~= "string" or text == "" then text = "Search" end
    local ask = M.Tr("Ask...")
    if type(ask) ~= "string" or ask == "" then ask = "Ask..." end
    return text .. " / " .. ask
end

local function SearchBoxHasText(searchBox)
    if not (searchBox and searchBox.GetText) then return false end
    return (searchBox:GetText() or ""):match("%S") ~= nil
end

local function RefreshSearchPlaceholder(searchBox)
    if not searchBox then return end
    local text = SearchPlaceholderText()
    if searchBox.Instructions and searchBox.Instructions.SetText then
        searchBox.Instructions:SetText(text)
    end
    if searchBox._msuf2SearchPlaceholder and searchBox._msuf2SearchPlaceholder.SetText then
        searchBox._msuf2SearchPlaceholder:SetText(text)
    end
end

local function UpdateSearchPlaceholder(searchBox)
    if not searchBox then return end
    RefreshSearchPlaceholder(searchBox)
    local placeholder = searchBox._msuf2SearchPlaceholder
    if not placeholder then return end
    local focused = (searchBox.HasFocus and searchBox:HasFocus()) and true or false
    if focused or SearchBoxHasText(searchBox) then
        placeholder:Hide()
    else
        placeholder:Show()
    end
end

local SEARCH_TEXT_FOLDS = {
    ["\195\128"] = "a", ["\195\129"] = "a", ["\195\130"] = "a", ["\195\131"] = "a", ["\195\133"] = "a",
    ["\195\160"] = "a", ["\195\161"] = "a", ["\195\162"] = "a", ["\195\163"] = "a", ["\195\165"] = "a",
    ["\195\135"] = "c", ["\195\167"] = "c",
    ["\195\136"] = "e", ["\195\137"] = "e", ["\195\138"] = "e", ["\195\139"] = "e",
    ["\195\168"] = "e", ["\195\169"] = "e", ["\195\170"] = "e", ["\195\171"] = "e",
    ["\195\140"] = "i", ["\195\141"] = "i", ["\195\142"] = "i", ["\195\143"] = "i",
    ["\195\172"] = "i", ["\195\173"] = "i", ["\195\174"] = "i", ["\195\175"] = "i",
    ["\195\145"] = "n", ["\195\177"] = "n",
    ["\195\146"] = "o", ["\195\147"] = "o", ["\195\148"] = "o", ["\195\149"] = "o",
    ["\195\178"] = "o", ["\195\179"] = "o", ["\195\180"] = "o", ["\195\181"] = "o",
    ["\195\153"] = "u", ["\195\154"] = "u", ["\195\155"] = "u",
    ["\195\185"] = "u", ["\195\186"] = "u", ["\195\187"] = "u",
}

local SEARCH_UTF_PUNCTUATION = {
    "\194\160", -- nbsp
    "\226\128\152", "\226\128\153", "\226\128\156", "\226\128\157",
    "\226\128\147", "\226\128\148", "\226\128\166",
    "\227\128\129", "\227\128\130",
    "\239\188\129", "\239\188\140", "\239\188\154", "\239\188\155", "\239\188\159",
}

local function NormalizeSearchText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("\195\132", "ae"):gsub("\195\164", "ae")
    text = text:gsub("\195\150", "oe"):gsub("\195\182", "oe")
    text = text:gsub("\195\156", "ue"):gsub("\195\188", "ue")
    text = text:gsub("\195\159", "ss")
    for from, to in pairs(SEARCH_TEXT_FOLDS) do text = text:gsub(from, to) end
    for i = 1, #SEARCH_UTF_PUNCTUATION do text = text:gsub(SEARCH_UTF_PUNCTUATION[i], " ") end
    text = text:gsub("[\240-\244][\128-\191][\128-\191][\128-\191]", " ")
    text = text:gsub("[/\\_%-%.:;,%(%)]", " ")
    text = string.lower(text)
    text = text:gsub("[\001-\031\127]", " ")
    -- Preserve non-ASCII letters so native localized FAQ keywords can match.
    text = text:gsub("[!\"#$%%&'%*%+<=>%?%@%[%]%^`{|}~]+", " ")
    text = text:gsub("%s+", " ")
    return TrimText(text)
end

local function DisplaySearchText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("%s+", " ")
    return TrimText(text)
end

local SEARCH_LOCALE_KEY_PREFIX = "MSUF2_SEARCH_"
local SEARCH_DEFAULT_LOCALE = "enUS"
local SEARCH_LOCALE_TEXT_CACHE = {}

local function IsSearchLocaleKey(text)
    return type(text) == "string" and text:sub(1, #SEARCH_LOCALE_KEY_PREFIX) == SEARCH_LOCALE_KEY_PREFIX
end

local function SearchEffectiveLocale()
    if type(ns.GetEffectiveLocale) == "function" then
        local ok, locale = pcall(ns.GetEffectiveLocale)
        if ok and type(locale) == "string" and locale ~= "" then return locale end
    end
    if type(ns.LOCALE) == "string" and ns.LOCALE ~= "" then return ns.LOCALE end
    if type(_G.GetLocale) == "function" then
        local ok, locale = pcall(_G.GetLocale)
        if ok and type(locale) == "string" and locale ~= "" then return locale end
    end
    return SEARCH_DEFAULT_LOCALE
end

local function SearchLocaleCacheKey(text)
    return SearchEffectiveLocale() .. "\031" .. tostring(text or "")
end

local function AddUniqueSearchPart(parts, seen, text)
    text = DisplaySearchText(text)
    if text == "" or seen[text] then return end
    seen[text] = true
    parts[#parts + 1] = text
end

local function SearchLocaleTranslations(text)
    local cacheKey = SearchLocaleCacheKey(text)
    local cached = SEARCH_LOCALE_TEXT_CACHE[cacheKey]
    if cached then return cached end

    local out, seen = {}, {}
    local function add(value)
        value = DisplaySearchText(value)
        if value == "" or seen[value] then return end
        seen[value] = true
        out[#out + 1] = value
    end

    if type(M.Tr) == "function" then
        local translated = M.Tr(text)
        if translated and translated ~= text then add(translated) end
    end

    if type(ns.RegisterLocale) == "function" then
        local L = ns.RegisterLocale(SearchEffectiveLocale())
        local translated = L and L[text]
        if translated and translated ~= text then add(translated) end
    end

    SEARCH_LOCALE_TEXT_CACHE[cacheKey] = out
    return out
end

local function SearchDisplayText(text)
    text = DisplaySearchText(text)
    if text == "" then return "" end
    local translations = SearchLocaleTranslations(text)
    if #translations > 0 then return translations[1] end
    if IsSearchLocaleKey(text) then return "" end
    return text
end

local function AddSearchText(parts, text)
    if text == nil then return end
    text = DisplaySearchText(text)
    if text == "" then return end
    local seen = {}
    local translations = SearchLocaleTranslations(text)
    if #translations > 0 then
        for i = 1, #translations do
            AddUniqueSearchPart(parts, seen, translations[i])
        end
        if not IsSearchLocaleKey(text) then
            AddUniqueSearchPart(parts, seen, text)
        end
    elseif not IsSearchLocaleKey(text) then
        AddUniqueSearchPart(parts, seen, text)
    end
end

local function AddSearchTextVariants(out, seen, text)
    local translations = SearchLocaleTranslations(text)
    if #translations > 0 then
        for i = 1, #translations do
            AddUniqueSearchPart(out, seen, translations[i])
        end
        if not IsSearchLocaleKey(text) then
            AddUniqueSearchPart(out, seen, text)
        end
    elseif not IsSearchLocaleKey(text) then
        AddUniqueSearchPart(out, seen, text)
    end
end

local function AddRawSearchText(parts, text)
    if text == nil then return end
    text = tostring(text)
    if text ~= "" then parts[#parts + 1] = text end
end

local function SearchTextVariants(text)
    local out, seen = {}, {}
    AddSearchTextVariants(out, seen, text)
    return out
end

local SEARCH_CONTROL_ACTION_KEYWORDS = "MSUF2_SEARCH_CONTROL_ACTION_KEYWORDS"
local SEARCH_CONTROL_PATTERNS = "MSUF2_SEARCH_CONTROL_PATTERNS"
local SEARCH_TOGGLE_ACTION_KEYWORDS = "MSUF2_SEARCH_TOGGLE_ACTION_KEYWORDS"
local SEARCH_TOGGLE_PATTERNS = "MSUF2_SEARCH_TOGGLE_PATTERNS"
local SEARCH_DROPDOWN_ACTION_KEYWORDS = "MSUF2_SEARCH_DROPDOWN_ACTION_KEYWORDS"
local SEARCH_DROPDOWN_PATTERNS = "MSUF2_SEARCH_DROPDOWN_PATTERNS"
local SEARCH_SEGMENT_ACTION_KEYWORDS = "MSUF2_SEARCH_SEGMENT_ACTION_KEYWORDS"
local SEARCH_SEGMENT_PATTERNS = "MSUF2_SEARCH_SEGMENT_PATTERNS"
local SEARCH_SLIDER_ACTION_KEYWORDS = "MSUF2_SEARCH_SLIDER_ACTION_KEYWORDS"
local SEARCH_SLIDER_PATTERNS = "MSUF2_SEARCH_SLIDER_PATTERNS"
local SEARCH_COLOR_ACTION_KEYWORDS = "MSUF2_SEARCH_COLOR_ACTION_KEYWORDS"
local SEARCH_COLOR_PATTERNS = "MSUF2_SEARCH_COLOR_PATTERNS"
local SEARCH_BUTTON_ACTION_KEYWORDS = "MSUF2_SEARCH_BUTTON_ACTION_KEYWORDS"
local SEARCH_BUTTON_PATTERNS = "MSUF2_SEARCH_BUTTON_PATTERNS"
local SEARCH_TEXTINPUT_ACTION_KEYWORDS = "MSUF2_SEARCH_TEXTINPUT_ACTION_KEYWORDS"
local SEARCH_TEXTINPUT_PATTERNS = "MSUF2_SEARCH_TEXTINPUT_PATTERNS"
local SEARCH_VALUE_PATTERNS = "MSUF2_SEARCH_VALUE_PATTERNS"

local SEARCH_KIND_ACTION_KEYWORDS = {
    toggle = SEARCH_TOGGLE_ACTION_KEYWORDS,
    dropdown = SEARCH_DROPDOWN_ACTION_KEYWORDS,
    segment = SEARCH_SEGMENT_ACTION_KEYWORDS,
    slider = SEARCH_SLIDER_ACTION_KEYWORDS,
    color = SEARCH_COLOR_ACTION_KEYWORDS,
    button = SEARCH_BUTTON_ACTION_KEYWORDS,
    textinput = SEARCH_TEXTINPUT_ACTION_KEYWORDS,
}

local SEARCH_KIND_PATTERNS = {
    toggle = SEARCH_TOGGLE_PATTERNS,
    dropdown = SEARCH_DROPDOWN_PATTERNS,
    segment = SEARCH_SEGMENT_PATTERNS,
    slider = SEARCH_SLIDER_PATTERNS,
    color = SEARCH_COLOR_PATTERNS,
    button = SEARCH_BUTTON_PATTERNS,
    textinput = SEARCH_TEXTINPUT_PATTERNS,
}

local function ForEachLocaleSearchPattern(key, callback)
    if type(key) ~= "string" or type(callback) ~= "function" then return end
    local translations = SearchLocaleTranslations(key)
    for i = 1, #translations do
        local text = translations[i]
        for pattern in tostring(text):gmatch("[^|]+") do
            pattern = TrimText(pattern)
            if pattern ~= "" then callback(pattern) end
        end
    end
end

local function AddSearchPatternText(parts, key, label)
    label = DisplaySearchText(label)
    if label == "" then return end
    local labels = SearchTextVariants(label)
    ForEachLocaleSearchPattern(key, function(pattern)
        for i = 1, #labels do
            local ok, formatted = pcall(string.format, pattern, labels[i])
            if ok then AddRawSearchText(parts, formatted) end
        end
    end)
end

local function AddSearchValuePatternText(parts, label, value)
    label = DisplaySearchText(label)
    value = DisplaySearchText(value)
    if label == "" or value == "" then return end
    local labels = SearchTextVariants(label)
    local values = SearchTextVariants(value)
    for i = 1, #labels do
        AddRawSearchText(parts, labels[i] .. " " .. value)
        AddRawSearchText(parts, value .. " " .. labels[i])
    end
    for i = 1, #values do
        AddRawSearchText(parts, label .. " " .. values[i])
        AddRawSearchText(parts, values[i] .. " " .. label)
    end
    ForEachLocaleSearchPattern(SEARCH_VALUE_PATTERNS, function(pattern)
        for i = 1, #labels do
            local ok, formatted = pcall(string.format, pattern, labels[i], value)
            if ok then AddRawSearchText(parts, formatted) end
        end
        for i = 1, #values do
            local ok, formatted = pcall(string.format, pattern, label, values[i])
            if ok then AddRawSearchText(parts, formatted) end
        end
    end)
end

local function AddToggleQuestionSearchText(parts, label)
    label = DisplaySearchText(label)
    if label == "" then return end
    AddRawSearchText(parts, "toggle " .. label)
end

local function AddControlQuestionSearchText(parts, label, kind, values)
    label = DisplaySearchText(label)
    if label == "" then return end

    kind = kind or "control"
    AddRawSearchText(parts, kind .. " " .. label)

    if type(values) ~= "table" then return end
    local limit = math.min(#values, 12)
    for i = 1, limit do
        local value = values[i]
        if type(value) == "table" then value = value.text or value.label or value.name or value.title or value.value or value.key end
        if value ~= nil then AddRawSearchText(parts, label .. " " .. tostring(value)) end
    end
end

local MIN_SEARCH_QUERY_LEN = 2
local SEARCH_TEXT_MAX_LEN = 170
local SEARCH_BACKGROUND_STEP_SEC = 0.22
local SEARCH_INPUT_DEBOUNCE_SEC = 0.10
local SEARCH_MAX_RESULTS = 24
local SEARCH_VISIBLE_RESULTS = 12
local SEARCH_MIN_RESULT_SCORE = 40
local SEARCH_MAX_RAW_WORDS = 12
local SEARCH_MAX_QUERY_CLAUSES = 8
local SEARCH_MAX_TERMS_PER_CLAUSE = 18
local SEARCH_MAX_RECORD_TOKENS = 90
local SEARCH_CONTROL_MAX_TOKENS = 36
local SEARCH_CONTROL_HAYSTACK_MAX_LEN = 1200
local SEARCH_STATE = {
    records = nil,
    recordsDirty = true,
    indexing = false,
    indexQueue = nil,
    inputSerial = 0,
    registrySerial = 0,
    aliasTypoKeys = nil,
    aliasTypoCache = {},
    queryClauseCacheNorm = nil,
    queryClauseCacheClauses = nil,
    registry = {},
    registryByPage = {},
    registryRecords = {},
    localeKey = nil,
}
M.searchRegistry = SEARCH_STATE.registry

local function MarkSearchIndexDirty()
    SEARCH_STATE.recordsDirty = true
end

local function ClearSearchLocaleCaches()
    SEARCH_LOCALE_TEXT_CACHE = {}
    SEARCH_STATE.queryClauseCacheNorm = nil
    SEARCH_STATE.queryClauseCacheClauses = nil
    SEARCH_STATE.registryRecords = {}
end

local function EnsureSearchLocaleFresh()
    local localeKey = SearchEffectiveLocale()
    if SEARCH_STATE.localeKey == localeKey then return end
    SEARCH_STATE.localeKey = localeKey
    ClearSearchLocaleCaches()
    MarkSearchIndexDirty()
end

local function SearchCombatLocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function CancelSearchBackgroundIndex()
    SEARCH_STATE.indexing = false
    SEARCH_STATE.indexQueue = nil
end

local SEARCH_NOISE_TEXT = {
    [""] = true,
    ["x"] = true,
    ["+"] = true,
    ["-"] = true,
    ["<"] = true,
    [">"] = true,
    ["|"] = true,
}

local SEARCH_STOP_WORDS = {
    a = true,
    an = true,
    ["and"] = true,
    are = true,
    bother = true,
    bothering = true,
    can = true,
    cant = true,
    change = true,
    changed = true,
    changing = true,
    configure = true,
    configured = true,
    customize = true,
    customise = true,
    ["do"] = true,
    does = true,
    doesnt = true,
    didn = true,
    didnt = true,
    basically = true,
    blind = true,
    brain = true,
    find = true,
    fixed = true,
    fix = true,
    ["for"] = true,
    get = true,
    going = true,
    hey = true,
    help = true,
    how = true,
    i = true,
    im = true,
    ["in"] = true,
    is = true,
    it = true,
    just = true,
    m = true,
    make = true,
    maybe = true,
    my = true,
    need = true,
    now = true,
    ["not"] = true,
    of = true,
    on = true,
    ["or"] = true,
    please = true,
    pls = true,
    option = true,
    options = true,
    de = true,
    del = true,
    el = true,
    la = true,
    las = true,
    los = true,
    un = true,
    una = true,
    esta = true,
    este = true,
    donde = true,
    como = true,
    est = true,
    le = true,
    les = true,
    des = true,
    du = true,
    une = true,
    ou = true,
    il = true,
    lo = true,
    gli = true,
    di = true,
    da = true,
    dove = true,
    per = true,
    para = true,
    o = true,
    os = true,
    as = true,
    um = true,
    uma = true,
    onde = true,
    ["найти"] = true,
    ["где"] = true,
    ["как"] = true,
    ["опция"] = true,
    setting = true,
    settings = true,
    setup = true,
    so = true,
    sorry = true,
    thanks = true,
    the = true,
    thx = true,
    to = true,
    want = true,
    where = true,
    why = true,
    with = true,
    would = true,
    t = true,
    etc = true,
    functioning = true,
    n = true,
    wtf = true,
    dumb = true,
    stupid = true,
    plsfix = true,
    s = true,
    see = true,
    image = true,
    screenshot = true,
    happening = true,
    here = true,
    still = true,
    even = true,
    though = true,
    wie = true,
    kann = true,
    ich = true,
    ist = true,
    sind = true,
    das = true,
    die = true,
    der = true,
    den = true,
    dem = true,
    ein = true,
    eine = true,
    einer = true,
    mein = true,
    meine = true,
    nicht = true,
    warum = true,
    wo = true,
    was = true,
    aendern = true,
    andern = true,
    einstellen = true,
    einstellungen = true,
    finde = true,
    finden = true,
    bitte = true,
    du = true,
    fuer = true,
    fur = true,
    mal = true,
    man = true,
    mich = true,
    mir = true,
    mit = true,
    nur = true,
    optionen = true,
    noch = true,
    immer = true,
    aus = true,
    obwohl = true,
    trotzdem = true,
    werden = true,
    und = true,
    oder = true,
    zu = true,
    zur = true,
    zum = true,
}

local SEARCH_QUERY_SOFT_STOP_WORDS = {
    activate = true,
    activated = true,
    adjust = true,
    button = true,
    checkbox = true,
    choose = true,
    chosen = true,
    decrease = true,
    disable = true,
    disabled = true,
    dropdown = true,
    enable = true,
    enabled = true,
    hide = true,
    hidden = true,
    increase = true,
    input = true,
    off = true,
    open = true,
    select = true,
    selected = true,
    slider = true,
    switch = true,
    toggle = true,
    turn = true,
    value = true,
    visible = true,
    aktivieren = true,
    aktiviere = true,
    aktiviert = true,
    anpassen = true,
    anzeigen = true,
    ausblenden = true,
    ausschalten = true,
    auswahl = true,
    auswaehlen = true,
    deaktivieren = true,
    deaktiviere = true,
    deaktiviert = true,
    einschalten = true,
    menu = true,
    menue = true,
    regler = true,
    schalter = true,
    umschalter = true,
    choisir = true,
    activer = true,
    desactiver = true,
    seleccionar = true,
    activar = true,
    desactivar = true,
    selezionare = true,
    attivare = true,
    disattivare = true,
    ativar = true,
    desativar = true,
}

local function SearchIgnoreQueryWord(word)
    return SEARCH_STOP_WORDS[word] or SEARCH_QUERY_SOFT_STOP_WORDS[word]
end

local SEARCH_QUERY_ALIASES = {
    evoker = { "empowered", "empower", "empowered casts", "stage", "stages", "hold cast", "release cast", "quell", "essence", "augmentation", "devastation", "preservation" },
    devastation = { "evoker", "empowered", "empower", "empowered casts", "essence" },
    preservation = { "evoker", "empowered", "empower", "empowered casts", "essence" },
    augmentation = { "evoker", "empowered", "empower", "empowered casts", "essence", "ebon might" },
    empower = { "empowered", "empowered casts", "stage", "stages", "hold cast", "release cast" },
    empowered = { "empower", "empowered casts", "stage", "stages", "hold cast", "release cast" },
    stage = { "empowered", "empowered casts", "blink", "castbar" },
    stages = { "empowered", "empowered casts", "blink", "castbar" },

    demonhunter = { "demon hunter", "dh", "havoc", "vengeance", "disrupt", "consume magic", "devour", "interrupt", "kick", "interrupt ready" },
    dh = { "demon hunter", "demonhunter", "havoc", "vengeance", "disrupt", "consume magic", "devour", "interrupt", "kick", "interrupt ready" },
    havoc = { "demon hunter", "demonhunter", "dh", "disrupt", "consume magic", "interrupt", "kick" },
    vengeance = { "demon hunter", "demonhunter", "dh", "disrupt", "consume magic", "interrupt", "kick" },
    devour = { "consume", "consume magic", "purge", "dispel", "disrupt", "interrupt", "kick", "interrupt ready" },
    consume = { "consume magic", "devour", "purge", "dispel", "interrupt", "kick" },
    disrupt = { "demon hunter", "demonhunter", "dh", "interrupt", "kick", "focus kick", "interrupt ready" },

    kick = { "interrupt", "interrupt ready", "focus kick", "counterspell", "disrupt", "pummel", "rebuke", "wind shear", "mind freeze", "muzzle", "skull bash", "spear hand strike", "counter shot", "quell", "silence" },
    kicks = { "interrupt", "interrupt ready", "focus kick", "counterspell", "disrupt", "pummel", "rebuke", "wind shear", "mind freeze", "muzzle", "skull bash", "spear hand strike", "counter shot", "quell", "silence" },
    interrupt = { "kick", "interrupt ready", "focus kick", "counterspell", "disrupt", "pummel", "rebuke", "wind shear", "mind freeze", "muzzle", "skull bash", "spear hand strike", "counter shot", "quell", "silence" },
    interrupts = { "kick", "interrupt", "interrupt ready", "focus kick" },
    counterspell = { "interrupt", "kick", "interrupt ready", "focus kick" },
    pummel = { "interrupt", "kick", "interrupt ready" },
    rebuke = { "interrupt", "kick", "interrupt ready" },
    windshear = { "wind shear", "interrupt", "kick", "interrupt ready" },
    silence = { "interrupt", "kick", "interrupt ready" },
    quell = { "evoker", "interrupt", "kick", "interrupt ready" },

    cast = { "castbar", "cast bar", "spell name", "channel", "gcd" },
    casting = { "castbar", "cast bar", "spell name", "channel", "gcd" },
    castbar = { "cast bar", "casts", "casting", "spell name", "channel", "gcd" },
    castbars = { "castbar", "cast bar", "casts", "casting", "spell name", "channel", "gcd" },
    zauberleiste = { "castbar", "cast bar", "casts", "casting" },

    level = { "level indicator", "level text", "show level", "unit level", "player level", "target level", "status icons", "status indicator", "indicator", "anchor level", "level anchor", "position level", "level position", "x offset", "y offset" },
    levels = { "level", "level indicator", "level text", "show level", "status icons", "status indicator" },
    lvl = { "level", "level indicator", "level text", "show level" },
    leveltext = { "level text", "level indicator", "show level", "status icons", "status indicator", "anchor", "position", "x offset", "y offset" },
    levelindicator = { "level indicator", "level text", "show level", "status icons", "status indicator", "anchor", "position", "x offset", "y offset" },
    statusindicator = { "status indicator", "status icons", "indicator", "level indicator", "level text", "enabled", "anchor", "size", "layer", "x offset", "y offset" },
    statusindicators = { "status indicators", "status icons", "indicator", "level indicator", "level text", "enabled", "anchor", "size", "layer", "x offset", "y offset" },
    indicator = { "indicators", "status icons", "status indicator", "selected indicator", "level indicator", "group indicators" },
    indicators = { "indicator", "status icons", "status indicators", "selected indicator", "level indicator", "group indicators" },
    turn = { "enable", "disable", "show", "hide", "enabled", "disabled", "visible", "hidden" },
    off = { "disable", "hide", "disabled", "hidden" },
    onoff = { "enable", "disable", "show", "hide", "enabled", "disabled" },
    greyed = { "disabled", "locked", "shared setting", "unit auras", "custom caps", "max buffs", "max debuffs" },
    grayed = { "disabled", "locked", "shared setting", "unit auras", "custom caps", "max buffs", "max debuffs" },
    showbuffs = { "show buffs", "unit auras", "display", "shared setting", "custom caps", "max buffs" },
    maxbuffs = { "max buffs", "buff cap", "caps & icons", "hide buffs", "custom caps" },
    customcaps = { "custom caps", "caps & icons", "max buffs", "max debuffs", "unit override" },
    positioning = { "position", "positions", "move", "edit mode", "x offset", "y offset", "anchor", "anchoring" },

    background = { "bar background tint", "background tint", "background opacity", "background alpha", "backdrop", "bg", "bar colors", "transparency", "alpha", "unitframe colors" },
    backgrond = { "background", "bar background tint", "background tint", "bg" },
    backgroud = { "background", "bar background tint", "background tint", "bg" },
    backround = { "background", "bar background tint", "background tint", "bg" },
    bakground = { "background", "bar background tint", "background tint", "bg" },
    hintergrund = { "background", "bar background tint", "background tint", "bg" },
    bg = { "background", "bar background tint", "background tint", "background opacity", "background alpha" },
    backdrop = { "background", "bar background tint", "background tint", "bg" },
    alpha = { "opacity", "transparency", "fade", "background alpha", "in combat", "out of combat" },
    opacity = { "alpha", "transparency", "fade", "background opacity", "in combat", "out of combat" },
    transparent = { "transparency", "alpha", "opacity", "fade" },
    transparency = { "alpha", "opacity", "fade", "background" },
    fade = { "alpha", "opacity", "transparency", "range fade", "out of range" },
    fades = { "fade", "alpha", "opacity", "range fade", "out of range" },
    faded = { "fade", "alpha", "opacity", "range fade", "out of range" },
    range = { "range fade", "out of range", "range alpha", "range check", "distance", "distance check" },
    rangecheck = { "range check", "range fade", "out of range", "distance check", "unit frame range check", "out of range alpha", "range fade affects" },
    rangechecker = { "range check", "range fade", "out of range", "distance check", "unit frame range check" },
    distance = { "range", "range fade", "out of range", "range check", "distance check", "alpha" },
    distancecheck = { "range check", "range fade", "out of range", "distance check", "unit frame range check" },
    outofrange = { "out of range", "range fade", "range alpha", "range check", "distance" },
    check = { "range check", "range fade", "out of range", "distance check", "ready check", "version check" },
    checker = { "check", "range check", "range fade", "out of range" },
    checking = { "check", "range check", "range fade", "out of range" },
    reichweite = { "range", "range fade", "out of range", "range check", "distance" },
    reichweiten = { "range", "range fade", "out of range", "range check", "distance" },
    reichweitencheck = { "range check", "range fade", "out of range", "distance check" },
    entfernung = { "distance", "range", "range fade", "out of range", "range check" },
    ausserhalb = { "out of range", "range fade", "range check" },
    misc = { "miscellaneous", "global style", "tooltips", "blizzard frames", "update intervals", "language" },
    miscellaneous = { "misc", "global style", "tooltips", "blizzard frames", "update intervals", "language" },
    verschiedenes = { "misc", "miscellaneous", "global style", "tooltips", "blizzard frames", "update intervals", "language" },

    move = { "edit mode", "position", "positions", "drag", "x offset", "y offset", "anchor", "anchoring" },
    moving = { "edit mode", "position", "positions", "drag", "x offset", "y offset", "anchor", "anchoring" },
    drag = { "edit mode", "move", "position", "x offset", "y offset" },
    position = { "positions", "move", "edit mode", "x offset", "y offset", "anchor", "anchoring" },
    positions = { "position", "move", "edit mode", "x offset", "y offset", "anchor", "anchoring", "reset positions" },
    anchor = { "anchoring", "position", "move", "attach", "global anchor", "custom anchor" },
    anchoring = { "anchor", "position", "move", "attach", "global anchor", "custom anchor" },
    unitframe = { "unit frame", "unit frames", "player frame", "target frame", "focus frame", "focus target frame", "boss frame", "frame basics", "anchoring", "edit mode" },
    unitframes = { "unit frame", "unit frames", "player frame", "target frame", "focus frame", "focus target frame", "boss frame", "frame basics", "anchoring", "edit mode" },
    unitfram = { "unitframe", "unit frame", "unit frames", "frame basics", "anchoring", "edit mode" },
    unitfrme = { "unitframe", "unit frame", "unit frames", "frame basics", "anchoring", "edit mode" },
    player = { "player frame", "playerframe" },
    target = { "target frame", "targetframe" },
    focus = { "focus frame", "focusframe" },
    focustarget = { "focus target frame", "focus target", "ft frame" },
    pet = { "pet frame", "petframe" },
    fram = { "frame", "unit frame", "frames", "frame basics" },
    frame = { "unit frame", "frames", "unitframe", "frame basics" },
    frames = { "unit frames", "unitframe", "frame basics", "edit mode" },
    playerframe = { "player frame", "move player frame", "drag player frame", "player position", "unit frame", "frame basics", "anchoring", "edit mode" },
    targetframe = { "target frame", "move target frame", "drag target frame", "target position", "unit frame", "frame basics", "anchoring", "edit mode" },
    focusframe = { "focus frame", "move focus frame", "drag focus frame", "focus position", "unit frame", "frame basics", "anchoring", "edit mode", "focus kick" },
    focustargetframe = { "focus target frame", "move focus target frame", "drag focus target frame", "focus target position", "unit frame", "frame basics", "anchoring", "edit mode" },
    petframe = { "pet frame", "move pet frame", "drag pet frame", "pet position", "unit frame", "frame basics", "anchoring", "edit mode" },
    bossframe = { "boss frame", "boss frames", "unit frame", "boss layout" },
    bossframes = { "boss frame", "boss frames", "unit frame", "boss layout", "boss preview" },
    size = { "width", "height", "scale", "frame basics", "frame scaling" },
    resize = { "size", "width", "height", "scale", "frame basics", "frame scaling" },
    bigger = { "size", "scale", "width", "height", "font size" },
    smaller = { "size", "scale", "width", "height", "font size" },
    big = { "bigger", "size", "scale", "width", "height", "font size" },
    small = { "smaller", "size", "scale", "width", "height", "font size", "text size", "icon size" },
    scale = { "size", "frame scaling", "menu scale", "ui scale" },
    smooth = { "smooth fill", "smooth health fill", "smooth power bar", "bar animation", "soft fill", "fluid fill", "weiche fuellung" },
    smoothfill = { "smooth fill", "smooth health fill", "smooth power bar", "bar animation", "soft fill", "fluid fill", "weiche fuellung" },
    softfill = { "smooth fill", "smooth health fill", "smooth power bar", "bar animation", "weiche fuellung" },
    fluidfill = { "smooth fill", "smooth health fill", "smooth power bar", "bar animation", "weiche fuellung" },

    rounded = { "rounded texture", "rounded frame texture", "rounded frames", "round corners", "unit frames", "group frames", "power bars", "mouseover highlights", "bars" },
    round = { "rounded", "rounded texture", "rounded frames", "round corners", "corners", "bars" },
    corners = { "rounded", "rounded texture", "rounded frames", "round corners", "frame corners", "bars" },
    corner = { "corners", "rounded", "round corners", "frame corners" },
    roundedframes = { "rounded frames", "rounded frame texture", "rounded texture", "unit frames", "group frames", "bars" },
    roundedtexture = { "rounded texture", "rounded frame texture", "rounded frames", "bars" },
    rund = { "rounded", "rounded frames", "round corners", "rounded texture", "bars" },
    runde = { "rounded", "rounded frames", "round corners", "rounded texture", "bars" },
    kanten = { "corners", "rounded", "round corners", "rounded frames", "bars" },
    ecken = { "corners", "rounded", "round corners", "rounded frames", "bars" },
    abrunden = { "rounded", "rounded frames", "round corners", "rounded texture", "bars" },
    abrundung = { "rounded", "rounded frames", "round corners", "rounded texture", "bars" },
    abgerundet = { "rounded", "rounded frames", "round corners", "rounded texture", "bars" },
    abgerundete = { "rounded", "rounded frames", "round corners", "rounded texture", "bars" },
    abgerundeten = { "rounded", "rounded frames", "round corners", "rounded texture", "bars" },
    einschalten = { "enable", "turn on", "on", "show" },
    anschalten = { "enable", "turn on", "on", "show" },
    aktivieren = { "enable", "turn on", "on", "show" },
    ausschalten = { "disable", "turn off", "off", "hide" },
    abschalten = { "disable", "turn off", "off", "hide" },
    deaktivieren = { "disable", "turn off", "off", "hide" },

    -- Smooth Fill: localized user vocabulary across supported menu locales.
    fuellung = { "smooth fill", "smooth health fill", "smooth power bar", "bar animation", "weiche fuellung" },
    fuellen = { "smooth fill", "smooth health fill", "smooth power bar", "bar animation", "weiche fuellung" },
    weich = { "smooth fill", "smooth health fill", "smooth power bar", "soft fill", "weiche fuellung" },
    weiche = { "smooth fill", "smooth health fill", "smooth power bar", "soft fill", "weiche fuellung" },
    weichen = { "smooth fill", "smooth health fill", "smooth power bar", "soft fill", "weiche fuellung" },
    sanft = { "smooth fill", "smooth health fill", "smooth power bar", "soft fill", "weiche fuellung" },
    sanfte = { "smooth fill", "smooth health fill", "smooth power bar", "soft fill", "weiche fuellung" },
    fluessig = { "smooth fill", "smooth health fill", "smooth power bar", "fluid fill", "weiche fuellung" },
    fluessige = { "smooth fill", "smooth health fill", "smooth power bar", "fluid fill", "weiche fuellung" },
    relleno = { "smooth fill", "soft fill", "fluid fill", "bar animation" },
    llenado = { "smooth fill", "soft fill", "fluid fill", "bar animation" },
    suave = { "smooth fill", "soft fill", "fluid fill", "bar animation" },
    fluido = { "smooth fill", "fluid fill", "bar animation" },
    fluida = { "smooth fill", "fluid fill", "bar animation" },
    animacion = { "bar animation", "smooth fill" },
    remplissage = { "smooth fill", "soft fill", "fluid fill", "bar animation" },
    doux = { "smooth fill", "soft fill", "bar animation" },
    douce = { "smooth fill", "soft fill", "bar animation" },
    fluide = { "smooth fill", "fluid fill", "bar animation" },
    riempimento = { "smooth fill", "soft fill", "fluid fill", "bar animation" },
    morbido = { "smooth fill", "soft fill", "bar animation" },
    morbida = { "smooth fill", "soft fill", "bar animation" },
    preenchimento = { "smooth fill", "soft fill", "fluid fill", "bar animation" },
    animacao = { "bar animation", "smooth fill" },
    ["плавное"] = { "smooth fill", "soft fill", "bar animation" },
    ["плавная"] = { "smooth fill", "soft fill", "bar animation" },
    ["заполнение"] = { "smooth fill", "bar animation" },
    ["заливка"] = { "smooth fill", "bar animation" },
    ["анимация"] = { "bar animation", "smooth fill" },
    ["полосы"] = { "bar animation", "smooth fill" },
    ["부드러운"] = { "smooth fill", "soft fill", "bar animation" },
    ["채우기"] = { "smooth fill", "bar animation" },
    ["막대"] = { "bar animation", "smooth fill" },
    ["애니메이션"] = { "bar animation", "smooth fill" },
    ["平滑填充"] = { "smooth fill", "bar animation" },
    ["柔和填充"] = { "smooth fill", "soft fill", "bar animation" },
    ["团队平滑填充"] = { "group smooth fill", "party smooth fill", "raid smooth fill" },
    ["小队平滑填充"] = { "group smooth fill", "party smooth fill", "raid smooth fill" },
    ["團隊平滑填充"] = { "group smooth fill", "party smooth fill", "raid smooth fill" },
    ["隊伍平滑填充"] = { "group smooth fill", "party smooth fill", "raid smooth fill" },
    ["条动画"] = { "bar animation", "smooth fill" },
    ["條動畫"] = { "bar animation", "smooth fill" },

    hp = { "health", "health text", "health bar", "leben" },
    health = { "hp", "health text", "health bar", "life", "leben" },
    leben = { "health", "hp", "health bar", "health text" },
    name = { "name text", "text", "font", "name shortening" },
    names = { "name text", "text", "font", "name shortening" },
    shorten = { "name shortening", "short names", "truncate names", "max name length" },
    shortened = { "name shortening", "short names", "truncate names", "max name length" },
    shortens = { "name shortening", "short names", "truncate names", "max name length" },
    shortening = { "name shortening", "short names", "truncate names", "max name length" },
    truncated = { "name shortening", "short names", "truncate names", "max name length" },
    override = { "custom settings", "font override", "scope override", "group frame override", "shared changes" },
    overrides = { "custom settings", "font override", "scope override", "group frame override", "shared changes" },
    fontoverride = { "font override", "custom font settings", "name shortening", "shared changes" },
    scopeoverride = { "scope override", "font override", "custom settings", "shared changes" },
    groupoverride = { "group frame override", "font override", "group frames", "name shortening" },
    text = { "font", "fonts", "name text", "health text", "power text", "spell name" },
    font = { "fonts", "text", "font size", "outline", "shadow" },
    fonts = { "font", "text", "font size", "outline", "shadow" },
    mana = { "power", "power bar", "alternative mana", "alt mana" },
    power = { "mana", "power bar", "class resources", "resource" },
    resource = { "class resources", "classpower", "power", "combo points", "essence" },
    resources = { "class resources", "classpower", "power", "combo points", "essence" },

    profile = { "profiles", "import", "export", "copy profile", "spec profiles", "wago" },
    profiles = { "profile", "import", "export", "copy profile", "spec profiles", "wago" },
    import = { "profiles", "profile", "import string", "wago", "legacy import" },
    export = { "profiles", "profile", "export string", "copy profile", "wago" },
    wago = { "profiles", "import", "export", "profile string" },
    reload = { "refresh", "apply", "not updating", "profile", "reset" },
    reset = { "reset positions", "factory reset", "profile reset", "profiles" },
    broken = { "not updating", "reset positions", "profile reset", "reload", "factory reset" },
    broke = { "broken", "not updating", "reset positions", "profile reset", "reload" },
    bugged = { "broken", "not updating", "reload", "reset positions" },
    wrong = { "not updating", "colors", "profile", "reset" },
    missing = { "not visible", "hidden", "invisible", "gone", "load conditions" },
    gone = { "missing", "not visible", "hidden", "invisible" },
    invisible = { "not visible", "hidden", "alpha", "transparency", "range fade" },
    hidden = { "hide", "show", "enable", "disable", "not visible" },
    show = { "enable", "visible", "not hidden" },
    hide = { "disable", "hidden", "not visible" },
    disabled = { "enable", "show", "frame basics" },
    enabled = { "enable", "show", "frame basics" },
    offscreen = { "reset positions", "move", "edit mode", "position" },
    overlap = { "text layer", "position", "anchor", "offset", "frame level" },
    overlapping = { "overlap", "text layer", "position", "anchor", "offset" },
    lag = { "performance", "update intervals", "auras", "cooldown", "filters" },
    fps = { "performance", "update intervals", "auras", "cooldown", "filters" },
    bad = { "wrong", "broken", "performance", "lag", "fps" },
    performance = { "update intervals", "auras", "cooldown", "filters", "range fade" },
    combat = { "combat lockdown", "in combat", "out of combat", "alpha", "settings" },
    lockdown = { "combat lockdown", "combat", "protected frames", "reload" },

    raidframes = { "group frames", "groupframes", "raid frames", "raid frame", "raid", "party", "layout", "group layout", "anchoring", "move raid frames" },
    partyframes = { "group frames", "groupframes", "party frames", "party frame", "party", "raid", "layout", "group layout", "anchoring", "move party frames" },
    gruppenframes = { "group frames", "party", "raid", "layout" },
    raid = { "group frames", "groupframes", "raid frames", "raid frame", "layout", "party", "anchoring", "move raid frames" },
    party = { "group frames", "groupframes", "party frames", "party frame", "layout", "raid", "anchoring", "move party frames" },
    group = { "group frames", "party", "raid", "layout" },
    groupframes = { "group frames", "party", "raid", "layout" },
    debuff = { [0] = false, "debuffs", "auras", "aura", "buffs", "dispellable debuffs", "dispel border", "dispel glow", "dispel overlay", "debuff stripe", "magic", "curse", "poison", "disease", "any debuff" },
    debuffs = { [0] = false, "debuff", "auras", "aura", "buffs", "dispellable debuffs", "dispel border", "dispel glow", "dispel overlay", "debuff stripe", "magic", "curse", "poison", "disease", "any debuff" },
    buff = { "buffs", "auras", "aura", "debuffs" },
    buffs = { "buff", "auras", "aura", "debuffs" },
    aura = { "auras", "buffs", "debuffs", "private auras", "cooldown", "aura filters" },
    auras = { "aura", "buffs", "debuffs", "private auras", "cooldown", "aura filters" },
    hot = { "hots", "healer buffs", "own buffs", "aura indicators", "group buffs" },
    hots = { "hot", "healer buffs", "own buffs", "aura indicators", "group buffs" },
    own = { "only mine", "own buffs", "own debuffs", "player only", "aura filters" },
    personal = { "only mine", "own buffs", "own debuffs", "player only", "aura filters" },
    spellid = { "spell id", "custom spells", "custom auras", "aura utilities" },
    spellids = { "spell id", "custom spells", "custom auras", "aura utilities" },
    bossdebuff = { "boss debuffs", "raid debuffs", "custom auras", "private auras" },
    bossdebuffs = { "boss debuffs", "raid debuffs", "custom auras", "private auras" },
    private = { "private auras", "auras", "raid mechanics" },
    dispel = { [0] = false, "dispel border", "dispel glow", "dispel overlay", "dispellable debuffs", "dispel border detects", "any dispel-type debuff", "any debuff", "magic", "curse", "poison", "disease", "cleanse", "decurse", "group indicators", "highlight borders" },
    dispels = { [0] = false, "dispel", "dispel border", "dispel glow", "dispellable debuffs", "magic", "curse", "poison", "disease" },
    dispell = { [0] = false, "dispel", "dispel border", "dispel glow", "dispellable debuffs", "cleanse", "decurse" },
    dispellable = { [0] = false, "dispellable debuffs", "dispel border detects", "dispellable by me", "any dispel-type debuff", "magic", "curse", "poison", "disease" },
    dispelable = { [0] = false, "dispellable", "dispellable debuffs", "dispel border detects" },
    cleansing = { [0] = false, "cleanse", "dispel", "dispellable debuffs", "magic", "curse", "poison", "disease" },
    cleanse = { [0] = false, "dispel", "dispellable debuffs", "magic", "curse", "poison", "disease" },
    decurse = { [0] = false, "curse", "dispel", "dispellable debuffs" },
    cure = { [0] = false, "cleanse", "dispel", "poison", "disease", "dispellable debuffs" },
    magic = { [0] = false, "dispel", "dispellable debuffs", "dispel border detects", "dispel test type" },
    curse = { [0] = false, "dispel", "decurse", "dispellable debuffs", "dispel border detects", "dispel test type" },
    poison = { [0] = false, "dispel", "cleanse", "dispellable debuffs", "dispel border detects", "dispel test type" },
    disease = { [0] = false, "dispel", "cleanse", "dispellable debuffs", "dispel border detects", "dispel test type" },
    bleed = { [0] = false, "debuff", "any debuff", "dispel test type" },
    stealable = { [0] = false, "auras", "buffs", "purge", "dispel", "spellsteal", "purge border", "offensive dispel" },
    purge = { [0] = false, "dispel", "stealable", "auras", "buffs", "purge border", "spellsteal", "offensive dispel" },
    spellsteal = { [0] = false, "stealable", "purge", "purge border", "offensive dispel", "buffs" },
    pandemic = { "auras", "cooldown text", "debuffs", "timer" },
    timer = { "cooldown text", "aura timers", "cast time", "combat timer" },
    cooldown = { "cooldown text", "cooldown swipe", "aura timers", "interrupt ready" },
    cooldowns = { "cooldown", "cooldown text", "cooldown swipe", "aura timers", "interrupt ready" },
    blacklist = { "ignore list", "global ignore list", "hide aura", "hide buff", "hide debuff", "unit auras", "aura filters" },
    ignore = { "ignore list", "global ignore list", "blacklist", "hide aura", "hide buff", "hide debuff", "unit auras" },
    absorb = { "absorbs", "absorb display", "heal prediction", "health" },
    absorbs = { "absorb", "absorb display", "heal prediction", "health" },
    heal = { "heal prediction", "incoming heals", "health", "healer" },
    aggro = { [0] = false, "threat", "aggro", "aggro border", "highlight borders", "indicators", "highlight priority" },
    threat = { [0] = false, "aggro", "threat border", "highlight borders", "indicators", "highlight priority" },

    blizzard = { "blizzard frames", "default frames", "hide blizzard", "disable blizzard" },
    default = { "blizzard frames", "default frames", "hide blizzard", "disable blizzard" },
    unlock = { "edit mode", "move", "drag", "frames unlocked", "lock frames" },
    locked = { "edit mode", "move", "drag", "frames locked", "lock frames", "disabled", "shared setting", "custom caps" },
    solo = { "show solo", "show player solo", "party frames solo", "group frames" },
    self = { "player", "show player", "hide player", "party frames" },
    tooltip = { "tooltips", "unitframe tooltips", "mouseover tooltip" },
    tooltips = { "tooltip", "unitframe tooltips", "mouseover tooltip" },
    language = { "locale", "localization", "translation", "sprache" },
    sprache = { "language", "locale", "localization", "translation" },
    click = { "click cast", "clickthrough", "click-through", "mouse", "mouseover", "target modifier" },
    clickcast = { "click cast", "click casting", "mouse", "targeting" },
    clickthrough = { "click-through", "click through", "mouse", "auras", "unitframe tooltips" },
    mouseover = { "mouse", "mouseover highlight", "tooltip", "click cast", "targeting" },
    menu = { "dashboard", "menu scale", "ui scale", "search", "support" },
    window = { "menu", "dashboard", "reset positions", "ui scale" },
    ui = { "ui scale", "menu scale", "dashboard" },

    unit = { "unit frame", "unit frames", "unitframe", "frame basics" },
    units = { "unit frame", "unit frames", "unitframe", "frame basics" },
    einheit = { "unit", "unit frame", "unitframe" },
    einheiten = { "unit", "unit frames", "unitframe" },
    einheitenfenster = { "unit frame", "unitframe", "frames" },
    spieler = { "player", "player frame", "playerframe" },
    spielerframe = { "player frame", "playerframe", "unit frame" },
    ziel = { "target", "target frame", "targetframe" },
    zielframe = { "target frame", "targetframe", "unit frame" },
    zielziel = { "target of target", "targettarget", "tot" },
    tot = { "target of target", "targettarget", "target target" },
    targettarget = { "target of target", "tot", "target target" },
    fokusziel = { "focus target", "focustarget", "focus target frame" },
    focusziel = { "focus target", "focustarget", "focus target frame" },
    ft = { "focus target", "focustarget", "focus target frame" },
    fokus = { "focus", "focus frame", "focusframe", "focus kick" },
    fokusframe = { "focus frame", "focusframe", "focus kick" },
    begleiter = { "pet", "pet frame", "petframe" },
    haustier = { "pet", "pet frame", "petframe" },

    enable = { "show", "visible", "frame basics", "aktivieren" },
    disable = { "hide", "hidden", "frame basics", "deaktivieren" },
    visible = { "show", "enable", "sichtbar" },
    aktivieren = { "enable", "show", "visible" },
    deaktivieren = { "disable", "hide", "hidden" },
    anzeigen = { "show", "visible", "enable" },
    ausblenden = { "hide", "hidden", "disable" },
    abschalten = { "disable", "hide", "hidden" },
    ausgegraut = { "disabled", "locked", "shared setting", "custom caps", "unit auras" },
    grau = { "disabled", "locked", "shared setting" },
    sichtbar = { "visible", "show", "enable" },
    unsichtbar = { "invisible", "hidden", "alpha", "transparency" },
    versteckt = { "hidden", "hide", "disable" },
    verschieben = { "move", "drag", "position", "edit mode", "anchor" },
    bewegen = { "move", "drag", "position", "edit mode" },
    ziehen = { "drag", "move", "edit mode" },
    verankern = { "anchor", "anchoring", "position" },
    anker = { "anchor", "anchoring", "position" },
    koordinaten = { "x offset", "y offset", "position", "anchor" },
    editmode = { "edit mode", "move", "drag", "position" },
    loadconditions = { "load conditions", "visibility", "show", "hide" },
    breite = { "width", "size", "resize", "frame basics" },
    hoehe = { "height", "size", "resize", "frame basics" },
    groesse = { "size", "resize", "scale", "width", "height" },
    skalierung = { "scale", "size", "frame scaling", "ui scale" },

    layout = { "group frames", "frame basics", "growth", "sorting", "anchoring" },
    sorting = { "sort", "role order", "group frames", "layout" },
    sortierung = { "sorting", "role order", "group frames", "layout" },
    growth = { "growth direction", "layout", "group frames" },
    spalten = { "columns", "layout", "group frames" },
    reihen = { "rows", "layout", "auras", "group frames" },
    rolle = { "role", "role icon", "sorting", "tank", "healer", "dps" },
    role = { "role icon", "sorting", "tank", "healer", "dps" },
    groupnumber = { "group number", "indicators", "group frames" },
    tank = { "role icon", "group indicators", "sorting" },
    healer = { "role icon", "healer buffs", "group indicators" },
    dps = { "role icon", "group indicators", "sorting" },

    healthbar = { "health bar", "health", "hp", "bar colors" },
    powerbar = { "power bar", "power", "mana", "class resources" },
    lebensbalken = { "health bar", "health", "hp" },
    energieleiste = { "power bar", "power", "mana" },
    manabar = { "mana", "power bar", "power" },
    color = { "colors", "bar colors", "unitframe colors", "class colors" },
    colours = { "colors", "color", "bar colors" },
    farbe = { "colors", "color", "bar colors", "class colors" },
    farben = { "colors", "color", "bar colors", "class colors" },
    klassfarbe = { "class color", "class colors", "health color" },
    classcolor = { "class color", "class colors", "health color" },
    reaction = { "reaction color", "npc type colors", "colors" },
    npc = { "npc type colors", "reaction color", "colors" },
    highlight = { [0] = false, "highlights", "mouseover highlight", "highlight borders", "dispel highlight", "aggro border", "target border", "focus highlight", "highlight priority", "colors", "bars" },
    highlights = { [0] = false, "highlight", "highlight borders", "dispel highlight", "aggro border", "target border", "focus highlight", "highlight priority", "mouseover highlight" },
    border = { [0] = false, "borders", "highlight borders", "frame outline", "dispel border", "aggro border", "purge border", "target border", "focus highlight", "group border" },
    borders = { [0] = false, "border", "highlight borders", "frame outline", "dispel border", "aggro border", "purge border", "target border", "focus highlight", "group border" },
    glow = { [0] = false, "dispel glow", "glow style", "glow lines", "glow speed", "glow thickness", "focus glow", "highlight borders" },
    overlay = { [0] = false, "dispel overlay", "unitframe dispel overlay", "overlay style", "overlay opacity", "health bar tint" },
    stripe = { [0] = false, "debuff stripe", "stripe edge", "stripe height", "stripe opacity", "debuff filter" },
    priority = { [0] = false, "highlight priority", "dispel priority", "aggro priority", "target priority", "focus priority" },

    fontsize = { "font size", "text size", "fonts", "text" },
    textsize = { "text size", "font size", "fonts", "text" },
    schrift = { "font", "fonts", "text", "font size" },
    schriftart = { "font", "fonts", "font family" },
    schriftgroesse = { "font size", "text size", "fonts" },
    namen = { "names", "name text", "name shortening" },
    kuerzen = { "name shortening", "short names", "truncate names", "max name length" },
    gekuerzt = { "name shortening", "short names", "truncate names", "max name length" },
    namenskuerzung = { "name shortening", "short names", "truncate names", "max name length" },
    namenskurzung = { "name shortening", "short names", "truncate names", "max name length" },
    kuerzung = { "name shortening", "short names", "truncate names", "max name length" },
    ueberschreiben = { "override", "font override", "custom settings" },
    ueberschreibung = { "override", "font override", "custom settings" },
    realm = { "realm names", "name shortening", "short names" },
    server = { "realm names", "name shortening", "short names" },
    truncate = { "name shortening", "short names", "max name length" },
    nameshortening = { "name shortening", "short names", "truncate names", "realm names" },
    healthtext = { "health text", "hp text", "text", "fonts" },
    powertext = { "power text", "mana text", "text", "fonts" },
    nametext = { "name text", "text", "fonts", "name shortening" },
    stufe = { "level", "level indicator", "level text", "show level", "status icons" },
    stufen = { "level", "level indicator", "level text", "show level", "status icons" },
    stufentext = { "level text", "level indicator", "show level", "status icons", "anchor", "position" },
    levelanzeige = { "level indicator", "level text", "show level", "status icons", "anchor", "position" },
    statusanzeige = { "status indicator", "status icons", "indicator", "level indicator" },

    portrait = { "portraits", "portrait mode", "class icon", "2d portrait", "3d portrait" },
    portraits = { "portrait", "portrait mode", "class icon" },
    avatar = { "portrait", "portraits", "class icon" },
    portraet = { "portrait", "portraits", "class icon" },
    portraitdeko = { "portrait decoration", "modules", "style" },
    castbalken = { "castbar", "cast bar", "casting" },
    zauberbalken = { "castbar", "cast bar", "casting" },
    spell = { "spell name", "castbar", "auras", "spell id" },
    spellname = { "spell name", "castbar", "name shortening" },
    globalcooldown = { "gcd", "global cooldown", "castbar" },
    interruptready = { "interrupt ready", "focus kick", "kick", "castbar" },
    kanal = { "channel", "channel ticks", "castbar" },
    kanalisieren = { "channel", "channel ticks", "castbar" },
    unterbrechen = { "interrupt", "kick", "focus kick", "interrupt ready" },
    fokuskick = { "focus kick", "interrupt", "kick", "castbar" },

    stack = { "stacks", "aura stack count", "auras" },
    stacks = { "stack", "aura stack count", "auras" },
    stapel = { "stacks", "stack", "auras" },
    cooldowntext = { "cooldown text", "timer", "auras" },
    swipe = { "cooldown swipe", "auras", "cooldown" },
    staerkungszauber = { "buffs", "buff", "auras" },
    zauber = { "spell", "auras", "castbar", "spell id" },
    defensives = { "defensives", "externals", "group buffs", "auras" },
    externals = { "defensives", "external cooldowns", "group buffs", "auras" },

    gruppe = { "group frames", "groupframes", "party", "raid", "layout" },
    gruppen = { "group frames", "groupframes", "party", "raid", "layout" },
    gruppenrahmen = { "group frames", "groupframes", "party", "raid", "layout" },
    gruppenfenster = { "group frames", "groupframes", "party", "raid", "layout" },
    raidframe = { "raid frames", "raidframes", "group frames", "layout" },
    partyframe = { "party frames", "partyframes", "group frames", "layout" },
    schlachtzug = { "raid", "raid frames", "group frames" },
    mythic = { "mythic raid", "raid", "group frames" },
    readycheck = { "ready check", "status icons", "group indicators" },
    bereitschaft = { "ready check", "status icons", "group indicators" },
    statusicon = { "status icons", "indicators", "dead", "offline", "ready check" },
    statusicons = { "status icons", "indicators", "dead", "offline", "ready check" },
    marker = { "raid marker", "markers", "indicators" },
    raidmarker = { "raid marker", "marker", "indicators" },
    leader = { "leader icon", "status icons", "indicators" },
    assist = { "assist icon", "status icons", "indicators" },
    offline = { "offline icon", "status icons", "indicators" },
    afk = { "afk icon", "status icons", "indicators" },
    dead = { "dead icon", "ghost", "status icons", "indicators" },

    profil = { "profile", "profiles", "import", "export" },
    importieren = { "import", "profiles", "wago", "profile string" },
    exportieren = { "export", "profiles", "profile string" },
    kopieren = { "copy profile", "profiles", "import", "export" },
    teilen = { "share profile", "export", "wago" },
    backup = { "profiles", "export", "copy profile" },
    restore = { "profiles", "import", "reset" },

    minimap = { "minimap icon", "minimap button", "miscellaneous" },
    minimapicon = { "minimap icon", "minimap button", "miscellaneous" },
    minimapbutton = { "minimap icon", "minimap button", "miscellaneous" },
    minikarte = { "minimap", "minimap icon", "miscellaneous" },
    sound = { "sounds", "target sound", "target lost", "miscellaneous" },
    sounds = { "sound", "target sound", "target lost", "miscellaneous" },
    targetsound = { "target sound", "target lost", "sounds", "miscellaneous" },
    versioncheck = { "version check", "miscellaneous", "update intervals" },
    menuscale = { "menu scale", "dashboard", "ui scale" },
    uiscale = { "ui scale", "dashboard", "menu scale" },
    unitauras = { "unit auras", "auras", "buffs", "debuffs" },
    globalstyle = { "global style", "bars", "fonts", "colors", "castbar", "miscellaneous" },
    blizzardframes = { "blizzard frames", "default frames", "hide blizzard", "disable blizzard" },
    standardframes = { "default frames", "blizzard frames", "hide blizzard" },

    crosshair = { "combat crosshair", "gameplay", "melee range spell", "range check" },
    fadenkreuz = { "crosshair", "combat crosshair", "gameplay", "melee range spell" },
    melee = { "melee range spell", "crosshair", "range check" },
    maus = { "mouse", "mouseover", "click cast", "targeting" },
    maustaste = { "mouse buttons", "click cast", "targeting" },
    klick = { "click", "click cast", "clickthrough", "targeting" },
    klicken = { "click", "click cast", "clickthrough", "targeting" },
    heilung = { "heal", "healer", "click cast", "mouseover" },
    mouseoverheal = { "mouseover heal", "click cast", "healing" },

    ruckelt = { "lag", "fps", "performance", "update intervals" },
    haengt = { "lag", "fps", "performance", "update intervals" },
    langsam = { "slow", "performance", "lag", "fps" },
    cpu = { "performance", "update intervals", "auras", "cooldown" },
    speicher = { "performance", "auras", "profiles" },
    optimieren = { "performance", "update intervals", "auras", "fps" },
    classpower = { "class resources", "power", "resource" },
    klassenressourcen = { "class resources", "classpower", "resource" },
    klassenressource = { "class resources", "classpower", "resource" },
    combopoints = { "combo points", "class resources", "rogue" },
    soulshards = { "soul shards", "class resources", "warlock" },
    runen = { "runes", "runic power", "class resources" },
    eclipse = { "eclipse", "class resources", "druid" },
    stagger = { "stagger", "class resources", "brewmaster" },
}

local SEARCH_DISPEL_DEBUFF_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DISPEL_DEBUFF_KEYWORDS",
}

local SEARCH_HIGHLIGHT_BORDER_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_HIGHLIGHT_BORDER_KEYWORDS",
}

local SEARCH_DISPEL_OVERLAY_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DISPEL_OVERLAY_KEYWORDS",
}

local SEARCH_DEBUFF_STRIPE_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DEBUFF_STRIPE_KEYWORDS",
}

local SEARCH_BLIZZARD_DISPEL_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_BLIZZARD_DISPEL_KEYWORDS",
}

local SEARCH_UNIT_AURA_DISPEL_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_UNIT_AURA_DISPEL_KEYWORDS",
}

local SEARCH_DASHBOARD_RECOVERY_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_RECOVERY_KEYWORDS",
}

local SEARCH_DASHBOARD_DISCORD_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_DISCORD_KEYWORDS",
}

local SEARCH_DASHBOARD_SUPPORT_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_SUPPORT_KEYWORDS",
}

local SEARCH_DASHBOARD_WAGO_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_WAGO_KEYWORDS",
}

local SEARCH_DASHBOARD_SCALING_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_SCALING_KEYWORDS",
}

local SEARCH_DASHBOARD_CHANGELOG_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_CHANGELOG_KEYWORDS",
}

local function SearchKeywordList(...)
    local out = {}
    for i = 1, select("#", ...) do
        local list = select(i, ...)
        if type(list) == "table" then
            for k = 1, #list do out[#out + 1] = list[k] end
        elseif list then
            out[#out + 1] = list
        end
    end
    return out
end

local SEARCH_PAGE_LOCALIZED_KEYWORDS = {}

local function AppendSearchKeywords(pageKey, list)
    if not (pageKey and type(list) == "table" and #list > 0) then return end
    local pageList = SEARCH_PAGE_LOCALIZED_KEYWORDS[pageKey]
    if not pageList then
        pageList = {}
        SEARCH_PAGE_LOCALIZED_KEYWORDS[pageKey] = pageList
    end
    for i = 1, #list do pageList[#pageList + 1] = list[i] end
end

local function AddPageLocalizedSearchKeywords(parts, pageKey)
    local list = SEARCH_PAGE_LOCALIZED_KEYWORDS[pageKey]
    if type(list) ~= "table" then return end
    for i = 1, #list do AddSearchText(parts, list[i]) end
end

AppendSearchKeywords("gf_bars", SEARCH_DISPEL_OVERLAY_KEYWORDS)
AppendSearchKeywords("gf_bars", SEARCH_DEBUFF_STRIPE_KEYWORDS)
AppendSearchKeywords("gf_auras", SEARCH_DISPEL_DEBUFF_KEYWORDS)
AppendSearchKeywords("gf_auras", SEARCH_BLIZZARD_DISPEL_KEYWORDS)
AppendSearchKeywords("gf_indicators", SEARCH_DISPEL_DEBUFF_KEYWORDS)
AppendSearchKeywords("gf_indicators", SEARCH_HIGHLIGHT_BORDER_KEYWORDS)
AppendSearchKeywords("opt_bars", SEARCH_HIGHLIGHT_BORDER_KEYWORDS)
AppendSearchKeywords("opt_bars", SEARCH_DISPEL_DEBUFF_KEYWORDS)
AppendSearchKeywords("opt_bars", SEARCH_DISPEL_OVERLAY_KEYWORDS)
AppendSearchKeywords("auras2", SEARCH_UNIT_AURA_DISPEL_KEYWORDS)
AppendSearchKeywords("auras2", SEARCH_DISPEL_DEBUFF_KEYWORDS)
AppendSearchKeywords("home", SEARCH_DASHBOARD_RECOVERY_KEYWORDS)
AppendSearchKeywords("home", SEARCH_DASHBOARD_SUPPORT_KEYWORDS)
AppendSearchKeywords("home", SEARCH_DASHBOARD_WAGO_KEYWORDS)
AppendSearchKeywords("home", SEARCH_DASHBOARD_SCALING_KEYWORDS)
AppendSearchKeywords("home", SEARCH_DASHBOARD_CHANGELOG_KEYWORDS)

local CONTROL_KIND_LABEL = {
    faq = "FAQ",
    easteregg = "Easter Egg",
    section = "Section",
    button = "Button",
    toggle = "Toggle",
    slider = "Slider",
    dropdown = "Dropdown",
    segment = "Choice",
    textinput = "Text Input",
    color = "Color",
}

local DASHBOARD_ROUTE_RECOVERY = { state = { dashboardRecoveryOpen = true } }
local DASHBOARD_ROUTE_SCALING = { state = { dashboardScalingOpen = true } }
local DASHBOARD_ROUTE_CHANGELOG = { state = { dashboardChangelogOpen = true } }

local function AddSearchTermUnique(list, seen, term)
    if #list >= SEARCH_MAX_TERMS_PER_CLAUSE then return end
    term = NormalizeSearchText(term)
    if term == "" or SearchIgnoreQueryWord(term) or seen[term] then return end
    seen[term] = true
    list[#list + 1] = term
end

local function SearchRawWords(normalized)
    local raw = {}
    for word in tostring(normalized or ""):gmatch("%S+") do
        if not SearchIgnoreQueryWord(word) then raw[#raw + 1] = word end
        if #raw >= SEARCH_MAX_RAW_WORDS then break end
    end
    return raw
end

local SearchEditDistanceWithin

local function SearchAliasTypoKeys()
    if SEARCH_STATE.aliasTypoKeys then return SEARCH_STATE.aliasTypoKeys end
    local keys = {}
    for key in pairs(SEARCH_QUERY_ALIASES) do
        if #key >= 5 then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        if #a ~= #b then return #a < #b end
        return a < b
    end)
    SEARCH_STATE.aliasTypoKeys = keys
    return keys
end

local function SearchAliasKeyForTypo(word)
    if not SearchEditDistanceWithin or #word < 5 then return nil end
    if SEARCH_STATE.aliasTypoCache[word] ~= nil then return SEARCH_STATE.aliasTypoCache[word] or nil end
    local maxDistance = (#word >= 8) and 2 or 1
    local bestKey, bestDelta
    local keys = SearchAliasTypoKeys()
    for i = 1, #keys do
        local key = keys[i]
        if math.abs(#key - #word) <= maxDistance and SearchEditDistanceWithin(word, key, maxDistance) then
            local delta = math.abs(#key - #word)
            if not bestKey or delta < bestDelta or (delta == bestDelta and #key < #bestKey) then
                bestKey = key
                bestDelta = delta
            end
        end
    end
    SEARCH_STATE.aliasTypoCache[word] = bestKey or false
    return bestKey
end

local function SearchCanonicalWords(raw)
    local words = {}
    local i = 1
    while i <= #raw do
        local word = raw[i]
        local nextWord = raw[i + 1]
        if word == "demon" and nextWord == "hunter" then
            words[#words + 1] = "demonhunter"
            i = i + 2
        elseif word == "death" and nextWord == "knight" then
            words[#words + 1] = "deathknight"
            i = i + 2
        elseif word == "wind" and nextWord == "shear" then
            words[#words + 1] = "windshear"
            i = i + 2
        elseif word == "cast" and nextWord == "bar" then
            words[#words + 1] = "castbar"
            i = i + 2
        elseif word == "health" and nextWord == "bar" then
            words[#words + 1] = "healthbar"
            i = i + 2
        elseif word == "power" and nextWord == "bar" then
            words[#words + 1] = "powerbar"
            i = i + 2
        elseif word == "show" and nextWord == "buffs" then
            words[#words + 1] = "showbuffs"
            i = i + 2
        elseif word == "max" and nextWord == "buffs" then
            words[#words + 1] = "maxbuffs"
            i = i + 2
        elseif word == "custom" and nextWord == "caps" then
            words[#words + 1] = "customcaps"
            i = i + 2
        elseif (word == "smooth" or word == "soft" or word == "fluid") and nextWord == "fill" then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif (word == "weiche" or word == "weichen" or word == "sanfte" or word == "fluessige") and nextWord == "fuellung" then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif (word == "relleno" or word == "llenado") and (nextWord == "suave" or nextWord == "fluido") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif word == "remplissage" and (nextWord == "doux" or nextWord == "fluide") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif word == "riempimento" and (nextWord == "fluido" or nextWord == "morbido") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif word == "preenchimento" and (nextWord == "suave" or nextWord == "fluido") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif (word == "плавное" or word == "плавная") and (nextWord == "заполнение" or nextWord == "заливка") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif (word == "부드러운" and nextWord == "채우기") or (word == "막대" and nextWord == "애니메이션") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif word == "class" and (nextWord == "resource" or nextWord == "resources" or nextWord == "power") then
            words[#words + 1] = "classpower"
            i = i + 2
        elseif word == "click" and (nextWord == "cast" or nextWord == "casting") then
            words[#words + 1] = "clickcast"
            i = i + 2
        elseif word == "click" and nextWord == "through" then
            words[#words + 1] = "clickthrough"
            i = i + 2
        elseif word == "edit" and nextWord == "mode" then
            words[#words + 1] = "editmode"
            i = i + 2
        elseif word == "load" and (nextWord == "condition" or nextWord == "conditions") then
            words[#words + 1] = "loadconditions"
            i = i + 2
        elseif word == "ready" and nextWord == "check" then
            words[#words + 1] = "readycheck"
            i = i + 2
        elseif word == "raid" and nextWord == "marker" then
            words[#words + 1] = "raidmarker"
            i = i + 2
        elseif word == "group" and nextWord == "number" then
            words[#words + 1] = "groupnumber"
            i = i + 2
        elseif word == "name" and nextWord == "shortening" then
            words[#words + 1] = "nameshortening"
            i = i + 2
        elseif word == "global" and nextWord == "cooldown" then
            words[#words + 1] = "globalcooldown"
            i = i + 2
        elseif word == "focus" and nextWord == "kick" then
            words[#words + 1] = "fokuskick"
            i = i + 2
        elseif word == "interrupt" and nextWord == "ready" then
            words[#words + 1] = "interruptready"
            i = i + 2
        elseif word == "level" and nextWord == "text" then
            words[#words + 1] = "leveltext"
            i = i + 2
        elseif word == "level" and nextWord == "indicator" then
            words[#words + 1] = "levelindicator"
            i = i + 2
        elseif word == "status" and (nextWord == "indicator" or nextWord == "indicators") then
            words[#words + 1] = "statusindicators"
            i = i + 2
        elseif word == "status" and (nextWord == "icon" or nextWord == "icons") then
            words[#words + 1] = "statusicons"
            i = i + 2
        elseif word == "turn" and nextWord == "off" then
            words[#words + 1] = "onoff"
            i = i + 2
        elseif word == "minimap" and (nextWord == "icon" or nextWord == "button") then
            words[#words + 1] = "minimapicon"
            i = i + 2
        elseif word == "ko" and nextWord == "fi" then
            words[#words + 1] = "kofi"
            i = i + 2
        elseif word == "menu" and nextWord == "scale" then
            words[#words + 1] = "menuscale"
            i = i + 2
        elseif word == "ui" and nextWord == "scale" then
            words[#words + 1] = "uiscale"
            i = i + 2
        elseif word == "target" and (nextWord == "sound" or nextWord == "sounds") then
            words[#words + 1] = "targetsound"
            i = i + 2
        elseif word == "unit" and (nextWord == "aura" or nextWord == "auras") then
            words[#words + 1] = "unitauras"
            i = i + 2
        elseif word == "global" and nextWord == "style" then
            words[#words + 1] = "globalstyle"
            i = i + 2
        elseif word == "spell" and nextWord == "id" then
            words[#words + 1] = "spellid"
            i = i + 2
        elseif word == "health" and nextWord == "text" then
            words[#words + 1] = "healthtext"
            i = i + 2
        elseif word == "power" and nextWord == "text" then
            words[#words + 1] = "powertext"
            i = i + 2
        elseif word == "name" and nextWord == "text" then
            words[#words + 1] = "nametext"
            i = i + 2
        elseif word == "class" and nextWord == "color" then
            words[#words + 1] = "classcolor"
            i = i + 2
        elseif word == "range" and (nextWord == "check" or nextWord == "checker" or nextWord == "checking") then
            words[#words + 1] = "rangecheck"
            i = i + 2
        elseif word == "distance" and (nextWord == "check" or nextWord == "checker" or nextWord == "checking") then
            words[#words + 1] = "distancecheck"
            i = i + 2
        elseif word == "out" and nextWord == "range" then
            words[#words + 1] = "outofrange"
            i = i + 2
        elseif word == "unit" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "unitframe"
            i = i + 2
        elseif word == "player" and nextWord == "frame" then
            words[#words + 1] = "playerframe"
            i = i + 2
        elseif word == "target" and nextWord == "frame" then
            words[#words + 1] = "targetframe"
            i = i + 2
        elseif word == "focus" and nextWord == "frame" then
            words[#words + 1] = "focusframe"
            i = i + 2
        elseif word == "focus" and nextWord == "target" then
            words[#words + 1] = "focustarget"
            local thirdWord = raw[i + 2]
            if thirdWord == "frame" then
                words[#words + 1] = "focustargetframe"
                i = i + 3
            else
                i = i + 2
            end
        elseif word == "pet" and nextWord == "frame" then
            words[#words + 1] = "petframe"
            i = i + 2
        elseif word == "boss" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "bossframes"
            i = i + 2
        elseif word == "party" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "partyframes"
            i = i + 2
        elseif word == "raid" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "raidframes"
            i = i + 2
        else
            words[#words + 1] = word
            i = i + 1
        end
    end
    return words
end

local function BuildSearchQueryClauses(query)
    local normalized = NormalizeSearchText(query)
    if normalized == SEARCH_STATE.queryClauseCacheNorm and SEARCH_STATE.queryClauseCacheClauses then
        return normalized, SEARCH_STATE.queryClauseCacheClauses
    end
    local raw = SearchRawWords(normalized)
    local words = SearchCanonicalWords(raw)
    local clauses = {}
    for i = 1, #words do
        if #clauses >= SEARCH_MAX_QUERY_CLAUSES then break end
        local word = words[i]
        local terms, seen = {}, {}
        AddSearchTermUnique(terms, seen, word)
        local aliases = SEARCH_QUERY_ALIASES[word]
        if not aliases then
            local aliasKey = SearchAliasKeyForTypo(word)
            if aliasKey then
                AddSearchTermUnique(terms, seen, aliasKey)
                aliases = SEARCH_QUERY_ALIASES[aliasKey]
            end
        end
        if aliases then
            for k = 1, #aliases do AddSearchTermUnique(terms, seen, aliases[k]) end
        end
        if #terms > 0 then
            clauses[#clauses + 1] = { word = word, terms = terms }
        end
    end
    SEARCH_STATE.queryClauseCacheNorm = normalized
    SEARCH_STATE.queryClauseCacheClauses = clauses
    return normalized, clauses
end

local function BuildSearchTokenList(normalized, limit)
    limit = tonumber(limit) or SEARCH_MAX_RECORD_TOKENS
    local tokens, seen = {}, {}
    for token in tostring(normalized or ""):gmatch("%S+") do
        if #token >= 2 and not SEARCH_STOP_WORDS[token] and not seen[token] then
            seen[token] = true
            tokens[#tokens + 1] = token
            if #tokens >= limit then break end
        end
    end
    return tokens
end

SearchEditDistanceWithin = function(a, b, maxDistance)
    if a == b then return true end
    maxDistance = tonumber(maxDistance) or 1
    local la, lb = #a, #b
    if math.abs(la - lb) > maxDistance then return false end

    if maxDistance <= 1 then
        if la == lb then
            local firstMismatch, mismatches = nil, 0
            for i = 1, la do
                if a:sub(i, i) ~= b:sub(i, i) then
                    mismatches = mismatches + 1
                    firstMismatch = firstMismatch or i
                    if mismatches > 2 then return false end
                end
            end
            if mismatches <= 1 then return true end
            return mismatches == 2
                and firstMismatch < la
                and a:sub(firstMismatch, firstMismatch) == b:sub(firstMismatch + 1, firstMismatch + 1)
                and a:sub(firstMismatch + 1, firstMismatch + 1) == b:sub(firstMismatch, firstMismatch)
        end

        local short, long = a, b
        if la > lb then short, long = b, a end
        local i, j, edits = 1, 1, 0
        while i <= #short and j <= #long do
            if short:sub(i, i) == long:sub(j, j) then
                i = i + 1
                j = j + 1
            else
                edits = edits + 1
                if edits > 1 then return false end
                j = j + 1
            end
        end
        return true
    end

    local prev, curr = {}, {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        curr[0] = i
        local rowMin = curr[0]
        local ca = a:sub(i, i)
        for j = 1, lb do
            local cost = (ca == b:sub(j, j)) and 0 or 1
            local value = math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            curr[j] = value
            if value < rowMin then rowMin = value end
        end
        if rowMin > maxDistance then return false end
        prev, curr = curr, prev
    end
    return prev[lb] <= maxDistance
end

local function SearchFuzzyTokenMatch(rec, term)
    if not rec or #term < 5 or term:find(" ", 1, true) then return false end
    if not rec.tokens then
        rec.tokens = BuildSearchTokenList(rec.haystack or "", rec.tokenLimit)
    end
    if not rec.tokens then return false end
    local maxDistance = (#term >= 8) and 2 or 1
    for i = 1, #rec.tokens do
        local token = rec.tokens[i]
        if math.abs(#token - #term) <= maxDistance and SearchEditDistanceWithin(token, term, maxDistance) then
            return true
        end
    end
    return false
end

local function SearchTermScore(rec, term, queryWord)
    local haystack = rec.haystack or ""
    local score = 0
    if haystack:find(term, 1, true) then
        if rec.labelNorm == term or rec.titleNorm == term then score = score + 180 end
        if rec.labelNorm:sub(1, #term) == term or rec.titleNorm:sub(1, #term) == term then score = score + 90 end
        if rec.labelNorm:find(term, 1, true) then score = score + 70 end
        if rec.titleNorm:find(term, 1, true) then score = score + 55 end
        if rec.hintNorm and rec.hintNorm:find(term, 1, true) then score = score + 45 end
        if rec.groupNorm:find(term, 1, true) then score = score + 35 end
        if term ~= queryWord then score = score + 35 end
        return true, score + 10
    end
    if term == queryWord and SearchFuzzyTokenMatch(rec, term) then
        return true, (term == queryWord) and 28 or 20
    end
    return false, 0
end

local function SearchClauseScore(rec, clause)
    local best = 0
    for i = 1, #clause.terms do
        local matched, score = SearchTermScore(rec, clause.terms[i], clause.word)
        if matched and score > best then best = score end
    end
    return best > 0, best
end

local function SearchLooksLikeSupportQuestion(query)
    local normalized = NormalizeSearchText(query)
    if normalized == "" then return false end
    if tostring(query or ""):find("?", 1, true) then return true end
    if normalized:find("how ", 1, true) or normalized:find("where ", 1, true) or normalized:find("why ", 1, true) then return true end
    if normalized:find("what ", 1, true) or normalized:find("help ", 1, true) then return true end
    if normalized:find("do i", 1, true) or normalized:find("can i", 1, true) then return true end
    for _, word in ipairs({ "missing", "gone", "invisible", "broken", "bugged", "wrong", "offscreen", "overlap", "overlapping", "lag", "fps", "lockdown" }) do
        if normalized:find(word, 1, true) then return true end
    end
    if normalized:find("not showing", 1, true) or normalized:find("doesnt show", 1, true) or normalized:find("not working", 1, true) then return true end
    if normalized:find("too big", 1, true) or normalized:find("too small", 1, true) or normalized:find("too many", 1, true) then return true end
    for _, word in ipairs({ "move", "drag", "resize", "hide", "show", "enable", "disable", "change", "reset", "import", "export" }) do
        if normalized == word or normalized:find("^" .. word .. " ", 1, false) or normalized:find(" " .. word .. " ", 1, false) then
            return true
        end
    end
    if normalized:find("my ", 1, true) and (
        normalized:find("change", 1, true)
        or normalized:find("move", 1, true)
        or normalized:find("hide", 1, true)
        or normalized:find("show", 1, true)
        or normalized:find("not", 1, true)
    ) then
        return true
    end
    return false
end

local SEARCH_CONTROL_QUERY_TERMS = "toggle checkbox switch enable disable enabled disabled show hide dropdown select choose slider adjust increase decrease color colour swatch input field textfield editbox aktivier deaktivier einschalt ausschalt anzeigen ausblenden auswahl auswaehlen dropdown regler schieberegler aument reducir ajustar seleccionar choisir activer desactiver selezionare attivare disattivare ativar desativar выбрать включить отключить 설정 선택 사용 비활성 활성 下拉 选择 啟用 停用 選擇"

local function SearchLooksLikeControlQuestion(query)
    local normalized = NormalizeSearchText(query)
    if normalized == "" then return false end
    if normalized:find("turn on", 1, true) or normalized:find("turn off", 1, true) then return true end
    for term in SEARCH_CONTROL_QUERY_TERMS:gmatch("%S+") do
        term = NormalizeSearchText(term)
        if term ~= "" and normalized:find(term, 1, true) then return true end
    end
    return false
end

local SEARCH_GENERIC_LOCATION_QUESTION_TERMS = {
    "where", "where is", "where are", "where do", "where can", "where to",
    "how do", "how to", "how can", "wo", "wo ist", "wo sind", "wo kann", "wo finde",
    "wie", "wie kann",
}

local SEARCH_GENERIC_LOCATION_ACTION_TERMS = {
    "change", "changed", "changing", "configure", "customize", "customise", "edit",
    "find", "set", "select", "choose", "adjust", "move", "resize", "enable",
    "disable", "show", "hide", "turn on", "turn off", "aendern", "aendere", "andern",
    "einstellen", "finden", "auswaehlen", "verschieben",
    "aktivieren", "deaktivieren", "anzeigen", "ausblenden",
}

local SEARCH_CONTROL_KINDS = {
    toggle = true,
    dropdown = true,
    segment = true,
    slider = true,
    color = true,
    button = true,
    textinput = true,
}

local function SearchContainsTerm(normalized, term)
    normalized = tostring(normalized or "")
    term = NormalizeSearchText(term)
    if normalized == "" or term == "" then return false end
    if term:find(" ", 1, true) then return normalized:find(term, 1, true) ~= nil end
    return (" " .. normalized .. " "):find(" " .. term .. " ", 1, true) ~= nil
end

local function SearchContainsAnyTerm(normalized, terms)
    if type(terms) ~= "table" then return false end
    for i = 1, #terms do
        if SearchContainsTerm(normalized, terms[i]) then return true end
    end
    return false
end

local function SearchLooksLikeGenericLocationQuestion(query)
    local normalized = NormalizeSearchText(query)
    if normalized == "" then return false end
    local hasQuestion = SearchContainsAnyTerm(normalized, SEARCH_GENERIC_LOCATION_QUESTION_TERMS)
    if not hasQuestion then return false end
    if normalized:find("where is", 1, true) or normalized:find("where are", 1, true) then return true end
    if normalized:find("wo ist", 1, true) or normalized:find("wo sind", 1, true) then return true end
    return SearchContainsAnyTerm(normalized, SEARCH_GENERIC_LOCATION_ACTION_TERMS)
end

local function SearchGenericLocationSubjectClauses(query)
    if not SearchLooksLikeGenericLocationQuestion(query) then return nil, nil end
    local raw = SearchRawWords(NormalizeSearchText(query))
    if #raw == 0 then return nil, nil end
    local words = SearchCanonicalWords(raw)
    local subject = table.concat(words, " ")
    if subject == "" then return nil, nil end
    local subjectNorm, subjectClauses = BuildSearchQueryClauses(subject)
    if type(subjectClauses) ~= "table" or #subjectClauses == 0 then return nil, nil end
    return subjectNorm, subjectClauses
end

local function SearchDirectSubjectMatches(rec, clauses)
    if not rec or type(clauses) ~= "table" then return 0, 0, 0 end
    local labelText = tostring(rec.labelNorm or "") .. " " .. tostring(rec.titleNorm or "")
    local contextText = labelText .. " " .. tostring(rec.hintNorm or "") .. " " .. tostring(rec.groupNorm or "")
    local haystack = tostring(rec.haystack or "")
    local labelMatches, contextMatches, haystackMatches = 0, 0, 0
    for i = 1, #clauses do
        local terms = clauses[i] and clauses[i].terms
        local inLabel, inContext, inHaystack = false, false, false
        if type(terms) == "table" then
            for k = 1, #terms do
                local term = terms[k]
                if term and term ~= "" then
                    if labelText:find(term, 1, true) then inLabel = true end
                    if contextText:find(term, 1, true) then inContext = true end
                    if haystack:find(term, 1, true) then inHaystack = true end
                end
                if inLabel and inContext and inHaystack then break end
            end
        end
        if inLabel then labelMatches = labelMatches + 1 end
        if inContext then contextMatches = contextMatches + 1 end
        if inHaystack then haystackMatches = haystackMatches + 1 end
    end
    return labelMatches, contextMatches, haystackMatches
end

local function SearchGenericLocationBoost(rec, clauses, matchedClauses, missedClauses)
    if not rec or type(clauses) ~= "table" or #clauses == 0 then return 0 end
    local labelMatches, contextMatches, haystackMatches = SearchDirectSubjectMatches(rec, clauses)
    local direct = math.max(labelMatches, contextMatches)
    local allMatched = (tonumber(missedClauses) or 0) == 0 and (tonumber(matchedClauses) or 0) >= #clauses

    if SEARCH_CONTROL_KINDS[rec.kind or ""] then
        if labelMatches > 0 then return 860 + labelMatches * 160 end
        if contextMatches > 0 then return 640 + contextMatches * 120 end
        if allMatched then return 420 end
        return -120
    end
    if rec.kind == "section" then
        if labelMatches > 0 then return 560 + labelMatches * 120 end
        if contextMatches > 0 then return 360 + contextMatches * 80 end
        if allMatched then return 180 end
        return -80
    end
    if rec.kind == "page" then
        if direct > 0 then return 110 + direct * 45 end
        if haystackMatches > 0 then return 40 end
        return -80
    end
    if rec.kind == "faq" then
        if labelMatches >= #clauses and #clauses >= 2 then return 100 end
        if direct > 0 then return -120 end
        return -260
    end
    if direct > 0 then return 180 + direct * 60 end
    return allMatched and 80 or 0
end

local function SearchSupportQuestionBoost(rec, clauses)
    if not rec or rec.kind ~= "faq" then return 0 end
    local haystack = rec.haystack or ""
    local direct = 0
    for i = 1, #(clauses or {}) do
        local word = clauses[i].word
        if word and word ~= "" and haystack:find(word, 1, true) then
            direct = direct + 1
        end
    end
    if direct > 0 then return 160 + direct * 90 end
    return -160
end

local function SearchResultSpecificityBoost(rec, clauses)
    if not rec then return 0 end
    local clauseCount = #(clauses or {})
    if clauseCount == 0 then return 0 end

    local label = rec.labelNorm or ""
    local title = rec.titleNorm or ""
    local direct = 0
    for i = 1, clauseCount do
        local clause = clauses[i]
        local terms = clause and clause.terms
        local matched = false
        if type(terms) == "table" then
            for k = 1, #terms do
                local term = terms[k]
                if term and term ~= "" and (label:find(term, 1, true) or title:find(term, 1, true)) then
                    matched = true
                    break
                end
            end
        end
        if matched then direct = direct + 1 end
    end

    if direct == 0 then
        if rec.kind == "faq" and clauseCount >= 2 then return -90 end
        if rec.kind == "page" and clauseCount >= 3 then return -40 end
        return 0
    end

    local boost = direct * 45
    if direct == clauseCount and clauseCount >= 2 then
        if rec.kind == "page" then
            boost = boost + 90
        elseif rec.kind == "faq" then
            boost = boost + 100
        else
            boost = boost + 260
        end
    end
    return boost
end

local function IsSearchableDisplayText(text)
    text = DisplaySearchText(text)
    if text == "" or #text > SEARCH_TEXT_MAX_LEN then return false end
    local normalized = NormalizeSearchText(text)
    if normalized == "" or SEARCH_NOISE_TEXT[normalized] then return false end
    if #normalized < 2 then return false end
    return true
end

local function FontStringText(region)
    if not (region and region.GetObjectType and region:GetObjectType() == "FontString") then return nil end
    local raw = region._msuf2SearchText
    local text = raw
    if text == nil and region.GetText then text = region:GetText() end
    text = DisplaySearchText(text)
    if text == "" then return nil end
    return text
end

local function SearchValueText(item)
    if type(item) == "table" then
        return item.text or item.label or item.name or item.title or item.value or item.key
    end
    return item
end

local function AddValuesSearchText(parts, values)
    if type(values) == "function" then
        local ok, resolved = pcall(values)
        if not ok then return end
        values = resolved
    end
    if type(values) ~= "table" then return end
    local limit = math.min(#values, 32)
    for i = 1, limit do
        local item = values[i]
        AddSearchText(parts, SearchValueText(item))
        if type(item) == "table" then
            AddSearchText(parts, item.tooltip)
            AddSearchText(parts, item.desc or item.description)
        end
    end
    local extra = 0
    for key, item in pairs(values) do
        if type(key) ~= "number" or key < 1 or key > #values then
            AddSearchText(parts, key)
            AddSearchText(parts, SearchValueText(item))
            if type(item) == "table" then
                AddSearchText(parts, item.tooltip)
                AddSearchText(parts, item.desc or item.description)
            end
            extra = extra + 1
            if extra >= 12 then break end
        end
    end
end

local function SearchSectionTitle(frame)
    if not frame then return nil end
    local entry = frame._msuf2CollapsibleEntry
    if entry and entry.label then
        local text = FontStringText(entry.label)
        if IsSearchableDisplayText(text) then return text end
    end
    if frame.title then
        local text = FontStringText(frame.title)
        if IsSearchableDisplayText(text) then return text end
    end
    if IsSearchableDisplayText(frame._msuf2SearchTitle) then return DisplaySearchText(frame._msuf2SearchTitle) end
    return nil
end

local function SectionPathForAnchor(anchor, pageTitle)
    local path, seen = {}, {}
    local parent = anchor and anchor.GetParent and anchor:GetParent()
    local pageNorm = NormalizeSearchText(pageTitle or "")
    while parent do
        local title = SearchSectionTitle(parent)
        local norm = NormalizeSearchText(title or "")
        if norm ~= "" and norm ~= pageNorm and not seen[norm] then
            seen[norm] = true
            table.insert(path, 1, title)
        end
        parent = parent.GetParent and parent:GetParent() or nil
    end
    return path
end

local function SearchHint(pageInfo, anchor)
    local parts, seen = {}, {}
    local function Add(text)
        text = SearchDisplayText(text)
        local norm = NormalizeSearchText(text)
        if norm ~= "" and not seen[norm] then
            seen[norm] = true
            parts[#parts + 1] = text
        end
    end
    Add(pageInfo.group)
    Add(pageInfo.label or pageInfo.title)
    local sections = SectionPathForAnchor(anchor, pageInfo.title or pageInfo.label)
    for i = 1, #sections do Add(sections[i]) end
    return table.concat(parts, " > ")
end

local function BuildSearchPageInfos()
    local groupLabels, navInfo = {}, {}
    for i = 1, #NAV_ITEMS do
        local item = NAV_ITEMS[i]
        if item.header then groupLabels[item.id or item.header] = item.header end
    end

    local infos, seen = {}, {}
    local function AddPageInfo(key, label, group)
        if not key or key == "search" or seen[key] then return end
        seen[key] = true
        local spec = M.pages[key]
        local info = {
            key = key,
            label = M.Tr(label or (spec and spec.title) or key),
            group = group and M.Tr(group) or "",
            title = M.Tr((spec and spec.title) or label or key),
        }
        infos[#infos + 1] = info
        navInfo[key] = info
    end

    for i = 1, #NAV_ITEMS do
        local item = NAV_ITEMS[i]
        if item.key then
            AddPageInfo(item.key, item.label, item.group and groupLabels[item.group] or nil)
        end
    end
    for i = 1, #(M.pageOrder or {}) do
        local key = M.pageOrder[i]
        local spec = M.pages[key]
        AddPageInfo(key, spec and spec.title or key, nil)
    end
    return infos, navInfo
end

local function BuildSearchPageInfoForKey(pageKey)
    local spec = M.pages and M.pages[pageKey]
    local title = (spec and spec.title) or pageKey or ""
    return {
        key = pageKey,
        label = M.Tr(title),
        group = "",
        title = M.Tr(title),
    }
end

local function ClearSearchRegistryPage(pageKey)
    if not pageKey then return end
    local ids = SEARCH_STATE.registryByPage[pageKey]
    if ids then
        for i = 1, #ids do
            SEARCH_STATE.registry[ids[i]] = nil
            SEARCH_STATE.registryRecords[ids[i]] = nil
        end
        SEARCH_STATE.registryByPage[pageKey] = nil
        MarkSearchIndexDirty()
    end
end

local function CopyStaticSearchValues(values)
    if type(values) == "function" then
        local ok, resolved = pcall(values)
        if not ok then return nil end
        values = resolved
    end
    if type(values) ~= "table" then return nil end
    local out, count = {}, 0
    local limit = math.min(#values, 32)
    for i = 1, limit do
        local item = values[i]
        local text = SearchValueText(item)
        if text ~= nil then
            count = count + 1
            out[count] = text
        end
    end
    local extra = 0
    for key, item in pairs(values) do
        if type(key) ~= "number" or key < 1 or key > #values then
            count = count + 1
            out[count] = key
            local text = SearchValueText(item)
            if text ~= nil then
                count = count + 1
                out[count] = text
            end
            extra = extra + 1
            if extra >= 12 then break end
        end
    end
    return count > 0 and out or nil
end

local BuildRegistrySearchRecord

function M.RegisterSearchWidget(widget, meta)
    if not widget or type(meta) ~= "table" then return end
    EnsureSearchLocaleFresh()
    local pageKey = meta.pageKey or M._msuf2SearchBuildKey or M.activeKey
    if type(pageKey) ~= "string" or pageKey == "" or pageKey == "search" then return end

    local label = DisplaySearchText(meta.label or meta.title or meta.text or widget._msuf2SearchText or widget._msuf2SearchTitle)
    if not IsSearchableDisplayText(label) then return end

    local id = widget._msuf2SearchRegistryId
    if not id or widget._msuf2SearchRegistryPage ~= pageKey or not SEARCH_STATE.registry[id] then
        SEARCH_STATE.registrySerial = SEARCH_STATE.registrySerial + 1
        id = pageKey .. ":" .. tostring(SEARCH_STATE.registrySerial)
        widget._msuf2SearchRegistryId = id
        widget._msuf2SearchRegistryPage = pageKey
        SEARCH_STATE.registryByPage[pageKey] = SEARCH_STATE.registryByPage[pageKey] or {}
        SEARCH_STATE.registryByPage[pageKey][#SEARCH_STATE.registryByPage[pageKey] + 1] = id
    end

    local entry = {
        id = id,
        pageKey = pageKey,
        label = label,
        kind = meta.kind or widget._msuf2ControlKind or "control",
        anchor = meta.anchor or widget._msuf2Title or widget._msuf2Label or widget,
        values = CopyStaticSearchValues(meta.values or widget.values),
        keywords = meta.keywords,
        help = meta.help or meta.description,
    }
    SEARCH_STATE.registry[id] = entry
    SEARCH_STATE.registryRecords[id] = nil
    MarkSearchIndexDirty()
end

local function AddSearchRecord(records, seenRecords, pageInfo, label, anchor, kind, extraParts)
    label = DisplaySearchText(label)
    if not IsSearchableDisplayText(label) then return end

    kind = kind or "text"
    local displayLabel = SearchDisplayText(label)
    if displayLabel == "" then displayLabel = label end
    local displayHint = SearchHint(pageInfo, anchor)
    local hint = (kind == "faq") and "" or displayHint
    local parts = {}
    AddSearchText(parts, label)
    if kind ~= "faq" then
        AddSearchText(parts, hint)
        AddSearchText(parts, pageInfo.label)
        AddSearchText(parts, pageInfo.group)
        AddSearchText(parts, pageInfo.title)
    end
    if kind == "page" then
        AddRawSearchText(parts, SEARCH_KEYWORDS[pageInfo.key])
    end
    if kind == "toggle" then
        AddToggleQuestionSearchText(parts, label)
    end
    if extraParts then
        for i = 1, #extraParts do AddSearchText(parts, extraParts[i]) end
    end

    local recordId = table.concat({
        tostring(pageInfo.key or ""),
        tostring(kind or ""),
        tostring(anchor or ""),
        NormalizeSearchText(label),
        NormalizeSearchText(hint),
    }, "\031")
    if seenRecords[recordId] then return end
    seenRecords[recordId] = true

    displayHint = DisplaySearchText(displayHint)
    local displayGroup = (kind == "faq") and "" or SearchDisplayText(pageInfo.group or "")
    local displayTitle = (kind == "faq") and "" or SearchDisplayText(pageInfo.title or pageInfo.label or "")
    local labelNorm = NormalizeSearchText(displayLabel)
    local titleNorm = (kind == "faq") and "" or NormalizeSearchText(displayTitle)
    local groupNorm = (kind == "faq") and "" or NormalizeSearchText(displayGroup)
    local hintNorm = (kind == "faq") and "" or NormalizeSearchText(displayHint)
    local haystackText = table.concat(parts, " ")
    if kind ~= "faq" and kind ~= "page" and #haystackText > SEARCH_CONTROL_HAYSTACK_MAX_LEN then
        haystackText = haystackText:sub(1, SEARCH_CONTROL_HAYSTACK_MAX_LEN)
    end
    local haystackNorm = NormalizeSearchText(haystackText)
    local record = {
        key = pageInfo.key,
        label = displayLabel,
        group = displayGroup,
        title = displayTitle,
        hint = displayHint,
        kind = kind,
        anchor = anchor,
        labelNorm = labelNorm,
        groupNorm = groupNorm,
        titleNorm = titleNorm,
        hintNorm = hintNorm,
        haystack = haystackNorm,
        tokenLimit = (kind ~= "faq" and kind ~= "page")
            and SEARCH_CONTROL_MAX_TOKENS
            or SEARCH_MAX_RECORD_TOKENS,
        order = #records + 1,
    }
    records[#records + 1] = record
    return record
end

BuildRegistrySearchRecord = function(entry)
    if type(entry) ~= "table" then return nil end
    local info = BuildSearchPageInfoForKey(entry.pageKey)
    local extra = {}
    AddValuesSearchText(extra, entry.values)
    if type(entry.keywords) == "string" then
        AddSearchText(extra, entry.keywords)
    elseif type(entry.keywords) == "table" then
        for i = 1, #entry.keywords do AddSearchText(extra, entry.keywords[i]) end
    end
    AddControlQuestionSearchText(extra, entry.label, entry.kind, entry.values)
    AddSearchText(extra, entry.help)
    local tempRecords, seenRecords = {}, {}
    local rec = AddSearchRecord(tempRecords, seenRecords, info, entry.label, entry.anchor, entry.kind or "control", extra)
    if rec then
        rec.answer = entry.help
    end
    return rec
end

local SEARCH_FAQ = {
    {
        label = "Discord",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_RECOVERY_DISCORD",
        anchorText = "Display & recovery Discord Copy Discord Link support help feedback bug report",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_DISCORD_KEYWORDS, {
            [0] = false,
            "discord", "discord link", "copy discord link", "where is discord", "open discord", "support discord", "feedback discord", "report bugs discord",
        }),
        route = DASHBOARD_ROUTE_RECOVERY,
        priority = 760,
    },
    {
        label = "Display & recovery",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_RECOVERY",
        anchorText = "Display & recovery Print Help Discord Factory Reset All recovery tools reset support",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_RECOVERY_KEYWORDS, {
            [0] = false,
            "display recovery", "recovery tools", "print help", "factory reset", "fullreset", "reset all", "recover menu", "dashboard recovery",
        }),
        route = DASHBOARD_ROUTE_RECOVERY,
        priority = 760,
    },
    {
        label = "Wago profile hub",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_WAGO",
        anchorText = "Wago profile hub Browse Wago profiles Backup current profile",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_WAGO_KEYWORDS, {
            [0] = false,
            "wago profiles", "browse wago profiles", "wago profile hub", "wago link", "wago backup",
        }),
        priority = 320,
    },
    {
        label = "Support MSUF Development",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_SUPPORT",
        anchorText = "Support MSUF Development Patreon PayPal Ko-fi GitHub support links donate repository",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_SUPPORT_KEYWORDS, {
            [0] = false,
            "support links", "donate", "donation", "support development", "support msuf", "patreon", "paypal", "ko-fi", "kofi", "github", "repository",
        }),
        priority = 660,
    },
    {
        label = "Scaling",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_SCALING",
        anchorText = "Scaling UI Scale MSUF Frame Scale MSUF Menu Scale Apply Revert resize window bigger smaller",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_SCALING_KEYWORDS, {
            [0] = false,
            "scaling", "ui scale", "menu scale", "msuf frame scale", "msuf menu scale", "make menu bigger", "make menu smaller", "resize window", "options too big", "options too small",
        }),
        route = DASHBOARD_ROUTE_SCALING,
        priority = 760,
    },
    {
        label = "Changelog",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_CHANGELOG",
        anchorText = "Changelog release notes patch notes version changes beta notes",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_CHANGELOG_KEYWORDS, {
            [0] = false,
            "changelog", "change log", "release notes", "patch notes", "version notes", "what changed", "latest changes", "beta notes",
        }),
        route = DASHBOARD_ROUTE_CHANGELOG,
        priority = 760,
    },
    {
        label = "Highlight Borders",
        answer = "Open Global Style > Bars. Textures & Gradient controls shared bar textures; Frame Outline and Highlight Borders control borders.",
        pageKey = "opt_bars",
        anchorText = "Highlight Borders Border Modes Dispel border Dispel border detects Dispel glow effect Glow style Highlight Priority Aggro border Purge border Boss target border",
        keywords = SearchKeywordList(SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, {
            [0] = false,
            "where are highlight borders", "where is dispel border", "where is dispel glow", "change dispel highlight", "change aggro highlight",
            "highlight border settings", "border glow settings", "priority dispel aggro target focus",
        }),
        priority = 780,
    },
    {
        label = "MSUF Dispel Highlights",
        answer = "Blizzard mode lets WoW place the selected aura types. MSUF Custom mode lets MSUF control aura size, growth, position, filters, and styling. MSUF Dispel Highlights keep Blizzard icons while allowing MSUF's dispel border, glow, and overlay visuals.",
        pageKey = "gf_auras",
        anchorText = "Aura Display Mode Use Blizzard Dispels MSUF Dispel Highlights Border Glow Overlay Blizzard renderer native dispel icons",
        keywords = SearchKeywordList(SEARCH_BLIZZARD_DISPEL_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS, {
            [0] = false,
            "why does blizzard mode hide dispel glow", "keep blizzard debuffs but show dispel glow", "keep blizzard debuffs but show dispel overlay", "blizzard dispel icons and msuf border",
        }),
        priority = 760,
    },
    {
        label = "Dispel Overlay",
        answer = "Tints the health bar when a configured debuff condition is active.",
        pageKey = "gf_bars",
        anchorText = "Dispel Overlay Overlay detects Overlay style Show on current health only Overlay opacity health bar tint dispellable debuff any debuff",
        keywords = SearchKeywordList(SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, {
            [0] = false,
            "where is dispel overlay", "health bar changes color for dispel", "raid frame tint dispel", "party frame tint dispel", "party overlay any debuff",
        }),
        priority = 740,
    },
    {
        label = "Debuff Stripe",
        answer = "Shows a thin colored stripe for debuffs matched by the debuff filter.",
        pageKey = "gf_bars",
        anchorText = "Debuff Stripe Stripe edge Stripe height Stripe opacity debuff filter colored stripe",
        keywords = SearchKeywordList(SEARCH_DEBUFF_STRIPE_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, {
            [0] = false,
            "where is debuff stripe", "thin debuff indicator", "colored line for debuffs", "raid debuff line",
        }),
        priority = 730,
    },
    {
        label = "Why are boss frames not visible?",
        answer = "Boss frames normally appear only during boss encounters. Enable Boss Frames and use Edit Mode or Boss Preview to test them outside combat.",
        pageKey = "uf_boss",
        target = "Opens: Boss > Frame Basics / Boss Layout",
        anchorText = "Enable boss castbars Boss Layout Boss Preview Frame Basics",
        keywords = { "boss frames not visible", "boss frames hidden", "why boss not show", "warum sehe ich boss frames nicht", "bossframes weg", "boss preview", "boss frames anzeigen", "boss frames sichtbar", "boss frames show" },
        priority = 20,
    },
    {
        label = "How do I move frames?",
        answer = "Open MSUF Edit Mode, select the frame, then drag it. Use the unit page > Anchoring only for exact anchor/X/Y fine-tuning.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode move frames drag position x offset y offset",
        keywords = { "where do i move my unitframe", "how to move unitframe", "how to move a unitframe", "how do i move unitframe", "move unitframe", "move unit frame", "move frames", "drag frames", "position", "verschieben", "frames bewegen", "edit mode", "x offset", "y offset", "unitframe position", "move player unitframe", "move target unitframe", "move focus unitframe", "move pet unitframe", "move boss unitframe", "how do i move the player frame", "move player frame", "move target frame", "move focus frame", "move pet frame", "move boss frame", "drag player frame", "drag target frame", "player frame position" },
        priority = 320,
    },
    {
        label = "How do I move the player frame?",
        answer = "Use MSUF Edit Mode to drag the player frame. For exact anchor or X/Y values, open Player > Anchoring after that.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode move player frame drag player frame position x offset y offset",
        keywords = { "how do i move the player frame", "how to move player frame", "how to move player unitframe", "where do i move my player frame", "move my player frame", "move player frame", "move player unitframe", "drag player frame", "player frame position", "playerframe position", "player x y", "player anchor", "player anchoring", "spieler frame verschieben", "spieler verschieben" },
        priority = 360,
    },
    {
        label = "How do I move or anchor one unit frame?",
        answer = "Use MSUF Edit Mode to drag a single unit frame. Use the unit page > Anchoring when you need exact anchor targets or X/Y values.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode Anchoring Anchor unit to Custom anchor target Global anchor move position",
        keywords = { "unit frame anchor", "unitframe anchor", "anchor player frame", "custom anchor", "global anchor", "anchor target frame", "anchor focus frame", "unitframe position", "unit frame position", "player frame position", "move player frame", "move target frame", "move focus frame", "move unitframe", "player x y", "target x y" },
        priority = 160,
    },
    {
        label = "How do I move party or raid frames?",
        answer = "Open Group Frames > Layout. Use Layout, Frame Scaling, and Anchoring for party/raid position, growth, spacing, size, and anchor behavior.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > Anchoring",
        anchorText = "Anchoring Layout Frame Scaling growth direction spacing columns position move party raid",
        keywords = { "move raid frames", "move party frames", "move group frames", "raidframes position", "partyframes position", "groupframes position", "group frame anchor", "raid frame anchor", "party frame anchor", "gruppe verschieben", "raid verschieben" },
        priority = 55,
    },
    {
        label = "How do I resize a unit frame?",
        answer = "Open that unit page and use Frame Basics for width, height, and scale. Text size is in Global Style > Fonts or the unit Text section.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics",
        anchorText = "Frame Basics width height scale size player target focus boss pet",
        keywords = { "resize unitframe", "resize unit frame", "make frame bigger", "make player frame bigger", "make target frame smaller", "width height scale", "unitframe size", "frame size", "frames too big", "frames too small" },
        priority = 40,
    },
    {
        label = "How do I resize party or raid frames?",
        answer = "Open Group Frames > Layout. General/Layout controls frame width, height, spacing, columns, and growth; Frame Scaling controls scale behavior.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout",
        anchorText = "General Layout Frame Scaling width height spacing columns growth scale",
        keywords = { "resize raid frames", "resize party frames", "resize group frames", "raid frame size", "party frame size", "group frame size", "raid frames too big", "party frames too small", "group scale" },
        priority = 45,
    },
    {
        label = "How do I change portraits?",
        answer = "Open the unit page, then use the Portrait section for mode, render type, shape, size, offset, and border.",
        pageKey = "uf_player",
        target = "Opens: Player > Portrait",
        anchorText = "Portrait mode render type shape size offset class icon portrait background",
        keywords = { "portrait", "portraits", "avatar", "face", "bild", "portraet", "portrait mode", "portrait shape", "class icon", "2d portrait", "3d portrait", "portrait background" },
        priority = 15,
    },
    {
        label = "How do I change castbars?",
        answer = "Use the unit page for per-unit castbar toggles and Global Style > Castbar for shared textures, direction, GCD, text, and interrupt options.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar",
        anchorText = "Castbar Textures & Outline GCD Bar Focus Kick Interrupt Ready Indicator",
        keywords = { "castbar", "cast bar", "gcd", "interrupt", "focus kick", "channel ticks", "zauberleiste", "castbar texture", "castbar direction", "spell name" },
        priority = 20,
    },
    {
        label = "Where are Evoker empowered cast settings?",
        answer = "Open Global Style > Castbar and use Empowered Casts for Evoker stage color, stage blink, and blink timing.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > Empowered Casts",
        anchorText = "Empowered Casts Evoker stage blink empower hold release",
        keywords = { "evoker castbar", "evoker cast bar", "empowered casts", "empower", "empower stage", "stage blink", "hold cast", "release cast", "augmentation", "devastation", "preservation", "quell" },
        priority = 180,
    },
    {
        label = "Where are Demon Hunter interrupt and castbar settings?",
        answer = "Open Global Style > Castbar for Focus Kick and Interrupt Ready Indicator. Per-unit castbar interrupt toggles are on each unit page.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > Interrupt Ready Indicator",
        anchorText = "Interrupt Ready Indicator Focus Kick Demon Hunter devour consume magic disrupt kick",
        keywords = { "devour demonhunter castbar", "devour demon hunter castbar", "dh castbar", "demon hunter interrupt", "demonhunter interrupt", "havoc kick", "vengeance kick", "consume magic", "disrupt", "interrupt ready", "focus kick", "kick cooldown" },
        priority = 180,
    },
    {
        label = "How do I make missing health white in Dark Mode?",
        answer = "Set Bar Background Tint to white and enable Custom color in Dark Mode. If black, enable Preserve HP color on all unit frames.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Bar Background Tint > Preserve HP color on all unit frames",
        anchorText = "Bar Background Tint Custom color in Dark Mode Preserve HP color missing health white background",
        keywords = {
            "is there a way to change the background color of unit frames",
            "change background color unit frames",
            "unit frame background color",
            "missing health white",
            "missing hp white",
            "dark mode white background",
            "custom color in dark mode",
            "bar background tint white",
            "singular global color",
            "background color dark mode",
            "preserve hp color",
            "hp track black",
            "target frame background black",
            "empty health area black",
            "backgroud color",
            "backgrond color",
            "backround color",
            "bg color white",
            "hintergrund weiss",
        },
        priority = 340,
    },
    {
        label = "How do I change my background?",
        answer = "For bar backgrounds: Bar Background Tint. White in Dark Mode needs Custom color in Dark Mode; black track? check Preserve HP color.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Bar Background Tint",
        anchorText = "Bar Background Tint Custom color in Dark Mode background backgrond backround bg backdrop opacity alpha",
        keywords = { "how do i change my backgrond", "how do i change my background", "change background", "change backgrond", "backround", "backgroud", "background color", "bar background", "background tint", "bg color", "backdrop", "opacity", "alpha", "transparent background", "hintergrund", "custom color in dark mode", "missing health white", "dark mode background", "preserve hp color", "hp track black" },
        priority = 70,
    },
    {
        label = "How do I make unit frames transparent?",
        answer = "Open the unit page > Transparency for in-combat/out-of-combat alpha. By default the sliders fade the whole frame; Keep text + portrait visible switches them to the selected layer: Bars, HP Bar, or Backdrop. Group frame transparency is in Group Frames > Layout > Transparency.",
        pageKey = "uf_player",
        target = "Opens: Player > Transparency",
        anchorText = "Transparency alpha in combat out of combat opacity whole frame layer fade bars hp bar backdrop preserve hp color keep text portrait visible",
        keywords = { "transparent unitframe", "transparent unit frame", "alpha unitframe", "opacity unitframe", "fade frame", "frame alpha", "whole frame alpha", "in combat alpha", "out of combat alpha", "transparent player frame", "transparent target frame", "hp bar alpha", "health bar alpha", "bars alpha", "backdrop alpha", "keep text portrait visible" },
        priority = 40,
    },
    {
        label = "How do I change bar textures, gradients, or outlines?",
        answer = "Open Global Style > Bars. Textures & Gradient controls shared bar textures; Frame Outline and Highlight Borders control borders.",
        pageKey = "opt_bars",
        target = "Opens: Global Style > Bars > Textures & Gradient",
        anchorText = "Textures & Gradient Frame Outline Highlight Borders texture gradient outline border",
        keywords = { "bar texture", "health texture", "power texture", "change texture", "gradient", "outline", "border", "bar border", "frame outline", "highlight border", "shared texture" },
        priority = 560,
    },
    {
        label = "How do I enable or disable rounded frames?",
        answer = "Open Global Style > Bars > Rounded Texture. Use the master toggle for all rounded frame textures, or the separate toggles for unit frames, group frames, power bars, and mouseover highlights.",
        pageKey = "opt_bars",
        target = "Opens: Global Style > Bars > Rounded Texture",
        anchorText = "Rounded Texture Rounded frame texture Unit frames Group frames Power bars Mouseover highlights rounded frames round corners",
        keywords = {
            "rounded frames", "rounded frame texture", "rounded texture", "round frames", "round corners", "rounded corners", "frame corners",
            "enable rounded frames", "disable rounded frames", "turn on rounded frames", "turn off rounded frames", "rounded frames on", "rounded frames off",
            "rounded unit frames", "rounded unitframes", "rounded group frames", "rounded power bars", "rounded mouseover", "rounded mouseover highlights",
            "abgerundete frames", "abgerundete unitframes", "runde kanten", "runde ecken", "abrundung", "abrunden", "rounded frames einschalten", "rounded frames ausschalten",
            "abgerundete frames einschalten", "abgerundete frames ausschalten", "runde kanten einschalten", "runde kanten ausschalten", "mouseover abgerundet", "powerbar abgerundet",
        },
        priority = 620,
    },
    {
        label = "Where is Smooth fill for unit frames?",
        answer = "Open the unit page, then use Frame Basics > Smooth fill for the health bar. For that unit's power bar animation, open Power Bar > Smooth fill.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics > Smooth fill",
        anchorText = "Frame Basics Smooth fill Power Bar Smooth fill health animation power animation soft fill weiche Fuellung",
        keywords = {
            "smooth fill", "smooth health fill", "smooth power bar", "soft fill", "fluid fill", "bar animation", "health bar animation", "power bar animation",
            "where is smooth fill", "find smooth fill", "option der weichen fuellung finden", "weiche fuellung", "weichen fuellung", "sanfte fuellung", "fluessige fuellung", "balken animation", "lebensbalken animation", "powerbar animation",
            "relleno suave", "llenado suave", "animacion de barra", "remplissage doux", "remplissage fluide", "animation de barre", "riempimento fluido", "riempimento morbido", "preenchimento suave", "animacao da barra",
            "плавное заполнение", "плавная заливка", "анимация полосы", "부드러운 채우기", "막대 애니메이션", "平滑填充", "柔和填充", "条动画", "條動畫", "平滑填充", "柔和填充",
        },
        priority = 360,
    },
    {
        label = "Where is Smooth fill for party or raid frames?",
        answer = "Open Group Frames > Layout for Smooth health fill. For group-frame power bars, open Group Frames > Health & Text > Power Bar > Smooth fill.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > Smooth health fill",
        anchorText = "Group Frames Layout Smooth health fill Health Text Power Bar Smooth fill party raid weiche Fuellung",
        keywords = {
            "group smooth fill", "party smooth fill", "raid smooth fill", "group frame smooth fill", "smooth health fill group frames", "smooth fill party raid", "party power smooth fill", "raid power smooth fill",
            "gruppen weiche fuellung", "gruppenrahmen weiche fuellung", "party weiche fuellung", "raid weiche fuellung", "weiche fuellung gruppe", "sanfte fuellung gruppe",
            "relleno suave grupo", "relleno suave banda", "remplissage fluide groupe", "remplissage fluide raid", "riempimento fluido gruppo", "preenchimento suave grupo",
            "плавное заполнение группы", "плавное заполнение рейда", "그룹 부드러운 채우기", "레이드 부드러운 채우기", "团队 平滑填充", "小队 平滑填充", "团队平滑填充", "小队平滑填充", "團隊 平滑填充", "隊伍 平滑填充", "團隊平滑填充", "隊伍平滑填充",
        },
        priority = 330,
    },
    {
        label = "How do I change health, power, or class colors?",
        answer = "Open Global Style > Colors. Bar Colors and Power Bar Colors control HP/power colors; Class Bar Colors controls class overrides.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Bar Colors",
        anchorText = "Bar Colors Power Bar Colors Class Bar Colors health hp power class color",
        keywords = { "health color", "hp color", "power color", "mana color", "class color", "bar color", "reaction color", "npc color", "color by class", "farbe", "farben" },
        priority = 35,
    },
    {
        label = "How do I change colors?",
        answer = "Most shared colors are in Global Style > Colors. Bar texture and border style controls are in Global Style > Bars.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors",
        anchorText = "Colors Bar Background Tint Bar Colors Unitframe Colors Class Bar Colors",
        keywords = { "colors", "colours", "farbe", "farben", "class color", "reaction color", "bar color", "background color", "unitframe colors" },
        priority = 10,
    },
    {
        label = "How do I change fonts and text?",
        answer = "Global Style > Fonts controls shared font settings. Unit pages contain per-unit name, health, and power text position and pattern settings.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts",
        anchorText = "Global Font Text Style Name & Power Colors Name Shortening font size outline shadow",
        keywords = { "font", "fonts", "text", "schrift", "name text", "hp text", "health text", "power text", "text size", "font size", "outline", "shadow", "name shortening", "make text bigger", "text too small" },
        priority = 25,
    },
    {
        label = "Where do I change HP, name, or power text position?",
        answer = "Open the unit page and use Text for name/health/power text patterns, anchors, offsets, font sizes, and layering.",
        pageKey = "uf_player",
        target = "Opens: Player > Text",
        anchorText = "Text name health power text anchor offset font size layer hp pattern",
        keywords = { "hp text position", "health text position", "name position", "power text position", "move text", "text anchor", "text offset", "name text", "health pattern", "power pattern", "percent hp" },
        priority = 35,
    },
    {
        label = "Where is the player, target, or unit level text?",
        answer = "Open the unit page > Status icons. Select Level in Indicator, then use Enabled, Anchor, X/Y Offset, Size, and Layer.",
        pageKey = "uf_player",
        target = "Opens: Player > Status icons > Indicator: Level",
        anchorText = "Status icons Indicator Level Enabled Anchor X Offset Y Offset Size Layer level text level indicator show level player level target level",
        keywords = { "level text", "level indicator", "player level", "target level", "unit level", "show level", "enable level", "disable level", "turn on level", "turn off level", "level anchor", "level position", "level positioning", "level x offset", "level y offset", "level size", "level layer", "status icons level", "status indicator level" },
        priority = 520,
    },
    {
        label = "How do I import, export, or switch profiles?",
        answer = "Open Profiles for active profile, spec auto-switching, import/export strings, legacy imports, and reset options.",
        pageKey = "profiles",
        target = "Opens: Profiles > Export / Import",
        anchorText = "Export / Import Profile Management Spec Profiles import export wago string",
        keywords = { "profile", "profiles", "import", "export", "wago", "copy profile", "reset profile", "profil", "spec profile", "profile string", "import string", "export string", "share profile" },
        priority = 35,
    },
    {
        label = "How do I reset positions or recover a broken layout?",
        answer = "Use Dashboard > Reset Positions for frame movers. Use Profiles only when you want to reset, copy, import, or replace profile data.",
        pageKey = "home",
        target = "Opens: Dashboard > Reset Positions",
        anchorText = "Reset Positions Factory Reset Profiles Print Help recovery support",
        keywords = { "reset positions", "reset movers", "frames off screen", "frame offscreen", "broken layout", "recover layout", "factory reset", "fullreset", "help reset", "position reset" },
        priority = 45,
    },
    {
        label = "How do I configure group frames?",
        answer = "Use Group Frames pages: Layout for size/growth/sorting, Health & Text for bars/text, Buffs & Debuffs for auras, and Indicators for status icons.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout",
        anchorText = "Group Frames Layout Health & Text Buffs & Debuffs Indicators party raid growth sorting",
        keywords = { "group frames", "groupframes", "party", "raid", "mythic raid", "gruppe", "raid frames", "layout", "growth", "sorting", "raidframes", "partyframes" },
        priority = 20,
    },
    {
        label = "How do I configure buffs and debuffs?",
        answer = "Unit Auras controls unitframe auras. Group Buffs & Debuffs controls group-frame aura layout, filtering, cooldowns, and private auras.",
        pageKey = "auras2",
        target = "Opens: Global Style > Unit Auras",
        anchorText = "Unit Auras Display Caps & Icons Aura Filters & Sorting Private Auras buffs debuffs",
        keywords = SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, {
            [0] = false,
            "buff", "buffs", "debuff", "debuffs", "auras", "aura", "private aura", "cooldown", "filter", "only my buffs", "only my debuffs", "hide buffs", "show debuffs", "aura size", "aura position",
        }),
        priority = 120,
    },
    {
        label = "Can MSUF hide debuffs with a blacklist?",
        answer = "Open Unit Auras > Global Ignore List. It can hide predefined aura categories for all unit frames, or per unit after enabling Override for this unit. MSUF does not currently have an ElvUI-style freeform spell-ID blacklist for arbitrary debuffs.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Global Ignore List",
        anchorText = "Global Ignore List Override for this unit blacklist black list ignore list hide debuffs hide buffs hidden proc BL ElvUI Emlui",
        keywords = SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, {
            [0] = false,
            "debuff blacklist",
            "debuff black list",
            "aura blacklist",
            "aura black list",
            "buff blacklist",
            "buff black list",
            "blacklist debuffs",
            "black list debuffs",
            "midnight simple unit frame",
            "midnight simple unit frames",
            "midnight simple unitframe",
            "midnight simple unitframes",
            "MSUF unitframe",
            "MSUF unit frames",
            "hide specific debuff",
            "hide specific debuffs",
            "hide a debuff",
            "icon for debuff",
            "hide debuff proc",
            "hide proc",
            "hidden proc",
            "proc hidden",
            "BL hidden proc",
            "BL debuff",
            "top right BL",
            "top right screenshot",
            "ElvUI debuff blacklist",
            "ElvUI blacklist",
            "Emlui debuff blacklist",
            "can MSUF do same",
            "ignore debuffs",
            "ignore aura",
            "ignore list",
            "global ignore list",
            "debuff ausblenden",
            "debuff verstecken",
            "aura ignorieren",
            "schwaechungszauber ausblenden",
        }),
        priority = 960,
    },
    {
        label = "How do I configure group buffs, debuffs, or defensives?",
        answer = "Open Group Frames > Buffs & Debuffs. It has sections for Buffs, Debuffs, Defensives, Private Auras, cooldown style, and aura utilities.",
        pageKey = "gf_auras",
        target = "Opens: Group Frames > Buffs & Debuffs",
        anchorText = "Buffs Debuffs Defensives Private Auras Cooldown Style Aura Utilities group frames",
        keywords = SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS, {
            [0] = false,
            "raid buffs", "raid debuffs", "party buffs", "party debuffs", "group auras", "group buffs", "group debuffs", "defensives", "externals", "private aura raid", "group cooldown swipe",
        }),
        priority = 210,
    },
    {
        label = "How do I add or change status icons and indicators?",
        answer = "Unit frame status icons are on each unit page. Group frame indicators are in Group Frames > Indicators.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators",
        anchorText = "Indicators Status Icons Spell Indicators Corner Indicators role icon dispel aggro raid marker",
        keywords = SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS, {
            [0] = false,
            "status icons", "indicator", "indicators", "corner indicator", "spell indicator", "raid marker", "role icon", "leader icon", "ready check", "aggro icon", "threat icon", "focus glow",
        }),
        priority = 190,
    },
    {
        label = "Why is something not updating immediately?",
        answer = "Some layout changes rebuild frames, while visual changes apply instantly. If needed, close and reopen the menu or reload after large profile/import changes.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Update intervals",
        anchorText = "Update intervals refresh reload apply not updating performance",
        keywords = { "not updating", "does not update", "refresh", "reload", "apply", "changes not showing", "aktualisiert nicht", "settings not applying", "profile not applying", "need reload" },
        priority = 20,
    },
    {
        label = "How do I disable Blizzard unit frames?",
        answer = "Open Global Style > Miscellaneous and use the Blizzard frame toggles.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Blizzard Frames",
        anchorText = "Blizzard Frames disable blizzard hide blizzard default frames playerframe",
        keywords = { "blizzard frames", "disable blizzard", "hide blizzard", "playerframe", "default frames", "standard frames", "hide default frames", "disable default unit frames", "blizzard player frame" },
        priority = 35,
    },
    {
        label = "Where is the minimap icon setting?",
        answer = "Open Global Style > Miscellaneous > Blizzard Frames and use Show MSUF minimap icon.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Blizzard Frames",
        anchorText = "Blizzard Frames Show MSUF minimap icon minimap button addon compartment",
        keywords = { "minimap", "minimap icon", "minimap button", "hide minimap icon", "show minimap icon", "addon compartment", "minikarte", "minimap symbol" },
        priority = 185,
    },
    {
        label = "Where are target sound settings?",
        answer = "Open Global Style > Miscellaneous > Blizzard Frames and use Play sound on Target/Target Lost.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Blizzard Frames",
        anchorText = "Blizzard Frames Play sound on Target Target Lost target sounds",
        keywords = { "target sound", "target sounds", "target lost sound", "play sound", "sound on target", "sound target lost", "ziel sound", "sounds" },
        priority = 170,
    },
    {
        label = "Where are menu snap or menu behavior settings?",
        answer = "Open Global Style > Miscellaneous > Menu behavior for edge snap and related menu behavior.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Menu behavior",
        anchorText = "Menu behavior edge snap windows snap menu resize ui scale menu scale",
        keywords = { "menu snap", "edge snap", "window snap", "menu behavior", "menu resize", "menu scale", "ui scale", "menu too big", "menu too small", "fenster einrasten" },
        priority = 65,
    },
    {
        label = "Where is Miscellaneous?",
        answer = "Open Global Style > Miscellaneous for language, menu behavior, update intervals, tooltips, Blizzard frames, minimap icon, sounds, and range fade.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous",
        anchorText = "Miscellaneous misc global style language menu behavior update intervals tooltips blizzard frames minimap sounds range fade",
        keywords = { "misc", "miscellaneous", "where is misc", "where is miscellaneous", "global style misc", "global style miscellaneous", "verschiedenes", "allgemein", "sonstiges" },
        priority = 260,
    },
    {
        label = "How do I change range fading?",
        answer = "Open Global Style > Miscellaneous and use the Range Fade section for affected units, alpha, and portrait fading.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Range Fade",
        anchorText = "Range Fade unit frame range check range checker distance check out of range range alpha distance fade portrait fading",
        keywords = { "range fade", "range check", "range checker", "unit frame range check", "distance check", "out of range", "range alpha", "distance fade", "reichweite", "reichweitencheck", "entfernung", "fade portrait", "frame fades", "out of range opacity" },
        priority = 45,
    },
    {
        label = "Where is the unit frame range check?",
        answer = "Open Global Style > Miscellaneous > Range Fade. It controls target, focus, and boss out-of-range fading; group range fade is in Group Frames > Health & Text.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Range Fade",
        anchorText = "Range Fade unit frame range check range checker distance check out of range alpha target focus boss",
        keywords = { "unit frame range check", "unitframe range check", "unit frames range check", "range check unitframe", "range check unit frame", "range checker", "distance check", "distance checker", "out of range unit frame", "out of range frames", "target out of range", "focus out of range", "boss out of range", "target range fade", "focus range fade", "boss range fade", "reichweitencheck", "reichweite check", "entfernung check" },
        priority = 165,
    },
    {
        label = "How do I change language or translations?",
        answer = "Open Global Style > Miscellaneous > Language. Translation coverage can also be checked with the /msuf locale command.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Language",
        anchorText = "Language locale localization translation deDE ruRU frFR esES",
        keywords = { "language", "locale", "translation", "translations", "localization", "localisation", "sprache", "deutsch", "english", "russian", "french", "spanish" },
        priority = 25,
    },
    {
        label = "How do I change unitframe tooltips?",
        answer = "Open Global Style > Miscellaneous > Unitframe tooltips to control mouseover tooltip behavior.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Unitframe tooltips",
        anchorText = "Unitframe tooltips tooltip mouseover hide tooltip show tooltip",
        keywords = { "tooltip", "tooltips", "unit tooltip", "mouseover tooltip", "hide tooltip", "show tooltip", "tooltip on mouseover" },
        priority = 20,
    },
    {
        label = "How do I change click, mouseover, or targeting behavior?",
        answer = "Open Gameplay for crosshair, click-cast, focus/target modifier, mouseover, interaction, and targeting options.",
        pageKey = "gameplay",
        target = "Opens: Gameplay",
        anchorText = "Gameplay click cast focus target modifier mouseover interaction targeting combat crosshair",
        keywords = { "click cast", "clickcast", "click casting", "clickthrough", "click-through", "mouseover", "target modifier", "focus modifier", "mouse buttons", "targeting", "combat crosshair" },
        priority = 30,
    },
    {
        label = "How do I change class resources?",
        answer = "Open Class Resources for combo points, holy power, soul shards, chi, maelstrom, essence, runes, stagger, detached power, and alternative mana.",
        pageKey = "classpower",
        target = "Opens: Class Resources",
        anchorText = "Class Resources Layout Behavior Style Auto-Hide Detached Power Bar Alternative Mana",
        keywords = { "class resource", "class resources", "combo points", "holy power", "soul shards", "chi", "maelstrom", "essence", "runes", "stagger", "alternative mana", "alt mana", "detached power" },
        priority = 25,
    },
    {
        label = "How do I hide or show a unit frame?",
        answer = "Open that unit page and use Frame Basics > Enable. Boss frames also have Boss Layout options.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics",
        anchorText = "Frame Basics Enable hide show player target focus boss pet",
        keywords = { "hide unitframe", "show unitframe", "disable unitframe", "enable unitframe", "hide player frame", "hide target frame", "hide focus frame", "hide pet frame", "show player frame", "enable target frame", "disable boss frame" },
        priority = 30,
    },
    {
        label = "Where are load conditions?",
        answer = "Open the matching unit page and use Load Conditions to control when player, target, focus, boss, or pet frames are shown.",
        pageKey = "uf_player",
        target = "Opens: Player > Load Conditions",
        anchorText = "Load Conditions show hide visibility player target focus boss pet combat group instance",
        keywords = { "load conditions", "visibility conditions", "show conditions", "hide conditions", "when to show frame", "when to hide frame", "frame visibility", "combat visibility", "instance visibility", "ladebedingungen", "sichtbarkeit" },
        priority = 80,
    },
    {
        label = "Why is my player, target, focus, or pet frame gone?",
        answer = "Open the matching unit page and check Frame Basics > Enable, Load Conditions, alpha/transparency, and range fade.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics",
        anchorText = "Frame Basics Enable Load Conditions Transparency Range Fade player target focus pet gone missing invisible",
        keywords = { "player frame gone", "target frame gone", "focus frame gone", "pet frame gone", "unitframe missing", "unitframe invisible", "frame not visible", "frame disappeared", "cannot see player frame", "target not showing", "focus not showing", "pet not showing", "unitframe hidden" },
        priority = 55,
    },
    {
        label = "Where is Target of Target?",
        answer = "Open Target of Target. Use Frame Basics to enable it, Text for labels, and Anchoring/Edit Mode for placement.",
        pageKey = "uf_targettarget",
        target = "Opens: Target of Target > Frame Basics",
        anchorText = "Frame Basics Target of Target ToT Enable Text Anchoring",
        keywords = { "target of target", "tot", "targettarget", "target target", "where is tot", "tot missing", "show target of target", "enable tot", "target of target frame" },
        priority = 45,
    },
    {
        label = "Where is Focus Target?",
        answer = "Open Focus Target. Use Frame Basics to enable it; it only appears when Focus is enabled and your focus has a target.",
        pageKey = "uf_focustarget",
        target = "Opens: Focus Target > Frame Basics",
        anchorText = "Frame Basics Focus Target Enable Text Anchoring",
        keywords = { "focus target", "focustarget", "focus target frame", "ft frame", "where is focus target", "focus target missing", "show focus target", "enable focus target" },
        priority = 45,
    },
    {
        label = "Why is my castbar not showing?",
        answer = "Open the unit page > Castbar to enable that unit's castbar. Shared castbar visuals are in Global Style > Castbar.",
        pageKey = "uf_player",
        target = "Opens: Player > Castbar",
        anchorText = "Castbar Enable player target focus boss pet show interrupt icon text",
        keywords = { "castbar not showing", "castbar missing", "player castbar gone", "target castbar missing", "focus castbar missing", "boss castbar missing", "show castbar", "enable castbar", "my castbar disappeared", "no cast bar" },
        priority = 55,
    },
    {
        label = "Where is the GCD bar?",
        answer = "Open Global Style > Castbar > GCD Bar. It controls instant-cast GCD display, time text, spell name, and icon.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > GCD Bar",
        anchorText = "GCD Bar instant casts show time text spell name icon",
        keywords = { "gcd", "gcd bar", "global cooldown", "instant casts", "show gcd", "gcd timer", "gcd spell", "gcd icon" },
        priority = 130,
    },
    {
        label = "Where do I change castbar spell names or long cast text?",
        answer = "Open Global Style > Castbar > Name Shortening for castbar spell name shortening, max length, and reserved space.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > Name Shortening",
        anchorText = "Name Shortening spell name max name length reserved space castbar",
        keywords = { "cast name too long", "spell name too long", "castbar text too long", "shorten castbar name", "castbar spell name", "max name length", "reserved space", "cast text overlap" },
        priority = 45,
    },
    {
        label = "Why are class resources missing?",
        answer = "Open Class Resources. Check Enable, Auto-Hide, class-specific behavior, detached power, and alternative mana settings.",
        pageKey = "classpower",
        target = "Opens: Class Resources > Layout / Auto-Hide",
        anchorText = "Class Resources Enable Auto-Hide Behavior Detached Power Bar Alternative Mana",
        keywords = { "class resources missing", "combo points missing", "holy power missing", "soul shards missing", "chi missing", "maelstrom missing", "essence missing", "runes missing", "stagger missing", "class power not showing", "resource bar missing" },
        priority = 55,
    },
    {
        label = "Where do I configure detached power or alternative mana?",
        answer = "Open Class Resources for global class-resource bars. Per-unit detached power options are in the unit page > Power Bar.",
        pageKey = "classpower",
        target = "Opens: Class Resources > Detached Power Bar",
        anchorText = "Detached Power Bar Alternative Mana Power Bar class resources sync width anchor",
        keywords = { "detached power", "detached power bar", "alternative mana", "alt mana", "dual resource", "power bar detached", "anchor to class resource", "sync width to class resource" },
        priority = 45,
    },
    {
        label = "Why are my buffs or debuffs missing?",
        answer = "Open Unit Auras. Check Display, Aura Filters & Sorting, Only Mine, boss aura filters, dispellable filters, and icon caps.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Aura Filters & Sorting",
        anchorText = "Aura Filters & Sorting Display Only my buffs Only my debuffs Show Debuffs Include boss buffs dispellable",
        keywords = SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS, {
            [0] = false,
            "buffs missing", "debuffs missing", "auras missing", "buff not showing", "debuff not showing", "hide buffs", "show debuffs", "only my buffs", "only my debuffs", "boss aura missing", "dispellable debuff missing", "aura filter",
        }),
        priority = 180,
    },
    {
        label = "Why do I have too many buffs or debuffs?",
        answer = "Open Unit Auras > Caps & Icons. Lower max buffs/debuffs, rows, icon size, and adjust filters.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Caps & Icons",
        anchorText = "Caps & Icons Max Buffs Max Debuffs Icon size rows spacing filters",
        keywords = { "too many buffs", "too many debuffs", "too many auras", "aura spam", "buff spam", "debuff spam", "max buffs", "max debuffs", "aura cap", "icon size", "aura rows" },
        priority = 55,
    },
    {
        label = "How do I turn off player buffs only?",
        answer = "Open Unit Auras, select Player, enable Custom caps, then set Caps & Icons > Max Buffs to 0. Show Buffs is a shared master toggle, so it is locked outside Shared.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Player > Custom caps > Caps & Icons > Max Buffs",
        anchorText = "Unit Auras Player Custom caps Display Show Buffs greyed out locked Caps & Icons Max Buffs set to 0 hide player buffs only",
        keywords = {
            "how do i turn off player buffs only its greyed out when editing player auras",
            "how do i turn off player buffs only",
            "player buffs greyed out",
            "player buffs grayed out",
            "show buffs greyed out player auras",
            "show buffs grayed out player auras",
            "turn off buffs only player",
            "disable player buffs only",
            "hide player buffs only",
            "remove player buffs only",
            "player aura buffs disabled",
            "player auras show buffs locked",
            "custom caps max buffs 0 player",
            "max buffs 0 player",
            "buffs nur beim spieler ausblenden",
            "spieler buffs ausblenden",
            "spieler buffs deaktivieren",
            "spieler buffs ausgegraut",
            "spieler auren buffs ausgegraut",
            "show buffs spieler ausgegraut",
            "max buffs 0 spieler",
            "desactivar buffs jugador",
            "ocultar buffs jugador",
            "buffs jugador gris",
            "auras jugador buffs gris",
            "desactiver buffs joueur",
            "masquer buffs joueur",
            "buffs joueur grise",
            "auras joueur buffs grise",
            "disattivare buff giocatore",
            "nascondere buff giocatore",
            "buff giocatore grigio",
            "desativar buffs jogador",
            "ocultar buffs jogador",
            "buffs jogador cinza",
            "как отключить баффы игрока",
            "баффы игрока серые",
            "ауры игрока баффы серые",
            "플레이어 버프 끄기",
            "플레이어 버프 비활성화",
            "플레이어 오라 버프 회색",
            "关闭玩家增益",
            "玩家增益灰色",
            "玩家光环增益灰色",
            "關閉玩家增益",
            "玩家增益灰色",
            "玩家光環增益灰色",
        },
        priority = 720,
    },
    {
        label = "Where are private auras?",
        answer = "Unit private aura controls are in Unit Auras > Private Auras. Group-frame private auras are in Group Frames > Buffs & Debuffs > Private Auras.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Private Auras",
        anchorText = "Private Auras Unit Auras Group Buffs Debuffs raid mechanics",
        keywords = { "private auras", "private aura", "raid private aura", "private aura missing", "show private aura", "private aura icon", "private auras group frames" },
        priority = 45,
    },
    {
        label = "Where do I change aura cooldown text?",
        answer = "Open Unit Auras > Text Coloring for timer colors and text sizes. Group aura cooldown style is in Group Frames > Buffs & Debuffs > Cooldown Style.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Text Coloring",
        anchorText = "Text Coloring Cooldown Timer Text cooldown text size safe warning urgent stack count",
        keywords = { "aura cooldown text", "aura cooldown text too small", "aura timer too small", "buff timer", "debuff timer", "cooldown text size", "stack text size", "timer color", "aura timer color", "cooldown swipe", "pandemic color" },
        priority = 150,
    },
    {
        label = "Where do I change group health text or power bars?",
        answer = "Open Group Frames > Health & Text. It controls health colors, bars, power bar, text, dispel overlay, debuff stripe, and range fade. Heal prediction is in Global Style > Bars > Absorb Display.",
        pageKey = "gf_bars",
        target = "Opens: Group Frames > Health & Text",
        anchorText = "Health Colors Bars Power Bar Text Dispel Overlay Debuff Stripe Range Fade group range check raid range check party range check",
        keywords = SearchKeywordList(SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DEBUFF_STRIPE_KEYWORDS, {
            [0] = false,
            "group health text", "raid health text", "party health text", "group power bar", "raid power bar", "party power bar", "heal prediction", "incoming heals", "dispel overlay", "debuff stripe", "group range fade", "group range check", "raid range check", "party range check", "raid out of range", "party out of range", "range check raid frames",
        }),
        priority = 180,
    },
    {
        label = "Where is party or raid range check?",
        answer = "Open Group Frames > Health & Text > Range Fade. That controls party and raid out-of-range fading.",
        pageKey = "gf_bars",
        target = "Opens: Group Frames > Health & Text > Range Fade",
        anchorText = "Range Fade group frame range check raid range check party range check out of range alpha",
        keywords = { "group range check", "group frame range check", "group frames range check", "raid range check", "raid frame range check", "raid frames range check", "party range check", "party frame range check", "party frames range check", "raid out of range", "party out of range", "group out of range", "range check raid frames", "range check party frames" },
        priority = 140,
    },
    {
        label = "Where are absorb bars or heal prediction?",
        answer = "Absorb styling and heal prediction are in Global Style > Bars > Absorb Display. Use the Party or Raid scope there for group incoming heals.",
        pageKey = "opt_bars",
        target = "Opens: Global Style > Bars > Absorb Display",
        anchorText = "Absorb Display Heal Prediction incoming heals absorb health group frames",
        keywords = { "absorb", "absorbs", "absorb bar", "absorb texture", "heal prediction", "incoming heals", "healing prediction", "shields", "shield bar", "health absorb" },
        priority = 45,
    },
    {
        label = "Where do I change aggro, threat, dispel, or raid markers?",
        answer = "Use Global Style > Bars for highlight borders and Group Frames > Indicators for role, threat, dispel, spell, corner, and raid-marker indicators.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators",
        anchorText = "Indicators Status Icons Spell Indicators Corner Indicators aggro threat dispel role icon raid marker",
        keywords = SearchKeywordList(SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, {
            [0] = false,
            "aggro", "threat", "aggro border", "threat border", "dispel indicator", "magic indicator", "curse indicator", "poison indicator", "disease indicator", "raid marker", "role icon", "ready check", "leader icon",
        }),
        priority = 220,
    },
    {
        label = "Why is text overlapping or in the wrong place?",
        answer = "Open the unit page > Text. Adjust anchors, offsets, font size, spacing, split spacing, and layer/draw order.",
        pageKey = "uf_player",
        target = "Opens: Player > Text",
        anchorText = "Text anchor offset font size layer draw order spacing split spacing overlaps bars portraits status icons",
        keywords = { "text overlap", "text overlapping", "text wrong place", "text on bar", "text on portrait", "name overlap", "hp text overlap", "power text overlap", "draw order", "text layer", "split spacing", "move text" },
        priority = 55,
    },
    {
        label = "Why is MSUF lagging or costing FPS?",
        answer = "Open Global Style > Miscellaneous > Update intervals. Also reduce aura counts/timers if aura-heavy layouts are expensive.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Update intervals",
        anchorText = "Update intervals performance lag fps auras cooldown timers filters",
        keywords = { "lag", "fps", "performance", "stutter", "slow", "too much cpu", "heavy", "optimize", "update intervals", "aura performance", "cooldown text performance", "combat performance" },
        priority = 55,
    },
    {
        label = "Why can I not change something in combat?",
        answer = "WoW blocks some protected frame changes in combat. Leave combat, then apply layout, anchoring, enable/disable, profile, or protected-frame changes.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous",
        anchorText = "combat lockdown protected frames settings in combat out of combat",
        keywords = { "combat lockdown", "cannot change in combat", "can't change in combat", "protected frame", "blocked in combat", "in combat settings", "combat error", "leave combat", "why can't i move in combat" },
        priority = 50,
    },
    {
        label = "Where did the menu window go?",
        answer = "Open MSUF again with /msuf. If frame positions are broken, use Dashboard > Reset Positions or the profile/reset tools.",
        pageKey = "home",
        target = "Opens: Dashboard > Reset Positions",
        anchorText = "Reset Positions menu window offscreen dashboard slash msuf recovery",
        keywords = { "menu gone", "menu missing", "window offscreen", "menu offscreen", "can't open menu", "cannot open menu", "lost menu", "options window gone", "reset menu position", "where is menu" },
        priority = 45,
    },
    {
        label = "Why did my profile or import look wrong?",
        answer = "Open Profiles. Check active profile, spec profiles, import/export, and legacy imports. Large imports may need a reload.",
        pageKey = "profiles",
        target = "Opens: Profiles > Profile Management / Export / Import",
        anchorText = "Profile Management Spec Profiles Export Import legacy imports active profile reload",
        keywords = { "profile wrong", "profile missing", "profile gone", "import failed", "import looks wrong", "wago import wrong", "profile not loading", "spec profile wrong", "active profile", "legacy import", "copy profile" },
        priority = 55,
    },
    {
        label = "Why are party or raid frames not showing?",
        answer = "Open Group Frames > Layout. Check enable/show behavior, player/solo visibility, layout mode, frame scaling, and anchoring.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > General",
        anchorText = "General Layout show hide player solo party raid enable frame scaling anchoring",
        keywords = { "party frames not showing", "raid frames not showing", "group frames missing", "party frames gone", "raid frames gone", "hide player solo", "show party frames", "show raid frames", "group frames invisible", "party hidden", "raid hidden" },
        priority = 60,
    },
    {
        label = "Where do I make names shorter?",
        answer = "Open Global Style > Fonts > Name Shortening for unit names. Castbar spell name shortening is in Global Style > Castbar > Name Shortening.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts > Name Shortening",
        anchorText = "Name Shortening names too long max name length castbar spell name shortening",
        keywords = { "name too long", "names too long", "shorten names", "name shortening", "long names", "cut names", "truncate names", "player name too long", "target name too long" },
        priority = 45,
    },
    {
        label = "Why are group names still shortened when name shortening is off?",
        answer = "Global Style > Fonts has Shared settings plus per-scope font overrides. If Party or Raid uses custom font settings, its Name Shortening can stay enabled even when Shared is off. Select Party/Raid in Fonts or reset the font override.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts > Name Shortening / scope override",
        anchorText = "Name Shortening Use custom settings for this scope Overrides Party Raid group frame name truncation font override shared changes",
        keywords = {
            "see image not sure whats happening here",
            "name shortening off but group names still shortened",
            "shorten names disabled but names still cut",
            "group names still shortened",
            "party names still shortened",
            "raid names still shortened",
            "group frame name truncation override",
            "group frame font override name shortening",
            "shared name shortening does not affect party raid",
            "getting confused with overrides",
            "no group frame override",
            "namen werden gekuerzt obwohl namenskuerzung aus",
            "namenskuerzung aus aber gruppennamen gekuerzt",
            "gruppenframe override namenskuerzung",
            "raid override namenskuerzung",
            "acortar nombres desactivado pero los nombres siguen acortados",
            "abreviar nombres desactivado pero nombres cortados",
            "marcos de grupo anulacion nombres",
            "sobrescritura de marcos de grupo nombres",
            "raccourcissement des noms desactive mais noms encore raccourcis",
            "noms raccourcis malgre option desactivee",
            "remplacement cadres de groupe noms",
            "abbreviazione nomi disattivata ma nomi ancora abbreviati",
            "nomi gruppo abbreviati override",
            "encurtar nomes desativado mas nomes ainda encurtados",
            "quadros de grupo substituicao nomes",
            "сокращение имен отключено но имена сокращаются",
            "сокращение имён выключено но имена сокращаются",
            "оверрайд рамок группы сокращение имен",
            "переопределение рамок группы имена",
            "이름 줄이기 꺼짐인데 이름이 줄어듦",
            "이름 줄이기 꺼짐 이름 줄어듦",
            "그룹 프레임 재정의 이름 줄이기",
            "名字缩短关闭但仍然缩短",
            "姓名缩短关闭但仍然缩短",
            "团队框架覆盖名字缩短",
            "小队框架覆盖名字缩短",
            "名字縮短關閉但仍然縮短",
            "姓名縮短關閉但仍然縮短",
            "團隊框架覆蓋名字縮短",
            "隊伍框架覆蓋名字縮短",
        },
        priority = 650,
    },
    {
        label = "Where do I make the menu bigger or smaller?",
        answer = "Use the Dashboard scale controls for menu scale or UI scale. You can also resize the MSUF2 window from its corner.",
        pageKey = "home",
        target = "Opens: Dashboard > UI Scale / Menu Scale",
        anchorText = "UI Scale Menu Scale resize window bigger smaller dashboard",
        keywords = { "menu too big", "menu too small", "make menu bigger", "make menu smaller", "ui scale", "menu scale", "resize window", "options too big", "options too small" },
        priority = 45,
    },
    {
        label = "Where do I change click-through auras?",
        answer = "Open Unit Auras > Display for click-through aura behavior. Gameplay contains click-cast and targeting behavior.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Display",
        anchorText = "Display click-through auras click through click cast gameplay targeting",
        keywords = { "clickthrough auras", "click-through auras", "click through auras", "auras block mouse", "can't click through buffs", "aura mouse", "click aura", "click cast not working", "mouse blocked by auras" },
        priority = 45,
    },
    {
        label = "Where are optional modules or style modules?",
        answer = "Open Modules > Style for optional style modules such as portrait decoration and dropdown styling.",
        pageKey = "modules",
        target = "Opens: Modules > Style",
        anchorText = "Modules Style portrait decoration dropdown style optional modules skins",
        keywords = { "modules", "optional modules", "style modules", "portrait decoration", "portrait deco", "module style", "skins" },
        priority = 70,
    },
    {
        label = "How do I show party or raid frames while solo?",
        answer = "Open Group Frames > Layout and check the solo/player visibility options. That is where MSUF controls whether party-style frames appear when you are alone.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > General",
        anchorText = "General show solo show player party raid group frames visibility",
        keywords = { "show party frames while solo", "show raid frames while solo", "solo raid frames", "solo party frames", "always show party frames", "always show raid frames", "show player solo", "show self in party", "party frames when alone", "raid frames when alone" },
        priority = 90,
    },
    {
        label = "How do I hide myself from party or raid frames?",
        answer = "Open Group Frames > Layout. The General and Sorting sections control player/self visibility and how player units are ordered in group frames.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > General",
        anchorText = "General Show player Player first in role Sorting party raid self visibility",
        keywords = { "hide myself from party", "hide player in party", "hide self in party frames", "show player in party frames", "player in raid frames", "self in party frames", "show player", "player first in role", "party contains me" },
        priority = 75,
    },
    {
        label = "How do I show only my HoTs or buffs on party frames?",
        answer = "Open Group Frames > Buffs & Debuffs. Use Buffs, custom buffs, and aura filters to prioritize your own HoTs, externals, and healer buffs.",
        pageKey = "gf_auras",
        target = "Opens: Group Frames > Buffs & Debuffs > Buffs",
        anchorText = "Buffs custom buffs own buffs only mine HoTs healer buffs externals group frames",
        keywords = { "show only my buffs party", "only my hots", "only my HoTs", "track my hots", "track my heals", "show my rejuv", "show my renew", "show my shields", "show externals", "own buffs party", "own buffs raid", "healer hots", "druid hots", "priest hots" },
        priority = 120,
    },
    {
        label = "How do I make my own buffs or debuffs bigger?",
        answer = "Open Unit Auras for unit-frame aura icon sizing and filters. For group frames, use Group Frames > Buffs & Debuffs and custom buff/debuff controls.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Caps & Icons",
        anchorText = "Caps & Icons icon size own buffs own debuffs custom buffs custom debuffs group buffs debuffs",
        keywords = { "make my buffs bigger", "make own buffs bigger", "make my debuffs bigger", "bigger own buffs", "bigger own debuffs", "my buffs bigger", "my debuffs bigger", "own aura size", "personal debuff size", "personal buff size" },
        priority = 95,
    },
    {
        label = "How do I move buff or debuff icons near a unit frame?",
        answer = "Open Unit Auras and use Display plus Caps & Icons for unit-frame aura placement. Buff/debuff icons are configured as aura layout, not moved through MSUF Edit Mode.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Display",
        anchorText = "Display Caps & Icons buffs debuffs position anchor rows spacing unit frame auras",
        keywords = { "move buffs", "move debuffs", "move buff icons", "move debuff icons", "buff icons next to unit frame", "debuff icons next to unit frame", "buffs under portrait", "debuffs under portrait", "unlock buffs debuffs", "buff debuff anchor", "anchor debuffs to buffs", "buffs on top", "debuffs on top" },
        priority = 110,
    },
    {
        label = "How do I add a specific boss debuff or custom aura?",
        answer = "Open Group Frames > Buffs & Debuffs for raid/party aura handling and Aura Utilities. Unit-frame aura filters are in Unit Auras.",
        pageKey = "gf_auras",
        target = "Opens: Group Frames > Buffs & Debuffs > Aura Utilities",
        anchorText = "Aura Utilities custom buffs custom debuffs boss debuffs spell id private auras raid debuffs",
        keywords = { "custom aura", "custom debuff", "custom buff", "boss debuff missing", "boss debuffs not showing", "raid debuff missing", "add boss debuff", "add spell id", "spell id", "spellid", "debuff stack count", "raid mechanic debuff", "healer custom auras" },
        priority = 125,
    },
    {
        label = "How do I show only dispellable debuffs?",
        answer = "Open Unit Auras for unit-frame debuff filtering. For party/raid dispels, use Group Frames > Indicators and Group Frames > Buffs & Debuffs.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators > Dispel / Status Icons",
        anchorText = "Indicators dispel magic curse poison disease debuffs debuff type border group frames",
        keywords = SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_UNIT_AURA_DISPEL_KEYWORDS, {
            [0] = false,
            "only dispellable debuffs", "dispellable debuffs", "dispel debuffs", "magic debuff", "curse debuff", "poison debuff", "disease debuff", "debuff type border", "debuff color border", "show dispels", "healer dispels",
        }),
        priority = 260,
    },
    {
        label = "How do I move or resize target, focus, or boss castbars?",
        answer = "Use MSUF Edit Mode to drag supported castbars. Per-unit castbar enable/icon/text options are on each unit page; shared castbar style is in Global Style > Castbar.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode move castbars target castbar focus castbar boss castbar player castbar resize",
        keywords = { "move target castbar", "move focus castbar", "move boss castbar", "move enemy castbar", "resize target castbar", "resize focus castbar", "target cast bar position", "focus cast bar position", "boss cast bar position", "castbar edit mode", "drag castbar" },
        priority = 115,
    },
    {
        label = "How do I stop castbars covering party or raid frames?",
        answer = "MSUF group frames do not use per-player castbars over the health frame. For MSUF castbar positioning, use MSUF Edit Mode and Global Style > Castbar.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar",
        anchorText = "Castbar position edit mode group frames party raid castbars over health",
        keywords = { "party castbar covering health", "raid castbar over frame", "castbar covers party frame", "castbar covers raid frame", "group castbar position", "party frame castbar", "raid frame castbar", "cast bars on raid frames" },
        priority = 70,
    },
    {
        label = "Why can I not unlock or drag buffs and debuffs?",
        answer = "MSUF Edit Mode moves frames and supported castbars. Aura icon placement is controlled from Unit Auras or Group Frames > Buffs & Debuffs.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Display",
        anchorText = "Display aura position buffs debuffs edit mode drag unlock frames",
        keywords = { "can't unlock buffs", "can't unlock debuffs", "cannot move buffs", "cannot move debuffs", "unlock buff frames", "unlock debuff frames", "drag buffs debuffs", "buffs not movable", "debuffs not movable", "lock frames buffs", "unlock frames buffs" },
        priority = 130,
    },
    {
        label = "How do I make raid frames cleaner for healing?",
        answer = "Use Group Frames > Layout for size and spacing, Buffs & Debuffs for aura clutter, and Indicators for fixed-position status icons.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout / Buffs & Debuffs / Indicators",
        anchorText = "Layout Buffs & Debuffs Indicators healer clean raid frames HoTs custom auras fixed positions",
        keywords = { "clean raid frames", "healer raid frames", "minimal raid frames", "declutter raid frames", "fixed hots positions", "fixed aura positions", "healer hots indicators", "raid frame indicators", "too much information raid frames", "healing frames setup" },
        priority = 100,
    },
    {
        label = "How do I change dead, offline, AFK, or ready-check indicators?",
        answer = "Open Group Frames > Indicators for status icons, role/leader/assist, ready check, focus glow, and other group-frame state indicators.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators > Status Icons",
        anchorText = "Status Icons ready check dead ghost offline afk dnd leader assist role icon",
        keywords = { "dead icon", "offline icon", "afk icon", "dnd icon", "ghost icon", "ready check icon", "leader icon", "assist icon", "status icons", "group status icon", "raid status icon" },
        priority = 85,
    },
    {
        label = "How do I hide realm names or shorten player names?",
        answer = "Open Global Style > Fonts > Name Shortening. It controls name shortening globally; unit text placement is on each unit page > Text.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts > Name Shortening",
        anchorText = "Name Shortening realm names short names player names font text",
        keywords = { "hide realm names", "remove realm names", "short names", "shorten player names", "names too long", "realm name showing", "server name showing", "name realm", "truncate names" },
        priority = 90,
    },
    {
        label = "How do I get class-colored health bars or names?",
        answer = "Open Global Style > Colors for class bar colors and unitframe colors. Group health colors are in Group Frames > Health & Text.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Class Bar Colors",
        anchorText = "Class Bar Colors Unitframe Colors Group Health Colors class colored names health bars",
        keywords = { "class colored health", "class colored names", "class color names", "class color health bars", "green health bars", "health bar class color", "target class color", "player class color", "raid class colors" },
        priority = 105,
    },
    {
        label = "How do I change click-casting so aura icons do not block heals?",
        answer = "Open Unit Auras > Display for click-through aura behavior, then use Gameplay for click-cast, mouseover, and targeting behavior.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Display",
        anchorText = "Display click-through auras Gameplay click cast mouseover healing party frames",
        keywords = { "auras block heals", "buffs block click casting", "debuffs block click cast", "can't heal through buffs", "mouseover heal blocked", "click cast blocked by aura", "heal mouseover auras", "party frame click through buffs" },
        priority = 115,
    },
    {
        label = "How do I open the MSUF options?",
        answer = "Use /msuf to open MSUF2. The Dashboard also contains reset, support, profile, and scale tools.",
        pageKey = "home",
        target = "Opens: Dashboard",
        anchorText = "Dashboard slash command msuf options menu support profiles reset",
        keywords = { "how to open msuf", "open msuf", "open options", "open addon options", "slash command", "/msuf", "msuf menu", "where is options", "addon options", "config menu", "configuration menu", "settings menu" },
        priority = 700,
    },
}

local SEARCH_EASTER_EGGS = {
    { name = "don lumen", result = "requested this feature" },
    { name = "Niuki", result = "Is the best Warlock in Retreat" },
    { name = "R41z0r", result = "He makes you better" },
    { name = "Unhalted", result = "South Africa ftw" },
    { name = "Hayato", result = "forgot to bind his heal spells" },
}

local function BuildSearchRecords()
    local pageInfos, pageInfoByKey = BuildSearchPageInfos()

    local records, seenRecords = {}, {}
    for i = 1, #pageInfos do
        local info = pageInfos[i]
        local pageParts = {}
        AddSearchText(pageParts, info.group)
        AddSearchText(pageParts, info.title)
        AddRawSearchText(pageParts, SEARCH_KEYWORDS[info.key])
        AddPageLocalizedSearchKeywords(pageParts, info.key)
        AddSearchRecord(records, seenRecords, info, info.label or info.title or info.key, nil, "page", pageParts)
    end

    for _, entry in pairs(SEARCH_STATE.registry) do
        local rec = SEARCH_STATE.registryRecords[entry.id]
        if not rec and BuildRegistrySearchRecord then
            rec = BuildRegistrySearchRecord(entry)
            SEARCH_STATE.registryRecords[entry.id] = rec
        end
        if rec then
            rec.order = #records + 1
            records[#records + 1] = rec
        end
    end

    for i = 1, #SEARCH_FAQ do
        local faq = SEARCH_FAQ[i]
        local pageKey = faq.pageKey or "home"
        local info = pageInfoByKey[pageKey] or { key = pageKey, label = "FAQ", title = "FAQ", group = "" }
        local extra = { faq.answer, faq.target, faq.anchorText }
        for k = 1, #(faq.keywords or {}) do extra[#extra + 1] = faq.keywords[k] end
        local rec = AddSearchRecord(records, seenRecords, info, faq.label, nil, "faq", extra)
        if rec then
            rec.answer = faq.answer
            rec.target = faq.target
            rec.anchorFallback = faq.anchorText or faq.label
            rec.route = faq.route
            rec.priority = tonumber(faq.priority) or 0
            rec.faq = true
        end
    end

    for i = 1, #SEARCH_EASTER_EGGS do
        local egg = SEARCH_EASTER_EGGS[i]
        local info = { key = "search", label = "", title = "", group = "" }
        local rec = AddSearchRecord(records, seenRecords, info, egg.name, nil, "easteregg", { egg.result, egg.name })
        if rec then
            rec.answer = egg.result
            rec.noOpen = true
            rec.priority = 1200
            rec.easterEgg = true
        end
    end

    return records
end

local SearchPages

local function RefreshSearchResultsPage()
    if M.activeKey ~= "search" then return end
    local query = TrimText(M.searchQuery or "")
    if query == "" or #NormalizeSearchText(query) < MIN_SEARCH_QUERY_LEN then return end
    M.searchResults = nil
    M.searchResultsQuery = nil
    M.searchResults = SearchPages(query)
    M.searchResultsQuery = query
    if M.InvalidatePage then M.InvalidatePage("search") end
    if M.SelectPage then M.SelectPage("search") end
end

local function FinishSearchBackgroundIndex()
    SEARCH_STATE.indexing = false
    SEARCH_STATE.indexQueue = nil
    local query = TrimText(M.searchQuery or "")
    local shouldRefresh = M.activeKey == "search" and query ~= "" and #NormalizeSearchText(query) >= MIN_SEARCH_QUERY_LEN
    if shouldRefresh and SEARCH_STATE.recordsDirty then
        SEARCH_STATE.records = BuildSearchRecords()
        SEARCH_STATE.recordsDirty = false
    end
    if shouldRefresh then RefreshSearchResultsPage() end
end

local function StartSearchBackgroundIndex()
    if SEARCH_STATE.indexing then return end
    if SearchCombatLocked() then return end
    if not (_G.C_Timer and _G.C_Timer.After) then return end
    if not (M.frame and M.frame.IsShown and M.frame:IsShown()) then return end
    if not M.scrollChild then return end

    local pageInfos = BuildSearchPageInfos()
    local queue = {}
    for i = 1, #pageInfos do
        local info = pageInfos[i]
        local cached = M.cache and M.cache[info.key]
        if info.key ~= "search" and not (cached and cached.wrapper) then
            queue[#queue + 1] = info.key
        end
    end
    if #queue == 0 then return end

    SEARCH_STATE.indexing = true
    SEARCH_STATE.indexQueue = queue

    local function Step()
        if not SEARCH_STATE.indexing then return end
        if M.activeKey ~= "search" or SearchCombatLocked() or not (M.frame and M.frame.IsShown and M.frame:IsShown()) then
            CancelSearchBackgroundIndex()
            return
        end

        local key = table.remove(SEARCH_STATE.indexQueue, 1)
        if key then
            if M.BuildPageEntry then M.BuildPageEntry(key, true) end
            MarkSearchIndexDirty()
        end

        if SEARCH_STATE.indexQueue and #SEARCH_STATE.indexQueue > 0 then
            _G.C_Timer.After(SEARCH_BACKGROUND_STEP_SEC, Step)
        else
            FinishSearchBackgroundIndex()
        end
    end

    _G.C_Timer.After(0, Step)
end

local function GetSearchRecords()
    EnsureSearchLocaleFresh()
    if SEARCH_STATE.indexing and SEARCH_STATE.records and not SEARCH_STATE.recordsDirty then
        return SEARCH_STATE.records
    end
    if not SEARCH_STATE.records or SEARCH_STATE.recordsDirty then
        SEARCH_STATE.records = BuildSearchRecords()
        SEARCH_STATE.recordsDirty = false
    end
    StartSearchBackgroundIndex()
    return SEARCH_STATE.records
end

local function CurateSearchResults(results, supportQuestion)
    local topScore = results[1] and (tonumber(results[1].score) or 0) or 0
    local floorScore = SEARCH_MIN_RESULT_SCORE
    if topScore >= 600 then
        floorScore = math.max(floorScore, topScore * (supportQuestion and 0.70 or 0.42))
    elseif topScore >= 300 then
        floorScore = math.max(floorScore, topScore * 0.30)
    end

    local function SpecificControlMatch(rec)
        local clauseCount = tonumber(rec and rec.queryClauseCount) or 0
        if clauseCount < 2 then return false end
        if rec.kind == "page" or rec.kind == "faq" or rec.kind == "easteregg" then return false end
        return (tonumber(rec.missedClauses) or 0) == 0 and (tonumber(rec.matchedClauses) or 0) == clauseCount
    end

    local curated = {}
    for i = 1, #results do
        local rec = results[i]
        if rec and ((tonumber(rec.score) or 0) >= floorScore or SpecificControlMatch(rec)) then
            curated[#curated + 1] = rec
            if #curated >= SEARCH_MAX_RESULTS then break end
        end
    end
    return curated
end

function SearchPages(query)
    query = TrimText(query)
    if SearchCombatLocked() then
        CancelSearchBackgroundIndex()
        return {}
    end
    local normalized, clauses = BuildSearchQueryClauses(query)
    if #clauses == 0 then return {} end
    if #normalized < MIN_SEARCH_QUERY_LEN then return {} end

    local supportQuestion = SearchLooksLikeSupportQuestion(query)
    local genericLocationSubject, genericLocationClauses = SearchGenericLocationSubjectClauses(query)
    local genericLocationQuestion = genericLocationSubject ~= nil and genericLocationClauses ~= nil
    local controlQuestion = SearchLooksLikeControlQuestion(query) or genericLocationQuestion
    local profileTransferQuestion = normalized:find("import", 1, true)
        or normalized:find("export", 1, true)
        or normalized:find("profile string", 1, true)
        or normalized:find("legacy import", 1, true)
    local wagoBrowseQuestion = (normalized:find("wago", 1, true) and normalized:find("profile", 1, true))
        or normalized:find("browse wago", 1, true)
        or normalized:find("wago hub", 1, true)
    if profileTransferQuestion then wagoBrowseQuestion = false end
    local requiredMatches = #clauses
    if supportQuestion and #clauses > 3 then
        requiredMatches = math.max(2, math.ceil(#clauses * 0.55))
    end
    local results = {}
    local records = GetSearchRecords()
    for i = 1, #records do
        local rec = records[i]
        local score = 0
        local matched = true
        local matchedClauses = 0
        local missedClauses = 0
        for c = 1, #clauses do
            local ok, clauseScore = SearchClauseScore(rec, clauses[c])
            if not ok then
                missedClauses = missedClauses + 1
                if requiredMatches == #clauses or (#clauses - missedClauses) < requiredMatches then
                    matched = false
                    break
                end
            else
                matchedClauses = matchedClauses + 1
                score = score + clauseScore
            end
        end
        if matched and matchedClauses >= requiredMatches then
            if rec.labelNorm == normalized or rec.titleNorm == normalized then score = score + 260 end
            if rec.labelNorm:sub(1, #normalized) == normalized then score = score + 130 end
            if rec.haystack and rec.haystack:find(normalized, 1, true) then score = score + 80 end
            if rec.kind == "section" then score = score + 70 end
            if rec.kind == "faq" then score = score + 55 end
            if supportQuestion and not genericLocationQuestion then score = score + SearchSupportQuestionBoost(rec, clauses) end
            if genericLocationQuestion then score = score + SearchGenericLocationBoost(rec, genericLocationClauses, matchedClauses, missedClauses) end
            score = score + SearchResultSpecificityBoost(rec, clauses)
            if missedClauses > 0 then score = score - (missedClauses * 60) end
            if rec.kind ~= "page" then score = score + 45 end
            if rec.kind == "slider" or rec.kind == "dropdown" or rec.kind == "toggle" then score = score + 25 end
            if controlQuestion
                and (rec.kind == "toggle" or rec.kind == "dropdown" or rec.kind == "slider" or rec.kind == "segment"
                    or rec.kind == "textinput" or rec.kind == "color")
                and #clauses >= 2 and missedClauses == 0 and matchedClauses == #clauses then
                score = score + 1300
            end
            if rec.priority then score = score + rec.priority end
            if profileTransferQuestion then
                if rec.key == "profiles" then score = score + 520 end
                if rec.key == "home" and rec.labelNorm == "wago profile hub" then score = score - 520 end
            elseif wagoBrowseQuestion then
                if rec.key == "home" and rec.labelNorm == "wago profile hub" then score = score + 720 end
                if rec.key == "profiles" and rec.kind == "page" then score = score - 180 end
            end
            rec.score = score
            rec.matchedClauses = matchedClauses
            rec.missedClauses = missedClauses
            rec.queryClauseCount = #clauses
            results[#results + 1] = rec
        end
    end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if (a.hint or "") ~= (b.hint or "") then return tostring(a.hint or "") < tostring(b.hint or "") end
        if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
        return tostring(a.label) < tostring(b.label)
    end)
    return CurateSearchResults(results, supportQuestion and not genericLocationQuestion)
end

local function SearchQueryReady(query)
    return #NormalizeSearchText(query or "") >= MIN_SEARCH_QUERY_LEN
end

local function ShowSearchPageForQuery(query)
    query = TrimText(query)
    if query ~= "" and M.activeKey ~= "search" then
        M.searchReturnKey = M.activeKey or M.searchReturnKey or "home"
    end
    M.InvalidatePage("search")
    if query ~= "" then
        M.SelectPage("search")
    elseif M.activeKey == "search" then
        M.SelectPage(M.searchReturnKey or "home")
    end
end

local function RunSearchInputQuery(query, openPage)
    query = TrimText(query)
    M.searchQuery = query
    M.searchResultsPending = nil

    if query == "" then
        M.searchResults = {}
        M.searchResultsQuery = ""
        if openPage then ShowSearchPageForQuery(query) end
        return
    end

    if SearchCombatLocked() then
        CancelSearchBackgroundIndex()
        M.searchResults = {}
        M.searchResultsQuery = query
        if openPage and M.activeKey ~= "search" then ShowSearchPageForQuery(query) end
        return
    end

    if not SearchQueryReady(query) then
        M.searchResults = {}
        M.searchResultsQuery = query
        if openPage then ShowSearchPageForQuery(query) end
        return
    end

    M.searchResults = SearchPages(query)
    M.searchResultsQuery = query
    if openPage then ShowSearchPageForQuery(query) end
end

local function ScheduleSearchInputQuery(searchBox, query)
    query = TrimText(query)
    SEARCH_STATE.inputSerial = SEARCH_STATE.inputSerial + 1
    local serial = SEARCH_STATE.inputSerial

    M.searchQuery = query

    if query == "" or SearchCombatLocked() or not SearchQueryReady(query) then
        RunSearchInputQuery(query, true)
        return
    end

    M.searchResultsPending = true
    M.searchResultsQuery = query
    if M.activeKey ~= "search" then
        M.searchResults = {}
        ShowSearchPageForQuery(query)
    end

    local function RunLatest()
        if serial ~= SEARCH_STATE.inputSerial then return end
        if searchBox and searchBox.GetText then
            local latest = TrimText(searchBox:GetText() or "")
            if latest ~= query then return end
        end
        RunSearchInputQuery(query, true)
    end

    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(SEARCH_INPUT_DEBOUNCE_SEC, RunLatest)
    else
        RunLatest()
    end
end

local function OpenSearchResults(query)
    SEARCH_STATE.inputSerial = SEARCH_STATE.inputSerial + 1
    RunSearchInputQuery(query, true)
end

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
            { id = "general", terms = { "general", "enable", "show player", "show solo", "solo", "visibility", "party frames not showing", "raid frames not showing" } },
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
            { id = "blizzrenderer", terms = { "aura display mode", "blizzard dispels", "blizzard mode", "msuf dispel border glow", "native dispel icons" } },
            { id = "buffs", terms = { "buffs", "buff", "hots", "own buffs", "healer buffs" } },
            { id = "debuffs", terms = { "debuffs", "debuff", "boss debuff", "raid debuff", "magic", "curse", "poison", "disease" } },
            { id = "ext", terms = { "externals", "defensives", "external cooldowns" } },
            { id = "textcolor", terms = { "text coloring", "timer color", "cooldown text", "stack text", "pandemic" } },
            { id = "priv", terms = { "private auras", "private aura" } },
            { id = "masque", terms = { "cooldown style", "masque", "cooldown swipe" } },
            { id = "autil", terms = { "aura utilities", "custom aura", "custom buff", "custom debuff", "spell id" } },
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
            { id = "bars_highlight", terms = { "highlight borders", "highlight border", "dispel border", "dispel glow", "aggro border", "purge border", "boss target border", "priority order" } },
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
            { id = "castbar_gcd", terms = { "gcd", "global cooldown", "gcd bar", "instant casts" } },
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
    elseif pageKey == "auras2" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "a2_display", terms = { "display", "click through", "click-through", "buffs", "debuffs", "show buffs", "show debuffs" } },
            { id = "a2_layout", terms = { "caps", "icons", "max buffs", "max debuffs", "icon size", "rows", "spacing", "anchor" } },
            { id = "a2_text_coloring", terms = { "text coloring", "cooldown text", "timer color", "stack text", "pandemic" } },
            { id = "a2_private", terms = { "private auras", "private aura" } },
            { id = "a2_filters", terms = { "aura filters", "filter", "sorting", "dispellable", "only mine", "own buffs", "own debuffs" } },
            { id = "a2_ignore", terms = { "ignore list", "global ignore", "blacklist" } },
            { id = "a2_reminders", terms = { "buff reminders", "reminders", "missing buff" } },
        })
        if SearchRouteHasAny(normalized, { "player" }) then
            SearchRouteSetState(route, "auraScope", "player")
        elseif SearchRouteHasAny(normalized, { "target" }) then
            SearchRouteSetState(route, "auraScope", "target")
        elseif SearchRouteHasAny(normalized, { "focus" }) then
            SearchRouteSetState(route, "auraScope", "focus")
        elseif SearchRouteHasAny(normalized, { "boss" }) then
            SearchRouteSetState(route, "auraScope", "boss")
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

local function SearchResultHasDetail(rec)
    if not rec then return false end
    if rec.kind == "faq" or rec.kind == "easteregg" then return rec.answer ~= nil and rec.answer ~= "" end
    return rec.answer ~= nil and rec.answer ~= ""
end

local function BuildSearchPage(ctx)
    local root = ctx.wrapper
    local width = ctx.width
    local query = TrimText(M.searchQuery or "")
    local combatLocked = SearchCombatLocked() and true or false
    local queryReady = not combatLocked and #NormalizeSearchText(query) >= MIN_SEARCH_QUERY_LEN
    local results = M.searchResults or {}
    if M.searchResultsQuery ~= query and not M.searchResultsPending then
        results = combatLocked and {} or SearchPages(query)
        M.searchResults = results
        M.searchResultsQuery = query
    end

    local b = W.PageBuilder(ctx)
    b:Header("Search", query ~= "" and M.Format("Results for \"%s\"", query) or "Type in the search box on the left.", 78)

    local maxVisible = SEARCH_VISIBLE_RESULTS
    local visible = math.min(#results, maxVisible)
    local hasExpandedResult = false
    for i = 1, visible do
        if SearchResultHasDetail(results[i]) then
            hasExpandedResult = true
            break
        end
    end
    local columns = (hasExpandedResult and 1) or (width >= 760 and 2 or 1)
    local gap = 12
    local colW = math.floor((width - 24 - gap * (columns - 1)) / columns)
    local rowH = hasExpandedResult and 62 or 30
    local resultTopY = SEARCH_STATE.indexing and -88 or -70
    local rows = math.max(3, math.ceil(math.max(visible, 1) / columns))
    local sectionH = math.max(160, 74 + rows * rowH + (SEARCH_STATE.indexing and 18 or 0))
    local sec = b:Section("Search Results", sectionH)

    if combatLocked then
        W.Text(sec, "Search is paused in combat.", 14, -44, width - 28, T.colors.muted)
        W.Text(sec, "MSUF2 does not build or refresh the search index during combat.", 14, -70, width - 28, T.colors.dim)
    elseif query == "" then
        W.Text(sec, "Start typing to search every MSUF2 menu page.", 14, -44, width - 28, T.colors.muted)
    elseif not queryReady then
        W.Text(sec, M.Format("Type at least %d characters to search.", MIN_SEARCH_QUERY_LEN), 14, -44, width - 28, T.colors.muted)
    elseif M.searchResultsPending then
        W.Text(sec, M.Format("Searching for \"%s\"...", query), 14, -44, width - 28, T.colors.muted)
        W.Text(sec, "Results update after you stop typing for a moment.", 14, -70, width - 28, T.colors.dim)
    elseif #results == 0 then
        W.Text(sec, M.Format("No results for \"%s\".", query), 14, -44, width - 28, T.colors.muted)
        W.Text(sec, SEARCH_STATE.indexing and "Still indexing menu pages..." or "Try a page name like bars, profiles, auras, castbar, colors, group, or target.", 14, -70, width - 28, T.colors.dim)
    else
        W.Text(sec, M.Format("Best %d match(es). Press Enter to open the first match.", visible), 14, -44, width - 28, T.colors.muted)
        if SEARCH_STATE.indexing then
            W.Text(sec, "Indexing more menu pages in the background.", 14, -62, width - 28, T.colors.dim)
        end
        for i = 1, visible do
            local rec = results[i]
            local col = (i - 1) % columns
            local row = math.floor((i - 1) / columns)
            local x = 14 + col * (colW + gap)
            local y = resultTopY - row * rowH
            local kind = CONTROL_KIND_LABEL[rec.kind or ""] or (rec.kind == "page" and "Page") or nil
            if kind and type(M.Tr) == "function" then kind = M.Tr(kind) end
            local prefix = rec.hint ~= "" and rec.hint or rec.group
            local text = prefix ~= "" and (ShortLabel(prefix, 42) .. " > " .. ShortLabel(rec.label, 38)) or rec.label
            if kind and rec.kind ~= "text" then text = text .. " [" .. kind .. "]" end
            local btn = T.Button(sec, text, colW, 22)
            btn:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            local pageKey = rec.key
            local fallback = rec.anchorFallback or rec.label or rec.title
            local anchor = rec.anchor
            local route = rec.route
            local noOpen = rec.noOpen
            btn:SetScript("OnClick", function()
                if noOpen then
                    if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
                    return
                end
                OpenSearchTarget(pageKey, query, fallback, anchor, route)
            end)
            if SearchResultHasDetail(rec) then
                local answer = (type(M.Tr) == "function" and M.Tr(rec.answer)) or rec.answer
                W.Text(sec, ShortLabel(answer, 132), x + 8, y - 24, colW - 16, T.colors.dim)
                if rec.target and rec.target ~= "" then
                    local target = (type(M.Tr) == "function" and M.Tr(rec.target)) or rec.target
                    W.Text(sec, ShortLabel(target, 112), x + 8, y - 42, colW - 16, T.colors.muted)
                end
            end
        end
        if #results > maxVisible then
            W.Text(sec, M.Format("Showing the best %d matches. Add one more word to narrow it further.", maxVisible), 14, resultTopY - rows * rowH, width - 28, T.colors.dim)
        end
    end

    local quick = b:Section("Support Search Examples", 206)
    local shortcutDispel = "dispel border glow any debuff"
    local shortcutStripe = "where is debuff stripe"
    local shortcutHighlights = "highlight priority dispel aggro target"
    local shortcuts = {
        { "Move Frames", "where do I move my unitframe" },
        { "Background", "change my backgrond" },
        { "Raid Frames", "move raid frames" },
        { "Text Size", "make text bigger" },
        { "Profiles", "import profile wago" },
        { "Castbar", "evoker castbar" },
        { "Buffs", "show only my buffs" },
        { "Blizzard", "hide blizzard frames" },
        { "Range Check", "unit frame range check" },
        { "Level Text", "where is level text anchor" },
        { "Performance", "why is msuf lagging" },
        { "Minimap", "where is the minimap icon setting" },
        { "Rounded", "rounded frames ausschalten" },
        { "Dispel", shortcutDispel },
        { "Stripe", shortcutStripe },
        { "Highlights", shortcutHighlights },
    }
    local buttonW = math.floor((width - 56) / 3)
    for i = 1, #shortcuts do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local searchQuery = shortcuts[i][2]
        local btn = T.Button(quick, shortcuts[i][1], buttonW, 22)
        btn:SetPoint("TOPLEFT", quick, "TOPLEFT", 14 + col * (buttonW + 14), -38 - row * 28)
        btn:SetScript("OnClick", function()
            if M.nav and M.nav.searchBox then
                M.nav.searchBox._msuf2SearchInternal = true
                M.nav.searchBox:SetText(searchQuery)
                M.nav.searchBox._msuf2SearchInternal = nil
                M.nav.searchBox:ClearFocus()
            end
            OpenSearchResults(searchQuery)
        end)
    end

    ctx:SetContentHeight(math.max(ContentHeight(), math.abs(b.y) + 42))
end


Search.SearchPlaceholderText = SearchPlaceholderText
Search.SearchBoxHasText = SearchBoxHasText
Search.RefreshSearchPlaceholder = RefreshSearchPlaceholder
Search.UpdateSearchPlaceholder = UpdateSearchPlaceholder
Search.MarkIndexDirty = MarkSearchIndexDirty
Search.CancelBackgroundIndex = CancelSearchBackgroundIndex
Search.ClearRegistryPage = ClearSearchRegistryPage
Search.BumpInputSerial = function()
    SEARCH_STATE.inputSerial = SEARCH_STATE.inputSerial + 1
end
Search.RefreshResultsPage = RefreshSearchResultsPage
Search.ScheduleInputQuery = ScheduleSearchInputQuery
Search.RunInputQuery = RunSearchInputQuery
Search.OpenResults = OpenSearchResults
Search.OpenTarget = OpenSearchTarget
Search.SearchPages = SearchPages
Search.TrimText = TrimText
Search.ShortLabel = ShortLabel

if type(ns.RegisterLocaleCallback) == "function" then
    ns.RegisterLocaleCallback("MSUF2_Menu2_Search", function()
        SEARCH_STATE.localeKey = nil
        ClearSearchLocaleCaches()
        CancelSearchBackgroundIndex()
        MarkSearchIndexDirty()
        if M.activeKey == "search" then RefreshSearchResultsPage() end
    end)
end

M.RegisterPage("search", { title = "Search", build = BuildSearchPage, version = 1 })

