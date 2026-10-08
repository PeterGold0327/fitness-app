# MVP quality review

This review checked every source file, each tab/sheet/settings route, the SwiftData model graph, store save/import paths, nutrition and coaching rules, HealthKit query/authorization paths, resources, Xcode target membership and test scheme. It fixed existing behavior; no accounts, backend, cloud sync, new tracking module or workout-plan engine was added.

**Verification boundary:** Linux can compile/run the portable core and parse all Swift source. It cannot type-check Apple framework APIs, run SwiftData, display SwiftUI, launch XCTest UI automation or read HealthKit. “Implemented” below means the source and UI entry point are present, not that an iPhone runtime has been verified.

## Feature coverage and UI access

| Original requirement | Where to access it | Status / limit |
|---|---|---|
| Food photo, estimate, review and save | Home → Take food photo; Nutrition → Take or upload food photo | Camera/library attachments and editable save flow implemented. OpenAI Responses HTTP adapter, editable item estimates and labelled mock/fallback implemented; credentials and live-device validation still needed. |
| Three next-meal options with grams | Home/Nutrition → What should I eat now? | Three supermarket recipes; inventory, remaining calories/protein, gym/badminton activity and weight advice considered. Over-budget normal portions are labelled. |
| Automatic yogurt/banana/oats breakfast | Home and Nutrition → Breakfast | Planned each day, mark eaten, skip, restore or edit eaten entry. Initial estimate ≈486 kcal / 29 g protein. |
| Initial and adjustable targets | Settings → Profile, targets & breakfast | 2700 kcal / 130 g protein / 70 g fat initially; editable and no silent trend-based changes. |
| Daily weight, average and 2/4-week trends | Home → Log weight; Progress → chart, comparisons, history | One weight/day, edit/delete, 7-day averages and coverage-gated advice implemented. |
| Gym exercises, load, sets/reps, RPE, notes | Home/Training → Log gym workout | Multi-row sessions, explicit completed/target sets and reps; date inherited from session; edit/delete implemented. |
| Weekly progression | Training → Next-week suggestions; Progress → Gym progress / Weekly summary | Completion, RPE, two-session per-set decline and rough weekly volume flags. Advice only. |
| Badminton near heavy leg day | Gym editor and expanded gym session | Warning for RPE ≥8 leg rows near recorded or readable Health badminton. No automatic plan edits. |
| Simple badminton | Home → Log badminton; Training → dates | Date-only, daily deduplication, upcoming dates, deletion. Duration remains optional/unimplemented. |
| Sleep | Home → Last night's sleep / recent average; Progress → summary | Real Health read path, overlapping asleep intervals merged, noon-to-noon attribution. No manual fatigue/mood fields. |
| Apple Health / Watch | Settings → Health permissions & data; Home → Connect Apple Health | Read-only steps, active energy, heart rate, workouts, sleep, weight. Watch via HealthKit. Needs real permissions and data. |
| Inventory | Settings → Food inventory | Add/remove, trimmed/case-insensitive deduplication, word-based recipe matches including yoghurt/yogurt. |
| Weekly summary | Progress → Weekly summary / Saved summaries | Rolling seven calendar days, coverage, average nutrition/sleep, manual gym/badminton, weight advice, exercise progression and snapshot saving. |
| Dashboard and quick actions | Home | All six quick actions plus targets, breakfast, activity, latest weight/trend, sleep and next-meal suggestion wired. |
| Five tabs | Bottom tab bar | Home, Nutrition, Training, Progress, Settings, each with its own navigation stack. |
| Progress page | Progress | Weight chart, calorie/protein adherence, actual gym session change, summaries and editable weight history. |
| Settings | Settings | Targets, breakfast, Health, kg/lb display, inventory and profile editing. Height/breakfast remain cm/g; weight/load/trend follow kg/lb preference. |
| Replaceable photo AI | `FoodPhotoAnalyzing` service | Swappable interface, real OpenAI/compatible Responses adapter, no-upload demo and opt-in labelled fallback. Credentials in device Keychain; upload only on Analyze. |
| Local data models | `Models.swift` | All 11 requested model types included. Parent-child inverses and cascade deletion explicit. |
| Simple personal-use design | All screens | Native lists/forms/charts, readable empty states, keyboard Done actions, visible errors and validation. |

## Corrections made

