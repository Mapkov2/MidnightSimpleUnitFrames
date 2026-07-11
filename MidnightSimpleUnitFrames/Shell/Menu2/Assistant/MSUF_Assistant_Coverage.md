# MSUF Assistant Coverage Status

Stand: 2026-07-03

Diese Datei beschreibt, was der MSUF Assistant aktuell kann, wie nah er am Ziel "100% MSUF Settings Coverage" ist, und was noch fehlt. Sie ist bewusst eine technische Momentaufnahme, kein Marketing-Text.

## Kurzfazit

Der externe Training-Harness ist aktuell gruen: `3770/3770` Cases bestanden, `0` Parser-Fehler, `0` Assistant-Load-Misses und `3283` Registry-Settings geladen.

Das bedeutet: Die rohe Registry- und Parser-Abdeckung ist fuer die aktuell bekannten generierten Testfaelle sehr stark. Es bedeutet aber noch nicht, dass jeder echte Spieler-Satz, jede Folgefrage, jede UI-Situation und jeder In-Game-Apply-Pfad wirklich bei 100% ist.

Aktuelle realistische Einschaetzung:

| Bereich | Naehe zu 100% | Warum |
| --- | ---: | --- |
| Raw setting registry coverage | 98-100% | Der aktuelle Harness deckt die Registry sehr breit ab und laeuft ohne Parser-Fehler. |
| Natural-language setting control | 85-90% | Viele direkte und menschliche Formulierungen funktionieren, aber seltene Satzformen, gemischte Deutsch/Englisch-Eingaben und Folgekontext sind noch nicht komplett. |
| Unit-frame indicator coverage | 90-95% | Level, PvP, Raid Marker, Raid Group, Leader/Assist, Combat/Rested/Resurrection und aehnliche Indikatoren sind deutlich besser abgedeckt. |
| Group-frame indicator coverage | 85-95% | Ready Check, Role, Leader/Assist, Raid Marker, Summon, Resurrection, PvP, Phase, Status Text, Corner und Spell Indicators sind breit erreichbar, brauchen aber noch Matrix-Audit gegen jedes UI-Control. |
| Aura/filter explanations | 80-85% | Der Assistant kann Filter besser erklaeren und aktive Filterzustaende einordnen, aber echte Einsteiger-Fuehrung fuer Raid, Mythic+, Rollen und konkrete Beispiele muss weiter ausgebaut werden. |
| Follow-up context | 70-80% | Einfache Folgewuensche wie "also for group frames" sind besser, aber komplexe Ketten wie "same as before but only raid and keep colors" brauchen noch Arbeit. |
| Safety and ambiguity handling | 85-90% | Er fragt oefter nach, statt riskant zu raten. Einige ueberlappende Begriffe bleiben gefaehrlich, z. B. power text vs. power color oder raid marker vs. raid group. |
| Runtime performance | 75-85% | Viele Stuck-/Slow-Faelle wurden durch Fast Paths geloest. Im letzten Harness bleiben `50` slow cases ueber dem 8ms-Schwellenwert. |
| Overall real-world readiness | 85-90% | Sehr brauchbar fuer viele Einstellungen, aber noch nicht "ChatGPT fuer jede MSUF-Frage ohne Kante". |

## Was der Assistant aktuell kann

### Unit Frames

- Player, Target, Focus, Pet, Boss, Target's Target und Focus Target aktivieren/deaktivieren.
- Position, Groesse, Scale, Anchor, Offsets und Layout-Einstellungen aendern.
- Health-, Power-, Name-, Level- und Status-Texte steuern.
- Textfarben, Powerfarben, Default-Farben, Class-/Power-Type-Farben und Font-Optionen setzen.
- Health- und Powerbar-Optionen wie Texture, Background Texture, Gradient, Gradient Strength, Smooth Fill und Reverse Fill steuern.
- Castbar-Optionen fuer Unit Frames steuern.
- Detached Power Bar und Class Resource-nahe Optionen bedienen.
- Status-Indikatoren wie Level, PvP Flag, Raid Marker, Raid Group Name, Leader, Assist, Combat, Rested, Dead Text und Incoming Resurrection per menschlicher Sprache erreichen.
- Kompakte Begriffe wie `playerframe`, `raidgroup`, `pvpflag`, `raidmarker`, `readycheck` und aehnliche Varianten besser verstehen.

