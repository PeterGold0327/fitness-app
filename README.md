# LeanLog — personal fitness MVP

Native iPhone app for nutrition, lean muscle gain, gym training, weight, sleep and simple badminton logging. SwiftUI + SwiftData, iOS 17+, local data, no account or backend. The default profile is 178 cm / 63 kg with 2700 kcal, 130 g protein and 70 g fat targets.

## Run on an iPhone

1. On a Mac with **Xcode 16 or later**, open `FitnessApp.xcodeproj` and select the **LeanLog** scheme. No project generator or third-party iOS packages are required.
2. Select the LeanLog target → Signing & Capabilities. Choose your Apple development team and change `com.personal.LeanLog` to your own unique bundle identifier if needed. Do the same for the LeanLogTests identifier if signing tests. HealthKit capability and the read-purpose string are already in the project. Your signing team/provisioning profile must support HealthKit.
3. Choose an iOS 17+ iPhone and run. Simulator works for manual logging and photo-library selection, but camera and real Apple Watch/Health records require a device.
4. Open Settings → Health permissions & data → Request / review Health access. Choose which data to share. Watch sleep requires sleep tracking to be enabled and Watch data to have synced to Health.
5. Start by logging breakfast, a meal, a weigh-in and a gym session. Add foods you have at home under Settings → Food inventory.

The cloud machine is Linux. **The iOS app has not been compiled or launched with Apple's SDK here.** See the device checklist below. Code signing, provisioning and actual Health reads must be checked on macOS/device.

## What's implemented

- **Home:** daily nutrition, remaining targets, breakfast state, quick logging, activity, weight averages and sleep.
- **Nutrition:** dated food log, add/edit/delete meals, camera/library attachment, two-step food-photo detection/review and nutrition estimation via OpenAI, or editable demo estimates, and three meal suggestions with specific grams and estimated macros.
- **Training:** date/name and multiple exercise rows per gym session, load/sets/reps/target reps/RPE/notes, edit/delete sessions, simple weekly progression, nearby badminton warnings and a date-only badminton log (including upcoming dates).
- **Progress:** Overview retains the 28-day weight graph and 7-day moving averages, 2/4-week comparisons, nutrition adherence, live last-seven-day summary and saved summary snapshots.
- **Growth Timeline / 成长时间线:** day/week/month/year history from existing logs, period summaries and previous-month comparison, automatic/manual milestones, private front/side/back progress photos and comparison pairs, On This Day, and Markdown + photo ZIP export to Files. Find Overview, Timeline, Milestones and Photos inside Progress. See [archive design and validation](docs/GROWTH_TIMELINE.md).
- **Settings:** profile and nutrition targets, breakfast portions, kg/lb display, inventory, Health access and food-photo API configuration.
- **HealthKit:** read steps, active energy, latest heart rate today, recent workouts, weight and sleep; manual logging remains usable without Health access. Watch data is read via HealthKit, not a separate Watch app.

## Languages

English is the fallback; Simplified Chinese (`zh-Hans`) follows the iPhone language automatically. All app labels, generated coaching/summaries and camera/Health explanations have native localization resources. User-entered text and saved snapshots stay as recorded. See [localization checks and the iPhone layout checklist](docs/LOCALIZATION.md).

## MVP rules and limits

- Each day starts with **planned** yogurt + banana + oats (200 / 120 / 60 g; about 486 kcal and 29 g protein). Mark eaten or skip it. Planned meals do not count toward intake, and breakfast cannot be logged twice. Edit an eaten breakfast in the food log.
- Nutrition estimates use typical supermarket values, not a verified food database. Check your product labels. Recipe quantities refer to edible portions; chicken and rice are cooked weights.
- Suggestions prioritize inventory matches and remaining calories/protein, with activity-sensitive portions. Weight-trend advice is displayed but targets change only when you explicitly save them in Settings. The app does not automatically add Health active calories to your calorie budget.
- **Food-photo AI:** a swappable OpenAI Responses service is implemented alongside a labelled demo provider. Demo is the initial mode; real analysis requires your API key and API billing/model access. Photos upload only when you tap Analyze. First review detected dishes and cooked portions, correcting, adding or removing foods. Then request nutrition for that reviewed list. Add text context (up to 2,000 characters) and re-detect or re-estimate, including Chinese mixed dishes such as 盖浇饭, 麻辣烫 and 火锅. Edit grams/macros/confidence/notes before saving; portion changes proportionally recalculate nutrition and meal totals. Confidence labels are low (<0.5), medium (0.5–<0.8), or high (≥0.8), and remain uncalibrated. Failures preserve the draft; optional labelled demo fallback is off by default. See [API setup and exact credentials](docs/FOOD_PHOTO_API.md).
- One weight per calendar day; manual values override Health imports. Trend comparison needs at least four weigh-ins in each of the two comparison weeks. The four-week rate compares the first and last week and divides by three. Rates are approximate coaching suggestions.
- Gym entries group sets sharing weight/reps. Use additional rows for different loads. Progression checks completed target sets/reps and RPE, and compares per-set performance across sessions for the same exercise name. The global weekly volume flag is a rough heuristic, not a personalised plan. Heavy leg rows (RPE ≥ 8) within 48 hours of a recorded or readable Health badminton date trigger a suggestion.
- Health workouts inform activity-aware meal suggestions and badminton warnings, but stay separate from manual gym sets/badminton dates. They do not duplicate logged sessions or supply exercise-level progression; weekly session counts are explicitly manual.
- Health read denial is intentionally hidden by Apple. Empty values mean no readable samples or no permission, never proof of zero activity. Previously imported sleep/weight stays locally cached after permission revocation. Deleting an imported weigh-in does not delete it from Health; refresh may reimport it.
- Sleep merges overlapping asleep samples (Watch/iPhone duplicates) in noon-to-noon windows assigned to the waking day. In-bed/awake records are excluded; naps can contribute to the daily total. There is no manual fatigue/mood module.
- Weekly nutrition averages use **logged days**, with coverage shown. Sleep averages use available nights. No-data days are not zeros. Adherence compares past intake to your current targets, not historical target snapshots.
- Local SwiftData only. Growth Timeline can export a Markdown/photo ZIP as a manual portable archive; it is not a restorable database backup. Deleting the app can remove local logs and progress photos. There is no cloud sync, authentication, subscription or social module.

