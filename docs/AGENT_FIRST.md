# Agent-first integration

The two product requests are implemented together on the existing LeanLog app, not a replacement app. The native route remains `FitnessApp.WindowGroup → RootView.tabs → Home / Nutrition / Training / Progress / Settings`. All 30 app Swift sources are compiled by the LeanLog application target, and the shared scheme builds/launches that target. The original Growth Timeline entry points remain owned by `RootView.progressTab` above the Progress analytics.

## What changed

Home answers what to do next with one primary and at most one secondary recommendation, then shows yesterday, readable sleep, current targets, an optional user-selected workout and current activity. Photo logging, starting a template workout and viewing today's advice are the three main actions. Manual food, meal suggestions, legacy gym logging, weigh-ins and badminton remain in the top-right menu. Breakfast accounting still requires marking breakfast eaten.

Daily Coach is a local, explainable rules layer, not a chatbot or an additional paid API. It prioritizes the selected training direction and logged protein gap, then known activity/recovery and a coverage-qualified weight trend. It distinguishes absent nutrition from zero intake, absent sleep from poor recovery, and missing Health energy from zero activity. Low sleep and long training gaps favor conservative loads. Recommendations never change calorie/protein targets or the workout schedule. Weight-target changes still require the existing explicit Settings action.

Nutrition retains the one-request photo estimate, editable components and computed totals. Optional re-analysis after manual edits preserves current names, grams, removals/additions and changed nutrition; unedited nutrition can refresh. The normal result has no confidence/range/uncertainty interface or required second request. Eat Now gives one primary meal, with existing alternatives under an optional disclosure. High readable activity can add 50 g cooked rice to that suggestion when there is room in the logged target; exercise energy is not mechanically reimbursed. Common Meals saves actual previous meals and can log them with one tap. A breakfast option remains available without pretending the user has saved a template.

Training starts with today's actual readable Health workouts: type, start/end, duration, active energy and recorded source. Energy is read from `HKQuantityType.activeEnergyBurned` workout statistics; `totalEnergyBurned` is not used. Unknown energy stays unavailable. Watch records appear through HealthKit; the app cannot infer Watch connection status or read denial. Manually entered duration/active energy can be shown when Health has no workout of that type/day, with a manual source label. Gym sets stay user-entered and separate from read-only Health workouts.

Four persistent templates cover Chest, Shoulders, Back and Legs. Users can edit exercise names and keep at most one optional badminton accessory. Templates have no mandatory set/rep prescription, rest-day module or timer. Each exercise loads the last completed session automatically, including English/Chinese aliases for equivalent movements; distinct movements such as incline press and flat bench stay separate. Prior per-set loads fill the form, but today's reps are blank until entered. Users can add sets or skip an exercise. Previous date/sets/reps and one short progression suggestion appear beside today's fields. Save records actual sets and shows a short comparison; those sets become the next workout's history. Existing sessions with grouped sets are expanded in memory and remain stored unchanged.

Progress retains all archive screens, charts, weight history, nutrition adherence and weekly summaries. A 14-day card adds recorded protein averages, recorded gym sessions, training days and observed weight change; missing nutrition days are excluded from averages. Day/week/month/year archive navigation, milestones, food and progress photos, On This Day and Markdown/photo ZIP export remain available. Period overview cards share the calm grouped surfaces used throughout the app.

Settings groups personal goals, Health/data/export, food recognition and preferences. Advanced endpoint/model/fallback options are behind a disclosure. Appearance supports system/light/dark, language opens iPhone settings, and weight units remain configurable. iCloud sync is explicitly unavailable rather than a nonfunctional switch. English and Simplified Chinese strings include the requested 运动 tab label.

## Storage and safety

**No SwiftData schema migration is needed.** The existing `@Model` definitions, model container schema, bundle identifier, entitlements and store location are unchanged. No store is deleted, recreated or reset. Per-set training uses existing `ExerciseEntry` rows with `sets = 1`; legacy multi-set rows remain readable. Old meal confidence/notes metadata stays compatible.

