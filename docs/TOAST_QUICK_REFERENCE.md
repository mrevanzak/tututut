# Toast Component - Quick Reference

## 🚀 Quick Start

### 1. App Setup (One Time)

```swift
@main
struct MyApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .overlay { ToastOverlay() }
        .withToast()
    }
  }
}
```

### 2. Use in Any View

```swift
struct MyView: View {
  @Environment(\.showToast) private var showToast

  var body: some View {
    Button("Save") {
      // Your logic
      showToast("Saved successfully", type: .success)
    }
  }
}
```

## 📋 Toast Types

| Type       | Usage                      | Visual                           |
| ---------- | -------------------------- | -------------------------------- |
| `.success` | Confirmations, completions | 🟢 Green circle, white checkmark |
| `.warning` | Non-critical issues        | 🟠 Orange circle, dark triangle  |
| `.error`   | Failures, errors           | 🔴 Red circle, white X           |
| `.custom`  | Special notifications      | Custom color & icon              |

## 💡 Common Patterns

### Success Confirmation

```swift
showToast("Changes saved", type: .success)
```

### Error Feedback

```swift
showToast("Unable to connect", type: .error)
```

### Warning Message

```swift
showToast("Connection unstable", type: .warning)
```

### Custom Style

```swift
ToastManager.shared.show(config: .custom(
  message: "Photo saved",
  icon: Image(systemName: "photo.fill"),
  color: .purple
))
```

### Custom Duration

```swift
showToast("Long message here", type: .success)
// Default 2 seconds

ToastManager.shared.show(
  config: .success(message: "Longer display", duration: 4.0)
)
```

## 🎯 Best Practices

### ✅ DO

- Keep messages under 50 characters
- Use semantic types (success/warning/error)
- Let toasts auto-dismiss
- Use for non-critical notifications

### ❌ DON'T

- Don't use for critical errors needing user action
- Don't stack multiple toasts rapidly
- Don't override system colors
- Don't use for information requiring interaction

## 🎨 Animation Details

```
Start: Small circle from top (0.35s)
  ↓
Expand: Circle → Pill with text (0.5s)
  ↓
Display: Visible state (2s default)
  ↓
Dismiss: Move up + fade out (0.35s)
```

**Total Time**: ~3.2 seconds (default)

## 📐 Layout Specs

- **Height**: 44pt fixed
- **Width**: Dynamic (content-based)
- **Icon**: 28pt circle
- **Padding**: 20pt horizontal, 8pt vertical
- **Position**: Top center, 8pt below safe area

## ♿️ Accessibility

- **VoiceOver**: Auto-announces with semantic prefix
- **Contrast**: WCAG AA compliant (4.5:1+)
- **Dynamic Type**: Fully supported
- **Reduced Motion**: Respects system setting

## 🔧 API Reference

### Environment Method

```swift
@Environment(\.showToast) private var showToast

showToast(
  _ message: String,
  type: ToastStyle = .success
)
```

### Direct Manager Method

```swift
ToastManager.shared.show(
  config: ToastConfig
)

ToastManager.shared.show(
  message: String,
  style: ToastStyle,
  duration: TimeInterval = 2.0
)
```

### View Modifier

```swift
.toast(
  isPresented: Binding<Bool>,
  config: ToastConfig
)
```

## 📱 Testing

Open **ToastView.swift** and run any preview:

- Interactive demo with buttons
- Light mode preview
- Dark mode preview
- Individual toasts side-by-side

## 🐛 Troubleshooting

| Issue                | Solution                                            |
| -------------------- | --------------------------------------------------- |
| Toast doesn't appear | Add `ToastOverlay()` and `.withToast()` to app root |
| Wrong colors         | Component auto-adapts, don't override               |
| Text clipped         | Keep messages concise (3 line max)                  |
| Animation choppy     | Test on device, not simulator                       |

## 📚 Documentation

- **Full Guide**: `TOAST_COMPONENT_GUIDE.md`
- **Examples**: `TOAST_INTEGRATION_EXAMPLES.md`
- **Summary**: `TOAST_IMPLEMENTATION_SUMMARY.md`

## 🎬 Example Flows

### Form Submission

```swift
private func saveForm() {
  guard isValid else {
    showToast("Please fill all fields", type: .warning)
    return
  }

  do {
    try save()
    showToast("Form saved", type: .success)
    dismiss()
  } catch {
    showToast("Failed to save", type: .error)
  }
}
```

### Network Operation

```swift
Task {
  do {
    try await fetchData()
    await MainActor.run {
      showToast("Data updated", type: .success)
    }
  } catch {
    await MainActor.run {
      showToast("Update failed", type: .error)
    }
  }
}
```

### List Actions

```swift
.swipeActions {
  Button(role: .destructive) {
    deleteItem(item)
    showToast("Item deleted", type: .success)
  } label: {
    Label("Delete", systemImage: "trash")
  }
}
```

---

**Version**: 1.0  
**Updated**: November 2025  
**Platform**: iOS 16.0+
