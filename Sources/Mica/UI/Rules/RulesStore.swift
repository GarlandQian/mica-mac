import Foundation
import MicaCore

struct RuleRowItem: Identifiable, Equatable, Sendable {
    let id: String
    let type: String
    let payload: String
    let proxy: String
    let isDisabled: Bool
    let hasMutableExtra: Bool
    let raw: RuleViewState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.raw == rhs.raw
    }
}

/// Lean projection store for Rules & Providers.
@MainActor
@Observable
final class RulesStore {
    private(set) var rows: [RuleRowItem] = []
    private(set) var availableTypes: [String] = []
    private(set) var totalRuleCount = 0

    var selectedType: String = "" {
        didSet {
            guard oldValue != selectedType else { return }
            rebuildRows()
        }
    }

    var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            rebuildRows()
        }
    }

    @ObservationIgnored private var rawRules: [RuleViewState] = []
    @ObservationIgnored private var lastRulesSnapshot: [RuleViewState] = []

    func sync(rules: [RuleViewState]) {
        guard rules != lastRulesSnapshot else { return }
        lastRulesSnapshot = rules
        rawRules = rules
        totalRuleCount = rules.count

        var seen = Set<String>()
        var types: [String] = []
        for rule in rules {
            let trimmed = rule.type.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, seen.insert(trimmed).inserted {
                types.append(trimmed)
            }
        }
        availableTypes = types.sorted()
        if !selectedType.isEmpty, !seen.contains(selectedType) {
            selectedType = ""
        }
        rebuildRows()
    }

    func rule(id: String) -> RuleViewState? {
        rawRules.first { $0.id == id }
    }

    private func rebuildRows() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var next: [RuleRowItem] = []
        next.reserveCapacity(rawRules.count)

        for rule in rawRules {
            if !selectedType.isEmpty, rule.type != selectedType {
                continue
            }
            if !query.isEmpty {
                let matched = rule.payload.lowercased().contains(query)
                    || rule.proxy.lowercased().contains(query)
                    || rule.type.lowercased().contains(query)
                if !matched { continue }
            }
            next.append(
                RuleRowItem(
                    id: rule.id,
                    type: rule.type,
                    payload: rule.payload,
                    proxy: rule.proxy,
                    isDisabled: rule.disabled ?? false,
                    hasMutableExtra: rule.hasMutableExtra,
                    raw: rule
                )
            )
        }

        if next != rows {
            rows = next
        }
    }
}
