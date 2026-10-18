import SiliconWalletKit
import SwiftUI

/// First run: choose the master password that protects the new vault.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockController.self) private var lock
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var movingFromAcrylic = false
    @FocusState private var focus: Field?

    private enum Field { case password, confirmation }

    static let minimumLength = 8

    private var problem: String? {
        if password.count < Self.minimumLength { return "Use at least \(Self.minimumLength) characters." }
        if confirmation.isEmpty { return "Type the password again to confirm it." }
        if password != confirmation { return "The passwords don't match." }
        return nil
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Welcome to Silicon Wallet")
                    .font(.largeTitle.bold())
                Text(
                    "Choose a master password. It encrypts everything in your vault, and it can't be recovered if you forget it."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                SecureField("Master password", text: $password)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .password)
                    .onSubmit { focus = .confirmation }
                SecureField("Confirm master password", text: $confirmation)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .confirmation)
                    .onSubmit(create)
                PasswordStrengthView(password: password)
                Toggle("I'm moving from Acrylic Wallet", isOn: $movingFromAcrylic)
                    .padding(.top, 4)
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

            Text(problem ?? " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(problem == nil)

            Button(action: create) {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Create Vault").frame(minWidth: 160)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(problem != nil || isWorking)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(maxWidth: 520)
        .onAppear { focus = .password }
    }

    private func create() {
        guard problem == nil, !isWorking, let session = model.session else { return }
        isWorking = true
        Task {
            do {
                try await session.createVault(password: password, starterGroups: !movingFromAcrylic)
                lock.didUnlockWithPassword()
                if movingFromAcrylic { model.isImportingAcrylic = true }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
            isWorking = false
        }
    }
}
