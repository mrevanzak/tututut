//
//  FeedbackBoardView.swift
//  kreta
//

import SwiftUI

struct FeedbackBoardScreen: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.showToast) private var showToast

    @State private var feedbackStore = FeedbackStore()
    @State private var sortOption: SortOption = .votes
    @State private var sortOrder: SortOrder = .descending
    @State private var newFeedbackText = ""
    @State private var isSubmitting = false
    @FocusState private var isInputFocused: Bool

    // Auto dynamic height
    @State private var calculatedHeight: CGFloat = 44
    private let maxTextEditorHeight: CGFloat = 80

    var sortedItems: [FeedbackItem] {
        let sorted = feedbackStore.feedbackItems.sorted { (a, b) -> Bool in
            let comparison: Bool
            switch sortOption {
            case .votes: comparison = a.voteCount < b.voteCount
            case .date: comparison = a.createdAt < b.createdAt
            }
            return sortOrder == .ascending ? comparison : !comparison
        }
        return sorted
    }

    var body: some View {
        VStack(spacing: 0) {

            // Header
            headerTitleSection
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            // List
            List {
                ForEach(sortedItems) { item in
                    FeedbackCard(item: item, hasVoted: feedbackStore.hasUserVoted(feedbackId: item.id))
                      .listRowSeparator(.hidden, edges: .all)
                      .listRowBackground(Color.clear)
                      .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .listStyle(.plain)
            .overlay {
                if sortedItems.isEmpty && !isInputFocused {
                    ContentUnavailableView(
                        "Belum ada masukkan",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Ayo tulis ide/masukkan kamu disini!")
                    )
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    sortMenu
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }

            // Input Section (patched)
            inputSection
        }
        .environment(feedbackStore)
        .presentationBackground(.ultraThickMaterial)
        .onChange(of: newFeedbackText) { _ in
            recalcHeight()
        }
    }

    // MARK: - Header
    private var headerTitleSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Feedback Board")
                    .font(.title2.weight(.bold))

                Text("Bagikan ide dan voting masukkan dari pengguna lain")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            closeButton
        }
    }
    
    private var closeButton: some View {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(.textSecondary, .primary)
          .font(.largeTitle)
      }
      .foregroundStyle(.backgroundSecondary)
      .glassEffect(.regular.tint(.backgroundSecondary))
    }

    // MARK: - Sort Menu
    private var sortMenu: some View {
        Menu {
            Section("Sort by") {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            sortOption = option
                        }
                    } label: {
                        HStack {
                            Text(option.displayName)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section("Order") {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            sortOrder = order
                        }
                    } label: {
                        HStack {
                            Text(order.displayName)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                Text("\(sortOption.displayName) • \(sortOrder == .ascending ? "↑" : "↓")")
                    .font(.subheadline)
            }
            .foregroundStyle(.primary)
        }
    }


    // MARK: - Input Section
    private var inputSection: some View {
        VStack {
            HStack(alignment: .bottom) {

                // 🔥 This entire container is now height-hugging
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(
                            color: colorScheme == .dark ? .black.opacity(0.4) : .black.opacity(0.05),
                            radius: 8, y: 4
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(.separator), lineWidth: 1)
                        )

                    HStack(alignment: .bottom, spacing: 8) {

                        // TextEditor (auto expand)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $newFeedbackText)
                                .frame(minHeight: calculatedHeight, maxHeight: calculatedHeight)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .focused($isInputFocused)

                            if newFeedbackText.isEmpty {
                                Text("Tulis ide/masukkan kamu disini…")
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 18)
                            }
                        }

                        // Send Button
                        Button {
                            submitFeedback()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.headline)
                                .bold()
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    isSubmitDisabled ? Color(.systemGray4) : Color.highlight,
                                    in: Circle()
                                )
                        }
                        .disabled(isSubmitDisabled)
                        .padding(.trailing, 10)
                        .padding(.bottom, 6)
                    }
                }
                .frame(
                    minHeight: calculatedHeight + 20,
                    maxHeight: calculatedHeight + 20
                )
                .animation(.easeInOut, value: calculatedHeight)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var isSubmitDisabled: Bool {
        newFeedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Submit
    private func submitFeedback() {
        guard !isSubmitting else { return }

        isSubmitting = true
        let trimmed = newFeedbackText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await feedbackStore.submitFeedback(description: trimmed, email: nil)
                DispatchQueue.main.async {
                    showToast("Feedback berhasil dikirim!", type: .success)
                    newFeedbackText = ""
                    calculatedHeight = 44
                    isInputFocused = false
                    isSubmitting = false
                }
            } catch {
                DispatchQueue.main.async {
                    showToast("Gagal mengirim: \(error.localizedDescription)", type: .error)
                    isSubmitting = false
                }
            }
        }
    }

    // MARK: - Dynamic Height Calculator
    private func recalcHeight() {
        let width = UIScreen.main.bounds.width - 32 - 60
        let size = CGSize(width: width, height: .infinity)

        let bounding = newFeedbackText.boundingRect(
            with: size,
            options: .usesLineFragmentOrigin,
            attributes: [.font: UIFont.systemFont(ofSize: 17)],
            context: nil
        )

        let desired = max(44, bounding.height + 28)
        calculatedHeight = min(desired, maxTextEditorHeight)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        view(for: .feedback)
    }
}

