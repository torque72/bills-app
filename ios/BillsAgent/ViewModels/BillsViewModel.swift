import Foundation

@MainActor
final class BillsViewModel: ObservableObject {
    @Published var bills: [Bill] = []
    @Published var isLoading = false
    @Published var searchText: String = ""
    @Published var alert: ErrorInfo?
    @Published var editingBill: EditableBill?

    let api: BillsAPI
    private var hasLoaded = false

    init(api: BillsAPI) {
        self.api = api
    }

    var monthKey: String {
        Date().monthKey()
    }

    var totals: BillTotals {
        let total = bills.reduce(0) { $0 + $1.amount }
        let paid = bills.filter { $0.isPaid }.reduce(0) { $0 + $1.amount }
        return BillTotals(total: total, paid: paid, remaining: total - paid)
    }

    var filteredBills: [Bill] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return bills.sorted { $0.dueDay < $1.dueDay }
        }
        let lower = trimmed.lowercased()
        return bills
            .filter { bill in
                bill.name.lowercased().contains(lower) ||
                String(bill.dueDay).contains(lower) ||
                String(format: "%.2f", bill.amount).contains(lower) ||
                (bill.notes?.lowercased().contains(lower) ?? false)
            }
            .sorted { $0.dueDay < $1.dueDay }
    }

    var upcomingBills: [Bill] {
        let calendar = Calendar.current
        let now = Date()
        let end = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        return bills
            .filter { bill in
                let dueDate = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: calendar.component(.month, from: now), day: bill.dueDay)) ?? now
                return dueDate >= now && dueDate <= end
            }
            .sorted { $0.dueDay < $1.dueDay }
    }

    func loadBillsIfNeeded() async {
        if hasLoaded { return }
        await loadBills(force: true)
    }

    func loadBills(force: Bool = false) async {
        if isLoading && !force { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            let fetched = try await api.fetchBills(monthKey: monthKey)
            bills = fetched
        } catch {
            alert = ErrorInfo(message: error.localizedDescription)
        }
    }

    func refresh() async {
        await loadBills(force: true)
    }

    func openNewBill() {
        editingBill = EditableBill()
    }

    func openEdit(for bill: Bill) {
        editingBill = EditableBill(from: bill)
    }

    func dismissForm() {
        editingBill = nil
    }

    func save(bill: EditableBill) async {
        do {
            if bill.isNew {
                let idValue = bill.customID.trimmingCharacters(in: .whitespacesAndNewlines)
                let payload = BillsAPI.BillRequest(
                    id: idValue.isEmpty ? nil : idValue,
                    name: bill.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueDay: bill.dueDay,
                    amount: bill.amount,
                    notes: bill.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                _ = try await api.createBill(payload)
            } else if let existingID = bill.originalID {
                let payload = BillsAPI.BillUpdateRequest(
                    name: bill.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueDay: bill.dueDay,
                    amount: bill.amount,
                    notes: bill.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                _ = try await api.updateBill(id: existingID, payload: payload)
            }
            await refresh()
            dismissForm()
        } catch {
            alert = ErrorInfo(message: error.localizedDescription)
        }
    }

    func togglePaid(for bill: Bill) async {
        do {
            try await api.setBillPaid(id: bill.id, isPaid: !bill.isPaid, monthKey: monthKey)
            await refresh()
        } catch {
            alert = ErrorInfo(message: error.localizedDescription)
        }
    }

    func delete(_ bill: Bill) async {
        do {
            try await api.deleteBill(id: bill.id)
            await refresh()
        } catch {
            alert = ErrorInfo(message: error.localizedDescription)
        }
    }
}

struct EditableBill: Identifiable, Equatable {
    let id = UUID()
    var originalID: String?
    var customID: String
    var name: String
    var dueDay: Int
    var amount: Double
    var notes: String

    var isNew: Bool {
        originalID == nil
    }

    init(
        originalID: String? = nil,
        customID: String = "",
        name: String = "",
        dueDay: Int = 1,
        amount: Double = 0,
        notes: String = ""
    ) {
        self.originalID = originalID
        self.customID = customID
        self.name = name
        self.dueDay = dueDay
        self.amount = amount
        self.notes = notes
    }

    init(from bill: Bill) {
        self.init(
            originalID: bill.id,
            customID: bill.id,
            name: bill.name,
            dueDay: bill.dueDay,
            amount: bill.amount,
            notes: bill.notes ?? ""
        )
    }
}
