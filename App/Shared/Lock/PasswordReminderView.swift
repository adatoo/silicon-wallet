import SwiftUI

/// Asks, every so often, whether the master password is still remembered (DESIGN.md §5). With
/// Face ID or Touch ID it may go unused for months, but it's the only way into the vault on a new
/// device. It can be skipped, and a wrong attempt changes nothing.
struct PasswordReminderView: View {
    @Environment(LockController.self) private var lock
    @State private var password = ""
    @State private var isWorking = false
    @State private var wrong = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Form {
            Section {
                SecureField("Master password", text: $password)
                    .textContentType(.password)
                    .focused($isFocused)
                    .onSubmit(check)
                if wrong {
                    Text("That's not it. Try again.").font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Do you still remember your master password?")
            } footer: {
                Text(
                    "It's the only way into your vault on a new device, and it can't be recovered. Type it to check, or skip this for a week."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Check Your Password")
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 240)
        #else
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .interactiveDismissDisabled()
        .onAppear { isFocused = true }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Not Now") { lock.snoozePasswordReminder() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check", action: check).disabled(password.isEmpty)
                }
            }
        }
    }

    private func check() {
        guard !password.isEmpty, !isWorking else { return }
        isWorking = true
        wrong = false
        Task {
            if !(await lock.confirmPassword(password)) {
                wrong = true
                password = ""
                isFocused = true
            }
            isWorking = false
        }
    }
}
