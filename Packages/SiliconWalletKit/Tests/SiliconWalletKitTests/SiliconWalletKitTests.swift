import Testing

@testable import SiliconWalletKit

@Test func formatVersionIsSet() {
    #expect(SiliconWalletKit.formatVersion == 1)
}
