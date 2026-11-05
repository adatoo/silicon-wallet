// TestFlight through the App Store Connect API (docs/app-store-release.md, B2).
//
//   swift scripts/testflight.swift setup  <group name> <tester email>
//   swift scripts/testflight.swift notes  <version> <build number> <changelog path>
//   swift scripts/testflight.swift status
//   swift scripts/testflight.swift changelog <version> <changelog path>
//
// Run it through `task testflight:*`. It reads the API key from ASC_KEY_PATH, ASC_KEY_ID and
// ASC_ISSUER_ID, signs a short-lived token with CryptoKit, and prints nothing secret.

import CryptoKit
import Foundation

let bundleID = "com.datoos.silicon-wallet"
let notesLocale = "en-GB"
/// TestFlight's limit for What to Test.
let notesLimit = 4000

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func environment(_ name: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        throw Failure("\(name) isn't set. Set ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID, locally in .env.local.")
    }
    return value
}

// MARK: - The API

struct Client {
    let token: String

    init() throws {
        let keyID = try environment("ASC_KEY_ID")
        let issuer = try environment("ASC_ISSUER_ID")
        let pem = try String(contentsOfFile: try environment("ASC_KEY_PATH"), encoding: .utf8)
        let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let now = Int(Date().timeIntervalSince1970)
        let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"])
        let claims = try JSONSerialization.data(
            withJSONObject: ["iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"])
        let signingInput = base64URL(header) + "." + base64URL(claims)
        let signature = try key.signature(for: Data(signingInput.utf8)).rawRepresentation
        token = signingInput + "." + base64URL(signature)
    }

    /// Sends a request and returns the decoded JSON, or nil for an empty response.
    @discardableResult
    func send(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil)
        async throws -> [String: Any]?
    {
        var components = URLComponents(string: "https://api.appstoreconnect.apple.com" + path)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, method: method, path: path, detail: Self.errorDetail(data))
        }
        guard !data.isEmpty else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The `data` array of a GET.
    func list(_ path: String, query: [String: String] = [:]) async throws -> [[String: Any]] {
        try await send("GET", path, query: query)?["data"] as? [[String: Any]] ?? []
    }

    private static func errorDetail(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errors = json["errors"] as? [[String: Any]]
        else { return String(data: data.prefix(300), encoding: .utf8) ?? "" }
        return errors.compactMap { $0["detail"] as? String ?? $0["title"] as? String }.joined(separator: "; ")
    }
}

struct APIError: Error, CustomStringConvertible {
    let status: Int
    let method: String
    let path: String
    let detail: String
    var description: String { "\(method) \(path) failed (\(status)): \(detail)" }
}

func id(_ object: [String: Any]) -> String { object["id"] as? String ?? "" }
func attributes(_ object: [String: Any]) -> [String: Any] { object["attributes"] as? [String: Any] ?? [:] }

func appID(_ client: Client) async throws -> String {
    guard let app = try await client.list("/v1/apps", query: ["filter[bundleId]": bundleID]).first else {
        throw Failure("No app with bundle ID \(bundleID) in App Store Connect.")
    }
    return id(app)
}

// MARK: - setup

/// Makes sure an internal group exists that gets every build, with `email` in it. Changes only
/// what's missing, so running it again does nothing.
func setup(groupName: String, email: String) async throws {
    let client = try Client()
    let app = try await appID(client)

    let groups = try await client.list("/v1/apps/\(app)/betaGroups", query: ["limit": "200"])
    var group = groups.first { attributes($0)["name"] as? String == groupName }
    if let existing = group {
        guard attributes(existing)["isInternalGroup"] as? Bool == true else {
            throw Failure("\"\(groupName)\" is an external group. Choose another name for the internal group.")
        }
        if attributes(existing)["hasAccessToAllBuilds"] as? Bool != true {
            try await client.send(
                "PATCH", "/v1/betaGroups/\(id(existing))",
                body: [
                    "data": [
                        "type": "betaGroups", "id": id(existing), "attributes": ["hasAccessToAllBuilds": true],
                    ]
                ])
            print("Group \"\(groupName)\" now gets every build.")
        } else {
            print("Group \"\(groupName)\" exists and gets every build.")
        }
    } else {
        group = try await client.send(
            "POST", "/v1/betaGroups",
            body: [
                "data": [
                    "type": "betaGroups",
                    "attributes": ["name": groupName, "isInternalGroup": true, "hasAccessToAllBuilds": true],
                    "relationships": ["app": ["data": ["type": "apps", "id": app]]],
                ]
            ])?["data"] as? [String: Any]
        print("Created internal group \"\(groupName)\", which gets every build.")
    }
    guard let groupID = group.map(id), !groupID.isEmpty else { throw Failure("The group has no ID.") }

    let members = try await client.list(
        "/v1/betaGroups/\(groupID)/betaTesters", query: ["limit": "200"])
    if members.contains(where: { (attributes($0)["email"] as? String)?.lowercased() == email.lowercased() }) {
        print("\(email) is already a tester in it.")
        return
    }
    // Creating the tester with the group, rather than linking an existing tester record, is what
    // works for an internal group: a record from another app's group can't be assigned to it.
    do {
        try await client.send(
            "POST", "/v1/betaTesters",
            body: [
                "data": [
                    "type": "betaTesters", "attributes": ["email": email],
                    "relationships": ["betaGroups": ["data": [["type": "betaGroups", "id": groupID]]]],
                ]
            ])
    } catch let error as APIError where error.status == 409 || error.status == 422 {
        throw Failure(
            "\(email) couldn't be added: \(error.detail). An internal tester must be a user in App Store Connect ▸ Users and Access, with the same email."
        )
    }
    print("Added \(email). Install TestFlight on your devices and accept the invitation it sends.")
}

