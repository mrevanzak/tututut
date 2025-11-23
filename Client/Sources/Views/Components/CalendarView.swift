//
//  CalendarView.swift
//  kreta
//
//  Created by AI Assistant
//

import SwiftUI
import UIKit

struct CalendarView: View {
  @Binding var selectedDate: Date
  let onDateSelected: (Date) -> Void
  let onBack: () -> Void
  
  @State private var temporarySelectedDate: Date?
  
  var body: some View {
    ZStack(alignment: .bottom) {
      VStack(spacing: 0) {
        // Back button
        HStack {
          Button {
            onBack()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "chevron.left")
                .font(.subheadline.weight(.semibold))
              Text("Kembali")
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.highlight)
          }
          .padding(.horizontal)
          .padding(.top, 8)
          
          Spacer()
        }
        
        // UICalendarView wrapper
        UICalendarViewRepresentable(
          selectedDate: $temporarySelectedDate,
          initialDate: selectedDate,
          insets: .init(top: 0, leading: 16, bottom: 16, trailing: 16)
        )
        .padding(.bottom, 100) // Space for floating button
      }
      
      // Floating confirmation button with gradient blur
      VStack(spacing: 0) {
        Spacer()
        
        Button {
          if let date = temporarySelectedDate {
            onDateSelected(date)
          }
        } label: {
          Text("Pilih Tanggal")
            .font(.headline)
            .foregroundStyle(temporarySelectedDate != nil ? .lessDark : .sublime)
            .frame(maxWidth: .infinity)
            .padding()
            .background(temporarySelectedDate != nil ? .highlight : .inactiveButton)
            .cornerRadius(1000)
        }
        .disabled(temporarySelectedDate == nil)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(
          LinearGradient(
            colors: [
              Color.backgroundPrimary.opacity(0),
              Color.backgroundPrimary.opacity(0.7),
              Color.backgroundPrimary.opacity(0.9),
              Color.backgroundPrimary,
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        )
      }
    }
    .padding(.top, 56)
    .onAppear {
      temporarySelectedDate = selectedDate
    }
  }
}

// MARK: - UICalendarView Representable

struct UICalendarViewRepresentable: UIViewRepresentable {
  @Binding var selectedDate: Date?
  let initialDate: Date
  var insets: NSDirectionalEdgeInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)

  func makeCoordinator() -> Coordinator {
    Coordinator(selectedDate: $selectedDate)
  }

  func makeUIView(context: Context) -> UIView {
    let container = UIView()
    container.backgroundColor = .clear
    container.directionalLayoutMargins = insets

    let calendarView = UICalendarView()
    calendarView.translatesAutoresizingMaskIntoConstraints = false
    calendarView.calendar = .current
    calendarView.locale = Locale(identifier: "id_ID")
    calendarView.fontDesign = .rounded
    
    // Customize tint color for chevrons and selected date
    calendarView.tintColor = UIColor(Color.highlight)

    container.addSubview(calendarView)
    NSLayoutConstraint.activate([
      calendarView.topAnchor.constraint(equalTo: container.layoutMarginsGuide.topAnchor),
      calendarView.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
      calendarView.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
      calendarView.bottomAnchor.constraint(equalTo: container.layoutMarginsGuide.bottomAnchor),
    ])

    // Range + selection
    let today = Calendar.current.startOfDay(for: Date())
    calendarView.availableDateRange = DateInterval(
      start: today,
      end: Calendar.current.date(byAdding: .year, value: 1, to: today) ?? today
    )
    let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
    calendarView.selectionBehavior = selection
    selection.selectedDate = Calendar.current.dateComponents([.year, .month, .day], from: initialDate)

    // Keep a reference if you need it later in updateUIView
    context.coordinator.calendarView = calendarView

    return container
  }

  func updateUIView(_ container: UIView, context: Context) {
    container.directionalLayoutMargins = insets

    if let selectedDate,
       let selection = context.coordinator.calendarView?.selectionBehavior as? UICalendarSelectionSingleDate {
      let comps = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
      selection.selectedDate = comps
    }
  }

  class Coordinator: NSObject, UICalendarSelectionSingleDateDelegate {
    @Binding var selectedDate: Date?
    weak var calendarView: UICalendarView?

    init(selectedDate: Binding<Date?>) {
      _selectedDate = selectedDate
    }

    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate comps: DateComponents?) {
      guard let comps, let date = Calendar.current.date(from: comps) else {
        selectedDate = nil
        return
      }
      selectedDate = date
    }

    func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate comps: DateComponents?) -> Bool {
      guard let comps, let date = Calendar.current.date(from: comps) else { return false }
      let today = Calendar.current.startOfDay(for: Date())
      return date >= today
    }
  }
}


// MARK: - Preview

#Preview {
  @Previewable @State var selectedDate = Date()
  
  CalendarView(
    selectedDate: $selectedDate,
    onDateSelected: { date in
      print("Selected date: \(date)")
    },
    onBack: {
      print("Back tapped")
    }
  )
  .background(.backgroundPrimary)
}