### Group Frames

- Party, Raid und Mythic Raid Frames aktivieren/deaktivieren und konfigurieren.
- Layout, Growth, Sortierung, Spacing, Scale, Visibility und Rollen-/Power-Optionen steuern.
- Healthbar, Powerbar, Role Power, Dead/Offline-Farben, Range Fade, Debuff Stripe und Full Group Border kontrollieren.
- Group Status Indicators wie Ready Check, Role, Leader, Assist, Raid Marker, Summon, Resurrection, PvP, Phase und Status Text erreichen.
- Corner Indicators, Spell Indicators, targeted spells und aehnliche Gruppen-Features besser bedienen.
- Folgewuensche wie "auch fuer alle group frames" in vielen einfachen Faellen aufloesen.

### Auren und Filter

- Buffs und Debuffs fuer Unit Frames, Party, Raid und Mythic Raid oeffnen, erklaeren und aendern.
- Icon Size, Count, Spacing, Growth, Direction, Anchor, Layer, Cooldown Text, Stack Text, Duration, Swipe und aehnliche Aura-Optionen setzen.
- Filter-Toggles und Filter-Token besser verstehen.
- Aura-Filter menschlicher erklaeren: was ein Filter ungefaehr tut, wann er sinnvoll ist, welche Filter aktiv sind und warum ein sicherer Scope wichtig ist.
- Blacklist-, Custom Spell-, Corner- und Spell-Filter-Workflows teilweise fuehren.

### Appearance, Farben, Fonts und Globales

- Bar Textures, Background Textures und Gradients fuer Unit Frames und Group Frames steuern.
- Health-, Power-, Castbar-, Highlight-, Dispel-, Class-, NPC- und Default-Farben setzen.
- Fonts, Font Sizes, Font Flags und Font-Scopes anpassen.
- UI/Menu/Frame Scale setzen, inklusive direkter Eingaben wie "scale the ui to 53%".
- Dark Mode, Pet Frame Color, Mouseover Highlights und Boss Target Highlight steuern.

### Class Resources, Gameplay, Profile und Tools

- Class Resource-Optionen wie Anzeige, Farben, Groesse, Fill Direction, Text, Preview und verwandte Bar-Optionen erreichen.
- Gameplay- und Runtime-Features teilweise steuern und erklaeren.
- Profile importieren, vergleichen, zusammenfassen, kopieren oder sicher zuruecksetzen, soweit der aktuelle Action-Pfad vorhanden ist.
- Edit Mode, Movers, Previews und Tooling-Actions besser per Sprache ausloesen.
- Stop/Cancel fuer laengere Assistant-Jobs anbieten, damit der User nicht in einer Endlosschleife haengt.

### Conversation Behavior

- Direkte Changes mit Rueckmeldung bestaetigen.
- Undo-Hinweise nach Aenderungen geben.
- Bei riskanten oder mehrdeutigen Settings nachfragen, statt einfach irgendeine Option zu aendern.
- Erklaerfragen wie "how do I change the texture of the unitframes?" schneller beantworten, ohne in einen schweren Parser-Pfad zu fallen.
- Einige Follow-ups auf den letzten Scope anwenden, z. B. bei Bar Gradient oder Group Frame Wiederholungen.

## Was zuletzt verbessert wurde

