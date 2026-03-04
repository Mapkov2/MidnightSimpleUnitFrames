-- ============================================================================
-- MSUF_Search.lua  v5
-- Every label indexed. Portrait fully covered. Click scrolls to exact widget.
-- Secret-safe: INDEX is static strings only, zero live API calls at query time.
-- ============================================================================
local addonName, ns = ...
ns = ns or {}

local lower  = string.lower
local find   = string.find
local format = string.format

local MAX_ROWS          = 20
local MIN_QUERY_LEN     = 2
local DEBOUNCE_SEC      = 0.18
local SEARCH_BOX_H      = 22
local SEARCH_RESERVE_PX = SEARCH_BOX_H + 14
local SCROLL_DELAY      = 0.18   -- seconds after page switch before scrolling
local SCROLL_RETRY      = 0.40   -- second attempt if first GetTop() returns nil

-- ---------------------------------------------------------------------------
-- SCROLL_MAP — which named ScrollFrame+ScrollChild serve each pageKey
-- ---------------------------------------------------------------------------
local SCROLL_MAP = {
    uf_player       = { sf="MSUF_FramesMenuScrollFrame",     sc="MSUF_FramesMenuScrollChild"     },
    uf_target       = { sf="MSUF_FramesMenuScrollFrame",     sc="MSUF_FramesMenuScrollChild"     },
    uf_targettarget = { sf="MSUF_FramesMenuScrollFrame",     sc="MSUF_FramesMenuScrollChild"     },
    uf_focus        = { sf="MSUF_FramesMenuScrollFrame",     sc="MSUF_FramesMenuScrollChild"     },
    uf_boss         = { sf="MSUF_FramesMenuScrollFrame",     sc="MSUF_FramesMenuScrollChild"     },
    uf_pet          = { sf="MSUF_FramesMenuScrollFrame",     sc="MSUF_FramesMenuScrollChild"     },
    opt_castbar     = { sf="MSUF_CastbarMenuScrollFrame",    sc="MSUF_CastbarMenuScrollChild"    },
    castbar         = { sf="MSUF_CastbarMenuScrollFrame",    sc="MSUF_CastbarMenuScrollChild"    },
    opt_bars        = { sf="MSUF_BarsMenuScrollFrame",       sc="MSUF_BarsMenuScrollChild"       },
    classpower      = { sf="MSUF_ClassPowerMenuScrollFrame", sc="MSUF_ClassPowerMenuScrollChild" },
    opt_colors      = { sf="MSUF_ColorsScrollFrame",         sc="MSUF_ColorsScrollChild"         },
    colors          = { sf="MSUF_ColorsScrollFrame",         sc="MSUF_ColorsScrollChild"         },
    gameplay        = { sf="MSUF_GameplayScrollFrame",       sc="MSUF_GameplayScrollChild"       },
}

-- ---------------------------------------------------------------------------
-- HighlightWidget — animated gold flash around the target widget.
-- One-shot overlay, double-pulse, fades over ~1.4s. Secret-safe.
-- ---------------------------------------------------------------------------
local _hlFrame = nil

local function HighlightWidget(anchor)
    if not anchor then return end
    local widget = _G[anchor]
    if not widget then return end
    local wTop  = widget:GetTop()
    local wLeft = widget:GetLeft()
    local wW    = widget:GetWidth()
    local wH    = widget:GetHeight()
    if not (wTop and wLeft and wW and wH) then return end

    if not _hlFrame then
        _hlFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        _hlFrame:SetFrameStrata("TOOLTIP")
        _hlFrame:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 10,
            insets = { left=2, right=2, top=2, bottom=2 },
        })
        _hlFrame:SetBackdropColor(1, 0.82, 0, 0)
        _hlFrame:SetBackdropBorderColor(1, 0.82, 0, 1)
        _hlFrame:Hide()
    end

    local pad = 4
    _hlFrame:ClearAllPoints()
    _hlFrame:SetWidth(wW + pad * 2)
    _hlFrame:SetHeight(wH + pad * 2)
    local screenH = UIParent:GetHeight()
    _hlFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
        wLeft - pad, wTop - screenH + pad)
    _hlFrame:SetAlpha(1)
    _hlFrame:Show()

    local step = 0
    local STEPS = 28
    local tickref = {}
    tickref[1] = C_Timer.NewTicker(0.05, function()
        step = step + 1
        local t = step / STEPS
        local a = (1 - t) * (0.5 + 0.5 * math.abs(math.sin(t * math.pi * 3)))
        if a < 0 then a = 0 end
        _hlFrame:SetAlpha(a)
        if step >= STEPS then
            tickref[1]:Cancel()
            _hlFrame:Hide()
        end
    end, STEPS)
end

-- ---------------------------------------------------------------------------
-- ScrollToWidget — resolves globals AFTER the page has shown.
-- Returns true on success so the caller can skip the retry.
-- ---------------------------------------------------------------------------
local function ScrollToWidget(pageKey, anchor)
    if not anchor then return true end
    local sm = SCROLL_MAP[pageKey]
    if not sm then return true end
    local sf     = _G[sm.sf]
    local sc     = _G[sm.sc]
    local widget = _G[anchor]
    if not (sf and sc and widget) then return true end
    local scTop = sc:GetTop()
    local wTop  = widget:GetTop()
    if not (scTop and wTop) then return false end
    local off = (scTop - wTop) - 20
    if off < 0 then off = 0 end
    if sf.SetVerticalScroll then sf:SetVerticalScroll(off) end
    if _G.UIPanelScrollFrame_Update then _G.UIPanelScrollFrame_Update(sf) end
    return true
end

