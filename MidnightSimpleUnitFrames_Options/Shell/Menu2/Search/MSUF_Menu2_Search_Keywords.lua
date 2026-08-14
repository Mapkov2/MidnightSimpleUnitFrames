local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data

local UF_CORE = "frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power hide percent sign hide percent symbol percent sign prozentzeichen"
local UF_STATUS = "status icons status indicators indicator selected indicator level level indicator level text show level"
local function UnitKeywords(subject, statusSubject, extra)
    return "unit frame unitframe " .. subject .. " " .. UF_CORE .. " " .. UF_STATUS .. " " .. statusSubject .. " level anchor level position level layer" .. (extra or "")
end

Data.KEYWORDS = {
    home = "dashboard start support links quick navigation edit mode move drag frames unitframe unit frames reset positions ui scale menu scale msuf frame scale profiles wago discord discord link patreon github curseforge paypal ko-fi slash command addon options minimap help recover recovery display recovery factory reset print help support search changelog release notes scaling",
    uf_player = UnitKeywords("player", "player"),
    uf_target = UnitKeywords("target", "target"),
    uf_targettarget = UnitKeywords("target of target tot", "target of target"),
    uf_focustarget = "unit frame unitframe focus target focus target frame focustarget ft frame basics enable disable hide show width height scale size health portrait text range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp " .. UF_STATUS .. " focus target level anchor level position level layer child focus frame",
    uf_focus = UnitKeywords("focus", "focus", " focus kick interrupt"),
    uf_boss = "unit frame unitframe boss frames bossframe bossframes frame basics enable disable hide show width height scale size health power portrait text castbar boss range fade range check distance check out of range transparency alpha auras buffs debuffs preview anchoring anchor boss layout copy to edit mode move drag position x offset y offset color name hp power " .. UF_STATUS .. " boss level anchor level position level layer",
    uf_pet = UnitKeywords("pet", "pet"),
    gf_layout = "group frames groupframes party raid mythic raid layout health text resource power bar name hp text font size text slot delimiter hide percent sign hide percent symbol show power tank healer damage smooth fill range fade range check distance check out of range offline alpha growth direction sorting role order frame scaling scale transparency opacity anchoring anchor position move drag preview show hide player solo enable disable disabled turn off off hide group frames turn off group frames disable group frames hide group frames turn off raid frames disable raid frames hide raid frames raid frames off turn off party frames disable party frames hide party frames party frames off ausschalten deaktivieren ausblenden width height spacing columns rows sorting role group number visibility",
    gf_bars = "group frames groupframes party raid dispel overlay overlay style overlay priority health bar tint any debuff dispel type debuff stripe stripe edge stripe height stripe opacity effects",
    gf_auras = "group frames groupframes party raid auras buffs debuffs spell indicators tracked spells placed spell icons anchor position x offset y offset icon size max buffs max debuffs spacing layer growth per row hots healer buffs raid debuffs boss debuffs custom spells slots preview frame highlight",
    gf_indicators = "group frames groupframes party raid indicators status icons corner indicators group number focus glow border dispel aggro threat role icon marker raid marker ready check leader assist dead ghost offline afk dnd",
    gf_priority = "group frames groupframes party raid priority frames priority group frames party priority frames priority party frames priority raid frames extra party frames extra raid frames dungeon priority frames duplicate frames pinned players pinned party members pin player tanks automatic tanks tank frames hover hotkey keybind important players healer externals stable strip slots placement attach group mover edit mode",
    opt_bars = "global style bars textures texture gradient gradient direction hp power absorb display heal prediction incoming heals highlight priority prio display overlay highlight borders outline border aggro purge boss target dispel overlay unitframe unit frame debuff tint any debuff dispellable rounded round corners rounded texture rounded frames rounded frame texture rounded unit frames rounded group frames rounded power bars rounded mouseover highlights mouseover bar colors background tint backdrop bg dark mode shared texture opacity alpha health texture power texture frame outline abgerundet abrundung runde kanten ecken abrunden einschalten ausschalten",
    opt_fonts = "global style fonts font family size outline shadow color text readability name hp power health spell cooldown bigger smaller text size name shortening realm names truncate font color",
    auras3 = "aura style styling basics text stack stacks cooldown timer cooldown text stack count font size anchor offset group frame buffs debuffs cooldown swipe",
    auras3_buffs = "buff buffs aura style styling basics text stack stacks cooldown timer cooldown text stack count font size group frame buff settings",
    auras3_debuffs = "debuff debuffs aura style styling basics text stack stacks cooldown timer cooldown text stack count font size group frame debuff settings",
    auras3_custom = "custom aura custom auras unitframe spell id spellid tracked aura exact aura custom icon square bar number full frame effect health tint border glow pulse name overlay frame strata priority",
    auras3_rendering = "aura style styling basics text stack stacks cooldown timer cooldown text stack count font size anchor offset group frame buffs debuffs cooldown swipe",
    auras3_filters = "aura filters blacklist blacklisting filter rules custom filters unit aura blacklist spell id ignore list group frame category blacklist declassified aura categories base filter raid helpful all mine only player dispellable stealable own buffs own debuffs category hiding",
    auras3_styling = "aura style styling appearance live preview tracked auras dummy preview whitelist basics text stack stacks cooldown timer cooldown text stack count font size spacing growth per row anchor offset group frame buffs debuffs custom 1 custom 2 custom 3 icon style full frame health tint border glow pulse name overlay effect strata priority duration bar cooldown swipe",
    opt_castbar = "global style castbar textures outline shake fill direction empowered casts empower stages evoker augmentation devastation preservation hold release interrupt ready focus kick kick cooldown kick unavailable unavailable cast fill unavailable fill interrupt cooldown fill demon hunter demonhunter dh havoc vengeance devour consume magic disrupt counterspell pummel rebuke wind shear mind freeze skull bash muzzle spear hand strike counter shot quell silence name shortening latency spark channel ticks boss castbar target castbar focus castbar player castbar",
    opt_colors = "global style colors class bar colors background backgrond backround bg backdrop tint opacity alpha unitframe colors npc type colors bar colors bar outline border color unit frame border group frame border dispel castbar mouseover highlight color hover highlight color gameplay superellipse color swatches portrait colors power colors font color health color reaction color aura colors aura timer colors aura cooldown colors safe warning urgent own buff own debuff stack count pandemic crosshair colors dark mode custom color missing health white background bar background tint preserve hp color hp track black mana rage energy focus runic power insanity fury pain essence astral power lunar power maelstrom combo points holy power soul shards chi arcane charges runes stagger class power",
    opt_misc = "global style miscellaneous misc language localization localisation locale translation range fade range check range checker distance check out of range unit frame range check ui behavior mouseover highlight hover highlight hover gradient hover border highlight style highlight size tooltip tooltips unitframe tooltip group frame tooltip mouseover tooltip modifier tooltip combat settings general blizzard frames default frames hide blizzard disable blizzard minimap minimap icon target sounds version check startup notices menu behavior menu font msuf menu font options font menu typeface snap edge snap navigation icons nav icons navigation symbols nav symbols navi symbole navigationssymbole",
    classpower = "class resources combo points holy power soul shards chi maelstrom eclipse essence evoker runes runic power stagger brewmaster resource prediction auto hide detached power bar alternative mana behavior style quick actions class power resource bar alternate mana monk druid rogue paladin warlock death knight hide percent sign hide percent symbol percent sign prozentzeichen",
    gameplay = "gameplay combat timer combat state combat enter combat leave combat crosshair crosshair size thickness in range out of range melee range spell totem frame totems statue frame statue icons player totems click cast click cast clickthrough click-through focus target modifier mouseover interaction targeting spells mouse buttons keybind modifier ctrl shift alt fadenkreuz target sound target lost mouseover heal click casting",
    modules = "modules style skins optional modules compatibility portrait decoration minimap compartment addon compartment",
    profiles = "profiles profile management spec profiles specialization auto switch create copy delete reset import export legacy import wago active profile share string profile string backup restore",
}

