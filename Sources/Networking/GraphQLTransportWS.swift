import Foundation

/// Message types for the `graphql-transport-ws` subprotocol
/// (https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md), which Entur's
/// realtime vehicles subscription endpoint speaks.
///
/// Handshake: `connection_init` → `connection_ack` → `subscribe` → `next`… → `complete`,
/// with `ping`/`pong` heartbeats either direction.
enum TransportWS {

    // MARK: Outgoing (client → server)

    struct ConnectionInit: Encodable {
        var type = "connection_init"
        var payload: Payload?

        struct Payload: Encodable {
            /// Entur reads `ET-Client-Name` from here (browsers can't set WebSocket upgrade
            /// headers); native clients also send it as an HTTP header for good measure.
            var headers: [String: String]
        }
    }

    struct Subscribe<Variables: Encodable & Sendable>: Encodable {
        let id: String
        var type = "subscribe"
        let payload: GraphQLOperation<Variables>
    }

    struct Complete: Encodable {
        let id: String
        var type = "complete"
    }

    struct Ping: Encodable {
        var type = "ping"
    }

    struct Pong: Encodable {
        var type = "pong"
    }

    // MARK: Incoming (server → client)

    /// Lightweight envelope decoded first to dispatch on `type` before doing a typed decode of
    /// the operation-specific payload.
    struct Envelope: Decodable {
        let type: String
        let id: String?
    }
}

/// A standard GraphQL operation body, reused for both the WebSocket `subscribe` payload and the
/// one-shot HTTP snapshot request.
struct GraphQLOperation<Variables: Encodable & Sendable>: Encodable, Sendable {
    let query: String
    let variables: Variables
    var operationName: String?
}
