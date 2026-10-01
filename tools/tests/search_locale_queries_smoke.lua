-- Runtime locale/search regression over the real Classic menu shards and packs.
local root=assert(arg[1], 'repository root required')
local flavor=arg[2] or 'Mainline'
local World=assert(loadfile(root..'/tools/tests/client_world.lua'))()
local locales={'enUS','enGB','deDE','esES','esMX','frFR','itIT','koKR','ptBR','ruRU','zhCN','zhTW'}
local faqAnswers={
'Open MSUF Edit Mode, select the frame, then drag it. Use the unit page > Anchor only for exact anchor/X/Y fine-tuning.',
'Open that unit page and use Frame Basics for width, height, and scale. Text size is in Style > Fonts or the unit Text section.',
'Use the unit page for per-unit castbar toggles and Frames > Cast Bars for shared textures, direction, text, and interrupt options.',
'Boss frames normally appear only during boss encounters. Enable Boss Frames and use Edit Mode or Boss Preview to test them outside combat.',
'Open Frames > Party/Raid Frames > Layout. Size & Scaling controls frame dimensions and scaling by group size. Group Layout controls growth, columns, and group visibility.',
'Open the unit page and use Text for name/health/power text patterns, anchors, offsets, font sizes, and layering.',
'Open Style > Colors. Bar Colors and Power Bar Colors control HP/power colors; Class Bar Colors controls class overrides.',
'Style > Fonts controls shared font settings. Unit pages contain per-unit name, health, and power text position and pattern settings.',
'Use Dashboard > Reset Positions for frame movers. Use Profiles only when you want to reset, copy, import, or replace profile data.',
'Open Profiles for active profile, spec auto-switching, 6.x import/export strings, and reset options.',
'Open Frames > Bars. Textures & Gradient controls shared bar textures; Frame Outline and Highlight Borders control borders.',
'Absorb styling and heal prediction are in Frames > Bars > Absorb Display. Use the Party or Raid scope there for group incoming heals.',
'Open the matching unit page and check Frame Basics > Enable, Load Conditions, alpha/transparency, and range fade.',
'Open Frames > Party/Raid Frames > Layout. Check enable/show behavior, player/solo visibility, layout mode, frame scaling, and anchoring.',
'Open Frames > Party/Raid Frames > Status & Indicators for status icons, role/leader/assist, ready check, focus glow, and other group-frame state indicators.'}
local uiKeys={
'Find settings and help','Search enabled features in your own words.','Search settings, then open a result to make your changes.',
'Try fewer words or a different spelling.','Best %d match(es). Open one to view its setting or help.','Search or ask a question',
'Start typing to search available settings and help.','Search settings...','Search Examples',
'Matches appear while you type. Enter opens the selected result.',
-- Search intro and the guided setup's search wording (review 2026-09-30 F9).
'Try "raid auras" or "how do I make text bigger?"',
'Skipping leaves Spell Icons unchanged; you can find them later with Menu Search.',
'Finish the tour and use Menu Search to find other settings.',
'MISSION COMPLETE - Press Finish to return to the Dashboard.','Finish setup','Find settings with Search',
'Search Menu2 in everyday language to jump to the exact setting. Search only includes controls available in your active modules.',
'Finish opens the Dashboard, where you can search settings across the active modules.',
"Try searches such as 'Party frame width', 'Spell Icons', or 'Class Resources'. Search opens the matching setting in Menu2.",
'Finish returns to the Dashboard. Smart Search stays ready for settings and questions.',
'Use the Dashboard for common tasks, or type a setting or full question into Smart Search.',
'Anything else? Just ask','You are ready to play','Smart Search','Next setting','Claim +10 XP'}
-- Castbar colors are configured on Style > Colors; the castbar page only links
-- there through its ::: shortcuts, so a color query must land on opt_colors.
-- (A bare "castbar" alias on every color word used to satisfy opt_castbar by
-- matching castbar textures and fill direction, review 2026-09-30 F6.)
local expected={ 'uf_target','opt_colors','gf_layout' }
local conversational={'how do I make target bigger','where change cast bar color','why party frames not showing'}
local nativeTarget={
 enUS='how do I make target bigger', enGB='how do I make target bigger',
 deDE='ich möchte den Zielframe größer machen',
 esES='quiero cambiar el tamaño del marco objetivo', esMX='quiero cambiar el tamaño del marco objetivo',
 frFR='je veux changer la taille du cadre cible', itIT='voglio cambiare la dimensione del riquadro bersaglio',
 ptBR='quero mudar o tamanho do quadro alvo', ruRU='хочу изменить размер рамки цели',
 koKR='대상 프레임 크기를 변경하고 싶어요', zhCN='我想调大目标框体', zhTW='我想放大目標框架'}
