# Bussradar — Claude guide

Universal SwiftUI + MapKit app (iPhone + Mac) showing Norwegian transit vehicles live on a map,
streamed from Entur's open real-time vehicles API. Swift 6 strict concurrency, MapKit, SwiftData,
project generated with xcodegen. Min targets: iOS 26 / macOS 26.

## Build & run

The system `xcode-select` points at CommandLineTools, which **cannot** build this app. The Makefile
pins the full Xcode via `DEVELOPER_DIR` (Xcode 27 beta), so always go through it:

```sh
make generate    # regenerate Bussradar.xcodeproj from project.yml
make open        # generate + open in Xcode
make build-mac   # compile macOS (signing disabled)
make build-ios   # build for the iOS Simulator
```

- **`Bussradar.xcodeproj` is generated and git-ignored.** Never edit it by hand — change `project.yml`
  and run `make generate`. Adding/removing source files also requires a regen.
- **Signing:** Automatic, with the **Espen Bye** team (`DEVELOPMENT_TEAM = 9QD8BJRLPC`) set in
  `project.yml` — builds sign without manual Xcode setup.
- App icon (`Resources/Assets.xcassets/AppIcon.appiconset`) is currently iOS-only (1024 single-size).

## Architecture

Layered, with a hard actor → main-actor boundary. `Vehicle` is an immutable `Sendable` value type
that crosses it.

| Layer                 | Type                                                                    | File(s)                                         |
| --------------------- | ----------------------------------------------------------------------- | ----------------------------------------------- |
| WebSocket / streaming | `actor EnturVehiclesClient`                                             | `Sources/Networking/`                           |
| Line-colour lookup    | `actor JourneyPlannerClient`                                            | `Sources/Networking/JourneyPlannerClient.swift` |
| Colour cache          | `@MainActor @Observable LineColorStore` + `@ModelActor LineCacheWriter` | `Sources/Persistence/`                          |
| App state             | `@MainActor @Observable VehiclesModel`                                  | `Sources/State/VehiclesModel.swift`             |
| Location              | `@MainActor @Observable LocationProvider`                               | `Sources/State/LocationProvider.swift`          |
| Map / UI              | SwiftUI                                                                 | `Sources/Map/`, `Sources/UI/`, `Sources/App/`   |

## Conventions

- **Concurrency:** networking is `actor`-isolated; state/UI models are `@MainActor @Observable`
  (Observation framework, not `ObservableObject`). Cross-boundary types must be `Sendable`. Background
  SwiftData writes go through a `@ModelActor`, never the main context.
- **No** `try!` / force-unwrap / `fatalError` in app code (one deliberate `fatalError` guards
  unrecoverable `ModelContainer` creation in `BussradarApp`).
- Persisted data uses **SwiftData** (`@Model`); transient UI prefs use `@AppStorage`/`@SceneStorage`.
- `CLLocationManager` delegate callbacks use `MainActor.assumeIsolated` (manager is created on main).
  Read Sendable values out of delegate params _before_ the closure — don't capture the non-Sendable
  `manager`/`CLLocation` into it.
- macOS differences: `CLAuthorizationStatus.authorizedWhenInUse` does not exist on macOS (see
  `LocationProvider.isAuthorized`); the sandbox entitlement is applied only via
  `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` in `project.yml`.

## Entur API (verified by live schema introspection — trust these over the public docs)

- **Vehicles subscription (WS):** `wss://api.entur.io/realtime/v2/vehicles/subscriptions`,
  subprotocol **`graphql-transport-ws`** (connection_init → connection_ack → subscribe → next →
  complete, with ping/pong). **HTTP** snapshot: `https://api.entur.io/realtime/v2/vehicles/graphql`.
- **Auth:** no API key. Send `ET-Client-Name: espenbye-bussradar` as an HTTP header _and_ in the
  connection_init payload (`{"headers":{...}}`).
- **`vehicles` args:** `boundingBox {minLat,minLon,maxLat,maxLon}` (all `Float!`), `mode`
  (`VehicleModeEnumeration`: AIR/BUS/COACH/FERRY/METRO/TAXI/TRAM/RAIL), `monitored`, `bufferSize`,
  `bufferTime`, `maxDataAge` (ISO-8601 `Duration`). Prefer `lastUpdatedEpochSecond` /
  `expirationEpochSecond` (Float) over the ISO `DateTime` fields — no string parsing.
- **Mode filter strategy:** one enabled mode → pass `mode` server-side; multiple → omit it and filter
  client-side (`VehiclesModel`).
- **Line colours** are NOT in the vehicles API. Fetch from **Journey Planner v3**
  (`https://api.entur.io/journey-planner/v3/graphql`, same `ET-Client-Name`): `lines(ids: [ID])` →
  `presentation { colour textColour }` (hex without `#`, may be null). A vehicle's `line.lineRef` is
  the Journey Planner line `id`. Unknown ids are silently omitted from the response.
- **Introspection gotcha:** the endpoints reject "bad-faith" introspection — only **one `__type`
  (and one `__Type.fields`) per request**. Split schema probes into separate calls.

## Verifying changes

Build both platforms (must be warning-clean under Swift 6). To sanity-check the live data path
without the UI: POST the `VehiclesQuery.snapshot` query (see `Sources/Networking/VehiclesQuery.swift`)
to the HTTP endpoint with an `ET-Client-Name` header and an Oslo bounding box.
