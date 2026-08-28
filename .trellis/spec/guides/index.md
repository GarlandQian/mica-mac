# Thinking Guides

These guides are short decision aids for Mica changes that cross ownership
boundaries or may duplicate existing behavior. They supplement, but do not
replace, the active backend and frontend contracts.

## Available Guides

| Guide | Purpose | When to use |
|---|---|---|
| [Code Reuse Thinking Guide](./code-reuse-thinking-guide.md) | Find the existing owner before introducing a helper, projection, or UI primitive | A change looks similar to code already in the repository |
| [Cross-Layer Thinking Guide](./cross-layer-thinking-guide.md) | Trace controller data and commands through every Mica boundary | A change touches transport, session state, presentation, or SwiftUI |

## Quick Triggers

Read the cross-layer guide when a change adds or changes a controller field,
capability, endpoint, live stream, session command, published snapshot,
projection, cache, timeline, or visible state.

Read the reuse guide before adding a formatter, index, cache, command
dispatcher, inspector field, Workbench primitive, localization key, or
preference value. Search current owners first:

```bash
rg "type|function|field|localization.key" Sources Tests .trellis/spec
```

After implementation, verify the affected contract, source owner, offline
tests, and `git diff --check`. Do not treat a plausible reviewer warning as a
defect until it is traced to the actual source and boundary.
