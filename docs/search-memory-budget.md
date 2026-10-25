# Combined search and page memory

`tools/tests/search_combined_heap_smoke.lua` boots the actual core and Options
graph, measures immediately before Options loads, builds every registered page
and expands its lazy sections. The same world then decodes the index and runs
exact, multiword and typo queries with the pages still retained. A test-only
observer samples each query immediately before its active fuzzy-distance cache
is released; these caches grow during the query. The reported peak includes
those caches, persistent tokens/character counts, locale caches and page widgets.
The observer is removed before checking the closed menu's retained heap.

Initial offline measurements (2026-10-24, base HEAD `03146e6c7`, concurrent H
source changes; KiB after full GC):

| Client/locale | Pages | Search records | Pages built | Combined peak | Closed |
| --- | ---: | ---: | ---: | ---: | ---: |
| Mainline/enUS | 33 | 6460 | 249022 | 269743 | 250989 |
| Mainline/deDE | 33 | 6460 | 249058 | 269972 | 251216 |
| Vanilla/enUS | 29 | 4265 | 174780 | 189496 | 176175 |
| Vanilla/deDE | 29 | 4265 | 174817 | 189727 | 176403 |

Fixed Mainline ceilings are 288 MiB open and 272 MiB closed; Vanilla uses
200 MiB open and 188 MiB closed, about 8-11% above these baseline peaks.
The release inventory runs all four combinations. This deliberately measures
the larger all-pages-built state rather than adding isolated index numbers.
The harness models native frames with retained Lua widget tables; it neither
estimates native frame/GPU bytes nor establishes in-game CPU or memory usage.
