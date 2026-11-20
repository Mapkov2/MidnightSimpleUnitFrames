-- Real cold/warm intent queries and the static/manual-tooltip lifecycle.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function OpenMenu(language)
    local world = World.Open(root, flavor, { page = "home", locale = language })
    assert(world.core.FinalizeLocale() == language)
    return world
end
local function WaitForIndex(mw)
    local api = mw.M.Search._CoreAPI
    for _ = 1, 1000 do
        local records = api.GetSearchRecords()
        if #records > 0 and #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("semantic search did not settle")
end
local function Matches(row, case)
    local t = row.exactTarget or {}
    return case[2] and t.settingKey == case[2] or case[3] and (t.controlId or ""):sub(-#case[3]) == case[3]
end
-- Real localized requests use the active menu language and preserve row identity.
local native = {
    deDE = {
        "wo finde ich die Profilsynchronisierung",
        "wie stelle ich die Manakostenvorschau ein",
        "wo ist die Option für Profilvarianten",
        "warum funktioniert die Profilsynchronisierung nicht",
    },
    enGB = {
        "where can I find the profile syncing setting",
        "how do I change spell cost preview",
        "where is the profile variants option",
        "why has profile sync stopped working",
    },
    enUS = {
        "where do I find profile sync",
        "where is the mana cost preview option",
        "how do I set up profile variants",
        "why is profile sync not working",
    },
    esES = {
        "dónde encuentro la sincronización de perfiles",
        "cómo configuro la vista previa del coste de maná",
        "dónde está la opción de variantes de perfil",
        "por qué no funciona la sincronización de perfiles",
    },
    esMX = {
        "dónde se configura la sincronización de perfiles",
        "dónde encuentro la vista previa del costo de maná",
        "cómo cambio las variantes de perfil",
        "por qué la sincronización de perfiles no sirve",
    },
    frFR = {
        "où se trouve la synchronisation des profils",
        "comment configurer la prévisualisation du coût en mana",
        "où sont les réglages pour les variantes de profil",
        "pourquoi la synchronisation des profils ne marche pas",
    },
    itIT = {
        "dove trovo la sincronizzazione dei profili",
        "dove trovo la voce anteprima del costo in mana",
        "come imposto le varianti del profilo",
        "perché la sincronizzazione dei profili non funziona",
    },
    koKR = {
        "프로필 동기화는 어디서 설정하나요",
        "마나 소모량 미리보기 설정은 어디에 있나요",
        "어디서 프로필 변형을 설정하나요",
        "프로필 동기화가 왜 안 되나요",
    },
    ptBR = {
        "onde fica a sincronização de perfis",
        "como configuro a prévia do custo de mana",
        "onde encontro as variantes de perfil",
        "por que a sincronização de perfis não funciona",
    },
    ruRU = {
        "где найти синхронизацию профилей",
        "как настроить предпросмотр затрат маны",
        "где в настройках варианты профиля",
        "почему не работает синхронизация профилей",
    },
    zhCN = {
        "配置同步在哪里设置",
        "怎么设置法力消耗预览",
        "配置变体设置在哪",
        "配置同步为什么不生效",
    },
    zhTW = {
        "設定檔同步在哪裡設定",
        "哪裡可以設定法力消耗預覽",
        "怎麼設定設定檔變體",
        "設定檔同步為什麼沒作用",
    },
}
local captionQuestions = {
    enUS = "where can I find the %s setting?", enGB = "how do I change %s?",
    deDE = "wo finde ich die Einstellung für %s?", esES = "¿Dónde encuentro %s?",
    esMX = "¿Dónde se configura %s?", frFR = "Où trouver %s ?",
    itIT = "Dove trovo la voce %s?", ptBR = "Onde encontro %s?",
    ruRU = "Где в настройках %s?", koKR = "%s 설정은 어디에 있나요?",
    zhCN = "%s在哪里设置？", zhTW = "哪裡可以設定%s？",
}

local function CheckCaptions(api, locale, targetField)
    local wanted = { ["general.fontKey"] = true, ["gf_priority.attachGap"] = true,
        ["general.castbarShakeStrength"] = true }
    if locale == "deDE" then
        local title = "Wie ändere ich die Zauberleisten?"
        local faq = api.SearchPages(title)[1]
        assert(faq and faq.kind == "faq" and faq.key == "opt_castbar" and faq.label == title, "castbar FAQ lost to its subject")
    end
    local found, question = 0, assert(captionQuestions[locale])
    for _, record in ipairs(api.GetSearchRecords()) do
        local key = targetField(record, "settingKey")
        if wanted[key] then
            wanted[key], found = nil, found + 1
            local bare = api.SearchPages(record.label)[1]
            local row = api.SearchPages(question:format(record.label))[1]
            assert(bare and row and row.exactTarget and bare.exactTarget and bare.exactTarget.settingKey == key
                and row.exactTarget.settingKey == key and not row.exactQueryHit, locale .. " caption missed: " .. record.label)
            if key == "general.fontKey" and locale == "deDE" then
                -- Use another spelling to miss the raw-input cache. The normal
                -- request scheduler must be able to interrupt a caption scan.
                local query = question:format(record.label) .. "?"
                local job = { index = 1, results = {}, fuzzy = {} }
                assert(not api.SearchPages(query, job, -1))
                assert(not api.SearchPages(query, job, -1) and job.context.captionIndex > 1)
                local resumed = api.SearchPages(query, job)[1]
                assert(resumed and resumed.exactTarget.settingKey == key and not resumed.exactQueryHit)
            end
            if found == 3 then break end
        end
    end
    assert(found == 3, locale .. " caption fixture is missing")
end


local function CheckNative(api, locale, targetField)
    local questions = assert(native[locale], locale)
    local nativeCases = { { questions[1], nil, ".sync.group.select" }, { questions[2], "bars.manaUpcomingCost" },
        { questions[3], nil, ".variant.select" } }
    for _, case in ipairs(nativeCases) do
        local row = api.SearchPages(case[1])[1]
        assert(row and Matches(row, case) and row.exactQueryHit, locale .. " native question missed: " .. case[1])
    end
    CheckCaptions(api, locale, targetField)
    for _, row in ipairs(api.SearchPages(questions[4])) do
        assert(not row.exactQueryHit, locale .. " problem report forced a setting: " .. questions[4])
    end
end
-- EN/DE already use the complete semantic replay on every client. Other
-- locales reuse one fresh options world for the native queries and captions.
if locale == "--other-locales" then
    for _, language in ipairs({ "enGB", "esES", "esMX", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }) do
        local world = OpenMenu(language)
        WaitForIndex(world)
        local api = world.M.Search._CoreAPI
        CheckNative(api, language, world.M.Search.StaticIndex.TargetField)
        if language == "frFR" then
            -- Exercise the existing effective-locale invalidation in a single
            -- warm search state. The character menu normally requests a reload.
            world.core.LOCALE = "zhTW"
            WaitForIndex(world)
            CheckNative(api, "zhTW", world.M.Search.StaticIndex.TargetField)
            for _, row in ipairs(api.SearchPages(native.frFR[1])) do
                assert(not row.exactQueryHit, "stale French query target after switching locale")
            end
        end
    end
    print("PASS native search across ten additional menu locales")
    return
end
local mw = OpenMenu(locale)
local M, api = mw.M, mw.M.Search._CoreAPI
local function Ready() WaitForIndex(mw) end
local cases = {
    { "ping system", "general.playerResourcePingEnabled" },
    { "how to ping my health", "general.playerResourcePingEnabled" },
    { "health ping", "general.playerResourcePingEnabled" },
    { "mana ping", "general.playerResourcePingEnabled" },
    { "wie pinge ich meine gesundheit", "general.playerResourcePingEnabled" },
    { "mana pingen", "general.playerResourcePingEnabled" },
    { "show the mana cost of my next spell", "bars.manaUpcomingCost" },
    { "manakosten des nächsten zaubers anzeigen", "bars.manaUpcomingCost" },
    { "five second mana regeneration rule", "bars.manaRegenPause" },
    { "fünf sekunden manaregeneration", "bars.manaRegenPause" },
    { "put a line at 35 percent mana", nil, ".marks.add" },
    { "markierung bei 35 prozent mana", nil, ".marks.add" },
    { "show healer mana in the raid", nil, ".field.healermanaenabled" },
    { "heilermana im raid anzeigen", nil, ".field.healermanaenabled" },
    { "track which healers are out of mana", nil, ".field.healermanaenabled" },
    { "which paladin blessing should each class have", nil, ".field.buffcoverageblessingpriorities" },
    { "welcher paladinsegen für welche klasse", nil, ".field.buffcoverageblessingpriorities" },
    { "prioritize tank blessings", nil, ".field.buffcoverageblessingtank1" },
    { "set boss focus with right click", "boss.rightClickFocusInCombat" },
    { "boss mit rechtsklick als fokus setzen", "boss.rightClickFocusInCombat" },
    { "right click arena enemy during combat", "arena.rightClickFocusInCombat" },
    { "new ping system", "general.playerResourcePingEnabled" },
    { "neues ping system", "general.playerResourcePingEnabled" },
}
local function Find(case, rows)
    for _, row in ipairs(rows or api.GetSearchRecords()) do if Matches(row, case) then return row end end
end
local function Ranked(case)
    for i, row in ipairs(api.SearchPages(case[1])) do
        if i > 6 then break end
        if Matches(row, case) then return row end
    end
end
Ready()
CheckNative(api, locale, M.Search.StaticIndex.TargetField)
if arg[4] == "--native-only" then print("PASS native search " .. flavor .. "/" .. locale) return end
assert(not M.cache.opt_misc and not M.cache.classpower, "cold index opened a feature page")
local available = {}
for _, case in ipairs(cases) do
    if Find(case) then
        available[#available + 1] = case
        assert(Ranked(case), "cold intent missed: " .. case[1])
    end
end
local expected = { Mainline = 18, Forever = 20, Vanilla = 7, TBC = 8, Mists = 10 }
assert(#available == expected[flavor], "semantic corpus availability changed: " .. #available)
if flavor == "Mainline" or flavor == "Forever" then assert(Find(cases[1]), "native ping missing")
else assert(not Find(cases[1]), "native ping exposed on unsupported client") end
if flavor == "Mainline" then assert(not Find(cases[9]), "Classic regeneration exposed on Mainline") end
if flavor ~= "Forever" then assert(not Find(cases[16]), "Forever blessing priorities exposed") end
if flavor == "Vanilla" or flavor == "Forever" then assert(not Find(cases[21]), "arena feature exposed") end

-- A known phrase inside a question or request resolves like the bare phrase;
-- clarifications, problems and negations never inherit its exact target.
-- The first two rows exist on every flavor and must keep the raid scope.
local framed = {
    { "could you show healer mana in the raid", nil, ".field.healermanaenabled" },
    { "kannst du bitte heilermana im raid anzeigen", nil, ".field.healermanaenabled" },
    { "could you show me the mana tick width please", "bars.manaRegenSparkWidth" },
    { "how do I change the mana tick glow", "bars.manaRegenSparkAlpha" },
    { "wie stelle ich die mana tick breite ein", "bars.manaRegenSparkWidth" },
    { "wo finde ich die Manakosten Vorschau", "bars.manaUpcomingCost" },
    { "where can I find the mana cost preview setting", "bars.manaUpcomingCost" },
    { "where do I find profile sync", nil, ".sync.group.select" },
    { "wo finde ich die Profilsynchronisierung", nil, ".sync.group.select" },
    { "wo finde ich die Postanzeige", "msufsuite.minimap.showMail" },
}
for index, case in ipairs(framed) do
    local row = Ranked(case)
    assert(row or (index > 2 and not Find(case)), "framed phrase missed: " .. case[1])
    if row then
        assert(row.exactQueryHit, "framed phrase ranked without its exact target: " .. case[1])
        assert(index > 2 or row.exactTarget.prepareValue == "raid", "framed phrase lost raid scope: " .. case[1])
    end
end
for _, query in ipairs({
    "could you show healer mana in the raid instead of party",
    "do not show healer mana in the raid",
    "why is healer mana in the raid broken",
    "how do I change the mana tick glow instead of mana tick width",
    "why is the mana tick width broken",
    "how do I not show the mana tick width",
    "warum ist die Postanzeige kaputt",
    "ich finde die Postanzeige nicht",
    "wo finde ich nicht die Manakosten Vorschau",
}) do
    for _, row in ipairs(api.SearchPages(query)) do
        assert(not row.exactQueryHit, "clarified phrase forced an exact target: " .. query)
    end
end

-- Opening a scoped result must not alter the shared cached row or any setting.
M.SetMenuStateValue("gfScope", "party")
local raid = assert(Ranked(cases[13]))
assert(raid.exactTarget.prepareKind == "groupScope" and raid.exactTarget.prepareValue == "raid", "query lost explicit raid scope")
local scopeField = "healerManaEnabled"
local party, raidDB = mw.core.GF.GetConf("party"), mw.core.GF.GetConf("raid")
local oldParty, oldRaid = rawget(party, scopeField), rawget(raidDB, scopeField)
assert(api.OpenSearchTarget(raid.key, raid.label, cases[13][1], nil, raid.route, raid.exactTarget))
Ready()
assert(M.gfScope == "raid", "raid query opened another group scope")
assert(rawget(party, scopeField) == oldParty and rawget(raidDB, scopeField) == oldRaid, "search changed healer settings")
M.SetMenuStateValue("gfScope", "party")
local generic = assert(Ranked({ "healer mana", nil, ".field.healermanaenabled" }))
assert(api.OpenSearchTarget(generic.key, generic.label, "healer mana", nil, generic.route, generic.exactTarget))
Ready()
assert(M.gfScope == "party", "scoped query contaminated the generic cached result")

for _, case in ipairs(available) do
    local row = assert(Ranked(case), "warm intent missed: " .. case[1])
    assert(api.OpenSearchTarget(row.key, row.label, case[1], nil, row.route, row.exactTarget), "intent did not open: " .. case[1])
    Ready()
    assert(Ranked(case), "page visit lost intent: " .. case[1])
end

-- Tooltip before and after registration, without executing dynamic hover code.
local widget = mw.env.CreateFrame("Frame", nil, M.frame)
local calls = 0
M.AddTooltip(widget, "Static diagnostic title", "uniquedescriptionneedle", { hook = true })
M.RegisterSearchWidget(widget, { pageKey = "opt_misc", label = "Diagnostic choice", kind = "dropdown",
    values = { "firstoptionneedle", "lateoptionneedle" }, keywords = "stablekeywordneedle" })
Ready()
assert(#api.SearchPages("uniquedescriptionneedle") > 0, "tooltip before registration lost")
M.AddTooltip(widget, "Static diagnostic title", string.rep("long prose ", 150) .. " truncatedtailneedle", { hook = true })
Ready()
assert(#api.SearchPages("uniquedescriptionneedle") == 0, "late tooltip left a cached description")
for _, q in ipairs({ "lateoptionneedle", "stablekeywordneedle" }) do
    assert(#api.SearchPages(q) > 0, "long tooltip displaced choice/keyword: " .. q)
end
assert(#api.SearchPages("truncatedtailneedle") == 0, "description quota was not applied")
M.AddTooltip(widget, function() calls = calls + 1 end, function() calls = calls + 1 end, { hook = true })
Ready()
assert(calls == 0, "search executed dynamic tooltip callbacks")
M.AddTooltip(widget, "Auto help", "autohelpfeedbackneedle", { hook = true, autoHelp = true })
Ready()
assert(#api.SearchPages("autohelpfeedbackneedle") == 0, "automatic help fed back into search")
print("search_semantic_context_smoke " .. flavor .. " " .. locale .. ": " .. #available .. " cold/warm intents, scope and tooltip lifecycle passed")
