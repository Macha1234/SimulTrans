# SimulTrans interface

SimulTrans uses native macOS glass surfaces, cool neutral colors and a blue primary action. Green denotes an active session; red is reserved for stopping or errors.

## Shared components

`SimulTransTheme.swift` owns the palette, typography and shared components. Use `STWindowBackdrop` for a window, `STGlassSurface` for a grouped surface, `STBrandMark` for the product identity and `STIconBadge` for supporting section icons. Use `STButtonStyle` with primary, secondary, quiet or destructive variants. Existing localized text and application state remain the source of UI content.

## Layout and typography

Use system rounded fonts for product titles, system fonts for controls and body text, and monospaced fonts for timestamps and compact measurements. Main cards use 20-point continuous corners, smaller controls use 10–13 points, and content generally uses 20–24-point insets. Group related controls with 8–16-point spacing. Keep a single prominent session action in each control surface.

## Glass and appearance

Window materials sample behind the window. Cards use a restrained translucent material, a subtle highlight edge and a soft shadow. Window backgrounds must stay clear and nonopaque so the material can work. Appearance follows the existing system/light/dark preference. Captions remain dark with high-contrast white text for use over video. Opacity affects the caption background, not the text.

## Interaction and accessibility

Shared buttons provide hover, pressed and disabled states. Respect Reduce Motion for shared button animations and Reduce Transparency for shared window/card surfaces. Preserve native keyboard operation, permission prompts, destructive-action confirmation, caption text selection and manual scroll/follow behavior. Icon-only caption actions have accessible labels. Localized screens use flexible layouts or scrollable content to avoid clipping.
