-- Menu2 search query aliases: maps natural search wording to known pages and controls.
-- Data stays deterministic and side-effect free so localized search can reuse canonical terms.
local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data
local Lines = M.Lines
local KeySetFromWords = M.KeySetFromWords

-- Search query alias catalogue.
-- Expands human terms and common misspellings into the canonical search keywords used by the
-- index/query layer. This is declarative data; routing/rendering live in other search shards.
local ZERO_INDEX_ALIASES = KeySetFromWords [[
    debuff debuffs dispel dispels dispell dispellable dispelable cleansing cleanse decurse cure magic curse poison disease bleed
    stealable purge spellsteal aggro threat highlight highlights border borders glow overlay stripe priority
]]

local function TermList(text, zeroIndex)
    local list = {}
    if zeroIndex then list[0] = false end
    for term in tostring(text or ""):gmatch("[^|]+") do
        list[#list + 1] = term
    end
    return list
end

local function AliasMap(rows)
    local aliases = {}
    local function Add(keys, terms)
        for key in tostring(keys or ""):gmatch("[^|]+") do
            aliases[key] = TermList(terms, ZERO_INDEX_ALIASES[key])
        end
    end
    if type(rows) == "string" then
        for line in Lines(rows) do
            local keys, terms = line:match("^([^=]+)=(.*)$")
            Add(keys, terms)
        end
    else
        for i = 1, #rows, 2 do Add(rows[i], rows[i + 1]) end
    end
    return aliases
end

Data.QUERY_ALIASES = AliasMap [[
evoker=empowered|empower|empowered casts|stage|stages|hold cast|release cast|quell|essence|augmentation|devastation|preservation
devastation|preservation=evoker|empowered|empower|empowered casts|essence
augmentation=evoker|empowered|empower|empowered casts|essence|ebon might
empower=empowered|empowered casts|stage|stages|hold cast|release cast
empowered=empower|empowered casts|stage|stages|hold cast|release cast
stage|stages=empowered|empowered casts|blink|castbar
demonhunter=demon hunter|dh|havoc|vengeance|disrupt|consume magic|devour|interrupt|kick|interrupt ready
dh=demon hunter|demonhunter|havoc|vengeance|disrupt|consume magic|devour|interrupt|kick|interrupt ready
havoc|vengeance=demon hunter|demonhunter|dh|disrupt|consume magic|interrupt|kick
devour=consume|consume magic|purge|dispel|disrupt|interrupt|kick|interrupt ready
consume=consume magic|devour|purge|dispel|interrupt|kick
disrupt=demon hunter|demonhunter|dh|interrupt|kick|focus kick|interrupt ready
kick|kicks=interrupt|interrupt ready|focus kick|counterspell|disrupt|pummel|rebuke|wind shear|mind freeze|muzzle|skull bash|spear hand strike|counter shot|quell|silence
interrupt=kick|interrupt ready|focus kick|counterspell|disrupt|pummel|rebuke|wind shear|mind freeze|muzzle|skull bash|spear hand strike|counter shot|quell|silence
interrupts=kick|interrupt|interrupt ready|focus kick
counterspell=interrupt|kick|interrupt ready|focus kick
pummel|rebuke|silence=interrupt|kick|interrupt ready
windshear=wind shear|interrupt|kick|interrupt ready
quell=evoker|interrupt|kick|interrupt ready
cast|casting=castbar|cast bar|spell name|channel
castbar=cast bar|casts|casting|spell name|channel
castbars=castbar|cast bar|casts|casting|spell name|channel
zauberleiste=castbar|cast bar|casts|casting
level=level indicator|level text|show level|unit level|player level|target level|status icons|status indicator|indicator|anchor level|level anchor|position level|level position|x offset|y offset
levels=level|level indicator|level text|show level|status icons|status indicator
lvl=level|level indicator|level text|show level
leveltext=level text|level indicator|show level|status icons|status indicator|anchor|position|x offset|y offset
levelindicator=level indicator|level text|show level|status icons|status indicator|anchor|position|x offset|y offset
statusindicator=status indicator|status icons|indicator|level indicator|level text|enabled|anchor|size|layer|x offset|y offset
statusindicators=status indicators|status icons|indicator|level indicator|level text|enabled|anchor|size|layer|x offset|y offset
indicator=indicators|status icons|status indicator|selected indicator|level indicator|group status and indicators|group indicators
indicators=indicator|status icons|status indicators|selected indicator|level indicator|group status and indicators|group indicators
turn=enable|disable|show|hide|enabled|disabled|visible|hidden
off=disable|hide|disabled|hidden
onoff=enable|disable|show|hide|enabled|disabled
greyed|grayed=disabled|locked|shared setting|unit auras|custom caps|max buffs|max debuffs
showbuffs=show buffs|unit auras|display|shared setting|custom caps|max buffs
maxbuffs=max buffs|buff cap|caps & icons|hide buffs|custom caps
customcaps=custom caps|caps & icons|max buffs|max debuffs|unit override
positioning=position|positions|move|edit mode|x offset|y offset|anchor|anchoring
background=bar background tint|background tint|background opacity|background alpha|backdrop|bg|bar colors|transparency|alpha|unitframe colors
backgrond|backgroud|backround|bakground|hintergrund|backdrop=background|bar background tint|background tint|bg
bg=background|bar background tint|background tint|background opacity|background alpha
alpha=opacity|transparency|fade|background alpha|in combat|out of combat
opacity=alpha|transparency|fade|background opacity|in combat|out of combat
transparent=transparency|alpha|opacity|fade
transparency=alpha|opacity|fade|background
fade=alpha|opacity|transparency|range fade|out of range
fades|faded=fade|alpha|opacity|range fade|out of range
range=range fade|out of range|range alpha|range check|distance|distance check
rangecheck=range check|range fade|out of range|distance check|unit frame range check|out of range alpha|range fade affects
rangechecker|distancecheck=range check|range fade|out of range|distance check|unit frame range check
distance=range|range fade|out of range|range check|distance check|alpha
outofrange=out of range|range fade|range alpha|range check|distance
check=range check|range fade|out of range|distance check|ready check|version check
checker|checking=check|range check|range fade|out of range
reichweite|reichweiten=range|range fade|out of range|range check|distance
reichweitencheck=range check|range fade|out of range|distance check
entfernung=distance|range|range fade|out of range|range check
ausserhalb=out of range|range fade|range check
misc=miscellaneous|global style|tooltips|blizzard frames|language|startup
miscellaneous=misc|global style|tooltips|blizzard frames|language|startup
verschiedenes=misc|miscellaneous|global style|tooltips|blizzard frames|language|startup
move|moving=edit mode|position|positions|drag|x offset|y offset|anchor|anchoring
drag=edit mode|move|position|x offset|y offset
position=positions|move|edit mode|x offset|y offset|anchor|anchoring
positions=position|move|edit mode|x offset|y offset|anchor|anchoring|reset positions
anchor=anchoring|position|move|attach|global anchor|custom anchor
anchoring=anchor|position|move|attach|global anchor|custom anchor
unitframe|unitframes=unit frame|unit frames|player frame|target frame|focus frame|focus target frame|boss frame|frame basics|anchoring|edit mode
unitfram|unitfrme=unitframe|unit frame|unit frames|frame basics|anchoring|edit mode
player=player frame|playerframe
target=target frame|targetframe
focus=focus frame|focusframe
focustarget=focus target frame|focus target|ft frame
pet=pet frame|petframe
pettarget=pet target frame|pettarget|pet target|pet target position
fram=frame|unit frame|frames|frame basics
frame=unit frame|frames|unitframe|frame basics
frames=unit frames|unitframe|frame basics|edit mode
playerframe=player frame|move player frame|drag player frame|player position|unit frame|frame basics|anchoring|edit mode
targetframe=target frame|move target frame|drag target frame|target position|unit frame|frame basics|anchoring|edit mode
focusframe=focus frame|move focus frame|drag focus frame|focus position|unit frame|frame basics|anchoring|edit mode|focus kick
focustargetframe=focus target frame|move focus target frame|drag focus target frame|focus target position|unit frame|frame basics|anchoring|edit mode
petframe=pet frame|move pet frame|drag pet frame|pet position|unit frame|frame basics|anchoring|edit mode
bossframe=boss frame|boss frames|unit frame|boss layout
arenaframe=arena frame|arena frames|unit frame|arena layout
arenaframes=arena frame|arena frames|unit frame|arena layout|arena preview
bossframes=boss frame|boss frames|unit frame|boss layout|boss preview
size=width|height|scale|frame basics|frame scaling
resize=size|width|height|scale|frame basics|frame scaling
bigger|smaller=size|scale|width|height|font size
big=bigger|size|scale|width|height|font size
small=smaller|size|scale|width|height|font size|text size|icon size
scale=size|frame scaling|menu scale|ui scale
smooth|smoothfill=smooth fill|smooth health fill|smooth power bar|bar animation|soft fill|fluid fill|weiche fuellung
softfill|fluidfill|fuellung|fuellen=smooth fill|smooth health fill|smooth power bar|bar animation|weiche fuellung
rounded=rounded texture|rounded frame texture|rounded frames|round corners|unit frames|group frames|power bars|mouseover highlights|bars
round=rounded|rounded texture|rounded frames|round corners|corners|bars
corners=rounded|rounded texture|rounded frames|round corners|frame corners|bars
corner=corners|rounded|round corners|frame corners
roundedframes=rounded frames|rounded frame texture|rounded texture|unit frames|group frames|bars
roundedtexture=rounded texture|rounded frame texture|rounded frames|bars
rund|runde|abrunden|abrundung|abgerundet|abgerundete|abgerundeten=rounded|rounded frames|round corners|rounded texture|bars
kanten|ecken=corners|rounded|round corners|rounded frames|bars
einschalten|anschalten|aktivieren=enable|turn on|on|show
ausschalten|abschalten|deaktivieren=disable|turn off|off|hide
weich|weiche|weichen|sanft|sanfte=smooth fill|smooth health fill|smooth power bar|soft fill|weiche fuellung
fluessig|fluessige=smooth fill|smooth health fill|smooth power bar|fluid fill|weiche fuellung
relleno|llenado|suave|remplissage|riempimento|preenchimento=smooth fill|soft fill|fluid fill|bar animation
fluido|fluida|fluide=smooth fill|fluid fill|bar animation
animacion|animacao=bar animation|smooth fill
doux|douce|morbido|morbida=smooth fill|soft fill|bar animation
hp=health|health text|health bar|leben
health=hp|health text|health bar|life|leben
leben=health|hp|health bar|health text
name|names=name text|text|font|name shortening
shorten|shortened|shortens|shortening|truncated|kuerzen|gekuerzt|namenskuerzung|namenskurzung|kuerzung=name shortening|short names|truncate names|max name length
override|overrides=custom settings|font override|scope override|group frame override|shared changes
fontoverride=font override|custom font settings|name shortening|shared changes
scopeoverride=scope override|font override|custom settings|shared changes
groupoverride=group frame override|font override|group frames|name shortening
text=font|fonts|name text|health text|power text|spell name
font=fonts|text|font size|outline|shadow
fonts=font|text|font size|outline|shadow
mana=power|power bar|alternative mana|alt mana
power=mana|power bar|class resources|resource
resource|resources=class resources|classpower|power|combo points|essence
profile=profiles|import|export|copy profile|spec profiles|wago
profiles=profile|import|export|copy profile|spec profiles|wago
import=profiles|profile|import string|wago
export=profiles|profile|export string|copy profile|wago
wago=profiles|import|export|profile string
reload=refresh|apply|not updating|profile|reset
reset=reset positions|factory reset|profile reset|profiles
broken=not updating|reset positions|profile reset|reload|factory reset
broke=broken|not updating|reset positions|profile reset|reload
bugged=broken|not updating|reload|reset positions
wrong=not updating|colors|profile|reset
missing=not visible|hidden|invisible|gone|load conditions
gone=missing|not visible|hidden|invisible
invisible=not visible|hidden|alpha|transparency|range fade
hidden=hide|show|enable|disable|not visible
show=enable|visible|not hidden
hide=disable|hidden|not visible
disabled|enabled=enable|show|frame basics
offscreen=reset positions|move|edit mode|position
overlap=text layer|position|anchor|offset|frame level
overlapping=overlap|text layer|position|anchor|offset
lag|fps=performance|auras|cooldown|filters
bad=wrong|broken|performance|lag|fps
performance=auras|cooldown|filters|range fade
combat=combat lockdown|in combat|out of combat|alpha|settings
lockdown=combat lockdown|combat|protected frames|reload
raidframes=group frames|groupframes|raid frames|raid frame|raid|party|layout|group layout|anchoring|move raid frames|disable raid frames|hide raid frames|turn off raid frames|raid frames off
partyframes=group frames|groupframes|party frames|party frame|party|raid|layout|group layout|anchoring|move party frames|disable party frames|hide party frames|turn off party frames|party frames off
gruppenframes|group|groupframes=group frames|party|raid|layout|disable group frames|hide group frames|turn off group frames
raid=group frames|groupframes|raid frames|raid frame|layout|party|anchoring|move raid frames|disable raid frames|hide raid frames|turn off raid frames|raid frames off
party=group frames|groupframes|party frames|party frame|layout|raid|anchoring|move party frames|disable party frames|hide party frames|turn off party frames|party frames off
tank|tanks=tank role|show tank power|tank power|tank power bar|role power|group frames
healer|healers=healer role|show healer power|healer power|healer power bar|healer mana|role power|group frames
dps|damager|damage=damage role|damager role|show dps power|show damager power|dps power|damager power|dps power bar|role power|group frames
debuff=debuffs|auras|aura|buffs|dispellable debuffs|dispel border|dispel overlay|debuff stripe|magic|curse|poison|disease|any debuff
debuffs=debuff|auras|aura|buffs|dispellable debuffs|dispel border|dispel overlay|debuff stripe|magic|curse|poison|disease|any debuff
buff=buffs|auras|aura|debuffs
buffs=buff|auras|aura|debuffs
aura=auras|buffs|debuffs|cooldown|aura filters
auras=aura|buffs|debuffs|cooldown|aura filters
hot=hots|healer buffs|own buffs|aura indicators|group buffs
hots=hot|healer buffs|own buffs|aura indicators|group buffs
own|personal=only mine|own buffs|own debuffs|player only|aura filters
spellid|spellids=spell id|aura blacklist|aura filters
bossdebuff|bossdebuffs=boss debuffs|raid debuffs|aura filters
dispel=dispel border|dispel overlay|dispellable debuffs|dispel border detects|any dispel-type debuff|any debuff|magic|curse|poison|disease|cleanse|decurse|group status and indicators|group indicators|highlight borders
dispels=dispel|dispel border|dispel overlay|dispellable debuffs|magic|curse|poison|disease
dispell=dispel|dispel border|dispel overlay|dispellable debuffs|cleanse|decurse
dispellable=dispellable debuffs|dispel border detects|dispellable by me|any dispel-type debuff|magic|curse|poison|disease
dispelable=dispellable|dispellable debuffs|dispel border detects
cleansing=cleanse|dispel|dispellable debuffs|magic|curse|poison|disease
cleanse=dispel|dispellable debuffs|magic|curse|poison|disease
decurse=curse|dispel|dispellable debuffs
cure=cleanse|dispel|poison|disease|dispellable debuffs
magic=dispel|dispellable debuffs|dispel border detects|dispel test type
curse=dispel|decurse|dispellable debuffs|dispel border detects|dispel test type
poison|disease=dispel|cleanse|dispellable debuffs|dispel border detects|dispel test type
bleed=debuff|any debuff|dispel test type
stealable=auras|buffs|purge|dispel|spellsteal|purge border|offensive dispel
purge=dispel|stealable|auras|buffs|purge border|spellsteal|offensive dispel
spellsteal=stealable|purge|purge border|offensive dispel|buffs
pandemic=colors|auras|cooldown text|debuffs|timer
timer=cooldown text|aura timers|cast time|combat timer
cooldown=cooldown text|cooldown swipe|aura timers|interrupt ready
cooldowns=cooldown|cooldown text|cooldown swipe|aura timers|interrupt ready
blacklist=ignore list|global ignore list|hide aura|hide buff|hide debuff|unit auras|aura filters
ignore=ignore list|global ignore list|blacklist|hide aura|hide buff|hide debuff|unit auras
absorb=absorbs|absorb display|heal prediction|health
absorbs=absorb|absorb display|heal prediction|health
heal=heal prediction|incoming heals|health|healer
aggro=threat|aggro|aggro border|highlight borders|indicators|highlight priority
threat=aggro|threat border|highlight borders|indicators|highlight priority
blizzard|default|blizzardframes=blizzard frames|default frames|hide blizzard|disable blizzard
unlock=edit mode|move|drag|frames unlocked|lock frames
locked=edit mode|move|drag|frames locked|lock frames|disabled|shared setting|custom caps
solo=show solo|show player solo|party frames solo|group frames
self=player|show player|hide player|party frames
tooltip=tooltips|unitframe tooltips|group frame tooltips|mouseover tooltip
tooltips=tooltip|unitframe tooltips|mouseover tooltip
language=locale|localization|translation|sprache
sprache=language|locale|localization|translation
click=click cast|clickthrough|click-through|mouse|mouseover|target modifier
clickcast=click cast|click casting|mouse|targeting
clickthrough=click-through|click through|mouse|unitframe tooltips
mouseover=mouse|mouseover highlight|tooltip|click cast|targeting
menu=dashboard|menu scale|ui scale|search|support
window=menu|dashboard|reset positions|ui scale
ui=ui scale|menu scale|dashboard
unit|units=unit frame|unit frames|unitframe|frame basics
einheit=unit|unit frame|unitframe
einheiten=unit|unit frames|unitframe
einheitenfenster=unit frame|unitframe|frames
spieler=player|player frame|playerframe
spielerframe=player frame|playerframe|unit frame
ziel=target|target frame|targetframe
zielframe=target frame|targetframe
zielziel=target of target|targettarget|tot
tot=target of target|targettarget|target target
targettarget=target of target|tot|target target
fokusziel|focusziel|ft=focus target|focustarget|focus target frame
fokus=focus|focus frame|focusframe|focus kick
fokusframe=focus frame|focusframe|focus kick
begleiter|haustier=pet|pet frame|petframe
enable=show|visible|frame basics|aktivieren
disable=hide|hidden|frame basics|deaktivieren
visible=show|enable|sichtbar
aktivieren=enable|show|visible
deaktivieren|abschalten=disable|hide|hidden
anzeigen=show|visible|enable
ausblenden=hide|hidden|disable
ausgegraut=disabled|locked|shared setting|custom caps|unit auras
grau=disabled|locked|shared setting
sichtbar=visible|show|enable
unsichtbar=invisible|hidden|alpha|transparency
versteckt=hidden|hide|disable
verschieben=move|drag|position|edit mode|anchor
bewegen=move|drag|position|edit mode
ziehen=drag|move|edit mode
verankern|anker=anchor|anchoring|position
koordinaten=x offset|y offset|position|anchor
editmode=edit mode|move|drag|position
loadconditions=load conditions|visibility|show|hide
breite=width|size|resize|frame basics
hoehe=height|size|resize|frame basics
groesse=size|resize|scale|width|height
skalierung=scale|size|frame scaling|ui scale
layout=group frames|frame basics|growth|sorting|anchoring
sorting=sort|role order|group frames|layout
sortierung=sorting|role order|group frames|layout
growth=growth direction|layout|group frames
spalten=columns|layout|group frames
reihen=rows|layout|auras|group frames
rolle=role|role icon|sorting|tank|healer|dps
role=role icon|sorting|tank|healer|dps
groupnumber=group number|indicators|group frames
tank|dps=role icon|group status and indicators|group indicators|sorting
healer=role icon|healer buffs|group status and indicators|group indicators
healthbar=health bar|health|hp|bar colors
powerbar=power bar|power|mana|class resources
lebensbalken=health bar|health|hp
energieleiste=power bar|power|mana
manabar=mana|power bar|power
color=colors|bar colors|unitframe colors|class colors
colours=colors|color|bar colors
farbe|farben=colors|color|bar colors|class colors
klassfarbe|classcolor=class color|class colors|health color
reaction=reaction color|npc type colors|colors
npc=npc type colors|reaction color|colors
highlight=highlights|mouseover highlight|highlight borders|dispel highlight|aggro border|target border|focus highlight|highlight priority|colors|bars
highlights=highlight|highlight borders|dispel highlight|aggro border|target border|focus highlight|highlight priority|mouseover highlight
border=borders|highlight borders|frame outline|dispel border|aggro border|purge border|target border|focus highlight|group border
borders=border|highlight borders|frame outline|dispel border|aggro border|purge border|target border|focus highlight|group border
glow=focus glow|highlight borders
overlay=dispel overlay|unitframe dispel overlay|overlay style|overlay opacity|health bar tint
stripe=debuff stripe|stripe edge|stripe height|stripe opacity|debuff filter
priority=highlight priority|dispel priority|aggro priority|target priority|focus priority
fontsize=font size|text size|fonts|text
textsize=text size|font size|fonts|text
schrift=font|fonts|text|font size
schriftart=font|fonts|font family
schriftgroesse=font size|text size|fonts
namen=names|name text|name shortening
ueberschreiben|ueberschreibung=override|font override|custom settings
realm|server=realm names|name shortening|short names
truncate=name shortening|short names|max name length
nameshortening=name shortening|short names|truncate names|realm names
healthtext=health text|hp text|text|fonts
powertext=power text|mana text|text|fonts
nametext=name text|text|fonts|name shortening
stufe|stufen=level|level indicator|level text|show level|status icons
stufentext=level text|level indicator|show level|status icons|anchor|position
levelanzeige=level indicator|level text|show level|status icons|anchor|position
statusanzeige=status indicator|status icons|indicator|level indicator
portrait=portraits|portrait mode|class icon|2d portrait
portraits=portrait|portrait mode|class icon
avatar|portraet=portrait|portraits|class icon
portraitdeko=portrait decoration|modules|style
castbalken|zauberbalken=castbar|cast bar|casting
spell=spell name|castbar|auras|spell id
spellname=spell name|castbar|name shortening
interruptready=interrupt ready|focus kick|kick|castbar
kanal|kanalisieren=channel|channel ticks|castbar
unterbrechen=interrupt|kick|focus kick|interrupt ready
fokuskick=focus kick|interrupt|kick|castbar
stack=stacks|aura stack count|auras
stacks=stack|aura stack count|auras
stapel=stacks|stack|auras
cooldowntext=cooldown text|timer|auras
swipe=cooldown swipe|auras|cooldown
staerkungszauber=buffs|buff|auras
zauber=spell|auras|castbar|spell id
gruppe|gruppen|gruppenrahmen|gruppenfenster=group frames|groupframes|party|raid|layout|disable group frames|hide group frames|turn off group frames
raidframe=raid frames|raidframes|group frames|layout|disable raid frames|hide raid frames|turn off raid frames|raid frames off
partyframe=party frames|partyframes|group frames|layout|disable party frames|hide party frames|turn off party frames|party frames off
schlachtzug=raid|raid frames|group frames|disable raid frames|hide raid frames|turn off raid frames
myhtic=mythic|mythic plus|party frames|dungeon
mythicplus|mplus=mythic plus|party frames|dungeon|keystone
keystone|schluesselstein|schlüsselstein=mythic plus|party frames|dungeon
mythic=mythic raid|raid|group frames
readycheck|bereitschaft=ready check|status icons|group status and indicators|group indicators
statusicon|statusicons=status icons|indicators|dead|offline|ready check
marker=raid marker|markers|indicators
raidmarker=raid marker|marker|indicators
leader=leader icon|status icons|indicators
assist=assist icon|status icons|indicators
offline=offline icon|status icons|indicators
afk=afk icon|status icons|indicators
dead=dead icon|ghost|status icons|indicators
profil=profile|profiles|import|export
importieren=import|profiles|wago|profile string
exportieren=export|profiles|profile string
kopieren=copy profile|profiles|import|export
teilen=share profile|export|wago
backup=profiles|export|copy profile
restore=profiles|import|reset
minimap|minimapicon|minimapbutton=minimap icon|minimap button|miscellaneous
minikarte=minimap|minimap icon|miscellaneous
sound=sounds|target sound|target lost|miscellaneous
sounds=sound|target sound|target lost|miscellaneous
targetsound=target sound|target lost|sounds|miscellaneous
versioncheck=version check|miscellaneous|startup
menuscale=menu scale|dashboard|ui scale
uiscale=ui scale|dashboard|menu scale
unitauras=unit auras|auras|buffs|debuffs
globalstyle=global style|bars|fonts|colors|castbar|miscellaneous
standardframes=default frames|blizzard frames|hide blizzard
crosshair=combat crosshair|gameplay|melee range spell|range check
fadenkreuz=crosshair|combat crosshair|gameplay|melee range spell
melee=melee range spell|crosshair|range check
maus=mouse|mouseover|click cast|targeting
maustaste=mouse buttons|click cast|targeting
klick|klicken=click|click cast|clickthrough|targeting
heilung=heal|healer|click cast|mouseover
mouseoverheal=mouseover heal|click cast|healing
ruckelt|haengt=lag|fps|performance
langsam=slow|performance|lag|fps
cpu=performance|auras|cooldown
speicher=performance|auras|profiles
optimieren=performance|auras|fps
classpower=class resources|power|resource
classresourceshape|classpowershape|resourceshape=class resources|shape|class resource shape|combo point shape
combopointshape|combopointsshape=combo points|class resources|shape|class resource shape
playerpowershape|detachedpowershape|powerbarshape=player power shape|detached power bar|shape|class resources
orb|orbs|manaorb|powerorb|manaorbs|powerorbs|manaball|powerball|powersphere=player power shape|detached power bar|orb|orb size|power orb
connectedpowerbar|managedpowerbar|managedpowertext|classresourcepowerbar=class resources|detached power bar|power text|anchor to class resource|sync width
playerhpbar|duplicatehp|secondhp|secondhealth|classresourcehealth|classresourcehp=class resources|player hp bar|health text|foreground texture|background texture|anchor|width mode|hp shape|follow player power|orb size|hp color|class color|dark mode|hp gradient|smooth fill|use player hp text|shared text
playerhpshape|secondhpshape|duplicatehpshape|healthorb|hporb=class resources|player hp bar|hp shape|follow player power|round|crystal|orb|orb size
playerhpcolor|secondhpcolor|duplicatehpcolor|classresourcehpcolor=class resources|player hp bar|hp color|class color|dark mode|hp gradient|global color
healthduplicate|doppelhp|zweitehp|zweitehealth|lebenzweimal=class resources|player hp bar|second player hp bar|health text
shapepreset|shapepresets|stylepreset|stylepresets=class resources|shape|class resource shape|preset|clean dots|gems|hex pips|compact
cleandots|dots|dotpips=class resources|shape|class resource shape|circle|shape preset
gems|gemshape=class resources|shape|class resource shape|diamond|shape preset
hexpips|hexshape=class resources|shape|class resource shape|hex|shape preset
autofit|autofitpips|fitpips=class resources|width mode|auto fit pips|shape alignment
pipalignment|shapealignment|alignpips=class resources|shape alignment|class resource alignment
klassenressourcen|klassenressource=class resources|classpower|resource
combopoints=combo points|class resources|rogue
soulshards=soul shards|class resources|warlock
runen=runes|runic power|class resources
eclipse=eclipse|class resources|druid
stagger=stagger|class resources|brewmaster
]]


-- Later blocks add words to a key; they never replace its meaning. Assigning
-- used to swap "color" (bar, unit and class colors) for castbar terms.
local function AddAliasTerms(key, terms)
    local list = Data.QUERY_ALIASES[key]
    if not list then
        Data.QUERY_ALIASES[key] = TermList(terms)
        return
    end
    local seen = {}
    for i = 1, #list do seen[list[i]] = true end
    for term in tostring(terms or ""):gmatch("[^|]+") do
        if not seen[term] then
            seen[term] = true
            list[#list + 1] = term
        end
    end
end

Data.CONTROL_QUERY_TARGETS = {
    ["tracked buffs"] = { pageKey = "suite_cooldownManager" },
    ["received buffs"] = { pageKey = "suite_cooldownManager" },
    ["raid"] = { pageKey = "gf_layout" },
    ["schlachtzug"] = { pageKey = "gf_layout" },
    ["ridden mount"] = { settingSuffix = "tooltipDetails.unitMount" },
    ["mount"] = { settingSuffix = "tooltipDetails.unitMount" },
    ["nebenhand"] = { settingKey = "swingTimers.main.offhandLane" },
    ["2d portrait"] = { settingSuffix = ".portraitRender" },
    ["2d portraet"] = { settingSuffix = ".portraitRender" },
    ["2d porträt"] = { settingSuffix = ".portraitRender" },
    ["drachen spiegeln"] = { settingSuffix = ".portraitDragonFlip" },
    ["drachenspiegeln"] = { settingSuffix = ".portraitDragonFlip" },
    ["dragon flip"] = { settingSuffix = ".portraitDragonFlip" },
    ["zaehne zusammenbeissen"] = { settingKey = "bars.showIgnorePain" },
    ["zähne zusammenbeißen"] = { settingKey = "bars.showIgnorePain" },
    ["zahne zusammenbeissen"] = { settingKey = "bars.showIgnorePain" },
    ["mana vorschau"] = { settingKey = "bars.manaUpcomingCost" },
    ["mana preview"] = { settingKey = "bars.manaUpcomingCost" },
    ["profilvariante"] = { controlSuffix = ".variant.select" },
    ["profile variants"] = { controlSuffix = ".variant.select" },
    ["profile variant"] = { controlSuffix = ".variant.select" },
    ["profilsynchronisierung"] = { controlSuffix = ".sync.group.select" },
    ["profil synchronisieren"] = { controlSuffix = ".sync.group.select" },
    ["profile sync"] = { controlSuffix = ".sync.group.select" },
    ["profile synchronization"] = { controlSuffix = ".sync.group.select" },
    ["profile synchronisation"] = { controlSuffix = ".sync.group.select" },
    ["variante aufnehmen"] = { controlSuffix = ".variant.values.edit" },
}


-- Compact native wording for common feature searches. Search routing still resolves only indexed controls/pages.
AddAliasTerms("zielframe", "target frame|target size|target scale")
AddAliasTerms("zielrahmen", "target frame|target size|target scale")
AddAliasTerms("targetframe", "target frame|target size|target scale")
AddAliasTerms("targetframesize", "target frame|target size|target scale")
AddAliasTerms("castbarfarbe", "castbar|cast bar color|castbar color")
AddAliasTerms("partyframeshidden", "party frames|group frames|layout|hidden|visibility")
AddAliasTerms("taschen", "bags|backpack|inventory")
AddAliasTerms("sacs", "bags|backpack|inventory")
AddAliasTerms("bolsas", "bags|backpack|inventory")
AddAliasTerms("가방", "bags|backpack|inventory")
AddAliasTerms("背包", "bags|backpack|inventory")
AddAliasTerms("сумки", "bags|backpack|inventory")
AddAliasTerms("minikarte", "minimap|minimap icon|miscellaneous")
AddAliasTerms("minicarte", "minimap|minimap icon|miscellaneous")
AddAliasTerms("мини карта", "minimap|minimap icon|miscellaneous")
AddAliasTerms("小地图", "minimap|minimap icon|miscellaneous")
AddAliasTerms("小地圖", "minimap|minimap icon|miscellaneous")
AddAliasTerms("cooldowns", "cooldown|cooldown manager|cooldown timers")
AddAliasTerms("재사용 대기시간", "cooldown|cooldown manager|cooldown timers")
AddAliasTerms("冷却", "cooldown|cooldown manager|cooldown timers")
AddAliasTerms("冷卻", "cooldown|cooldown manager|cooldown timers")

Data.SEARCH_EXAMPLES = {
    enUS = { {"Target size", "target size", "uf_target"}, {"Cast bar color", "castbar color", "opt_castbar"}, {"Hidden party frames", "party frames hidden", "gf_layout"}, {"Bags", "bags", "suite_bags"}, {"Minimap", "minimap icon"}, {"Cooldowns", "cooldown timers", "suite_cooldownManager"} },
    enGB = { {"Target size", "target size", "uf_target"}, {"Cast bar colour", "castbar colour", "opt_castbar"}, {"Hidden party frames", "party frames hidden", "gf_layout"}, {"Bags", "bags", "suite_bags"}, {"Minimap", "minimap icon"}, {"Cooldowns", "cooldown timers", "suite_cooldownManager"} },
    deDE = { {"Zielframe Größe", "zielframe groesser", "uf_target"}, {"Zauberleistenfarbe", "castbar farbe", "opt_castbar"}, {"Versteckte Gruppenrahmen", "gruppenrahmen verborgen", "gf_layout"}, {"Taschen", "taschen", "suite_bags"}, {"Minikarte", "minikarte", nil}, {"Abklingzeiten", "abklingzeiten", "suite_cooldownManager"} },
    esES = { {"Tamaño del objetivo", "tamaño marco objetivo", "uf_target"}, {"Color de la barra de lanzamiento", "color barra lanzamiento", "opt_castbar"}, {"Marcos de grupo ocultos", "marcos de grupo ocultos", "gf_layout"}, {"Bolsas", "bolsas", "suite_bags"}, {"Minimapa", "minimapa", nil}, {"Reutilizaciones", "tiempos de reutilización", "suite_cooldownManager"} },
    esMX = { {"Tamaño del objetivo", "tamaño marco objetivo", "uf_target"}, {"Color de la barra de lanzamiento", "color barra lanzamiento", "opt_castbar"}, {"Marcos de grupo ocultos", "marcos de grupo ocultos", "gf_layout"}, {"Bolsas", "bolsas", "suite_bags"}, {"Minimapa", "minimapa", nil}, {"Reutilizaciones", "tiempos de reutilización", "suite_cooldownManager"} },
    frFR = { {"Taille de la cible", "taille cadre cible", "uf_target"}, {"Couleur de barre d'incantation", "couleur barre incantation", "opt_castbar"}, {"Cadres de groupe cachés", "cadres groupe cachés", "gf_layout"}, {"Sacs", "sacs", "suite_bags"}, {"Mini-carte", "minicarte", nil}, {"Temps de recharge", "temps de recharge", "suite_cooldownManager"} },
    itIT = { {"Dimensione del bersaglio", "dimensione riquadro bersaglio", "uf_target"}, {"Colore barra di lancio", "colore barra lancio", "opt_castbar"}, {"Riquadri gruppo nascosti", "riquadri gruppo nascosti", "gf_layout"}, {"Borse", "borse", "suite_bags"}, {"Minimappa", "minimappa", nil}, {"Tempi di recupero", "tempi di recupero", "suite_cooldownManager"} },
    ptBR = { {"Tamanho do alvo", "tamanho quadro alvo", "uf_target"}, {"Cor da barra de lançamento", "cor barra lancamento", "opt_castbar"}, {"Quadros de grupo ocultos", "quadros grupo ocultos", "gf_layout"}, {"Bolsas", "bolsas", "suite_bags"}, {"Minimapa", "minimapa", nil}, {"Recargas", "recarga", "suite_cooldownManager"} },
    ruRU = { {"Размер цели", "размер рамки цели", "uf_target"}, {"Цвет полосы заклинания", "цвет полосы заклинания", "opt_castbar"}, {"Скрытые групповые рамки", "скрытые рамки группы", "gf_layout"}, {"Сумки", "сумки", "suite_bags"}, {"Миникарта", "мини карта", nil}, {"Перезарядка", "перезарядка", "suite_cooldownManager"} },
    koKR = { {"대상 프레임 크기", "대상 프레임 크기", "uf_target"}, {"시전 바 색상", "시전 바 색상", "opt_castbar"}, {"숨겨진 파티 프레임", "숨겨진 파티 프레임", "gf_layout"}, {"가방", "가방", "suite_bags"}, {"미니맵", "미니맵", nil}, {"재사용 대기시간", "재사용 대기시간", "suite_cooldownManager"} },
    zhCN = { {"目标框体大小", "目标大小", "uf_target"}, {"施法条颜色", "施法条颜色", "opt_castbar"}, {"隐藏的小队框体", "隐藏小队框体", "gf_layout"}, {"背包", "背包", "suite_bags"}, {"小地图", "小地图", nil}, {"冷却", "冷却", "suite_cooldownManager"} },
    zhTW = { {"目標框架大小", "目標大小", "uf_target"}, {"施法條顏色", "施法條顏色", "opt_castbar"}, {"隱藏的小隊框架", "隱藏小隊框架", "gf_layout"}, {"背包", "背包", "suite_bags"}, {"小地圖", "小地圖", nil}, {"冷卻", "冷卻", "suite_cooldownManager"} },
}

-- These examples explicitly advertise the Suite's cooldown manager. Keep that
-- owner ahead of generic aura cooldown controls after native synonym expansion.
-- Exact targets only rank records that the installed provider actually exposes.
for _, examples in pairs(Data.SEARCH_EXAMPLES) do
    for _, example in ipairs(examples) do
        if example[3] == "suite_cooldownManager" then
            Data.CONTROL_QUERY_TARGETS[example[2]] = { pageKey = example[3] }
        end
    end
end

-- Common localized query components used by the example phrases above.
-- A color word adds color terms only: a bare "castbar" there matched every castbar row.
AddAliasTerms("groesser", "size|font size|width|height|scale")
AddAliasTerms("größer", "size|font size|width|height|scale")
AddAliasTerms("farbe", "color|castbar color")
AddAliasTerms("gruppenrahmen", "party frames|group frames|layout")
AddAliasTerms("verborgen", "hidden|party frames|group frames")
AddAliasTerms("tamaño", "size|width|height|scale")
AddAliasTerms("marco", "frame|frames|party frames")
AddAliasTerms("objetivo", "target|target frame|target size")
AddAliasTerms("color", "color|castbar color")
AddAliasTerms("ocultos", "hidden|party frames|group frames")
AddAliasTerms("ocultosgrupo", "hidden|party frames|group frames")
AddAliasTerms("grupo", "group|party frames|group frames")
AddAliasTerms("taille", "size|width|height|scale")
AddAliasTerms("cadre", "frame|frames|party frames")
AddAliasTerms("cible", "target|target frame|target size")
AddAliasTerms("couleur", "color|castbar color")
AddAliasTerms("cachés", "hidden|party frames|group frames")
AddAliasTerms("dimensione", "size|width|height|scale")
AddAliasTerms("riquadro", "frame|frames|party frames")
AddAliasTerms("bersaglio", "target|target frame|target size")
AddAliasTerms("colore", "color|castbar color")
AddAliasTerms("nascosti", "hidden|party frames|group frames")
AddAliasTerms("gruppo", "group|party frames|group frames")
AddAliasTerms("tamanho", "size|width|height|scale")
AddAliasTerms("quadro", "frame|frames|party frames")
AddAliasTerms("alvo", "target|target frame|target size")
AddAliasTerms("cor", "color|castbar color")
AddAliasTerms("размер", "size|width|height|scale")
AddAliasTerms("рамки", "frame|frames|party frames")
AddAliasTerms("цели", "target|target frame|target size|цель")
AddAliasTerms("цвет", "color|castbar color")
AddAliasTerms("полосы", "castbar|cast bar|castbar color")
AddAliasTerms("скрытые", "hidden|party frames|group frames")
AddAliasTerms("группы", "group|party frames|group frames")
AddAliasTerms("대상", "target|target frame|target size")
AddAliasTerms("프레임", "frame|frames|party frames")
AddAliasTerms("크기", "size|width|height|scale")
AddAliasTerms("시전", "castbar|cast bar|castbar color")
AddAliasTerms("바", "castbar|cast bar|castbar color")
AddAliasTerms("색상", "color|castbar color")
AddAliasTerms("숨겨진", "hidden|party frames|group frames")
AddAliasTerms("파티", "party|party frames|group frames")
AddAliasTerms("目标框体大小", "target frame|target size|scale")
AddAliasTerms("施法条颜色", "castbar|castbar color|color")
AddAliasTerms("隐藏小队框体", "hidden|party frames|group frames")
AddAliasTerms("目標框架大小", "target frame|target size|scale")
AddAliasTerms("施法條顏色", "castbar|castbar color|color")
AddAliasTerms("隱藏小隊框架", "hidden|party frames|group frames")

-- CJK query segments used by the compact locale examples.
AddAliasTerms("目标", "target|target frame")
AddAliasTerms("框体", "frame|unit frame")
AddAliasTerms("大小", "width|height|scale|size")
AddAliasTerms("施法条", "castbar|cast bar")
AddAliasTerms("颜色", "color|castbar color")
AddAliasTerms("隐藏", "hidden|hide|party frames")
AddAliasTerms("小队", "party|party frames|group frames")
AddAliasTerms("目標", "target|target frame")
AddAliasTerms("框架", "frame|unit frame")
AddAliasTerms("顏色", "color|castbar color")
AddAliasTerms("隱藏", "hidden|hide|party frames")
AddAliasTerms("隊伍", "party|party frames|group frames")


AddAliasTerms("施法条颜色", "castbar|cast bar|interrupt")
AddAliasTerms("施法條顏色", "castbar|cast bar|interrupt")


-- Natural sentence grammar and compact domain nouns for localized questions.
local localizedHardStops = [[
estan mis sono dove sont mes le la les du des ma mia mie miei onde estao minhas meus где мои 를 을 은 는 이 가 에서 에 어디에 있나요 설정은 设置在哪里 設定在哪裡 在哪里 在哪裡 我想
]]
for word in localizedHardStops:gmatch("%S+") do Data.STOP_WORDS[word] = true end
local localizedSoftStops = [[ quiero cambiar je veux changer voglio cambiare quero mudar хочу изменить 변경하고 싶어요 ]]
for word in localizedSoftStops:gmatch("%S+") do Data.QUERY_SOFT_STOP_WORDS[word] = true end
local AddLocalizedAlias = AddAliasTerms
AddLocalizedAlias("borse", "bags|backpack|inventory")
AddLocalizedAlias("borsa", "bags|backpack|inventory")
AddLocalizedAlias("bolsa", "bags|backpack|inventory")
AddLocalizedAlias("bolsas", "bags|backpack|inventory")
AddLocalizedAlias("sac", "bags|backpack|inventory")
AddLocalizedAlias("sacs", "bags|backpack|inventory")
AddLocalizedAlias("taschen", "bags|backpack|inventory")
AddLocalizedAlias("сумки", "bags|backpack|inventory")
AddLocalizedAlias("가방", "bags|backpack|inventory")
AddLocalizedAlias("背包", "bags|backpack|inventory")
AddLocalizedAlias("recarga", "cooldown|cooldown manager|cooldown timers")
AddLocalizedAlias("recargas", "cooldown|cooldown manager|cooldown timers")
AddLocalizedAlias("перезарядка", "cooldown manager|cooldown timers|менеджер восстановления|времени восстановления")


-- Additional inflected sentence fillers, kept separate from feature vocabulary.
for word in ([[ ich den will meinen meinem meiner vom too am put side by ]]):gmatch("%S+") do Data.STOP_WORDS[word] = true end
for word in ([[ möchte moechte machen mache aendere sehe sehen ]]):gmatch("%S+") do Data.QUERY_SOFT_STOP_WORDS[word] = true end
-- Everyday names describe the setting, without assigning a unit or changing it.
AddAliasTerms("lebenszahl", "health text|health|text|font size")
AddAliasTerms("lebenszahlen", "health text|health|text|font size")
AddAliasTerms("numbers", "text|health text|font size")
AddAliasTerms("zahl", "text|font size")
AddAliasTerms("zahlen", "text|font size")
AddAliasTerms("spielerbalken", "player frame|playerframe")
AddAliasTerms("zielbalken", "target frame|targetframe")
AddAliasTerms("klein", "size|scale|width|height|font size")
AddAliasTerms("kleiner", "size|scale|width|height|font size")
AddAliasTerms("durchsichtig", "opacity|alpha|transparency")
AddAliasTerms("durchsichtigkeit", "opacity|alpha|transparency")
AddAliasTerms("gruppenmitglieder", "party|group frames|party frames")
AddAliasTerms("members", "party|group frames|party frames")
AddAliasTerms("nebeneinander", "horizontal|growth|group layout")
AddAliasTerms("rueckgaengig", "undo|redo")

local HUMAN_REQUEST_WORDS = "i|my|want|how|where|why|make|too|put|hide|show|numbers|lebenszahl|lebenszahlen|"
    .. "ich|mein|meine|meinen|meinem|wie|wo|warum|machen|moechte|will|zu|ausblenden|anzeigen"
local HUMAN_DETAIL_WORDS = "buff|buffs|debuff|debuffs|aura|auras|portrait|portraits|portraet|castbar|cast bar|cast bars|zauberleiste|"
    .. "indicator|indicators|symbol|symbols|icon|icons|background|hintergrund"
local HUMAN_OTHER_CONTEXT_WORDS = "chat|minimap|minikarte|nameplate|nameplates|name plate|namensplaketten|bags|bag|taschen|"
    .. "damage meter|dps meter|schadensmesser|action bar|action bars|aktionsleisten|cooldown|cooldowns|cdm|abklingzeiten|"
    .. "quest|quests|tooltip|cursor|data texts|datatexts|rune|runes|combo|essence|klassenressourcen"
local HUMAN_QUALIFIER_WORDS = "only|except|when|while|during|mine|not mine|filter|filters|friendly|enemy|combat|"
    .. "nur|ausser|ausgenommen|wenn|waehrend|meine buffs|meine debuffs|eigene|fremde|kampf|freundlich|feindlich"
local HUMAN_RESOURCE_WORDS = "power|mana|resource|resources|ressource|ressourcen|energy|energie|rage|wut|focus power|fokusenergie"

-- Finite native vocabulary shared by ordinary search and conversational intent.
-- esMX shares Spanish vocabulary; enGB shares English. Locale packs still own labels.
local NATIVE_QUERY_WORDS = {
    { -- enUS
        size = "larger|smaller|enlarge|shrink",
        name = "name|names",
        grammar = "do|does|can|could|please",
        targettarget = "target s target|target of my target",
        focustarget = "focus s target|target of my focus",
        pettarget = "pet s target|target of my pet",
        auraDetail = "timer|timers|border|borders|swipe|glow|stack|stacks|duration",
        tab = "tab|tabs",
        suiteDetail = "button|buttons|drawer|artwork|shadow|shadows|tooltip|color|colour",
    },
    { -- deDE
        player = "spielerrahmen|spielerrahmens",
        target = "zielrahmen|zielrahmens|ziels",
        focus = "fokus",
        size = "vergrößern|verkleinern|größere|kleinere",
        request = "möchte|möchten|machen|warum|wo|wie",
        grammar = "meines|meiner|möchte|möchten",
        name = "namen|namens",
        health = "lebensbalken|lebenszahlen",
        numbers = "lebenszahlen|zahlen",
        chat = "chat|chatfenster",
        bags = "taschen|rucksack",
        minimap = "minikarte",
        targettarget = "ziel meines ziels|ziel des zieles",
        focustarget = "ziel meines fokus",
        pettarget = "ziel meines begleiters",
        qualifier = "freundlich|freundliche|feindlich|feindliche|gegnerisch|gegnerische",
        auraDetail = "timer|rand|raender|leuchten|stapel|dauer|filter",
        tab = "tab|tabs|reiter",
        suiteDetail = "knopf|knoepfe|schaltflaeche|schaltflaechen|schublade|grafik|schatten|tooltip|farbe",
    },
    { -- esES
        request = "quiero|cómo|dónde|por qué|ocultar|mostrar|muy",
        grammar = "quiero|puedo|hacer|sean|mi|mis|que|los|las|del|en",
        player = "jugador|jugadora",
        target = "objetivo",
        focus = "foco",
        pet = "mascota",
        boss = "jefe|jefes",
        arena = "arena",
        targettarget = "objetivo del objetivo|objetivo de mi objetivo",
        focustarget = "objetivo del foco|objetivo de mi foco",
        pettarget = "objetivo de la mascota|objetivo de mi mascota",
        group = "grupo|banda|miembros del grupo",
        size = "tamaño|agrandar|aumentar|grande|grandes|pequeño|pequeños",
        text = "texto|fuente|letra|letras",
        numbers = "números|número",
        health = "vida|salud|barra de salud|barra de vida",
        name = "nombre|nombres",
        move = "mover|desplazar",
        missing = "no veo|no aparece|invisible|desaparecido",
        opacity = "transparente|transparencia|opacidad",
        buff = "beneficio|beneficios",
        debuff = "perjuicio|perjuicios",
        hide = "ocultar|esconder",
        show = "mostrar",
        horizontal = "uno al lado del otro|horizontal",
        vertical = "vertical|uno debajo del otro",
        qualifier = "solo|sólo|solamente|excepto|cuando|combate|mis beneficios|mis perjuicios|propios|amigo|amigos|" ..
            "amistoso|amistosos|enemigo|enemigos|enemiga|enemigas",
        resource = "maná|poder|energía|ira|recurso|recursos",
        icon = "icono|iconos|indicador|indicadores",
        castbar = "barra de lanzamiento|barra de hechizos",
        portrait = "retrato",
        background = "fondo",
        chat = "chat",
        minimap = "minimapa|minimapa cuadrado",
        bags = "bolsas|bolsa|mochila|inventario",
        nameplates = "placas de nombre|placas de nombres",
        meter = "medidor de daño|medidor de sanación",
        actionbars = "barras de acción|barra de acción",
        cooldowns = "tiempos de reutilización|tiempo de reutilización",
        quests = "misiones|rastreador de misiones",
        classresources = "recursos de clase",
        auraDetail = "temporizador|temporizadores|borde|bordes|brillo|acumulaciones|duración|filtro|filtros",
        tab = "pestaña|pestañas",
        suiteDetail = "botón|botones|cajón|arte|sombra|sombras|descripción|color",
    },
    { -- frFR
        request = "je|veux|comment|où|pourquoi|masquer|afficher|trop",
        grammar = "je|veux|puis|peux|rendre|mettre|ma|mes|mon|le|la|les|du|de|des",
        player = "joueur|joueuse",
        target = "cible",
        focus = "focus|focalisation",
        pet = "familier",
        boss = "boss",
        arena = "arène",
        targettarget = "cible de la cible|cible de ma cible",
        focustarget = "cible du focus|cible de mon focus",
        pettarget = "cible du familier|cible de mon familier",
        group = "groupe|raid|membres du groupe",
        size = "taille|agrandir|augmenter|réduire|grand|grande|petit|petite",
        text = "texte|police|lettres",
        numbers = "chiffres|nombres",
        health = "vie|santé|barre de vie|barre de santé",
        name = "nom|noms",
        move = "déplacer|bouger",
        missing = "ne vois pas|ne voit pas|invisible|disparu|disparue",
        opacity = "transparent|transparente|transparence|opacité",
        buff = "amélioration|améliorations",
        debuff = "affaiblissement|affaiblissements",
        hide = "masquer|cacher",
        show = "afficher|montrer",
        horizontal = "côte à côte|horizontal|horizontalement",
        vertical = "vertical|verticalement",
        qualifier = "uniquement|seulement|sauf|quand|pendant|combat|mes améliorations|mes affaiblissements|ami|amis|amical|" ..
            "amicale|ennemi|ennemis|ennemie|ennemies",
        resource = "mana|puissance|énergie|rage|ressource|ressources",
        icon = "icône|icônes|indicateur|indicateurs",
        castbar = "barre d'incantation|barre de lancement",
        portrait = "portrait",
        background = "arrière-plan|fond",
        chat = "chat|discussion",
        minimap = "minicarte|mini-carte",
        bags = "sacs|sac|sac à dos|inventaire",
        nameplates = "barres de nom|plaques de nom",
        meter = "compteur de dégâts|compteur de soins",
        actionbars = "barres d'action|barre d'action",
        cooldowns = "temps de recharge|recharges",
        quests = "quêtes|suivi des quêtes",
        classresources = "ressources de classe",
        auraDetail = "minuteur|minuteurs|bordure|bordures|lueur|charges|durée|filtre|filtres",
        tab = "onglet|onglets",
        suiteDetail = "bouton|boutons|tiroir|illustration|ombre|ombres|infobulle|couleur",
    },
    { -- itIT
        request = "voglio|come|dove|perché|nascondere|mostrare|troppo",
        grammar = "voglio|posso|rendere|mettere|mio|mia|il|lo|gli|i|le|del|della|di|sul",
        player = "giocatore|giocatrice",
        target = "bersaglio",
        focus = "focus|focalizzazione",
        pet = "famiglio|mascotte",
        boss = "boss",
        arena = "arena",
        targettarget = "bersaglio del bersaglio|bersaglio del mio bersaglio",
        focustarget = "bersaglio del focus|bersaglio del mio focus",
        pettarget = "bersaglio del famiglio|bersaglio del mio famiglio",
        group = "gruppo|incursione|membri del gruppo",
        size = "dimensione|dimensioni|ingrandire|aumentare|ridurre|grande|piccolo|piccola",
        text = "testo|carattere|caratteri",
        numbers = "numeri|numero",
        health = "salute|vita|barra della salute",
        name = "nome|nomi",
        move = "spostare|muovere",
        missing = "non vedo|non appare|invisibile|scomparso",
        opacity = "trasparente|trasparenza|opacità",
        buff = "beneficio|benefici",
        debuff = "penalità|effetti negativi",
        hide = "nascondere|nascondi",
        show = "mostrare|mostra",
        horizontal = "uno accanto all'altro|orizzontale|orizzontalmente",
        vertical = "verticale|verticalmente",
        qualifier = "solo|soltanto|tranne|quando|durante|combattimento|miei benefici|miei effetti|amico|amici|amichevole|" ..
            "amichevoli|nemico|nemici|nemica|nemiche",
        resource = "mana|potenza|energia|rabbia|risorsa|risorse",
        icon = "icona|icone|indicatore|indicatori",
        castbar = "barra di lancio|barra degli incantesimi",
        portrait = "ritratto",
        background = "sfondo",
        chat = "chat",
        minimap = "minimappa",
        bags = "borse|borsa|zaino|inventario",
        nameplates = "barre dei nomi|targhette",
        meter = "misuratore dei danni|misuratore delle cure",
        actionbars = "barre delle azioni|barra delle azioni",
        cooldowns = "tempi di recupero|tempo di recupero",
        quests = "missioni|tracciatore delle missioni",
        classresources = "risorse di classe",
        auraDetail = "timer|bordo|bordi|bagliore|cariche|durata|filtro|filtri",
        tab = "scheda|schede",
        suiteDetail = "pulsante|pulsanti|cassetto|grafica|ombra|ombre|suggerimento|colore",
    },
    { -- ptBR
        request = "quero|como|onde|por que|ocultar|mostrar|muito",
        grammar = "quero|posso|deixar|colocar|meu|minha|meus|minhas|o|a|os|as|do|da|de|no",
        player = "jogador|jogadora",
        target = "alvo",
        focus = "foco",
        pet = "ajudante|mascote",
        boss = "chefe|chefes",
        arena = "arena",
        targettarget = "alvo do alvo|alvo do meu alvo",
        focustarget = "alvo do foco|alvo do meu foco",
        pettarget = "alvo do ajudante|alvo do meu ajudante",
        group = "grupo|raide|membros do grupo",
        size = "tamanho|aumentar|diminuir|ampliar|grande|pequeno|pequena",
        text = "texto|fonte|letras",
        numbers = "números|número",
        health = "vida|saúde|barra de vida",
        name = "nome|nomes",
        move = "mover|deslocar",
        missing = "não vejo|não aparece|invisível|desaparecido",
        opacity = "transparente|transparência|opacidade",
        buff = "benefício|benefícios|bônus",
        debuff = "penalidade|penalidades",
        hide = "ocultar|esconder",
        show = "mostrar|exibir",
        horizontal = "lado a lado|horizontal|horizontalmente",
        vertical = "vertical|verticalmente",
        qualifier = "apenas|somente|exceto|quando|durante|combate|meus benefícios|meus bônus|amigo|amigos|amigável|" ..
            "amigáveis|inimigo|inimigos|inimiga|inimigas",
        resource = "mana|poder|energia|raiva|recurso|recursos",
        icon = "ícone|ícones|indicador|indicadores",
        castbar = "barra de lançamento|barra de feitiços",
        portrait = "retrato",
        background = "fundo",
        chat = "chat|bate-papo",
        minimap = "minimapa",
        bags = "bolsas|bolsa|mochila|inventário",
        nameplates = "placas de nome|placas de identificação",
        meter = "medidor de dano|medidor de cura",
        actionbars = "barras de ação|barra de ação",
        cooldowns = "recargas|tempo de recarga",
        quests = "missões|rastreador de missões",
        classresources = "recursos de classe",
        auraDetail = "temporizador|temporizadores|borda|bordas|brilho|cargas|duração|filtro|filtros",
        tab = "aba|abas",
        suiteDetail = "botão|botões|gaveta|arte|sombra|sombras|dica|cor",
    },
    { -- ruRU
        request = "хочу|как|где|почему|скрыть|показать|слишком",
        grammar = "хочу|можно|сделать|я|мой|мои|моего|мне|на|не|это",
        player = "игрок|игрока",
        target = "цель|цели|целью",
        focus = "фокус|фокуса",
        pet = "питомец|питомца|питомцу",
        boss = "босс|босса|боссы",
        arena = "арена|арены",
        targettarget = "цель цели|цели цели|цель моей цели",
        focustarget = "цель фокуса|цели фокуса|цель моего фокуса",
        pettarget = "цель питомца|цели питомца|цель моего питомца",
        group = "группа|группы|рейд|рейда|участников группы",
        size = "размер|увеличить|уменьшить|больше|меньше|маленький|маленькие",
        text = "текст|шрифт|шрифта|буквы",
        numbers = "цифры|числа",
        health = "здоровье|здоровья|полоса здоровья|полосу здоровья",
        name = "имя|имени",
        move = "переместить|передвинуть|сдвинуть",
        missing = "не вижу|не видно|пропал|пропала|исчез|исчезла",
        opacity = "прозрачный|прозрачной|прозрачность|прозрачным",
        buff = "бафф|баффы|усиления",
        debuff = "дебафф|дебаффы|ослабления",
        hide = "скрыть|спрятать",
        show = "показать|показывать",
        horizontal = "рядом|горизонтально|горизонтальный",
        vertical = "вертикально|вертикальный|друг под другом",
        qualifier = "только|кроме|когда|во время|бою|мои баффы|мои дебаффы|свои|дружественные|дружественных|вражеские|" ..
            "вражеских|союзников|противников",
        resource = "мана|ману|маны|энергия|энергию|ярость|ресурс|ресурсы",
        icon = "значок|значки|иконка|иконки|индикатор|индикаторы",
        castbar = "полоса заклинаний|полосу заклинаний|полоса произнесения|полосу произнесения",
        portrait = "портрет|портрета",
        background = "фон|фона",
        chat = "чат|чата",
        minimap = "миникарта|миникарту|миникарты|мини карта|мини карту",
        bags = "сумки|сумку|сумок|рюкзак|инвентарь",
        nameplates = "индикаторы здоровья|именные пластины",
        meter = "счётчик урона|счетчик урона|измеритель урона",
        actionbars = "панели команд|панель команд",
        cooldowns = "перезарядка|перезарядки|время восстановления",
        quests = "задания|заданий",
        classresources = "ресурсы класса|руны",
        auraDetail = "таймер|таймеры|границу|границы|рамку баффа|свечение|заряды|длительность|фильтр|фильтры",
        tab = "вкладка|вкладки|вкладок",
        suiteDetail = "кнопка|кнопки|кнопок|ящик|рисунок|тень|тени|подсказка|цвет",
    },
    { -- koKR
        request = "싶어요|싶습니다|어디|왜|어떻게|작아요|작습니다|너무",
        grammar = "하고|싶어요|싶습니다|어디서|싶어|설정은|있나요",
        player = "플레이어",
        target = "대상",
        focus = "주시 대상|주시대상",
        pet = "소환수|야수",
        boss = "우두머리|보스",
        arena = "투기장",
        targettarget = "대상의 대상|대상의대상",
        focustarget = "주시 대상의 대상|주시대상의대상",
        pettarget = "소환수의 대상|소환수의대상",
        group = "파티|파티원|공격대|그룹",
        size = "크기|크게|작게|작아요|작습니다|확대|축소",
        text = "글꼴|글자|텍스트",
        numbers = "숫자",
        health = "체력|생명력",
        name = "이름",
        move = "옮기|이동|움직이",
        missing = "안 보이|안보이|보이지 않|사라|안 보이나요",
        opacity = "투명|불투명도",
        buff = "강화 효과|강화효과|버프",
        debuff = "약화 효과|약화효과|디버프",
        hide = "숨기|숨겨",
        show = "표시|보이게",
        horizontal = "나란히|가로",
        vertical = "세로|위아래",
        qualifier = "만 표시|효과만|버프만|내 강화 효과|내 버프|제외|전투|동안|아군|적 대상|적대|우호",
        resource = "마나|기력|분노|자원",
        icon = "아이콘|지시기|표시기",
        castbar = "시전바|시전 바",
        portrait = "초상화",
        background = "배경",
        chat = "채팅|대화창",
        minimap = "미니맵|미니 맵",
        bags = "가방|배낭|소지품",
        nameplates = "이름표|이름 표시",
        meter = "피해량 측정|피해량 미터|공격력 측정",
        actionbars = "행동 단축바|행동단축바",
        cooldowns = "재사용 대기시간|재사용대기시간",
        quests = "퀘스트|임무 추적",
        classresources = "직업 자원|룬|연계 점수",
        auraDetail = "타이머|테두리|빛남|중첩|지속시간|필터",
        tab = "탭",
        suiteDetail = "버튼|서랍|그림|그림자|툴팁|색상",
    },
    { -- zhCN
        request = "我|想|怎么|如何|为什么|隐藏|显示|太小|太大",
        grammar = "我|想|把|让|的|在|设置|哪里|怎么|如何",
        player = "玩家",
        target = "目标",
        focus = "焦点",
        pet = "宠物",
        boss = "首领|头目",
        arena = "竞技场",
        targettarget = "目标的目标",
        focustarget = "焦点的目标",
        pettarget = "宠物的目标",
        group = "队伍|小队|团队|队伍成员",
        size = "大小|尺寸|调大|调小|放大|缩小|太小|太大",
        text = "文字|字体",
        numbers = "数字|数值",
        health = "生命|血量|生命条",
        name = "名字|姓名|名称",
        move = "移动|拖动",
        missing = "看不到|不见了|消失",
        opacity = "透明|不透明度",
        buff = "增益|增益效果|强化效果",
        debuff = "减益|减益效果|负面效果",
        hide = "隐藏",
        show = "显示",
        horizontal = "并排|横向|横着",
        vertical = "纵向|竖向|竖着",
        qualifier = "只|仅|只有|自己|我的增益|我的减益|战斗|除了|除外|期间|友方|敌方|友善|敌对",
        resource = "法力|能量|怒气|资源",
        icon = "图标|指示器",
        castbar = "施法条|读条",
        portrait = "头像",
        background = "背景",
        chat = "聊天|聊天框",
        minimap = "小地图|迷你地图",
        bags = "背包|包裹|行囊",
        nameplates = "姓名板|血条",
        meter = "伤害统计|伤害计量|伤害计量器",
        actionbars = "动作条|技能栏",
        cooldowns = "冷却|冷却管理",
        quests = "任务|任务追踪",
        classresources = "职业资源|符文|连击点",
        auraDetail = "计时器|计时|边框|发光|层数|持续时间|过滤",
        tab = "标签|页签",
        suiteDetail = "按钮|抽屉|装饰|阴影|提示|颜色",
    },
    { -- zhTW
        request = "我|想|怎麼|如何|為什麼|隱藏|顯示|太小|太大",
        grammar = "我|想|把|讓|的|在|設定|哪裡|怎麼|如何",
        player = "玩家",
        target = "目標",
        focus = "專注目標|焦點",
        pet = "寵物",
        boss = "首領|頭目",
        arena = "競技場",
        targettarget = "目標的目標",
        focustarget = "專注目標的目標|焦點的目標",
        pettarget = "寵物的目標",
        group = "隊伍|小隊|團隊|隊伍成員",
        size = "大小|尺寸|調大|調小|放大|縮小|太小|太大",
        text = "文字|字型|字體",
        numbers = "數字|數值",
        health = "生命|血量|生命條",
        name = "名字|姓名|名稱",
        move = "移動|拖動",
        missing = "看不到|不見了|消失",
        opacity = "透明|不透明度",
        buff = "增益|增益效果|強化效果",
        debuff = "減益|減益效果|負面效果",
        hide = "隱藏",
        show = "顯示",
        horizontal = "並排|橫向|橫著",
        vertical = "縱向|直向|直排",
        qualifier = "只|僅|只有|自己|我的增益|我的減益|戰鬥|除了|除外|期間|友方|敵方|友善|敵對",
        resource = "法力|能量|怒氣|資源",
        icon = "圖示|圖標|指示器",
        castbar = "施法條|讀條",
        portrait = "頭像",
        background = "背景",
        chat = "聊天|聊天框",
        minimap = "小地圖|迷你地圖",
        bags = "背包|包裹|行囊",
        nameplates = "名條|血條",
        meter = "傷害統計|傷害計量|傷害計量表",
        actionbars = "快捷列|動作條|技能列",
        cooldowns = "冷卻|冷卻管理",
        quests = "任務|任務追蹤",
        classresources = "職業資源|符文|連擊點",
        auraDetail = "計時器|計時|邊框|發光|層數|持續時間|過濾",
        tab = "標籤|頁籤",
        suiteDetail = "按鈕|抽屜|裝飾|陰影|提示|顏色",
    },
}
local NATIVE_LANGUAGES = { enUS = 1, deDE = 2, esES = 3, frFR = 4, itIT = 5, ptBR = 6, ruRU = 7, koKR = 8, zhCN = 9, zhTW = 10 }

local NATURAL_WORDS = {
    tab = "tab|tabs|reiter", suiteDetail = "button|buttons|drawer|artwork|shadow|tooltip|color|colour",
    chat = "chat|chat frame|chatfenster", minimap = "minimap|minikarte", bags = "bag|bags|backpack|taschen",
    nameplates = "nameplate|nameplates|name plate|namensplaketten", meter = "damage meter|dps meter|healing meter|schadensmesser",
    actionbars = "action bar|action bars|aktionsleisten", cooldowns = "cooldown|cooldowns|cdm|abklingzeiten",
    quests = "quest|quests", classresources = "rune|runes|combo|essence|class resources|klassenressourcen",
    foreign = "tooltip|cursor|data texts|datatexts",
    auraDetail = "filter|filters|swipe|glow|stack|stacks|timer|timers|border|borders",
    request = HUMAN_REQUEST_WORDS, detail = HUMAN_DETAIL_WORDS, other = HUMAN_OTHER_CONTEXT_WORDS,
    qualifier = HUMAN_QUALIFIER_WORDS, resource = HUMAN_RESOURCE_WORDS,
    player = "player|playerframe|spieler|spielerframe|spielerbalken", target = "target|targetframe|ziel|zielframe|zielrahmen|zielbalken",
    focus = "focus|focusframe|fokus|fokusframe", pet = "pet|petframe|begleiter", boss = "boss|bosses|bossframe", arena = "arena|arenaframe",
    focustarget = "focus target|fokusziel|fokus ziel|focustarget", targettarget = "target of target|ziel des ziels|targettarget",
    pettarget = "pet target|pettarget|begleiterziel",
    group = "party|raid|group members|gruppenmitglieder|gruppenrahmen|gruppenframes|gruppe|schlachtzug",
    size = "size|bigger|smaller|small|big|groesser|groesse|klein|kleiner|schriftgroesse",
    text = "text|font|schrift|schriftgroesse", numbers = "numbers|number|lebenszahl|lebenszahlen|zahlen",
    health = "health|healthbar|health bars|lebensbalken|hp|lebenszahl|lebenszahlen|lebenstext",
    name = "name|names|namen", move = "move|drag|verschieben|bewegen|positionieren",
    missing = "missing|disappeared|invisible|not see|cant see|cannot see|nicht|verschwunden|unsichtbar",
    opacity = "opacity|transparent|transparency|durchsichtig|durchsichtigkeit",
    buff = "buff|buffs|aura|auras", debuff = "debuff|debuffs", icon = "icon|icons|symbol|symbols",
    hide = "hide|ausblenden", show = "show|anzeigen", horizontal = "side by side|nebeneinander|horizontal", vertical = "untereinander|vertical",
}
local NATIVE_ALIAS_TERMS = {
    player = "player|player frame", target = "target|target frame", focus = "focus|focus frame", pet = "pet|pet frame",
    boss = "boss|boss frame", arena = "arena|arena frame", targettarget = "target of target|targettarget",
    focustarget = "focus target|focustarget", pettarget = "pet target|pettarget", group = "party|raid|group frames|group layout",
    size = "size|width|height|scale|font size", text = "text|font|font size", numbers = "text|health text|font size",
    health = "health|health text|health bar", name = "name|name text", move = "move|edit mode|position|anchor",
    missing = "hidden|visible|enabled", opacity = "opacity|alpha|transparency", resource = "power|mana|power text",
    buff = "buff|buffs|unit auras", debuff = "debuff|debuffs|unit auras", icon = "icon|indicator|status indicator",
    hide = "hide|hidden|visible", show = "show|visible|enabled", horizontal = "horizontal|growth|group layout",
    vertical = "vertical|growth|group layout", castbar = "castbar|cast bar", portrait = "portrait", background = "background",
    chat = "chat|chat frame", minimap = "minimap", bags = "bags|bag|inventory|backpack",
    nameplates = "nameplate|nameplates", meter = "damage meter|healing meter", actionbars = "action bars|action bar",
    cooldowns = "cooldown|cooldown manager", quests = "quest|quest tracker", classresources = "class resources|classpower",
}
local NATIVE_OTHER = { chat = true, minimap = true, bags = true, nameplates = true, meter = true,
    actionbars = true, cooldowns = true, quests = true, classresources = true }
local NATIVE_DETAIL = { suiteDetail = true, auraDetail = true, castbar = true, portrait = true, background = true, icon = true, buff = true, debuff = true }
for _, language in ipairs(NATIVE_QUERY_WORDS) do
    for kind, words in pairs(language) do
        if kind == "grammar" then
            for word in words:gmatch("[^|]+") do Data.QUERY_SOFT_STOP_WORDS[word] = true end
        else
            NATURAL_WORDS[kind] = (NATURAL_WORDS[kind] and (NATURAL_WORDS[kind] .. "|") or "") .. words
            if NATIVE_OTHER[kind] then NATURAL_WORDS.other = NATURAL_WORDS.other .. "|" .. words end
            if NATIVE_DETAIL[kind] then NATURAL_WORDS.detail = NATURAL_WORDS.detail .. "|" .. words end
            if NATIVE_ALIAS_TERMS[kind] then
                for word in words:gmatch("[^|]+") do AddAliasTerms(word, NATIVE_ALIAS_TERMS[kind]) end
            end
        end
    end
end

-- Fold once, when Text is available on the first query. Compact scripts match
-- native stems (Korean particles included); Latin/Cyrillic words keep boundaries.
local naturalQueryLexicon, naturalQueryLocale
local function NaturalQueryLexicon()
    local locale = MSUF.LOCALE or "enUS"
    if naturalQueryLexicon and naturalQueryLocale == locale then return naturalQueryLexicon end
    local nativeLocale = locale == "esMX" and "esES" or (locale == "enGB" and "enUS" or locale)
    local preferred = NATIVE_QUERY_WORDS[NATIVE_LANGUAGES[nativeLocale]] or {}
    local meanings = {}
    for kind, words in pairs(preferred) do
        if kind ~= "grammar" then
            for word in words:gmatch("[^|]+") do
                word = M.Search.Text.NormalizeSearchText(word)
                local kinds = meanings[word] or {}
                kinds[kind] = true
                if NATIVE_OTHER[kind] then kinds.other = true end
                if NATIVE_DETAIL[kind] then kinds.detail = true end
                meanings[word] = kinds
            end
        end
    end
    local normalized = {}
    for kind, words in pairs(NATURAL_WORDS) do
        local list, seen = {}, {}
        for word in words:gmatch("[^|]+") do
            word = M.Search.Text.NormalizeSearchText(word)
            if word ~= "" and not seen[word] and (not meanings[word] or meanings[word][kind]) then
                local compact = word:find("[\227-\237][\128-\191][\128-\191]")
                list[#list + 1] = { needle = compact and word or (" " .. word .. " "), compact = compact }
                seen[word] = true
            end
        end
        normalized[kind] = list
    end
    naturalQueryLexicon, naturalQueryLocale = normalized, locale
    return normalized
end
local function NaturalWordMatch(q, words)
    local bestStart, bestEnd, bestLength = nil, nil, 0
    for _, word in ipairs(words) do
        local first, last = q:find(word.needle, 1, true)
        if first and #word.needle > bestLength then
            bestStart, bestEnd, bestLength = first, last, #word.needle
            if not word.compact then bestStart, bestEnd = first + 1, last - 1 end
        end
    end
    return bestStart, bestEnd
end
local NATURAL_UNITS = { "focustarget", "targettarget", "pettarget", "player", "target", "focus", "pet", "boss", "arena" }
local function NaturalUnit(q, lexicon)
    local unit, first, last, length = nil, nil, nil, 0
    for _, key in ipairs(NATURAL_UNITS) do
        local startAt, endAt = NaturalWordMatch(q, lexicon[key])
        if startAt and endAt - startAt + 1 > length then
            unit, first, last, length = key, startAt, endAt, endAt - startAt + 1
        end
    end
    if unit then
        for _, key in ipairs(NATURAL_UNITS) do
            for _, word in ipairs(lexicon[key]) do
                local offset = 1
                while true do
                    local startAt, endAt = q:find(word.needle, offset, true)
                    if not startAt then break end
                    offset = startAt + 1
                    if not word.compact then startAt, endAt = startAt + 1, endAt - 1 end
                    if startAt < first or endAt > last then return nil, true end
                end
            end
        end
    end
    return unit
end
function Data.NaturalQueryTarget(normalized)
    local q, lexicon = " " .. normalized .. " ", NaturalQueryLexicon()
    local function Has(kind) return NaturalWordMatch(q, lexicon[kind]) ~= nil end
    if not Has("request") and not Has("size") then return nil end
    if Has("qualifier") then return nil end
    local unit, ambiguous = NaturalUnit(q, lexicon)
    if ambiguous then return nil end
    local group, size = Has("group"), Has("size")
    local text = Has("text") or Has("numbers") or Has("name")
    local detail, resource = Has("detail"), Has("resource")
    if Has("other") then
        if unit or group or detail or resource or Has("foreign") then return nil end
        local domains = 0
        for kind in pairs(NATIVE_OTHER) do if Has(kind) then domains = domains + 1 end end
        if domains ~= 1 or not size then return nil end
        -- These targets are used only when an available Suite row actually owns
        -- the setting. Missing addons/clients still fail through the normal index.
        if Has("minimap") and not text and not Has("tab") then return { settingKey = "msufsuite.minimap.size" } end
        if Has("bags") and not text and not Has("tab") then return { settingKey = "msufsuite.bags.windowScale" } end
        if Has("chat") and text and not Has("name") then
            return { settingKey = Has("tab") and "msufsuite.chat.tabFontSize" or "msufsuite.chat.fontSize" }
        end
        return nil
    end
    -- A short, unqualified unit-size phrase is as clear as a full request.
    if not Has("request") and not (unit and size and not text and not detail and not resource) then return nil end
    if group and not detail and not text and (Has("horizontal") or Has("vertical")) then
        return { pageKey = "gf_layout", controlSuffix = Has("vertical") and ".field.growth.option.down" or ".field.growth.option.right" }
    end
    if size and text and not detail then
        if group then return { pageKey = "gf_layout" } end
        if Has("numbers") or Has("health") then return { pageKey = unit and ("uf_" .. unit) or "uf_player" } end
        if unit and Has("name") then return { settingKey = unit .. ".nameFontSize" } end
        return { pageKey = unit and ("uf_" .. unit) or "opt_fonts" }
    end
    if unit and not detail and not text and not resource and (size or Has("move")) then return { pageKey = "uf_" .. unit } end
    if unit and not detail and not text and not resource and Has("missing") then return { settingKey = unit .. ".enabled" } end
    if not group and not text and not detail and not resource and Has("opacity") and Has("health") then
        return { settingKey = (unit or "player") .. ".hpBarAlpha" }
    end
    if unit and not group and not text and not size and not Has("icon") and not Has("auraDetail") and (Has("buff") or Has("debuff")) then
        local lane = Has("debuff") and "debuff" or "buff"
        if Has("hide") or Has("show") then return { settingKey = "auras3." .. unit .. "." .. lane .. ".visible" } end
    end
end

-- Full compact phrases contain independent concepts, not interchangeable
-- synonyms. Keep the source aliases but parse these as separate AND clauses.
Data.QUERY_COMPOUNDS = {
    ["目标框体大小"] = "目标 框体 大小", ["目標框架大小"] = "目標 框架 大小",
    ["施法条颜色"] = "施法条 颜色", ["施法條顏色"] = "施法條 顏色",
    ["隐藏小队框体"] = "隐藏 小队 框体", ["隱藏小隊框架"] = "隱藏 隊伍 框架",
}

AddLocalizedAlias("调大", "target size|width|height|scale")
AddLocalizedAlias("放大", "target size|width|height|scale")
