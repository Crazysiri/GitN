# GitX UI Rules

- For top chrome, keep three layers distinct:
  - Navigation/tab bar: darkest chrome color.
  - Selected tab: same color as the repo toolbar below, so they visually merge.
  - Repo toolbar: slightly lighter than the navigation/tab bar.
- When changing toolbar colors, always update the selected tab color in the same change.
- Prefer dynamic AppKit colors or a shared dynamic palette over hard-coded dark-only RGB values.
- Default theme behavior should follow the macOS system appearance unless the user explicitly chooses a fixed light/dark mode.
- Avoid adding new `isDark` branches for general SwiftUI surfaces when a system-driven color or dynamic palette can be used.
- Keep tab width content-driven first, then compress only when horizontal space is insufficient.
- Top chrome buttons and the primary action buttons on the New Tab page should have a visible hover state; keep that feedback consistent with the shared button/chrome language.
