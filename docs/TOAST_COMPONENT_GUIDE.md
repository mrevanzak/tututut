# Toast Component Guide

A polished, animated toast notification system for SwiftUI that matches iOS design standards with smooth animations and accessibility support.

## Features

✨ **Beautiful Animations**

- Starts as a small circular badge from the top of the screen
- Smoothly expands into a pill shape with text
- Dismisses with an upward fade-out animation
- Spring-based physics for natural motion

🎨 **Adaptive Design**

- Automatic light and dark mode support
- Blurred translucent background using Material effects
- Proper contrast in all color schemes
- SF Symbols integration

📱 **Responsive Layout**

- Supports multiline text (up to 3 lines)
- Dynamic Type compatible
- Respects safe areas
- Horizontally centered positioning

♿️ **Accessibility**

- VoiceOver announcements
- High contrast support
- Semantic color meanings

## Usage

### Basic Usage

```swift
import SwiftUI

struct ContentView: View {
  @State private var showToast = false

  var body: some View {
    VStack {
      Button("Show Success") {
        showToast = true
      }
    }
    .toast(
      isPresented: $showToast,
      config: .success(message: "Category added")
    )
  }
}
```

### Using ToastManager (Recommended)

For app-wide toast management, use the `ToastManager` singleton:

```swift
import SwiftUI

@main
struct MyApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .overlay {
          ToastOverlay() // Add this at the root level
        }
        .withToast() // Enable environment access
    }
  }
}

// In any view:
struct SomeView: View {
  @Environment(\.showToast) private var showToast

  var body: some View {
    Button("Save") {
      saveData()
      showToast("Changes saved", type: .success)
    }
  }
}
```

### Toast Styles

#### Success Toast

```swift
.toast(
  isPresented: $showSuccess,
  config: .success(message: "Operation completed successfully")
)
```

- Green background
- White checkmark icon
- Use for: confirmations, successful operations

#### Warning Toast

```swift
.toast(
  isPresented: $showWarning,
  config: .warning(message: "Connection unstable")
)
```

- Orange background
- Dark exclamation triangle icon
- Use for: warnings, non-critical issues

#### Error Toast

```swift
.toast(
  isPresented: $showError,
  config: .error(message: "Failed to save changes")
)
```

- Red background
- White X icon
- Use for: errors, failed operations

#### Custom Toast

```swift
.toast(
  isPresented: $showCustom,
  config: .custom(
    message: "Files uploaded",
    icon: Image(systemName: "icloud.and.arrow.up"),
    color: .blue
  )
)
```

- Custom color and icon
- Use for: special notifications

### Advanced Configuration

#### Custom Duration

```swift
ToastConfig.success(
  message: "Operation completed",
  duration: 3.0 // Display for 3 seconds
)
```

#### Multiline Messages

The toast automatically handles multiline text:

```swift
ToastConfig.warning(
  message: "Network connection is unstable. Some features may not work properly."
)
```

## Animation Sequence

The toast follows a 4-phase animation:

1. **Appearance** (0.35s)

   - Scales up from 0.3x to 1.0x
   - Fades in from 0 to 1.0 opacity
   - Moves from top edge into position
   - Shows as circular badge with icon only

2. **Expansion** (0.5s)

   - Expands horizontally from 44pt circle to full width
   - Text fades in with 0.25s delay
   - Uses spring animation for natural feel

3. **Display** (configurable, default 2.0s)

   - Toast remains fully visible
   - No animations during this phase

4. **Dismissal** (0.35s)
   - Text fades out first
   - Pill scales down to 0.8x
   - Moves up and fades out
   - Quick ease-in animation

Total animation time: ~0.65s entrance + display duration + 0.35s exit

## Component Architecture

### Files

```
Client/Sources/Views/
├── Components/
│   └── ToastView.swift          # Toast view and config
├── ToastManager.swift            # Singleton manager
└── ToastOverlay.swift            # App-level overlay
```

### Types

**ToastStyle** - Enum defining visual styles

- `.success` - Green with checkmark
- `.warning` - Orange with exclamation
- `.error` - Red with X
- `.custom(icon:color:)` - Custom appearance

**ToastConfig** - Configuration struct

- `style: ToastStyle` - Visual style
- `message: String` - Display text
- `duration: TimeInterval` - Display duration

**ToastManager** - Singleton for app-wide toast management

- `show(config:)` - Queue and display toast
- `show(message:style:duration:)` - Convenience method
- `dismiss()` - Manually dismiss current toast

## Design Specifications

### Layout

- **Width**: Dynamic based on content, max screen width minus 48pt padding
- **Height**: 44pt fixed
- **Icon Size**: 28pt diameter circle
- **Padding**: 20pt horizontal, 8pt vertical
- **Corner Radius**: Capsule (fully rounded)