- Ein externer Training-Harness wurde aufgebaut, der generierte und manuelle Regression-Cases ausfuehrt.
- Es gibt Reports unter `tools/AssistantTraining/out/report.md`.
- Der Harness laedt aktuell `3283` Registry Settings ohne Load Misses.
- Power Text, Power Color und Default-/Energy-Formulierungen wurden verbessert.
- Bar Gradient wurde gegen falsche Treffer wie "Focus Target Frame Enabled" abgesichert.
- Fast Paths fuer einfache Scale-, Texture-, Gradient-, Boolean-, Enum- und Color-Commands wurden ausgebaut.
- Stop/Cancel wurde fuer haengende Assistant-Jobs sichtbarer und nutzbarer gemacht.
- Indikator-Begriffe fuer Unit Frames und Group Frames wurden normalisiert.
- Konkrete Problemfaelle wie `move playerframe raidgroup indicator to the right` werden jetzt direkt auf den passenden Key gemappt.

## Automatisiertes Coverage-Audit (in-game)

Seit 2026-07-03 gibt es ein automatisiertes DB-Matrix-Audit, das den manuellen
Scope-Abgleich in dieser Datei ersetzt:

- `/msufcoverage` - Zusammenfassung pro Scope (player/target/.../gf_party/general/bars/gameplay) im Chat.
- `/msufcoverage <scope|all>` - Detailreport (Gaps + Stale-Eintraege) in einem kopierbaren Fenster.
- `/msufcoverage stubs <scope>` - generiert fertige `RegisterUnit*`/`RegisterGroup*`-Stubs fuer alle Gaps.
- `/msufcoverage generated <scope|all>` - listet generierte Fallbacks als Alias-Curation-Arbeitsliste.
- `/msufcoverage manifest` - exportiert einen copybaren `Manifest.defaults = { ... }` Block aus einer frisch geseedeten DB.
- `/msufcoverage smoke` - oeffnet die In-game-Akzeptanz-Checkliste fuer die Plan-Saetze.
- `/msufcoverage smoke pass|fail|block <id> [note]` - protokolliert echte WoW-Smoke-Ergebnisse nach `MSUF_GlobalDB.assistantAcceptance`.
- `/msufcoverage gate` - fasst Smoke, Manifest und Coverage als Abschluss-Gate in `MSUF_GlobalDB.assistantAcceptanceGate` zusammen.

Das Audit vergleicht jeden skalaren Key der Live-DB gegen `A.Registry` (Setting-Key-Prefix
und `unit`+`attribute`). Ergebnis wird zusaetzlich nach `MSUF_GlobalDB.assistantCoverage`
geschrieben, damit der externe Harness es aus den SavedVariables lesen kann.
Nested Tables (Auras-Lanes etc.) und Nicht-Scope-Settings (Farben, Workflows, Actions)
sind bewusst ausserhalb dieser Matrix und werden separat gezaehlt.
Interne Keys via `A.CoverageAudit.ignore` ausschliessen. Quelle: `MSUF_AssistantAudit.lua`.

Wichtige Einordnung der Zahlen: Die DB speichert nur angepasste Werte (nil-preserving
defaults). "Stale" heisst deshalb meist "Default nie angefasst" oder "custom get/set-Pfad",
nicht "kaputte Registrierung". Der erste echte Matrix-Lauf am 2026-07-03 zeigte 39-81%
Raw-Coverage pro Scope - deutlich unter der Harness-Schaetzung, weil der Harness Registry
gegen Testfaelle misst, nicht Registry gegen die reale DB.

## Auto-Coverage-Fallback (generierte Settings)

`MSUF_AssistantRegistry_AutoCoverage.lua` schliesst die Matrix-Luecken mechanisch: bei
PLAYER_LOGIN (und via `/msufcoverage fill`) wird fuer jeden ungedeckten skalaren DB-Key
ein generiertes englisches Setting registriert (Label/Aliases aus dem camelCase-Key,
direktes get/set, breitester sicherer Apply pro Scope). Handgeschriebene Eintraege haben
immer Vorrang; generierte sind mit `generated = true` markiert und als Kategorie
"Auto (generated)" erkennbar. Sie sind der Boden, nicht die Decke: fuer wichtige Settings
weiterhin per `/msufcoverage generated <scope|all>` und `/msufcoverage stubs <scope>`
kuratierte Registrierungen nachziehen (bessere Aliases, praeziser Apply, min/max).

