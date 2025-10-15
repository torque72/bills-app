import SwiftUI

struct BillFormView: View {
    enum CompletionAction {
        case cancel
        case save(EditableBill)
    }

    @State private var form: EditableBill
    @State private var amountText: String
    let onComplete: (CompletionAction) -> Void

    init(form: EditableBill, onComplete: @escaping (CompletionAction) -> Void) {
        _form = State(initialValue: form)
        _amountText = State(initialValue: form.amount == 0 ? "" : String(format: "%.2f", form.amount))
        self.onComplete = onComplete
    }

    var body: some View {
        Form {
            if form.isNew {
                Section("Identifier") {
                    TextField("Optional custom ID", text: $form.customID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }
            } else if let id = form.originalID {
                Section("Identifier") {
                    Text(id)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                TextField("Name", text: $form.name)
                Stepper(value: $form.dueDay, in: 1...31) {
                    Text("Due day: \(form.dueDay)")
                }
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                TextField("Notes", text: $form.notes, axis: .vertical)
                    .lineLimit(1...3)
            }
        }
        .navigationTitle(form.isNew ? "Add bill" : "Edit bill")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onComplete(.cancel) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    commitChanges()
                }
                .disabled(!isFormValid)
            }
        }
    }

    private var isFormValid: Bool {
        !form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Double(amountText) != nil
    }

    private func commitChanges() {
        guard let amount = Double(amountText) else { return }
        form.amount = amount
        onComplete(.save(form))
    }
}
