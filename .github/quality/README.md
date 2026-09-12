# Portable MSUF regression contracts

Run from the repository root with Python 3.9+ and Lua 5.1:

```powershell
python .github/quality/run.py --lua lua
```

`--lua` accepts an absolute executable path. `MSUF_LUA51` is also supported.
No `_local_workflows/`, ignored `tools/` files, third-party Python packages,
WoW installation, SavedVariables or network access are required.

The runner compiles current Core and Options sources, resolves their real
TOC/XML order, rejects protected-call names/aliases in owned runtime code,
checks that explicit test services and late core dependencies have real loaded
export providers, then executes eleven behavior contracts through the versioned
`.github/scripts/auras3_test_driver.lua` and its loader:

- original callback errors/stacks, argument preservation, once/reentrant dispatch,
  cancellation and scheduler continuation after an exception;
- Blizzard panel lifecycle and ownership after failed open/close;
- Class Resources resume before lazy construction and after page invalidation;
- native font cold-start settling, bounded retries, caches and failed-owner recovery;
- Edit Mode session listener failure and unregistration;
- preview-pan rollback before error reporting;
- saved font/aura rules, anchor coordinates and nested layout settling;
- Aura settings/controls without loading or constructing a page;
- shared render stages with separate per-preview dependencies and unchanged order;
- media burst coalescing, group refresh masks, combat catch-up and timer fallback;
- plain/secret text cache transitions and current visible priority-row ownership.

Two additional integration tests run directly under native Lua `loadfile`, with
no legacy loader or MSUF service injection. They load actual Bootstrap, timer,
page, preview, profile/storage and window collaborators. The window test follows
the shell XML through its API and executes native-frame fixture `OnShow`/`OnHide`
handlers. Coverage includes first Home open before lazy Class Resources creation,
switch/reopen, failed builders and refreshers, invalidation, cancelled tasks,
timer registration failure and font failure followed by a successful retry.

The export check also inspects explicit service declarations in local test files
when present. It rejects nonexistent exports; it does not claim to prove every
dynamic Lua call or every test double's behavior.

The loader models WoW's vararg `xpcall` in PUC Lua 5.1 for tests only. Production
does not receive this adapter. Stage dispatch tests use test-local spies; they
do not replace the separate full rendering/parity suite.

The larger machine-local suite remains separate. Its overlapping test
entry points forward to these canonical files rather than copying assertions.
CI remains packaging-only. These files belong to the developer checkout and
are outside addon release roots. Passing these contracts is not live combat,
taint, visual or CPU certification.
