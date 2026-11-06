import SiliconWalletKit
import SwiftUI

/// The card as it was read, for the person to check and correct before using it (ADR-0009).
/// Each line read has a box, tinted by the field it gave; choosing a box uses it for another
/// field. The image is only in memory and goes when this view does.
struct CardScanReview: View {
    /// The image the boxes are drawn over: the straightened card, or the photo as it came.
    let image: CGImage
    @Binding var lines: [RecognisedLine]
    @Binding var card: ScannedCard
    @State private var choosing: RecognisedLine?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        ForEach(lines) { line in
                            LineBox(line: line, size: proxy.size) { choosing = line }
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
                .frame(maxHeight: 320)
                .frame(maxWidth: .infinity)
            Text(
                lines.isEmpty
                    ? "No text was found on the card." : "Choose any text on the card to use it for a different field."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                // Every field with a value, whichever side was scanned: a box chosen for a field
                // that side doesn't usually give still shows here.
                ForEach(CardField.allCases, id: \.self) { field in
                    if let value = card[field] {
                        row(field, value)
                    }
                }
            }
        }
        .confirmationDialog(
            choosing.map { "Use “\($0.text)” as…" } ?? "", isPresented: isChoosing, titleVisibility: .visible,
            presenting: choosing
        ) { line in
            ForEach(CardField.allCases, id: \.self) { field in
                if CardTextParser.value(for: field, fromLine: line.text) != nil {
                    Button(field.name) { assign(line, to: field) }
                }
            }
            if line.field != nil {
                Button("Don't Use", role: .destructive) { clear(line.field!) }
            }
        }
    }

    /// The field's name over its value, so a long number keeps the row's width; a card number's
    /// scheme sits at the end of the name's line.
    private func row(_ field: CardField, _ value: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(field.colour).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(field.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if field == .number, let scheme = PaymentCard.scheme(for: value) {
                        CardSchemeBadge(scheme: scheme)
                    }
                }
                Text(value)
                    .fontDesign(field == .cardholder ? nil : .monospaced)
                    .textSelection(.enabled)
            }
            Button("Clear \(field.name)", systemImage: "xmark.circle.fill") { clear(field) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }

    private var isChoosing: Binding<Bool> {
        Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } })
    }

    private func assign(_ line: RecognisedLine, to field: CardField) {
        guard let value = CardTextParser.value(for: field, fromLine: line.text) else { return }
        card[field] = value
        for index in lines.indices where lines[index].field == field { lines[index].field = nil }
        if let index = lines.firstIndex(where: { $0.id == line.id }) { lines[index].field = field }
    }

    private func clear(_ field: CardField) {
        card[field] = nil
        for index in lines.indices where lines[index].field == field { lines[index].field = nil }
    }
}

/// A box over one line of text: tinted and labelled when it gave a field, faint otherwise.
struct LineBox: View {
    let line: RecognisedLine
    let size: CGSize
    var action: (() -> Void)?
    /// The colour of a box that gave no field: grey on a photo, white over the camera.
    var neutral: Color = .gray

    var body: some View {
        let rect = CGRect(
            x: line.box.minX * size.width - 3, y: line.box.minY * size.height - 3,
            width: line.box.width * size.width + 6, height: line.box.height * size.height + 6)
        let colour = line.field?.colour ?? neutral
        let shape = RoundedRectangle(cornerRadius: 4)
        shape
            .fill(colour.opacity(line.field == nil ? 0.08 : 0.18))
            .stroke(colour.opacity(line.field == nil ? 0.7 : 1), lineWidth: line.field == nil ? 1 : 2)
            .overlay(alignment: .topLeading) {
                if let field = line.field {
                    Text(field.shortName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .background(colour, in: .rect(cornerRadius: 3))
                        .fixedSize()
                        // Over the box's top edge, clear of the line above.
                        .offset(x: 4, y: -9)
                }
            }
            .contentShape(shape)
            .onTapGesture { action?() }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .accessibilityElement()
            .accessibilityLabel(line.field.map { "\($0.name): \(line.text)" } ?? line.text)
            .accessibilityAddTraits(action == nil ? [] : .isButton)
            .allowsHitTesting(action != nil)
    }
}

extension CardField {
    var name: String {
        switch self {
        case .number: "Card Number"
        case .validFrom: "Valid From"
        case .expiry: "Expiry"
        case .cardholder: "Cardholder"
        case .securityCode: "Security Code"
        }
    }

    var shortName: String {
        switch self {
        case .number: "Number"
        case .validFrom: "From"
        case .expiry: "Expiry"
        case .cardholder: "Name"
        case .securityCode: "Code"
        }
    }

    var colour: Color {
        switch self {
        case .number: .blue
        case .validFrom: .teal
        case .expiry: .orange
        case .cardholder: .green
        case .securityCode: .purple
        }
    }
}