Seit 2026-07-10 traversiert AutoCoverage zusaetzlich sichere verschachtelte DB-Pfade bis
zu acht Ebenen. Skalare Blaetter wie `target.auras.buff.iconSize` erhalten denselben
generischen get/set-/Apply-Pfad und werden als `generatedNested = true` markiert. Interne
`_`-Felder, numerische Pfadsegmente, Arrays/Spell-ID-Maps, Zyklen und tiefere Strukturen
werden bewusst nicht freigegeben; dynamische Listen und riskante Actions bleiben bei den
kuratierten Workflows. Der Manifest-Export schreibt verschachtelte Blaetter kompakt als
punkt-separierte Keys und kann sie beim Setzen sicher in der Live-DB materialisieren.

`MSUF_AssistantRegistry_AutoCoverage_Manifest.lua` ergaenzt nil-preserving Defaults:
`AutoCoverage.Fill()` registriert Manifest-Keys, die in der Live-DB fehlen, mit
Fallback auf den Manifest-Default. Dadurch misst `/msufcoverage` gegen den vollen
skalaren Default-Raum statt nur gegen bereits materialisierte SavedVariables-Keys.

**Status 2026-07-03: Das Manifest ist befuellt** - 2044 skalare Defaults ueber 12 Scopes,
offline generiert durch Dekodieren des Factory-Default-Profils
(`MSUF_FACTORY_DEFAULT_PROFILE_COMPACT` in `State/MSUF_Defaults.lua`, Base64 + raw
Deflate + CBOR, dieselbe Pipeline wie `C_EncodingUtil` in-game; `tot` wurde in
`targettarget` gemerged). Einzige Luecke: `focustarget` hat keinen Factory-Block im
Profil-Payload - dessen unberuehrte Defaults bleiben Live-DB-only. Zum Aktualisieren
(z. B. nach neuen Factory-Defaults): in einem frisch geseedeten Profil
`/msufcoverage manifest` ausfuehren und den erzeugten `Manifest.defaults`-Block aus dem
Fenster oder aus `MSUF_GlobalDB.assistantAutoCoverageManifest.text` in die Datei uebernehmen.

## In-game Acceptance Smoke

`/msufcoverage smoke` liefert die konkrete manuelle Smoke-Suite fuer die Context-Engine:
Phase-0-No-op-Nudges, Partial-Subject-Followups, Context-Scoring, Ambiguity-Ordinal,
Generated-Curation und Manifest-Dump. Die Liste ist copybar und speichert den Status
jedes Checks in `MSUF_GlobalDB.assistantAcceptance`, z. B.:

- `/msufcoverage smoke pass p0_2_target_leader_continuation`
- `/msufcoverage smoke fail p0_1_relative_noop_nudge changed the anchor instead`
- `/msufcoverage smoke block p2_3_manifest_dump needs freshly seeded profile`

Diese Smoke-Suite ersetzt den fehlenden lokalen WoW-Client nicht; sie macht die In-game
Akzeptanz aber reproduzierbar und als SavedVariables-Artefakt nachweisbar.
`/msufcoverage gate` ist der abschliessende In-game-Nachweis: PASS nur wenn alle Smoke-Cases
als pass gespeichert sind, ein Manifest-Export vorhanden ist und eine Coverage-Summary
gespeichert wurde.

Lokale Public-Path-Smokes vom 2026-07-03, mit WoW-Stubs und XML-Ladereihenfolge. Diese acht Checks laufen jetzt dauerhaft als `Public path smoke cases` im externen Harness:

- Phase 0.1: `move target of target name more to the right` bei bereits rechter
  Anchor-Enum aendert `targettarget.nameOffsetX` von `0` auf `10`.