-- ---------------------------------------------------------------------------
-- INDEX
-- label    : exact UI text the user recognises
-- hint     : breadcrumb shown in result row
-- pageKey  : MIRROR_PAGES key
-- anchor   : optional _G widget name — page will scroll to it on click
-- keywords : synonyms, typos, natural language, acronyms (all lowercase)
-- ---------------------------------------------------------------------------
local INDEX = {
    { label="MSUF Edit Mode (öffnen / enter / move frames)",
      hint="Dashboard", pageKey="home",anchor="MSUF_EditModeButton",
      keywords={"edit mode","edit","mode","open","enter","move","drag","layout","position","reposition","frame mover","editmode","unlock","arrange","customize","bearbeiten","einrichten","frame placement"} },
    { label="< Undo / Undo last change",
      hint="Edit Mode", pageKey="home",anchor="MSUF_EditModeUndoBtn",
      keywords={"undo","undo change","last change","revert","ctrl z","strg z","rückgängig","undo last","previous state","undo move","undo button","< undo"} },
    { label="Redo > / Redo last undone change",
      hint="Edit Mode", pageKey="home",anchor="MSUF_EditModeRedoBtn",
      keywords={"redo","redo change","ctrl y","strg y","wiederholen","redo last","redo move","redo >","redo button","redo last undone"} },
    { label="Exit MSUF Edit Mode",
      hint="Edit Mode", pageKey="home",anchor="MSUF_EditModeExitButton",
      keywords={"exit","leave edit mode","close edit","done editing","beenden","schließen","exit edit"} },
    { label="Cancel Changes (Edit Mode)",
      hint="Edit Mode", pageKey="home",anchor="MSUF_EditModeCancelButton",
      keywords={"cancel","discard","revert all","cancel changes","abbrechen","verwerfen","cancel edit"} },
    { label="Reset Frame (Edit Mode)",
      hint="Edit Mode", pageKey="home",anchor="MSUF_EditModeResetButton",
      keywords={"reset frame","reset position","default position","wrong place","offscreen","frame went offscreen","restore position","zurücksetzen"} },
    { label="Snap to grid (Edit Mode)",
      hint="Dashboard", pageKey="home",anchor="MSUF_EditModeSnapCheck",
      keywords={"snap","grid","align","pixel","gridsnap","snap to grid","raster","am gitter"} },
    { label="Grid Size (px) (Edit Mode)",
      hint="Edit Mode", pageKey="home",anchor="MSUF_EditModeGridSlider",
      keywords={"grid size","grid","size","px","pixel","raster größe","grid px","snap distance"} },
    { label="Edit Mode Background (opacity slider)",
      hint="Edit Mode", pageKey="home",anchor="MSUF_EditModeAlphaSlider",
      keywords={"background","alpha","opacity","overlay","dim","transparency","edit bg","edit alpha","backdrop"} },
    { label="Aura Preview (Edit Mode)",
      hint="Edit Mode", pageKey="home",anchor="MSUF_EditModeAuraPreviewCheck",
      keywords={"aura preview","preview auras","show auras edit","dummy auras","test auras","buff preview"} },
    { label="Boss Preview (Edit Mode)",
      hint="Edit Mode", pageKey="home",anchor="MSUF_EditModeBossPreviewCheck",
      keywords={"boss preview","preview boss","show boss edit","dummy boss","test boss"} },
    { label="Custom anchor frame name (/fstack)",
      hint="Edit Mode", pageKey="home",anchor="MSUF_EditModeAnchorNameInput",
      keywords={"custom anchor","frame name","fstack","/fstack","anchor name","type frame name","enter frame"} },
    { label="Anchor to unitframe (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"anchor to unitframe","anchor unitframe","attach frame","snap to frame"} },
    { label="Anchor to Boss unitframe (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"anchor boss","anchor to boss","boss frame anchor"} },
    { label="Anchor to Resource Bar (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"anchor resource bar","sync resource","attach resource bar"} },
    { label="Detach from frame (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"detach","detach from frame","free frame","unlink frame","standalone"} },
    { label="Sync width to Resource Bar (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"sync width","resource bar width","match resource width","sync resource width"} },
    { label="Power text on bar (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"power text on bar","text on bar","embed text","power text bar","mana text on bar"} },
    { label="Text Anchor Left / Center / Right (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"text anchor","left","center","right","align text","justify","text align","text justify"} },
    { label="Edit Unit: Player / Target / ToT / Focus / Pet / Boss (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"edit unit","select frame","player","target","tot","focus","pet","boss","which frame","choose unit"} },
    { label="Copy settings to / Copy size to / Copy text to (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"copy settings","copy size","copy text","clone frame","transfer settings","copy to"} },
    { label="Name X / Name Y / Name Size (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"name x","name y","name size","move name","name offset","name position","text name pos"} },
    { label="HP X / HP Y / HP Size (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"hp x","hp y","hp size","move hp","hp offset","hp text position","health text pos"} },
    { label="Power X / Power Y / Power Size (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"power x","power y","power size","move power","power offset","mana text position"} },
    { label="Spell X / Spell Y / Spell Size (Edit Mode castbar text)",
      hint="Edit Mode", pageKey="home",
      keywords={"spell x","spell y","spell size","spell text","castbar text position","spell name pos"} },
    { label="Icon X / Icon Y / Icon Size (Edit Mode aura icons)",
      hint="Edit Mode", pageKey="home",
      keywords={"icon x","icon y","icon size","aura icon position","buff icon pos","icon offset"} },
    { label="Time X / Time Y / Time Size (Edit Mode castbar timer)",
      hint="Edit Mode", pageKey="home",
      keywords={"time x","time y","time size","timer position","cast timer pos","time offset"} },
    { label="Stack text X / Stack text Y / Text size (Stacks) (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"stack text x","stack text y","stack text size","text size stacks","stack position"} },
    { label="Cooldown text X / Cooldown text Y / Text size (Cooldown) (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"cooldown text x","cooldown text y","cooldown text size","text size cooldown","cd text pos"} },
    { label="Buff offset X / Buff offset Y / Buff icon size (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"buff offset x","buff offset y","buff icon size","buff position","aura buff pos"} },
    { label="Debuff offset X / Debuff offset Y / Debuff icon size (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"debuff offset x","debuff offset y","debuff icon size","debuff position","aura debuff pos"} },
    { label="Private offset X / Private offset Y / Private icon size (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"private offset x","private offset y","private icon size","private aura position"} },
    { label="Offset X / Offset Y (frame position)",
      hint="Edit Mode", pageKey="home",
      keywords={"offset x","offset y","frame offset","position offset","x offset","y offset"} },
    { label="Width / Height / Spacing (Edit Mode)",
      hint="Edit Mode", pageKey="home",
      keywords={"width","height","spacing","frame width","frame height","resize frame","frame size","breite","höhe","frame spacing"} },
    { label="Buffs / Debuffs section (Edit Mode aura position panel)",
      hint="Edit Mode", pageKey="home",
      keywords={"buffs debuffs","aura position","buff debuff section","buff debuff edit"} },
    { label="Portrait — Player (Off / 2D Left / 2D Right / 3D Left / 3D Right / Class Icon)",
      hint="Player › Basics", pageKey="uf_player",anchor="MSUF_UF_PortraitDropDown",
      keywords={"portrait","portriat","portrat","porrait","portraite","portrit","portrai","porträt","bild","gesicht","face","avatar","model","2d","3d","class icon","portrait off","portrait left","portrait right","player portrait","class icon left","class icon right"} },
    { label="Portrait — Target (Off / 2D Left / 2D Right / 3D Left / 3D Right / Class Icon)",
      hint="Target", pageKey="uf_target",
      keywords={"portrait","portriat","portrat","porrait","portraite","portrit","portrai","porträt","bild","gesicht","face","avatar","model","2d","3d","class icon","portrait off","portrait left","portrait right","target portrait","class icon left","class icon right"} },
    { label="Portrait — Target of Target (Off / 2D Left / 2D Right / 3D Left / 3D Right / Class Icon)",
      hint="Target of Target", pageKey="uf_targettarget",
      keywords={"portrait","portriat","portrat","porrait","portraite","portrit","portrai","porträt","bild","gesicht","face","avatar","model","2d","3d","class icon","portrait off","portrait left","portrait right","target of target portrait","class icon left","class icon right"} },
    { label="Portrait — Focus (Off / 2D Left / 2D Right / 3D Left / 3D Right / Class Icon)",
      hint="Focus", pageKey="uf_focus",
      keywords={"portrait","portriat","portrat","porrait","portraite","portrit","portrai","porträt","bild","gesicht","face","avatar","model","2d","3d","class icon","portrait off","portrait left","portrait right","focus portrait","class icon left","class icon right"} },
    { label="Portrait — Boss (Off / 2D Left / 2D Right / 3D Left / 3D Right / Class Icon)",
      hint="Boss Frames", pageKey="uf_boss",
      keywords={"portrait","portriat","portrat","porrait","portraite","portrit","portrai","porträt","bild","gesicht","face","avatar","model","2d","3d","class icon","portrait off","portrait left","portrait right","boss portrait","class icon left","class icon right"} },
    { label="Portrait — Pet (Off / 2D Left / 2D Right / 3D Left / 3D Right / Class Icon)",
      hint="Pet Frame", pageKey="uf_pet",
      keywords={"portrait","portriat","portrat","porrait","portraite","portrit","portrai","porträt","bild","gesicht","face","avatar","model","2d","3d","class icon","portrait off","portrait left","portrait right","pet portrait","class icon left","class icon right"} },
    { label="Enable this frame (Player)",
      hint="Player › Basics", pageKey="uf_player",anchor="MSUF_UF_EnableFrameCB",
      keywords={"enable frame","enable player","disable player","turn on player","player on off"} },
    { label="Show name (Player)",
      hint="Player › Basics", pageKey="uf_player",
      keywords={"show name","player name","display name","hide name","name visible"} },
    { label="Show HP text (Player)",
      hint="Player › Basics", pageKey="uf_player",
      keywords={"show hp","hp text","health text","show health","hp number","current hp","missing hp"} },
    { label="Show power text (Player)",
      hint="Player › Basics", pageKey="uf_player",
      keywords={"show power","power text","mana text","resource text","manatext","show mana"} },
    { label="Reverse fill (HP/Power) bars",
      hint="Player › Basics", pageKey="uf_player",
      keywords={"reverse fill","rtl","right to left","invert bar","bar fill backwards","flip bar","drain effect"} },
    { label="Alpha in combat (Player)",
      hint="Player › Alpha", pageKey="uf_player",anchor="MSUF_UF_AlphaInCombatSlider",
      keywords={"alpha in combat","opacity combat","fade combat","dim combat","in combat alpha","combat visibility","allpha","transparent combat"} },
    { label="Alpha out of combat (Player)",
      hint="Player › Alpha", pageKey="uf_player",anchor="MSUF_UF_AlphaOutCombatSlider",
      keywords={"alpha out of combat","ooc alpha","opacity ooc","fade ooc","idle alpha","resting alpha","allpha","not fighting","out combat fade"} },
    { label="Sync both (alpha HP and Power bar)",
      hint="Player › Alpha", pageKey="uf_player",anchor="MSUF_UF_AlphaSyncCB",
      keywords={"sync both","sync alpha","link alpha","same alpha","lock alpha","alpha linked"} },
    { label="Keep text + portrait visible (when bar faded)",
      hint="Player › Alpha", pageKey="uf_player",anchor="MSUF_UF_AlphaExcludeTextPortraitCB",
      keywords={"keep text visible","portrait visible","dont fade text","keep visible","exclude from fade","text visible alpha","portrait visible alpha"} },
    { label="Alpha sliders affect: Foreground / Background layer",
      hint="Player › Alpha", pageKey="uf_player",anchor="MSUF_UF_AlphaLayerDropDown",
      keywords={"alpha sliders affect","foreground layer","background layer","which layer fades","fg bg alpha","what fades","alpha scope"} },
    { label="Load Condition: Mounted",
      hint="Player › Load Conditions", pageKey="uf_player",
      keywords={"load condition mounted","load condition","load cond","mounted","mount","hide mounted","flying","riding","on mount"} },
    { label="Load Condition: In vehicle",
      hint="Player › Load Conditions", pageKey="uf_player",
      keywords={"load condition in vehicle","load condition","load cond","vehicle","car","gun vehicle","siege vehicle","turret","hide in vehicle"} },
    { label="Load Condition: Resting",
      hint="Player › Load Conditions", pageKey="uf_player",
      keywords={"load condition resting","load condition","load cond","resting","inn","city","capital","rest xp","hide resting","tavern","rest area"} },
    { label="Load Condition: Stealthed",
      hint="Player › Load Conditions", pageKey="uf_player",
      keywords={"load condition stealthed","load condition","load cond","stealth","stealthed","rogue","druid cat","invisible","sneak","hide stealthed"} },
    { label="Load Condition: In combat",
      hint="Player › Load Conditions", pageKey="uf_player",
      keywords={"load condition in combat","load condition","load cond","in combat","combat","fight","aggro","show in combat","hide ooc","load combat"} },
    { label="Load Condition: Out of combat",
      hint="Player › Load Conditions", pageKey="uf_player",
      keywords={"load condition out of combat","load condition","load cond","out of combat","ooc","idle","not fighting","hide in combat","load ooc"} },
    { label="Load Condition: Solo",
      hint="Player › Load Conditions", pageKey="uf_player",
      keywords={"load condition solo","load condition","load cond","solo","alone","no group","not grouped","ungrouped","single player"} },
    { label="Load Condition: In group",
      hint="Player › Load Conditions", pageKey="uf_player",
      keywords={"load condition in group","load condition","load cond","group","party","raid","grouped","in party","in raid","not solo"} },
    { label="Load Condition: In instance",
      hint="Player › Load Conditions", pageKey="uf_player",
      keywords={"load condition in instance","load condition","load cond","instance","dungeon","raid","mythic","heroic","lfr","m+","keystone","in instance"} },
    { label="Show leader / assist icon",
      hint="Player › Indicator", pageKey="uf_player",
      keywords={"leader icon","assist icon","crown","raid leader","party leader","master looter","show leader"} },
    { label="Show raid marker icon",
      hint="Player › Indicator", pageKey="uf_player",
      keywords={"raid marker","skull","cross","circle","square","moon","triangle","diamond","star","world marker","target mark","raidmark","show raid marker"} },
    { label="Show level (Player)",
      hint="Player › Indicator", pageKey="uf_player",
      keywords={"show level","level text","lvl","character level","level number","display level"} },
    { label="Inline Text (ToT / castbar inline)",
      hint="Player › Inline Text", pageKey="uf_player",
      keywords={"inline text","tot inline","target of target inline","castbar inline","inline"} },
    { label="Status icons: Combat indicator",
      hint="Player › Status Icons", pageKey="uf_player",anchor="MSUF_StatusCombatIconCB",
      keywords={"status icons","combat status","combat icon","combat indicator","show combat"} },
    { label="Status icons: Rested indicator",
      hint="Player › Status Icons", pageKey="uf_player",anchor="MSUF_StatusRestingIconCB",
      keywords={"rested status","rest icon","resting indicator","inn icon","rest bonus icon"} },
    { label="Status icons: Incoming Rez indicator",
      hint="Player › Status Icons", pageKey="uf_player",anchor="MSUF_StatusIncomingResIconCB",
      keywords={"incoming rez","battle rez","brez","soulstone","rez icon","incoming resurrection"} },
    { label="Status icons test mode (preview)",
      hint="Player › Status Icons", pageKey="uf_player",anchor="MSUF_StatusIconsTestModeCB",
      keywords={"status icons test","test mode status","preview status","demo status","force status"} },
    { label="Status icon style (Midnight themed)",
      hint="Player › Status Icons", pageKey="uf_player",anchor="MSUF_StatusIconsStyleCB",
      keywords={"status style","midnight icon","status icon texture","themed status","custom status icon"} },
    { label="Resets current indicator (status icons)",
      hint="Player › Status Icons", pageKey="uf_player",
      keywords={"reset indicator","resets current indicator","status reset"} },
    { label="Castbar toggle: Player / Target / Focus / Boss",
      hint="Player › Castbar Toggles", pageKey="uf_player",
      keywords={"castbar","enable castbar","player castbar","target castbar","focus castbar","boss castbar","cast bar toggle","casbar","casting bar","casbar toggle"} },
    { label="Show ToT inline in Target frame",
      hint="Player › ToT Inline", pageKey="uf_player",anchor="MSUF_ToTInlineInTargetCB",
      keywords={"tot inline","target of target inline","tot in target","secondary target text","tot text inline"} },
    { label="ToT inline separator style",
      hint="Player › ToT Inline", pageKey="uf_player",anchor="MSUF_ToTInlineSeparatorDropDown",
      keywords={"tot separator","inline separator","tot divider","separator style tot"} },
    { label="Anchor pet to (frame)",
      hint="Player › Anchors", pageKey="uf_player",anchor="MSUF_PetAnchorToDropDown",
      keywords={"anchor pet","pet anchor","pet follows","attach pet","pet position"} },
    { label="Anchor focus to (frame)",
      hint="Player › Anchors", pageKey="uf_player",anchor="MSUF_FocusAnchorToDropDown",
      keywords={"anchor focus","focus anchor","focus follows","attach focus","focus position"} },
    { label="Enable Target frame",
      hint="Target", pageKey="uf_target",
      keywords={"enable target","target frame","target on off","activate target"} },
    { label="Target frame: Alpha / Load Conditions",
      hint="Target", pageKey="uf_target",
      keywords={"target alpha","target fade","target load condition","target visibility","target opacity"} },
    { label="Enable Target of Target frame",
      hint="Target of Target", pageKey="uf_targettarget",
      keywords={"tot","target of target","enable tot","tot frame","secondary target","tot enable"} },
    { label="Enable Focus frame",
      hint="Focus", pageKey="uf_focus",
      keywords={"enable focus","focus frame","focus on off","activate focus"} },
    { label="Focus frame: Alpha / Load Conditions",
      hint="Focus", pageKey="uf_focus",
      keywords={"focus alpha","focus fade","focus load condition","focus visibility"} },
    { label="Enable Boss frames",
      hint="Boss Frames", pageKey="uf_boss",
      keywords={"enable boss","boss frames","boss unitframes","encounter frames","boss on off"} },
    { label="Invert boss order",
      hint="Boss Frames", pageKey="uf_boss",anchor="MSUF_UF_InvertBossOrderCB",
      keywords={"invert boss","boss order","reverse boss","flip boss order","boss sort"} },
    { label="Enable Pet frame",
      hint="Pet Frame", pageKey="uf_pet",
      keywords={"enable pet","pet frame","hunter pet","warlock pet","familiar","ghoul","pet on off"} },
    { label="Castbar texture (SharedMedia)",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarTextureDropdown",
      keywords={"castbar texture","cast bar skin","cast texture","castbar look","lsm castbar","sharedmedia castbar"} },
    { label="Castbar background texture (SharedMedia)",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarBackgroundTextureDropdown",
      keywords={"castbar background","cast bg texture","behind castbar","castbar bg"} },
    { label="Castbar fill direction (Right to left / Left to right)",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarFillDirectionDropdown",
      keywords={"castbar fill direction","cast direction","fill left","fill right","rtl castbar","ltr castbar","right to left","left to right","cast fill direction"} },
    { label="Always use fill direction for all casts",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarUnifiedDirectionCheck",
      keywords={"always fill direction","unified direction","same direction all","force cast direction","unify fill"} },
    { label="Use opposite fill direction for target castbar",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarOpositeDirectionTarget",
      keywords={"opposite direction","target opposite","reverse target cast","invert target castbar"} },
    { label="Show channel tick lines (5)",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarChannelTicksCheck",
      keywords={"channel ticks","tick lines","channeling","5 ticks","cast ticks","show ticks","channel tick lines"} },
    { label="Show GCD bar for instant casts",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarGCDBarCheck",
      keywords={"gcd bar","global cooldown bar","instant gcd","show gcd","gcd instant","gcd castbar"} },
    { label="GCD bar: show time text",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarGCDTimeCheck",
      keywords={"gcd time","gcd timer text","global cd time","gcd text","gcd duration"} },
    { label="GCD bar: show spell name",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarGCDSpellCheck",
      keywords={"gcd spell name","spell on gcd","gcd spell","global cd spell"} },
    { label="Show castbar glow effect",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarGlowCheck",
      keywords={"castbar glow","cast glow","glow effect","glow animation","castbar shine"} },
    { label="Show latency indicator",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarLatencyCheck",
      keywords={"latency","lag","ping","ms lag","latency bar","latency indicator","lag indicator"} },
    { label="Shake on interrupt (castbar animation)",
      hint="Castbar", pageKey="opt_castbar",
      keywords={"shake interrupt","castbar shake","interrupt shake","shake animation","interrupted animation"} },
    { label="Shake intensity (castbar)",
      hint="Castbar", pageKey="opt_castbar",
      keywords={"shake intensity","shake strength","shake amount","interrupt shake strength"} },
    { label="Add color to stages (Empowered casts)",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_EmpowerColorStagesCheck",
      keywords={"empower color","stage color","empowered color","evoker stage color","add color stages"} },
    { label="Add stage blink (Empowered casts)",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_EmpowerStageBlinkCheck",
      keywords={"stage blink","empower blink","empowered blink","evoker blink","blink animation empower"} },
    { label="Texture and Empowered Cast settings",
      hint="Castbar", pageKey="opt_castbar",
      keywords={"texture empowered","empowered cast settings","castbar texture empowered","empower section"} },
    { label="Castbar fill direction section (Behavior / Style)",
      hint="Castbar", pageKey="opt_castbar",
      keywords={"castbar behavior","castbar style","castbar section","behavior style castbar"} },
    { label="Focus Kick (interrupt button on focus castbar)",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarFocusButton",
      keywords={"focus kick","kick button","interrupt button","focus castbar button","focus kick icon","focus interrupt","kick icon"} },
    { label="Shorten spell name on castbar (max length / font size)",
      hint="Castbar", pageKey="opt_castbar",anchor="MSUF_CastbarSpellNameShortenToggle",
      keywords={"shorten spell name","spell name length","castbar spell name","truncate cast name","max spell length","spell name short","castbar name max"} },
    { label="Bar texture Foreground (SharedMedia)",
      hint="Bars › Texture", pageKey="opt_bars",anchor="MSUF_BarTextureDropdown",
      keywords={"bar texture","foreground texture","hp bar texture","bar skin","bar look","lsm bar"} },
    { label="Bar background texture (SharedMedia)",
      hint="Bars › Texture", pageKey="opt_bars",anchor="MSUF_BarBackgroundTextureDropdown",
      keywords={"bar background texture","bg texture","empty bar texture","unfilled bar","bar bg"} },
    { label="Absorb display (off / bar / bar+text / text only)",
      hint="Bars › Absorb", pageKey="opt_bars",anchor="MSUF_AbsorbDisplayDrop",
      keywords={"absorb display","absorb off","absorb bar","absorb text","shield display","absorb mode","show absorb","absorb overlay"} },
    { label="Absorb bar anchoring (Anchor to left / right / Follow HP / Reverse from max)",
      hint="Bars › Absorb", pageKey="opt_bars",anchor="MSUF_AbsorbAnchorDrop",
      keywords={"absorb anchoring","absorb anchor","absorb left","absorb right","follow hp bar","reverse from max","absorb direction","anchor to left side","anchor to right side"} },
    { label="Absorb bar texture (SharedMedia)",
      hint="Bars › Absorb", pageKey="opt_bars",anchor="MSUF_AbsorbBarTextureDropdown",
      keywords={"absorb texture","shield texture","absorb bar texture","absorb skin"} },
    { label="Heal-Absorb bar texture (SharedMedia)",
      hint="Bars › Absorb", pageKey="opt_bars",anchor="MSUF_HealAbsorbBarTextureDropdown",
      keywords={"heal absorb texture","mortal wounds texture","heal-absorb","heal absorb skin"} },
    { label="Enable HP bar gradient",
      hint="Bars › Gradient", pageKey="opt_bars",
      keywords={"hp gradient","health gradient","enable gradient","gradient hp","bar gradient","gradient health"} },
    { label="Enable power bar gradient",
      hint="Bars › Gradient", pageKey="opt_bars",
      keywords={"power gradient","mana gradient","enable gradient power","gradient mana","gradient power"} },
    { label="Gradient Options / Gradient strength / direction",
      hint="Bars › Gradient", pageKey="opt_bars",anchor="MSUF_GradientDirectionPad",
      keywords={"gradient options","gradient strength","gradient direction","gradient intensity","color fade strength","fade intensity","gradient settings"} },
    { label="Power bar height",
      hint="Bars › Power Bar", pageKey="opt_bars",anchor="MSUF_PowerBarHeightEdit",
      keywords={"power bar height","mana bar height","power height","thin mana","mana height","resource bar size"} },
    { label="Border thickness (power bar)",
      hint="Bars › Power Bar", pageKey="opt_bars",anchor="MSUF_PowerBarBorderSizeEdit",
      keywords={"border thickness","power bar border size","mana border","power border width"} },
    { label="Show power bar on target / boss / player / focus",
      hint="Bars › Power Bar", pageKey="opt_bars",
      keywords={"show power bar","enable power bar","mana bar on","power bar target","power bar boss","power bar player","power bar focus","show mana","resource bar show"} },
    { label="Show power bar border",
      hint="Bars › Power Bar", pageKey="opt_bars",
      keywords={"power bar border","mana bar border","show border power","power border","mana outline"} },
    { label="Embed power bar into health bar",
      hint="Bars › Power Bar", pageKey="opt_bars",
      keywords={"embed power bar","mana in hp bar","combined bar","integrate mana","embed mana","single bar","combine bars","power inside health"} },
    { label="Power Bar Settings section",
      hint="Bars › Power Bar", pageKey="opt_bars",
      keywords={"power bar settings","power settings section","mana bar settings"} },
    { label="Bar scope: Shared / per-unit override",
      hint="Bars › Scope", pageKey="opt_bars",anchor="MSUF_HPTextScopeDropdown",
      keywords={"bar scope","shared bar","per unit bar","configure settings for","unit override bar","different bar per unit","bar settings scope"} },
    { label="Textmode HP / Power (Full value / Cur/Max / Percent etc)",
      hint="Bars › Text Mode", pageKey="opt_bars",anchor="MSUF_HPTextModeDropdown",
      keywords={"textmode","text mode","hp format","power format","full value only","cur max","percent","cur + percent","curmax + percent","textmode hp","textmode power","number format"} },
    { label="Power text mode",
      hint="Bars › Text Mode", pageKey="opt_bars",anchor="MSUF_PowerTextModeDropdown",
      keywords={"power text mode","mana text mode","power format","resource text mode"} },
    { label="Text Separators — Health (HP)",
      hint="Bars › Text Mode", pageKey="opt_bars",anchor="MSUF_HPTextSeparatorDropdown",
      keywords={"text separators","hp separator","health separator","number divider","between numbers","separator text","slash divider","| separator"} },
    { label="Power Spacer on/off + X offset",
      hint="Bars › Text Mode", pageKey="opt_bars",anchor="MSUF_PowerTextSpacerCheck",
      keywords={"power spacer","mana spacer","power text x","power text offset","spacer power"} },
    { label="HP Spacer on/off + X offset",
      hint="Bars › Text Mode", pageKey="opt_bars",anchor="MSUF_HPTextSpacerCheck",
      keywords={"hp spacer","health spacer","hp text x","hp text offset","spacer hp","health spacer"} },
    { label="Bar Animation + Text Accuracy (C-side interpolation)",
      hint="Bars › Performance", pageKey="opt_bars",
      keywords={"bar animation","text accuracy","c-side interpolation","fluid bar","animation accuracy","bar accuracy","c side","smooth animation bar"} },
    { label="Smooth power bar (C-side interpolation)",
      hint="Bars › Performance", pageKey="opt_bars",anchor="MSUF_SmoothPowerBarCheck",
      keywords={"smooth power bar","smooth bar","animated bar","interpolation bar","fluid power","bar lag","snap bar","delayed bar","smooth mana"} },
    { label="Real-time power text (update every event)",
      hint="Bars › Performance", pageKey="opt_bars",anchor="MSUF_RealtimePowerTextCheck",
      keywords={"real-time power text","realtime text","update every event","accurate text","live text","pixel accurate text","real time mana","update text every event","higher cpu text"} },
    { label="Reset all overrides (bars)",
      hint="Bars › Scope", pageKey="opt_bars",anchor="MSUF_HPTextResetOverridesBtn",
      keywords={"reset all overrides","clear overrides","reset bar overrides","undo overrides","revert overrides"} },
    { label="Name shortening (max length / truncation / reserved space)",
      hint="Bars › Name", pageKey="opt_bars",
      keywords={"name shortening","shorten name","max name length","truncate name","name max","name abbrev"} },
    { label="Aggro border on / off — Target, Focus, Boss frames",
      hint="Bars › Borders", pageKey="opt_bars",anchor="MSUF_AggroOutlineDropdown",
      keywords={"aggro border","aggro outline","threat border","aggro on off","aggro indicator","aggro border target focus boss"} },
    { label="Dispel border on / off — Player, Target, Focus, ToT",
      hint="Bars › Borders", pageKey="opt_bars",anchor="MSUF_DispelOutlineDropdown",
      keywords={"dispel border","dispel outline","magic border","curse border","poison border","disease border","dispel indicator","can dispel","dispel border player target"} },
    { label="Purge border on / off — Target, Focus, ToT",
      hint="Bars › Borders", pageKey="opt_bars",anchor="MSUF_PurgeOutlineDropdown",
      keywords={"purge border","purge outline","spellsteal border","removable border","purgeable","can purge","purge indicator"} },
    { label="Outline thickness (bar borders)",
      hint="Bars › Borders", pageKey="opt_bars",
      keywords={"outline thickness","border width","bar border thickness","outline size","border thickness"} },
    { label="Bar Highlight Border — drag to reorder priority (Aggro / Dispel / Purge)",
      hint="Bars › Borders", pageKey="opt_bars",anchor="MSUF_HighlightPrioContainer",
      keywords={"bar highlight border","border priority","highlight priority","drag reorder","aggro dispel purge priority","custom highlight priority","left-click drag priority","highlight order"} },
    { label="Open Auras 2.0 (shortcut from Bars panel)",
      hint="Bars", pageKey="opt_bars",
      keywords={"open auras","auras 2.0","go to auras","auras button","open auras 2.0"} },
    { label="Border & Text Options section",
      hint="Bars", pageKey="opt_bars",
      keywords={"border text options","border section","text options section"} },
    { label="Font selection (SharedMedia)",
      hint="Fonts", pageKey="opt_fonts",
      keywords={"font selection","choose font","change font","font name","typeface","which font","font picker","custom font","sharedmedia font","lsm font"} },
    { label="Font size",
      hint="Fonts", pageKey="opt_fonts",
      keywords={"font size","text size","bigger font","smaller font","font pt","font px","increase font"} },
    { label="Font outline (Shadow / Outline / Thick / Monochrome / None)",
      hint="Fonts", pageKey="opt_fonts",
      keywords={"font outline","text shadow","outline style","thick outline","monochrome","no outline","font border","shadow text","outline off","thickoutline"} },
    { label="Overrides section (Fonts)",
      hint="Fonts › Overrides", pageKey="opt_fonts",
      keywords={"font overrides","overrides section","font override"} },
    { label="Reset overrides (Fonts)",
      hint="Fonts › Overrides", pageKey="opt_fonts",anchor="MSUF_ResetFontOverridesBtn",
      keywords={"reset font overrides","clear font override","default font","restore font","reset overrides"} },
    { label="Truncation style (keep start / keep end)",
      hint="Fonts › Name Shortening", pageKey="opt_fonts",
      keywords={"truncation style","keep start","keep end","truncate style","name cut style"} },
    { label="Max name length",
      hint="Fonts › Name Shortening", pageKey="opt_fonts",anchor="MSUF_ShortenNameMaxCharsSlider",
      keywords={"max name length","name max chars","shorten max","name length max","max chars name"} },
    { label="Reserved space / Reserved space left / Reserved space unused",
      hint="Fonts › Name Shortening", pageKey="opt_fonts",anchor="MSUF_ShortenNameFrontMaskSlider",
      keywords={"reserved space","reserved left","reserved unused","front mask","name reserved space"} },
    { label="Name Shortening section",
      hint="Fonts › Name Shortening", pageKey="opt_fonts",
      keywords={"name shortening","shorten names","name abbreviation","name shortening section"} },
    { label="Font color presets: White / Black / Red / Green / Blue / Yellow / Cyan / Magenta / Orange / Purple / Pink / Turquoise / Grey / Brown / Gold",
      hint="Fonts", pageKey="opt_fonts",
      keywords={"font color","text color","colour","white","black","red","green","blue","yellow","cyan","magenta","orange","purple","pink","turquoise","grey","gray","brown","gold","schrift farbe","text colour","font palette","font color preset"} },
    { label="Auras 2.0 — main panel",
      hint="Auras 2.0", pageKey="auras2",
      keywords={"auras 2.0","auras","buffs","debuffs","buff icons","aura panel","open auras","auras2"} },
    { label="Enable Auras 2.0",
      hint="Auras 2.0", pageKey="auras2",
      keywords={"enable auras","turn on auras","aura enable","auras on off"} },
    { label="Enable filters",
      hint="Auras 2.0", pageKey="auras2",
      keywords={"enable filters","filter on","aura filter","activate filter","filtering"} },
    { label="Enable Masque skinning",
      hint="Auras 2.0", pageKey="auras2",
      keywords={"masque skinning","masque enable","masque support","use masque","icon skin masque"} },
    { label="Hide Masque borders",
      hint="Auras 2.0", pageKey="auras2",
      keywords={"hide masque borders","masque no border","masque border off","remove masque border"} },
    { label="Override shared filters (per unit)",
      hint="Auras 2.0", pageKey="auras2",
      keywords={"override shared filters","filter override","per unit filter","unit filter override"} },
    { label="Override shared caps (per unit)",
      hint="Auras 2.0", pageKey="auras2",
      keywords={"override shared caps","cap override","per unit caps","unit caps override"} },
    { label="Preview in Edit Mode",
      hint="Auras 2.0", pageKey="auras2",
      keywords={"preview edit mode","aura preview","buff preview","show auras edit mode","test auras edit"} },
    { label="Show Buffs",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"show buffs","display buffs","enable buffs","helpful auras","positive auras","buff display"} },
    { label="Show Debuffs",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"show debuffs","display debuffs","enable debuffs","harmful auras","negative auras","debuff display"} },
    { label="Only my buffs",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"only my buffs","mine buffs","own buffs","self buffs","player cast only","just mine buffs"} },
    { label="Only my debuffs",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"only my debuffs","mine debuffs","own debuffs","self debuffs","just mine debuffs"} },
    { label="Highlight own buffs",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"highlight own buffs","own buff border","mark own buffs","my buff highlight"} },
    { label="Highlight own debuffs",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"highlight own debuffs","own debuff border","mark own debuffs","my debuff highlight"} },
    { label="Dispel-type borders (on debuffs)",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"dispel-type borders","debuff type border","magic curse poison disease border","dispel color border","debuff border type"} },
    { label="Show cooldown swipe (spiral animation)",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"cooldown swipe","swipe animation","spiral aura","sweep","radial cooldown","show cooldown swipe"} },
    { label="Swipe darkens on loss",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"swipe darkens","darker on loss","swipe dark","cooldown swipe dark","darken swipe"} },
    { label="Show stack count",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"show stack count","stack count","stacks","buff stacks","charge count","charges display"} },
    { label="Show cooldown text (timer on icons)",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"show cooldown text","cooldown numbers","timer on icons","duration text","omnicc","aura timer","cd text aura","buff timer","remaining text"} },
    { label="Show tooltip (hover over icons)",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"show tooltip","aura tooltip","buff tooltip","hover tooltip","icon tooltip","mouse tooltip"} },
    { label="Click-through auras",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"click-through auras","clickthrough","mouse passthrough","click through","aura click through"} },
    { label="Hide permanent buffs",
      hint="Auras 2.0 › Display", pageKey="auras2",
      keywords={"hide permanent buffs","permanent buff","infinite duration","no permanent","hide infinite"} },
    { label="Layout — Single row / Separate rows",
      hint="Auras 2.0 › Layout", pageKey="auras2",
      keywords={"layout","single row","separate rows","aura layout","one row","buff row","debuff row"} },
    { label="Buff Growth (Grow Right / Grow Left / Vertical Down / Vertical Up)",
      hint="Auras 2.0 › Layout", pageKey="auras2",
      keywords={"buff growth","grow right","grow left","vertical down","vertical up","buff direction","expand direction","buff expand"} },
    { label="Debuff Growth direction",
      hint="Auras 2.0 › Layout", pageKey="auras2",
      keywords={"debuff growth","debuff direction","debuff expand","grow direction debuff"} },
    { label="Buff wrap rows",
      hint="Auras 2.0 › Layout", pageKey="auras2",
      keywords={"buff wrap rows","buff overflow","buff second row","wrap buffs","buff row wrap"} },
    { label="Debuff wrap rows",
      hint="Auras 2.0 › Layout", pageKey="auras2",
      keywords={"debuff wrap rows","debuff overflow","debuff second row","wrap debuffs"} },
    { label="Icons per row",
      hint="Auras 2.0 › Layout", pageKey="auras2",
      keywords={"icons per row","icons row","aura columns","per row","how many per row","row count"} },
    { label="Max Buffs (cap)",
      hint="Auras 2.0 › Layout", pageKey="auras2",
      keywords={"max buffs","buff cap","maximum buffs","buff limit","how many buffs","buff count max"} },
    { label="Max Debuffs (cap)",
      hint="Auras 2.0 › Layout", pageKey="auras2",
      keywords={"max debuffs","debuff cap","maximum debuffs","debuff limit","debuff count max"} },
    { label="Stack Anchor (Top Left / Top Right / Bottom Left / Bottom Right)",
      hint="Auras 2.0 › Layout", pageKey="auras2",
      keywords={"stack anchor","where stack","anchor stack","top left","top right","bottom left","bottom right","stack position","second row anchor"} },
    { label="Block spacing (gap between icons)",
      hint="Auras 2.0 › Layout", pageKey="auras2",
      keywords={"block spacing","icon gap","buff spacing","space between auras","icon spacing","padding"} },
    { label="Sort order (Unsorted / Default / Big Defensive / Expiration / Name)",
      hint="Auras 2.0 › Sort", pageKey="auras2",anchor="MSUF_Auras2_SortOrderDropDown",
      keywords={"sort order","sort auras","buff sort","unsorted","default sort","big defensive","expiration sort","expiration only","name alphabetical","name only","aura order","sort by"} },
    { label="Edit filters (per unit)",
      hint="Auras 2.0 › Advanced", pageKey="auras2",anchor="MSUF_Auras2_EditFiltersDropDown",
      keywords={"edit filters","filter editor","per unit filter","custom filter","unit filter","whitelist","blacklist","advanced filter","filter auras"} },
    { label="Units — which units show auras",
      hint="Auras 2.0 › Units", pageKey="auras2",
      keywords={"aura units","which units aura","player auras","target auras","focus auras","boss auras","unit aura list","aura on unit"} },
    { label="Include boss buffs",
      hint="Auras 2.0 › Advanced", pageKey="auras2",
      keywords={"include boss buffs","boss buffs","show boss buffs","include boss"} },
    { label="Include boss debuffs",
      hint="Auras 2.0 › Advanced", pageKey="auras2",
      keywords={"include boss debuffs","boss debuffs","show boss debuffs"} },
    { label="Show Sated / Bloodlust / Exhaustion / Temporal Displacement",
      hint="Auras 2.0 › Advanced", pageKey="auras2",
      keywords={"sated","exhaustion","bloodlust","heroism","temporal displacement","lust","bl","time warp","ancient hysteria","hide lust","sated debuff","show sated","bloodlust filter"} },
    { label="Only show boss auras",
      hint="Auras 2.0 › Advanced", pageKey="auras2",
      keywords={"only boss auras","boss only auras","boss filter auras","show only boss"} },
    { label="Only show IMPORTANT buffs",
      hint="Auras 2.0 › Advanced", pageKey="auras2",
      keywords={"only important buffs","important only buffs","major buffs","important buffs filter"} },
    { label="Only show IMPORTANT debuffs",
      hint="Auras 2.0 › Advanced", pageKey="auras2",
      keywords={"only important debuffs","important only debuffs","major debuffs","important debuffs filter"} },
    { label="Private Auras — Enable / Show Player / Focus / Boss",
      hint="Auras 2.0 › Private Auras", pageKey="auras2",
      keywords={"private auras","blizzard private","private aura enable","show private player","show private focus","show private boss","private anchor"} },
    { label="Private Auras — Max (Player) / Max (Focus/Boss)",
      hint="Auras 2.0 › Private Auras", pageKey="auras2",
      keywords={"private max","max player private","max focus private","max boss private","private aura limit"} },
    { label="Global Ignore List — Raid Buffs",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"global ignore list raid buffs","global ignore list","ignore list","raid buffs","raid buffs","flask food","well fed","ignore raid buffs","buff suppress"} },
    { label="Global Ignore List — Blessing of the Bronze",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"global ignore list blessing of the bronze","global ignore list","ignore list","blessing of the bronze","blessing of the bronze","bronze blessing","evoker buff bronze","ignore bronze"} },
    { label="Global Ignore List — Healer HoTs",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"global ignore list healer hots","global ignore list","ignore list","healer hots","healer hots","renew","rejuvenation","regrowth","hots ignore","heal over time ignore"} },
    { label="Global Ignore List — Rogue Poisons",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"global ignore list rogue poisons","global ignore list","ignore list","rogue poisons","rogue poisons","lethal poison","non-lethal poison","ignore poison","rogue poison ignore"} },
    { label="Global Ignore List — Shaman Imbuements",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"global ignore list shaman imbuements","global ignore list","ignore list","shaman imbuements","shaman imbuements","flametongue","windfury","imbue","shaman weapon buff"} },
    { label="Global Ignore List — Deserter",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"global ignore list deserter","global ignore list","ignore list","deserter","deserter","battleground leave","bg deserter","ignore deserter"} },
    { label="Global Ignore List — Skyriding",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"global ignore list skyriding","global ignore list","ignore list","skyriding","skyriding","vigor","skyriding buff","sky riding","ignore skyriding"} },
    { label="Global Ignore List — Long-term Self Buffs",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"global ignore list long-term self buffs","global ignore list","ignore list","long-term self buffs","long-term self buffs","long term buff","permanent self buff","ignore long-term"} },
    { label="Global Ignore List — Resource-like Auras",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"global ignore list resource-like auras","global ignore list","ignore list","resource-like auras","resource-like auras","resource aura","ignore resource","resource like"} },
    { label="Global Ignore List — Cooldowns",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"global ignore list cooldowns","global ignore list","ignore list","cooldowns","cooldowns ignore","ignore cooldowns","cd ignore","hide cooldowns"} },
    { label="Override for this unit (Ignore List)",
      hint="Auras 2.0 › Global Ignore List", pageKey="auras2",
      keywords={"override for this unit","ignore list override","unit override ignore","local ignore"} },
    { label="Buff Reminder — Power Word: Fortitude",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"buff reminder power word: fortitude","buff reminder","missing buff reminder","remind power word: fortitude","buff missing","power word: fortitude","pw:f","fort","fortitude","priest stamina","fortitude buff","power word fortitude","pw fortitude","pfort"} },
    { label="Buff Reminder — Arcane Intellect",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"buff reminder arcane intellect","buff reminder","missing buff reminder","remind arcane intellect","buff missing","arcane intellect","arcane intellect","ai buff","mage intellect","intellect buff","arcane int"} },
    { label="Buff Reminder — Mark of the Wild",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"buff reminder mark of the wild","buff reminder","missing buff reminder","remind mark of the wild","buff missing","mark of the wild","mark of the wild","motw","druid buff","mark wild","wild mark","nature resist buff","stats buff","motw reminder"} },
    { label="Buff Reminder — Battle Shout",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"buff reminder battle shout","buff reminder","missing buff reminder","remind battle shout","buff missing","battle shout","battle shout","battleshout","warrior buff","attack power buff","bs buff"} },
    { label="Buff Reminder — Skyfury",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"buff reminder skyfury","buff reminder","missing buff reminder","remind skyfury","buff missing","skyfury","skyfury","sky fury","shaman crit buff","crit buff"} },
    { label="Buff Reminder — Source of Magic",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"buff reminder source of magic","buff reminder","missing buff reminder","remind source of magic","buff missing","source of magic","source of magic","som","mana regen buff","healer mana buff","source magic"} },
    { label="Buff Reminder — Blessing of the Bronze",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"buff reminder blessing of the bronze","buff reminder","missing buff reminder","remind blessing of the bronze","buff missing","blessing of the bronze","blessing of the bronze","bronze blessing","bronze buff","evoker bronze"} },
    { label="Buff Reminder — Lethal Poison (Rogue)",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"buff reminder lethal poison (rogue)","buff reminder","missing buff reminder","remind lethal poison (rogue)","buff missing","lethal poison (rogue)","lethal poison","lethal poison rogue","weapon poison lethal","rogue lethal"} },
    { label="Buff Reminder — Non-Lethal Poison (Rogue)",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"buff reminder non-lethal poison (rogue)","buff reminder","missing buff reminder","remind non-lethal poison (rogue)","buff missing","non-lethal poison (rogue)","non-lethal poison","non lethal","crippling poison","rogue utility poison","non lethal rogue"} },
    { label="Enable Buff Reminders",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"enable buff reminders","buff reminder enable","missing buff","ghost icon","rebuff","pre-buff","remind buff","buff alert","reminder system"} },
    { label="Expiry Warning — show reminder when buff expires within X seconds",
      hint="Auras 2.0 › Buff Reminders", pageKey="auras2",
      keywords={"expiry warning","buff expiry","expire warning","about to expire","expiry threshold","buffer timer warning","buff warning","running out","0 only when missing"} },
    { label="Class Power — enable class resource bar (Combo Points, Holy Power, Soul Shards, Chi, Essence, Runes)",
      hint="Class Resources", pageKey="classpower",anchor="MSUF_ClassPowerShowCheck",
      keywords={"class power","resource bar","combo points","holy power","soul shards","chi","essence","runes","enable class power","class bar","class resource","class power bar"} },
    { label="Show resource text (number on class bar)",
      hint="Class Resources", pageKey="classpower",anchor="MSUF_ClassPowerTextCheck",
      keywords={"resource text","show text class","combo number","chi number","class text","count text"} },
    { label="Show empowered / charged combo points",
      hint="Class Resources", pageKey="classpower",anchor="MSUF_ShowChargedCPCheck",
      keywords={"empowered combo","charged combo","charged cp","enhanced cp","show empowered","combo charged"} },
    { label="Show rune time per rune (Death Knight)",
      hint="Class Resources", pageKey="classpower",anchor="MSUF_RuneTimeTextCheck",
      keywords={"rune time","rune timer","dk rune","death knight rune","rune cd","per rune","rune cooldown text"} },
    { label="Fill right-to-left (class power bar)",
      hint="Class Resources", pageKey="classpower",anchor="MSUF_ClassPowerReverseCheck",
      keywords={"fill right to left","rtl class power","reverse fill class","class bar reverse"} },
    { label="Show Maelstrom bar (Elemental Shaman)",
      hint="Class Resources", pageKey="classpower",anchor="MSUF_ClassPowerEleMaelCheck",
      keywords={"maelstrom bar","elemental shaman","ele maelstrom","show maelstrom","maelstrom elemental"} },
    { label="Show Ebon Might timer (Augmentation Evoker)",
      hint="Class Resources", pageKey="classpower",anchor="MSUF_ClassPowerEbonMightCheck",
      keywords={"ebon might","ebon might timer","aug evoker","augmentation timer","ebon timer"} },
    { label="Anchor to Essential Cooldown (CDM/ECV)",
      hint="Class Resources", pageKey="classpower",anchor="MSUF_ClassPowerAnchorCooldownCheck",
      keywords={"anchor essential cooldown","cdm anchor","ecv anchor","essential cooldown class power","anchor to essential","cdm class power"} },
    { label="Match width (Player frame / CDM / Utility / Tracked Buffs / Custom / Manual)",
      hint="Class Resources", pageKey="classpower",anchor="MSUF_CPWidthModeDrop",
      keywords={"match width","class power width","sync width","cdm width","ecv width","width match","player frame width","utility width","tracked buffs width","class bar width","manual width"} },
    { label="Auto-Hide: hide out of combat",
      hint="Class Resources › Auto-Hide", pageKey="classpower",anchor="MSUF_ClassPowerHideOOC",
      keywords={"hide out of combat","auto hide ooc","class power ooc","resource ooc","hide when ooc"} },
    { label="Auto-Hide: hide when full",
      hint="Class Resources › Auto-Hide", pageKey="classpower",anchor="MSUF_ClassPowerHideFull",
      keywords={"hide when full","full hide class","class power full","resource full","hide at max"} },
    { label="Auto-Hide: hide when empty",
      hint="Class Resources › Auto-Hide", pageKey="classpower",anchor="MSUF_ClassPowerHideEmpty",
      keywords={"hide when empty","empty hide class","class power empty","resource empty","hide at zero"} },
    { label="Alternative Mana Bar — Shadow, Ret, Ele, Enh, Balance, Feral, WW",
      hint="Class Resources › Alt Mana", pageKey="classpower",anchor="MSUF_AltManaShowCheck",
      keywords={"alternative mana bar","alt mana","dual resource","shadow priest mana","ret mana","ele mana","enh mana","balance mana","feral mana","ww mana","secondary mana","alt mana bar","shadow ret ele enh balance feral ww"} },
    { label="Detached Power Bar — foreground / background texture / width mode / outline",
      hint="Class Resources › Detached Power Bar", pageKey="classpower",anchor="MSUF_DPBFgTextureDropdown",
      keywords={"detached power bar","dpb","detach bar","standalone power bar","detach power","separate power","dpb texture","dpb width","dpb outline","detached power bar texture"} },
    { label="Only applies when power bar is detached",
      hint="Class Resources › Detached Power Bar", pageKey="classpower",
      keywords={"only when detached","detach note","detached only","power bar detached note"} },
    { label="Use foreground texture / Use global bar texture (class power)",
      hint="Class Resources › Style", pageKey="classpower",anchor="MSUF_CPFgTextureDropdown",
      keywords={"use foreground texture","use global bar texture","class power texture","cp texture","foreground texture cp"} },
    { label="Background texture (class power)",
      hint="Class Resources › Style", pageKey="classpower",anchor="MSUF_CPBgTextureDropdown",
      keywords={"background texture class power","cp background texture","class bar bg texture"} },
    { label="Class color (class power bar)",
      hint="Class Resources › Style", pageKey="classpower",anchor="MSUF_ClassPowerColorCheck",
      keywords={"class color class power","class power color","cp class color","resource class color"} },
    { label="Colors, textures & visual tweaks (class power style section)",
      hint="Class Resources › Style", pageKey="classpower",
      keywords={"colors textures visual","class power style","cp style section","visual tweaks class"} },
    { label="Style section (class power)",
      hint="Class Resources › Style", pageKey="classpower",
      keywords={"style class power","class power style","cp style","resource bar style"} },
    { label="Essential Cooldowns / Utility Cooldowns / Tracked Buffs (width anchor sources)",
      hint="Class Resources", pageKey="classpower",
      keywords={"essential cooldowns","utility cooldowns","tracked buffs","cdm","ecv","width source","cooldown source width"} },
    { label="Class Power — Edit Mode button",
      hint="Class Resources", pageKey="classpower",anchor="MSUF_ClassPower_EditModeButton",
      keywords={"class power edit mode","edit class power","move class power","reposition resource bar"} },
    { label="Enable in-combat timer",
      hint="Gameplay › Combat Timer", pageKey="gameplay",anchor="MSUF_Gameplay_CombatTimerCheck",
      keywords={"in-combat timer","combat timer","fight timer","combat clock","combat duration","how long combat"} },
    { label="Lock position (combat timer)",
      hint="Gameplay › Combat Timer", pageKey="gameplay",anchor="MSUF_Gameplay_LockCombatTimerCheck",
      keywords={"lock position combat timer","timer locked","pin timer","fix timer position"} },
    { label="Click-through — ALT to drag when unlocked (combat timer)",
      hint="Gameplay › Combat Timer", pageKey="gameplay",anchor="MSUF_Gameplay_CombatTimerClickThroughCheck",
      keywords={"click through timer","combat timer click through","alt drag timer","clickthrough timer"} },
    { label="Show combat enter / leave text",
      hint="Gameplay › Combat State", pageKey="gameplay",anchor="MSUF_Gameplay_CombatStateCheck",
      keywords={"combat enter text","combat leave text","show combat state","in combat text","ooc text","entering combat text","leaving combat text","combat state text"} },
    { label="Lock position (combat state text)",
      hint="Gameplay › Combat State", pageKey="gameplay",anchor="MSUF_Gameplay_CombatStateLockCheck",
      keywords={"lock combat text","combat state locked","pin combat text","fix combat text"} },
    { label="Enable Totem tracker (Shaman)",
      hint="Gameplay › Class Toggles", pageKey="gameplay",anchor="MSUF_Gameplay_PlayerTotemsCheck",
      keywords={"totem tracker","shaman totem","enable totem","totem bar","fire earth water air totem"} },
    { label="Show cooldown text (Totem tracker)",
      hint="Gameplay › Class Toggles", pageKey="gameplay",anchor="MSUF_Gameplay_PlayerTotemsShowTextCheck",
      keywords={"totem cooldown text","totem timer","totem cd text","show totem timer","totem remaining"} },
    { label="Scale text by icon size (Totem tracker)",
      hint="Gameplay › Class Toggles", pageKey="gameplay",anchor="MSUF_Gameplay_PlayerTotemsScaleTextCheck",
      keywords={"scale text totem","totem text scale","totem font scale","scale by icon"} },
    { label="Track 'The First Dance' (6s after leaving combat)",
      hint="Gameplay › Class Toggles", pageKey="gameplay",anchor="MSUF_Gameplay_FirstDanceCheck",
      keywords={"first dance","the first dance","6s timer","after combat rogue","rogue timer","leaving combat timer","6.0 first dance"} },
    { label="Show green combat crosshair under player (in combat)",
      hint="Gameplay › Combat Crosshair", pageKey="gameplay",anchor="MSUF_Gameplay_CombatCrosshairCheck",
      keywords={"combat crosshair","green circle","green crosshair","feet indicator","crosshair combat","circle under player","show crosshair","range indicator"} },
    { label="Crosshair: color by melee range (green=in range, red=out)",
      hint="Gameplay › Combat Crosshair", pageKey="gameplay",anchor="MSUF_Gameplay_CrosshairRangeColorCheck",
      keywords={"crosshair range color","melee range crosshair","green red crosshair","in range out range","crosshair color range","melee indicator color"} },
    { label="Crosshair melee spell (spell ID / name input)",
      hint="Gameplay › Crosshair Spell", pageKey="gameplay",anchor="MSUF_Gameplay_MeleeSpellInput",
      keywords={"melee spell","crosshair spell","range spell","melee range spell","spell id input","choose spell","type spell id"} },
    { label="Store per class (melee range spell)",
      hint="Gameplay › Crosshair Spell", pageKey="gameplay",anchor="MSUF_Gameplay_MeleeSpellPerClassCheck",
      keywords={"store per class","per class spell","class spell","remember per class","class melee spell"} },
    { label="Store per spec (melee range spell)",
      hint="Gameplay › Crosshair Spell", pageKey="gameplay",anchor="MSUF_Gameplay_MeleeSpellPerSpecCheck",
      keywords={"store per spec","per spec spell","spec spell","remember per spec","spec melee spell"} },
    { label="Tip: Gameplay colors are in Colors > Gameplay",
      hint="Gameplay", pageKey="gameplay",
      keywords={"gameplay colors","where colors gameplay","crosshair color where","timer color where","totem color where","tip gameplay"} },
    { label="Preview (crosshair preview)",
      hint="Gameplay", pageKey="gameplay",anchor="MSUF_Gameplay_CrosshairPreview",
      keywords={"crosshair preview","preview crosshair","test crosshair","show crosshair demo"} },
    { label="Unit update interval (Perf / Balanced / Accurate)",
      hint="Miscellaneous › Performance", pageKey="opt_misc",anchor="MSUF_UpdateIntervalSlider",
      keywords={"update interval","unit update","refresh rate","performance balanced accurate","how often update","polling rate","reduce cpu","update frequency"} },
    { label="Castbar update interval",
      hint="Miscellaneous › Performance", pageKey="opt_misc",anchor="MSUF_CastbarUpdateIntervalSlider",
      keywords={"castbar update interval","cast update","castbar refresh","cast polling","castbar smooth"} },
    { label="UFCore flush budget (ms)",
      hint="Miscellaneous › Performance", pageKey="opt_misc",anchor="MSUF_UFCoreFlushBudgetSlider",
      keywords={"ufcore flush budget","flush budget","core budget","ms budget","frame budget","ufcore ms"} },
    { label="UFCore urgent cap",
      hint="Miscellaneous › Performance", pageKey="opt_misc",anchor="MSUF_UFCoreUrgentCapSlider",
      keywords={"ufcore urgent cap","urgent cap","priority cap","update cap","core urgent"} },
    { label="Disable MSUF unit info panel tooltips",
      hint="Miscellaneous › Unit Info Panel", pageKey="opt_misc",anchor="MSUF_InfoTooltipDisableCheck",
      keywords={"disable tooltips","no tooltip","hide tooltip","info panel tooltip off","unit info tooltip"} },
    { label="Unit info panel position (Blizzard Classic / Modern under cursor)",
      hint="Miscellaneous › Unit Info Panel", pageKey="opt_misc",anchor="MSUF_InfoTooltipPosDropdown",
      keywords={"tooltip position","info panel position","blizzard classic tooltip","modern under cursor","where tooltip","tooltip placement","unit info position"} },
    { label="Disable Blizzard unitframes",
      hint="Miscellaneous › Blizzard Frames", pageKey="opt_misc",anchor="MSUF_DisableBlizzUFCheck",
      keywords={"disable blizzard","blizzard unitframes","hide default frames","remove stock ui","blizzard frames off","native frames off","disable blizzard unitframes"} },
    { label="Hide Blizzard PlayerFrame (turn off for other addon compatibility)",
      hint="Miscellaneous › Blizzard Frames", pageKey="opt_misc",
      keywords={"hide blizzard player frame","blizzard player hide","playerframe hide","addon compatibility frame","blizzard player frame off","hide blizzard playerframe"} },
    { label="Fully Hide Blizzard PlayerFrame (resource bar compatibility)",
      hint="Miscellaneous › Blizzard Frames", pageKey="opt_misc",anchor="MSUF_HardKillPlayerFrameCheck",
      keywords={"fully hide blizzard playerframe","fully hide player","resource bar compatibility","classbars compat","bartender compat","hard kill playerframe"} },
    { label="Show MSUF minimap icon",
      hint="Miscellaneous", pageKey="opt_misc",anchor="MSUF_MinimapIconCheck",
      keywords={"minimap icon","minimap button","show minimap","minimap broker","hide minimap icon"} },
    { label="Play sound on Target / Target Lost",
      hint="Miscellaneous", pageKey="opt_misc",anchor="MSUF_TargetSoundsCheck",
      keywords={"target sound","sound target","play sound","target acquire","target lost sound","audio target"} },
    { label="Show welcome message on login",
      hint="Miscellaneous", pageKey="opt_misc",anchor="MSUF_ShowWelcomeMessageCheck",
      keywords={"welcome message","login message","startup message","show welcome","greet on login"} },
    { label="Enable version check (peer-to-peer)",
      hint="Miscellaneous", pageKey="opt_misc",anchor="MSUF_VersionCheckEnabledCheck",
      keywords={"version check","peer to peer","p2p version","addon version check","update broadcast"} },
    { label="Show AFK indicator",
      hint="Miscellaneous › Status Indicators", pageKey="opt_misc",
      keywords={"show afk","afk indicator","away from keyboard","afk icon","afk status"} },
    { label="Show DND indicator",
      hint="Miscellaneous › Status Indicators", pageKey="opt_misc",
      keywords={"show dnd","dnd indicator","do not disturb","busy status","dnd icon"} },
    { label="Show Dead indicator",
      hint="Miscellaneous › Status Indicators", pageKey="opt_misc",
      keywords={"show dead","dead indicator","death icon","corpse status","died indicator"} },
    { label="Show Ghost indicator",
      hint="Miscellaneous › Status Indicators", pageKey="opt_misc",
      keywords={"show ghost","ghost indicator","spirit","released spirit","ghost status"} },
    { label="Enable Target Range Fade",
      hint="Miscellaneous › Range Fade", pageKey="opt_misc",anchor="MSUF_TargetRangeFadeCheck",
      keywords={"target range fade","target fade","target oor","target out of range fade","range fade target"} },
    { label="Enable Focus Range Fade",
      hint="Miscellaneous › Range Fade", pageKey="opt_misc",anchor="MSUF_FocusRangeFadeCheck",
      keywords={"focus range fade","focus fade","focus oor","focus out of range","range fade focus"} },
    { label="Enable Boss Range Fade",
      hint="Miscellaneous › Range Fade", pageKey="opt_misc",anchor="MSUF_BossRangeFadeCheck",
      keywords={"boss range fade","boss fade","boss oor","boss out of range","range fade boss"} },
    { label="Global font color",
      hint="Colors", pageKey="opt_colors",anchor="MSUF_Colors_FontSwatchButton",
      keywords={"global font color","text color","all text","font colour","change text color","white text default","global text color","schrift farbe"} },
    { label="Use font palette",
      hint="Colors", pageKey="opt_colors",anchor="MSUF_Colors_FontResetButton",
      keywords={"use font palette","font palette","palette preset","reset font color","font color palette"} },
    { label="Class bar colors — per class HP bar color",
      hint="Colors › Class Bar Colors", pageKey="opt_colors",
      keywords={"class bar colors","class color","per class color","class hp color","warrior color","paladin color","hunter color","rogue color","priest color","dk color","death knight color","shaman color","mage color","warlock color","monk color","druid color","dh color","demon hunter color","evoker color","class colour","choose class color"} },
    { label="Reset all class colors",
      hint="Colors › Class Bar Colors", pageKey="opt_colors",
      keywords={"reset all class colors","restore class colors","default class colors","undo class colors"} },
    { label="Bar mode — Dark Mode (dark black bars) / Class Color Mode / Unified Color Mode",
      hint="Colors › Bar Appearance", pageKey="opt_colors",anchor="MSUF_Colors_BarModeDropdown",
      keywords={"bar mode","dark mode","class color mode","unified color mode","dark black bars","bar appearance","bar style mode","one color all frames","color mode"} },
    { label="Unified bar color swatch",
      hint="Colors › Bar Appearance", pageKey="opt_colors",anchor="MSUF_Colors_UnifiedBarSwatch",
      keywords={"unified bar color","same color all","one color","flat color","unified colour"} },
    { label="Reset to default (unified color)",
      hint="Colors › Bar Appearance", pageKey="opt_colors",
      keywords={"reset unified","default unified","restore unified color","reset to default unified"} },
    { label="Dark mode bar color — brightness slider",
      hint="Colors › Bar Appearance", pageKey="opt_colors",anchor="MSUF_Colors_DarkToneSlider",
      keywords={"dark mode color","dark bar color","dark mode brightness","black bar darkness","dark tone"} },
    { label="Bar background tint",
      hint="Colors › Bar Background", pageKey="opt_colors",anchor="MSUF_Colors_ClassBarBgSwatch",
      keywords={"bar background tint","bg tint","empty bar color","bar back color","tint color","background tint"} },
    { label="Match HP (bar background follows HP bar color)",
      hint="Colors › Bar Background", pageKey="opt_colors",anchor="MSUF_Colors_BarBgMatchHP",
      keywords={"match hp","bg match hp","background match hp","follow hp color","bar bg hp match"} },
    { label="Reset to black (bar background)",
      hint="Colors › Bar Background", pageKey="opt_colors",
      keywords={"reset to black","black background","bar bg black","reset background black"} },
    { label="Custom color in Dark Mode",
      hint="Colors › Bar Background", pageKey="opt_colors",anchor="MSUF_Colors_DarkBgCustomColor",
      keywords={"custom color dark mode","dark mode custom","dark bg custom","custom dark color"} },
    { label="Unitframe Colors section (NPC reactions)",
      hint="Colors › Unitframe Colors", pageKey="opt_colors",
      keywords={"unitframe colors","npc colors","reaction colors","mob colors","enemy color settings"} },
    { label="Friendly NPC Color",
      hint="Colors › Unitframe Colors", pageKey="opt_colors",anchor="MSUF_Colors_NPCFriendlySwatch",
      keywords={"friendly npc color","friendly green","friendly mob color","npc friendly colour"} },
    { label="Neutral NPC Color",
      hint="Colors › Unitframe Colors", pageKey="opt_colors",anchor="MSUF_Colors_NPCNeutralSwatch",
      keywords={"neutral npc color","neutral yellow","neutral mob color","npc neutral colour"} },
    { label="Enemy NPC Color",
      hint="Colors › Unitframe Colors", pageKey="opt_colors",anchor="MSUF_Colors_NPCEnemySwatch",
      keywords={"enemy npc color","hostile red","enemy mob color","hostile colour","npc enemy"} },
    { label="Dead NPC Color",
      hint="Colors › Unitframe Colors", pageKey="opt_colors",anchor="MSUF_Colors_NPCDeadSwatch",
      keywords={"dead npc color","dead mob grey","corpse color","dead colour","npc dead gray"} },
    { label="Pet Frame Color",
      hint="Colors › Unitframe Colors", pageKey="opt_colors",anchor="MSUF_Colors_PetFrameSwatch",
      keywords={"pet frame color","pet colour","familiar color","minion color","pet bar color"} },
    { label="Reset Extra Color (NPC unitframe colors)",
      hint="Colors › Unitframe Colors", pageKey="opt_colors",
      keywords={"reset extra color","reset npc colors","restore reaction colors","reset extra colour"} },
    { label="Absorb Bar Color",
      hint="Colors › Bar Colors", pageKey="opt_colors",anchor="MSUF_Colors_AbsorbOverlaySwatch",
      keywords={"absorb bar color","shield color","bubble color","barrier colour","absorb colour"} },
    { label="Heal-Absorb Bar Color",
      hint="Colors › Bar Colors", pageKey="opt_colors",anchor="MSUF_Colors_HealAbsorbOverlaySwatch",
      keywords={"heal-absorb bar color","heal absorb color","mortal wounds color","heal absorb colour"} },
    { label="Power Bar Background Color",
      hint="Colors › Bar Colors", pageKey="opt_colors",anchor="MSUF_Colors_PowerBarBackgroundSwatch",
      keywords={"power bar background color","mana bg color","behind mana","unfilled power color","mana background"} },
    { label="Power Bar Background — Match HP",
      hint="Colors › Bar Colors", pageKey="opt_colors",anchor="MSUF_Colors_PowerBarBgMatchHP",
      keywords={"power bar bg match hp","mana bg match hp","power background match","power bar match hp"} },
    { label="Aggro Border Color",
      hint="Colors › Bar Colors", pageKey="opt_colors",anchor="MSUF_Colors_AggroBorderSwatch",
      keywords={"aggro border color","threat color","aggro colour","threat border color"} },
    { label="Dispel Border Color",
      hint="Colors › Bar Colors", pageKey="opt_colors",anchor="MSUF_Colors_DispelBorderSwatch",
      keywords={"dispel border color","dispel colour","magic border color","curse border color"} },
    { label="Purge Border Color",
      hint="Colors › Bar Colors", pageKey="opt_colors",anchor="MSUF_Colors_PurgeBorderSwatch",
      keywords={"purge border color","spellsteal color","removable border color","purge colour"} },
    { label="Castbar colors section",
      hint="Colors › Castbar Colors", pageKey="opt_colors",
      keywords={"castbar colors","cast colors","castbar colour settings","cast colour section"} },
    { label="Interruptible cast color",
      hint="Colors › Castbar Colors", pageKey="opt_colors",anchor="MSUF_Colors_InterruptibleCastColorSwatch",
      keywords={"interruptible cast color","can interrupt color","kickable color","kick color","interruptible colour"} },
    { label="Non-interruptible cast color",
      hint="Colors › Castbar Colors", pageKey="opt_colors",anchor="MSUF_Colors_NonInterruptibleCastColorSwatch",
      keywords={"non-interruptible cast color","cant interrupt color","immune cast color","protected cast color"} },
    { label="Interrupt color (all castbars feedback)",
      hint="Colors › Castbar Colors", pageKey="opt_colors",anchor="MSUF_Colors_InterruptFeedbackColorSwatch",
      keywords={"interrupt color all castbars","interrupt feedback color","interrupted color","kicked color"} },
    { label="Castbar text color",
      hint="Colors › Castbar Colors", pageKey="opt_colors",anchor="MSUF_Colors_CastbarTextColorSwatch",
      keywords={"castbar text color","cast name color","cast text colour","spell name color"} },
    { label="Castbar border color",
      hint="Colors › Castbar Colors", pageKey="opt_colors",anchor="MSUF_Colors_CastbarBorderColorSwatch",
      keywords={"castbar border color","cast border colour","castbar frame color","cast outline color"} },
    { label="Player castbar override — Enable / Class color / Custom color",
      hint="Colors › Castbar Colors", pageKey="opt_colors",anchor="MSUF_Colors_PlayerCastbarOverrideSwatch",
      keywords={"player castbar override","enable player override","player cast color","override cast color","custom player castbar","class color castbar","player cast colour"} },
    { label="Reset castbar colors",
      hint="Colors › Castbar Colors", pageKey="opt_colors",
      keywords={"reset castbar colors","default castbar colors","restore cast colors","reset cast colours"} },
    { label="Enable mouseover highlight",
      hint="Colors › Mouseover", pageKey="opt_colors",anchor="MSUF_Colors_HighlightEnableCheck",
      keywords={"enable mouseover highlight","hover highlight","mouseover border","hover glow","enable highlight"} },
    { label="Mouseover highlight color",
      hint="Colors › Mouseover", pageKey="opt_colors",anchor="MSUF_Colors_HighlightColorSwatch",
      keywords={"mouseover highlight color","hover color","mouse over colour","glow color","highlight colour"} },
    { label="Gameplay colors — Combat timer / Enter / Leave / Crosshair / Totem",
      hint="Colors › Gameplay Colors", pageKey="opt_colors",
      keywords={"gameplay colors","combat timer color","combat enter color","combat leave color","crosshair color","totem color","gameplay colour section"} },
    { label="Combat timer text color",
      hint="Colors › Gameplay Colors", pageKey="opt_colors",anchor="MSUF_Colors_CombatTimerColorSwatch",
      keywords={"combat timer color","fight timer colour","clock color","combat clock color"} },
    { label="Combat Enter text color",
      hint="Colors › Gameplay Colors", pageKey="opt_colors",anchor="MSUF_Colors_CombatEnterColorSwatch",
      keywords={"combat enter color","entering combat color","in combat text color","combat start color"} },
    { label="Combat Leave text color",
      hint="Colors › Gameplay Colors", pageKey="opt_colors",anchor="MSUF_Colors_CombatLeaveColorSwatch",
      keywords={"combat leave color","ooc text color","leaving combat color","out of combat color"} },
    { label="Sync (combat state colors enter = leave)",
      hint="Colors › Gameplay Colors", pageKey="opt_colors",anchor="MSUF_Colors_CombatStateColorSyncCheck",
      keywords={"sync combat colors","same enter leave color","link combat colors","sync state color"} },
    { label="Crosshair in-range color",
      hint="Colors › Gameplay Colors", pageKey="opt_colors",anchor="MSUF_Colors_CrosshairInRangeColorSwatch",
      keywords={"crosshair in-range color","green crosshair","in range color","melee range green"} },
    { label="Crosshair out-of-range color",
      hint="Colors › Gameplay Colors", pageKey="opt_colors",anchor="MSUF_Colors_CrosshairOutRangeColorSwatch",
      keywords={"crosshair out-of-range color","red crosshair","out of range color","oor color crosshair"} },
    { label="Totem tracker text color",
      hint="Colors › Gameplay Colors", pageKey="opt_colors",anchor="MSUF_Colors_PlayerTotemsTextColorSwatch",
      keywords={"totem text color","totem timer colour","shaman totem color","totem tracker colour"} },
    { label="Power bar colors — Mana / Rage / Energy / Focus / Runic Power / Insanity / Fury / Pain / Essence",
      hint="Colors › Power Bar Colors", pageKey="opt_colors",anchor="MSUF_Colors_PowerTypeDropdown",
      keywords={"power bar colors","mana color","rage color","energy color","focus color","runic power color","insanity color","fury color","pain color","essence color","resource color","power colour","change mana color","power type color","mana colour"} },
    { label="Reset power bar colors",
      hint="Colors › Power Bar Colors", pageKey="opt_colors",anchor="MSUF_Colors_PowerColorResetBtn",
      keywords={"reset power bar colors","default mana color","restore power colors","reset resource colour"} },
    { label="Class Power colors — Combo Points / Holy Power / Soul Shards / Chi / Arcane Charges / Runes / Empowered / Soul Fragments / Maelstrom / Astral Power / Eclipse / Stagger / Insanity / Whirlwind / Tip of the Spear / Ebon Might / Resource Text",
      hint="Colors › Class Power Colors", pageKey="opt_colors",anchor="MSUF_Colors_ClassPowerTypeDropdown",
      keywords={"class power colors","combo points color","holy power color","soul shards color","chi color","arcane charges color","runes color","empowered color","soul fragments color","maelstrom color","astral power color","eclipse color","stagger color","insanity color","whirlwind color","tip of the spear color","ebon might color","resource text color","class bar color","class power colour"} },
    { label="Reset class power colors",
      hint="Colors › Class Power Colors", pageKey="opt_colors",anchor="MSUF_Colors_ClassPowerColorResetBtn",
      keywords={"reset class power colors","default class power colors","restore class power colour"} },
    { label="Auras colors — Own buff / Own debuff / Stack count / Cooldown text Safe / Warning / Urgent",
      hint="Colors › Auras Colors", pageKey="opt_colors",anchor="MSUF_Colors_AuraOwnBuffHighlightSwatch",
      keywords={"aura colors","own buff highlight color","own debuff highlight color","stack count color","cooldown text safe","cooldown text warning","cooldown text urgent","aura colour","buff color"} },
    { label="Own buff highlight color",
      hint="Colors › Auras Colors", pageKey="opt_colors",anchor="MSUF_Colors_AuraOwnBuffHighlightSwatch",
      keywords={"own buff highlight","my buff color","buff border color","buff highlight colour"} },
    { label="Own debuff highlight color",
      hint="Colors › Auras Colors", pageKey="opt_colors",anchor="MSUF_Colors_AuraOwnDebuffHighlightSwatch",
      keywords={"own debuff highlight","my debuff color","debuff border color","debuff highlight colour"} },
    { label="Stack count text color",
      hint="Colors › Auras Colors", pageKey="opt_colors",anchor="MSUF_Colors_AuraStackCountSwatch",
      keywords={"stack count text color","stacks color","charge count color","stack number colour"} },
    { label="Cooldown text color — Safe (long duration)",
      hint="Colors › Auras Colors", pageKey="opt_colors",anchor="MSUF_Colors_AuraCooldownSafeSwatch",
      keywords={"cooldown text safe","safe color aura","long duration color","cd safe colour"} },
    { label="Cooldown text color — Warning (medium duration)",
      hint="Colors › Auras Colors", pageKey="opt_colors",anchor="MSUF_Colors_AuraCooldownWarningSwatch",
      keywords={"cooldown text warning","warning color aura","medium duration color","cd warning colour"} },
    { label="Cooldown text color — Urgent (short / expiring)",
      hint="Colors › Auras Colors", pageKey="opt_colors",anchor="MSUF_Colors_AuraCooldownUrgentSwatch",
      keywords={"cooldown text urgent","urgent color aura","short duration color","cd urgent colour","expiring color"} },
    { label="Profiles panel",
      hint="Profiles", pageKey="profiles",
      keywords={"profiles","profile","profile manager","profile section"} },
    { label="Select / switch active profile",
      hint="Profiles", pageKey="profiles",anchor="MSUF_ProfileDropdown",
      keywords={"select profile","switch profile","active profile","change profile","current profile","existing profiles"} },
    { label="Auto-switch profile by specialization",
      hint="Profiles", pageKey="profiles",anchor="MSUF_ProfileSpecAutoSwitchCB",
      keywords={"auto switch profile","spec profile","per spec profile","auto-switch","spec auto switch"} },
    { label="Create new profile",
      hint="Profiles", pageKey="profiles",anchor="MSUF_ProfileNewEdit",
      keywords={"new profile","create profile","add profile","make profile","fresh profile"} },
    { label="Delete profile",
      hint="Profiles", pageKey="profiles",
      keywords={"delete profile","remove profile","erase profile","wipe profile"} },
    { label="Copy / duplicate profile",
      hint="Profiles", pageKey="profiles",
      keywords={"copy profile","duplicate profile","clone profile","snapshot profile","backup profile"} },
    { label="Reset profile to defaults",
      hint="Profiles", pageKey="profiles",
      keywords={"reset profile","default profile","restore profile","revert profile","clear profile"} },
    { label="Import profile (Ctrl+V to paste / Legacy Import)",
      hint="Profiles", pageKey="profiles",
      keywords={"import profile","paste profile","import settings","ctrl v profile","legacy import","load profile string"} },
    { label="Export profile (share string / Wago)",
      hint="Profiles", pageKey="profiles",anchor="MSUF_ProfileExportPicker",
      keywords={"export profile","share profile","profile string","copy profile code","wago profile","export settings","what to export"} },
    { label="MSUF frame scale",
      hint="Dashboard › Scale", pageKey="home",
      keywords={"frame scale","msuf scale","unit frame size","zoom in","zoom out","make bigger","make smaller","frame too small","frame too big","scale frames"} },
    { label="Global UI scale (1080 / 1440 / Auto / Scaling OFF)",
      hint="Dashboard › Scale", pageKey="home",
      keywords={"global scale","ui scale","1080p scale","1440p scale","4k scale","auto scale","scaling off","resolution scale","everything too small","everything too big","global ui scale"} },
    { label="Rounded unitframes (style toggle)",
      hint="Dashboard", pageKey="home",
      keywords={"rounded unitframes","round corners","soft edges","rounded frames","circle corners"} },
    { label="Factory Reset (overwrites entire active profile)",
      hint="Dashboard", pageKey="home",
      keywords={"factory reset","overwrite profile","full reset","start over","nuclear reset","everything default","wipe all settings","reset everything"} },
    { label="Reset frame positions to default",
      hint="Dashboard", pageKey="home",
      keywords={"reset positions","frame positions","went offscreen","frames disappeared","reset layout","default positions","restore layout"} },
    { label="Print Help / slash commands",
      hint="Dashboard", pageKey="home",
      keywords={"print help","slash commands","/msuf","list commands","help commands","msuf commands"} },
    { label="Open MSUF Menu",
      hint="Dashboard", pageKey="home",
      keywords={"open msuf menu","open menu","msuf menu","main menu open"} },
    { label="Enable MSUF Style module",
      hint="Modules", pageKey="modules",
      keywords={"enable style module","msuf style","midnight style","style module","styling","ui skin","custom look","module style","enable msuf style"} },
    { label="Rounded unitframes (Style module)",
      hint="Modules", pageKey="modules",
      keywords={"rounded style module","round corners module","style rounded","circle frame style"} },
}

