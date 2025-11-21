# Toast Integration Examples

Practical examples showing how to integrate and use the Toast component in real-world scenarios.

## 1. Basic View Integration

### Simple Button Action

```swift
import SwiftUI

struct SettingsView: View {
  @State private var showSuccessToast = false
  @State private var notificationsEnabled = true

  var body: some View {
    List {
      Toggle("Enable Notifications", isOn: $notificationsEnabled)
        .onChange(of: notificationsEnabled) { _, newValue in
          saveSettings()
          showSuccessToast = true
        }
    }
    .navigationTitle("Settings")
    .toast(
      isPresented: $showSuccessToast,
      config: .success(message: "Settings saved")
    )
  }

  private func saveSettings() {
    UserDefaults.standard.set(notificationsEnabled, forKey: "notifications")
  }
}
```

## 2. Form Submission with Error Handling

```swift
import SwiftUI

struct CreateCategoryView: View {
  @State private var categoryName = ""
  @State private var showToast = false
  @State private var toastConfig: ToastConfig?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Form {
      Section {
        TextField("Category Name", text: $categoryName)
      }

      Section {
        Button("Create Category") {
          createCategory()
        }
        .disabled(categoryName.isEmpty)
      }
    }
    .navigationTitle("New Category")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
    }
    .toast(
      isPresented: $showToast,
      config: toastConfig ?? .success(message: "Created")
    )
  }

  private func createCategory() {
    guard !categoryName.isEmpty else {
      toastConfig = .error(message: "Name cannot be empty")
      showToast = true
      return
    }

    do {
      try saveCategory(name: categoryName)
      toastConfig = .success(message: "Category added")
      showToast = true

      // Dismiss after short delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        dismiss()
      }
    } catch {
      toastConfig = .error(message: "Failed to save")
      showToast = true
    }
  }

  private func saveCategory(name: String) throws {
    // Your save logic here
  }
}
```

## 3. Network Operation with Loading State

```swift
import SwiftUI

struct DataSyncView: View {
  @State private var isSyncing = false
  @State private var showToast = false
  @State private var toastConfig: ToastConfig?

  var body: some View {
    VStack(spacing: 20) {
      if isSyncing {
        ProgressView()
          .progressViewStyle(.circular)
        Text("Syncing...")
          .foregroundStyle(.secondary)
      } else {
        Button("Sync Data") {
          syncData()
        }
      }
    }
    .navigationTitle("Sync")
    .toast(
      isPresented: $showToast,
      config: toastConfig ?? .success(message: "Synced")
    )
  }

  private func syncData() {
    isSyncing = true

    Task {
      do {
        try await performSync()

        await MainActor.run {
          isSyncing = false
          toastConfig = .success(message: "Data synced successfully")
          showToast = true
        }
      } catch {
        await MainActor.run {
          isSyncing = false
          toastConfig = .error(message: "Sync failed")
          showToast = true
        }
      }
    }
  }

  private func performSync() async throws {
    try await Task.sleep(nanoseconds: 2_000_000_000) // Simulate network
    // Your actual sync logic
  }
}
```

## 4. Using Environment with ToastManager (Recommended)

### App Setup

```swift
import SwiftUI

@main
struct KretaApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .overlay {
          ToastOverlay() // Global toast overlay
        }
        .withToast() // Enable environment access
    }
  }
}
```

### View Usage

```swift
import SwiftUI

struct ProfileView: View {
  @Environment(\.showToast) private var showToast
  @State private var username = ""
  @State private var email = ""

  var body: some View {
    Form {
      Section("Profile") {
        TextField("Username", text: $username)
        TextField("Email", text: $email)
      }

      Section {
        Button("Save Changes") {
          saveProfile()
        }
      }
    }
    .navigationTitle("Profile")
  }

  private func saveProfile() {
    // Validate
    guard !username.isEmpty else {
      showToast("Username cannot be empty", type: .error)
      return
    }

    guard isValidEmail(email) else {
      showToast("Invalid email address", type: .warning)
      return
    }

    // Save
    do {
      try performSave()
      showToast("Profile updated", type: .success)
    } catch {
      showToast("Failed to save changes", type: .error)
    }
  }

  private func isValidEmail(_ email: String) -> Bool {
    email.contains("@") && email.contains(".")
  }

  private func performSave() throws {
    // Your save logic
  }
}
```

## 5. List Operations