for _, row in ipairs({
    "DISPEL_DEBUFF_KEYWORDS|MSUF2_SEARCH_DISPEL_DEBUFF_KEYWORDS",
    "HIGHLIGHT_BORDER_KEYWORDS|MSUF2_SEARCH_HIGHLIGHT_BORDER_KEYWORDS",
    "DISPEL_OVERLAY_KEYWORDS|MSUF2_SEARCH_DISPEL_OVERLAY_KEYWORDS",
    "DEBUFF_STRIPE_KEYWORDS|MSUF2_SEARCH_DEBUFF_STRIPE_KEYWORDS",
    "BLIZZARD_DISPEL_KEYWORDS|MSUF2_SEARCH_BLIZZARD_DISPEL_KEYWORDS",
    "UNIT_AURA_DISPEL_KEYWORDS|MSUF2_SEARCH_UNIT_AURA_DISPEL_KEYWORDS",
    "DASHBOARD_RECOVERY_KEYWORDS|MSUF2_SEARCH_DASHBOARD_RECOVERY_KEYWORDS",
    "DASHBOARD_DISCORD_KEYWORDS|MSUF2_SEARCH_DASHBOARD_DISCORD_KEYWORDS",
    "DASHBOARD_SUPPORT_KEYWORDS|MSUF2_SEARCH_DASHBOARD_SUPPORT_KEYWORDS",
    "DASHBOARD_WAGO_KEYWORDS|MSUF2_SEARCH_DASHBOARD_WAGO_KEYWORDS",
    "DASHBOARD_SCALING_KEYWORDS|MSUF2_SEARCH_DASHBOARD_SCALING_KEYWORDS",
    "DASHBOARD_CHANGELOG_KEYWORDS|MSUF2_SEARCH_DASHBOARD_CHANGELOG_KEYWORDS",
}) do
    local key, token = row:match("^([^|]+)|(.+)$")
    Data[key] = { [0] = false, token }
end

Data.CONTROL_KIND_LABEL = {
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

Data.EASTER_EGGS = {
    { name = "don lumen", result = "requested this feature" },
    { name = "Niuki", result = "Is the best Warlock in Retreat" },
    { name = "R41z0r", result = "He makes you better" },
    { name = "Unhalted", result = "South Africa ftw" },
    { name = "Hayato", result = "forgot to bind his heal spells" },
}
