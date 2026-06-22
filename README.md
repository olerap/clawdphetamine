# clawdphetamine

Een piepkleine **native macOS achtergrond-agent** (Swift/AppKit, geen UI) die bestaat
zolang er minstens één Claude Code-sessie draait. Koppel er een Amphetamine
**Application-trigger** aan en je Mac blijft wakker tijdens Claude Code — en alleen dan.

Volledig eigen beheer, geen Electron, geen Node, geen externe plugin. Vervangt
`cc-amphetamine` (~200 MB Electron + hardgecodeerde paden) door ~40 KB native code.

---

## Waarom

Amphetamine kan alleen triggeren op een draaiende **applicatie**, niet op het
`claude`-CLI-proces. De oplossing: laat een minimale eigen app draaien precies zolang
Claude Code actief is, en laat Amphetamine daarop triggeren. De app heeft géén
zichtbare UI nodig — Amphetamine matcht op de **bundle-id** van het draaiende proces.

`cc-amphetamine` doet iets soortgelijks met een Electron-app, maar dat is zwaar (een
complete Chromium-runtime), macOS-only én out-of-the-box kapot (hardgecodeerd
`/Users/rchaves/...`-pad, geen `npm install`). clawdphetamine is één klein Swift-proces.

---

## Hoe het werkt

```
   Claude Code sessie start
        │  (SessionStart / UserPromptSubmit hook)
        ▼
   claude-hook.sh  ──►  legt marker neer: ~/.local/state/clawdphetamine/sessions/<claude-PID>
        │              en doet `open -g clawdphetamine.app` (start agent als die niet draait)
        ▼
   clawdphetamine.app (onzichtbaar achtergrond-proces)
        │  pollt elke 5s alle markers
        │  • marker "live" zolang z'n PID leeft  (kill(pid,0))
        │  • dode-PID markers worden verwijderd
        ▼
   geen live markers meer  ──►  agent sluit zichzelf af
        │
        ▼
   Amphetamine "Application"-trigger op clawdphetamine ziet de app verdwijnen
        │
        ▼
   Mac mag weer slapen
```

**De kern:** de marker is gekoppeld aan de **PID van het `claude`-proces**. De agent
bewaakt die PID. Sterft het proces — door nette afsluiting, crash, of **terminal-quit** —
dan is de PID weg, ruimt de agent de marker op, en sluit zichzelf af zodra er geen
sessies meer zijn. Dit is robuust waar een `SessionEnd`-hook faalt: die vuurt *niet*
bij een harde terminal-quit (precies het probleem dat cc-amphetamine met een
timeout omzeilt; wij lossen het op met PID-liveness, wat ook sneller opruimt).

Meerdere gelijktijdige sessies worden correct geteld: elke sessie heeft z'n eigen
marker; de agent stopt pas als de láátste PID weg is.

---

## Bestanden in dit project (`~/clawdphetamine/`)

| Bestand | Doel |
|---|---|
| `clawdphetamine.swift` | De agent: poll-loop + zelf-afsluiten. Geen UI (accessory-app). |
| `Info.plist` | Bundle-metadata: naam `clawdphetamine`, bundle-id `nl.olerap.clawdphetamine`, `LSUIElement`. |
| `build.sh` | Compileert met `swiftc`, bouwt `~/Applications/clawdphetamine.app`, ad-hoc signing. |
| `claude-hook.sh` | De Claude Code-hook: vindt de `claude`-PID, schrijft de marker, start de agent. |
| `README.md` | Dit bestand. |

Runtime-state (door de agent/hook beheerd): `~/.local/state/clawdphetamine/sessions/`.

---

## Vereisten

- macOS (getest op 26/27, arm64).
- **Xcode Command Line Tools** voor `swiftc` + `codesign`: `xcode-select --install`.
- Amphetamine (Mac App Store) voor de eigenlijke sleep-preventie.

---

## Bouwen & installeren

```sh
~/clawdphetamine/build.sh
```

Wat het doet:
1. Compileert `clawdphetamine.swift` met `swiftc -O -swift-version 5 -framework Cocoa`
   naar `~/Applications/clawdphetamine.app/Contents/MacOS/clawdphetamine`.
2. Kopieert `Info.plist` in de bundle.
3. **Ad-hoc code-signing** (`codesign --force --sign -`). Op Apple Silicon móét elke
   binary een geldige signature hebben, anders weigert macOS hem te starten.

Herbouwen na een wijziging: gewoon `build.sh` opnieuw draaien.

---

## Claude Code-hook

In `~/.claude/settings.json` (zie `hooks`):

```json
"hooks": {
  "SessionStart":     [ { "hooks": [ { "type": "command", "command": "\"$HOME/clawdphetamine/claude-hook.sh\"" } ] } ],
  "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "\"$HOME/clawdphetamine/claude-hook.sh\"" } ] } ]
}
```

- **SessionStart** start de agent meteen bij een nieuwe / hervatte sessie.
- **UserPromptSubmit** is een goedkope herstart-vangnet (mocht de agent ooit gecrasht
  zijn) en ververst de marker-mtime. Bewust geen hooks op elke tool-call.

