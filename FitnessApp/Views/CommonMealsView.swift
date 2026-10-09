import SwiftUI

struct CommonMealsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var library: PersonalLibrary
    @State private var logged: String?
    var body: some View {
        List {
            Section(L10n.text("Saved meals")) {
                if library.state.meals.isEmpty { Text(L10n.text("Save a recent meal below to log it again with one tap.")).foregroundStyle(.secondary) }
                ForEach(library.state.meals) { template in
                    Button {
                        if store.logMealTemplate(template) { logged = template.name }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(template.name).font(.headline)
                            Text(L10n.text("%@ kcal · %@ g protein", template.calories.wholeText, template.protein.wholeText)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("meal.template.\(template.id)")
                        .swipeActions { Button(L10n.text("Delete"), role: .destructive) { library.update { $0.meals.removeAll { $0.id == template.id } } } }
                }
                Button(L10n.text("Log yogurt, oats & banana")) {
                    if store.logOption(store.breakfast, breakfast: true) { logged = store.breakfast.displayName }
                }
            }
            Section(L10n.text("Save from recent records")) {
                ForEach(Array(store.meals.prefix(20))) { meal in
                    Button { if store.saveMealTemplate(meal) { logged = L10n.text("Saved as a common meal") } } label: {
                        Label(meal.name, systemImage: "bookmark")
                    }
                }
            }
            if let logged { Section { Text(L10n.text("Done: %@", logged)).foregroundStyle(.teal) } }
            if let error = library.error { Section { Text(error).foregroundStyle(.red) } }
        }.calmList().navigationTitle(L10n.text("Common meals"))
    }
}