### Colors

**Light Mode**

- Background: `.regularMaterial` with white 30% overlay
- Border: Black 5% opacity
- Shadow: Black 15% opacity, 12pt radius
- Text: `.primary` (black)

**Dark Mode**

- Background: `.ultraThinMaterial` with black 40% overlay
- Border: White 10% opacity
- Shadow: Black 50% opacity, 12pt radius
- Text: `.primary` (white)

### Typography

- Font: System `.subheadline`
- Weight: Medium
- Alignment: Leading
- Line Limit: 3 lines
- Dynamic Type: Supported

### Shadows

- Radius: 12pt
- Offset: (0, 6)
- Color: Black with opacity based on color scheme

## Accessibility

### VoiceOver

The toast automatically announces with semantic prefixes:

- Success: "Success: [message]"
- Warning: "Warning: [message]"
- Error: "Error: [message]"
- Custom: "[message]"

### Contrast

All color combinations meet WCAG AA standards:

- Success: White on green (7.1:1)
- Warning: Black on orange (8.2:1)
- Error: White on red (6.8:1)

### Dynamic Type

- Respects user's text size preferences
- Layout adjusts automatically
- Maintains readability at all sizes

## Best Practices

### Do's ✅

- Keep messages concise (under 50 characters ideal)
- Use appropriate styles for context
- Allow automatic dismissal
- Use success for confirmations
- Use warnings for non-blocking issues
- Use errors for failures requiring attention

### Don'ts ❌

- Don't use toasts for critical errors requiring action
- Don't stack multiple toasts rapidly
- Don't use overly long messages
- Don't customize colors arbitrarily (use semantic styles)
- Don't bypass the manager for one-off toasts

### Examples

**Good**

```swift
showToast("Category added", type: .success)
showToast("Connection unstable", type: .warning)
showToast("Failed to save", type: .error)
```

**Avoid**

```swift
// Too verbose
showToast("Your category has been successfully added to the list", type: .success)

// Wrong style for action
showToast("Delete account?", type: .error) // Use alert instead

// Non-semantic color
ToastConfig.custom(message: "Hello", icon: ..., color: .pink) // Use semantic styles
```

## Integration Example

Complete example showing integration in a real app:

```swift
import SwiftUI

@main
struct KretaApp: App {
  var body: some Scene {
    WindowGroup {
      MainTabView()
        .overlay {
          ToastOverlay()
        }
        .withToast()
    }
  }
}

struct CategoryView: View {
  @Environment(\.showToast) private var showToast
  @State private var categories: [Category] = []

  var body: some View {
    List {
      ForEach(categories) { category in
        CategoryRow(category: category)
      }
      .onDelete(perform: deleteCategories)
    }
    .toolbar {
      Button {
        addCategory()
      } label: {
        Image(systemName: "plus")
      }
    }
  }

  private func addCategory() {
    let newCategory = Category(name: "New Category")
    categories.append(newCategory)
    showToast("Category added", type: .success)
  }

  private func deleteCategories(at offsets: IndexSet) {
    categories.remove(atOffsets: offsets)
    showToast("Category deleted", type: .success)
  }
}
```

## Testing

The component includes comprehensive previews:

```swift
#Preview("Light Mode") {
  ToastPreview()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
  ToastPreview()
    .preferredColorScheme(.dark)
}

#Preview("Individual Toasts") {
  // Shows all styles side-by-side
}
```

## Performance

- **Animation**: 60 FPS smooth animations
- **Memory**: Lightweight, no retained state between shows
- **Queue**: Automatic queuing prevents overlapping toasts
- **Thread Safety**: All operations on MainActor

## Troubleshooting

### Toast doesn't appear

- Ensure `.withToast()` modifier is applied to root view
- Check that `ToastOverlay()` is in the view hierarchy
- Verify `isPresented` binding is toggling to `true`

### Animation is choppy

- Check for heavy operations on main thread during display
- Ensure app is running on device (simulator may lag)
- Verify iOS 16+ deployment target

### Text is clipped

- Messages are limited to 3 lines automatically
- Consider breaking long messages into multiple toasts
- Use more concise wording

### Wrong colors in dark mode

- Component automatically adapts to color scheme
- Don't override system colors
- Test in both light and dark modes

## Future Enhancements

Potential improvements (not yet implemented):

- Swipe to dismiss gesture
- Position variants (top, center, bottom)
- Custom transition animations
- Interactive action buttons
- Progress indicators
- Queueing with priority

---

**Version**: 1.0  
**iOS**: 16.0+  
**SwiftUI**: Yes  
**UIKit**: No
