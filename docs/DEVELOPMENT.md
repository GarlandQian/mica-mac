# Development

## Local Verification

All disposable output belongs under `tmp/codex/`.

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
node --check scripts/verify-runtime-smoke.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
git diff --check
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
python3 .agents/skills/apple-hig-expert/scripts/hig_checker.py batch tmp/codex/hig-audit.json
```

The source verifier checks the durable eleven-destination/Liquid Glass/single-live-session contract without reading active or archived Trellis task directories. The HIG batch input is a temporary task artifact and must be removed after its score is recorded in the task/journal. The runtime smoke script remains available as an optional compatibility check, but it is not part of the default finish gate and must be skipped when the user requests no smoke testing.

## Native sing-box Dependencies

`Package.swift` pins the StartedService transport dependencies exactly:

- `grpc-swift-2` 2.4.2
- `grpc-swift-nio-transport` 2.9.0
- `grpc-swift-protobuf` 2.4.1
- `swift-protobuf` 1.38.0

The license files in the resolved SwiftPM checkouts are Apache License 2.0. Generated protobuf Swift files are checked in; regenerate them only through `scripts/generate-sing-box-grpc.sh`. A future DMG/Sparkle packaging task must include the required third-party license notices.

## UI Smoke

When explicitly requested, UI smoke may launch the already-built Mica executable with command-line preference overrides. Do not click Test, Refresh, source update, connection close, or core-action controls during a visual-only pass. Store screenshots, window metadata, temporary homes, and helper scripts under `tmp/codex/`, then remove them when the task no longer needs them.

## Trellis Agents

Project-scoped Trellis integrations are installed for Codex and Claude Code.

Codex roles are configured in `.codex/agents/`. The project does not pin their models or reasoning levels and does not override Trellis's default Codex dispatch mode. Trellis-generated configuration and workflow files remain the source of truth for agent behavior.

Claude Code uses `.claude/settings.json` to register SessionStart, per-prompt workflow-state, and sub-agent context hooks. Its Trellis agents live in `.claude/agents/`, reusable workflow skills in `.claude/skills/trellis-*`, and explicit continuation/finish commands under `.claude/commands/trellis/`. Existing non-Trellis Claude skills are preserved during installation.

## Product Boundary

Mica is a remote controller application. Development and verification must not download, bundle, start, or run a local core, and must not modify system proxy settings, environment variables, firewall rules, OpenWrt, SSH, or `ubus` state.
