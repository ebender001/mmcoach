package dev.benderapps.mmcoach.models

import java.util.Date

/**
 * Local-only metadata for the Home screen's "Recent Cases" list. Mirrors
 * iOS `Models/RecentCaseRecord.swift` -- the backend has no case-listing
 * Cloud Function, so this stays a small local index refreshed on demand.
 */
data class RecentCaseRecord(
    val id: String,
    val title: String,
    val createdAt: Date,
    val status: CaseStatus,
)
