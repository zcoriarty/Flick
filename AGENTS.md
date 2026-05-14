# Codex Instructions

## Project Context

Flick is an iOS app. Treat this repository as an iOS 26+ codebase and prefer current Apple platform patterns that are supported by the project's active Xcode and SDK.

## Coding Guidelines

- Use modern iOS 26+ Swift and SwiftUI best practices. Prefer native framework capabilities and current platform APIs over compatibility shims or older patterns when the deployment target and SDK support them.
- Keep views small and focused. Break large SwiftUI views into dedicated subviews before a file becomes difficult to scan, and put meaningful reusable subviews in their own files.
- Match the existing folder structure when adding files:
  - Feature-specific screens and subviews belong under their feature folder in `Flick/Views`.
  - Shared view components belong in `Flick/Views/Shared`.
  - Cross-feature styling primitives belong in `Flick/DesignSystem`.
  - Shared non-UI helpers belong in the appropriate common area, such as `Flick/Utilities`, `Flick/Services`, `Flick/Models`, or another existing shared module.
- Share code when it is genuinely reusable across features. Keep shared code in an obvious common location and name it so reuse intent is clear.
- Keep code that is only for one view close to that view. If a helper, subview, formatter, or computed property should not be reused elsewhere, keep it in that view's file and mark it `private`.
- Do not create custom view modifiers unless they remove meaningful duplication, improve readability across multiple call sites, or match an existing project pattern. Prefer direct SwiftUI composition for one-off styling.
- Preserve the existing app architecture and naming conventions. Avoid broad refactors unless they are necessary for the requested change.
- Add focused tests when changing logic, persistence, scheduling, services, or other behavior where regressions are likely. UI-only changes should be verified in the simulator when practical.
