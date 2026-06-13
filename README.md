# Bussradar

A universal **SwiftUI + MapKit** app for iPhone and Mac that shows Norwegian public-transit
vehicles moving in realtime, streamed from [Entur](https://developer.entur.org)'s open
real-time vehicle API.

- **Live positions** via Entur's GraphQL-over-WebSocket subscription (`graphql-transport-ws`).
- **Viewport-scoped**: only vehicles inside the visible map area are subscribed, using Entur's
  server-side `boundingBox` + `mode` filtering.
- **All transit modes** with a filter (defaults to buses).
- **Real line colours** enriched from the Entur Journey Planner v3 API and cached with **SwiftData**.
- **Swift 6** strict concurrency throughout.

## Requirements

- Xcode 26 or later (developed against Xcode 27 beta), iOS 26 / macOS 26 SDK.
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) ≥ 2.41 (`brew install xcodegen`).

## Getting started

```sh
make open        # generate the Xcode project and open it
```

Then, once, in Xcode → the **Bussradar** target → **Signing & Capabilities**, pick the
**Espen Bye** team (signing is set to Automatic; the team is intentionally left blank in
`project.yml`).

### Command line

```sh
make generate    # regenerate Bussradar.xcodeproj from project.yml
make build-ios   # build for the iOS Simulator
make build-mac   # compile the macOS app (signing disabled)
```

The project file (`Bussradar.xcodeproj`) is generated and **not** committed — edit `project.yml`
instead and re-run `make generate`.

## How it works

| Layer                  | Type                     | Responsibility                                                                                                |
| ---------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `EnturVehiclesClient`  | `actor`                  | Owns the WebSocket, speaks `graphql-transport-ws`, re-subscribes on viewport change, reconnects with backoff. |
| `JourneyPlannerClient` | `actor`                  | HTTP `lines(ids:)` lookups for line colours.                                                                  |
| `LineColorStore`       | `@MainActor @Observable` | Resolves line → colour, caches results in SwiftData (`CachedLine`).                                           |
| `VehiclesModel`        | `@MainActor @Observable` | Holds the live vehicle set, debounces the viewport, applies the mode filter, evicts stale vehicles.           |
| `LocationProvider`     | `@MainActor @Observable` | Core Location wrapper for the initial camera.                                                                 |
| `BusMapView` / UI      | SwiftUI                  | `Map` with one annotation per vehicle, `NavigationSplitView` shell.                                           |

No API key is required; all requests identify themselves with the `ET-Client-Name` header.

## Attribution

Real-time and journey-planner data from **Entur**, licensed under
[NLOD](https://data.norge.no/nlod/en/2.0).
