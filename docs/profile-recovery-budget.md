# Account recovery history

Newer-revision and quarantined profile histories share a 2 MiB account budget,
including deleted identities in the recovery archive. The byte count is the
deterministic Lua literal of both live history maps and the archive, including
the compatibility copy of each latest snapshot and bucket metadata. This is a
serialized history budget, not a native WoW or whole SavedVariables heap budget.
The independent pre-7.0 rollback snapshot retains its separate 8 MiB ceiling.

Each new snapshot gets a persisted account sequence. Entries are evicted oldest
first across both kinds and live/deleted profiles; each profile still retains
at most three entries. Entries older than the sequence format sort first, then
by identity and in-bucket order, with a deterministic name fallback for legacy
single-entry saves. Oversized snapshots are refused without displacing retained
history. Empty archive buckets are removed. Login bounds existing history too.
Live profiles and the rollback snapshot are never changed by history eviction.

Use `/msuf recovery list` to print the aggregate bytes, limit and retained keys.
`/msuf recovery export <key>` opens the existing copy popup with a complete
`return {...}` Lua snapshot; it loads Options on demand and refuses combat.
`/msuf recovery purge <key>` removes that entry, and
`/msuf recovery purge all` removes both kinds and deleted-identity history.
These explicit purge commands leave active/named profiles intact.

`tools/tests/profile_recovery_account_budget_smoke.lua` exercises all five
client graphs: deleted identities, oldest-first eviction, exact false/zero/text
export, command dispatch, legacy histories and oversized-entry cleanup.
The release inventory runs it on every supported client. These are offline
contracts; native popup rendering and SavedVariables serialization need a
separate in-game check.

Sparse I/O initialization (2026-10-25): V2/V3 wire dictionaries, expanded owner
fields and logout scratch are built on the first sparse restore or persist,
then reused. Full-profile login and legacy V1 decoding do not construct them.
The mandatory original rollback snapshot still runs before migrations; a saved
snapshot prevents this one-time copy on later logins. The startup smoke checks
both first-upgrade and ordinary reload costs, retaining the original 1849k
instruction ceiling for ordinary login.
