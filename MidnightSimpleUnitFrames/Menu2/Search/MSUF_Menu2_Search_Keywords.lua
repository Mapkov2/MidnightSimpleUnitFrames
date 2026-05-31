local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data

Data.KEYWORDS = {
    home = "dashboard start support links quick navigation edit mode move drag frames unitframe unit frames reset positions ui scale menu scale msuf frame scale profiles wago discord discord link patreon github curseforge paypal ko-fi slash command addon options minimap help recover recovery display recovery factory reset print help support search changelog release notes scaling",
    uf_player = "unit frame unitframe player frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level player level anchor level position level layer",
    uf_target = "unit frame unitframe target frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level target level anchor level position level layer",
    uf_targettarget = "unit frame unitframe target of target tot frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level target of target level anchor level position level layer",
    uf_focustarget = "unit frame unitframe focus target focus target frame focustarget ft frame basics enable disable hide show width height scale size health portrait text range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp status icons status indicators indicator selected indicator level level indicator level text show level focus target level anchor level position level layer child focus frame",
    uf_focus = "unit frame unitframe focus frame basics enable disable hide show width height scale size health power portrait text castbar focus kick interrupt auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level focus level anchor level position level layer",
    uf_boss = "unit frame unitframe boss frames bossframe bossframes frame basics enable disable hide show width height scale size health power portrait text castbar boss range fade range check distance check out of range transparency alpha auras buffs debuffs preview anchoring anchor boss layout copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level boss level anchor level position level layer",
    uf_pet = "unit frame unitframe pet frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power status icons status indicators indicator selected indicator level level indicator level text show level pet level anchor level position level layer",
    gf_layout = "group frames groupframes party raid mythic raid layout growth direction sorting role order frame scaling scale transparency alpha opacity anchoring anchor position move drag tooltip range fade preview show hide player solo enable disable disabled turn off off hide group frames turn off group frames disable group frames hide group frames turn off raid frames disable raid frames hide raid frames raid frames off turn off party frames disable party frames hide party frames party frames off ausschalten deaktivieren ausblenden width height spacing columns rows sorting role group number visibility",
    gf_bars = "group frames groupframes party raid health text power bar name hp text heal prediction absorb display range fade range check distance check out of range layout font size anchor offset opacity alpha smooth fill show power tank healer damage incoming heals shields debuff stripe dispel overlay priority order border priority any debuff dispel type",
    gf_auras = "group frames groupframes party raid auras buffs debuffs anchor position x offset y offset icon size max buffs max debuffs spacing layer growth per row hots healer buffs raid debuffs boss debuffs",
    gf_indicators = "group frames groupframes party raid indicators status icons spell indicators corner indicators group number focus glow border dispel aggro threat role icon custom spells slots preview current show all marker raid marker ready check leader assist dead ghost offline afk dnd",
    opt_bars = "global style bars textures texture gradient gradient direction hp power absorb display heal prediction incoming heals highlight priority prio display overlay highlight borders outline border aggro purge boss target dispel overlay unitframe unit frame debuff tint any debuff dispellable rounded round corners rounded texture rounded frames rounded frame texture rounded unit frames rounded group frames rounded power bars rounded mouseover highlights mouseover bar colors background tint backdrop bg dark mode shared texture opacity alpha health texture power texture frame outline abgerundet abrundung runde kanten ecken abrunden einschalten ausschalten",
    opt_fonts = "global style fonts font family size outline shadow color text readability name hp power health spell cooldown bigger smaller text size name shortening realm names truncate font color",
    auras3 = "auras buffs debuffs enable enabled visibility aura scope group frame auras unit auras click through clickthrough aura position",
    auras3_rendering = "auras buffs debuffs enable enabled visibility aura scope group frame auras unit auras",
    auras3_filters = "aura filters blacklist blacklisting filter rules custom filters unit aura blacklist spell id ignore list group frame category blacklist declassified aura categories base filter raid helpful all mine only player dispellable stealable own buffs own debuffs category hiding",
    auras3_styling = "aura style styling colors text stack stacks cooldown timer colors cooldown text stack count font size anchor offset safe warning urgent own buff own debuff group frame buffs debuffs cooldown swipe",
    opt_castbar = "global style castbar textures outline shake fill direction empowered casts empower stages evoker augmentation devastation preservation hold release interrupt ready focus kick kick cooldown demon hunter demonhunter dh havoc vengeance devour consume magic disrupt counterspell pummel rebuke wind shear mind freeze skull bash muzzle spear hand strike counter shot quell silence name shortening latency spark channel ticks boss castbar target castbar focus castbar player castbar",
    opt_colors = "global style colors class bar colors background backgrond backround bg backdrop tint opacity alpha unitframe colors npc type colors bar colors bar outline border color unit frame border group frame border dispel castbar mouseover highlight gameplay superellipse color swatches portrait colors power colors font color health color reaction color aura colors crosshair colors dark mode custom color missing health white background bar background tint preserve hp color hp track black mana rage energy focus runic power insanity fury pain essence astral power lunar power maelstrom combo points holy power soul shards chi arcane charges runes stagger class power",
    opt_misc = "global style miscellaneous misc language localization localisation locale translation range fade range check range checker distance check out of range unit frame range check ui behavior tooltip tooltips combat settings general blizzard frames default frames hide blizzard disable blizzard update intervals performance minimap minimap icon target sounds version check menu behavior snap edge snap",
    classpower = "class resources combo points holy power soul shards chi maelstrom eclipse essence evoker runes runic power stagger brewmaster resource prediction auto hide detached power bar alternative mana behavior style quick actions class power resource bar alternate mana monk druid rogue paladin warlock death knight",
    gameplay = "gameplay combat crosshair click cast click cast clickthrough click-through focus target modifier mouseover interaction targeting spells mouse buttons keybind modifier ctrl shift alt fadenkreuz melee range spell target sound target lost mouseover heal click casting",
    modules = "modules style skins optional modules compatibility portrait decoration minimap compartment addon compartment",
    profiles = "profiles profile management spec profiles specialization auto switch create copy delete reset import export legacy import wago active profile share string profile string backup restore",
}

Data.DISPEL_DEBUFF_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DISPEL_DEBUFF_KEYWORDS",
}

Data.HIGHLIGHT_BORDER_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_HIGHLIGHT_BORDER_KEYWORDS",
}

Data.DISPEL_OVERLAY_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DISPEL_OVERLAY_KEYWORDS",
}

Data.DEBUFF_STRIPE_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DEBUFF_STRIPE_KEYWORDS",
}

Data.BLIZZARD_DISPEL_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_BLIZZARD_DISPEL_KEYWORDS",
}

Data.UNIT_AURA_DISPEL_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_UNIT_AURA_DISPEL_KEYWORDS",
}

Data.DASHBOARD_RECOVERY_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_RECOVERY_KEYWORDS",
}

Data.DASHBOARD_DISCORD_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_DISCORD_KEYWORDS",
}

Data.DASHBOARD_SUPPORT_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_SUPPORT_KEYWORDS",
}

Data.DASHBOARD_WAGO_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_WAGO_KEYWORDS",
}

Data.DASHBOARD_SCALING_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_SCALING_KEYWORDS",
}

Data.DASHBOARD_CHANGELOG_KEYWORDS = {
    [0] = false,
    "MSUF2_SEARCH_DASHBOARD_CHANGELOG_KEYWORDS",
}

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
