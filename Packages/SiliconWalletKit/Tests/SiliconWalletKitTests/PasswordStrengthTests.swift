import Testing

@testable import SiliconWalletKit

@Test(arguments: [
    ("", PasswordStrength.Rating.veryWeak),
    ("password", .veryWeak),
    ("aaaaaaaaaaaa", .veryWeak),
    ("abcdefgh", .veryWeak),
    ("fakepass", .weak),
    ("fakepass12", .fair),
    ("Fake-pass-12", .good),
    ("correct horse battery staple", .strong),
    ("x7#Kp2!vQ9@mZr4&", .strong),
])
func passwordStrengthRatings(password: String, expected: PasswordStrength.Rating) {
    #expect(PasswordStrength(password).rating == expected, "\(password): \(PasswordStrength(password).bits) bits")
}

@Test func longerIsStronger() {
    #expect(PasswordStrength("fake-pass-word").bits > PasswordStrength("fake-pass").bits)
}
