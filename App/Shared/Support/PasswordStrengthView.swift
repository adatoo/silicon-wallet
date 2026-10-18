import SiliconWalletKit
import SwiftUI

/// A five-step meter for `PasswordStrength`.
struct PasswordStrengthView: View {
    let password: String

    var body: some View {
        let strength = PasswordStrength(password)
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(PasswordStrength.Rating.allCases, id: \.self) { step in
                    Capsule()
                        .fill(
                            step <= strength.rating && !password.isEmpty
                                ? color(strength.rating) : .secondary.opacity(0.25)
                        )
                        .frame(height: 4)
                }
            }
            Text(password.isEmpty ? " " : strength.rating.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Password strength")
        .accessibilityValue(password.isEmpty ? "None" : strength.rating.label)
    }

    private func color(_ rating: PasswordStrength.Rating) -> Color {
        switch rating {
        case .veryWeak: .red
        case .weak: .orange
        case .fair: .yellow
        case .good: .green
        case .strong: .mint
        }
    }
}
