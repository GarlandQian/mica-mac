# Native Swift sing-box transport research

- Date: 2026-07-18
- Decision: Mica remains native Swift/SwiftUI and MIT licensed.

## Protocol surface

The audited Sparxie reference contains `core/proto/daemon/started_service.proto`. The service surface needed for parity is:

- Unary: GetVersion, GetDefaultLogLevel, ClearLogs, GetClashModeStatus, SetClashMode, URLTest, SelectOutbound, CloseConnection, CloseAllConnections, SetTailscaleExitNode, TailscaleLogout.
- Server streams: SubscribeLog, SubscribeStatus, SubscribeGroups, SubscribeClashMode, SubscribeConnections, SubscribeTailscaleStatus.
- Data families: version, logs, status/traffic/memory, policy groups/nodes, outbound mode, connections/process metadata, and Tailscale endpoints/users/peers.

The proto is treated as a protocol description only. Sparxie Rust implementation source is not copied or linked.

## Swift implementation choice

- Use the official gRPC Swift 2 stack: `grpc-swift-2`, `grpc-swift-nio-transport`, and `grpc-swift-protobuf`.
- Current official releases observed during planning were gRPC Swift 2.4.2, NIO transport 2.9.0, and protobuf integration 2.4.1. Implementation must resolve a mutually compatible exact set and record the lockfile rather than assuming all latest version numbers compose.
- Commit the proto plus reproducibly generated Swift message/client files so routine builds do not require a developer-installed `protoc`.
- Wrap generated code behind `SingBoxGRPCClient`; no generated type crosses into App presentation state.
- Use structured concurrency and bounded AsyncSequence adapters; generation cancellation closes streams and the underlying client channel.

## Primary sources

- gRPC Swift 2: https://github.com/grpc/grpc-swift-2
- gRPC Swift NIO transport: https://github.com/grpc/grpc-swift-nio-transport
- gRPC Swift protobuf integration: https://github.com/grpc/grpc-swift-protobuf

## First implementation gate

Before adding any sing-box UI, compile a minimal generated StartedService client under Swift 6.2/macOS 27 and prove with an in-process fixture service that unary calls, server streams, cancellation, and channel shutdown work. Do not connect to or start a real sing-box core.