-- ---------------------------------------------------------------------------
-- Query — pure Lua, no API calls, no comparisons on live values
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Query — splits on whitespace, ALL tokens must match somewhere in the entry.
-- Single-token queries work as before (substring in label/hint/keyword).
-- Multi-word queries (e.g. "mark of the wild") require every token to be
-- found in the combined searchable text of the entry → zero false negatives.
-- Secret-safe: no C-API values touched, pure string operations only.
-- ---------------------------------------------------------------------------
local function Query(text)
    if not text or #text < MIN_QUERY_LEN then return {}, 0 end

    -- Build token list (split on spaces, skip empty)
    local tokens = {}
    for tok in lower(text):gmatch("%S+") do
        tokens[#tokens + 1] = tok
    end
    if #tokens == 0 then return {}, 0 end

    local results = {}
    local count   = 0

    for i = 1, #INDEX do
        if count >= MAX_ROWS then break end
        local entry    = INDEX[i]
        local labelL   = lower(entry.label)
        local hintL    = lower(entry.hint)
        local kws      = entry.keywords

        -- Every token must hit somewhere in this entry
        local allMatch = true
        for t = 1, #tokens do
            local tok = tokens[t]
            local hit = find(labelL, tok, 1, true)
                     or find(hintL,  tok, 1, true)
            if not hit then
                for j = 1, #kws do
                    if find(kws[j], tok, 1, true) then hit = true; break end
                end
            end
            if not hit then allMatch = false; break end
        end

        if allMatch then
            count = count + 1
            results[count] = entry
        end
    end
    return results, count
end

-- ---------------------------------------------------------------------------
-- Search Results Panel
-- ---------------------------------------------------------------------------
local _panel    = nil
local _rows     = {}
local _subtitle = nil
local _noResult = nil

local ROW_H    = 36
local ROW_GAP  = 2
local PAD_TOP  = 46
local PAD_SIDE = 10

local function _SkinRow(btn)
    if not btn then return end
    for _, k in ipairs({"Left","Middle","Right"}) do
        if btn[k] and btn[k].Hide then btn[k]:Hide() end
    end
    local bg = btn:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(btn)
    bg:SetColorTexture(0.10,0.12,0.18,0.55)
    local hl = btn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(btn)
    hl:SetColorTexture(0.18,0.36,0.80,0.20)
    for _, m in ipairs({"GetNormalTexture","GetPushedTexture","GetHighlightTexture"}) do
        if btn[m] then local t=btn[m](btn); if t then t:SetAlpha(0) end end
    end
end

local function _BuildPanel()
    if _panel then return _panel end
    local p = CreateFrame("Frame","MSUF_SearchResultsPanel",UIParent)
    p:SetPoint("TOPLEFT",0,0); p:SetPoint("BOTTOMRIGHT",0,0); p:Hide()
    p.__MSUF_MirrorNoRestoreShow = true

    local title = p:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",PAD_SIDE,-12); title:SetText("Search Results")
    if _G.MSUF_SkinTitle then _G.MSUF_SkinTitle(title) end

    local sub = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-3); sub:SetText("")
    if _G.MSUF_SkinMuted then _G.MSUF_SkinMuted(sub) end
    _subtitle = sub

    local noRes = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
    noRes:SetPoint("TOPLEFT",p,"TOPLEFT",PAD_SIDE,-(PAD_TOP+16))
    noRes:SetText("No results found. Try another keyword."); noRes:Hide()
    if _G.MSUF_SkinMuted then _G.MSUF_SkinMuted(noRes) end
    _noResult = noRes

    for i = 1, MAX_ROWS do
        local yOff = -(PAD_TOP + (i-1)*(ROW_H+ROW_GAP))
        local row  = CreateFrame("Button",nil,p)
        row:SetPoint("TOPLEFT",p,"TOPLEFT",PAD_SIDE,yOff)
        row:SetPoint("TOPRIGHT",p,"TOPRIGHT",-PAD_SIDE,yOff)
        row:SetHeight(ROW_H)
        _SkinRow(row)

        local lbl = row:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        lbl:SetPoint("TOPLEFT",row,"TOPLEFT",8,-6)
        lbl:SetPoint("TOPRIGHT",row,"TOPRIGHT",-24,-6)
        lbl:SetJustifyH("LEFT")
        if _G.MSUF_SkinText then _G.MSUF_SkinText(lbl) end
        row._msufLbl = lbl

        local hint = row:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
        hint:SetPoint("BOTTOMLEFT",row,"BOTTOMLEFT",8,5)
        hint:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",-24,5)
        hint:SetJustifyH("LEFT")
        if _G.MSUF_SkinMuted then _G.MSUF_SkinMuted(hint) end
        row._msufHint = hint

        local arrow = row:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        arrow:SetPoint("RIGHT",row,"RIGHT",-6,0)
        arrow:SetText("|cff5588cc›|r")

        row:Hide()
        _rows[i] = row
    end

    _panel = p
    return p
