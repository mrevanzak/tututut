//
//  ToastWindow.swift
//  kreta
//
//  Created by AI Assistant
//  Window-based toast system that renders on top of all content including sheets
//

import SwiftUI
import UIKit

// MARK: - Toast Window

/// Custom UIWindow that hosts toast notifications above all other content
final class ToastWindow: UIWindow {
  private var hostingController: UIHostingController<ToastContainerView>?

  override init(windowScene: UIWindowScene) {
    super.init(windowScene: windowScene)
    setupWindow()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupWindow() {
    // Configure window to sit above everything
    windowLevel = .alert + 1
    backgroundColor = .clear
    isUserInteractionEnabled = true

    // Create hosting controller with toast container
    let containerView = ToastContainerView()
    let controller = UIHostingController(rootView: containerView)
    controller.view.backgroundColor = .clear

    // Make hosting controller the root
    rootViewController = controller
    hostingController = controller

    // Make window visible but allow touches to pass through
    isHidden = false
  }

  // MARK: - Hit Testing

  /// Allow touches to pass through to underlying windows when not hitting toast
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let hitView = super.hitTest(point, with: event) else { return nil }

    // If the hit view is the root view or hosting controller's view,
    // it means we didn't hit the actual toast content, so pass through
    if hitView == rootViewController?.view || hitView == self {
      return nil
    }

    return hitView
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // Check if point is inside any interactive toast content
    guard let rootView = rootViewController?.view else { return false }
    let convertedPoint = convert(point, to: rootView)
    return rootView.hitTest(convertedPoint, with: event) != nil
      && rootView.hitTest(convertedPoint, with: event) != rootView
  }
}

// MARK: - Toast Container View

struct ToastContainerView: View {
  @State private var manager = ToastManager.shared

  var body: some View {
    ZStack(alignment: .top) {
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)

      if let toast = manager.currentToast {
        ToastView(
          config: toast,
          isPresented: Binding(
            get: { true },
            set: { if !$0 { Task { await manager.dismiss() } } }
          )
        )
        .zIndex(1000)
        .transition(
          .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
          )
        )
        .onTapGesture {
          Task {
            await manager.dismiss()
          }
        }
      }
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: manager.currentToast)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .allowsHitTesting(manager.currentToast != nil)
  }
}

// MARK: - Toast Window Manager

/// Manages the lifecycle of the toast window
@MainActor
final class ToastWindowManager {
  static let shared = ToastWindowManager()

  private var toastWindow: ToastWindow?

  private init() {}

  /// Initialize the toast window with the given window scene
  func setup(in windowScene: UIWindowScene) {
    guard toastWindow == nil else { return }

    let window = ToastWindow(windowScene: windowScene)
    toastWindow = window
  }

  /// Get the current toast window
  var window: ToastWindow? {
    toastWindow
  }
}
