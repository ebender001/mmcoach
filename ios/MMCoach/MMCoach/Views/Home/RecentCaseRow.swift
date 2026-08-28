//
//  RecentCaseRow.swift
//  MMCoach
//

import SwiftUI

/// One recent case, styled as a tappable card. Status uses neutral tones
/// (not red) since "In Progress" is a routine, expected state here -- not
/// a warning.
struct RecentCaseRow: View {
    let record: RecentCaseSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(record.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(Color.slateText)
            }

            Spacer(minLength: 8)

            statusBadge
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var statusBadge: some View {
        StatusBadge(text: statusText, tint: statusTint, textColor: statusTextColor)
    }

    private var statusText: String {
        switch record.status {
        case .collectingInformation: "In Progress"
        case .readyToFinalize: "Ready"
        case .completed: "Completed"
        }
    }

    // Deliberately neutral (grays + a touch of teal) -- these are routine
    // workflow states, not alerts, so nothing here reads as red/urgent.
    private var statusTint: Color {
        switch record.status {
        case .collectingInformation: Color(.systemGray5)
        case .readyToFinalize: Color.mutedTeal.opacity(0.16)
        case .completed: Color(.systemGray5)
        }
    }

    private var statusTextColor: Color {
        switch record.status {
        case .collectingInformation: Color.slateText
        case .readyToFinalize: Color.mutedTeal
        case .completed: Color.slateText
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        RecentCaseRow(record: RecentCaseSummary(id: "1", title: "68-year-old man, CABG x3, postoperative bleeding", createdAt: Date(), status: .collectingInformation))
        RecentCaseRow(record: RecentCaseSummary(id: "2", title: "54-year-old woman, laparoscopic cholecystectomy, bile leak", createdAt: Date(), status: .readyToFinalize))
        RecentCaseRow(record: RecentCaseSummary(id: "3", title: "72-year-old man, AAA repair, postoperative MI", createdAt: Date(), status: .completed))
    }
    .padding()
    .background(Color.warmBackground)
}
