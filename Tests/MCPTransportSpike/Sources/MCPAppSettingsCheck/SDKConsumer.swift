import MCP

func compileMCPConsumer() async {
    let server = Server(name: "app-settings-check", version: "1")
    await server.withMethodHandler(ListTools.self) { _ in .init(tools: []) }
    await server.stop()
}
