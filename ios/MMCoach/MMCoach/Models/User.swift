//
//  User.swift
//  MMCoach
//
//  The app's Parse User type. `ParseUser` already covers
//  username/email/password/authData/emailVerified; the only MVP-specific
//  addition is `appleUserIdentifier`, the stable id that ties repeat Sign
//  in with Apple sign-ins back to this account (Apple only guarantees
//  name/email on the *first* authorization for a given app, so that
//  identifier -- not the email -- is what repeat sign-ins are matched on).
//

import Foundation
import ParseSwift

struct User: ParseUser {
    var objectId: String?
    var createdAt: Date?
    var updatedAt: Date?
    var ACL: ParseACL?
    var originalData: Data?

    var username: String?
    var email: String?
    var emailVerified: Bool?
    var password: String?
    var authData: [String: [String: String]?]?

    var appleUserIdentifier: String?
}
