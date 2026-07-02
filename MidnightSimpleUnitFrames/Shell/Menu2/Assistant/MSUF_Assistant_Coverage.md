# MSUF Assistant Coverage Status

Stand: 2026-07-03

Diese Datei beschreibt, was der MSUF Assistant aktuell kann, wie nah er am Ziel "100% MSUF Settings Coverage" ist, und was noch fehlt. Sie ist bewusst eine technische Momentaufnahme, kein Marketing-Text.

## Kurzfazit

Der externe Training-Harness ist aktuell gruen: `3711/3711` Cases bestanden, `0` Parser-Fehler, `0` Assistant-Load-Misses und `3243` Registry-Settings geladen.

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
| Runtime performance | 75-85% | Viele Stuck-/Slow-Faelle wurden durch Fast Paths geloest. Im letzten Harness bleiben `57` slow cases ueber dem 8ms-Schwellenwert. |
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
- Der Harness laedt aktuell `3243` Registry Settings ohne Load Misses.
- Power Text, Power Color und Default-/Energy-Formulierungen wurden verbessert.
- Bar Gradient wurde gegen falsche Treffer wie "Focus Target Frame Enabled" abgesichert.
- Fast Paths fuer einfache Scale-, Texture-, Gradient-, Boolean-, Enum- und Color-Commands wurden ausgebaut.
- Stop/Cancel wurde fuer haengende Assistant-Jobs sichtbarer und nutzbarer gemacht.
- Indikator-Begriffe fuer Unit Frames und Group Frames wurden normalisiert.
- Konkrete Problemfaelle wie `move playerframe raidgroup indicator to the right` werden jetzt direkt auf den passenden Key gemappt.

## Was noch fehlt bis echte 100%

### 1. Vollstaendiger Menu-Widget-Audit

Jedes sichtbare Menu-Control muss gegen Registry und Assistant Actions gemappt werden:

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

- Total cases: `3711`
- Passed: `3711`
- Failed: `0`
- Slow cases: `57`
- Registry settings loaded: `3243`
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
