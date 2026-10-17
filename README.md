# PhotoSorter

macOS-App (SwiftUI) zum automatischen Aussortieren von Fotos – komplett on-device mit Apple-Frameworks (Vision, ImageIO, Accelerate).

## Funktionen

- Ordner wählen (oder per Drag & Drop) – JPEG, HEIC, PNG, TIFF und RAW (CR2/CR3, NEF, ARW, DNG, RAF, ORF, RW2 …). RAW+JPEG+XMP mit gleichem Namen werden als ein Foto behandelt.
- **Szenen-Erkennung**: ähnliche Fotos werden über Aufnahmezeit (EXIF inkl. Sub-Sekunden) und Bildinhalt (Vision Feature Prints) gruppiert.
- **Bewertung** je Foto: Schärfe des Motivs (Laplace-Varianz), Augen offen/zu (Gesichts-Landmarken, relativ zur selben Person in der Serie), Apple-Gesichtsqualität, Blickrichtung, Belichtung, Apple Aesthetics Score.
- **Schieberegler** für die Aussortier-Stärke – Fotos fliegen animiert zwischen „Behalten“ (links) und „Aussortieren“ (rechts).
- **Gruppenfotos**: Personen werden über die Serie hinweg verfolgt; für jede Person bleibt mindestens eine Version, auf der sie gut aussieht. Vergleichsansicht zeigt alle Gesichter pro Version.
- Manuelles Überstimmen (Doppelklick, Kontextmenü, Tasten K / X / A).
- **Aussortieren** verschiebt in den Unterordner `Aussortiert` (nichts wird gelöscht, Rückgängig möglich). Behaltene Fotos werden optional nach Kategorie umbenannt (`Gruppenfoto_…`, `Portrait_…`, `Tier_…`, `Motiv_…`) und bleiben im Ordner.

## Bauen

```bash
xcodegen generate
open PhotoSorter.xcodeproj
```

Benötigt macOS 15+ und Xcode 16+.