Templates, selected workout/day, optional goal weight, common-meal snapshots and manual activity metadata use a bounded, versioned Codable preference document (`leanlog.personalLibrary.v1`). They do not duplicate the fitness database or photos. Failed reads retain the saved preference copy and block replacement; invalid writes preserve the prior state. Gym metadata follows its workout ID when edited/deleted; manual badminton metadata follows the logged date. UI tests use a dedicated preferences suite and an in-memory fitness store, not personal records. Core persistence tests use isolated suites.

Local history makes exercise progression, weight advice and common-meal reuse more useful over time. There is no automatic changing of targets, hidden model training, cloud synchronization or new Agent API upload.

## Swift file inventory

| New Swift file | Purpose |
| --- | --- |
| `Services/DailyCoach.swift` | Two-action priority logic and one activity-aware meal suggestion |
| `Services/TrainingCoach.swift` | Four templates, canonical exercise names, per-set history and conservative progression |
| `Services/PersonalLibrary.swift` | Validated Codable template/meal/plan/activity preferences |
| `ViewModels/CoachStore.swift` | Preference persistence, current coach input, historical set lookup and common-meal logging |
| `Views/DashboardComponents.swift` | Reusable summary, recommendation and activity cards |
| `Views/TrainingTemplatesView.swift` | Template selection/editing, per-set logging and gym detail |
| `Views/CommonMealsView.swift` | One-tap saved meals and saving recent meals |
| `FitnessAppTests/AgentTests.swift` | Coach, training and preference persistence regression cases |

Modified app Swift files: `FitnessApp.swift`; `ViewModels/AppStore.swift`; `Services/FitnessLogic.swift`, `FoodPhotoService.swift`, `HealthService.swift`; and `Views/RootView.swift`, `HomeView.swift`, `NutritionView.swift`, `TrainingView.swift`, `MealEditor.swift`, `ProgressView.swift`, `GrowthTimelineView.swift`, `SettingsView.swift`, `FoodAnalysisSettingsView.swift`. Updated tests: `FoodPhotoAPITests.swift`, `LocalizationTests.swift`, `PersistenceTests.swift` and `FitnessAppUITests/NavigationTests.swift`. The project, Swift package source list, English/Chinese resources and documentation are updated alongside these files.

## Verification

Linux passes **126 portable XCTest cases**: the original tests plus 16 Agent/template cases and one correction-preserving photo re-analysis case. Checks cover missing data, priority/action limits, active-energy context, modest meal changes, exercise aliases, per-set comparison, gaps, repeated decline, sleep, four valid templates, saved-template/meal/plan reloads, corrupt/invalid preference protection and manual fallback values. Project/scheme regression checks and localization coverage also pass. Swift syntax parses for all app and test files.

The app target now includes 26 SwiftData tests, 2 configuration tests and 11 UI tests. Three new SwiftData cases check per-set alias history after reopening, independent common-meal logging without changing the original photo, and manual activity metadata following workout edits/deletes. Two new UI cases exercise the actual Coach/template navigation and common meals/archive reachability. **These Apple-platform tests and Apple-SDK compilation were not run on Linux.** Offline food tests do not prove live recognition accuracy.

On macOS, open `FitnessApp.xcodeproj`, select LeanLog and run the full scheme tests on an available iPhone simulator/device. On the real iPhone, verify:

- Upgrade an existing install without deleting its database; existing meals/photos, weight, gym sessions and archives reopen.
- Coach produces one or two useful cards with complete data and reasonable missing/denied-Health fallbacks; selecting today's split updates the card without changing targets.
- All four templates save/reopen, previous English/Chinese exercise rows appear, pounds convert correctly, blank reps cannot be saved as completed work, and a saved per-set session appears next time.
- Watch strength/badminton duration and **active** energy agree with Health, unavailable energy stays unavailable, and manual fallback does not duplicate readable same-type/day activity.
- Photo estimate → optional edit → Save still works; a current manual correction survives explicit re-analysis, and common meals log without altering the original meal/photo.
- Progress's five archive routes, weight history, charts and Markdown/photo ZIP export still work.
- Chinese/English, Dynamic Type, Light/Dark/system appearance, iPhone 17 Pro Max and smaller iPhone layouts remain readable. This cloud environment cannot verify these rendered layouts.