### De PID-walk-up (waarom `$PPID` niet genoeg is)

De hook draait onder één of meer tussenliggende shells, dus `$PPID` is niet
betrouwbaar de `claude`-PID. `find_claude_pid()` loopt daarom de ouder-keten omhoog
(`ps -o ppid=`) tot het een proces met `comm == claude` vindt. Dat is de sessie-PID
die de marker krijgt. Faalt de zoektocht, dan valt het terug op `$PPID`.

---

## Amphetamine-trigger instellen (de echte sleep-preventie)

clawdphetamine houdt zélf geen slaap tegen — het is puur het signaal. Amphetamine doet het werk:

1. Zorg dat de agent draait (start een Claude-sessie, of test met de commando's hieronder).
2. Amphetamine → **Preferences → Triggers** → nieuwe trigger, categorie **Application**.
3. Kies **`clawdphetamine`** (bundle-id `nl.olerap.clawdphetamine`). Staat het niet in de lijst,
   blader dan naar `~/Applications/clawdphetamine.app` (in het open-venster `⌘⇧G`).

Klaar: app aanwezig → Amphetamine houdt de Mac wakker; app weg → Mac mag slapen.

> De app heeft bewust **geen menubalk-icoon** — dat zou dubbelop zijn met Amphetamine's eigen oog.

---

## Verifiëren / testen

```sh
# Simuleer een sessie met een levende test-PID en start de agent:
DIR=~/.local/state/clawdphetamine/sessions; mkdir -p "$DIR"
sleep 300 & echo $! ; : > "$DIR/$!"
open -g ~/Applications/clawdphetamine.app

# Identiteit zoals Amphetamine die ziet (moet clawdphetamine / nl.olerap.clawdphetamine zijn):
APID=$(pgrep -x clawdphetamine)
osascript -l JavaScript -e 'ObjC.import("AppKit");var p=parseInt("'"$APID"'"),a=$.NSWorkspace.sharedWorkspace.runningApplications,o="";for(var i=0;i<a.count;i++){var x=a.objectAtIndex(i);if(x.processIdentifier===p)o=x.localizedName.js+" / "+x.bundleIdentifier.js}o'

# Kill de test-PID -> binnen ~5s ruimt de agent op en sluit zichzelf af:
kill %1
sleep 6; pgrep -x clawdphetamine && echo "draait nog" || echo "afgesloten ✓"
```

---

## Aanpassen

| Wat | Waar |
|---|---|
| Poll-interval (5s) | `pollInterval` in `clawdphetamine.swift` |
| PID-reuse backstop (24u) | `maxAgeSeconds` in `clawdphetamine.swift` |
| Naam / bundle-id | `Info.plist` (`CFBundle*`) **en** `build.sh` (`--identifier`). Daarna trigger in Amphetamine opnieuw kiezen. |

Na elke aanpassing: `build.sh` opnieuw draaien.

---

## Troubleshooting

- **Agent draait niet:** check `pgrep -x clawdphetamine`. Zo niet, hook handmatig
  draaien: `~/clawdphetamine/claude-hook.sh` en kijken of er een marker komt in
  `~/.local/state/clawdphetamine/sessions/`.
- **"app is damaged / can't be opened":** signature ontbreekt of klopt niet → `build.sh`
  opnieuw (dat her-signt). Check met `codesign --verify --verbose ~/Applications/clawdphetamine.app`.
- **Agent sluit niet af na sessie-einde:** de marker-PID leeft nog. Controleer
  `~/.local/state/clawdphetamine/sessions/` en `ps -o comm= -p <PID>`.
- **Amphetamine ziet de app niet:** de agent moet *draaien* op het moment dat je de trigger
  kiest. Anders: blader rechtstreeks naar `~/Applications/clawdphetamine.app`.
- **Hooks doen niets:** ze gelden pas voor een **nieuwe** sessie (herstart Claude Code).

---

## Verwijderen

```sh
rm -rf ~/Applications/clawdphetamine.app ~/.local/state/clawdphetamine ~/clawdphetamine
# en de "hooks"-sectie uit ~/.claude/settings.json halen.
```

---

## Verschil met cc-amphetamine

| | cc-amphetamine | clawdphetamine |
|---|---|---|
| Runtime | Electron (~200 MB) | native Swift (~40 KB) |
| UI | menubalk-icoon (Electron tray) | geen (onzichtbaar achtergrond-proces) |
| Afhankelijkheden | node, npm, electron, pnpm | alleen CLT (build-time) |
| Cleanup bij terminal-quit | activity-timeout (tot 15 min) | PID-liveness (~5 s) |
| Identiteit | generieke `Electron` / `com.github.Electron` | eigen `clawdphetamine` / `nl.olerap.clawdphetamine` |
| Overleeft plugin-update | nee (4 patches kwijt) | n.v.t. — geen plugin |
| Eigendom | iemand anders z'n repo | volledig van jou |
