-- On-screen keyboard for MSUF and Suite edit boxes on WoW Forever's Gamepad UI,
-- opened by A on an edit box like a phone keyboard. The letter layout follows
-- MSUF's menu language, the language the search and the labels use (QWERTZ,
-- AZERTY, Cyrillic with a Latin page, QWERTY with the language's own letters),
-- a symbols page holds punctuation and accented
-- letters, and a number pad opens first when the field holds a number. A line
-- on top shows the text with its cursor. The keyboard sits in the other half
-- of the screen, so the field and a search list under it stay visible.
--
-- A types the selected key, X deletes, Y adds a space, LB/RB move the text
-- cursor, the right stick walks the field's own list (the search matches)
-- through its Up/Down arrow keys and a press on it (R3) opens the picked
-- match the way Enter does, Start confirms through the field's Enter
-- handler, B closes the keyboard and ends editing like a click elsewhere (the
-- field commits through its focus-lost handler).
local _, MSUF = ...
if not (MSUF.Client and MSUF.Client.IsForever) then return end
local PadNav = MSUF.PadNavigation
if not PadNav then return end
local Kit = PadNav.Kit
local PixelLayoutRegion = Kit.PixelLayoutRegion

local Keyboard = {}
PadNav.Keyboard = Keyboard

local max, min = math.max, math.min
local KEY_W, KEY_H, KEY_GAP, KEY_PAD, LINE_H, SCREEN_GAP = 34, 30, 4, 10, 24, 90
local KEY_COLOR, KEY_EDGE = { 0.08, 0.11, 0.16, 0.96 }, { 0.22, 0.78, 0.94, 0.35 }
local KEY_ACTIVE = { 0.10, 0.35, 0.42, 0.96 }
local PANEL_COLOR, PANEL_EDGE = { 0.015, 0.03, 0.055, 0.97 }, { 0.22, 0.78, 0.94, 0.7 }
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

-- Letter rows per client language; every row has 11 keys.
local LETTERS = {
    latin = { "1234567890-", "qwertyuiop'", "asdfghjkl.,", "zxcvbnm?!/_" },
    deDE = { "1234567890ß", "qwertzuiopü", "asdfghjklöä", "yxcvbnm,.-'" },
    frFR = { "1234567890-", "azertyuiopè", "qsdfghjklmé", "wxcvbn,.'àç" },
    esES = { "1234567890-", "qwertyuiop'", "asdfghjklñ,", "zxcvbnm.?!/" },
    ptBR = { "1234567890-", "qwertyuiop'", "asdfghjklç,", "zxcvbnm.?!/" },
    ruRU = { "1234567890-", "йцукенгшщзх", "фывапролджэ", "ячсмитьбю.," },
}
LETTERS.esMX = LETTERS.esES
local SYMBOLS = { "!?@#%&*()+=", "/:;\"'<>[]_~", "áàâäãéèêëíî", "óòôöõúùûüçñ" }
local NUMBERS = { "789", "456", "123", "-0." }
-- Upper-case pairs for the letters string.upper does not know.
local LOWER = "äöüàâçéèêëîïôûùÿñáíóúãõåìòабвгдеёжзийклмнопрстуфхцчшщъыьэюя"
local UPPER = "ÄÖÜÀÂÇÉÈÊËÎÏÔÛÙŸÑÁÍÓÚÃÕÅÌÒАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"

