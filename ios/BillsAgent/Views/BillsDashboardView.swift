import SwiftUI

struct BillsDashboardView: View {
    @EnvironmentObject private var viewModel: BillsViewModel
    @EnvironmentObject private var pushManager: PushManager
    @State private var isShowingChat = false
    @State private var chatViewModel: BillsChatViewModel?

    private var editingBinding: Binding<EditableBill?> {
        Binding(
            get: { viewModel.editingBill },
            set: { newValue in
                if let value = newValue {
                    viewModel.editingBill = value
                } else {
                    viewModel.dismissForm()
                }
            }
        )
    }

    var body: some View {
        List {
            totalsSection
            upcomingSection
            billsSection
            pushSection
        }
        .listStyle(.insetGrouped)
        .overlay(alignment: .center) {
            if viewModel.isLoading && viewModel.bills.isEmpty {
                ProgressView("Loading bills…")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Bills Agent")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showChat()
                } label: {
                    Label("Ask BillsGPT", systemImage: "message.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.openNewBill()
                } label: {
                    Label("Add Bill", systemImage: "plus")
                }
            }
        }
        .sheet(item: editingBinding) { bill in
            NavigationStack {
                BillFormView(form: bill) { action in
                    switch action {
                    case .cancel:
                        viewModel.dismissForm()
                    case let .save(updated):
                        Task { await viewModel.save(bill: updated) }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingChat, onDismiss: {
            chatViewModel = nil
        }) {
            if let chatViewModel {
                NavigationStack {
                    BillsChatView(viewModel: chatViewModel, monthKey: viewModel.monthKey)
                }
            } else {
                ProgressView().task {
                    prepareChat()
                }
            }
        }
        .alert(item: $viewModel.alert) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
        .task {
            await pushManager.ensureAuthorizationChecked()
        }
    }

    private func showChat() {
        if chatViewModel == nil {
            prepareChat()
        }
        isShowingChat = true
    }

    private func prepareChat() {
        chatViewModel = BillsChatViewModel(api: viewModel.api)
    }

    private var totalsSection: some View {
        Section("This month") {
            TotalsGrid(totals: viewModel.totals)
        }
    }

    private var upcomingSection: some View {
        Section {
            if viewModel.upcomingBills.isEmpty {
                Label("Nothing due in the next week", systemImage: "calendar.badge.check")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.upcomingBills) { bill in
                    UpcomingBillRow(bill: bill, onToggle: {
                        Task { await viewModel.togglePaid(for: bill) }
                    })
                }
            }
        } header: {
            Text("Due in the next 7 days")
        }
    }

    private var billsSection: some View {
        Section("All bills") {
            if viewModel.filteredBills.isEmpty {
                ContentUnavailableView(
                    "No bills",
                    systemImage: "tray",
                    description: Text("Add your first bill or change the search filters.")
                )
            } else {
                ForEach(viewModel.filteredBills) { bill in
                    BillRow(
                        bill: bill,
                        onTogglePaid: { Task { await viewModel.togglePaid(for: bill) } },
                        onEdit: { viewModel.openEdit(for: bill) },
                        onDelete: { Task { await viewModel.delete(bill) } }
                    )
                }
            }
        }
    }

    private var pushSection: some View {
        Section("Notifications") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Status", systemImage: "bell")
                    Spacer()
                    Text(pushManager.status.description)
                        .foregroundStyle(.secondary)
                }
                if let token = pushManager.token {
                    Text("Registered token: \(token)")
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                if let summary = pushManager.lastNotificationSummary {
                    Text("Last dispatch: sent \(summary.sent) notification(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let reason = summary.reason {
                        Text("Reason: \(reason)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Request Permission") {
                        Task { await pushManager.requestAuthorization() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Send upcoming alert") {
                        Task { await pushManager.triggerUpcomingPush(monthKey: viewModel.monthKey) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct TotalsGrid: View {
    let totals: BillTotals

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Total due", value: totals.total.currencyString())
            MetricCard(title: "Paid", value: totals.paid.currencyString())
            MetricCard(title: "Remaining", value: totals.remaining.currencyString(), highlight: true)
        }
        .padding(.vertical, 4)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(highlight ? Color.blue.opacity(0.15) : Color.gray.opacity(0.12))
        )
    }
}

private struct UpcomingBillRow: View {
    let bill: Bill
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bill.name)
                    .font(.headline)
                Spacer()
                Button(bill.isPaid ? "Paid" : "Mark paid") {
                    onToggle()
                }
                .buttonStyle(.bordered)
            }
            Text("Due on day \(bill.dueDay) – \(bill.amount.currencyString())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct BillRow: View {
    let bill: Bill
    let onTogglePaid: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.name)
                        .font(.headline)
                    Text("Due day \(bill.dueDay)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(bill.amount.currencyString())
                    .font(.headline)
            }
            if let notes = bill.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onTogglePaid) {
                Label(bill.isPaid ? "Unmark" : "Mark paid", systemImage: bill.isPaid ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .tint(.green)
        }
    }
}
