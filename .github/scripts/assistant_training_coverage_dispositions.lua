-- Reviewed coverage dispositions for registry entries that intentionally do not
-- expose a standalone conversational action alias.  The AssistantTraining gate
-- loads this file as data and rejects missing, stale, or structurally invalid
-- entries.  Keep this list narrow: user-invokable actions belong in the runner's
-- deterministic sample-prompt table instead.

return {
    version = 1,

    settingPolicies = {
        ["unreviewed-number-domain"] = {
            classification = "read-only-generated-fallback",
            evidence = "getter-and-fail-closed-mutation-probe",
            reason = "The saved/default value proves the current number, but not a safe minimum, maximum, step, unit, or enum domain.",
        },
        ["unconstrained-string"] = {
            classification = "read-only-generated-fallback",
            evidence = "getter-and-fail-closed-mutation-probe",
            reason = "The saved/default value proves the current string, but not a reviewed set or grammar of writable values.",
        },
    },

    -- These raw read-only identities have a best natural-language alias that
    -- deterministically resolves to a different, longer/canonical registry
    -- owner.  They still receive an exact synthetic execution-boundary probe;
    -- this ledger makes the non-addressable alias state explicit and prevents
    -- it from being mistaken for conversational mutation coverage.
    settingAliasShadows = {
        ["player.portraitBgColorA"] = { resolvesTo = "player.portraitBackgroundColorA", reason = "The abbreviation Bg expands to the longer Background label." },
        ["player.portraitBgColorB"] = { resolvesTo = "player.portraitBackgroundColorB", reason = "The abbreviation Bg expands to the longer Background label." },
        ["player.portraitBgColorG"] = { resolvesTo = "player.portraitBackgroundColorG", reason = "The abbreviation Bg expands to the longer Background label." },
        ["player.portraitBgColorR"] = { resolvesTo = "player.portraitBackgroundColorR", reason = "The abbreviation Bg expands to the longer Background label." },
        ["boss.portraitBgColorA"] = { resolvesTo = "boss.portraitBackgroundColorA", reason = "The abbreviation Bg expands to the longer Background label." },
        ["boss.portraitBgColorB"] = { resolvesTo = "boss.portraitBackgroundColorB", reason = "The abbreviation Bg expands to the longer Background label." },
        ["boss.portraitBgColorG"] = { resolvesTo = "boss.portraitBackgroundColorG", reason = "The abbreviation Bg expands to the longer Background label." },
        ["boss.portraitBgColorR"] = { resolvesTo = "boss.portraitBackgroundColorR", reason = "The abbreviation Bg expands to the longer Background label." },
        ["focus.portraitBgColorA"] = { resolvesTo = "focus.portraitBackgroundColorA", reason = "The abbreviation Bg expands to the longer Background label." },
        ["focus.portraitBgColorB"] = { resolvesTo = "focus.portraitBackgroundColorB", reason = "The abbreviation Bg expands to the longer Background label." },
        ["focus.portraitBgColorG"] = { resolvesTo = "focus.portraitBackgroundColorG", reason = "The abbreviation Bg expands to the longer Background label." },
        ["focus.portraitBgColorR"] = { resolvesTo = "focus.portraitBackgroundColorR", reason = "The abbreviation Bg expands to the longer Background label." },
        ["target.portraitBgColorA"] = { resolvesTo = "target.portraitBackgroundColorA", reason = "The abbreviation Bg expands to the longer Background label." },
        ["target.portraitBgColorB"] = { resolvesTo = "target.portraitBackgroundColorB", reason = "The abbreviation Bg expands to the longer Background label." },
        ["target.portraitBgColorG"] = { resolvesTo = "target.portraitBackgroundColorG", reason = "The abbreviation Bg expands to the longer Background label." },
        ["target.portraitBgColorR"] = { resolvesTo = "target.portraitBackgroundColorR", reason = "The abbreviation Bg expands to the longer Background label." },
        ["targettarget.portraitBgColorA"] = { resolvesTo = "targettarget.portraitBackgroundColorA", reason = "The abbreviation Bg expands to the longer Background label." },
        ["targettarget.portraitBgColorB"] = { resolvesTo = "targettarget.portraitBackgroundColorB", reason = "The abbreviation Bg expands to the longer Background label." },
        ["targettarget.portraitBgColorG"] = { resolvesTo = "targettarget.portraitBackgroundColorG", reason = "The abbreviation Bg expands to the longer Background label." },
        ["targettarget.portraitBgColorR"] = { resolvesTo = "targettarget.portraitBackgroundColorR", reason = "The abbreviation Bg expands to the longer Background label." },
        ["pet.portraitBgColorA"] = { resolvesTo = "pet.portraitBackgroundColorA", reason = "The abbreviation Bg expands to the longer Background label." },
        ["pet.portraitBgColorB"] = { resolvesTo = "pet.portraitBackgroundColorB", reason = "The abbreviation Bg expands to the longer Background label." },
        ["pet.portraitBgColorG"] = { resolvesTo = "pet.portraitBackgroundColorG", reason = "The abbreviation Bg expands to the longer Background label." },
        ["pet.portraitBgColorR"] = { resolvesTo = "pet.portraitBackgroundColorR", reason = "The abbreviation Bg expands to the longer Background label." },
    },

    actions = {
        ["dashboard.globalUiScale.apply"] = {
            classification = "ui-only",
            expectedType = "dashboard",
            expectedMutability = "ephemeral",
            entrypoint = "Dashboard scale card Apply button",
            reason = "Applies the Dashboard's already-staged value and has no meaningful standalone Assistant arguments.",
        },
        ["dashboard.globalUiScale.revertPending"] = {
            classification = "ui-only",
            expectedType = "dashboard",
            expectedMutability = "ephemeral",
            entrypoint = "Dashboard scale card Revert button",
            reason = "Reverts Dashboard-local staged state and is only meaningful from that card.",
        },
        ["dashboard.globalUiScale.disable"] = {
            classification = "ui-only",
            expectedType = "dashboard",
            expectedMutability = "savedState",
            entrypoint = "Dashboard global UI scale Off control",
            reason = "The guided Dashboard control owns this operation; the Assistant must guide to it rather than synthesize a raw button action.",
        },
        ["dashboard.msufFrameScale.apply"] = {
            classification = "ui-only",
            expectedType = "dashboard",
            expectedMutability = "ephemeral",
            entrypoint = "Dashboard MSUF frame scale Apply button",
            reason = "Applies the Dashboard's already-staged value and has no meaningful standalone Assistant arguments.",
        },
        ["dashboard.msufFrameScale.revertPending"] = {
            classification = "ui-only",
            expectedType = "dashboard",
            expectedMutability = "ephemeral",
            entrypoint = "Dashboard MSUF frame scale Revert button",
            reason = "Reverts Dashboard-local staged state and is only meaningful from that card.",
        },
        ["dashboard.menuScale.apply"] = {
            classification = "ui-only",
            expectedType = "dashboard",
            expectedMutability = "ephemeral",
            entrypoint = "Dashboard menu scale Apply button",
            reason = "Applies the Dashboard's already-staged value and has no meaningful standalone Assistant arguments.",
        },
        ["dashboard.menuScale.revertPending"] = {
            classification = "ui-only",
            expectedType = "dashboard",
            expectedMutability = "ephemeral",
            entrypoint = "Dashboard menu scale Revert button",
            reason = "Reverts Dashboard-local staged state and is only meaningful from that card.",
        },

        ["menu_search_query"] = {
            classification = "ui-only",
            expectedType = "navigation",
            expectedMutability = "navigation",
            entrypoint = "Menu search shortcut chips",
            reason = "Shortcut buttons pass their fixed query programmatically; free-form conversational search is handled by the Assistant search/navigation surface.",
        },
        ["menu_search_clear"] = {
            classification = "ui-only",
            expectedType = "navigation",
            expectedMutability = "navigation",
            allowDescriptiveAliases = true,
            entrypoint = "Menu search field Clear button",
            reason = "This clears transient menu-field state; Assistant search and navigation requests use their own conversational surface.",
        },

        ["first_load.personalize"] = {
            classification = "ui-only",
            expectedType = "onboarding",
            expectedMutability = "savedState",
            entrypoint = "First-load Personalize button",
            reason = "This is a stateful onboarding-card transition owned by the first-load flow.",
        },
        ["first_load.import_profile"] = {
            classification = "ui-only",
            expectedType = "onboarding",
            expectedMutability = "savedState",
            entrypoint = "First-load Import Profile button",
            reason = "This is a stateful onboarding-card transition owned by the first-load flow.",
        },
        ["first_load.use_defaults"] = {
            classification = "ui-only",
            expectedType = "onboarding",
            expectedMutability = "savedState",
            entrypoint = "First-load Use Defaults button",
            reason = "This is a stateful onboarding decision owned by the first-load flow.",
        },
        ["first_load.whats_new"] = {
            classification = "ui-only",
            expectedType = "onboarding",
            expectedMutability = "savedState",
            entrypoint = "First-load What's New button",
            reason = "This is an onboarding-card transition owned by the first-load flow.",
        },
        ["first_load.not_now"] = {
            classification = "ui-only",
            expectedType = "onboarding",
            expectedMutability = "savedState",
            entrypoint = "First-load Not Now button",
            reason = "This persists a first-load-flow decision and must remain contextual to that card.",
        },
        ["first_load.full_settings"] = {
            classification = "ui-only",
            expectedType = "onboarding",
            expectedMutability = "savedState",
            entrypoint = "First-load Full Settings button",
            reason = "This is a first-load-card transition; general Assistant navigation uses page/control actions instead.",
        },

        ["open_setting_control"] = {
            classification = "internal",
            expectedType = "navigation",
            expectedMutability = "navigation",
            entrypoint = "Resolved setting-context Open button and show-me routing",
            reason = "The action requires a canonical settingKey selected by trusted resolution and must not parse arbitrary standalone aliases.",
        },
    },
}
