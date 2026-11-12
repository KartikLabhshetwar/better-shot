# MCP transport feasibility spike

Run `bash Tests/MCPTransportSpike/run.sh` on macOS 26+ with Xcode 26+. If
SwiftPM cannot apply its build sandbox in the current shell, rerun with
`BETTERSHOT_MCP_SPIKE_DISABLE_SANDBOX=1`. The script pins the official
`modelcontextprotocol/swift-sdk` 0.12.1 release and
its resolved dependencies, binds a temporary HTTP listener to `127.0.0.1`, and
checks initialize, tool discovery, a harmless `ping`, missing/wrong bearer
tokens, and a rejected Origin. It shuts down the server and listener on both
success and failure. `BETTERSHOT_TESTING=1` is set for the run.

The SDK provides `StatelessHTTPServerTransport.handleRequest`, not a listening
HTTP server. This proof supplies a small SwiftNIO adapter; neither dependency
is added to BetterShot. A consumer target compiles an SDK integration with the
app's Swift 5, MainActor-default, and approachable-concurrency settings. It
proves SDK import and a server handler call compile under those settings, not
full app-target integration.

The harness uses a one-shot fixed-response tool and an ephemeral token; it does
not open a BetterShot project or read user files. Streaming responses return
501, requests over 1 MiB receive 413, and Host, path, bearer token, and the
SDK's localhost Origin validation are checked. These are harness boundaries,
not a production endpoint design.

The pin is reproducible, but 0.12.1 has reported compatibility and transport
risks that need target-client testing before app integration:

- [#262](https://github.com/modelcontextprotocol/swift-sdk/issues/262) reports
  initialize decoding failures for nested `experimental` and `extensions`
  capabilities from a ChatGPT client.
- [#265](https://github.com/modelcontextprotocol/swift-sdk/issues/265) reports
  cross-request context collisions when concurrent clients reuse a JSON-RPC ID.
- [#255](https://github.com/modelcontextprotocol/swift-sdk/issues/255) reports
  a cancelled stateless request can leave its HTTP exchange waiting.

These are upstream reports, not failures reproduced by this limited smoke test.
The SDK also declares Swift tools 6.1 and macOS 13 in its 0.12.1 manifest; the
isolated consumer check passed with BetterShot's current compiler settings on
the installed Xcode toolchain. `project.yml` was not changed.