- Phase 0.1: `move target of target name to the right` bei linker Anchor-Enum setzt
  weiter den Anchor auf `RIGHT` und laesst `targettarget.nameOffsetX` bei `0`.
- Phase 0.1: `set target of target name anchor to right` bei rechter Anchor-Enum
  bleibt `Already set` und nudged nicht.
- Phase 0.2: `enable target leader icon` -> `now move target leader up` ueber
  `A.HandleInput()` aendert `target.leaderIconOffsetY` von `0` auf `10` und
  laesst `target.offsetY` bei `0`.
- Phase 0.1/0.2: `move target frame up` ohne vorigen Subject-Kontext aendert
  `target.offsetY` von `0` auf `10` und laesst `target.leaderIconOffsetY` bei `0`.
- Phase 0.2: `set target hp bar opacity to 80%` -> `now move target leader up`
  nutzt den stale HP-Kontext nicht und faellt auf `target.offsetY` zurueck.
- Phase 0.2: abgelaufener Leader-Kontext (>3 Turns) faellt fuer
  `now move target leader up` ebenfalls auf `target.offsetY` zurueck.
- Phase 1.3: `change castbar color from green to red` erzeugt `6` Pending-Choices;
  `the second one` resolved gegen diese Liste und applied eine konkrete Aenderung.
- Gate API: `A.CoverageAudit.BuildAcceptanceGate()` meldet mit synthetisch
  vollstaendigen SavedVariables `smoke=11/11`, `manifest=true`, `coverage=true`.
- Generated/Manifest API: `A.CoverageAudit.BuildGeneratedReport()` und
  `A.AutoCoverage.BuildManifestText()`/`StoreManifestExport()` liefern und
  speichern die Phase-2b/2c-Artefakte ohne UI-Abhaengigkeit.

## Was noch fehlt bis echte 100%

### 1. Vollstaendiger Menu-Widget-Audit

Der DB-Matrix-Teil davon ist jetzt automatisiert (siehe oben). Offen bleibt der
UI-seitige Abgleich: jedes sichtbare Menu-Control muss gegen Registry und Assistant
Actions gemappt werden:

- Toggle
- Slider
- Stepper
- Dropdown
- Color Picker
- Texture Picker
- Anchor Picker
- Position Control
- Test-/Preview-/Reset-Button
- Hidden oder debug-only Options

Solange nicht jede UI-Kontrolle eine eindeutige Setting- oder Action-ID hat, ist "100%" nicht belegbar.

### 2. Indicator Matrix

Alle Unit- und Group-Frame-Indikatoren brauchen eine Matrix:

- enable/disable
- move left/right/up/down
- exact x/y offset
- anchor
- size
- layer/strata, falls vorhanden
- color/style, falls vorhanden
- reset
- preview/test
- menschliche Aliase

Erst wenn diese Matrix fuer Player, Target, Focus, Pet, Boss, Party, Raid und Mythic Raid durchlaeuft, ist Indicator Coverage wirklich voll.

### 3. Aura/filter Knowledge

Filter muessen fuer neue Spieler deutlich menschlicher werden:

- "Was macht dieser Filter?"
- "Welcher Filter ist fuer Raid gut?"
- "Warum sehe ich diesen Buff nicht?"
- "Was ist gerade aktiv?"
- "Was soll ich als Heiler/Tank/DD in Mythic+ nehmen?"
- "Was ist sicher fuer Target Debuffs vs. Party Buffs?"

Dafuer braucht der Assistant mehr erklaerende Filter-Modelle, konkrete Beispiele und aktive Zustandsauswertung.

### 4. Follow-up Context

Der Assistant muss mehr Folgefragen ohne erneutes Raten verstehen:

- "also for raid"
- "same for all group frames"
- "make that smaller"
- "undo only the color"
- "do the same for target and focus"
- "now move it a bit left"
- "keep the same texture but change the background"

Das braucht eine saubere Conversation-State-Schicht mit letztem Scope, letzter Option, letzter Action, letzter Zielgruppe und sicherer Ambiguity-Pruefung.

