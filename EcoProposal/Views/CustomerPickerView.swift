import SwiftUI
import SwiftData

struct CustomerPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var searchText = ""
    @State private var showingNewCustomer = false

    var onSelect: (Customer) -> Void

    private var filtered: [Customer] {
        guard !searchText.isEmpty else { return customers }
        let q = searchText.lowercased()
        return customers.filter {
            $0.name.lowercased().contains(q) ||
            ($0.companyName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if customers.isEmpty {
                    ContentUnavailableView(
                        "No Customers Yet",
                        systemImage: "person.crop.circle",
                        description: Text("Tap + to add your first customer.")
                    )
                } else {
                    ForEach(filtered) { customer in
                        Button {
                            onSelect(customer)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(customer.displayName)
                                    .foregroundStyle(.primary)
                                if let email = customer.email, !email.isEmpty {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search customers")
            .navigationTitle("Choose Customer")
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewCustomer = true
                    } label: {
                        Label("New Customer", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewCustomer) {
                NewCustomerSheet { newCustomer in
                    modelContext.insert(newCustomer)
                    try? modelContext.save()
                    onSelect(newCustomer)
                    dismiss()
                }
            }
        }
    }
}

private struct NewCustomerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var company: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var street: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var zip: String = ""

    var onCreate: (Customer) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField("Full name", text: $name)
                    TextField("Company (optional)", text: $company)
                    TextField("Email", text: $email)
                        .iosKeyboardType(.email)
                        .iosNoAutocapitalization()
                    TextField("Phone", text: $phone)
                        .iosKeyboardType(.phone)
                }
                Section("Billing address") {
                    TextField("Street", text: $street)
                    TextField("City", text: $city)
                    HStack {
                        TextField("State", text: $state)
                            .iosUppercaseAutocapitalization()
                            .frame(maxWidth: 120)
                        TextField("ZIP", text: $zip)
                            .iosKeyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("New Customer")
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let customer = Customer(
                            name: name.trimmingCharacters(in: .whitespaces),
                            companyName: company.isEmpty ? nil : company,
                            email: email.isEmpty ? nil : email,
                            phone: phone.isEmpty ? nil : phone,
                            street: street.isEmpty ? nil : street,
                            city: city.isEmpty ? nil : city,
                            state: state.isEmpty ? nil : state,
                            zip: zip.isEmpty ? nil : zip
                        )
                        onCreate(customer)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && company.isEmpty)
                }
            }
        }
    }
}
