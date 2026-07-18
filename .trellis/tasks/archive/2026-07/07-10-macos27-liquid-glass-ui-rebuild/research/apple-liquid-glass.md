# Apple Liquid Glass Research

Primary Apple sources:

- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- https://developer.apple.com/documentation/SwiftUI/ConcentricRectangle
- https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)
- https://developer.apple.com/videos/play/wwdc2026/289/
- https://developer.apple.com/videos/play/wwdc2026/8120/

## Planning Consequences

- Standard SwiftUI/AppKit navigation and toolbar components receive current Liquid Glass behavior automatically; custom backgrounds should be removed before adding custom effects.
- Glass is a functional control/navigation layer over content, not a universal translucent background for every data row.
- Custom interactive glass belongs on a small number of meaningful selectors/actions and should use `GlassEffectContainer` for related elements.
- macOS 27 refines sidebars, toolbar grouping, scroll-edge behavior, interactive glass response, and concentric corner treatment.
- `ConcentricRectangle` and container shapes can replace hand-maintained radius arithmetic where nested custom glass controls need to align with their container.
- `sharedBackgroundVisibility(_:)` can prevent inappropriate toolbar items from inheriting a shared glass background.
- Reduced Transparency and Reduced Motion are first-class acceptance states, not optional fallbacks.

## Local SDK Verification

- The installed SDK reports `MacOSX26.5.sdk` even though the package deployment target is macOS 27; SwiftPM may continue to emit the existing target-version warning.
- The local SwiftUI/SwiftUICore interfaces contain `glassEffect`, `GlassEffectContainer`, `GlassButtonStyle`, `sharedBackgroundVisibility(_:)`, and `ConcentricRectangle` for macOS, so the planned source can be compiled with the installed toolchain.