end

-- Navigate to page, scroll to anchor, flash highlight.
local _scrollEpoch = 0
local function _NavigateAndScroll(pageKey, anchor, subkey)
    if type(_G.MSUF_SwitchMirrorPage) == "function" then
        _G.MSUF_SwitchMirrorPage(pageKey, subkey)
    elseif type(_G.MSUF_OpenPage) == "function" then
        _G.MSUF_OpenPage(pageKey, subkey)
    end
    if not anchor then return end
    _scrollEpoch = _scrollEpoch + 1
    local epoch = _scrollEpoch
    C_Timer.After(SCROLL_DELAY, function()
        if _scrollEpoch ~= epoch then return end
        local ok = ScrollToWidget(pageKey, anchor)
        if ok then
            C_Timer.After(0.05, function()
                if _scrollEpoch ~= epoch then return end
                HighlightWidget(anchor)
            end)
        else
            C_Timer.After(SCROLL_RETRY - SCROLL_DELAY, function()
                if _scrollEpoch ~= epoch then return end
                if ScrollToWidget(pageKey, anchor) then
                    C_Timer.After(0.05, function()
                        if _scrollEpoch ~= epoch then return end
                        HighlightWidget(anchor)
                    end)
                end
            end)
        end
    end)
end

local function _RenderResults(results, count, queryText)
    count = count or #results
    if _subtitle then
        if count == 0 then
            _subtitle:SetText("")
        elseif count >= MAX_ROWS then
            _subtitle:SetText(format("Top %d results for \"%s\"", MAX_ROWS, tostring(queryText)))
        else
            _subtitle:SetText(format("%d result%s for \"%s\"",
                count, count == 1 and "" or "s", tostring(queryText)))
        end
    end
    if _noResult then _noResult:SetShown(count == 0) end
    for i = 1, MAX_ROWS do
        local row   = _rows[i]
        local entry = results[i]
        if entry then
            if row._msufLbl  then row._msufLbl:SetText(entry.label)  end
            if row._msufHint then row._msufHint:SetText(entry.hint)  end
            local pk = entry.pageKey
            local sk = entry.subkey
            local an = entry.anchor
            row:SetScript("OnClick", function()
                _NavigateAndScroll(pk, an, sk)
            end)
            row:Show()
        else
            if row._msufLbl  then row._msufLbl:SetText("")  end
            if row._msufHint then row._msufHint:SetText("") end
            row:SetScript("OnClick", nil)
            row:Hide()
        end
    end
