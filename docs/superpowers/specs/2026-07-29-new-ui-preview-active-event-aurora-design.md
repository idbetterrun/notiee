# New UI Preview Active-Event Aurora Design

## Status

Approved design. This document defines an experimental `NewUIPreview` effect only;
it does not change the production Today screen or connect the preview to
`NotieeStore`.

## Goal

Give an in-progress event a calm, low-contrast visual presence in the top Hero
area. The Aurora effect communicates the event's user-selected tag color without
competing with the event title, dashboard content, dock, or capture gestures.

## Scope and Target Classification

- Classification: shared experimental UI work for both Notiee and Notiee+.
- The effect belongs only to `Notiee/Features/Settings/NewUIPreview/`.
- Do not add backend calls, target-specific transport code, persistent settings,
  or production Today behavior.
- Do not add visible copy or localization keys.

## Behavior

### Visibility

- Render Aurora only when `NewUIPreviewHeroContext` is `.activeEvent`.
- For every other Hero state, do not mount or draw the renderer. There is no
  idle, calm, reflection, upcoming-event, or todo Aurora.
- Aurora is visual-only and must use `allowsHitTesting(false)`.

### Placement

- Place Aurora behind the dashboard content in `NewUIPreviewTodayView`'s root
  background `ZStack`.
- Its frame covers the page's top Hero region, including the transparent
  navigation-bar area and Hero card backdrop, at approximately 280 pt high.
- Fade the bottom edge to transparent so it ends at the Hero boundary instead of
  becoming a page-wide background.
- Keep the existing semantic system background beneath it and the Hero content
  above it. Existing dock, menu, scenario switcher, and pull gestures retain
  their current z-order and interaction behavior.

### Color Semantics

- Add optional `auroraColorHex` to `NewUIPreviewHero`.
- The active-event fixture supplies an event-tag color. The initial fixture uses
  the existing Work tag orange (`#FF9500`) to make the mapping easy to inspect.
- A `nil` tag color uses `Color.newUIPreviewAccent` (Notiee green) as the
  fallback.
- The renderer derives three related stops from this one semantic color: a light
  tint, the supplied base color, and a deeper tint. It must not introduce an
  unrelated second tag hue.
- In production Today work, the equivalent input will come from
  `ScheduledEvent.tagID -> EventTag.colorHex`; that integration is explicitly
  outside this preview change.

### Motion and Accessibility

- Port the React Bits Aurora simplex-noise, color-ramp, alpha, and blend logic
  into a Metal fragment shader. Use a full-screen triangle and transparent
  premultiplied-alpha blending.
- Advance the shader at a deliberately slow pace, capped at 30 fps.
- When the view is not active, the app is not foregrounded, or Reduce Motion is
  enabled, pause time advancement. Reduce Motion leaves one stable frame rather
  than removing the active-event color cue.
- If a Metal device or drawable cannot be created, fail closed by drawing
  nothing. The dashboard must remain usable and legible.

## Components

| File | Responsibility |
| --- | --- |
| `NewUIPreviewAuroraView.swift` | SwiftUI wrapper for an `MTKView`; passes visibility, semantic color, frame time, and accessibility state into Metal. |
| `NewUIPreviewAurora.metal` | Full-screen-triangle vertex shader and Aurora fragment shader, including simplex noise and the three-stop color ramp. |
| `NewUIPreviewState.swift` | Supplies the active-event mock's optional `auroraColorHex`; does not read production data. |
| `NewUIPreviewTodayView.swift` | Places the non-interactive, top-clipped Aurora behind dashboard content only for an active-event Hero. |
| `Notiee.xcodeproj/project.pbxproj` | Adds both new shared source files to the Notiee and Notiee+ targets. |

`NewUIPreviewAuroraView` owns render lifecycle decisions. `NewUIPreviewTodayView`
does not own frame timing, Metal resources, or color derivation. The shader only
renders values supplied by its wrapper and has no business-state knowledge.

## Verification

- With an active-event fixture and a tag color, the top Aurora uses that color
  family and moves slowly.
- With an active-event fixture without a tag color, it uses Notiee green.
- For every non-active Hero scenario, no Aurora renderer is visible or running.
- The Aurora ends at the Hero region, preserves Hero text contrast in light and
  dark appearance, and does not cover lower dashboard slots.
- Reduce Motion freezes the Aurora; foreground/background and visibility changes
  pause and resume safely.
- Tap the dock, menu, scenario switcher, Hero controls, and capture gesture area
  to verify the background never intercepts input.
- Build both `Notiee` and `Notiee+` schemes with the required Xcode developer
  directory prefix. Perform visual QA on an iOS 26 device or simulator that
  supports Metal.

## Non-goals

- No React, WebGL, `ogl`, or WebView dependency.
- No production Today renderer, `NotieeStore` wiring, or event-data migration.
- No extra color picker, color persistence, analytics, backend API, or target
  split.