local function Chars(text)
    local list = {}
    for char in text:gmatch(UTF8_CHAR) do list[#list + 1] = char end
    return list
end

local UPPER_OF = {}
do
    local lower, upper = Chars(LOWER), Chars(UPPER)
    if #lower == #upper then
        for index = 1, #lower do UPPER_OF[lower[index]] = upper[index] end
    end
end

-- Captions of the word keys ("@name" in ACTIONS). Done comes from the locale
-- packs (MSUF.L "Done"). The letter-page and shift captions name the alphabet
-- of the layout, so they live with it, like LETTERS. Numbers, symbols and
-- Delete stay symbols, as on a phone in every language.
-- koKR, zhCN and zhTW type on the Latin page: Hangul syllables and Chinese
-- characters need composition (an IME) that a key grid does not give. itIT
-- types on the Latin QWERTY page; the symbols page has à, è, é, ò and ù but
-- not ì (its eleven-key rows are full).
local LAYOUT_CAPTIONS = { ruRU = { letters = "АБВ", shift = "Аа" } }
local DEFAULT_CAPTIONS = { done = "Done", letters = "ABC", shift = "Aa" }

-- Bottom rows: { action, label, width in keys }. "layout:<name>" switches pages.
local ACTIONS = {
    text = {
        { "shift", "@shift", 1 }, { "layout:number", "123", 2 }, { "layout:symbols", "#+=", 2 },
        { "space", " ", 3 }, { "delete", "<-", 1 }, { "done", "@done", 2 },
    },
    textWithLatin = {
        { "shift", "@shift", 1 }, { "layout:number", "123", 1 }, { "layout:symbols", "#+=", 1 },
        { "layout:latin", "ABC", 1 }, { "space", " ", 4 }, { "delete", "<-", 1 }, { "done", "@done", 2 },
    },
    latin = {
        { "shift", "Aa", 1 }, { "layout:number", "123", 1 }, { "layout:symbols", "#+=", 1 },
        { "layout:text", "\208\144\208\145\208\146", 1 }, { "space", " ", 4 }, { "delete", "<-", 1 },
        { "done", "@done", 2 },
    },
    symbols = {
        { "layout:text", "@letters", 2 }, { "layout:number", "123", 2 }, { "space", " ", 4 },
        { "delete", "<-", 1 }, { "done", "@done", 2 },
    },
    number = { { "layout:text", "@letters", 1 }, { "delete", "<-", 1 }, { "done", "@done", 1 } },
}

local frame, line
local keys, firstKey = {}, {}
local layoutRows = {}

local function Continuation(text, index)
    local byte = text:byte(index)
    return byte ~= nil and byte >= 128 and byte < 192
end

local function Cursor(edit, text)
    local cursor = Kit.Plain(edit:GetCursorPosition()) or #text
    return max(0, min(#text, cursor))
end

-- The typed text with a cursor mark, its last 48 bytes when long.
local function PaintLine()
    local edit = Keyboard.target
    if not (line and edit) then return end
    local text = edit:GetText() or ""
    local cursor = Cursor(edit, text)
    local shown = text:sub(1, cursor):gsub("|", "||") .. "|cff38c7f0_|r" .. text:sub(cursor + 1):gsub("|", "||")
    if #text > 48 then
        local start = max(1, cursor - 40)
        while start > 1 and Continuation(text, start) do start = start - 1 end
        shown = "..." .. text:sub(start, cursor):gsub("|", "||") .. "|cff38c7f0_|r"
            .. text:sub(cursor + 1, cursor + 8):gsub("|", "||")
    end
    line:SetText(shown)
end

-- Typed text reaches the field the way a key press does: Menu2 mirrors some
-- fields only on OnTextChanged with userInput.
local function Changed(edit)
    Kit.RunScript(edit, "OnTextChanged", true)
    PaintLine()
end

local function TypeText(edit, value)
    edit:Insert(value)
    Changed(edit)
end

local function DeleteBackward(edit)
    local text = edit:GetText() or ""
    local cursor = Cursor(edit, text)
    if cursor == 0 then return end
    local start = cursor
    while start > 1 and Continuation(text, start) do start = start - 1 end
    edit:SetText(text:sub(1, start - 1) .. text:sub(cursor + 1))
    edit:SetCursorPosition(start - 1)
    Changed(edit)
end

local function MoveCursor(edit, delta)
    local text = edit:GetText() or ""
    local cursor = Cursor(edit, text)
    repeat
        cursor = cursor + delta
    until cursor <= 0 or cursor >= #text or not Continuation(text, cursor + 1)
    edit:SetCursorPosition(max(0, min(#text, cursor)))
    PaintLine()
end

local function KeyLabel(key)
    local value = key.padValue
    if not Keyboard.shift or #value == 0 then return value end
    return UPPER_OF[value] or value:upper()
end

local function PaintKeys()
    for index = 1, #keys do
        local key = keys[index]
        local shown = key.padLayout == Keyboard.layout
        key:SetShown(shown)
        if shown and key.padValue then key.label:SetText(KeyLabel(key)) end
        if key.padAction == "shift" then
            local color = Keyboard.shift and KEY_ACTIVE or KEY_COLOR
            key.fill:SetColorTexture(color[1], color[2], color[3], color[4])
        end
    end
    local rows = layoutRows[Keyboard.layout]
    local columns = rows.columns
    frame:SetSize(KEY_PAD * 2 + columns * KEY_W + (columns - 1) * KEY_GAP,
        KEY_PAD * 2 + LINE_H + KEY_GAP + (#rows + 1) * KEY_H + #rows * KEY_GAP)
end

function Keyboard.Press(action)
    local edit = Keyboard.target
    if not (edit and edit:IsVisible()) then
        Keyboard.Close()
        return
    end
    local layout = action:match("^layout:(.+)$")
    if action == "delete" then
        DeleteBackward(edit)
    elseif action == "space" then
        TypeText(edit, " ")
    elseif action == "left" or action == "right" then
        MoveCursor(edit, action == "left" and -1 or 1)
    elseif action == "shift" then
        Keyboard.shift = not Keyboard.shift
        PaintKeys()
    elseif layout then
        Keyboard.layout = layout
        PaintKeys()
        PadNav.Activate(frame, firstKey[layout])
    elseif action == "done" then
        Keyboard.Close(true)
        if edit:HasScript("OnEnterPressed") and edit:GetScript("OnEnterPressed") then
            Kit.RunScript(edit, "OnEnterPressed")
        else
            edit:ClearFocus()
        end
    end
end

local function OnKeyClick(key)
    if key.padAction then
        Keyboard.Press(key.padAction)
    elseif Keyboard.target then
        TypeText(Keyboard.target, KeyLabel(key))
        -- One upper-case letter at a time, like a phone keyboard.
        if Keyboard.shift then
            Keyboard.shift = false
            PaintKeys()
        end
    end
end

local function CreateKey(layout, column, row, width, value, action, label)
    local key = Kit.CreateUnhookedFrame("Button", frame)
    local keyWidth = width * KEY_W + (width - 1) * KEY_GAP
    key:SetSize(keyWidth, KEY_H)
    key:SetPoint("TOPLEFT", frame, "TOPLEFT", KEY_PAD + column * (KEY_W + KEY_GAP),
        -(KEY_PAD + LINE_H + KEY_GAP + row * (KEY_H + KEY_GAP)))
    key.fill = PixelLayoutRegion(key:CreateTexture(nil, "BACKGROUND"))
    key.fill:SetAllPoints()
    key.fill:SetColorTexture(KEY_COLOR[1], KEY_COLOR[2], KEY_COLOR[3], KEY_COLOR[4])
    Kit.AddBorder(key, KEY_EDGE, 1)
    key.label = PixelLayoutRegion(key:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
    key.label:SetPoint("CENTER")
    key.label:SetText(label or value)
    -- A long caption (a translated "Done" on the number pad) shrinks to its key.
    local wide = Kit.Plain(key.label:GetStringWidth())
    if wide and wide > keyWidth - 6 and key.label.SetTextScale then key.label:SetTextScale((keyWidth - 6) / wide) end
    if action == "space" then
        local bar = PixelLayoutRegion(key:CreateTexture(nil, "ARTWORK"))
        bar:SetColorTexture(0.85, 0.9, 0.95, 0.8)
        bar:SetSize(width * KEY_W * 0.5, 2)
        bar:SetPoint("CENTER", 0, -6)
    end
    key.padLayout, key.padValue, key.padAction = layout, value, action
    key:SetScript("OnClick", OnKeyClick)
    keys[#keys + 1] = key
    return key
end

-- "@name" captions: Done in the menu language, the others from the layout.
local function Caption(label, captions)
    local name = label:match("^@(%a+)$")
    if not name then return label end
    if name == "done" then
        local L = MSUF.L
        return (L and L["Done"]) or DEFAULT_CAPTIONS.done
    end
    return captions[name] or DEFAULT_CAPTIONS[name]
end

local function BuildLayout(layout, rows, actions, captions)
    local columns, built = 0, {}
    for row = 1, #rows do
        local chars = Chars(rows[row])
        built[row] = chars
        columns = max(columns, #chars)
        for column = 1, #chars do
            local key = CreateKey(layout, column - 1, row - 1, 1, chars[column])
            firstKey[layout] = firstKey[layout] or key
        end
    end
    local column = 0
    for index = 1, #actions do
        local spec = actions[index]
        CreateKey(layout, column, #rows, spec[3], nil, spec[1], Caption(spec[2], captions))
        column = column + spec[3]
    end
    built.columns = max(columns, column)
    layoutRows[layout] = built
end

local PROMPTS = {
    "PAD1", "Type key", "PAD3", "Delete", "PAD4", "Space", "PADLSHOULDER/PADRSHOULDER", "Move cursor",
    "PADFORWARD", "Confirm", "PAD2", "Close",
}
local LIST_PROMPTS = {
    "PAD1", "Type key", "PAD3", "Delete", "PAD4", "Space", "PADLSHOULDER/PADRSHOULDER", "Move cursor",
    "PADRSTICKAXIS", "Scroll", "PADRSTICK", "Select", "PADFORWARD", "Confirm", "PAD2", "Close",
}

-- A field with its own list under it (the search fields' matches) walks that
-- list with Up/Down (OnArrowPressed); the right stick presses them.
local function ListActive()
    local edit = Keyboard.target
    return edit ~= nil and edit:GetScript("OnArrowPressed") ~= nil
end

local function ListStep(_, _, dy)
    local edit = Keyboard.target
    if dy == 0 or not edit then return end
    Kit.RunScript(edit, "OnArrowPressed", dy > 0 and "UP" or "DOWN")
    Kit.Haptic("step")
end

local function KeyboardPrompts()
    return ListActive() and LIST_PROMPTS or PROMPTS
end

-- R3 opens the match the stick picked: Enter opens a search field's selection.
local function PickMatch()
    if ListActive() then Keyboard.Press("done") else Kit.Haptic("edge") end
end

local function EnsureKeyboard()
    if frame then return frame end
    frame = Kit.CreateUnhookedFrame("Frame", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(Kit.RING_LEVEL - 100)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    local fill = PixelLayoutRegion(frame:CreateTexture(nil, "BACKGROUND"))
    fill:SetAllPoints()
    fill:SetColorTexture(PANEL_COLOR[1], PANEL_COLOR[2], PANEL_COLOR[3], PANEL_COLOR[4])
    Kit.AddBorder(frame, PANEL_EDGE, 1)
    line = PixelLayoutRegion(frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", KEY_PAD + 4, -KEY_PAD)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -KEY_PAD - 4, -KEY_PAD)
    line:SetHeight(LINE_H)
    line:SetJustifyH("LEFT")
    frame:Hide()
    -- Locales/MSUF_Localization.lua loads first and resolves the menu language.
    local locale = MSUF.GetEffectiveLocale()
    local letters = LETTERS[locale] or LETTERS.latin
    local captions = LAYOUT_CAPTIONS[locale] or DEFAULT_CAPTIONS
    local nonLatin = locale == "ruRU"
    BuildLayout("text", letters, nonLatin and ACTIONS.textWithLatin or ACTIONS.text, captions)
    if nonLatin then BuildLayout("latin", LETTERS.latin, ACTIONS.latin, captions) end
    BuildLayout("symbols", SYMBOLS, ACTIONS.symbols, captions)
    BuildLayout("number", NUMBERS, ACTIONS.number, captions)
    local function Press(action) return function() Keyboard.Press(action) end end
    PadNav.Attach(frame, function() Keyboard.Close() end, {
        PAD3 = Press("delete"), PAD4 = Press("space"), PADFORWARD = Press("done"), PADRSTICK = PickMatch,
        PADLSHOULDER = Press("left"), PADRSHOULDER = Press("right"),
        repeatable = { PAD3 = true, PADLSHOULDER = true, PADRSHOULDER = true },
    }, { prompts = KeyboardPrompts, stepper = ListStep, stepperActive = ListActive })
    return frame
end

-- In the half of the screen away from the field, so the field and a list
-- under it (search results, a dropdown) stay visible.
local function PlaceKeyboard(edit)
    frame:ClearAllPoints()
    local _, bottom, _, top = Kit.Rect(edit)
    local _, _, _, screenTop = Kit.Rect(UIParent)
    if bottom and screenTop and (bottom + top) * 0.5 < screenTop * 0.5 then
        frame:SetPoint("TOP", UIParent, "TOP", 0, -SCREEN_GAP)
    else
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, SCREEN_GAP)
    end
end

function Keyboard.Open(edit)
    EnsureKeyboard()
    Keyboard.target = edit
    local text = edit:GetText() or ""
    -- A number, also with a decimal comma or a percent sign (a slider's value box).
    local numeric = (edit.IsNumeric and edit:IsNumeric()) or (text ~= "" and tonumber(text) ~= nil)
        or text:match("^%s*%-?%d*[%.,]?%d+%s*%%?%s*$") ~= nil
    Keyboard.layout = numeric and "number" or "text"
    Keyboard.shift = false
    edit:SetFocus()
    PaintKeys()
    PlaceKeyboard(edit)
    PaintLine()
    frame:Show()
    PadNav.Activate(frame, firstKey[Keyboard.layout])
end

function Keyboard.Close(keepFocus)
    local edit = Keyboard.target
    Keyboard.target = nil
    if frame and frame:IsShown() then frame:Hide() end
    if edit and not keepFocus and edit.HasFocus and edit:HasFocus() then edit:ClearFocus() end
end

-- The field's window closed or the field went away: the keyboard goes with it.
function Keyboard.Check()
    if frame and frame:IsShown() and not (Keyboard.target and Keyboard.target:IsVisible()) then
        Keyboard.Close()
    end
end

PadNav.OpenKeyboard = Keyboard.Open
