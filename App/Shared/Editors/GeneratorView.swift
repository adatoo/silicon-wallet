import SiliconWalletKit
import SwiftUI

/// Makes a random password or passphrase (DESIGN.md §5) and hands it back with `onUse`.
struct GeneratorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case characters = "Characters"
        case words = "Words"
        var id: String { rawValue }
    }

    let onUse: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("generatorMode") private var mode = Mode.characters
    @State private var characters = PasswordGenerator.CharacterOptions()
    @State private var words = PasswordGenerator.WordOptions()
    @State private var result = ""

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(alignment: .top) {
                    Text(result)
                        .font(.title3.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Generated password")
                    Button("Regenerate", systemImage: "arrow.clockwise", action: generate)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .keyboardShortcut("r")
                }
                LabeledContent("Strength", value: "\(Int(entropy)) bits")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            switch mode {
            case .characters:
                Section("Options") {
                    Stepper(
                        "Length: \(characters.length)", value: $characters.length,
                        in: PasswordGenerator.CharacterOptions.lengthRange)
                    Toggle("Lowercase (a–z)", isOn: $characters.lowercase)
                    Toggle("Uppercase (A–Z)", isOn: $characters.uppercase)
                    Toggle("Digits (0–9)", isOn: $characters.digits)
                    Toggle("Symbols (!#$…)", isOn: $characters.symbols)
                    Toggle("Avoid look-alikes (0 O 1 l I)", isOn: $characters.avoidAmbiguous)
                }
            case .words:
                Section("Options") {
                    Stepper(
                        "Words: \(words.wordCount)", value: $words.wordCount,
                        in: PasswordGenerator.WordOptions.wordCountRange)
                    Picker("Separator", selection: $words.separator) {
                        Text("Hyphen").tag("-")
                        Text("Space").tag(" ")
                        Text("Full stop").tag(".")
                        Text("Underscore").tag("_")
                    }
                    Toggle("Capitalise words", isOn: $words.capitalise)
                    Toggle("Add a digit", isOn: $words.includeDigit)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Generate Password")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #else
            .frame(minWidth: 420, minHeight: 440)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Use Password") {
                    onUse(result)
                    dismiss()
                }
            }
        }
        .onAppear(perform: generate)
        .onChange(of: mode) { generate() }
        .onChange(of: characters) { generate() }
        .onChange(of: words) { generate() }
    }

    private var entropy: Double {
        mode == .characters ? PasswordGenerator.entropy(characters) : PasswordGenerator.entropy(words)
    }

    private func generate() {
        result = mode == .characters ? PasswordGenerator.password(characters) : PasswordGenerator.passphrase(words)
    }
}