-- Alias blocks after the base catalogue only add terms (AddAliasTerms); a direct
-- assignment silently replaced a key's meaning ("color" became castbar).
do
 local handle=assert(io.open(root..'/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_QueryAliases.lua','rb'))
 local source=handle:read('*a'):gsub('\r\n','\n'); handle:close()
 for line in source:gmatch('[^\n]+') do
  assert(not line:find('^Data%.QUERY_ALIASES%['),'QueryAliases replaces an alias key instead of adding terms: '..line)
 end
end
for _,locale in ipairs(locales) do
 local world=World.New(root,flavor,{locale=locale}); world:Boot()
 local failure=world:FirstFailure(); assert(not failure,failure and failure.message)
 local e,n=world.env,world.core
 assert(n.FinalizeLocale()==locale,locale..': locale pack not selected')
 local M=n.MSUF2; local api=M.Search._CoreAPI
 -- The menu is closed by default, so no query/index work is allowed before opening it.
 assert(#api.SearchPages('target size')==0,locale..': closed-menu query was not gated')
 M.frame=e.CreateFrame('Frame',nil,e.UIParent); M.frame:Show()
 local function owner(query,want)
  local rows=api.SearchPages(query)
  for _,row in ipairs(rows) do if row.key==want then return true end end
  local got={}; for i=1,math.min(8,#rows) do got[#got+1]=tostring(rows[i].key)..':'..tostring(rows[i].kind) end
  error(locale..': query '..query..' missed owner '..want..' (got '..table.concat(got,', ')..')')
 end
 -- The compact Spanish "ocultosgrupo" (hidden group) keeps its alias.
 local hidden=M.SearchData.QUERY_ALIASES.ocultosgrupo
 local hiddenTerms={}; for _,term in ipairs(hidden or {}) do hiddenTerms[term]=true end
 assert(hiddenTerms['hidden'] and hiddenTerms['party frames'] and hiddenTerms['group frames'],locale..': the ocultosgrupo alias is gone')
 local examples=M.SearchData.SEARCH_EXAMPLES[locale]
 assert(type(examples)=='table' and #examples==6,locale..': expected six localized examples')
 assert(examples[4][3]=='suite_bags' and examples[6][3]=='suite_cooldownManager',locale..': Suite examples need feature availability gates')
 for i=1,3 do owner(examples[i][2],expected[i]); owner(conversational[i],expected[i]) end
 owner(nativeTarget[locale],'uf_target')
 if locale=='enUS' or locale=='enGB' then
  -- Relevance golden set: color words keep their color meaning, and an exact
  -- query target is pinned on top without cutting the rest of the list.
  local barColors=api.SearchPages('bar colors')
  assert(barColors[1] and barColors[1].key=='opt_colors',locale..': "bar colors" ranks '..tostring(barColors[1] and barColors[1].label)..' first')
  for i=1,math.min(3,#barColors) do assert(barColors[i].key~='opt_castbar',locale..': "bar colors" ranks castbar textures on top') end
  local castbarColor=api.SearchPages('castbar color')
  assert(castbarColor[1] and castbarColor[1].kind=='color',locale..': "castbar color" does not rank a color control first')
  local raid=api.SearchPages('raid')
  assert(raid[1] and raid[1].key=='gf_layout' and raid[1].kind=='page' and #raid>1,locale..': "raid" lost its pinned page or every other result')
 end
 local records=api.GetFAQRecords(); assert(#records==15,locale..': FAQ catalog should contain exactly 15 curated rows'); local seen={}
 for _,row in ipairs(records) do if row.answer then seen[row.answer]=true; assert(not row.answer:lower():find('assistant',1,true),locale..': obsolete Assistant claim remains in FAQ') end end
 for _,answer in ipairs(faqAnswers) do
  assert(seen[answer],locale..': required FAQ answer missing from live catalog')
  local translated=M.Tr(answer)
  assert(type(translated)=='string' and translated~='',locale..': empty FAQ answer translation')
  if locale~='enUS' and locale~='enGB' then assert(translated~=answer,locale..': FAQ answer fell back to English: '..answer) end
 end
 for _,key in ipairs(uiKeys) do
  local value=M.Tr(key)
  assert(type(value)=='string' and value~='',locale..': empty UI key '..key)
  if locale~='enUS' and locale~='enGB' then assert(value~=key,locale..': UI key fell back to English: '..key) end
 end
 io.write(locale..': localized natural target sentence, 3 conversational queries, 15 curated FAQ answers, UI chrome OK\n')
end
