package dev.benderapps.mmcoach.models

/**
 * The surgical specialty a case belongs to. Mirrors iOS
 * `Models/Specialty.swift` -- the dictionary/abbreviation lists there feed
 * the on-device speech correction service, which the Android client will
 * need its own equivalent of once dictation is ported.
 */
enum class Specialty(val id: String, val displayName: String, val dictionaryResourceName: String) {
    CARDIOTHORACIC("cardiothoracic", "Cardiothoracic Surgery", "CVTMedicalDictionary"),
    GENERAL_SURGERY("generalSurgery", "General Surgery", "GenSurgMedicalDictionary"),
}
