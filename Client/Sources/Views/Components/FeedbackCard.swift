//
//  FeedbackCard.swift
//  kreta
//
//  Liquid glass styled feedback card with vote button and status
//

import SwiftUI

struct FeedbackCard: View {
  @Environment(FeedbackStore.self) private var store
  @Environment(\.colorScheme) private var colorScheme

  @State private var hasVoted = false
  @State private var localVoteCount: Int
  @State private var isVoting = false
  @State private var buttonScale: CGFloat = 1.0
  @State private var iconRotation: Double = 0

  let item: FeedbackItem

  init(item: FeedbackItem, hasVoted: Bool) {
    self.item = item
    _hasVoted = State(initialValue: hasVoted)
    _localVoteCount = State(initialValue: item.voteCount)
  }

  var body: some View {
    VStack(spacing: 16) {
      HStack(alignment: .top, spacing: 16) {
        // Title
          Text(item.description)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)


        Spacer()

        voteButton
      }

      HStack {
        // Timestamp
        Text(item.relativeTime)
          .font(.caption)
          .foregroundStyle(.sublime)

        Spacer()

        statusTag
      }
    }
    .padding(20)
    .background(cardGlassBackground)
    .clipShape(cardShape)
    .overlay(
      cardShape
        .stroke(cardBorderGradient, lineWidth: 1)
    )
    .shadow(color: cardShadowColor, radius: 8, x: 0, y: 4)
  }

  private var statusTag: some View {
    Text(item.status.rawValue.capitalized)
      .font(.caption2)
      .fontWeight(.semibold)
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color(hex: item.statusColor), in: RoundedRectangle(cornerRadius: 8))
  }

  private var voteButton: some View {
    Button {
      handleVoteToggle()
    } label: {
      VStack(spacing: 8) {
        Image(systemName: hasVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
          .foregroundStyle(hasVoted ? .highlight : .sublime)
          .rotationEffect(.degrees(iconRotation))
          .animation(.spring(response: 0.4, dampingFraction: 0.6), value: iconRotation)
        Text("\(localVoteCount)")
          .font(.caption2)
          .foregroundStyle(.sublime)
      }
      .frame(width: 44, height: 44)
    }
    .scaleEffect(buttonScale)
    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: buttonScale)
    .disabled(isVoting)
  }

  private func handleVoteToggle() {
    guard !isVoting else { return }

    // Trigger tap animation
    buttonScale = 0.85
    iconRotation = hasVoted ? -15 : 15

    // Reset animations after a brief delay
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
      buttonScale = 1.0
      iconRotation = 0
    }

    // Optimistic update
    isVoting = true
    let previousHasVoted = hasVoted
    let previousVoteCount = localVoteCount

    if hasVoted {
      hasVoted = false
      localVoteCount = max(0, localVoteCount - 1)
    } else {
      hasVoted = true
      localVoteCount += 1
    }

    // Actual vote
    Task {
      do {
        let result = try await store.toggleVote(feedbackId: item.id)
        // Only update if result differs (shouldn't happen but safety net)
        hasVoted = result
        if result != previousHasVoted {
          localVoteCount = result ? previousVoteCount + 1 : previousVoteCount - 1
        }
      } catch {
        // Revert optimistic update
        hasVoted = previousHasVoted
        localVoteCount = previousVoteCount
        print("❌ Vote toggle error: \(error)")
      }
      isVoting = false
    }
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 24, style: .continuous)
  }

  private var cardGlassBackground: some View {
    cardShape
      .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.95 : 0.98))
      .background(
        cardShape
          .fill(cardGlassTint)
          .blur(radius: 36)
      )
  }

  private var cardGlassTint: LinearGradient {
    LinearGradient(
      colors: colorScheme == .dark
        ? [
          Color.white.opacity(0.18),
          Color.white.opacity(0.04),
        ]
        : [
          Color.white.opacity(0.8),
          Color.white.opacity(0.45),
        ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var cardBorderGradient: LinearGradient {
    LinearGradient(
      colors: [
        Color.white.opacity(colorScheme == .dark ? 0.35 : 0.6),
        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.25),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var cardShadowColor: Color {
    colorScheme == .dark ? .black.opacity(0.45) : .black.opacity(0.12)
  }
}

#Preview {
  let store = FeedbackStore()
  let item = FeedbackItem(
    id: "1",
    // title: "Add dark mode support",
    description:
      "It would be great to have a dark mode option for users who prefer darker interfaces.",
    status: .pending,
    createdAt: Float(Date().timeIntervalSince1970 - 3600),
    voteCount: 42
  )

  ZStack {
    Color.black.ignoresSafeArea()
    FeedbackCard(item: item, hasVoted: false)
      .padding()
      .environment(store)
  }
}