```swift
import SwiftUI

struct TaskListView: View {
  @Environment(\.showToast) private var showToast
  @State private var tasks: [Task] = []

  var body: some View {
    List {
      ForEach(tasks) { task in
        TaskRow(task: task)
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
              deleteTask(task)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
          .swipeActions(edge: .leading) {
            Button {
              toggleComplete(task)
            } label: {
              Label("Complete", systemImage: "checkmark")
            }
            .tint(.green)
          }
      }
    }
    .navigationTitle("Tasks")
    .toolbar {
      Button {
        addNewTask()
      } label: {
        Image(systemName: "plus")
      }
    }
  }

  private func addNewTask() {
    let newTask = Task(title: "New Task")
    tasks.append(newTask)
    showToast("Task added", type: .success)
  }

  private func deleteTask(_ task: Task) {
    tasks.removeAll { $0.id == task.id }
    showToast("Task deleted", type: .success)
  }

  private func toggleComplete(_ task: Task) {
    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
      tasks[index].isCompleted.toggle()
      if tasks[index].isCompleted {
        showToast("Task completed", type: .success)
      }
    }
  }
}

struct Task: Identifiable {
  let id = UUID()
  var title: String
  var isCompleted = false
}

struct TaskRow: View {
  let task: Task

  var body: some View {
    HStack {
      Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(task.isCompleted ? .green : .secondary)
      Text(task.title)
        .strikethrough(task.isCompleted)
    }
  }
}
```

## 6. Multiple Toast Scenarios

```swift
import SwiftUI

struct FileManagerView: View {
  @Environment(\.showToast) private var showToast
  @State private var files: [File] = []
  @State private var isUploading = false

  var body: some View {
    List {
      ForEach(files) { file in
        FileRow(file: file)
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button {
            uploadFile()
          } label: {
            Label("Upload File", systemImage: "icloud.and.arrow.up")
          }

          Button {
            downloadAll()
          } label: {
            Label("Download All", systemImage: "arrow.down.circle")
          }

          Button(role: .destructive) {
            deleteAll()
          } label: {
            Label("Delete All", systemImage: "trash")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
  }

  private func uploadFile() {
    isUploading = true

    Task {
      do {
        try await performUpload()
        await MainActor.run {
          isUploading = false
          showToast("File uploaded successfully", type: .success)
        }
      } catch {
        await MainActor.run {
          isUploading = false
          showToast("Upload failed. Please try again", type: .error)
        }
      }
    }
  }

  private func downloadAll() {
    guard !files.isEmpty else {
      showToast("No files to download", type: .warning)
      return
    }

    Task {
      do {
        try await performDownload()
        await MainActor.run {
          showToast("All files downloaded", type: .success)
        }
      } catch {
        await MainActor.run {
          showToast("Download failed", type: .error)
        }
      }
    }
  }

  private func deleteAll() {
    let count = files.count
    files.removeAll()
    showToast("\(count) files deleted", type: .success)
  }

  private func performUpload() async throws {
    try await Task.sleep(nanoseconds: 2_000_000_000)
  }

  private func performDownload() async throws {
    try await Task.sleep(nanoseconds: 2_000_000_000)
  }
}

struct File: Identifiable {
  let id = UUID()
  var name: String
  var size: Int64
}

struct FileRow: View {
  let file: File

  var body: some View {
    HStack {
      Image(systemName: "doc.fill")
        .foregroundStyle(.blue)
      VStack(alignment: .leading) {
        Text(file.name)
          .font(.headline)
        Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
```

## 7. Custom Toast Styles for Specific Actions

```swift
import SwiftUI

struct NotificationView: View {
  @Environment(\.showToast) private var showToast

  var body: some View {
    List {
      Button("New Message") {
        // Custom style for messages
        ToastManager.shared.show(
          config: .custom(
            message: "New message from John",
            icon: Image(systemName: "message.fill"),
            color: .blue
          )
        )
      }

      Button("Photo Saved") {
        ToastManager.shared.show(
          config: .custom(
            message: "Photo saved to library",
            icon: Image(systemName: "photo.fill"),
            color: .purple
          )
        )
      }

      Button("Reminder Set") {
        ToastManager.shared.show(
          config: .custom(
            message: "Reminder set for 3 PM",
            icon: Image(systemName: "bell.fill"),
            color: .orange
          )
        )
      }

      Button("Backup Complete") {
        ToastManager.shared.show(
          config: .custom(
            message: "Cloud backup completed",
            icon: Image(systemName: "icloud.and.arrow.up.fill"),
            color: .teal
          )
        )
      }
    }
    .navigationTitle("Custom Toasts")
  }
}
```