- Added target sets and checks for **all planned sets/reps completed**. Incomplete/zero-set sessions cannot trigger an increase. Bodyweight exercises suggest reps rather than added kilograms. Fewer planned sets alone do not masquerade as two declining sessions; the decline heuristic uses per-set performance and explicitly asks whether lighter days were intentional.
- Added actual latest workout/load and volume-change text to Progress and weekly summaries. Exercise-name matching is case-insensitive and multi-row exercises remain one observation per session.
- Eaten breakfast shows the **saved meal**, not new settings. Daily state reconciles with saved meals after reload/rollback; skip/restore cannot contradict an eaten meal. Breakfast saves check day rollover themselves.
- Numeric inputs now reject invalid/blank/partial input instead of silently retaining the previous valid number. Shared finite/range validation exists at the store boundary for meals, weights and workouts. Zero-calorie drinks can be logged. Display formatting avoids unsafe Double-to-Int conversion.
- Weight advice ignores non-finite/future measurements, rejects unusable comparison windows and handles floating-point noise at the 0.1/0.25 kg/week boundaries. Calendar-based windows are tested across daylight saving changes.
- Explicit meal→food and workout→exercise inverses with cascade deletion. Editing clears old child links before deleting stale children. Explicit row positions preserve newly saved exercise order across reloads. Draft forms stage changes locally, automatic context saves are disabled, failed saves roll back and reload profile/day references, and load failure has a retry screen. A committed save is not reported as failed merely because its subsequent reload fails, avoiding duplicate retries.
- Manual weigh-ins retain precedence. Health imports sort by sample date and upsert deterministically, reject invalid/future values and avoid repeated daily entries. Upcoming badminton is excluded from completed summaries.
- Health authorization has a separate in-flight guard; refresh cannot overwrite an authorization failure. All six types are read-only. No `authorizationStatus(for:)` check is incorrectly used to infer read permission. Unavailable Health has explicit copy; empty reads remain unknown, not zero. Live values clear before refresh; locally imported sleep/weight is explicitly labelled cached.
- Readable Health gym/badminton informs meal/activity and scheduling advice without creating duplicate manual log records. Weekly session totals are explicitly manual; Health workout records remain visible separately.
- Camera permission denial has a library/manual fallback and Settings link. Library photos are downsampled before full decode. Replaced photo loads are cancelled, photo/analysis states cannot overwrite one another, and repeated Save taps are guarded.
- Better empty states, direct edit access to eaten breakfast, a Today control in the food log, foreground/midnight refresh, readable sheet-level errors and a keyboard Done control.

## Executed checks

- **56 portable XCTest cases passed**, zero failures: 20 original domain tests, 16 quality regressions and 20 food-photo API tests.
- Portable tests compile real nutrition, trend, progression, input/validation, inventory and sleep-window logic; they do not assert that Apple integrations ran.
- Swift parser accepted all app, unit-test and UI-test source files.
- All Info/entitlement/privacy plists and the Xcode project parsed successfully. Every source file belongs to its intended target; target dependencies and shared unit/UI test references resolve.
- Shell setup/test scripts passed syntax checks. No new third-party app dependency or API credential was added.

## Xcode/macOS and device checks still unrun

- **19 SwiftData tests**: daily state/rollover, breakfast and ingredient snapshots, meal edits/deletion, manual/import weight precedence, repeated imports, validation, workout replacement/completion, inverse/cascade rules, rollback, summary coverage, row ordering and real file-backed reopening.
- **2 configuration tests**: nonsecret preference persistence, key preservation/removal and failed credential writes using isolated preferences and injected fake credentials. Real device Keychain remains unverified.
- **4 Xcode UI tests**: five-tab navigation, logging/recommendation sheets and cancel paths, food save/dashboard updates plus invalid-input gating, and settings subpage back navigation. Tests use a DEBUG-only in-memory launch flag; they never erase personal logs or request Health access automatically.
- Apple SDK compilation, code signing, provisioning and install/launch on iOS 17+. An Xcode build may still reveal framework/type-check issues that Linux parsing cannot detect.
- Camera grant/denial, real photo picker, keyboard/focus behavior, chart rendering, VoiceOver/Dynamic Type and actual navigation gestures.
- Real Health grant/partial/denied reads, authorization failures, unavailable Health, synced Apple Watch sleep/workouts, refresh after permission revocation and current-device calendar/timezone behavior.
- Database schema upgrade from an earlier installed build. SwiftData's inferred migration for new inverse relationships/target sets/row positions/food macros and analysis metadata must be checked in Xcode; no destructive reset or migration framework was added.

Run `xcodebuild -project FitnessApp.xcodeproj -scheme LeanLog -showdestinations`, then the README's simulator test command. The shared scheme now includes both LeanLogTests and LeanLogUITests. Use a physical iPhone for real Watch/Health and camera verification.

## External API and known limitations

- **Real food-photo recognition needs your external API credentials.** OpenAI Responses and compatible Responses endpoints are now implemented behind a swappable interface, with Keychain configuration, editable itemized estimates and explicit demo fallback. Supply an OpenAI project API key with Responses access, billing/credits and vision-model access. See [setup, tests and limitations](FOOD_PHOTO_API.md). No live paid call has been made here. All other features run locally or read Apple's HealthKit.
- Nutrition uses a small three-recipe catalogue and typical product labels; it is not a comprehensive food database, gram-based scanner or medical nutrition planner. Recommendations can exceed remaining calories when a normal serving is larger; the UI warns rather than pretending it fits.
- Gym advice is a simple heuristic, not a recovery/periodisation model. You supply the plan and targets through logs; there are no separate reusable workout templates. Row-level sets share weight/reps; use multiple rows when loads/reps differ. Exercise order is explicitly saved; any legacy rows without stored positions must be reviewed if upgrading an older build.
- Summaries are rolling seven-day views and user-saved snapshots, not an automatic weekly notification/report. Missing/partially logged days are labelled; averages use logged days/available sleep nights. Historical adherence uses current targets.
- Health read denial cannot be distinguished from no samples. Cached imports remain after revocation; deleted local Health weigh-ins may reappear on refresh. Refresh is foreground/manual, not continuous/background sync. Health workouts inform advice but do not count as manually logged gym/badminton sessions in summaries.
- Sleep windows can include naps. Overnight durations are elapsed hours, not a manual sleep diary.
- Daily timestamps use the device calendar; travel across timezones can change attribution of historical entries. DST is covered for calculations, but cross-timezone storage behavior remains a device check/limitation.
- Data is local only. No export/backup/sync; deleting the app may remove logs. No app icon polish or advanced analytics was added.
