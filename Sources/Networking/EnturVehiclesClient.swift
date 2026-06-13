import Foundation

enum ConnectionStatus: Sendable, Equatable {
    case idle
    case connecting
    case live
    case reconnecting
}

/// Owns the WebSocket connection to Entur's realtime vehicles subscription and drives the
/// `graphql-transport-ws` handshake. All mutable state is actor-isolated; consumers observe two
/// `AsyncStream`s: `updates` (batches of vehicles) and `status` (connection state).
///
/// The active subscription tracks the visible map viewport: `setViewport(_:mode:)` swaps the
/// subscription (`complete` old → `subscribe` new) so the server only streams vehicles in view.
actor EnturVehiclesClient {
    private let subscriptionURL = URL(string: "wss://api.entur.io/realtime/v2/vehicles/subscriptions")!
    private let httpURL = URL(string: "https://api.entur.io/realtime/v2/vehicles/graphql")!
    private let clientName: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var task: URLSessionWebSocketTask?
    private var isAcknowledged = false
    private var activeSubscriptionID: String?
    private var subscriptionCounter = 0
    private var currentRequest: (box: BoundingBox, mode: VehicleMode?)?
    private var reconnectAttempts = 0
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    let updates: AsyncStream<[Vehicle]>
    private let updatesContinuation: AsyncStream<[Vehicle]>.Continuation
    let status: AsyncStream<ConnectionStatus>
    private let statusContinuation: AsyncStream<ConnectionStatus>.Continuation

    init(clientName: String = "espenbye-bussradar", session: URLSession = .shared) {
        self.clientName = clientName
        self.session = session
        (updates, updatesContinuation) = AsyncStream.makeStream()
        (status, statusContinuation) = AsyncStream.makeStream()
    }

    // MARK: - Public API

    /// Points the live subscription at a new viewport (and optional single-mode filter).
    /// Connects lazily on first call.
    func setViewport(_ box: BoundingBox, mode: VehicleMode?) async {
        currentRequest = (box, mode)
        if task == nil {
            await connect()
        } else if isAcknowledged {
            await resubscribe()
        }
    }

    /// Tears down the connection and stops reconnecting.
    func stop() {
        currentRequest = nil
        receiveTask?.cancel()
        pingTask?.cancel()
        receiveTask = nil
        pingTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isAcknowledged = false
        activeSubscriptionID = nil
        statusContinuation.yield(.idle)
    }

    /// One-shot HTTP query to fill the map immediately, before the subscription warms up.
    func snapshot(box: BoundingBox, mode: VehicleMode?) async -> [Vehicle] {
        var request = URLRequest(url: httpURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientName, forHTTPHeaderField: "ET-Client-Name")
        let operation = GraphQLOperation(
            query: VehiclesQuery.snapshot,
            variables: VehiclesVariables(boundingBox: box, mode: mode?.rawValue),
            operationName: "Vehicles"
        )
        guard let body = try? encoder.encode(operation) else { return [] }
        request.httpBody = body

        guard let (data, _) = try? await session.data(for: request),
            let response = try? decoder.decode(VehiclesResponse.self, from: data)
        else { return [] }
        return (response.data?.vehicles ?? []).compactMap { $0.toVehicle() }
    }

    // MARK: - Connection lifecycle

    private func connect() async {
        guard task == nil else { return }
        statusContinuation.yield(.connecting)

        var request = URLRequest(url: subscriptionURL)
        request.setValue(clientName, forHTTPHeaderField: "ET-Client-Name")
        request.setValue("graphql-transport-ws", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let socket = session.webSocketTask(with: request)
        task = socket
        isAcknowledged = false
        activeSubscriptionID = nil
        socket.resume()

        await send(TransportWS.ConnectionInit(payload: .init(headers: ["ET-Client-Name": clientName])))

        receiveTask = Task { [weak self] in await self?.runReceiveLoop() }
        pingTask = Task { [weak self] in await self?.runPingLoop() }
    }

    private func runReceiveLoop() async {
        while !Task.isCancelled, let socket = task {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    await handle(text)
                case .data(let data):
                    await handle(String(decoding: data, as: UTF8.self))
                @unknown default:
                    break
                }
            } catch {
                await handleDisconnect()
                return
            }
        }
    }

    private func runPingLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            if isAcknowledged {
                await send(TransportWS.Ping())
            }
        }
    }

    private func handleDisconnect() async {
        guard task != nil else { return }  // already torn down by another path
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil
        isAcknowledged = false
        activeSubscriptionID = nil
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil

        guard currentRequest != nil else {
            statusContinuation.yield(.idle)
            return
        }

        statusContinuation.yield(.reconnecting)
        reconnectAttempts += 1
        let backoff = min(pow(2.0, Double(reconnectAttempts - 1)), 30.0)
        let jitter = Double.random(in: 0...1)
        try? await Task.sleep(for: .seconds(backoff + jitter))

        guard !Task.isCancelled, currentRequest != nil, task == nil else { return }
        await connect()
    }

    // MARK: - Messaging

    private func handle(_ text: String) async {
        guard let data = text.data(using: .utf8),
            let envelope = try? decoder.decode(TransportWS.Envelope.self, from: data)
        else { return }

        switch envelope.type {
        case "connection_ack":
            isAcknowledged = true
            reconnectAttempts = 0
            statusContinuation.yield(.live)
            if currentRequest != nil { await resubscribe() }

        case "next":
            guard envelope.id == activeSubscriptionID,
                let message = try? decoder.decode(VehiclesNextMessage.self, from: data)
            else { return }
            let vehicles = (message.payload.data?.vehicles ?? []).compactMap { $0.toVehicle() }
            if !vehicles.isEmpty { updatesContinuation.yield(vehicles) }

        case "error", "complete":
            if envelope.id == activeSubscriptionID { activeSubscriptionID = nil }

        case "ping":
            await send(TransportWS.Pong())

        default:
            break  // connection_ack handled above; pong/ka ignored
        }
    }

    private func resubscribe() async {
        guard let request = currentRequest else { return }
        if let oldID = activeSubscriptionID {
            await send(TransportWS.Complete(id: oldID))
        }
        subscriptionCounter += 1
        let id = "sub-\(subscriptionCounter)"
        activeSubscriptionID = id

        let operation = GraphQLOperation(
            query: VehiclesQuery.subscription,
            variables: VehiclesVariables(boundingBox: request.box, mode: request.mode?.rawValue),
            operationName: "Vehicles"
        )
        await send(TransportWS.Subscribe(id: id, payload: operation))
    }

    private func send(_ message: some Encodable) async {
        guard let socket = task, let data = try? encoder.encode(message) else { return }
        do {
            try await socket.send(.string(String(decoding: data, as: UTF8.self)))
        } catch {
            await handleDisconnect()
        }
    }
}