## 8. Sequential Toasts with Queue

```swift
import SwiftUI

struct BatchOperationView: View {
  @Environment(\.showToast) private var showToast

  var body: some View {
    VStack(spacing: 20) {
      Button("Process Batch") {
        processBatch()
      }
    }
    .navigationTitle("Batch Operations")
  }

  private func processBatch() {
    let operations = ["Import", "Validate", "Transform", "Export"]

    Task {
      for (index, operation) in operations.enumerated() {
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        await MainActor.run {
          showToast("\(operation) completed (\(index + 1)/\(operations.count))", type: .success)
        }
      }

      try? await Task.sleep(nanoseconds: 1_500_000_000)

      await MainActor.run {
        showToast("All operations completed", type: .custom(
          icon: Image(systemName: "checkmark.seal.fill"),
          color: .green
        ))
      }
    }
  }
}
```

## 9. Conditional Toast Display

```swift
import SwiftUI

struct ConnectionStatusView: View {
  @Environment(\.showToast) private var showToast
  @State private var isConnected = true
  @State private var previousConnectionState = true

  var body: some View {
    VStack {
      Image(systemName: isConnected ? "wifi" : "wifi.slash")
        .font(.system(size: 60))
        .foregroundStyle(isConnected ? .green : .red)

      Text(isConnected ? "Connected" : "Disconnected")
        .font(.headline)

      Button("Toggle Connection") {
        toggleConnection()
      }
      .padding(.top)
    }
    .onChange(of: isConnected) { oldValue, newValue in
      // Only show toast if state actually changed
      if oldValue != newValue {
        if newValue {
          showToast("Connection restored", type: .success)
        } else {
          showToast("Connection lost", type: .warning)
        }
      }
    }
  }

  private func toggleConnection() {
    isConnected.toggle()
  }
}
```

## 10. Integration with Async/Await Operations

```swift
import SwiftUI

struct DataFetchView: View {
  @Environment(\.showToast) private var showToast
  @State private var data: [String] = []
  @State private var isLoading = false

  var body: some View {
    List {
      ForEach(data, id: \.self) { item in
        Text(item)
      }
    }
    .overlay {
      if isLoading {
        ProgressView()
      }
    }
    .refreshable {
      await refreshData()
    }
    .task {
      await loadInitialData()
    }
  }

  private func loadInitialData() async {
    isLoading = true

    do {
      data = try await fetchData()
      isLoading = false
    } catch {
      isLoading = false
      await MainActor.run {
        showToast("Failed to load data", type: .error)
      }
    }
  }

  private func refreshData() async {
    do {
      let newData = try await fetchData()
      data = newData
      await MainActor.run {
        showToast("Data refreshed", type: .success)
      }
    } catch {
      await MainActor.run {
        showToast("Refresh failed", type: .error)
      }
    }
  }

  private func fetchData() async throws -> [String] {
    try await Task.sleep(nanoseconds: 1_000_000_000)
    return ["Item 1", "Item 2", "Item 3"]
  }
}
```

## Best Practices from Examples

1. **Use Environment for Global Access**: Prefer `@Environment(\.showToast)` over managing state in each view
2. **Keep Messages Short**: Aim for under 40 characters when possible
3. **Match Toast Type to Action**: Success for completions, warnings for non-critical issues, errors for failures
4. **Don't Block UI**: Toasts auto-dismiss, don't wait for user interaction
5. **Queue Management**: ToastManager automatically queues multiple toasts
6. **Async Operations**: Always use `await MainActor.run` when showing toasts from background tasks
7. **Conditional Display**: Only show toasts when state actually changes, not on every render

## Common Patterns

### Success Confirmation

```swift
// After save operation
showToast("Changes saved", type: .success)
```

### Error Feedback

```swift
// After failed operation
showToast("Unable to connect", type: .error)
```

### Warning Message

```swift
// Non-critical issue
showToast("Connection unstable", type: .warning)
```

### Custom Notification

```swift
// Special events
ToastManager.shared.show(config: .custom(
  message: "New feature available",
  icon: Image(systemName: "sparkles"),
  color: .purple
))
```

---

These examples demonstrate real-world integration patterns. Choose the approach that best fits your app's architecture and user experience requirements.
