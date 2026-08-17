import SwiftUI

/// Shared interest picker — wizard step and Profile sheet.
struct ProfileInterestsEditor: View {
    let catalog: [Interest]
    @Binding var selectedIds: [String]
    var isLoading = false
    var errorMessage: String?
    var atLimitMessage: String?
    var showsSelectionCount = true

    private var selectedSet: Set<String> {
        Set(selectedIds)
    }

    private var groupedCatalog: [(Interest.Category, [Interest])] {
        Interest.Category.allCases.compactMap { category in
            let items = catalog.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsSelectionCount {
                HStack {
                    Text("\(selectedIds.count) / \(InterestSelection.maxCount)")
                        .font(NADATheme.headlineFont)
                        .foregroundStyle(NADATheme.ink)
                    Spacer()
                    Text("Optional — pick up to \(InterestSelection.maxCount)")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }
            }

            if let atLimitMessage, selectedIds.count >= InterestSelection.maxCount {
                Text(atLimitMessage)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.brandPressed)
            }

            if isLoading, catalog.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if catalog.isEmpty {
                Text(errorMessage ?? "Couldn't load interests. Check Firestore rules and the `interests` seed.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.danger)
            } else {
                ForEach(groupedCatalog, id: \.0.id) { category, items in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(category.title)
                            .font(NADATheme.headlineFont)
                            .foregroundStyle(NADATheme.ink)

                        WrappingHStack(spacing: 8, lineSpacing: 8) {
                            ForEach(items) { interest in
                                Button {
                                    selectedIds = InterestSelection.toggling(interest.id, in: selectedIds)
                                } label: {
                                    InterestBadgeChip(
                                        label: interest.label,
                                        isSelected: selectedSet.contains(interest.id),
                                        isInteractive: true
                                    )
                                }
                                .buttonStyle(.plain)
                                .animation(.easeOut(duration: 0.15), value: selectedSet.contains(interest.id))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let errorMessage, !catalog.isEmpty {
                Text(errorMessage)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProfileInterestsSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var catalog: [Interest] = []
    @State private var selectedIds: [String] = []
    @State private var isLoading = false
    @State private var localError: String?
    @State private var didHydrate = false

    private let interestService = FirestoreInterestService()

    var body: some View {
        ProfileSheetScaffold(title: "Interests") {
            VStack(alignment: .leading, spacing: 20) {
                Text("Show friends what you’re into. These show up on your Discover card.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)

                ProfileInterestsEditor(
                    catalog: catalog,
                    selectedIds: $selectedIds,
                    isLoading: isLoading,
                    errorMessage: localError ?? auth.errorMessage,
                    atLimitMessage: "That’s 8 — tap one to swap it out."
                )

                Button {
                    Task { await save() }
                } label: {
                    if auth.isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save interests")
                    }
                }
                .buttonStyle(NADAPrimaryButtonStyle())
                .disabled(auth.isBusy || isLoading)
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        localError = nil
        defer { isLoading = false }

        if !didHydrate {
            selectedIds = auth.currentUser?.interestIds ?? []
            didHydrate = true
        }

        do {
            catalog = try await interestService.fetchActiveInterests(locale: "en")
        } catch {
            if catalog.isEmpty {
                localError = "Couldn't load interests. Check Firestore rules and the `interests` seed."
            }
        }
    }

    private func save() async {
        localError = nil
        auth.clearError()
        _ = await auth.updateInterestIds(selectedIds)
        if auth.errorMessage == nil {
            dismiss()
        }
    }
}
