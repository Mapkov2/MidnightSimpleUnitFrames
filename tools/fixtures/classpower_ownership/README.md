# Power ownership notification traces

The four traces freeze the reviewed pre-refactor differential probe: 13 distinct
scenarios, 27 client/scenario runs, and 108 Player Power notifications. They pin
notification ordering and effective ownership, plus the controller state after
spec/form/source changes, vehicles, resource toggles, disable/re-enable,
combat-deferred Aug entry/exit/reversal, missing hosts and failed sensors.

`classpower_ownership_notification_order_smoke.lua` loads the real BarsCommon
identity resolver, Power element subscription and ClassPower stack. At each
notification it checks the identity resolver and Power.Apply's Ebon predicate
against the frozen expected ownership, including Target isolation. Moving Aug
exit notification before clearing ownership fails at notification 2.

The review probe's `gtypes` suffix described the removed compatibility globals;
only that suffix is omitted. Every scenario, state and notification line is
otherwise unchanged. These are behavioral fixtures, separate from the untouched
SavedVariables/profile corpus. They do not establish live combat or taint safety.