## Structure

```
FitnessApp/
  FitnessApp.swift          App entry, SwiftData container, visible storage errors
  Models/Models.swift      Persisted profile, day state, meals/foods, weight,
                           workouts/exercises, sleep, badminton, inventory, summaries
  ViewModels/AppStore.swift Small shared view model; save/upsert/import and summaries
  Services/                Pure coaching rules, HealthKit reads, photo service
  Views/                   Five tabs plus logging forms
  Resources/               Info.plist, HealthKit entitlement, privacy manifest
FitnessAppTests/            Portable domain tests + iOS persistence tests
FitnessAppUITests/          Navigation and core form tests (Xcode only)
FitnessApp.xcodeproj/       Checked-in project and shared LeanLog scheme
Package.swift              Portable logic test target; not the iOS app entry
```

## Validation commands

Portable core, on Linux or macOS with Swift 5.9+:

```sh
bash scripts/test-core.sh
```

`SWIFT_BIN=/path/to/swift` can override the toolchain. This cloud instance has Swift 6.0.3 under `/workspace/.fitness-tools`. Caches use writable temporary directories. `scripts/setup-cloud.sh` restores that pinned Linux toolchain over verified TLS and checks the pinned SHA-256 when needed, then runs core tests. It never changes application source or lockfiles.

On macOS, list simulator destinations and run the full app-hosted test suite:

```sh
xcodebuild -project FitnessApp.xcodeproj -scheme LeanLog -showdestinations
xcodebuild -project FitnessApp.xcodeproj -scheme LeanLog \
  -destination 'platform=iOS Simulator,id=REPLACE_WITH_SIMULATOR_UDID' \
  -derivedDataPath DerivedData test CODE_SIGNING_ALLOWED=NO
```

**Quality pass:** 103 portable XCTest cases pass on Linux. Xcode also contains 23 SwiftData tests, 2 configuration tests and 7 UI tests, all still unrun here. Persistence tests cover inverses/cascades, replacement of children, rollback, daily rollover, repeated imports, completion targets, coverage, exercise ordering and file-backed reopening. UI tests cover all five tabs, sheets/cancellation, food save/invalid-input handling and settings navigation. See [the full review](docs/MVP_REVIEW.md) for feature-by-feature coverage, fixes and known limits. These Apple-platform tests cannot execute on Linux.

Only if files are added/removed, regenerate project references using `python3 scripts/generate_project.py` (this replaces the generated project and scheme; preserve any custom signing/project settings first). Otherwise open the checked-in project directly.

## Still required on macOS / iPhone

- Build the app and run all app-hosted XCTest cases; resolve any Apple-SDK compile issues discovered there.
- Fresh launch: default profile and planned breakfast. Skip/restore/eat breakfast; verify totals update once and persist after termination/relaunch.
- Camera: approve, deny, cancel and capture; library: choose/cancel. Apply demo estimate, edit each food/portion/macro/confidence/note, save, reopen and delete the meal.
- API: configure your key, verify Keychain storage and a real OpenAI photo request, then test offline/invalid-key handling, cancellation and explicit demo fallback. Validate schema upgrades from any earlier installed build.
- Log an entire multi-exercise workout, edit/delete it, change units, add nearby badminton, and inspect progression/warning text.
- Enter enough daily weights for averages, inspect the chart, preview a calorie adjustment, cancel it, and confirm targets only change on Save.
- Grant all, some and no Health read types; refresh on returning to foreground. Check real Watch steps/workouts/sleep, overlapping sleep, manual weigh-in precedence and missing-data messaging.
- Verify a midnight/day rollover and a timezone change without double breakfast or daily entries. Historical days use the device's local calendar at entry time; cross-timezone history is not normalized in this MVP.
- Review the last-seven-day summary and nutrition coverage, save it, relaunch and confirm local persistence.
- Validate Growth Timeline after upgrading an existing install: original logs/photos remain intact, milestones do not duplicate, progress photos reopen locally, period navigation and Chinese layouts work, and an exported ZIP opens in Files with every referenced image. See the archive checklist.

No simulator/device behavior or real Health reads have been claimed as verified in this Linux environment.
