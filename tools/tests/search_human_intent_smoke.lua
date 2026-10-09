-- Conversational tasks find their real destination without applying settings.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local cases = {
    { "ich will meine lebenszahl groesser machen", "uf_player" },
    { "ich möchte meine Lebenszahlen größer machen", "uf_player" },
    { "i want bigger health numbers", "uf_player" },
    { "helth numbers bigger", "uf_player" },
    { "my target health numbers are too small", "uf_target" },
    { "my raid health numbers are too small", "gf_layout" },
    { "wie mache ich die schrift groesser", "opt_fonts" },
    { "how can i make my target name text bigger", "uf_target", "target.nameFontSize" },
    { "my target mana text is too small", "uf_target" },
    { "mein ziel ist zu klein", "uf_target" },
    { "my target is too small", "uf_target" },
    { "wo kann ich den spielerbalken verschieben", "uf_player" },
    { "where can i move my player frame", "uf_player" },
    { "ich sehe mein focus nicht", "uf_focus", "focus.enabled" },
    { "warum sehe ich meinen fokus nicht", "uf_focus", "focus.enabled" },
    { "why can i not see my focus", "uf_focus", "focus.enabled" },
    { "lebensbalken durchsichtig machen", "uf_player", "player.hpBarAlpha" },
    { "make health bars transparent", "uf_player", "player.hpBarAlpha" },
    { "buffs am ziel ausblenden", "uf_target", "auras3.target.buff.visible" },
    { "hide buffs on my target", "uf_target", "auras3.target.buff.visible" },
    { "show debuffs on my target", "uf_target", "auras3.target.debuff.visible" },
    { "ich moechte die gruppenmitglieder nebeneinander", "gf_layout", ".field.growth.option.right" },
    { "put my party members side by side", "gf_layout", ".field.growth.option.right" },
    { "ich will die gruppe untereinander", "gf_layout", ".field.growth.option.down" },
}
local native = {
    ["enUS"] = {
        "I want bigger health numbers",
        "make my target frame larger",
        "make my target name text bigger",
        "where can I move my player frame",
        "why can I not see my focus",
        "make my health bar transparent",
        "hide buffs on my target",
        "put my party members side by side",
        "how do I make the font bigger",
        "make my chat font bigger",
        "show only my buffs on my target",
        "why is my focus mana missing",
    },
    ["enGB"] = {
        "I want bigger health numbers",
        "make my target frame larger",
        "make my target name text bigger",
        "where can I move my player frame",
        "why can I not see my focus",
        "make my health bar transparent",
        "hide buffs on my target",
        "put my party members side by side",
        "how do I make the font bigger",
        "make my chat font bigger",
        "show only my buffs on my target",
        "why is my focus mana missing",
    },
    ["deDE"] = {
        "ich möchte meine Lebenszahlen größer machen",
        "ich möchte meinen Zielrahmen vergrößern",
        "ich möchte den Namen meines Ziels größer machen",
        "wo kann ich meinen Spielerrahmen verschieben",
        "warum sehe ich meinen Fokus nicht",
        "meinen Lebensbalken durchsichtig machen",
        "Buffs am Ziel ausblenden",
        "ich möchte meine Gruppenmitglieder nebeneinander",
        "wie mache ich die Schrift größer",
        "die Schrift im Chat größer machen",
        "nur meine Buffs am Ziel anzeigen",
        "warum fehlt meinem Fokus Mana",
    },
    ["esES"] = {
        "quiero que los números de vida sean más grandes",
        "quiero agrandar el marco del objetivo",
        "quiero agrandar el texto del nombre del objetivo",
        "dónde puedo mover el marco del jugador",
        "por qué no veo mi foco",
        "quiero hacer transparente la barra de salud",
        "quiero ocultar los beneficios del objetivo",
        "quiero poner los miembros del grupo uno al lado del otro",
        "cómo puedo aumentar el tamaño de la fuente",
        "quiero agrandar la fuente del chat",
        "mostrar solo mis beneficios en el objetivo",
        "por qué no veo el maná de mi foco",
    },
    ["esMX"] = {
        "quiero que los números de vida sean más grandes",
        "quiero agrandar el marco del objetivo",
        "quiero agrandar el texto del nombre del objetivo",
        "dónde puedo mover el marco del jugador",
        "por qué no veo mi foco",
        "quiero hacer transparente la barra de salud",
        "quiero ocultar los beneficios del objetivo",
        "quiero poner los miembros del grupo uno al lado del otro",
        "cómo puedo aumentar el tamaño de la fuente",
        "quiero agrandar la fuente del chat",
        "mostrar solo mis beneficios en el objetivo",
        "por qué no veo el maná de mi foco",
    },
    ["frFR"] = {
        "je veux agrandir les chiffres de vie",
        "je veux agrandir le cadre de ma cible",
        "je veux agrandir le texte du nom de ma cible",
        "où puis-je déplacer le cadre du joueur",
        "pourquoi je ne vois pas mon focus",
        "je veux rendre la barre de vie transparente",
        "je veux masquer les améliorations de ma cible",
        "je veux mettre les membres du groupe côte à côte",
        "comment agrandir la police",
        "je veux agrandir la police du chat",
        "afficher uniquement mes améliorations sur la cible",
        "pourquoi je ne vois pas le mana de mon focus",
    },
    ["itIT"] = {
        "voglio ingrandire i numeri della salute",
        "voglio ingrandire il riquadro del bersaglio",
        "voglio ingrandire il testo del nome del bersaglio",
        "dove posso spostare il riquadro del giocatore",
        "perché non vedo il mio focus",
        "voglio rendere trasparente la barra della salute",
        "voglio nascondere i benefici sul bersaglio",
        "voglio mettere i membri del gruppo uno accanto all'altro",
        "come ingrandire il carattere",
        "voglio ingrandire il carattere della chat",
        "mostrare solo i miei benefici sul bersaglio",
        "perché non vedo il mana del mio focus",
    },
    ["ptBR"] = {
        "quero aumentar os números de vida",
        "quero aumentar o quadro do alvo",
        "quero aumentar o texto do nome do alvo",
        "onde posso mover o quadro do jogador",
        "por que não vejo meu foco",
        "quero deixar a barra de vida transparente",
        "quero ocultar os benefícios do alvo",
        "quero colocar os membros do grupo lado a lado",
        "como aumentar o tamanho da fonte",
        "quero aumentar a fonte do chat",
        "mostrar apenas meus benefícios no alvo",
        "por que não vejo o mana do meu foco",
    },
    ["ruRU"] = {
        "хочу увеличить цифры здоровья",
        "хочу увеличить рамку цели",
        "хочу увеличить текст имени цели",
        "где можно переместить рамку игрока",
        "почему я не вижу фокус",
        "хочу сделать полосу здоровья прозрачной",
        "хочу скрыть баффы цели",
        "хочу расположить участников группы рядом",
        "как увеличить размер шрифта",
        "хочу увеличить шрифт чата",
        "показывать только мои баффы на цели",
        "почему я не вижу ману фокуса",
    },
    ["koKR"] = {
        "체력 숫자를 더 크게 하고 싶어요",
        "대상 프레임을 더 크게 하고 싶어요",
        "대상 이름 글자를 더 크게 하고 싶어요",
        "플레이어 프레임을 어디서 옮기나요",
        "주시 대상이 왜 안 보이나요",
        "체력 바를 투명하게 하고 싶어요",
        "대상의 강화 효과를 숨기고 싶어요",
        "파티원을 가로로 나란히 놓고 싶어요",
        "글꼴 크기를 더 크게 하고 싶어요",
        "채팅 글꼴을 더 크게 하고 싶어요",
        "대상에 내 강화 효과만 표시하고 싶어요",
        "주시 대상의 마나가 왜 안 보이나요",
    },
    ["zhCN"] = {
        "我想把血量数字调大",
        "我想把目标框体放大",
        "我想把目标名字的文字调大",
        "我想移动玩家框体",
        "为什么看不到我的焦点",
        "我想让生命条透明",
        "我想隐藏目标的增益效果",
        "我想让队伍成员横着并排显示",
        "我想把字体调大",
        "我想把聊天字体调大",
        "只显示目标上我自己的增益",
        "为什么看不到焦点的法力",
    },
    ["zhTW"] = {
        "我想把血量數字調大",
        "我想把目標框架放大",
        "我想把目標名字的文字調大",
        "我想移動玩家框架",
        "為什麼看不到我的專注目標",
        "我想讓生命條透明",
        "我想隱藏目標的增益效果",
        "我想讓隊伍成員橫向並排顯示",
        "我想把字型調大",
        "我想把聊天字型調大",
        "只顯示目標上我自己的增益",
        "為什麼看不到專注目標的法力",
    },
}
local destinations = {
    { "uf_player" }, { "uf_target" }, { "uf_target", "target.nameFontSize" },
    { "uf_player" }, { "uf_focus", "focus.enabled" }, { "uf_player", "player.hpBarAlpha" },
    { "uf_target", "auras3.target.buff.visible" }, { "gf_layout", ".field.growth.option.right" }, { "opt_fonts" },
}
local compactCases = {
    ruRU = { { "размер питомца", "uf_pet" } },
    koKR = { { "대상프레임크기", "uf_target" } },
    zhCN = { { "目标框体大小", "uf_target" }, { "施法条颜色", "opt_colors" } },
    zhTW = { { "目標框架大小", "uf_target" }, { "施法條顏色", "opt_colors" } },
}
for _, locale in ipairs({ "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }) do
    local world = World.New(root, flavor, { locale = locale })
    world.env.MAX_BOSS_FRAMES = 5
    world:Boot()
    assert(not world:FirstFailure(), "boot failed")
    local M, env = world.core.MSUF2, world.env
    world.core.FinalizeLocale()
    M.frame = env.CreateFrame("Frame", nil, env.UIParent)
    M.frame:Show()
    local api = M.Search._CoreAPI
    local example = M.SearchData.SEARCH_EXAMPLES[locale][1]
    assert(api.SearchPages(example[2])[1].key == example[3], locale .. ": the shown size example opens another unit")
    local checked = 0
    for _, case in ipairs(cases) do
        if case[2] ~= "uf_focus" or world.core.Client.SupportsUnit("focus") then
            local first = api.SearchPages(case[1])[1]
            assert(first and first.key == case[2], locale .. ": wrong owner for " .. case[1]
                .. " -> " .. tostring(first and first.key) .. ":" .. tostring(first and first.label))
            if case[3] then
                local exact = assert(first.exactTarget, "missing exact target")
                local identity = exact.settingKey or exact.controlId or ""
                assert(identity:find(case[3], 1, true), locale .. ": wrong control for " .. case[1] .. " -> " .. identity)
            else
                assert(first.kind == "page", "frame task did not lead to its real page")
            end
            checked = checked + 1
        end
    end
local adversarial = {
    ["enUS"] = {
        { "make my target's target frame bigger", "uf_targettarget" },
        { "make my focus target and target bigger" },
        { "hide buff timers on my target" },
        { "hide target buff borders" },
    },
    ["deDE"] = {
        { "ich möchte das Ziel meines Ziels größer machen", "uf_targettarget" },
        { "ich möchte nur freundliche Buffs am Ziel ausblenden" },
    },
    ["esES"] = {
        { "quiero agrandar el objetivo de mi objetivo", "uf_targettarget" },
        { "quiero ocultar los beneficios enemigos del objetivo" },
        { "quiero ocultar el borde de los beneficios del objetivo" },
    },
    ["frFR"] = {
        { "je veux agrandir la cible de ma cible", "uf_targettarget" },
        { "je veux masquer les améliorations ennemies de ma cible" },
        { "je veux masquer les bordures des améliorations de ma cible" },
    },
    ["itIT"] = {
        { "voglio ingrandire il bersaglio del mio bersaglio", "uf_targettarget" },
        { "voglio nascondere i benefici nemici del bersaglio" },
    },
    ["ptBR"] = {
        { "quero aumentar o alvo do meu alvo", "uf_targettarget" },
        { "quero ocultar os benefícios inimigos do alvo" },
    },
    ["ruRU"] = {
        { "хочу увеличить цель моей цели", "uf_targettarget" },
        { "хочу скрыть вражеские баффы цели" },
        { "хочу увеличить полосу произнесения цели" },
    },
    ["koKR"] = {
        { "대상의 대상과 대상을 더 크게 하고 싶어요" },
        { "적 대상의 강화 효과를 숨기고 싶어요" },
        { "대상의 강화 효과 타이머를 숨기고 싶어요" },
    },
    ["zhCN"] = {
        { "我想放大目标的目标和目标" },
        { "我想隐藏友方目标的增益" },
        { "我想隐藏目标的增益计时器" },
    },
    ["zhTW"] = {
        { "我想放大目標的目標和目標" },
        { "我想隱藏友方目標的增益" },
        { "我想隱藏目標的增益計時器" },
    },
}
    for _, case in ipairs(adversarial[locale] or {}) do
        local target = M.SearchData.NaturalQueryTarget(M.Search.Text.NormalizeSearchText(case[1]))
        if case[2] then
            assert(target and target.pageKey == case[2], locale .. ": compound unit misread: " .. case[1])
            local first = api.SearchPages(case[1])[1]
            assert(first and first.key == case[2], locale .. ": compound unit wrong first result: " .. case[1])
        else
            assert(target == nil, locale .. ": scoped request was reinterpreted: " .. case[1])
        end
    end
    if locale == "esES" or locale == "esMX" then
        local first = api.SearchPages("quiero agrandar los nombres del objetivo")[1]
        assert(first and first.exactTarget and first.exactTarget.settingKey == "target.nameFontSize",
            locale .. ": Spanish names were interpreted as French numbers")
    elseif locale == "frFR" then
        assert(api.SearchPages("je veux agrandir les nombres de vie")[1].key == "uf_player",
            "frFR: French numbers were interpreted as Spanish names")
    end
    for i, destination in ipairs(destinations) do
        if destination[1] ~= "uf_focus" or world.core.Client.SupportsUnit("focus") then
            local query, wanted = native[locale][i], destination[2]
            local first = api.SearchPages(query)[1]
            assert(first and first.key == destination[1], locale .. ": native task wrong owner: " .. query)
            if wanted then
                local exact = first.exactTarget or {}
                local identity = exact.settingKey or exact.controlId or ""
                assert(identity:find(wanted, 1, true), locale .. ": native task wrong control: " .. query .. " -> " .. identity)
            else
                assert(first.kind == "page", locale .. ": native frame task did not open its page: " .. query)
            end
            checked = checked + 1
        end
    end
    for i = 10, #native[locale] do
        local query = native[locale][i]
        local target = M.SearchData.NaturalQueryTarget(M.Search.Text.NormalizeSearchText(query))
        if i == 10 then
            assert(target and target.settingKey == "msufsuite.chat.fontSize", locale .. ": chat font task lost its Suite owner")
        else
            assert(target == nil, locale .. ": native specific task was reinterpreted: " .. query)
        end
    end
    for _, case in ipairs(compactCases[locale] or {}) do
        local found = false
        for i, row in ipairs(api.SearchPages(case[1])) do
            if i <= 6 and row.key == case[2] then found = true end
        end
        assert(found, locale .. ": compact native task missing owner: " .. case[1])
    end
    assert(#api.SearchPages("qzxvflorp nonsenseword") == 0, "unknown words fabricated a destination")
    local resolver = M.SearchData.NaturalQueryTarget
    for _, query in ipairs({ "status indicator size", "my target portrait is too small",
        "my target castbar is missing", "my target buff icon is too small", "why is my target pink",
        "why is my focus health text missing", "where can i move my target name text",
        "put my party buff icons side by side", "make my target cast bar bigger",
        "my damage meter numbers are too small",
        "make my minimap buttons bigger", "make my minimap artwork bigger", "make my minimap shadow bigger",
        "make my minimap font bigger", "my rune numbers are too small",
        "make my party health bars transparent", "make my target health text transparent",
        "show only my buffs on my target", "hide buffs on my target that are not mine",
        "why is my focus mana missing", "warum fehlt meinem fokus mana",
        "nur meine buffs am ziel anzeigen", "hide target buffs during combat" }) do
        assert(resolver(M.Search.Text.NormalizeSearchText(query)) == nil, "unrelated task was reinterpreted: " .. query)
    end
    -- Searching never invokes the target's action/setter. A hidden frame stays hidden.
    local enabled = env.MSUF_DB.focus.enabled
    env.MSUF_DB.focus.enabled = false
    api.SearchPages("why can i not see my focus")
    assert(env.MSUF_DB.focus.enabled == false, "search enabled the frame")
    env.MSUF_DB.focus.enabled = enabled
    print(flavor .. " " .. locale .. ": " .. checked .. " natural tasks and specificity guards passed")
end

-- A language change invalidates preferred meanings without losing fallback terms.
do
    local world = World.New(root, flavor, { locale = "esES" })
    world:Boot()
    assert(not world:FirstFailure(), "locale transition boot failed")
    world.core.FinalizeLocale()
    local M = world.core.MSUF2
    for _, locale in ipairs({ "esES", "frFR", "esMX", "enGB", "esES" }) do
        world.core.LOCALE = locale
        local query = (locale == "frFR" or locale == "enGB") and "je veux agrandir les nombres de ma cible"
            or "quiero agrandar los nombres del objetivo"
        local target = M.SearchData.NaturalQueryTarget(M.Search.Text.NormalizeSearchText(query))
        if locale == "frFR" or locale == "enGB" then
            assert(target and target.pageKey == "uf_target", "French number fallback/cache mismatch: " .. locale)
        else
            assert(target and target.settingKey == "target.nameFontSize", "Spanish name/cache mismatch: " .. locale)
        end
    end
end
