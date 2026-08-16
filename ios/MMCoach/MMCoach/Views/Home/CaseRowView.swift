//
//  CaseRowView.swift
//  MMCoach
//

import SwiftUI

struct CaseRowView: View {
    let record: RecentCaseRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.body)
                    .lineLimit(2)
                Text(record.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(statusColor)
    }

    private var statusText: String {
        switch record.status {
        case .collectingInformation: "In Progress"
        case .readyToFinalize: "Ready"
        case .completed: "Completed"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .collectingInformation: .orange
        case .readyToFinalize: .blue
        case .completed: .secondary
        }
    }
}

#Preview {
    List {
        CaseRowView(record: RecentCaseRecord(id: "1", title: "68-year-old man, CABG x3, postoperative bleeding", createdAt: Date(), status: .collectingInformation))
        CaseRowView(record: RecentCaseRecord(id: "2", title: "54-year-old woman, laparoscopic cholecystectomy, bile leak", createdAt: Date(), status: .readyToFinalize))
        CaseRowView(record: RecentCaseRecord(id: "3", title: "72-year-old man, AAA repair, postoperative MI", createdAt: Date(), status: .completed))
    }
}
