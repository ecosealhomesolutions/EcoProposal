import SwiftUI
import SwiftData

/// Edit an existing customer's contact + billing address in-place.
/// Bound directly to the model — all edits persist on save.
struct EditCustomerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var customer: Customer

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField("Full name", text: $customer.name)
                    TextField("Company (optional)", text: Binding(
                        get: { customer.companyName ?? "" },
                        set: { customer.companyName = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Email", text: Binding(
                        get: { customer.email ?? "" },
                        set: { customer.email = $0.isEmpty ? nil : $0 }
                    ))
                    .iosKeyboardType(.email)
                    .iosNoAutocapitalization()
                    TextField("Phone", text: Binding(
                        get: { customer.phone ?? "" },
                        set: { customer.phone = $0.isEmpty ? nil : $0 }
                    ))
                    .iosKeyboardType(.phone)
                }
                Section("Billing address") {
                    TextField("Street", text: Binding(
                        get: { customer.street ?? "" },
                        set: { customer.street = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("City", text: Binding(
                        get: { customer.city ?? "" },
                        set: { customer.city = $0.isEmpty ? nil : $0 }
                    ))
                    HStack {
                        TextField("State", text: Binding(
                            get: { customer.state ?? "" },
                            set: { customer.state = $0.isEmpty ? nil : $0 }
                        ))
                        .iosUppercaseAutocapitalization()
                        .frame(maxWidth: 120)
                        TextField("ZIP", text: Binding(
                            get: { customer.zip ?? "" },
                            set: { customer.zip = $0.isEmpty ? nil : $0 }
                        ))
                        .iosKeyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("Edit Customer")
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        customer.updatedAt = Date()
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
