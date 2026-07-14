_G = _G or _ENV

_G.MSUF_AssistantAuditForbiddenTerms = {
    "de",
    "gruppenlayout",
    "gruppenframes",
    "gruppengesundheit",
    "gruppenindikatoren",
    "klassenressourcen",
    "zauberleisten",
    "zauberleiste",
    "sonderbereich",
    "hoch",
    "offen",
    "grupo",
    "diseno",
    "cadres",
    "groupe",
    "bearbeitungsmodus",
}

_G.MSUF_AssistantAuditSampleArgs = {
    open_page = { page = "gf_layout", label = "DE Gruppenlayout", query = "DE raid frames", anchor = "DE Anker" },
    assistant_scope_help = { frameType = "editMode", label = "DE Bearbeitungsmodus" },
    set_nav_section = { section = "groupframes" },
    assistant_nomatch_worklist = { owner = "DE Gruppenframes", resolution = "DE offen", priority = "DE hoch", tag = "DE zauberleiste" },
    set_menu_selector_state = { selector = "unit_copy_scope", unit = "player", category = "layout", value = true },
}

_G.MSUF_AssistantAuditConfigureEnvironment = function()
    local MSUF = assert(_G.MSUF_NS, "MSUF namespace missing")
    local M = assert(MSUF.MSUF2, "Menu namespace missing")

    M.Tr = function(text) return "DE:" .. tostring(text or "") end
    M.pages = {
        opt_castbar = { title = "DE Zauberleisten" },
        gf_layout = { title = "DE Gruppenlayout" },
        gf_bars = { title = "DE Gruppengesundheit" },
        gf_indicators = { title = "DE Gruppenindikatoren" },
        modules = { title = "DE Module" },
        classpower = { title = "DE Klassenressourcen" },
    }
    M.navItems = {
        { header = "DE Gruppenframes", id = "groupframes", defaultOpen = false },
        { key = "gf_layout", label = "DE Gruppenlayout" },
        { key = "gf_bars", label = "DE Gruppengesundheit" },
        { key = "gf_indicators", label = "DE Gruppenindikatoren" },
        { key = "modules", label = "DE Module" },
        { key = "classpower", label = "DE Klassenressourcen" },
    }
    M.UnitPage = {
        UF_COPY_CATEGORIES = {
            { key = "layout", label = "ES Diseno de grupo", default = true, aliases = { "layout", "position" } },
        },
    }
    M.GroupPage = {
        GF_COPY_CATEGORIES = {
            { key = "general", label = "FR Cadres de groupe", aliases = { "general", "basics" } },
        },
    }
    M.ResolveNavHeader = function()
        return "groupframes", "DE Gruppenframes", { defaultOpen = false }
    end
    M.SetNavHeaderOpen = function(_, open)
        M.navHeaderState = type(M.navHeaderState) == "table" and M.navHeaderState or {}
        if open == nil then open = not M.navHeaderState.groupframes else open = open and true or false end
        M.navHeaderState.groupframes = open
        return true, (open and "Opened " or "Closed ") .. "DE Gruppenframes navigation section.", open, "groupframes", "DE Gruppenframes"
    end
    M.SearchBridge = {
        OpenSearchTarget = function(page, query, label, anchor)
            M._localeAuditOpenSearchTarget = { page = page, query = query, label = label, anchor = anchor }
            M.activeKey = page
        end,
    }

    local A = assert(MSUF.Assistant, "Assistant missing")
    if A.Knowledge and A.Knowledge.MarkDirty then A.Knowledge.MarkDirty() end
end

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local audit = "tools/assistant_action_output_english_audit.lua"
if not exists(audit) then audit = "../../tools/assistant_action_output_english_audit.lua" end
dofile(audit)

local M = assert(_G.MSUF_NS and _G.MSUF_NS.MSUF2, "Menu namespace missing after audit")
local target = M._localeAuditOpenSearchTarget
if target then
    local label = tostring(target.label or "")
    assert(not label:find("DE", 1, true), "SearchBridge label leaked localized text: " .. label)
    assert(label == "Group Layout", "SearchBridge label should be the English page label, got: " .. label)
end

_G.MSUF_AssistantAuditConfigureEnvironment = nil
_G.MSUF_AssistantAuditForbiddenTerms = nil
_G.MSUF_AssistantAuditSampleArgs = nil

io.write("assistant_locale_action_output_audit: ok\n")
