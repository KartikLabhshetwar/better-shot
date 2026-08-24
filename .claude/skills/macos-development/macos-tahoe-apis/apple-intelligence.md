# Apple Intelligence on macOS

On-device AI on macOS 26 ships through the **FoundationModels** framework —
there is no `AppleIntelligence` module, no `processingLocation` switch, and no
MCP (Model Context Protocol) support in Apple's SDK. The full, current API
guidance (availability handling, sessions, structured output, tool calling,
Private Cloud Compute, guardrails) lives in the dedicated skill:
**`skills/apple-intelligence/foundation-models/`** — read that, not this file,
before implementing.

## macOS specifics

```swift
import FoundationModels

let model = SystemLanguageModel.default

switch model.availability {
case .available:
    let session = LanguageModelSession()
    let response = try await session.respond(to: prompt)
case .unavailable(.deviceNotEligible):
    // Apple silicon required — Intel Macs are not eligible
    showUnsupportedUI()
case .unavailable(.appleIntelligenceNotEnabled):
    // User must enable Apple Intelligence in System Settings
    showEnableIntelligenceUI()
case .unavailable(let reason):
    showErrorUI(reason)
}
```

- The system model runs **on-device by default**; privacy is inherent to the
  framework, not a property you set. Larger workloads opt into Private Cloud
  Compute via `PrivateCloudComputeLanguageModel` (see the foundation-models
  skill's `models-and-agents.md`).
- Check `availability` every launch — model eligibility and the Apple
  Intelligence toggle are user- and hardware-dependent.
- Tool calling uses the framework's `Tool` protocol (see the foundation-models
  skill) — define tools there rather than inventing protocol layers.

## References

- [Foundation Models documentation](https://developer.apple.com/documentation/foundationmodels)
- `skills/apple-intelligence/foundation-models/SKILL.md` — the canonical skill
