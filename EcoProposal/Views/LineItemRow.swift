import SwiftUI

struct LineItemRow: View {
    @Bindable var item: LineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Description", text: $item.descriptionText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Qty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Qty", value: $item.quantity, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .iosKeyboardType(.decimal)
                        .frame(width: 70)
                }
                unitPicker
                Spacer()
            }

            HStack {
                HStack(spacing: 4) {
                    Text("Unit $")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Unit price", value: $item.unitPrice, format: .currency(code: "USD"))
                        .textFieldStyle(.roundedBorder)
                        .iosKeyboardType(.decimal)
                        .frame(width: 130)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(item.lineTotal, format: .currency(code: "USD"))
                        .font(.body.monospacedDigit())
                        .fontWeight(.medium)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Menu-style picker of preset units + a Custom text-input option.
    private var unitPicker: some View {
        HStack(spacing: 4) {
            Text("Unit")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(LineItem.presetUnits, id: \.self) { u in
                    Button(u) { item.unit = u }
                }
                Divider()
                Button("Custom…") {
                    // Leaves the current value editable inline via the text field below.
                }
            } label: {
                HStack(spacing: 4) {
                    Text(item.unit.isEmpty ? "—" : item.unit)
                        .font(.body)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(white: 0.85), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            // Also expose an inline text field so a rep can type any unit directly.
            TextField("unit", text: $item.unit)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
        }
    }
}