end

local function MSUF_Search_EnsurePanel()
    return _BuildPanel()
end

-- ---------------------------------------------------------------------------
-- EditBox Injection — BOTTOM of navRail, navStack BOTTOM raised, no clip
-- ---------------------------------------------------------------------------
local _debounceEpoch = 0
local _lastPageKey   = nil

local function MSUF_Search_InjectNavEditBox(navStack)
    if not navStack or navStack._msufSearchInjected then return end
    navStack._msufSearchInjected = true

    local navRail = navStack:GetParent()
    if not navRail then return end

    local sep = navRail:CreateTexture(nil,"ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",navRail,"BOTTOMLEFT",8,SEARCH_RESERVE_PX+2)
    sep:SetPoint("BOTTOMRIGHT",navRail,"BOTTOMRIGHT",-8,SEARCH_RESERVE_PX+2)
    sep:SetColorTexture(0.25,0.45,0.80,0.28)

    local eb = CreateFrame("EditBox","MSUF_SearchEditBox",navRail,"InputBoxTemplate")
    eb:SetHeight(SEARCH_BOX_H)
    eb:SetPoint("BOTTOMLEFT",navRail,"BOTTOMLEFT",8,8)
    eb:SetPoint("BOTTOMRIGHT",navRail,"BOTTOMRIGHT",-8,8)
    eb:SetAutoFocus(false); eb:SetMaxLetters(48)
    if eb.SetTextInsets then eb:SetTextInsets(20,6,0,0) end

    local icon = navRail:CreateFontString(nil,"ARTWORK","GameFontDisableSmall")
    icon:SetPoint("LEFT",eb,"LEFT",5,0); icon:SetText("|cff445577⌕|r")

    local ph = navRail:CreateFontString(nil,"ARTWORK","GameFontDisableSmall")
    ph:SetPoint("LEFT",eb,"LEFT",20,0); ph:SetPoint("RIGHT",eb,"RIGHT",-6,0)
    ph:SetJustifyH("LEFT"); ph:SetText("Search settings...")
    if _G.MSUF_SkinMuted then _G.MSUF_SkinMuted(ph) end
    eb._msufPlaceholder = ph

    local PAD = 8
    navStack:ClearAllPoints()
    navStack:SetPoint("TOPLEFT",     navRail,"TOPLEFT",      PAD, -PAD)
    navStack:SetPoint("TOPRIGHT",    navRail,"TOPRIGHT",    -PAD, -PAD)
    navStack:SetPoint("BOTTOMLEFT",  navRail,"BOTTOMLEFT",   PAD,  PAD+SEARCH_RESERVE_PX)
    navStack:SetPoint("BOTTOMRIGHT", navRail,"BOTTOMRIGHT", -PAD,  PAD+SEARCH_RESERVE_PX)

    local function UpdatePlaceholder()
        ph:SetShown(#(eb:GetText() or "") == 0)
    end

    local function TriggerSearch(queryText)
        queryText = queryText or ""
        if #queryText < MIN_QUERY_LEN then
            if _lastPageKey and _lastPageKey ~= "search" then
                if type(_G.MSUF_SwitchMirrorPage) == "function" then
                    _G.MSUF_SwitchMirrorPage(_lastPageKey)
                end
                _lastPageKey = nil
            end
            return
        end
        if not _lastPageKey or _lastPageKey == "search" then
            local win    = _G.MSUF_StandaloneOptionsWindow
            local curKey = win and win._msufCurrentKey
            _lastPageKey = (type(curKey)=="string" and curKey~="search") and curKey or "home"
        end
        if type(_G.MSUF_SwitchMirrorPage) == "function" then
            _G.MSUF_SwitchMirrorPage("search")
        end
        local p = _BuildPanel()
        if p then
            local results, count = Query(queryText)
            _RenderResults(results, count, queryText)
        end
    end

    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        UpdatePlaceholder()
        local txt      = self:GetText() or ""
        _debounceEpoch = _debounceEpoch + 1
        local epoch    = _debounceEpoch
        if C_Timer and C_Timer.After then
            C_Timer.After(DEBOUNCE_SEC, function()
                if _debounceEpoch ~= epoch then return end
                TriggerSearch(txt)
            end)
        else
            TriggerSearch(txt)
        end
    end)

    eb:SetScript("OnEscapePressed", function(self)
        self:SetText(""); self:ClearFocus(); UpdatePlaceholder()
        _debounceEpoch = _debounceEpoch + 1
        if _lastPageKey and _lastPageKey ~= "search" then
            if type(_G.MSUF_SwitchMirrorPage) == "function" then
                _G.MSUF_SwitchMirrorPage(_lastPageKey)
            end
            _lastPageKey = nil
        end
    end)

    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self)
        if self.HighlightText then self:HighlightText() end
        UpdatePlaceholder()
    end)
    eb:SetScript("OnEditFocusLost", function() UpdatePlaceholder() end)

    UpdatePlaceholder()
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------
ns.MSUF_Search_EnsurePanel      = MSUF_Search_EnsurePanel
ns.MSUF_Search_InjectNavEditBox = MSUF_Search_InjectNavEditBox
