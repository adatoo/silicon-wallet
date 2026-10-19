import CryptoKit
import Foundation

/// What an Acrylic Wallet file becomes in Silicon Wallet, ready for `VaultSession.importItems`.
/// It holds plaintext, so it lives only in memory and only until the import finishes.
public struct AcrylicImportPlan: Sendable {
    public struct Attachment: Sendable {
        public let entryID: UUID
        public let filename: String
        public let uti: String
        public let contents: Data
    }

    public var groups: [VaultGroup]
    public var entries: [VaultEntry]
    public var attachments: [Attachment]
    /// Values that had no field definition in their group, kept as extra fields.
    public var unlabelledValueCount: Int
    /// Attachment references whose file wasn't in the vault.
    public var missingAttachmentCount: Int

    public var fieldCount: Int { entries.reduce(0) { $0 + $1.values.count + $1.extraFields.count } }
}

/// Maps a decrypted Acrylic Wallet 3.5 vault onto Silicon Wallet's model (DESIGN.md §4, §9).
/// Nothing is dropped: values without a field definition become extra fields.
public enum AcrylicImporter {
    /// One field definition from a group's `defaultheaders` or an entry's `extraheaders`.
    struct Header: Equatable {
        let uuid: String
        let title: String
        let type: Int
        let contentType: Int
    }

    /// Reads and maps a `.wallet` file. Group names already in the vault get " (Acrylic)".
    public static func plan(
        ciphertext: Data, password: String, existingGroupNames: Set<String> = []
    ) throws -> AcrylicImportPlan {
        let reader = try AcrylicWalletReader(ciphertext: ciphertext, password: password)
        return try plan(reader: reader, existingGroupNames: existingGroupNames)
    }

    public static func plan(reader: AcrylicWalletReader, existingGroupNames: Set<String> = []) throws
        -> AcrylicImportPlan
    {
        let acrylicGroups = try reader.groups()
        let acrylicEntries = try reader.entries()
        let filesByUUID = Dictionary(try reader.files().map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

        var takenNames = Set(existingGroupNames.map { $0.lowercased() })
        var groups: [VaultGroup] = []
        var groupIDByUUID: [String: UUID] = [:]
        var fieldsByGroupUUID: [String: [(header: Header, template: FieldTemplate)]] = [:]

        for (order, source) in acrylicGroups.enumerated() {
            let headers = decodeHeaders(source.defaultHeadersArchive)
            let pairs = headers.map { ($0, template(for: $0, groupTitle: source.title)) }
            var name = source.title.isEmpty ? "Imported" : source.title
            if takenNames.contains(name.lowercased()) {
                name = uniqueName("\(name) (Acrylic)", taken: takenNames)
            }
            takenNames.insert(name.lowercased())

            let group = VaultGroup(
                name: name, icon: icon(for: source), fields: pairs.map(\.1), order: order,
                modified: parseDate(source.lastUpdated) ?? .now)
            groups.append(group)
            groupIDByUUID[source.uuid] = group.id
            fieldsByGroupUUID[source.uuid] = pairs
        }

        var entries: [VaultEntry] = []
        var attachments: [AcrylicImportPlan.Attachment] = []
        var unlabelled = 0
        var missing = 0

        for source in acrylicEntries {
            // An entry whose group is missing goes into a catch-all group, made on demand.
            let groupUUID = source.parentGroupUUID ?? ""
            let groupID: UUID
            if let id = groupIDByUUID[groupUUID] {
                groupID = id
            } else {
                let name = uniqueName("Imported", taken: takenNames)
                takenNames.insert(name.lowercased())
                let group = VaultGroup(name: name, icon: "tray", order: groups.count)
                groups.append(group)
                groupIDByUUID[groupUUID] = group.id
                fieldsByGroupUUID[groupUUID] = []
                groupID = group.id
            }

            var remaining = source.fieldValues
            var values: [UUID: String] = [:]
            for (header, template) in fieldsByGroupUUID[groupUUID] ?? [] {
                if let value = remaining.removeValue(forKey: header.uuid), !value.isEmpty {
                    values[template.id] = value
                }
            }

            var extraFields: [CustomField] = []
            for header in decodeHeaders(source.extraHeadersArchive) {
                let template = template(for: header)
                let value = remaining.removeValue(forKey: header.uuid) ?? ""
                extraFields.append(
                    CustomField(
                        label: template.label, kind: template.kind, isConcealed: template.isConcealed,
                        isMonospaced: template.isMonospaced, value: value))
            }
            for (_, value) in remaining.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
                unlabelled += 1
                extraFields.append(CustomField(label: "Field", value: value))
            }

            let modified = parseDate(source.lastUpdated) ?? .now
            let entry = VaultEntry(
                groupID: groupID, title: source.title.isEmpty ? "Untitled" : source.title, values: values,
                extraFields: extraFields, notes: source.notes, isFavorite: source.isStarred, created: modified,
                modified: modified)
            entries.append(entry)

            for fileUUID in source.fileUUIDs {
                guard let file = filesByUUID[fileUUID] else {
                    missing += 1
                    continue
                }
                attachments.append(
                    .init(entryID: entry.id, filename: file.name, uti: uti(for: file), contents: file.data))
            }
        }

        return AcrylicImportPlan(
            groups: groups, entries: entries, attachments: attachments, unlabelledValueCount: unlabelled,
            missingAttachmentCount: missing)
    }

