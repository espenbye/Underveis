# Underveis

A universal SwiftUI + MapKit app showing Norwegian transit vehicles live on a map, streamed from
Entur's open real-time vehicles API. This glossary fixes the language the app and its UI use.

## Language

**Innstillinger** (Settings):
App-level configuration and information — persistent preferences and an "About" section
(version, data attribution, links). Distinct from the transient on-map **Filtre**: Innstillinger is
reached app-wide and persists, Filtre scopes only what the live map currently shows.
_Avoid_: Preferences, Valg.

**Filtre** (Filter):
The transient, on-map control that scopes the live vehicle feed — which transport **modes** are shown
and whether **holdeplasser** are drawn. Lives on the map for in-context access; not part of Innstillinger.
_Avoid_: Settings (for this control).

**Modus** (Mode):
A category of transit vehicle (Buss, Trikk, T-bane, Tog, Ferge, Ekspressbuss, Fly, Taxi), mirroring
Entur's `VehicleModeEnumeration`.

**Holdeplass** (Stop):
A transit stop place drawn on the map when zoomed in; toggled via Filtre.

**Watched line** / **Fulgt linje**:
A line the user has pinned so its vehicles are always shown on the map, overriding the Filtre mode
scope. Distinct from following a single vehicle's live position (**Følg**).
