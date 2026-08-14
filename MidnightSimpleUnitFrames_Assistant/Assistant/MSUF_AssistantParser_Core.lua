local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Low-level text helpers shared by all Assistant parser shards.
-- This file owns normalization, tokenization, fuzzy matching, and broad scope detection.
-- It deliberately has no profile writes and no UI side effects; callers should build
-- declarative parse results and let the router execute them after confirmation.
local Registry = A.Registry
local P = A.Parser or {}
A.Parser = P
local Data = A.ParserData or {}
A.ParserData = Data
local CoreData = Data.CORE_PARSER or {}
local UnitTerms = CoreData.UNIT_TERMS or {}

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local Normalize

-- Generational cache: two tables, no per-key deletes. Delete-based eviction
-- (FIFO/ring) keeps a hash table at capacity under constant insert+delete,
-- which drives Lua into rehash storms (~200us per insert, measured — it made
-- index builds 25x slower). Instead, inserts go into the hot table; when it
-- fills, the hot generation becomes the cold one and a fresh table starts.
-- Lookups check hot then cold, so the effective window is 1-2 generations.
local normalizeCacheHot = {}
local normalizeCacheCold = {}
local normalizeCacheHotCount = 0
local NORMALIZE_CACHE_LIMIT = 8192

local NORMALIZE_WORD_REPLACEMENTS = {
    -- Everyday abbreviation. Control names spell it out ("Temp Max Health
    -- Background Opacity"), so "temp max health bg opacity to 50" matched no
    -- control while the spelled-out sentence resolved normally. Safe as a whole
    -- word: MSUF has no control literally named "bg".
    bg = "background",
    groesse = "size",
    grosse = "size",
    wat = "what",
    whta = "what",
    wich = "which",
    whcih = "which",
    whch = "which",
    wheer = "where",
    wheree = "where",
    wher = "where",
    permanant = "permanent",
    permenant = "permanent",
    permanet = "permanent",
    permenent = "permanent",
    rsult = "result",
    rsults = "results",
    reslt = "result",
    reslts = "results",
    resut = "result",
    resuts = "results",
    reslut = "result",
    resluts = "results",
    reuslt = "result",
    reults = "results",
    playerframe = "player frame",
    targetframe = "target frame",
    focusframe = "focus frame",
    petframe = "pet frame",
    bossframe = "boss frame",
    targettargetframe = "targettarget frame",
    focustargetframe = "focustarget frame",
    unitframe = "unit frame",
    groupframe = "group frame",
    groupframes = "group frames",
    partyframe = "party frame",
    partyframes = "party frames",
    raidframe = "raid frame",
    raidframes = "raid frames",
    mythicraidframe = "mythicraid frame",
    mythicraidframes = "mythicraid frames",
    raidgroup = "raid group",
    raidgroupname = "raid group name",
    subgroupname = "subgroup name",
    groupnumber = "group number",
    readycheck = "ready check",
    readycheckicon = "ready check icon",
    raidmarker = "raid marker",
    raidmarkericon = "raid marker icon",
    roleicon = "role icon",
    leadericon = "leader icon",
    assisticon = "assist icon",
    summonicon = "summon icon",
    resurrecticon = "resurrect icon",
    resurrectionicon = "resurrection icon",
    phaseicon = "phase icon",
    pvpflag = "pvp flag",
    pvpicon = "pvp icon",
    pvpindicator = "pvp indicator",
    optino = "option",
    optinos = "options",
    opiton = "option",
    opitons = "options",
    choise = "choice",
    choises = "choices",
    alowed = "allowed",
    allowd = "allowed",
    valus = "values",
    valuees = "values",
    vaues = "values",
    supprted = "supported",
    suported = "supported",
    suppported = "supported",
    availble = "available",
    avaiable = "available",
    rang = "range",
    gradiant = "gradient",
    gradiants = "gradients",
    gradent = "gradient",
    gradents = "gradients",
    frist = "first",
    firts = "first",
    frst = "first",
    secnd = "second",
    secon = "second",
    seocnd = "second",
    sceond = "second",
    thrid = "third",
    thrd = "third",
    thierd = "third",
    tird = "third",
    fouth = "fourth",
    foruth = "fourth",
    fourthh = "fourth",
    fith = "fifth",
    fifht = "fifth",
    fifthh = "fifth",
    sixt = "sixth",
    sixthh = "sixth",
    seveth = "seventh",
    sevnth = "seventh",
    eigth = "eighth",
    eightth = "eighth",
    nineth = "ninth",
    ninthh = "ninth",
    tenthh = "tenth",
    oen = "one",
    onee = "one",
    teo = "two",
    twoo = "two",
    thre = "three",
    threee = "three",
    foor = "four",
    fourr = "four",
    fiv = "five",
    fivee = "five",
    nxt = "next",
    nex = "next",
    nextt = "next",
    previus = "previous",
    previos = "previous",
    prevous = "previous",
    prvious = "previous",
    previouss = "previous",
    shoudl = "should",
    shuld = "should",
    compair = "compare",
    compar = "compare",
    comapre = "compare",
    comapir = "compare",
    diference = "difference",
    differnce = "difference",
    diffrence = "difference",
    diferences = "differences",
    differnces = "differences",
    diffrences = "differences",
    betwen = "between",
    beetween = "between",
    trun = "turn",
    tirn = "turn",
    tunr = "turn",
    turnn = "turn",
    maek = "make",
    mkae = "make",
    chnage = "change",
    chagne = "change",
    moev = "move",
    mvoe = "move",
    adjut = "adjust",
    ajust = "adjust",
    aply = "apply",
    aplly = "apply",
    applay = "apply",
    toggel = "toggle",
    togge = "toggle",
    tggle = "toggle",
    shwo = "show",
    hsow = "show",
    hdie = "hide",
    hied = "hide",
    increse = "increase",
    increae = "increase",
    increasee = "increase",
    decrese = "decrease",
    decres = "decrease",
    decreasee = "decrease",
    chek = "check",
    chekc = "check",
    checl = "check",
    enabel = "enable",
    enble = "enable",
    enablee = "enable",
    enalbe = "enable",
    disabel = "disable",
    disble = "disable",
    disablee = "disable",
    disaable = "disable",
    porfile = "profile",
    profiel = "profile",
    profie = "profile",
    paeg = "page",
    mneu = "menu",
    improt = "import",
    exprot = "export",
    copie = "copy",
    seperat = "separat",
    seperator = "separator",
    seperators = "separators",
    delimeter = "delimiter",
    delimeters = "delimiters",
    heigth = "height",
    hieght = "height",
    hight = "height",
    widht = "width",
    widh = "width",
    opactiy = "opacity",
    opacitiy = "opacity",
    aplha = "alpha",
    alhpa = "alpha",
    fdae = "fade",
    fde = "fade",
    faed = "fade",
    transparancy = "transparency",
    transparant = "transparent",
    transperency = "transparency",
    transperancy = "transparency",
    curent = "current",
    currnet = "current",
    currnt = "current",
    vaule = "value",
    valeu = "value",
    valye = "value",
    explian = "explain",
    expalin = "explain",
    explan = "explain",
    exlain = "explain",
    locaton = "location",
    loction = "location",
    lcoation = "location",
    collor = "color",
    colour = "color",
    grey = "gray",
    fitler = "filter",
    fliter = "filter",
    filtres = "filters",
    antoher = "another",
    bgu = "bug",
    condtion = "condition",
    conditoin = "condition",
    dispelable = "dispellable",
    dispellabe = "dispellable",
    dispellble = "dispellable",
    felher = "fehler",
    restar = "restore",
    resotre = "restore",
    snappign = "snapping",
    snaping = "snapping",
    snappping = "snapping",
    taregt = "target",
    targte = "target",
    targt = "target",
    targrt = "target",
    taret = "target",
    traget = "target",
    taerget = "target",
    targett = "target",
    tagret = "target",
    targert = "target",
    targer = "target",
    targget = "target",
    tarhet = "target",
    trget = "target",
    playr = "player",
    plaer = "player",
    plyer = "player",
    palyer = "player",
    plaeyr = "player",
    playre = "player",
    pleyer = "player",
    foucs = "focus",
    focs = "focus",
    focsu = "focus",
    fcous = "focus",
    focuss = "focus",
    foccus = "focus",
    partty = "party",
    praty = "party",
    pratty = "party",
    partyy = "party",
    parties = "party",
    riad = "raid",
    raide = "raid",
    raidss = "raid",
    raids = "raid",
    mythci = "mythic",
    myhtic = "mythic",
    mithic = "mythic",
    mythc = "mythic",
    mythicc = "mythic",
    clas = "class",
    calss = "class",
    cass = "class",
    frm = "frame",
    frms = "frames",
    unitfram = "unitframe",
    unitframs = "unitframes",
    unitfames = "unitframes",
    auras = "aura",
    auara = "aura",
    auaras = "aura",
    auars = "aura",
    aurra = "aura",
    aurs = "aura",
    bufs = "buffs",
    bufff = "buff",
    debuf = "debuff",
    debufs = "debuffs",
    debufff = "debuff",
    cd = "cooldown",
    countdwon = "countdown",
    countdonw = "countdown",
    coundown = "countdown",
    pwr = "power",
    powr = "power",
    pwoer = "power",
    ressource = "resource",
    resrouce = "resource",
    resoruce = "resource",
    resorce = "resource",
    stak = "stack",
    staks = "stacks",
    privte = "private",
    prviate = "private",
    pirvate = "private",
    visiblity = "visibility",
    visibilty = "visibility",
    visable = "visible",
    visibile = "visible",
    indcator = "indicator",
    indciator = "indicator",
    indictor = "indicator",
    idnicator = "indicator",
    threshhold = "threshold",
    treshold = "threshold",
    castbr = "castbar",
    castabr = "castbar",
    castba = "castbar",
    castbra = "castbar",
    crosair = "crosshair",
    crossair = "crosshair",
    crosshir = "crosshair",
    protait = "portrait",
    portriat = "portrait",
    portrtait = "portrait",
    portait = "portrait",
    portraid = "portrait",
    helath = "health",
    haelth = "health",
    helth = "health",
    healt = "health",
    waggo = "wago",
    wagoo = "wago",
    wgao = "wago",
    rihgt = "right",
    rigth = "right",
    riht = "right",
    lef = "left",
    lft = "left",
    upp = "up",
    dn = "down",
    donw = "down",
    dwon = "down",
    smaler = "smaller",
    smalller = "smaller",
    biger = "bigger",
    lagrer = "larger",
    closser = "closer",
    clsoer = "closer",
    achor = "anchor",
    ancor = "anchor",
    ancher = "anchor",
    anchro = "anchor",
    acnhor = "anchor",
    atach = "attach",
    detatch = "detach",
    teh = "the",
    yu = "you",
    yuo = "you",
    u = "you",
    txt = "text",
    txts = "texts",
    icn = "icon",
    icns = "icons",
    icno = "icon",
    iocn = "icon",
    iconn = "icon",
    boder = "border",
    bordr = "border",
    broder = "border",
    outlne = "outline",
    outlien = "outline",
    otuline = "outline",
    oultine = "outline",
    rdy = "ready",
    readycheck = "ready check",
    readychecks = "ready checks",
    readychek = "ready check",
    readycheks = "ready checks",
    readychekc = "ready check",
    readychk = "ready check",
    readychks = "ready checks",
    raidmark = "raid marker",
    raidmarks = "raid markers",
    zlayer = "z layer",
    interupt = "interrupt",
    trennzeichen = "separator",
    trenner = "separator",
    -- The German infinitive "verstecken" is wired through the visibility
    -- parsers; the imperative a player actually types was not. Fold it onto the
    -- form that already works instead of translating to English, so every
    -- German-specific path keeps matching.
    verstecke = "verstecken",
    versteck = "verstecken",
    verberge = "verstecken",
    verbergen = "verstecken",
}

-- German writes "target width" as one word, so "zielbreite" never matched the
-- unit or the attribute and the whole request fell through to a generic
-- fallback. Split the compounds the same way "targetframe" is already split,
-- and fold the genitive ("die Breite des Ziels") onto the plain noun so the
-- unit still resolves. Generated rather than listed: the combinations are
-- mechanical, and a hand-written list would drift as terms are added.
do
    local units = {
        ziel = "ziel", ziels = "ziel", zieles = "ziel",
        spieler = "spieler", spielers = "spieler",
        fokus = "fokus", fokusses = "fokus",
        begleiter = "begleiter", begleiters = "begleiter",
        boss = "boss", bosses = "boss",
        gruppe = "gruppe", gruppen = "gruppe",
    }
    -- Emit the English attribute: replacement happens in a single token pass,
    -- so a German word produced here would never be translated afterwards, and
    -- the parsers resolve a German unit next to an English attribute fine
    -- ("setze ziel width auf 260" already works). Declensions are listed
    -- explicitly because German inflects the noun, not the compound.
    local attributes = {
        breite = "width", breiten = "width",
        hoehe = "height", hoehen = "height",
        groesse = "size", groessen = "size",
        farbe = "color", farben = "color",
        transparenz = "opacity", opazitaet = "opacity",
        schrift = "font", schriften = "font",
        schriftgroesse = "font size",
        abstand = "spacing", abstaende = "spacing",
        skalierung = "scale",
        name = "name", namen = "name",
        rahmen = "frame",
        portraet = "portrait", portraets = "portrait",
        textur = "texture", texturen = "texture",
        position = "position",
    }
    for compoundPrefix, unitWord in pairs(units) do
        -- The bare genitive on its own still has to reach the unit.
        if compoundPrefix ~= unitWord and not NORMALIZE_WORD_REPLACEMENTS[compoundPrefix] then
            NORMALIZE_WORD_REPLACEMENTS[compoundPrefix] = unitWord
        end
        for germanAttribute, englishAttribute in pairs(attributes) do
            local compound = compoundPrefix .. germanAttribute
            if not NORMALIZE_WORD_REPLACEMENTS[compound] then
                NORMALIZE_WORD_REPLACEMENTS[compound] = unitWord .. " " .. englishAttribute
            end
        end
    end
end

local ACTIONABLE_LEADING_PREFIXES = {
    "can you please",
    "could you please",
    "would you please",
    "will you please",
    "can you",
    "could you",
    "would you",
    "will you",
    "please",
    "pls",
    "hey",
    "hi",
    "hello",
    "assistant",
    "msuf assistant",
    -- Discourse fillers that open a sentence without changing the request.
    -- "now disable Focus Show Power" names its frame and control exactly, yet
    -- the leading word alone was enough to drop it to "I'm not confident enough
    -- to guess what you meant" while the identical sentence without it applied.
    --
    -- Conjunctions ("and", "then", "so", "also") are deliberately NOT here:
    -- compound parsing splits on exactly those words, and listing them as
    -- strippable prefixes blew the cold compound preflight budget tenfold.
    "now",
    "ok",
    "okay",
    "just",
    "quickly",
    "go ahead and",
    "i want to",
    "i wanna",
    "i need to",
    "i would like to",
    "id like to",
    "i am trying to",
    "im trying to",
    "help me to",
    "help me",
    "let us",
    "lets",
    "bitte",
    "kannst du bitte",
    "kannst du",
    "koenntest du bitte",
    "koenntest du",
    "ich moechte",
    "ich will",
    "ich brauche",
    "hilf mir bitte",
    "hilf mir",
}

local ACTIONABLE_TRAILING_SUFFIXES = {
    "for me please",
    "for me",
    "please",
    "pls",
    "in msuf",
    "inside msuf",
    "with msuf",
    "on msuf",
    "thanks",
    "thank you",
    "danke",
    "danke dir",
    "bitte",
}

local actionableTextCache = {}
local actionableTextCacheCount = 0

local function StripPhrasePrefix(text, prefix)
    if text == prefix then return "" end
    if text:sub(1, #prefix + 1) == prefix .. " " then return Trim(text:sub(#prefix + 2)) end
    return nil
end

local function StripPhraseSuffix(text, suffix)
    if text == suffix then return "" end
    if #text > #suffix and text:sub(-#suffix) == suffix and text:sub(#text - #suffix, #text - #suffix) == " " then
        return Trim(text:sub(1, #text - #suffix - 1))
    end
    return nil
end

-- A second normalized form for matching only. It removes human chat wrappers while
-- preserving the original/raw text for string values and profile payloads.
local function ActionableText(text)
    local normalized = Normalize(text)
    if normalized == "" then return normalized end
    local cached = actionableTextCache[normalized]
    if cached ~= nil then return cached end

    local out = normalized
    local changed = true
    local loops = 0
    while changed and loops < 8 do
        loops = loops + 1
        changed = false
        for i = 1, #ACTIONABLE_LEADING_PREFIXES do
            local stripped = StripPhrasePrefix(out, ACTIONABLE_LEADING_PREFIXES[i])
            if stripped ~= nil then
                out = stripped
                changed = true
                break
            end
        end
    end

    changed = true
    loops = 0
    while changed and loops < 6 do
        loops = loops + 1
        changed = false
        for i = 1, #ACTIONABLE_TRAILING_SUFFIXES do
            local stripped = StripPhraseSuffix(out, ACTIONABLE_TRAILING_SUFFIXES[i])
            if stripped ~= nil then
                out = stripped
                changed = true
                break
            end
        end
    end

    if out == "" then out = normalized end
    if #normalized <= 180 then
        if actionableTextCacheCount > 2048 then
            actionableTextCache = {}
            actionableTextCacheCount = 0
        end
        if actionableTextCache[normalized] == nil then actionableTextCacheCount = actionableTextCacheCount + 1 end
        actionableTextCache[normalized] = out
    end
    return out
end

-- Normalization runs on every assistant query and on many registry aliases. Keep the cache
-- bounded and only cache short strings so pasted imports or bug reports cannot grow it forever.
local function CacheNormalize(raw, value)
    if #raw <= 180 then
        if normalizeCacheHot[raw] == nil then
            normalizeCacheHotCount = normalizeCacheHotCount + 1
            if normalizeCacheHotCount > NORMALIZE_CACHE_LIMIT then
                normalizeCacheCold = normalizeCacheHot
                normalizeCacheHot = {}
                normalizeCacheHotCount = 1
            end
        end
        normalizeCacheHot[raw] = value
    end
    return value
end

-- Phrase folding below only ever fires when one of these plain substrings is
-- present; a handful of allocation-free find() probes lets the common case
-- (registry aliases, most user input) skip 18 gsub passes.
local NORMALIZE_FOLD_NEEDLES = {
    "turn", "target", "focus", "cast", "power", "mana",
    "unit", "gruppen", "status", "incoming",
}

Normalize = function(text)
    local raw = tostring(text or "")
    local cached = normalizeCacheHot[raw]
    if cached ~= nil then return cached end
    cached = normalizeCacheCold[raw]
    if cached ~= nil then
        -- Promote so the entry survives the next generation swap.
        return CacheNormalize(raw, cached)
    end
    -- The assistant accepts English/German phrasing plus common typos. These replacements
    -- intentionally happen before phrase folding so the downstream parser can stay literal.
    text = raw:lower()
    -- Charset folding only touches bytes >= 128 plus the listed quote and
    -- punctuation characters; pure ASCII-word strings skip all 17 passes.
    if text:find("[\128-\255\"'`,;:!?%(%)]") then
        text = text:gsub("\195\131\194\164", "ae")
        text = text:gsub("\195\131\194\182", "oe")
        text = text:gsub("\195\131\194\188", "ue")
        text = text:gsub("\195\131\194\159", "ss")
        text = text:gsub("\195\164", "ae")
        text = text:gsub("\195\182", "oe")
        text = text:gsub("\195\188", "ue")
        text = text:gsub("\195\159", "ss")
        text = text:gsub("\228", "ae")
        text = text:gsub("\246", "oe")
        text = text:gsub("\252", "ue")
        text = text:gsub("\196", "ae")
        text = text:gsub("\214", "oe")
        text = text:gsub("\220", "ue")
        text = text:gsub("\223", "ss")
        text = text:gsub("[\"'`]", "")
        text = text:gsub("[,;:!?%(%)]", " ")
    end
    -- Sentence-ending periods/ellipses are conversational punctuation, not
    -- part of a setting alias. Raw input remains available to specialists
    -- that intentionally interpret '..', '...', or the Unicode ellipsis.
    text = text:gsub("%.+%s*$", "")
    text = text:gsub("…%s*$", "")
    text = text:gsub("%s+", " ")
    text = Trim(text)
    if text ~= "" then
        local out = {}
        local changed = false
        for token in text:gmatch("%S+") do
            local replacement = NORMALIZE_WORD_REPLACEMENTS[token]
            if replacement then changed = true end
            out[#out + 1] = replacement or token
        end
        if changed then text = table.concat(out, " ") end
    end
    local needsFold = false
    for i = 1, #NORMALIZE_FOLD_NEEDLES do
        if text:find(NORMALIZE_FOLD_NEEDLES[i], 1, true) then
            needsFold = true
            break
        end
    end
    if needsFold then
        text = text:gsub("%f[%w]turn%s+of%f[%W]", "turn off")
        text = text:gsub("target%s+of%s+target", "targettarget")
        text = text:gsub("target%s+target", "targettarget")
        text = text:gsub("focus%s+target", "focustarget")
        text = text:gsub("cast%s+bar", "castbar")
        text = text:gsub("castbars", "castbar")
        text = text:gsub("cast%s+text", "castbar text")
        text = text:gsub("powerbars", "power bars")
        text = text:gsub("power%s+bars", "power bar")
        text = text:gsub("powerbar", "power bar")
        text = text:gsub("manabars", "mana bars")
        text = text:gsub("mana%s+bars", "mana bar")
        text = text:gsub("manabar", "mana bar")
        text = text:gsub("unit%s+frames", "unitframes")
        text = text:gsub("gruppen%s+frames", "gruppenframes")
        text = text:gsub("status%s+icons", "status icon")
        text = text:gsub("incoming%s+res%s+", "incoming rez ")
        text = text:gsub("incoming%s+res$", "incoming rez")
    end
    return CacheNormalize(raw, Trim(text))
end
A.Normalize = Normalize

local DISPLAY_COLOR_LABEL_FALLBACKS = {
    gray = "grey",
    grau = "grey",
    violet = "purple",
    violett = "purple",
    aqua = "cyan",
    teal = "turquoise",
    weiss = "white",
    schwarz = "black",
    rot = "red",
    gruen = "green",
    blau = "blue",
    gelb = "yellow",
    lila = "purple",
    rosa = "pink",
    tuerkis = "turquoise",
}

if type(A.DisplayColorLabel) ~= "function" then
    function A.DisplayColorLabel(label)
        label = tostring(label or "")
        if label == "" then return "" end
        local normalized = Normalize(label)
        local data = A.GlobalColorSettingsRegistryData
        local aliases = type(data) == "table" and data.COLOR_ALIASES or nil
        if type(aliases) == "table" and aliases[normalized] then return aliases[normalized] end
        return DISPLAY_COLOR_LABEL_FALLBACKS[normalized] or label
    end
end

local EXACT_ONLY_FUZZY_WORDS = {
    ["on"] = true,
    ["off"] = true,
    ["no"] = true,
    ["yes"] = true,
    ["y"] = true,
    ["ja"] = true,
    ["nein"] = true,
    ["x"] = true,
    ["y"] = true,
    ["ui"] = true,
    ["hp"] = true,
    ["id"] = true,
    ["stuck"] = true,
    -- One edit from "state", "status", "stature" and "statues", and it is the
    -- only term identifying the Blizzard Totem Frame. "enable target combat
    -- state indicator" therefore fuzzy-matched the totem lane and enabled the
    -- Totem Frame -- a setting the player never mentioned, on a different page.
    -- A word this collision-prone must be spelled exactly to count. The check is
    -- symmetric, so listing "statue" alone breaks the pair; "state" keeps its
    -- ordinary typo tolerance, which several real control names rely on.
    ["statue"] = true,
}

-- Short control words are too dangerous to fuzzy-match: "on", "off", "x", "y", and IDs
-- frequently decide which setting is touched. Keep fuzzy matching for longer human words.
local function IsWordToken(word)
    return type(word) == "string" and word:match("^[a-z]+$") ~= nil
end

local function Tokenize(text)
    local out = {}
    for token in tostring(text or ""):gmatch("%S+") do
        out[#out + 1] = token
    end
    return out
end

local function IsAdjacentTranspose(a, b)
    local len = #a
    if len ~= #b or len < 3 then return false end
    local first
    for i = 1, len do
        if a:sub(i, i) ~= b:sub(i, i) then
            if first then
                return i == first + 1
                    and a:sub(first, first) == b:sub(i, i)
                    and a:sub(i, i) == b:sub(first, first)
                    and a:sub(i + 1) == b:sub(i + 1)
            end
            first = i
        end
    end
    return false
end

local function IsEditDistanceOne(a, b)
    local la, lb = #a, #b
    if math.abs(la - lb) > 1 then return false end
    if math.min(la, lb) < 5 then return false end
    if a:sub(1, 1) ~= b:sub(1, 1) then return false end

    if la == lb then
        local diff = 0
        for i = 1, la do
            if a:sub(i, i) ~= b:sub(i, i) then
                diff = diff + 1
                if diff > 1 then return false end
            end
        end
        return diff == 1
    end

    local shorter, longer = a, b
    if la > lb then shorter, longer = b, a end
    if longer == shorter .. "s" then return false end
    local i, j, skipped = 1, 1, false
    while i <= #shorter and j <= #longer do
        if shorter:sub(i, i) == longer:sub(j, j) then
            i = i + 1
            j = j + 1
        elseif skipped then
            return false
        else
            skipped = true
            j = j + 1
        end
    end
    return true
end

local function FuzzyWordMatch(word, expected)
    word = tostring(word or "")
    expected = tostring(expected or "")
    if word == expected then return true end
    if EXACT_ONLY_FUZZY_WORDS[word] or EXACT_ONLY_FUZZY_WORDS[expected] then return false end
    if not IsWordToken(word) or not IsWordToken(expected) then return false end
    if math.min(#word, #expected) < 3 then return false end
    if IsAdjacentTranspose(word, expected) then return true end
    return IsEditDistanceOne(word, expected)
end

local fuzzyPhraseCacheText
local fuzzyPhraseCache = {}
local fuzzyPhraseCacheTokens = {}
local fuzzyPhraseTokenCache = {}
local fuzzyPhraseTokenCacheOrder = {}
local fuzzyPhraseTokenCacheHead = 1
local FUZZY_PHRASE_TOKEN_CACHE_LIMIT = 4096

-- Phrase fuzzy matching is scoped to the current input text. Registry aliases are reused
-- heavily, so the bounded token cache saves work without retaining unbounded alias text.
local function CachedFuzzyPhraseTokens(phrase)
    local phraseTokens = fuzzyPhraseTokenCache[phrase]
    if phraseTokens then return phraseTokens end
    phraseTokens = Tokenize(phrase)
    fuzzyPhraseTokenCache[phrase] = phraseTokens
    fuzzyPhraseTokenCacheOrder[#fuzzyPhraseTokenCacheOrder + 1] = phrase
    while #fuzzyPhraseTokenCacheOrder - fuzzyPhraseTokenCacheHead + 1 > FUZZY_PHRASE_TOKEN_CACHE_LIMIT do
        local oldPhrase = fuzzyPhraseTokenCacheOrder[fuzzyPhraseTokenCacheHead]
        fuzzyPhraseTokenCacheOrder[fuzzyPhraseTokenCacheHead] = nil
        fuzzyPhraseTokenCacheHead = fuzzyPhraseTokenCacheHead + 1
        fuzzyPhraseTokenCache[oldPhrase] = nil
    end
    -- Amortized compaction keeps the queue itself bounded without shifting
    -- thousands of entries for every new phrase once the cache is full.
    if fuzzyPhraseTokenCacheHead > FUZZY_PHRASE_TOKEN_CACHE_LIMIT
        and fuzzyPhraseTokenCacheHead > (#fuzzyPhraseTokenCacheOrder / 2)
    then
        local compact = {}
        for i = fuzzyPhraseTokenCacheHead, #fuzzyPhraseTokenCacheOrder do
            compact[#compact + 1] = fuzzyPhraseTokenCacheOrder[i]
        end
        fuzzyPhraseTokenCacheOrder = compact
        fuzzyPhraseTokenCacheHead = 1
    end
    return phraseTokens
end

local function FuzzyPhraseMatch(text, phrase)
    text = Normalize(text)
    phrase = Normalize(phrase)
    if text == "" or phrase == "" or #phrase < 3 then return false end
    if text ~= fuzzyPhraseCacheText then
        fuzzyPhraseCacheText = text
        fuzzyPhraseCache = {}
        fuzzyPhraseCacheTokens = Tokenize(text)
    elseif fuzzyPhraseCache[phrase] ~= nil then
        return fuzzyPhraseCache[phrase]
    end

    local phraseTokens = CachedFuzzyPhraseTokens(phrase)
    if #phraseTokens == 0 or #phraseTokens > 6 then
        fuzzyPhraseCache[phrase] = false
        return false
    end

    local textTokens = fuzzyPhraseCacheTokens
    local matched = false
    if #phraseTokens == 1 then
        for i = 1, #textTokens do
            if FuzzyWordMatch(textTokens[i], phraseTokens[1]) then
                matched = true
                break
            end
        end
    elseif #textTokens >= #phraseTokens then
        for start = 1, (#textTokens - #phraseTokens + 1) do
            local ok = true
            for offset = 1, #phraseTokens do
                if not FuzzyWordMatch(textTokens[start + offset - 1], phraseTokens[offset]) then
                    ok = false
                    break
                end
            end
            if ok then
                matched = true
                break
            end
        end
    end

    fuzzyPhraseCache[phrase] = matched
    return matched
end

A.FuzzyWordMatch = FuzzyWordMatch
A.FuzzyPhraseMatch = FuzzyPhraseMatch

local function HasPhrase(text, phrase)
    text = Normalize(text)
    phrase = Normalize(phrase)
    if phrase == "" then return false end
    return (" " .. text .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

local function ContainsAny(text, words)
    for i = 1, #(words or {}) do
        if HasPhrase(text, words[i]) then return true end
    end
    return false
end

local FUZZY_ALIAS_ANCHOR_IGNORE = {
    a = true,
    an = true,
    ["and"] = true,
    are = true,
    as = true,
    at = true,
    by = true,
    ["for"] = true,
    from = true,
    ["in"] = true,
    is = true,
    my = true,
    of = true,
    on = true,
    the = true,
    to = true,
    with = true,
    set = true,
    change = true,
    make = true,
    turn = true,
}

local fuzzyAliasPrefilterText
local fuzzyAliasPrefilterTokens = {}
local fuzzyAliasPrefilterSet = {}

-- Full-registry fuzzy scans can cooperatively yield while the Dashboard job is
-- active. Keep that temporary capability on the scan coroutine instead of a
-- shared parser flag: a cancelled or failed job can then never leave fuzzy
-- matching enabled for a later request. The weak keys also make abandoned job
-- coroutines self-cleaning without an idle timer or explicit sweep.
local fuzzyAliasCoroutineScopes = setmetatable({}, { __mode = "k" })

function P.SetFuzzyAliasCoroutineScope(co, enabled)
    if type(co) ~= "thread" then return false end
    if enabled == true then
        fuzzyAliasCoroutineScopes[co] = true
    else
        fuzzyAliasCoroutineScopes[co] = nil
    end
    return true
end

function P.FuzzyAliasMatchEnabled()
    if P._allowFuzzyAliasMatch == true then return true end
    if type(coroutine) ~= "table" or type(coroutine.running) ~= "function" then return false end
    local co = coroutine.running()
    return co ~= nil and fuzzyAliasCoroutineScopes[co] == true
end

local function EnsureFuzzyAliasPrefilter(text)
    text = Normalize(text)
    if fuzzyAliasPrefilterText == text then
        return fuzzyAliasPrefilterTokens, fuzzyAliasPrefilterSet
    end
    fuzzyAliasPrefilterText = text
    fuzzyAliasPrefilterTokens = Tokenize(text)
    fuzzyAliasPrefilterSet = {}
    for i = 1, #fuzzyAliasPrefilterTokens do
        fuzzyAliasPrefilterSet[fuzzyAliasPrefilterTokens[i]] = true
    end
    return fuzzyAliasPrefilterTokens, fuzzyAliasPrefilterSet
end

local function FuzzyAliasWorthTrying(text, alias)
    text = Normalize(text)
    alias = Normalize(alias)
    if text == "" or alias == "" then return false end
    local textTokens, textSet = EnsureFuzzyAliasPrefilter(text)
    local aliasTokens = Tokenize(alias)
    if #aliasTokens == 0 or #aliasTokens > 6 or #aliasTokens > #textTokens then return false end

    if #aliasTokens > 1 then
        for i = 1, #aliasTokens do
            local token = aliasTokens[i]
            if not FUZZY_ALIAS_ANCHOR_IGNORE[token] and textSet[token] then return true end
        end
        if #aliasTokens <= 4 and #textTokens <= 10 then
            for i = 1, #aliasTokens do
                local token = aliasTokens[i]
                if not FUZZY_ALIAS_ANCHOR_IGNORE[token] and not EXACT_ONLY_FUZZY_WORDS[token] and #token >= 5 then
                    for j = 1, #textTokens do
                        if FuzzyWordMatch(textTokens[j], token) then return true end
                    end
                end
            end
        end
        return false
    end

    local expected = aliasTokens[1]
    if FUZZY_ALIAS_ANCHOR_IGNORE[expected] or EXACT_ONLY_FUZZY_WORDS[expected] or #expected < 4 then return false end
    local first = expected:sub(1, 1)
    for i = 1, #textTokens do
        local word = textTokens[i]
        if word:sub(1, 1) == first and math.abs(#word - #expected) <= 1 then return true end
    end
    return false
end

local UNIT_ORDER = { "targettarget", "focustarget", "player", "target", "focus", "pet", "boss" }
local GROUP_ORDER = { "mythicraid", "party", "raid" }
local ALL_UNITFRAMES = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
local ALL_GROUPS = { "party", "raid", "mythicraid" }
-- These term buckets are shared across parser shards so "castbar", "class power", "group",
-- and global bar commands do not each invent their own meaning for the same words.
local CLASS_POWER_TERMS = {
    "class power", "class resource", "class resources", "class bar", "resource bar",
    "combo point", "combo points", "holy power", "soul shard", "soul shards",
    "chi", "arcane charge", "arcane charges", "rune", "runes", "essence", "essences",
    "soul fragment", "soul fragments", "maelstrom weapon", "maelstorm weapon",
    "whirlwind", "tip of the spear", "icicle", "icicles",
    "klassenressource", "klassenressourcen", "klassenleiste", "klassen ressourcen",
    "ressourcenleiste", "ressourcen leiste", "kombopunkt", "kombopunkte",
    "heilige kraft", "seelensplitter", "rune", "runen", "essenz", "essenzen",
    "seelenfragment", "seelenfragmente", "mahlstrom waffe", "wirbelwind", "speerspitze", "eiskristalle",
}
local GAMEPLAY_TERMS = {
    "gameplay", "spielhilfe", "combat timer", "combat state", "combat enter", "combat leave",
    "kampf timer", "kampftimer", "kampf text", "kampfstatus", "kampfanzeige",
    "totem frame", "totemframe", "blizzard totem", "statue frame", "totem rahmen", "totemrahmen",
    "statuen rahmen", "statuenrahmen", "combat crosshair",
    "crosshair", "fadenkreuz", "melee range spell", "nahkampf zauber", "reichweiten zauber",
}
local GLOBAL_BARS_TERMS = { "bar texture", "bar background", "bar gradient", "bar gradients", "bars gradient", "gradient direction", "hp gradient", "health gradient", "power gradient", "unitframe bar gradient", "unit frame bar gradient", "absorb bar", "absorb bars", "heal prediction", "heal absorb", "bar outline", "rounded frames", "rounded frame", "rounded texture", "highlight border", "highlight priority", "custom highlight priority", "aggro border", "aggro role filter", "aggro shows for", "dispel border", "purge border", "boss target border", "dispel overlay", "power text" }
local CASTBAR_ROOT_DETAIL_TERMS = {
    "castbar time", "cast time", "time text", "timer",
    "castbar icon", "cast icon", "spell icon",
    "castbar text", "castbar name", "castbar spell name", "spell name", "spell text",
    "interrupt", "interruptible", "kick", "kickable",
    "channel ticks", "channel tick lines", "castbar ticks", "tick lines",
    "glow", "spark", "sparks", "latency", "fill direction", "unified direction", "opposite direction",
    "texture", "background texture", "outline", "border thickness", "shake", "shake strength",
    "empower", "empowered", "stage blink", "spell name shortening", "max spell name length", "reserved spell name space",
    "focus kick", "focus interrupt", "interrupt ready",
}

local PAGE_TEXT_TARGETS = {
    { page = "home", label = "Dashboard", terms = { "dashboard", "home", "main menu", "start page", "overview" } },
    { page = "profiles", label = "Profiles", terms = { "profile", "profiles", "profil", "profile import", "profile export" } },
    { page = "gameplay", label = "Gameplay", terms = GAMEPLAY_TERMS },
    { page = "classpower", label = "Class Resources", terms = CLASS_POWER_TERMS },

    { page = "gf_indicators", label = "Group Status & Indicators", terms = { "group status and indicators", "group indicators", "group indicator", "party indicators", "raid indicators", "group status icons", "raid status icons", "ready check", "summon icon", "role icon", "leader icon", "assist icon" } },
    { page = "gf_auras", label = "Group Auras", terms = { "group auras", "group aura", "party auras", "raid auras", "group buffs", "group debuffs", "party buffs", "raid debuffs" } },
    { page = "gf_bars", label = "Group Dispel Overlay", terms = { "group dispel", "group dispel overlay", "party dispel overlay", "raid dispel overlay", "dispel overlay", "debuff stripe", "group effects", "party effects", "raid effects" } },
    { page = "gf_priority", label = "Priority Frames", terms = { "priority frames", "priority frame", "priority strip", "pinned frames", "pinned frame", "extra party frames", "extra raid frames", "co tank frames", "co-tank frames", "off tank frames", "off-tank frames", "prioritaetsframes", "prioritaetsrahmen" } },
    { page = "gf_layout", label = "Group Layout", terms = { "group layout", "party layout", "raid layout", "group health", "group text", "group resource", "group power", "group bars", "group range", "range fade", "party health", "party text", "party bars", "raid health", "raid text", "raid bars", "health and text", "group settings", "party settings", "raid settings", "group frames", "groupframes", "party frames", "raid frames", "mythic raid", "mythicraid", "gruppenframes", "group", "party", "raid" } },

    { page = "auras3_filters", label = "Aura Filters", terms = { "aura filters", "aura filter", "filters", "blacklist", "aura blacklist", "blocked auras" } },
    { page = "auras3_styling", label = "Aura Style", terms = { "aura style", "aura styling", "aura cooldown text", "aura borders" } },
    { page = "auras3_debuffs", label = "Aura Debuffs", terms = { "debuff", "debuffs", "debuff settings", "debuff style" } },
    { page = "auras3_custom", label = "Custom Auras", terms = { "custom aura", "custom auras", "tracked aura", "spell id aura", "full frame aura", "aura glow" } },
    { page = "auras3_buffs", label = "Aura Buffs", terms = { "buff", "buffs", "buff settings", "buff style" } },
    { page = "auras3", label = "Auras", terms = { "aura", "auras", "auren", "aura settings", "auren einstellungen" } },

    { page = "opt_castbar", label = "Cast Bars", terms = { "castbar", "castbars", "zauberleiste" } },
    { page = "opt_colors", label = "Colors", terms = { "colors", "colours", "color palette", "aura colors", "aura timer colors", "farben" } },
    { page = "opt_fonts", label = "Fonts", terms = { "fonts", "font", "schrift" } },
    { page = "opt_misc", label = "Miscellaneous", terms = { "misc", "miscellaneous", "tooltips", "tooltip", "modules style", "dropdown style" } },
    { page = "opt_bars", label = "Bars", terms = GLOBAL_BARS_TERMS },
    { page = "opt_bars", label = "Bars", terms = { "bars", "textures", "bar settings", "leisten" } },
    { page = "modules", label = "Modules", terms = { "modules", "advanced", "advanced modules", "module settings" } },

    { page = "uf_targettarget", label = "Target of Target", terms = { "targettarget", "target of target", "tot" } },
    { page = "uf_focustarget", label = "Focus Target", terms = { "focustarget", "focus target" } },
    { page = "uf_player", label = "Player", terms = { "player", "spieler" } },
    { page = "uf_target", label = "Target", terms = { "target", "ziel" } },
    { page = "uf_focus", label = "Focus", terms = { "focus", "fokus" } },
    { page = "uf_pet", label = "Pet", terms = { "pet", "begleiter" } },
    { page = "uf_boss", label = "Boss", terms = { "boss", "boss frames", "bossframes" } },
    { page = "search", label = "Search", terms = { "search", "search page", "search results" } },
}

local function AddUnique(out, value)
    if not value then return end
    for i = 1, #out do
        if out[i] == value then return end
    end
    out[#out + 1] = value
end

-- "no target" is a game state, not the Target frame. MSUF names a whole family
-- of load conditions after it -- "Player Hide with No Target", "Boss Hide Out
-- of Combat with No Target" -- and reading the word as a scope put TWO units in
-- play, so "turn on player hide with no target" planned a write to the Target
-- frame's copy as well as the Player's, and the scope-stripped text no longer
-- matched the control's own label. Masked rather than dropped from the alias
-- list: "hide the target frame when i have no target" still finds Target
-- through its other mention.
local function MaskNonScopeTargetIdioms(text)
    text = tostring(text or "")
    if not (text:find("no target", 1, true) or text:find("without", 1, true)
        or text:find("kein ziel", 1, true) or text:find("ohne ziel", 1, true))
    then
        return text
    end
    return (text:gsub("%f[%w]no%s+target%f[%W]", " ")
        :gsub("%f[%w]without%s+a%s+target%f[%W]", " ")
        :gsub("%f[%w]without%s+target%f[%W]", " ")
        :gsub("%f[%w]kein%s+ziel%f[%W]", " ")
        :gsub("%f[%w]ohne%s+ziel%f[%W]", " "))
end

local function DetectUnits(text)
    local units = {}
    text = MaskNonScopeTargetIdioms(text)
    if HasPhrase(text, "all unitframes") or HasPhrase(text, "all unitframe") or HasPhrase(text, "every unitframe") or HasPhrase(text, "alle unitframes") then
        for i = 1, #ALL_UNITFRAMES do AddUnique(units, ALL_UNITFRAMES[i]) end
        return units
    end
    local aliases = A.UnitAliases or {}
    for i = 1, #UNIT_ORDER do
        local unit = UNIT_ORDER[i]
        local list = aliases[unit] or {}
        for j = 1, #list do
            if HasPhrase(text, list[j]) then
                AddUnique(units, unit)
                break
            end
        end
    end
    if #units == 0 then
        if ContainsAny(text, UnitTerms.player) then AddUnique(units, "player") end
        if ContainsAny(text, UnitTerms.target) then AddUnique(units, "target") end
        if ContainsAny(text, UnitTerms.focus) then AddUnique(units, "focus") end
        if ContainsAny(text, UnitTerms.pet) then AddUnique(units, "pet") end
        if ContainsAny(text, UnitTerms.boss) then AddUnique(units, "boss") end
        if ContainsAny(text, UnitTerms.targettarget) then AddUnique(units, "targettarget") end
        if ContainsAny(text, UnitTerms.focustarget) then AddUnique(units, "focustarget") end
    end
    -- Someone who has never opened MSUF does not say "player frame", they say
    -- "my name" or "make my health text bigger". With no frame named anywhere
    -- in the sentence, a first-person possessive can only mean their own frame
    -- -- "make the player name bigger" already worked, so this closes a gap in
    -- wording rather than in capability. Last resort on purpose: any explicitly
    -- named unit above wins, and a named group scope ("my party frames") is
    -- left to DetectGroups instead of being mixed with a unit.
    if #units == 0 and ContainsAny(text, CoreData.FIRST_PERSON_POSSESSIVE_TERMS or {})
        and not ContainsAny(text, CoreData.FIRST_PERSON_POSSESSIVE_BULK_GUARD_TERMS or {})
        and not ContainsAny(text, CoreData.GROUP_FRAME_TERMS or {})
        and not ContainsAny(text, CoreData.PARTY_GROUP_TERMS or {})
        and not ContainsAny(text, CoreData.RAID_GROUP_TERMS or {})
        and not ContainsAny(text, CoreData.MYTHIC_GROUP_TERMS or {})
        -- "my buffs" is not a frame, it is whose aura it is: MSUF names those
        -- controls with the same word ("Highlight My Buffs"), so reading the
        -- possessive as the Player frame retargeted them onto Player Buffs.
        -- Matched as whole phrases, not by the bare word, so "make my name
        -- bigger" keeps resolving to the Player frame.
        and not ContainsAny(text, CoreData.FIRST_PERSON_AURA_OWNERSHIP_TERMS or {})
    then
        AddUnique(units, "player")
    end
    return units
end

local function DetectGroups(text)
    local groups = {}
    if HasPhrase(text, "all group frames") or HasPhrase(text, "all groups") or HasPhrase(text, "alle gruppenframes") then
        for i = 1, #ALL_GROUPS do AddUnique(groups, ALL_GROUPS[i]) end
        return groups
    end
    -- Mythic raid contains the word "raid", so consume its aliases first before testing
    -- the generic raid scope. Otherwise a single command can accidentally target both.
    local mythicAliases = CoreData.MYTHIC_GROUP_TERMS
    local scopeText = text
    if ContainsAny(scopeText, mythicAliases) then
        AddUnique(groups, "mythicraid")
        scopeText = " " .. Normalize(scopeText) .. " "
        for i = 1, #mythicAliases do
            local alias = Normalize(mythicAliases[i])
            if alias ~= "" then scopeText = scopeText:gsub(" " .. alias:gsub("([^%w%s])", "%%%1") .. " ", " ") end
        end
        scopeText = Normalize(scopeText)
    end
    if ContainsAny(scopeText, CoreData.PARTY_GROUP_TERMS) then AddUnique(groups, "party") end
    local raidScopeText = " " .. Normalize(scopeText) .. " "
    local raidDetailTerms = CoreData.RAID_DETAIL_TERMS
    for i = 1, #raidDetailTerms do
        local alias = raidDetailTerms[i]
        alias = Normalize(alias)
        if alias ~= "" then raidScopeText = raidScopeText:gsub(" " .. alias:gsub("([^%w%s])", "%%%1") .. " ", " ") end
    end
    raidScopeText = Normalize(raidScopeText)
    if ContainsAny(raidScopeText, CoreData.RAID_GROUP_TERMS) then AddUnique(groups, "raid") end
    if #groups == 0
        and not ContainsAny(text, CoreData.GROUP_COPY_GUARD_TERMS)
        and ContainsAny(text, CoreData.GROUP_FRAME_TERMS) then
        for i = 1, #ALL_GROUPS do AddUnique(groups, ALL_GROUPS[i]) end
    end
    return groups
end

local function DetectGlobalScope(text)
    if HasPhrase(text, "all scopes") then return "shared" end
    if HasPhrase(text, "party") or HasPhrase(text, "party frames") or HasPhrase(text, "group frames") then return "gf_party" end
    if HasPhrase(text, "raid") or HasPhrase(text, "raid frames") or HasPhrase(text, "mythic raid") or HasPhrase(text, "mythicraid") then return "gf_raid" end
    local units = DetectUnits(text)
    if units[1] then return units[1] end
    if ContainsAny(text, CoreData.GLOBAL_SCOPE_TERMS) then return "shared" end
    return nil
end

local OFF_WORDS = {
    "off", "disable", "disabled", "hide", "hidden", "false", "no",
    "dont", "dont show", "do not", "do not show", "never", "never show",
    -- Everyday synonyms the German list already had ("deaktiviere",
    -- "ausschalten") but English did not, so "deactivate player name" and
    -- "switch off party bold text" were understood as neither on nor off.
    "deactivate", "deactivated", "switch off", "switched off", "shut off",
    "toggle off", "turned off",
    -- How players actually phrase "off" when they are describing a result
    -- rather than naming a state. Deliberately phrases, never the bare verbs:
    -- "stop" and "remove" alone belong to Assistant actions ("stop the class
    -- resource preview", "remove profile") and reading them as a boolean turns
    -- an action request into a setting write.
    "stop showing", "stop the", "get rid of", "no more",
    -- Border/highlight toggles are asked for by their effect: "stop
    -- highlighting frames when i have threat" names OFF without any state
    -- word. Phrases only -- bare "highlight" also names controls (Focus
    -- Highlight, Highlight Priority) and must never read as a polarity.
    "stop highlighting", "quit highlighting", "no longer highlight",
    "aus", "deaktivieren", "deaktiviert", "ausschalten", "ausgeschaltet",
    "deaktiviere", "schalte aus", "mach aus", "verstecken", "versteckt",
    "verstecke", "ausblenden", "ausgeblendet", "blende aus", "nein",
}
local ON_WORDS = {
    "on", "enable", "enabled", "show", "visible", "true", "yes",
    "activate", "activated", "switch on", "switched on", "unhide",
    "toggle on", "turned on", "display", "displayed",
    -- "i want to see the absorb bar" is how a player asks for a toggle without
    -- ever naming a state. Only the phrases that can mean nothing else: bare
    -- "add" and "give me" also start size requests ("add more space between
    -- party frames"), where a boolean reading writes the wrong setting.
    "want to see", "let me see",
    -- Mirror of the OFF highlight phrases: "highlight the frame when
    -- something is attacking me" is an ON request with no state word. Word
    -- boundaries keep this from matching "highlighting" (OFF is also checked
    -- first, so "stop highlighting the frame" stays OFF).
    "highlight the", "highlight when", "highlight my", "start highlighting",
    "an", "aktivieren", "aktiviert", "einschalten", "eingeschaltet",
    "aktiviere", "schalte an", "mach an", "anzeigen", "zeige",
    "zeig", "einblenden", "eingeblendet", "blende ein", "sichtbar",
    "wieder an", "ja",
}

local TARGET_VALUE_CONNECTORS = { " to ", " as ", " is ", " be ", " into ", " value ", " = ", " auf ", " zu ", " als ", " wert " }

local function RawAfterLastConnector(text, connectors)
    text = tostring(text or "")
    if text == "" then return nil end
    connectors = connectors or TARGET_VALUE_CONNECTORS
    local padded = " " .. text .. " "
    local lower = padded:lower()
    local bestEnd
    for i = 1, #connectors do
        local connector = tostring(connectors[i] or ""):lower()
        if connector ~= "" then
            local startAt = 1
            while true do
                local _, endPos = lower:find(connector, startAt, true)
                if not endPos then break end
                if not bestEnd or endPos > bestEnd then bestEnd = endPos end
                startAt = endPos + 1
            end
        end
    end
    local tail = bestEnd and Trim(padded:sub(bestEnd + 1)) or nil
    if tail then tail = Trim(tail:gsub("^the%s+", ""):gsub("^a%s+", "")) end
    if tail == "" then return nil end
    return tail
end

local function TargetAfterLastConnector(text, connectors)
    local tail = RawAfterLastConnector(text, connectors)
    if not tail then return nil end
    tail = Normalize(tail)
    if tail == "" then return nil end
    return tail
end

-- Phrases where "off" belongs to a phrasal verb or a noun rather than stating a
-- polarity. "names are getting cut off" was read as an OFF command and offered
-- to switch the name text off -- the exact opposite of the request, which is
-- that the name is being TRUNCATED and the player wants more of it.
local NON_POLARITY_OFF_PHRASES = {
    "cut off", "cuts off", "cutting off", "cutoff", "cut%-off",
    "off screen", "offscreen", "off center", "off centre", "off%-center",
}
local function MaskNonPolarityOff(text)
    for i = 1, #NON_POLARITY_OFF_PHRASES do
        text = text:gsub(NON_POLARITY_OFF_PHRASES[i], " ")
    end
    return text
end

local function DetectBoolean(text)
    text = MaskNonPolarityOff(text)
    local target = TargetAfterLastConnector(text)
    if target then
        if ContainsAny(target, OFF_WORDS) then return false end
        if ContainsAny(target, ON_WORDS) then return true end
    end
    -- Off wins over on when both appear. Commands like "do not show" include "show", and
    -- treating the negative intent as stronger avoids destructive surprise.
    if ContainsAny(text, OFF_WORDS) then return false end
    if ContainsAny(text, ON_WORDS) then return true end
    return nil
end

local function FirstNumber(text)
    local value = text:match("[-+]?%d+%.?%d*")
    return tonumber(value)
end

function A._ExplicitNumberValue(text)
    text = tostring(text or "")
    local value
    for _, pattern in ipairs({
        "%f[%w]to%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]auf%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]zu%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]as%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]is%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]be%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]value%f[%W]%s+([-+]?%d+%.?%d*)",
        "=%s*([-+]?%d+%.?%d*)",
        -- Players state a size in its unit rather than after a connector:
        -- "make the shield bar 6 pixels tall", "give my frames a 3 pixel outline".
        "([-+]?%d+%.?%d*)%s*pixels",
        "([-+]?%d+%.?%d*)%s*pixel",
        "([-+]?%d+%.?%d*)%s*px",
    }) do
        for numberText in text:gmatch(pattern) do
            value = tonumber(numberText)
        end
    end
    return value
end

function A._LastNumberValue(text)
    local value
    for numberText in tostring(text or ""):gmatch("[-+]?%d+%.?%d*") do
        value = tonumber(numberText)
    end
    return value
end

function A._NumberValueForText(setting, text)
    local explicit = A._ExplicitNumberValue(text)
    if explicit ~= nil then return explicit end
    local hay = setting and (tostring(setting.key or "") .. " " .. tostring(setting.label or "") .. " " .. tostring(setting.attribute or "")) or ""
    if hay:find("%d") then
        -- Digits embedded in the exact control label describe the control, not
        -- the requested value (for example "Party Scale 1-10 Players").
        -- Explicit "to/by/value" forms were already handled above; remove one
        -- literal label occurrence before accepting a connector-less number.
        local valueText = Normalize(text)
        local label = Normalize(setting and setting.label or "")
        local startAt, endAt = label ~= "" and valueText:find(label, 1, true) or nil, nil
        if startAt then
            endAt = startAt + #label - 1
            valueText = valueText:sub(1, startAt - 1) .. " " .. valueText:sub(endAt + 1)
        end
        return A._LastNumberValue(valueText)
    end
    return FirstNumber(text)
end

function A._RelativeNumberAmountForText(text)
    text = tostring(text or "")
    local value
    for _, pattern in ipairs({
        "%f[%w]by%f[%W]%s+([-+]?%d+%.?%d*)",
        "%f[%w]um%f[%W]%s+([-+]?%d+%.?%d*)",
    }) do
        for numberText in text:gmatch(pattern) do
            value = tonumber(numberText)
        end
    end
    return value or FirstNumber(text)
end

local function Compact(text)
    return Normalize(text):gsub("%s+", "")
end

local pluralFoldCache = {}
local pluralFoldCacheCount = 0

local PLURAL_FOLD_KEEP = {
    this = true,
    was = true,
    yes = true,
    dps = true,
}

local function PluralFoldWord(word)
    word = tostring(word or "")
    if word == "" or word:match("^[-+]?%d") or PLURAL_FOLD_KEEP[word] then return word end
    local len = #word
    if len <= 3 then return word end
    if word:sub(-3) == "ies" and len > 4 then
        return word:sub(1, -4) .. "y"
    end
    if word:sub(-4) == "izes" and len > 4 then
        return word:sub(1, -2)
    end
    if word:sub(-2) == "es" then
        local base = word:sub(1, -3)
        if base:sub(-2) == "ss" or base:sub(-2) == "ch" or base:sub(-2) == "sh"
            or base:sub(-1) == "s" or base:sub(-1) == "x" or base:sub(-1) == "z" then
            return base
        end
    end
    if word:sub(-1) == "s" and word:sub(-2) ~= "ss" and word:sub(-2) ~= "us" then
        return word:sub(1, -2)
    end
    return word
end

local function PluralFoldText(text)
    text = Normalize(text)
    local cached = pluralFoldCache[text]
    if cached ~= nil then return cached end
    local out = {}
    for word in text:gmatch("%S+") do
        out[#out + 1] = PluralFoldWord(word)
    end
    local folded = table.concat(out, " ")
    if #text <= 180 then
        if pluralFoldCacheCount > 4096 then
            pluralFoldCache = {}
            pluralFoldCacheCount = 0
        end
        if pluralFoldCache[text] == nil then pluralFoldCacheCount = pluralFoldCacheCount + 1 end
        pluralFoldCache[text] = folded
    end
    return folded
end

local aliasRelationCacheText
local aliasRelationCacheValue
local function AliasRelationText(text)
    text = Normalize(text)
    if text == aliasRelationCacheText then return aliasRelationCacheValue end
    local padded = " " .. text .. " "
    if not (padded:find(" for ", 1, true) or padded:find(" on ", 1, true) or padded:find(" of ", 1, true)
        or padded:find(" vom ", 1, true) or padded:find(" von ", 1, true) or padded:find(" fuer ", 1, true)) then
        aliasRelationCacheText = text
        aliasRelationCacheValue = text
        return text
    end
    local t = padded
    local rel = { "for", "on", "of", "vom", "von", "fuer" }
    for i = 1, #rel do
        t = t:gsub("%f[%w]" .. rel[i] .. "%f[%W]", " ")
    end
    aliasRelationCacheText = text
    aliasRelationCacheValue = Trim(t:gsub("%s+", " "))
    return aliasRelationCacheValue
end

local function TextMatchesAlias(text, relationText, alias)
    if HasPhrase(text, alias) or HasPhrase(relationText or AliasRelationText(text), alias) then return true end
    local normalizedText = Normalize(text)
    local normalizedRelation = Normalize(relationText or AliasRelationText(text))
    local normalizedAlias = Normalize(alias)
    if P.FuzzyAliasMatchEnabled() then
        if FuzzyAliasWorthTrying(normalizedText, normalizedAlias) and FuzzyPhraseMatch(normalizedText, normalizedAlias) then return true end
        if FuzzyAliasWorthTrying(normalizedRelation, normalizedAlias) and FuzzyPhraseMatch(normalizedRelation, normalizedAlias) then return true end
    end
    local foldedText = PluralFoldText(normalizedText)
    local foldedRelation = PluralFoldText(normalizedRelation)
    local foldedAlias = PluralFoldText(alias)
    if foldedText == normalizedText and foldedRelation == normalizedRelation and foldedAlias == normalizedAlias then return false end
    if HasPhrase(foldedText, foldedAlias) then return true end
    return HasPhrase(foldedRelation, foldedAlias)
end

local function ExtractColor(raw, text)
    local rawTarget = RawAfterLastConnector(raw)
    local textTarget = TargetAfterLastConnector(text)
    local function hexFrom(value)
        value = tostring(value or "")
        return value:match("#(%x%x%x%x%x%x)") or value:match("0x(%x%x%x%x%x%x)")
    end
    local function rgbFrom(value)
        return tostring(value or ""):match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    end
    local hex = rawTarget and hexFrom(rawTarget) or nil
    if not hex and not rawTarget then hex = hexFrom(raw) end
    if hex and A.HexToColor then
        return A.HexToColor(hex)
    end
    local rr, gg, bb = rawTarget and rgbFrom(rawTarget) or nil
    if not rr and not rawTarget then rr, gg, bb = rgbFrom(raw) end
    if rr and gg and bb then
        local r, g, b = tonumber(rr) or 255, tonumber(gg) or 255, tonumber(bb) or 255
        if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
        return r, g, b, tostring(rr) .. "," .. tostring(gg) .. "," .. tostring(bb)
    end
    local colorText = textTarget or tostring(text or "")
    rr, gg, bb = tostring(colorText or ""):match("rgb%s+([-+]?%d+%.?%d*)%s+([-+]?%d+%.?%d*)%s+([-+]?%d+%.?%d*)")
    if not rr then
        rr, gg, bb = tostring(colorText or ""):match("r%s+([-+]?%d+%.?%d*)%s+g%s+([-+]?%d+%.?%d*)%s+b%s+([-+]?%d+%.?%d*)")
    end
    if rr and gg and bb then
        local r, g, b = tonumber(rr) or 1, tonumber(gg) or 1, tonumber(bb) or 1
        if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
        return r, g, b, tostring(rr) .. "," .. tostring(gg) .. "," .. tostring(bb)
    end
    if A.ColorFromName then
        for word in tostring(colorText or ""):gmatch("%S+") do
            local r, g, b, label = A.ColorFromName(word)
            if r then return r, g, b, label end
        end
    end
    return nil
end

local function DetectFrameType(text, ctx)
    if ContainsAny(text, CoreData.ALT_MANA_TERMS) then return "altMana" end
    if ContainsAny(text, CLASS_POWER_TERMS) then return "classPower" end
    if ContainsAny(text, GLOBAL_BARS_TERMS) then return "globalBars" end
    if ContainsAny(text, CoreData.COMBAT_TIMER_TERMS) then return "combatTimer" end
    if ContainsAny(text, CoreData.COMBAT_STATE_TERMS) then return "combatState" end
    if ContainsAny(text, CoreData.PLAYER_TOTEMS_TERMS) then return "playerTotems" end
    if ContainsAny(text, CoreData.COMBAT_CROSSHAIR_TERMS) then return "combatCrosshair" end
    if HasPhrase(text, "castbar") or HasPhrase(text, "zauberleiste") then return "castbar" end
    if ContainsAny(text, CoreData.RAID_MARKER_FRAME_TERMS)
        and not ContainsAny(text, CoreData.RAID_MARKER_GROUP_GUARD_TERMS) then
        return "unitframe"
    end
    if HasPhrase(text, "group frames") or HasPhrase(text, "gruppenframes") or HasPhrase(text, "party") or HasPhrase(text, "raid") then return "group" end
    if (HasPhrase(text, "it") or HasPhrase(text, "that") or HasPhrase(text, "das")) and ctx and type(ctx.lastFrameType) == "string" then
        return ctx.lastFrameType
    end
    return "unitframe"
end

local function DetectDirection(text, ctx)
    local function directionIn(segment)
        if ContainsAny(segment, CoreData.DIRECTION_RIGHT_TERMS) then return "right" end
        if ContainsAny(segment, CoreData.DIRECTION_LEFT_TERMS) then return "left" end
        if ContainsAny(segment, CoreData.DIRECTION_DOWN_TERMS) then return "down" end
        if ContainsAny(segment, CoreData.DIRECTION_UP_TERMS) then return "up" end
        return nil
    end
    local target = TargetAfterLastConnector(text)
    local targetDirection = target and directionIn(target)
    if targetDirection then return targetDirection end
    local direction = directionIn(text)
    if direction then return direction end
    if ContainsAny(text, CoreData.DIRECTION_REPEAT_TERMS) and ctx and type(ctx.lastDirection) == "string" then
        return ctx.lastDirection
    end
    return nil
end

local function DetectAttribute(text, frameType)
    if ContainsAny(text, CoreData.RANGE_FADE_TERMS) then return "rangeFade" end
    if ContainsAny(text, CoreData.RAID_MARKER_ATTR_TERMS) then return "raidMarker" end
    if frameType == "castbar" and ContainsAny(text, CoreData.CASTBAR_TERMS) then
        if ContainsAny(text, CoreData.CASTBAR_ICON_TERMS) then return "icon" end
        if ContainsAny(text, CoreData.CASTBAR_TIME_TERMS) then return "time" end
        if ContainsAny(text, CoreData.CASTBAR_TEXT_TERMS) then return "text" end
        if ContainsAny(text, CoreData.CASTBAR_INTERRUPT_TERMS) then return "showInterrupt" end
    end
    if frameType == "castbar" and ContainsAny(text, CoreData.CASTBAR_TERMS) and not ContainsAny(text, CASTBAR_ROOT_DETAIL_TERMS) and not ContainsAny(text, CoreData.CASTBAR_ROOT_GUARD_TERMS) then
        return "enabled"
    end
    if ContainsAny(text, CoreData.HP_TEXT_TERMS) then return "hpText" end
    if ContainsAny(text, CoreData.POWER_TEXT_TERMS) then return "powerText" end
    if ContainsAny(text, CoreData.NAME_TEXT_TERMS) then return "name" end
    if ContainsAny(text, CoreData.WIDTH_TERMS) then return "width" end
    if ContainsAny(text, CoreData.HEIGHT_TERMS) then return "height" end
    if ContainsAny(text, CoreData.ENABLED_VERB_TERMS)
        and ContainsAny(text, CoreData.FRAME_SCOPE_TERMS)
        and not ContainsAny(text, CoreData.ENABLED_EXCLUDE_TERMS) then
        return "enabled"
    end
    return nil
end

local function PageForText(text)
    for i = 1, #PAGE_TEXT_TARGETS do
        local spec = PAGE_TEXT_TARGETS[i]
        if ContainsAny(text, spec.terms) then return spec.page, spec.label end
    end
    return nil, nil
end

local function FrameTypeForPage(page)
    if page == "profiles" then return "profiles" end
    if page == "opt_castbar" then return "castbar" end
    if page == "auras3" or page == "auras3_buffs" or page == "auras3_debuffs" or page == "auras3_custom" or page == "auras3_rendering" or page == "auras3_styling" or page == "auras3_filters" then return "aura" end
    if page == "gf_layout" or page == "gf_bars" or page == "gf_auras" or page == "gf_indicators" or page == "gf_priority" then return "group" end
    if page == "opt_colors" then return "colors" end
    if page == "opt_fonts" then return "fonts" end
    if page == "opt_bars" then return "globalBars" end
    if page == "gameplay" then return "gameplay" end
    if page == "classpower" then return "classPower" end
    if type(page) == "string" and page:find("^uf_") then return "unitframe" end
    return nil
end

local function UnitPageKey(unit)
    if unit == "player" then return "uf_player" end
    if unit == "target" then return "uf_target" end
    if unit == "focus" then return "uf_focus" end
    if unit == "targettarget" then return "uf_targettarget" end
    if unit == "focustarget" then return "uf_focustarget" end
    if unit == "pet" then return "uf_pet" end
    if unit == "boss" then return "uf_boss" end
    return nil
end

-- Classify prompts that describe a problem, request information, or ask for a
-- subjective recommendation before any registry matcher is allowed to build a
-- write plan. This guard is deliberately parser-owned: Submit's low-latency
-- mutation path calls parser helpers directly and therefore cannot rely on the
-- conversational router having run first.
local NON_MUTATING_PROBLEM_TERMS = {
    "gone", "missing", "failed", "failing", "fails", "failure", "error", "errors", "stuck", "broken",
    "filtered out", "filtered", "blacklisted", "blocked", "disappeared", "vanished", "not shown", "not showing",
    "not displayed", "not appearing", "does not show", "doesnt show", "cannot see",
    "cant see", "not visible", "invisible", "hidden", "not working", "does not work", "doesnt work",
    "wrong place", "wrong position", "weird place", "weird position", "out of place",
    "misplaced", "empty", "not filling", "does not fill", "doesnt fill",
    "too faded", "too transparent", "too small",
    "too far apart", "too busy", "hard to see", "hard to read",
    "weg", "fehlt", "fehlen", "fehlende", "fehlender", "fehlendes", "fehlenden", "fehlgeschlagen",
    "verschwunden", "nicht angezeigt", "wird nicht angezeigt",
    "werden nicht angezeigt", "nicht sichtbar", "unsichtbar", "versteckt", "ausgeblendet",
    "geht nicht", "funktioniert nicht", "kaputt",
}

local EXPLICIT_MUTATION_PREFIXES = {
    "set", "change", "make", "adjust", "use", "apply", "turn", "enable", "disable", "show", "hide", "move", "nudge",
    "shift", "increase", "decrease", "raise", "lower", "reset", "restore", "recover",
    "open", "close", "copy", "create", "delete", "remove", "add", "clear", "empty", "toggle",
    "allow", "unhide", "unblacklist", "unblock", "whitelist", "unwhitelist",
    "dont", "do not", "never",
    "setze", "stelle", "mache", "aendere", "verwende", "nutze", "aktiviere", "aktivieren", "deaktiviere", "deaktivieren",
    "einschalten", "ausschalten", "zeige", "anzeigen", "verstecke", "verstecken",
    "einblenden", "ausblenden", "verschiebe", "verschieben", "erhoehe", "senke",
    "zuruecksetzen", "wiederherstellen",
}

local INFORMATION_PREFIXES = {
    "list", "list all", "what", "what are", "what is", "what can", "which", "where",
    "how", "explain", "describe", "tell me", "show me", "help me find", "help me locate",
    "i need", "i want", "i am looking for", "im looking for", "i am trying to find",
    "im trying to find", "zeige mir", "liste", "welche", "welcher", "welches", "wo",
    "wie", "erklaere", "beschreibe", "ich suche", "ich brauche",
}

local INFORMATION_TARGET_TERMS = {
    "option", "options", "setting", "settings", "choice", "choices", "value", "values",
    "available", "supported", "controls", "colors", "colours", "farben", "optionen",
    "einstellungen", "werte", "auswahl",
}

local CAPABILITY_QUESTION_PREFIXES = {
    "can i", "could i", "is there a way to", "kann ich", "koennte ich", "gibt es eine moeglichkeit",
}

local PROCEDURAL_QUESTION_PREFIXES = {
    "how do i", "how can i", "how to", "wie kann ich", "wie mache ich", "wie stelle ich",
    "where can i", "where do i", "where is", "wo kann ich", "wo finde ich", "wo ist",
}

-- These forms ask for information or diagnosis even when they contain words
-- that are also valid setting aliases (for example, "buffs", "hidden", or
-- "filtering"). They must be classified before the immediate mutation path
-- is allowed to build a write plan. Location words stay separate from causal
-- words: "where/wo" means navigation, while "why/warum" means diagnosis.
local READ_ONLY_QUESTION_PREFIXES = {
    "what", "which", "where", "how", "why",
    "was", "welche", "welcher", "welches", "wo", "wie", "warum", "wieso", "weshalb", "wofuer",
}

local READ_ONLY_LOOKUP_PREFIXES = {
    "explain", "describe", "list", "current", "status", "tell me",
    -- "help with X" asks about X; it is not permission to switch X on. The
    -- "i need help with" phrasing has to be listed in full: ActionableText does
    -- not strip "i need", so it never reached the "help with" prefix and
    -- "i need help with Boss Show Leader Icon" was executed as "show leader
    -- icon" -- a question that switched the icon on.
    "help with", "help me with", "help on", "help for", "info about",
    "i need help with", "i need help on", "need help with", "i need help",
    "information about", "i want to know about", "what page is",
    "erklaere", "beschreibe", "liste", "aktuell", "aktueller", "aktuelle", "aktuelles", "status",
    "hilfe zu", "hilfe bei", "info ueber", "infos ueber",
}

local EMBEDDED_QUESTION_PHRASES = {
    "what is", "what are", "what does", "what did", "what can", "what depends", "what affects",
    "which is", "which are", "where is", "where are", "how is", "how are", "how does", "why is", "why are",
    "was ist", "was sind", "welche sind", "welcher ist", "welches ist", "wo ist", "wo sind",
    "wie ist", "wie sind", "warum ist", "warum sind", "wieso ist", "wieso sind",
}

local CAUSAL_QUESTION_PREFIXES = {
    "why", "warum", "wieso", "weshalb", "wofuer",
}

local CAPABILITY_ACTION_TERMS = {
    "turn on", "turn off", "enable", "disable", "show", "hide", "display", "make", "change",
    "set", "move", "detach", "attach", "anchor", "reduce", "increase", "decrease", "reset",
    "delete", "import", "export", "copy", "unlock", "lock",
    "einschalten", "ausschalten", "aktivieren", "deaktivieren", "anzeigen", "verstecken",
    "aendern", "setzen", "verschieben", "abkoppeln", "ankoppeln", "zuruecksetzen", "loeschen",
}

local SUBJECTIVE_SETTING_TERMS = {
    "useless", "unimportant", "irrelevant", "best", "optimal", "automatically",
    "less noisy", "too noisy", "noisy", "less cluttered", "cluttered", "declutter",
    "clean up", "cleaner", "spam", "unwichtig", "wichtig", "nutzlos", "automatisch",
}

local SUBJECTIVE_SETTING_AREAS = {
    "aura", "auras", "buff", "buffs", "debuff", "debuffs", "frame", "frames",
    "unitframe", "unitframes", "ui", "interface", "icon", "icons",
    "auren", "rahmen", "oberflaeche", "symbol", "symbole",
}

local SUBJECTIVE_ACTION_TERMS = {
    "hide", "show", "make", "set", "change", "filter", "only", "remove", "reduce",
    "verstecken", "anzeigen", "aendern", "filtern", "nur", "entfernen", "reduzieren",
}

local REPAIR_PROBLEM_TERMS = {
    "fix", "repair", "please fix", "please repair",
    "repariere", "reparieren", "bitte repariere", "beheben", "bitte beheben",
}

local function HasAnyExactPhrase(text, phrases)
    for i = 1, #(phrases or {}) do
        if HasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local function StartsWithAnyPhrase(text, phrases)
    text = Normalize(text)
    for i = 1, #(phrases or {}) do
        local phrase = Normalize(phrases[i])
        if text == phrase or text:sub(1, #phrase + 1) == phrase .. " " then return true end
    end
    return false
end

local function NonMutatingIntent(text)
    local normalized = Normalize(text)
    if normalized == "" then return nil end
    local actionable = ActionableText(normalized)
    local explicitMutation = StartsWithAnyPhrase(actionable, EXPLICIT_MUTATION_PREFIXES)
    local questionPrefix = StartsWithAnyPhrase(actionable, READ_ONLY_QUESTION_PREFIXES)
    -- Check the raw text too: ActionableText strips conversational leads such
    -- as "i want to", which would delete the very prefix that marks the request
    -- as a lookup ("i want to know about X" became "know about X").
    local lookupPrefix = StartsWithAnyPhrase(actionable, READ_ONLY_LOOKUP_PREFIXES)
        or StartsWithAnyPhrase(normalized, READ_ONLY_LOOKUP_PREFIXES)
    local embeddedQuestion = HasAnyExactPhrase(normalized, EMBEDDED_QUESTION_PHRASES)
    local bareCapability = StartsWithAnyPhrase(actionable, { "can", "could", "does" })
        and not StartsWithAnyPhrase(actionable, { "can you", "could you" })
    -- "Show me X" asks to be shown X, whatever X is; only "show X" without the
    -- pronoun is the command to switch X on. Requiring a page/location word on
    -- top meant "show me Boss Absorb Bar Texture" was treated as an imperative
    -- and wrote to the texture.
    local presentationLookup = StartsWithAnyPhrase(actionable, { "show me", "zeige mir" })
    local explicitImportantAuraFilter = explicitMutation
        and HasAnyExactPhrase(normalized, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" })
        and HasAnyExactPhrase(normalized, {
            "important aura", "important auras", "important buff", "important buffs",
            "important debuff", "important debuffs", "filter to important", "important filter",
        })

    -- Subjective labels describe a desired policy, not one concrete toggle.
    -- This intentionally wins over an imperative prefix ("hide useless buffs").
    if not explicitImportantAuraFilter
        and HasAnyExactPhrase(normalized, SUBJECTIVE_SETTING_TERMS)
        and HasAnyExactPhrase(normalized, SUBJECTIVE_SETTING_AREAS)
        and HasAnyExactPhrase(actionable, SUBJECTIVE_ACTION_TERMS)
    then
        return "subjective"
    end

    -- A repair request that names only a UI area still lacks one concrete
    -- setting/value. Diagnose it first instead of guessing an enable/reset.
    -- Specific workflows such as "fix profile mappings" do not name one of
    -- these visual areas and continue to their explicit action parser.
    -- "Why would I change X" asks for the rationale behind a control; it is not
    -- a report that X is broken. Both start with "why", so the repair branch
    -- claimed it and the request was routed to diagnostics instead of an
    -- explanation.
    local rationaleQuestion = StartsWithAnyPhrase(actionable, {
        "why would i", "why should i", "why do i need", "why would you",
        "why is it useful", "what is the point of", "whats the point of",
    })
    if not rationaleQuestion and not explicitMutation
        and HasAnyExactPhrase(normalized, REPAIR_PROBLEM_TERMS)
        and HasAnyExactPhrase(normalized, SUBJECTIVE_SETTING_AREAS)
    then
        return "problem"
    end
    if rationaleQuestion then return "lookup" end

    -- Fail closed for questions and read-only inspection requests. A genuine
    -- imperative still wins ("set hp text to current", "copy current
    -- profile"), while language wrappers such as "answer in German what is
    -- aura filtering" are caught by the embedded question phrase.
    if (not explicitMutation or presentationLookup)
        and (questionPrefix or lookupPrefix or embeddedQuestion or presentationLookup or bareCapability)
    then
        if StartsWithAnyPhrase(actionable, CAUSAL_QUESTION_PREFIXES)
            or HasAnyExactPhrase(normalized, { "why is", "why are", "warum ist", "warum sind", "wieso ist", "wieso sind" })
            or HasAnyExactPhrase(normalized, NON_MUTATING_PROBLEM_TERMS)
        then
            return "problem"
        end
        if StartsWithAnyPhrase(actionable, PROCEDURAL_QUESTION_PREFIXES)
            or StartsWithAnyPhrase(actionable, CAPABILITY_QUESTION_PREFIXES)
            or bareCapability
            or StartsWithAnyPhrase(actionable, { "how", "wie" })
        then
            return "capability"
        end
        return "lookup"
    end

    if StartsWithAnyPhrase(normalized, CAPABILITY_QUESTION_PREFIXES)
        and HasAnyExactPhrase(normalized, CAPABILITY_ACTION_TERMS)
    then
        return "capability"
    end

    if StartsWithAnyPhrase(normalized, PROCEDURAL_QUESTION_PREFIXES)
        and HasAnyExactPhrase(normalized, CAPABILITY_ACTION_TERMS)
    then
        return "capability"
    end

    if HasAnyExactPhrase(normalized, INFORMATION_TARGET_TERMS)
        and StartsWithAnyPhrase(normalized, INFORMATION_PREFIXES)
        and not explicitMutation
    then
        return "lookup"
    end

    if HasAnyExactPhrase(normalized, NON_MUTATING_PROBLEM_TERMS)
        and not explicitMutation
    then
        return "problem"
    end
    return nil
end

local function NonMutatingIntentAnswer(text)
    local intent = NonMutatingIntent(text)
    if not intent then return nil end
    local normalized = Normalize(text)
    if intent == "subjective" then
        if not HasAnyExactPhrase(normalized, { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "auren" }) then
            local area = HasAnyExactPhrase(normalized, { "raid" }) and "raid frames"
                or (HasAnyExactPhrase(normalized, { "party" }) and "party frames" or "that UI area")
            return {
                kind = "answer",
                status = "info",
                text = "Frame readability planning\nI did not change " .. area .. " from a subjective request. Name the exact source of clutter, such as aura count, text density, indicators, spacing, or opacity, and I can adjust that concrete control without guessing.",
                summary = "Keeps a subjective frame-readability request read-only until the user chooses a concrete control.",
            }
        end
        return {
            kind = "answer",
            status = "info",
            text = "Aura filter planning\nI will not guess which buffs or debuffs are useless or important, because that depends on class, content, and preference. Open Aura Filters to inspect the available live filters, or name an exact filter and scope. I did not change any aura visibility setting.",
            summary = "Keeps a subjective aura request read-only until the user chooses a concrete filter.",
        }
    end
    if intent == "lookup" or intent == "capability" then
        local markerQuestion = HasAnyExactPhrase(normalized, {
            "raid marker", "target marker", "moon", "skull", "star", "circle", "diamond",
            "triangle", "square", "cross",
        })
        local title = markerQuestion and "Raid Marker setting location"
            or (HasAnyExactPhrase(normalized, { "castbar", "cast bar" })
            and HasAnyExactPhrase(normalized, { "interrupt", "kick" })
            and HasAnyExactPhrase(normalized, { "color", "colors", "colour", "colours" })
            and "Cast Bar interrupt color help"
            or "MSUF option help")
        return {
            kind = "answer",
            status = "info",
            text = title .. "\nI treated that as a request to list or explain options, not as a value to write. I did not change a setting. Ask me to open the relevant page, or use an explicit command with a supported value when you want a change.",
            summary = "Keeps an option-list request read-only.",
        }
    end

    local title = "MSUF visibility troubleshooting"
    if HasAnyExactPhrase(normalized, { "totem", "totems", "statue frame" }) then
        title = "Totem Frame visibility help"
    elseif HasAnyExactPhrase(normalized, { "crosshair", "fadenkreuz" }) then
        title = "Combat Crosshair visibility help"
    elseif HasAnyExactPhrase(normalized, { "buff", "buffs", "debuff", "debuffs", "aura", "auras", "auren" }) then
        title = "Aura visibility troubleshooting"
    elseif HasAnyExactPhrase(normalized, { "party", "raid", "boss", "frame", "frames", "rahmen" }) then
        title = "Frame visibility troubleshooting"
    end
    return {
        kind = "answer",
        status = "info",
        text = title .. "\nI treated that as a problem report, not permission to enable, disable, or reset anything. I did not change a setting. Ask me to diagnose the named area, or give an explicit command after you choose the intended fix.",
        summary = "Keeps a natural problem report read-only.",
    }
end

P.Trim = Trim
P.Normalize = Normalize
P.ActionableText = ActionableText
P.FuzzyWordMatch = FuzzyWordMatch
P.FuzzyPhraseMatch = FuzzyPhraseMatch
P.HasPhrase = HasPhrase
P.ContainsAny = ContainsAny
P.UNIT_ORDER = UNIT_ORDER
P.GROUP_ORDER = GROUP_ORDER
P.ALL_UNITFRAMES = ALL_UNITFRAMES
P.ALL_GROUPS = ALL_GROUPS
P.CLASS_POWER_TERMS = CLASS_POWER_TERMS
P.GAMEPLAY_TERMS = GAMEPLAY_TERMS
P.GLOBAL_BARS_TERMS = GLOBAL_BARS_TERMS
P.CASTBAR_ROOT_DETAIL_TERMS = CASTBAR_ROOT_DETAIL_TERMS
P.PAGE_TEXT_TARGETS = PAGE_TEXT_TARGETS
P.AddUnique = AddUnique
P.DetectUnits = DetectUnits
P.DetectGroups = DetectGroups
P.DetectGlobalScope = DetectGlobalScope
P.OFF_WORDS = OFF_WORDS
P.ON_WORDS = ON_WORDS
P.RawAfterLastConnector = RawAfterLastConnector
P.TargetAfterLastConnector = TargetAfterLastConnector
P.DetectBoolean = DetectBoolean
P.FirstNumber = FirstNumber
P.Compact = Compact
P.AliasRelationText = AliasRelationText
P.TextMatchesAlias = TextMatchesAlias
P.PluralFoldWord = PluralFoldWord
P.PluralFoldText = PluralFoldText
P.ExtractColor = ExtractColor
P.DetectFrameType = DetectFrameType
P.DetectDirection = DetectDirection
P.DetectAttribute = DetectAttribute
P.PageForText = PageForText
P.FrameTypeForPage = FrameTypeForPage
P.UnitPageKey = UnitPageKey
P.NonMutatingIntent = NonMutatingIntent
P.NonMutatingIntentAnswer = NonMutatingIntentAnswer
