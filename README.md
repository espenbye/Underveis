# Underveis

A universal **SwiftUI + MapKit** app for iPhone and Mac that shows Norwegian public-transit
vehicles moving in realtime, streamed from [Entur](https://developer.entur.org)'s open
real-time vehicle API.

- **Live positions** via Entur's GraphQL-over-WebSocket subscription (`graphql-transport-ws`),
  with smooth marker interpolation between updates.
- **Viewport-scoped**: only vehicles inside the visible map area are subscribed, using Entur's
  server-side `boundingBox` + `mode` filtering.
- **All transit modes** with a filter (defaults to buses).
- **Transit stops** from the National Stop Register, with a **live departures board** — tap a stop
  for real-time departures and countdowns that tick every second.
- **Follow mode**: tap a vehicle to track it as it moves; the camera keeps it centred.
- **Real line colours** enriched from the Entur Journey Planner v3 API and cached with **SwiftData**.
- **Swift 6** strict concurrency throughout.

## Requirements

- Xcode 26 or later (developed against Xcode 27 beta), iOS 26 / macOS 26 SDK.
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) ≥ 2.41 (`brew install xcodegen`).

## Getting started

```sh
make open        # generate the Xcode project and open it
```

Signing uses Automatic code signing with the **Espen Bye** team (`DEVELOPMENT_TEAM = 9QD8BJRLPC`,
set in `project.yml`), so it builds and signs without any manual Xcode setup.

> The system `xcode-select` typically points at the Command Line Tools, which **cannot** build this
> app. The Makefile pins the full Xcode toolchain via `DEVELOPER_DIR`, so always build through it.

### Command line

```sh
make generate    # regenerate Underveis.xcodeproj from project.yml
make build-ios   # build for the iOS Simulator
make build-mac   # compile the macOS app (signing disabled)
```

The project file (`Underveis.xcodeproj`) is generated and **not** committed — edit `project.yml`
instead and re-run `make generate`. Adding or removing source files also requires a regen.

## How it works

Layered, with a hard `actor` → `@MainActor` boundary. `Vehicle`, `Stop`, and `Departure` are
immutable `Sendable` value types that cross it.

| Layer                  | Type                     | Responsibility                                                                                                |
| ---------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `EnturVehiclesClient`  | `actor`                  | Owns the WebSocket, speaks `graphql-transport-ws`, re-subscribes on viewport change, reconnects with backoff. |
| `JourneyPlannerClient` | `actor`                  | HTTP Journey Planner v3 lookups: line colours, stop places in a bounding box, and a stop's departures.        |
| `LineColorStore`       | `@MainActor @Observable` | Resolves line → colour, caches results in SwiftData (`CachedLine`) via a background `LineCacheWriter`.        |
| `VehiclesModel`        | `@MainActor @Observable` | Holds the live vehicle + stop sets, debounces the viewport, applies the mode filter, evicts stale vehicles.   |
| `DeparturesModel`      | `@MainActor @Observable` | Polls the selected stop's departures and runs a 1 Hz ticker so countdowns stay live between fetches.          |
| `LocationProvider`     | `@MainActor @Observable` | Core Location wrapper for the initial camera.                                                                 |
| `VehicleMapView` / UI  | SwiftUI                  | `Map` with a marker per vehicle and stop; wide-zoom clustering, follow mode, status pill, filter popover, and detail inspector. |

No API key is required; all requests identify themselves with the `ET-Client-Name` header.

## Attribution

Real-time and journey-planner data from **Entur**, licensed under
[NLOD](https://data.norge.no/nlod/en/2.0).
