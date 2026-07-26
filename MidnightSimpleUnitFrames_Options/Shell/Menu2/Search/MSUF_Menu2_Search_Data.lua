local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data

local WordSet = M.KeySetFromWords

Data.TEXT_FOLDS = {
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

Data.UTF_PUNCTUATION = {
    "\194\160", --- nbsp
    "\226\128\152", "\226\128\153", "\226\128\156", "\226\128\157",
    "\226\128\147", "\226\128\148", "\226\128\166",
    "\227\128\129", "\227\128\130",
    "\239\188\129", "\239\188\140", "\239\188\154", "\239\188\155", "\239\188\159",
}

Data.NOISE_TEXT = {
    [""] = true,
    ["x"] = true,
    ["+"] = true,
    ["-"] = true,
    ["<"] = true,
    [">"] = true,
    ["|"] = true,
}

Data.STOP_WORDS = WordSet [[
    a an and are bother bothering can cant change changed changing configure configured customize customise do does doesnt didn didnt basically blind brain find fixed fix for get going hey help how i im in is it just m make maybe my need now not of on or please pls option options de del el la las los un una esta este donde como est le les des du une ou il lo gli di da dove per para o os as um uma onde найти где как опция setting settings setup so sorry thanks the thx to want where why with would t etc functioning n wtf dumb stupid plsfix s see image screenshot happening here still even though wie kann ich ist sind das die der den dem ein eine einer mein meine nicht warum wo was aendern andern einstellen einstellungen finde finden bitte du fuer fur mal man mich mir mit nur optionen noch immer aus obwohl trotzdem werden und oder zu zur zum
]]

Data.QUERY_SOFT_STOP_WORDS = WordSet [[
    activate activated adjust button checkbox choose chosen decrease disable disabled dropdown enable enabled hide hidden increase input off open select selected slider switch toggle turn value visible aktivieren aktiviere aktiviert anpassen anzeigen ausblenden ausschalten auswahl auswaehlen deaktivieren deaktiviere deaktiviert einschalten menu menue regler schalter umschalter choisir activer desactiver seleccionar activar desactivar selezionare attivare disattivare ativar desativar
]]