### 5. Performance und Anti-Stuck

Der Assistant darf bei simplen Fragen nicht in tiefe Fallback-Suche laufen.

Noch noetig:

- Parser-Budget pro Nachricht
- harte Timeouts fuer tiefe Suchpfade
- Stop-Signal in allen langen Loops pruefen
- mehr direkte Fast Paths fuer Informationsfragen
- Cache-Warmup ausserhalb von Combat
- keine zusaetzliche Combat-Overhead-Logik
- Slow-Report so lange abarbeiten, bis `0` slow cases oder ein sehr niedriger Restwert bleibt

### 6. Action Workflows

Einige nicht-reinen Setting-Actions brauchen mehr sichere Abdeckung:

- copy unit settings
- copy group settings
- reset page
- reset profile
- reset positions
- clear custom anchors
- remove custom aura spells
- import/export safety checks
- preview/test frame actions

Diese Actions sind riskanter als normale Settings und brauchen klare Bestaetigungen, Erklaerungen und Regression-Cases.

### 7. In-Game Verification

Der Harness prueft Parser-Plan und Registry-Mapping. Er beweist nicht automatisch, dass jede Aenderung im Spiel perfekt sichtbar applied wird.

Fuer echte 100% braucht es zusaetzlich:

- In-game DB verification
- UI refresh verification
- Preview-frame verification
- Combat-lockdown safety checks
- Reload/reopen menu persistence checks

## Latest Harness Snapshot

Quelle: `tools/AssistantTraining/out/report.md`

- Total cases: `3770`
- Passed: `3770`
- Failed: `0`
- Slow cases: `50`
- Registry settings loaded: `3283`
- Assistant file load misses: `0`

Der Slow-Schwellenwert im Tool liegt bei `8ms`. Das ist ein Parser-/Tooling-Signal und kein direkter FPS-Wert im Spiel.

## Naechster sinnvoller Plan

1. Menu Inventory Audit bauen: jedes Menu-Control automatisch in eine Coverage-Liste schreiben.
2. Indicator Matrix abschliessen: alle Unit- und Group-Indikatoren mit Toggle, Move, Anchor, Size, Reset und Alias testen.
3. Slow Cases abbauen: `tools/AssistantTraining/out/report.md` nach slow cases sortieren und Fast Paths fuer die groessten Verursacher bauen.
4. Filter Assistant ausbauen: aktive Filterzustände, einfache Empfehlungen und tiefere Erklaerungen fuer Einsteiger.
5. Follow-up Resolver bauen: letzter Scope, letzte Option und letzte Zielgruppe sicher speichern und wiederverwenden.
6. In-game Smoke Suite definieren: kleine Liste echter WoW-Kommandos, die DB-Aenderung und UI-Refresh verifizieren.

## Definition von "100%"

Der Assistant ist erst dann wirklich bei 100%, wenn alle folgenden Aussagen gleichzeitig stimmen:

- Jede sichtbare MSUF-Option ist per Assistant erreichbar.
- Jede Registry-Option hat mindestens einen generierten Test und mehrere menschliche Prompt-Varianten.
- Jede Action hat sichere Clarification- und Confirmation-Regeln.
- Jede Unit-, Group-, Aura-, Class Resource-, Gameplay-, Profile- und Tool-Option ist erklaerbar.
- Follow-ups funktionieren fuer Scope, Ziel, Richtung, Wert, Undo und Wiederholung.
- Simple Fragen antworten sofort und laufen nicht in schwere Parser-Pfade.
- Stop/Cancel beendet jeden langen Job verlaesslich.
- Der externe Harness und ein In-game Smoke-Test laufen beide sauber.

Aktuell ist der Assistant stark verbessert und in der Parser-Registry sehr nah dran. Fuer echtes "ChatGPT nur fuer MSUF" fehlen vor allem noch Follow-up-Gedaechtnis, Filter-Erklaertiefe, In-game-Verifikation und Performance-Haertung.
