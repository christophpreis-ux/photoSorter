<img src="icon.png" width="128" alt="PhotoSorter Icon">

# PhotoSorter

macOS-App (SwiftUI) zum automatischen Aussortieren von Fotos – komplett on-device mit Apple-Frameworks (Vision, ImageIO, Accelerate).

## Funktionen

- Ordner wählen (oder per Drag & Drop) – JPEG, HEIC, PNG, TIFF und RAW (CR2/CR3, NEF, ARW, DNG, RAF, ORF, RW2 …). RAW+JPEG+XMP mit gleichem Namen werden als ein Foto behandelt.
- **Szenen-Erkennung**: ähnliche Fotos werden über Aufnahmezeit (EXIF inkl. Sub-Sekunden) und Bildinhalt (Vision Feature Prints) gruppiert.
- **Bewertung** je Foto: Schärfe des Motivs (Laplace-Varianz), Augen offen/zu (Gesichts-Landmarken, relativ zur selben Person in der Serie), Apple-Gesichtsqualität, Blickrichtung, Belichtung, Apple Aesthetics Score.
- **Schieberegler** für die Aussortier-Stärke – Fotos fliegen animiert zwischen „Behalten“ (links) und „Aussortieren“ (rechts).
- **Gruppenfotos**: Personen werden über die Serie hinweg verfolgt; für jede Person bleibt mindestens eine Version, auf der sie gut aussieht. Vergleichsansicht zeigt alle Gesichter pro Version.
- **Abschnitte erkennen** – Alltag, Reisen und Feiern (Strand & Meer, Berge, Winter, Stadt, Natur, Tiere, Kinder & Spielplatz, Geburtstag, Weihnachten, Party, Konzert, Sport, Essen, Unterwegs, Zuhause, Nacht, Dokumente …) sowie Hochzeiten (Getting Ready, Trauung Kirche/Standesamt/frei, Sektempfang, Paarshooting) – über Vision-Bildklassifikation, Gesichter und Zeitpausen. Unbekannte Abschnitte benennt – falls verfügbar – Apples On-Device-Sprachmodell. Abschnitte lassen sich umbenennen, umtypisieren, teilen und zusammenführen.
- **Sortieren in Ordner pro Abschnitt** (`01 Getting Ready`, `02 Trauung Kirche`, `03 Sektempfang` …) – damit in Lightroom pro Ordner ein Preset angewendet werden kann.
- **Gruppenfotos kombinieren**: Hat jemand auf dem besten Foto die Augen zu, wird sein Gesicht aus einer anderen Aufnahme der Serie per Landmarken ausgerichtet, farblich angeglichen und weich eingeblendet. Vorher/Nachher-Vergleich, Speichern nur auf Wunsch (JPEG bzw. 16-Bit-TIFF bei RAW), Original bleibt unverändert. Ist die Kopfhaltung zu unterschiedlich, wird bewusst nicht getauscht.
- **Abschnitt „Kombinieren“** in der Seitenleiste: alle Gruppenfotos, bei denen jemand die Augen zu hat, mit Vorher/Nachher – mit einem Klick übernehmen (oder „Alle übernehmen“).
- **Apple Fotos**: Jahr oder Monat aus der Mediathek wählen, analysieren lassen und Aussortiertes nach „Zuletzt gelöscht“ verschieben (30 Tage wiederherstellbar). **Favoriten werden immer behalten.** Kombinierte Gruppenfotos werden als neues Foto in der Mediathek angelegt.
- **Statistik** in einer lokalen Datenbank (SwiftData, `~/Library/Application Support/PhotoSorter`): aussortierte Fotos, Quote, Datenmenge, kombinierte Fotos, geschützte Favoriten, Verlauf pro Monat.
- **Großansicht** mit der Leertaste: blättern mit ← →, entscheiden mit K / X, Gesichter einblenden mit F.
- **Drag & Drop**: Fotos einfach zwischen „Behalten“ und „Aussortieren“ hin- und herziehen.
- **Lightroom** (Schritt 4): behaltene Fotos mit Presets übertragen – ein Standard-Preset für alle und ein eigenes pro Abschnitt. Passende Presets werden vorgeschlagen (eigene Lightroom-Presets mit passendem Namen haben Vorrang, sonst eingebaute PhotoSorter-Vorschläge wie „Hochzeit Hell & Weich“, „Landschaft Lebendig“, „Nacht & Party“). RAW bekommt eine XMP-Begleitdatei, JPEG/HEIC die Einstellungen verlustfrei in den Metadaten; Abschnitt und Kategorie werden als Stichwörter gesetzt. Danach öffnet sich Lightroom mit dem Import-Dialog.
- Manuelles Überstimmen (Doppelklick, Kontextmenü, Tasten K / X / A).
- **Sortieren** verschiebt Aussortiertes in den Unterordner `Aussortiert` (nichts wird gelöscht, Rückgängig möglich). Behaltene Fotos kommen in die Abschnitts-Ordner und können optional ein Kategorie-Präfix bekommen (`Gruppenfoto_…`, `Portrait_…`, `Tier_…`, `Motiv_…`).

## Tests

```bash
xcodebuild test -project PhotoSorter.xcodeproj -scheme PhotoSorter -destination 'platform=macOS'
```

Die Tests (Swift Testing) decken Auswahl-Logik, Gruppenfoto-Regel, Szenen- und Abschnitts-Erkennung, Einlesen, Sortieren/Rückgängig, Schärfemessung, Ausrichtung beim Kombinieren und den Favoritenschutz ab – mit generierten Testbildern, ohne private Fotos.

## Loslegen (für Mitentwickler)

```bash
git clone https://github.com/christophpreis-ux/photoSorter.git
cd photoSorter
open PhotoSorter.xcodeproj
```

In Xcode einfach ⌘R (App) bzw. ⌘U (Tests). Signiert wird lokal ad hoc – kein Apple-Developer-Team nötig. Benötigt macOS 26+ (Liquid Glass) und Xcode 26+.

Das Xcode-Projekt wird aus `project.yml` erzeugt. Wer Dateien hinzufügt oder Build-Einstellungen ändert, passt `project.yml` an und führt `xcodegen generate` aus (`brew install xcodegen`).

### Aufbau

| Ordner | Inhalt |
| --- | --- |
| `PhotoSorter/Analysis` | Einlesen (Ordner, Apple Fotos), Bildanalyse (Vision), Szenen, Auswahl-Logik, Abschnitte, Kombinieren, Dateien sortieren, Lightroom/XMP |
| `PhotoSorter/Model` | `AppModel` (Zustand der App), Datenmodelle, Statistik-Datenbank (SwiftData) |
| `PhotoSorter/Views` | SwiftUI-Oberfläche (Liquid Glass, dunkles Theme) |
| `PhotoSorterTests` | Swift-Testing-Tests mit generierten Testbildern |

Startargumente zum schnellen Testen: `-openFolder /pfad` öffnet direkt einen Ordner, `-openSidebar merge|stats|preview|lightroom` springt in eine Ansicht.