// MARK: - notes

/// The CHANGELOG section for `version`, as plain text for What to Test.
func changelogNotes(version: String, path: String) throws -> String {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    var lines: [String] = []
    var inSection = false
    for line in text.components(separatedBy: "\n") {
        if line.hasPrefix("## [") {
            if inSection { break }
            inSection = line.hasPrefix("## [\(version)]")
            continue
        }
        guard inSection else { continue }
        if line.hasPrefix("### ") {
            lines.append(String(line.dropFirst(4)) + ":")
        } else {
            lines.append(line)
        }
    }
    guard inSection || !lines.isEmpty else { throw Failure("CHANGELOG.md has no section for \(version).") }
    // Join wrapped bullet lines, so each change is one line.
    var joined: [String] = []
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("  "), let last = joined.last, last.hasPrefix("- ") {
            joined[joined.count - 1] = last + " " + trimmed
        } else {
            joined.append(trimmed)
        }
    }
    let notes = joined.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let full = "Version \(version)\n\n\(notes)"
    return full.count <= notesLimit ? full : String(full.prefix(notesLimit - 1)) + "…"
}

/// Waits for the builds of `version` (build `number`) to finish processing, then sets their
/// What to Test from the changelog.
func notes(version: String, number: String, changelog: String) async throws {
    let whatsNew = try changelogNotes(version: version, path: changelog)
    let client = try Client()
    let app = try await appID(client)

    // Uploads take a few minutes to appear and process.
    let deadline = Date().addingTimeInterval(45 * 60)
    var builds: [[String: Any]] = []
    while true {
        builds = try await client.list(
            "/v1/builds",
            query: [
                "filter[app]": app, "filter[version]": number, "filter[preReleaseVersion.version]": version,
                "limit": "10",
            ])
        let states = builds.map { attributes($0)["processingState"] as? String ?? "?" }
        if !builds.isEmpty, states.allSatisfy({ $0 != "PROCESSING" }) { break }
        guard Date() < deadline else { throw Failure("Build \(number) of \(version) is still processing after 45 minutes.") }
        print("Waiting for build \(number) of \(version): \(states.isEmpty ? "not there yet" : states.joined(separator: ", "))")
        try await Task.sleep(for: .seconds(60))
    }

    for build in builds {
        let state = attributes(build)["processingState"] as? String ?? "?"
        guard state == "VALID" else {
            print("Build \(id(build)) is \(state), so it has no notes.")
            continue
        }
        let localizations = try await client.list("/v1/builds/\(id(build))/betaBuildLocalizations")
        if let existing = localizations.first(where: { attributes($0)["locale"] as? String == notesLocale }) {
            try await client.send(
                "PATCH", "/v1/betaBuildLocalizations/\(id(existing))",
                body: [
                    "data": [
                        "type": "betaBuildLocalizations", "id": id(existing), "attributes": ["whatsNew": whatsNew],
                    ]
                ])
        } else {
            try await client.send(
                "POST", "/v1/betaBuildLocalizations",
                body: [
                    "data": [
                        "type": "betaBuildLocalizations",
                        "attributes": ["whatsNew": whatsNew, "locale": notesLocale],
                        "relationships": ["build": ["data": ["type": "builds", "id": id(build)]]],
                    ]
                ])
        }
    }
    print("Set What to Test on \(builds.count) build(s) of \(version) (\(number)).")
}

// MARK: - status

/// An upload date in local time; App Store Connect gives it in Pacific time.
func uploaded(_ text: String?) -> String {
    guard let text, let date = ISO8601DateFormatter().date(from: text) else { return text ?? "?" }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}

/// The latest builds, newest first.
func status() async throws {
    let client = try Client()
    let app = try await appID(client)
    guard let json = try await client.send(
        "GET", "/v1/builds",
        query: ["filter[app]": app, "sort": "-uploadedDate", "limit": "12", "include": "preReleaseVersion"])
    else { return }
    let versions = Dictionary(
        uniqueKeysWithValues: (json["included"] as? [[String: Any]] ?? []).map { (id($0), attributes($0)) })
    for build in json["data"] as? [[String: Any]] ?? [] {
        let a = attributes(build)
        let versionID =
            ((build["relationships"] as? [String: Any])?["preReleaseVersion"] as? [String: Any])?["data"]
            as? [String: Any]
        let version = versionID.flatMap { versions[id($0)] }
        let platform = version?["platform"] as? String ?? "?"
        let line = [
            (version?["version"] as? String ?? "?").padding(toLength: 8, withPad: " ", startingAt: 0),
            "(\(a["version"] as? String ?? "?"))".padding(toLength: 7, withPad: " ", startingAt: 0),
            platform.padding(toLength: 7, withPad: " ", startingAt: 0),
            (a["processingState"] as? String ?? "?").padding(toLength: 10, withPad: " ", startingAt: 0),
            uploaded(a["uploadedDate"] as? String),
            (a["expired"] as? Bool == true) ? "expired" : "",
        ]
        print(line.joined(separator: " "))
    }
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case "setup" where arguments.count == 3:
        try await setup(groupName: arguments[1], email: arguments[2])
    case "notes" where arguments.count == 4:
        try await notes(version: arguments[1], number: arguments[2], changelog: arguments[3])
    case "status" where arguments.count == 1:
        try await status()
    case "changelog" where arguments.count == 3:
        print(try changelogNotes(version: arguments[1], path: arguments[2]))
    default:
        throw Failure("Usage: testflight.swift setup <group> <email> | notes <version> <build> <changelog> | status | changelog <version> <changelog>")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
