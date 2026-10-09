import SwiftUI

struct SummaryCard<Content: View>: View {
    var title: String
    var symbol: String
    var content: () -> Content
    init(title: String, symbol: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.symbol = symbol; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
struct RecommendationCard: View {
    var actions: [CoachAction]
    var body: some View {
        SummaryCard(title: L10n.text("Today's Recommendation"), symbol: "sparkles") {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Text(action.text).font(index == 0 ? .body.weight(.medium) : .subheadline)
                    .foregroundStyle(index == 0 ? .primary : .secondary)
                    .accessibilityIdentifier("coach.\(action.id)")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("coach.recommendation")
    }
}
struct ActivityCard: View {
    var workout: HealthWorkout
    var body: some View {
        SummaryCard(title: workout.label, symbol: workout.isBadminton ? "figure.badminton" : "figure.strengthtraining.traditional") {
            Text(L10n.text("%@ min", workout.minutes.wholeText)).font(.title2.weight(.semibold))
            if let energy = workout.activeCalories, energy.isFinite, energy >= 0 {
                Text(L10n.text("%@ active kcal", energy.wholeText))
            } else { Text(L10n.text("Active energy unavailable")).foregroundStyle(.secondary) }
            Text(workout.date.formatted(date: .omitted, time: .shortened) + (workout.endDate.map { " – " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("Apple Health · %@", workout.source ?? L10n.text("Source unavailable"))).font(.caption).foregroundStyle(.secondary)
        }
    }
}
extension View {
    func calmList() -> some View {
        listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}
