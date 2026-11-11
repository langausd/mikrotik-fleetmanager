# `tools/branding/` – Prototyp für das cfm-Branding-Paket (DO1.8, DT3.3, TODO 79)

Plan und Stand: [docs/NETINSTALL.md](../../docs/NETINSTALL.md). Noch **kein** gebautes `.dpk`, nichts davon ist auf
Hardware gelaufen. Die Dateien hier sind die Zutaten für MikroTiks „Branding maker“ (mikrotik.com-Konto):

| Datei | Feld im Branding Maker | Inhalt |
|---|---|---|
| `cfm-stub.rsc` | Default configuration | cfm-Stub: Bridge, DHCP-Client + 192.168.88.1, Onboarding-Schlüssel für `admin`, nur SSH |
| `caps-mode.rsc` | CAPs mode script | derselbe Stub (Reset-Taster → CAP-Modus bei PoE-Geräten) |
| `webfig/index2.fragment.html` | WebFig login page (`index2.html`) | der Ausschnitt, der in MikroTiks `index2.html` eingefügt wird (Knopf + Einbindung von `cfm.js`/`cfm.css`) |
| `webfig/cfm.js`, `webfig/cfm.css` | weitere Dateien der Login-Seite (gleicher Pfad wie `index2.html`) | Anmeldung an der REST-API, Laden von `web/cfm-*.js` vom Gerät |
| `skins/` | skins | Skin für die Gruppe `cfm-dns` – wird in WebFig („Design Skin“) erzeugt, siehe dort |
| Logo | WebFig logo (`mikrotik_logo.png`), ASCII logo | noch kein Entwurf |

Bauen: Branding Maker öffnen → Router name `cfm` → Default configuration = `cfm-stub.rsc` (vorher `@ONBKEY@`
ersetzen, siehe Stub) → CAPs mode script = `caps-mode.rsc` → WebFig login page: MikroTiks Standard-`index2.html`
herunterladen, den Ausschnitt aus `webfig/index2.fragment.html` einfügen, `cfm.js` und `cfm.css` als weitere Dateien
hochladen → Optionen „Hide Default configuration prompt“ und „Hide default caps-mode-script“ (ab 7.15) → MAKE.
Installieren wie ein Paket: Datei auf das Gerät, Neustart (oder per Netinstall mit den Paketen).

`cfm.js` ist bewusst nahe an `tools/editor/cfm-loader.js` (DT3.2) gehalten; Änderungen dort gehören auch hierher.
