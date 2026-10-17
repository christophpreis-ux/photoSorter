<img src="icon.png" width="128" alt="PhotoSorter Icon">

# PhotoSorter

macOS-App (SwiftUI) zum automatischen Aussortieren von Fotos – komplett on-device mit Apple-Frameworks (Vision, ImageIO, Accelerate).

## Funktionen

- Ordner wählen (oder per Drag & Drop) – JPEG, HEIC, PNG, TIFF und RAW (CR2/CR3, NEF, ARW, DNG, RAF, ORF, RW2 …). RAW+JPEG+XMP mit gleichem Namen werden als ein Foto behandelt.
- **Szenen-Erkennung**: ähnliche Fotos werden über Aufnahmezeit (EXIF inkl. Sub-Sekunden) und Bildinhalt (Vision Feature Prints) gruppiert.
- **Bewertung** je Foto: Schärfe des Motivs (Laplace-Varianz), Augen offen/zu (Gesichts-Landmarken, relativ zur selben Person in der Serie), Apple-Gesichtsqualität, Blickrichtung, Belichtung, Apple Aesthetics Score.
- **Schieberegler** für die Aussortier-Stärke – Fotos fliegen animiert zwischen „Behalten“ (links) und „Aussortieren“ (rechts).
- **Gruppenfotos**: Personen werden über die Serie hinweg verfolgt; für jede Person bleibt mindestens eine Version, auf der sie gut aussieht. Vergleichsansicht zeigt alle Gesichter pro Version.
- **Abschnitte erkennen** (Getting Ready, Trauung Kirche/Standesamt/frei, Sektempfang, Gruppenfotos, Paarshooting, Essen, Party, Details …) über Vision-Bildklassifikation, Gesichter und Zeitpausen. Unbekannte Abschnitte benennt – falls verfügbar – Apples On-Device-Sprachmodell. Abschnitte lassen sich umbenennen, umtypisieren, teilen und zusammenführen.
- **Sortieren in Ordner pro Abschnitt** (`01 Getting Ready`, `02 Trauung Kirche`, `03 Sektempfang` …) – damit in Lightroom pro Ordner ein Preset angewendet werden kann.
- **Gruppenfotos kombinieren**: Hat jemand auf dem besten Foto die Augen zu, wird sein Gesicht aus einer anderen Aufnahme der Serie per Landmarken ausgerichtet, farblich angeglichen und weich eingeblendet. Vorher/Nachher-Vergleich, Speichern nur auf Wunsch (JPEG bzw. 16-Bit-TIFF bei RAW), Original bleibt unverändert. Ist die Kopfhaltung zu unterschiedlich, wird bewusst nicht getauscht.
- Manuelles Überstimmen (Doppelklick, Kontextmenü, Tasten K / X / A).
- **Sortieren** verschiebt Aussortiertes in den Unterordner `Aussortiert` (nichts wird gelöscht, Rückgängig möglich). Behaltene Fotos kommen in die Abschnitts-Ordner und können optional ein Kategorie-Präfix bekommen (`Gruppenfoto_…`, `Portrait_…`, `Tier_…`, `Motiv_…`).

## Bauen

```bash
xcodegen generate
open PhotoSorter.xcodeproj
```

Benötigt macOS 26+ (Liquid Glass) und Xcode 26+.