    // MARK: - Field definitions

    /// Decodes Wallet's `NSKeyedArchiver` array of field dictionaries (`Type`, `UUID`, `Title`,
    /// `Section`, optionally `Content-Type`). Only Foundation's plist classes may be decoded, so a
    /// hostile file can't instantiate anything else.
    static func decodeHeaders(_ archive: Data?) -> [Header] {
        guard let archive, !archive.isEmpty,
            let object = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [
                    NSArray.self, NSMutableArray.self, NSDictionary.self, NSMutableDictionary.self, NSString.self,
                    NSMutableString.self, NSNumber.self,
                ], from: archive),
            let array = object as? [Any]
        else { return [] }

        return array.compactMap { item in
            guard let dictionary = item as? [String: Any], let uuid = dictionary["UUID"] as? String else { return nil }
            return Header(
                uuid: uuid, title: dictionary["Title"] as? String ?? "",
                type: (dictionary["Type"] as? NSNumber)?.intValue ?? 0,
                contentType: (dictionary["Content-Type"] as? NSNumber)?.intValue ?? 0)
        }
    }

    /// Wallet's field types: 0 text, 1 web address, 2 user name, 3 password; `Content-Type` 1
    /// marks a secure field. Labels that name a secret (PIN, security code, CVV) are concealed too.
    static func template(for header: Header, groupTitle: String = "") -> FieldTemplate {
        let label = header.title.trimmingCharacters(in: .whitespaces)
        let lower = label.lowercased()
        let kind: FieldKind
        switch header.type {
        case 1: kind = .url
        case 3: kind = .password
        default:
            if header.contentType == 1 || lower.contains("password") || lower.contains("passcode") {
                kind = .password
            } else if lower.contains("email") || lower.contains("e-mail") {
                kind = .email
            } else if lower.contains("phone") || lower.contains("mobile") {
                kind = .phone
            } else if lower == "url" || lower.contains("website") || lower.contains("web address") {
                kind = .url
            } else {
                kind = .text
            }
        }
        let words = Set(lower.split { !$0.isLetter }.map(String.init))
        let secretWords: Set = ["pin", "cvv", "cvc", "cv2", "secret", "passphrase", "passcode"]
        let secretPhrases = ["security code", "licence key", "license key", "card number", "account number", "iban"]
        let isCardNumber = groupTitle.lowercased().contains("card") && lower == "number"
        let concealed =
            kind == .password || !words.isDisjoint(with: secretWords) || secretPhrases.contains { lower.contains($0) }
            || isCardNumber
        return FieldTemplate(label: label.isEmpty ? "Field" : label, kind: kind, isConcealed: concealed)
    }

    // MARK: - Helpers

    static func icon(for group: AcrylicGroup) -> String {
        let title = group.title.lowercased()
        if title.contains("card") { return "creditcard" }
        if title.contains("web") || title.contains("login") || title.contains("password") { return "person.badge.key" }
        if title.contains("serial") || title.contains("licen") || title.contains("software") { return "key" }
        if title.contains("bank") || title.contains("account") { return "building.columns" }
        if title.contains("note") { return "note.text" }
        if title.contains("wi-fi") || title.contains("wifi") || title.contains("network") { return "wifi" }
        switch group.icon {
        case "1": return "key"
        case "2": return "person.badge.key"
        case "3": return "creditcard"
        default: return "folder"
        }
    }

    static func uti(for file: AcrylicFile) -> String {
        let ext = (file.type?.isEmpty == false ? file.type! : (file.name as NSString).pathExtension).lowercased()
        switch ext {
        case "png": return "public.png"
        case "jpg", "jpeg": return "public.jpeg"
        case "gif": return "com.compuserve.gif"
        case "heic": return "public.heic"
        case "pdf": return "com.adobe.pdf"
        case "txt": return "public.plain-text"
        case "rtf": return "public.rtf"
        default: return "public.data"
        }
    }

    static func uniqueName(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    /// Wallet writes dates as `yyyy-MM-dd HH:mm:ss Z`.
    static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text)
    }
}
