import CryptoKit
import Foundation
import Testing

@testable import SiliconWalletKit

/// Seeded fuzz tests for code that reads untrusted input: sealed values from the store or iCloud,
/// Acrylic Wallet files and their property-list text. Each must throw or return, never crash or
/// hang. The generator is seeded, so a failure reproduces; every value is fake.

/// SplitMix64: small, fast and deterministic, which is all a fuzz test needs.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Data {
    fileprivate static func random(count: Int, using generator: inout SeededGenerator) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    /// A copy with `flips` random bits flipped from `offset` on.
    fileprivate func flippingBits(_ flips: Int, from offset: Int = 0, using generator: inout SeededGenerator) -> Data {
        var copy = self
        guard copy.count > offset else { return copy }
        for _ in 0..<flips {
            let index = copy.startIndex + Int.random(in: offset..<copy.count, using: &generator)
            copy[index] ^= 1 << UInt8.random(in: 0..<8, using: &generator)
        }
        return copy
    }
}

private enum FuzzFixture {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/AcrylicWallet")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }
}

// MARK: - Sealed values

@Test func randomTruncatedAndFlippedEnvelopesNeverOpen() throws {
    var generator = SeededGenerator(state: 0x5157_A11E)
    let key = SymmetricKey(size: .bits256)
    let id = UUID()
    let sealed = try RecordSealer.seal(Data("fake record payload".utf8), recordID: id, key: key)

    for round in 0..<500 {
        let input: Data
        switch round % 4 {
        case 0: input = .random(count: Int.random(in: 0...96, using: &generator), using: &generator)
        case 1: input = sealed.prefix(Int.random(in: 0..<sealed.count, using: &generator))
        case 2: input = sealed.flippingBits(Int.random(in: 1...4, using: &generator), using: &generator)
        default: input = sealed + .random(count: Int.random(in: 1...16, using: &generator), using: &generator)
        }
        #expect(throws: CryptoError.self) { try RecordSealer.open(input, recordID: id, key: key) }
    }
}

// MARK: - Acrylic Wallet files

@Test func randomHeadersEitherGiveAValidPageSizeOrThrow() {
    var generator = SeededGenerator(state: 0xACE5_0001)
    for _ in 0..<2_000 {
        let header = [UInt8](Data.random(count: Int.random(in: 0...600, using: &generator), using: &generator))
        do {
            let pageSize = try AcrylicWalletFile.pageSize(ofHeader: header)
            #expect(pageSize >= 512 && pageSize <= 65_536 && pageSize & (pageSize - 1) == 0)
        } catch {
            #expect(error is AcrylicWalletError)
        }
    }
}

@Test func randomFilesAreRejected() {
    var generator = SeededGenerator(state: 0xACE5_0002)
    for _ in 0..<300 {
        let file = Data.random(count: 512 * Int.random(in: 0...8, using: &generator), using: &generator)
        #expect(throws: AcrylicWalletError.self) { try AcrylicWalletReader(ciphertext: file, password: "fakepass") }
    }
}

@Test func truncatedWalletFilesAreRejected() throws {
    var generator = SeededGenerator(state: 0xACE5_0003)
    let file = try FuzzFixture.data("a.wallet")
    for _ in 0..<100 {
        let cut = file.prefix(Int.random(in: 0..<file.count, using: &generator))
        #expect(throws: AcrylicWalletError.self) { try AcrylicWalletReader(ciphertext: cut, password: "fakepass") }
    }
}

/// Damaged pages decrypt to damaged SQLite. The reader must reject it or read what survives;
/// whatever it returns, mapping it must not crash either.
@Test func damagedWalletPagesAreRejectedOrReadSafely() throws {
    var generator = SeededGenerator(state: 0xACE5_0004)
    let file = try FuzzFixture.data("g.wallet")
    for _ in 0..<150 {
        // Leave the plaintext header bytes alone, so the damage reaches SQLite.
        let damaged = file.flippingBits(Int.random(in: 1...32, using: &generator), from: 24, using: &generator)
        do {
            let reader = try AcrylicWalletReader(ciphertext: damaged, password: "fakepass")
            _ = try? AcrylicImporter.plan(reader: reader)
        } catch {
            #expect(error is AcrylicWalletError)
        }
    }
}

@Test func randomPropertyListTextNeverCrashesTheParser() {
    var generator = SeededGenerator(state: 0x9715_7000)
    let alphabet = Array("{}()=;,\"\\ \n\tabcXYZ019-_é💳")
    let samples = [
        #"{ "A" = "B"; "C" = "D \" E"; }"#, #"( "x", "y" )"#, #"{ files = ( "F1", "F2" ); }"#,
    ]
    for round in 0..<2_000 {
        let text: String
        if round % 3 == 0 {
            let base = samples[round % samples.count]
            text = String(base.prefix(Int.random(in: 0...base.count, using: &generator)))
        } else {
            text = String(
                (0..<Int.random(in: 0...80, using: &generator)).map { _ in alphabet.randomElement(using: &generator)! })
        }
        _ = AcrylicPropertyListText.parseFlatStringDictionary(text)
        _ = AcrylicPropertyListText.quotedStrings(afterEqualsIn: text)
    }
}
