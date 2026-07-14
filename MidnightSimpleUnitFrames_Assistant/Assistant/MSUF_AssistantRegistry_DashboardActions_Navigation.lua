-- Assistant Dashboard navigation action registry.
-- Loaded before MSUF_AssistantRegistry_DashboardActions.lua; the main action file preserves registration order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DashboardRegistry = A.DashboardRegistry or {}

function A.DashboardRegistry.RegisterNavigationActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local WorkflowOwner = ctx.A or A
    if not (Registry and type(Registry.RegisterAction) == "function") then return end

    local function NormalizedActionText(text)
        return tostring(text or ""):lower():gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function RequestedOpenState(text)
        text = NormalizedActionText(text)
        if text:find("close", 1, true) or text:find("collapse", 1, true) or text:find("hide", 1, true) then return false end
        if text:find("open", 1, true) or text:find("expand", 1, true) or text:find("show", 1, true) then return true end
        return nil
    end

    local function ParseDashboardPanelAliasArgs(text)
        text = NormalizedActionText(text)
        local panel = text:find("recovery", 1, true) and "recovery"
            or text:find("scaling", 1, true) and "scaling"
            or text:find("changelog", 1, true) and "changelog"
        local open = RequestedOpenState(text)
        -- "Close dashboard panel" has one safe deterministic meaning: close
        -- every optional Dashboard panel. Opening/toggling still requires the
        -- caller to name the exact panel.
        if not panel and open == false then panel = "all" end
        if not panel then return false end
        return { panel = panel, open = open }
    end

    local function ParseNavSectionAliasArgs(text)
        text = NormalizedActionText(text)
        local section
        if text:find("group frame", 1, true) or text:find("raid frame", 1, true) or text:find("party frame", 1, true) then
            section = "groupframes"
        elseif text:find("aura", 1, true) or text:find("buff", 1, true) or text:find("debuff", 1, true) then
            section = "auras"
        elseif text:find("appearance", 1, true) or text:find("global style", 1, true) then
            section = "globalstyle"
        elseif text:find("advanced", 1, true) or text:find("module", 1, true) then
            section = "modules"
        elseif text:find("frame", 1, true) then
            section = "unitframes"
        end
        if not section then return false end
        return { section = section, open = RequestedOpenState(text) }
    end

    Registry:RegisterAction({
        key = "open_recovery_tools",
        label = "Open Recovery Tools",
        type = "navigation",
        combatSafe = true,
        run = function()
            return WorkflowOwner.Workflow.OpenDashboardPanel("recovery")
        end,
    })

    Registry:RegisterAction({
        key = "open_dashboard_panel",
        label = "Open Dashboard Panel",
        type = "navigation",
        combatSafe = true,
        run = function(args)
            return WorkflowOwner.Workflow.OpenDashboardPanel(args and args.panel)
        end,
    })

    Registry:RegisterAction({
        key = "set_dashboard_panel",
        label = "Set Dashboard Panel",
        type = "navigation",
        aliases = {
            "open dashboard panel", "close dashboard panel", "toggle dashboard panel",
            "open recovery tools", "close recovery tools", "toggle recovery tools",
            "open scaling tools", "close scaling tools", "toggle scaling tools",
            "open changelog", "close changelog", "toggle changelog",
        },
        parseAliasArgs = ParseDashboardPanelAliasArgs,
        combatSafe = true,
        run = function(args)
            return WorkflowOwner.Workflow.SetDashboardPanel(args and args.panel, args and args.open)
        end,
    })

    Registry:RegisterAction({
        key = "set_nav_section",
        label = "Set Navigation Section",
        type = "navigation",
        aliases = {
            "open navigation section", "close navigation section", "toggle navigation section",
            "expand frames section", "collapse frames section",
            "expand group frames section", "collapse group frames section",
            "expand appearance section", "collapse appearance section",
            "expand advanced section", "collapse advanced section",
        },
        parseAliasArgs = ParseNavSectionAliasArgs,
        combatSafe = true,
        run = function(args)
            return WorkflowOwner.Workflow.SetNavSection(args and args.section, args and args.open)
        end,
    })

    Registry:RegisterAction({
        key = "set_nav_search_intro",
        label = "Set Search Intro",
        type = "navigation",
        aliases = {
            "show search intro", "hide search intro", "reset search intro",
            "mark search intro seen", "show ask msuf intro",
        },
        combatSafe = true,
        run = function(args)
            return WorkflowOwner.Workflow.SetNavSearchIntro(args and args.command)
        end,
    })

    Registry:RegisterAction({
        key = "menu_search_clear",
        label = "Clear Menu Search",
        type = "navigation",
        aliases = { "clear menu search", "clear search box", "clear ask msuf search" },
        combatSafe = true,
        run = function()
            if not (M and type(M.ClearNavSearch) == "function") then
                return false, "Open the MSUF menu first so I can clear its search box."
            end
            M.ClearNavSearch()
            return true, "Cleared the MSUF menu search."
        end,
    })

    Registry:RegisterAction({
        key = "menu_reset_current_page_prompt",
        label = "Reset Current Menu Page",
        type = "navigation",
        aliases = { "reset current menu page", "reset this options page", "open page reset confirmation" },
        aliasNoArgs = true,
        combatSafe = true,
        run = function()
            local pageKey = M and M.activeKey
            if not (pageKey and type(M.ShowPageResetConfirm) == "function") then
                return false, "Open an MSUF options page first so I can show its reset confirmation."
            end
            M.ShowPageResetConfirm(pageKey)
            return true, "Opened the reset confirmation for the current MSUF page."
        end,
    })

    Registry:RegisterAction({
        key = "set_menu_selector_state",
        label = "Set Menu Selector State",
        type = "navigation",
        aliases = {
            "select text tab", "select text slot", "select status tab", "select status indicator",
            "select group status icon", "select spell indicator", "select corner editor slot",
            "select power color token", "select class resource color token",
            "select class power style tab", "select class resource style tab", "select class resources style area",
            "select highlight borders tab", "select bars highlight tab", "select highlight area",
            "move text as one group", "move text per slot", "text move together",
            "select profile export kind", "set profile staging field", "set profile string field",
            "set unit copy category", "select unit copy categories",
            "set group copy category", "select group copy categories",
        },
        combatSafe = true,
        run = function(args)
            return WorkflowOwner.Workflow.SetMenuSelectorState(args)
        end,
    })

    Registry:RegisterAction({
        key = "menu_window_close",
        label = "Close MSUF Menu",
        type = "navigation",
        aliases = { "close menu", "close msuf menu", "close dashboard", "hide menu", "hide msuf menu" },
        combatSafe = true,
        run = function()
            return WorkflowOwner.Workflow.ControlMenuWindow("close")
        end,
    })

    Registry:RegisterAction({
        key = "menu_window_minimize",
        label = "Minimize MSUF Menu",
        type = "navigation",
        aliases = { "minimize menu", "minimize msuf menu", "minimize dashboard", "collapse menu window" },
        combatSafe = true,
        run = function()
            return WorkflowOwner.Workflow.ControlMenuWindow("minimize")
        end,
    })

    Registry:RegisterAction({
        key = "menu_window_maximize",
        label = "Maximize MSUF Menu",
        type = "navigation",
        aliases = { "maximize menu", "maximize msuf menu", "maximize dashboard", "fullscreen menu" },
        combatSafe = true,
        run = function()
            return WorkflowOwner.Workflow.ControlMenuWindow("maximize")
        end,
    })

    Registry:RegisterAction({
        key = "menu_window_restore",
        label = "Restore MSUF Menu",
        type = "navigation",
        aliases = { "restore menu", "restore msuf menu", "restore dashboard", "restore maximized menu", "unminimize menu", "show minimized menu" },
        combatSafe = true,
        run = function()
            return WorkflowOwner.Workflow.ControlMenuWindow("restore")
        end,
    })
end
