# Personal Fitness System / LeanLog

This repository is part of my personal fitness and nutrition system. The project started as **LeanLog**, a native iPhone fitness app, but the wider system now also includes cross-device fitness tracking, Supabase-backed data, Apple Health data and AI-assisted coaching.

> For the complete cross-device architecture, data-source rules and AI-agent behaviour, see **[System Architecture](docs/SYSTEM_ARCHITECTURE.md)**.

## What this project is trying to build

The goal is not only to create a workout logging app. The long-term goal is to build a personal fitness system that can:

- record workouts at the **individual set level**
- track weight, reps and RPE for progressive overload
- remember previous performance for each exercise
- provide next-session training suggestions
- record meals, calories and macronutrients
- remember frequently used foods and nutrition values
- track body weight and nutrition trends
- use Apple Health data such as sleep, activity and workouts
- keep long-term fitness history
- allow an AI agent to use historical data when giving training and nutrition advice

The basic feedback loop is:

**Record → Store → Analyse history → Recommend → Train/Eat → Record again**

The system should become more useful as more personal data is collected.

## System Architecture

The current fitness project should be understood as several connected parts rather than only this iPhone repository.

### 1. LeanLog — iPhone App

LeanLog is the native iPhone application contained in this repository.

Technology:

- SwiftUI
- SwiftData
- iOS 17+
- HealthKit
- OpenAI-assisted food photo analysis

Main functions include nutrition logging, food photo estimation, workout logging, workout templates, per-set weight/repetition tracking, RPE tracking, progression suggestions, body-weight trends, Apple Health integration and Growth Timeline history.

LeanLog originally used local SwiftData as its main storage system.

### 2. Fitness Web / Windows Interface

A separate interface is used on Windows and other devices for recording and reviewing fitness data.

The workout model records individual sets rather than only one weight for an entire exercise. Each set can store its own weight, reps and RPE so progression can be judged from actual performance rather than a single exercise-level value.

### 3. Supabase — Shared Fitness Data

The wider fitness system uses **Supabase** as a cloud data layer.

Current stored data includes areas such as:

- workouts
- exercise sets
- weight / reps / RPE
- meals
- calories and macros
- body weight
- profile and nutrition targets
- workout templates
- frequently used food information
- imported health/activity information
- sleep and activity summaries

Supabase allows the fitness history to be accessed independently of one device.

The long-term architecture is intended to move toward:

**iPhone + Windows/Web + Health data + AI Agent → shared fitness data**

rather than keeping important fitness history isolated on individual devices.

> Important: the original LeanLog implementation in this repository is still primarily SwiftData/local-first. Supabase belongs to the wider fitness system and should not be confused with the original local persistence architecture described later in this README.

## Training Logic

The training system is designed mainly around **hypertrophy**.

It does not use a simple rule such as “hit the top of the rep range, then automatically increase weight”. Recommendations should consider previous weight, repetitions, RPE, performance across individual sets and recent training history.

The goal is **long-term progressive overload**, not forcing weight increases every workout.

## Nutrition Logic

Nutrition tracking combines manual input with reusable food information and AI-assisted photo estimation.

For foods used frequently, confirmed nutrition information can be remembered so that the system does not need to estimate the same product repeatedly. When reliable manual information is available, it should take priority over AI visual estimation.

## Health and Recovery

Apple Health / HealthKit data can provide context such as sleep, steps, active energy, heart rate, workouts, badminton sessions and body weight.

The longer-term goal is to combine recovery information with gym performance, so temporary changes in RPE or performance can be interpreted in context rather than automatically treated as strength loss.

## AI Agent Role

An AI agent can act as an analysis layer on top of the fitness history.

Instead of treating every question independently, the agent should use previous records when answering questions such as:

- What weight did I use last time?
- What should I use for this exercise today?
- Am I progressing on this movement?
- Is my weekly training volume increasing?
- Did my RPE increase at the same load?
- Am I eating enough protein?
- Is my body weight moving toward my goal?
- Could poor recovery explain today's performance?

The intended behaviour is:

**historical data first → analysis → personalised recommendation**

rather than generic fitness advice.

## Current Direction

The project is gradually moving from a collection of fitness logging features toward a unified personal fitness platform.

The intended architecture is:

**LeanLog iPhone App + Windows/Web Interface + Supabase + Apple Health + AI Agent = Personal Fitness System**

The sections below document the current native LeanLog iPhone implementation in more technical detail.

---

# LeanLog — personal fitness MVP

Native iPhone fitness and nutrition app with an embedded Daily Coach: one or two practical next actions, nutrition photo logging, repeatable gym training and Growth Timeline history. SwiftUI + SwiftData, iOS 17+, local data, no account or backend. The default profile is 178 cm / 63 kg with 2700 kcal, 130 g protein and 70 g fat targets.

The Home tab is a calm card dashboard for yesterday, sleep, today's targets, a selected workout and the next useful action. Common meals can be saved from prior records and logged with one tap. Goals, Health/data, food recognition and preferences are grouped in Settings; theme follows the system or a Light/Dark choice. No SwiftData migration or store replacement is needed. See [Agent-first integration, file inventory and device checks](docs/AGENT_FIRST.md).

## Run on an iPhone

1. On a Mac with **Xcode 16 or later**, open `FitnessApp.xcodeproj` and select the **LeanLog** scheme. No project generator or third-party iOS packages are required.
2. Select the LeanLog target → Signing & Capabilities. Choose your Apple development team and change `com.personal.LeanLog` to your own unique bundle identifier if needed. Do the same for the LeanLogTests identifier if signing tests. HealthKit capability and the read-purpose string are already in the project. Your signing team/provisioning profile must support HealthKit.
3. Choose an iOS 17+ iPhone and run. Simulator works for manual logging and photo-library selection, but camera and real Apple Watch/Health records require a device.
4. Open Settings → Health permissions & data → Request / review Health access. Choose which data to share. Watch sleep requires sleep tracking to be enabled and Watch data to have synced to Health.
5. Start by logging breakfast, a meal, a weigh-in and a gym session. Add foods you have at home under Settings → Food inventory.

The cloud machine is Linux. **The iOS app has not been compiled or launched with Apple's SDK here.** See the device checklist below. Code signing, provisioning and actual Health reads must be checked on macOS/device.

## What's implemented

- **Home:** Daily Coach cards with one or two actions, yesterday summary, readable sleep, targets, optional workout selection and three main quick actions; additional logging is in the top-right menu.
- **Nutrition:** dated food log, add/edit/delete meals, camera/library attachment, one-request food-photo component and nutrition estimates via OpenAI, or editable demo estimates, one primary meal suggestion with optional alternatives, and one-tap common meals.
- **Training:** today's readable Health activity first, active workout energy (never total energy), editable persistent Chest/Shoulders/Back/Legs templates, automatic previous-session lookup across English/Chinese exercise aliases, per-set weights/reps and one progression suggestion. Legacy workout editing, RPE/targets/notes, badminton dates and manual duration/active-energy fallback remain available.
- **Progress:** 28-day weight graph and 7-day moving averages, 2/4-week comparisons, nutrition adherence, live last-seven-day summary and saved summary snapshots.
- **Growth Timeline / 成长时间线:** day/week/month/year history from existing logs, period summaries and previous-month comparison, automatic/manual milestones, private front/side/back progress photos and comparison pairs, On This Day, and Markdown + photo ZIP export to Files. The Progress tab root in `RootView.swift` pins Growth Timeline navigation above the scrolling analytics and links directly to Timeline, Milestones, Photos, On This Day and Export Archive; existing charts and history remain below it. See [archive design and validation](docs/GROWTH_TIMELINE.md).
- **Settings:** goals/profile, Health/data/export, food recognition with advanced provider options, units, system/light/dark appearance, language settings, inventory and common meals.
- **HealthKit:** read steps, active energy, latest heart rate today, recent workouts, weight and sleep; manual logging remains usable without Health access. Watch data is read via HealthKit, not a separate Watch app.

## Languages

English is the fallback; Simplified Chinese (`zh-Hans`) follows the iPhone language automatically. All app labels, generated coaching/summaries and camera/Health explanations have native localization resources. User-entered text and saved snapshots stay as recorded. See [localization checks and the iPhone layout checklist](docs/LOCALIZATION.md).

## MVP rules and limits

- Each day starts with **planned** yogurt + banana + oats (200 / 120 / 60 g; about 486 kcal and 29 g protein). Mark eaten or skip it. Planned meals do not count toward intake, and breakfast cannot be logged twice. Edit an eaten breakfast in the food log.
- Nutrition estimates use typical supermarket values, not a verified food database. Check your product labels. Recipe quantities refer to edible portions; chicken and rice are cooked weights.
- Suggestions prioritize inventory matches and remaining calories/protein, with activity-sensitive portions. Weight-trend advice is displayed but targets change only when you explicitly save them in Settings. The app does not automatically add Health active calories to your calorie budget.
- **Food-photo AI:** OpenAI Responses analysis returns one practical estimate for each visible component, with grams, calories, protein, carbs and fat together. Take/choose a photo, tap Analyze, optionally edit, and Save; no required text context, confidence controls, follow-up questions or second nutrition step. Chinese mixed meals are split into visible ingredients. Optional context improves re-analysis. Editing grams rescales nutrition; editing values, adding or removing foods immediately updates totals. Demo remains clearly labelled, and API failures preserve the draft. See [API setup](docs/FOOD_PHOTO_API.md).
- One weight per calendar day; manual values override Health imports. Trend comparison needs at least four weigh-ins in each of the two comparison weeks. The four-week rate compares the first and last week and divides by three. Rates are approximate coaching suggestions.
- Gym entries group sets sharing weight/reps. Use additional rows for different loads. Progression checks completed target sets/reps and RPE, and compares per-set performance across sessions for the same exercise name. The global weekly volume flag is a rough heuristic, not a personalised plan. Heavy leg rows (RPE ≥ 8) within 48 hours of a recorded or readable Health badminton date trigger a suggestion.
- Health workouts inform activity-aware meal suggestions and badminton warnings, but stay separate from manual gym sets/badminton dates. They do not duplicate logged sessions or supply exercise-level progression; weekly session counts are explicitly manual.
- Health read denial is intentionally hidden by Apple. Empty values mean no readable samples or no permission, never proof of zero activity. Previously imported sleep/weight stays locally cached after permission revocation. Deleting an imported weigh-in does not delete it from Health; refresh may reimport it.
- Sleep merges overlapping asleep samples (Watch/iPhone duplicates) in noon-to-noon windows assigned to the waking day. In-bed/awake records are excluded; naps can contribute to the daily total. There is no manual fatigue/mood module.
- Weekly nutrition averages use **logged days**, with coverage shown. Sleep averages use available nights. No-data days are not zeros. Adherence compares past intake to your current targets, not historical target snapshots.
- Local SwiftData only. Growth Timeline can export a Markdown/photo ZIP as a manual portable archive; it is not a restorable database backup. Deleting the app can remove local logs and progress photos. There is no cloud sync, authentication, subscription or social module.

## Structure

```text
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

**Quality pass:** 126 portable XCTest cases pass on Linux. Xcode also contains 26 SwiftData tests, 2 configuration tests and 11 UI tests, all still unrun here. Persistence tests cover inverses/cascades, replacement of children, rollback, daily rollover, repeated imports, completion targets, coverage, exercise ordering and file-backed reopening. UI tests cover all five tabs, sheets/cancellation, food save/invalid-input handling and settings navigation. See [the full review](docs/MVP_REVIEW.md) for feature-by-feature coverage, fixes and known limits. These Apple-platform tests cannot execute on Linux.

Only if files are added/removed, regenerate project references using `python3 scripts/generate_project.py` (this replaces the generated project and scheme; preserve any custom signing/project settings first). Otherwise open the checked-in project directly.

## Still required on macOS / iPhone

- Build the app and run all app-hosted XCTest cases; resolve any Apple-SDK compile issues discovered there.
- Fresh launch: default profile and planned breakfast. Skip/restore/eat breakfast; verify totals update once and persist after termination/relaunch.
- Camera: approve, deny, cancel and capture; library: choose/cancel. Apply demo estimate, edit each food name, grams and nutrition value, save, reopen and delete the meal.
- API: configure your key, verify Keychain storage and a real OpenAI photo request, then test offline/invalid-key handling, cancellation and explicit demo fallback. Validate schema upgrades from any earlier installed build.
- Log an entire multi-exercise workout, edit/delete it, change units, add nearby badminton, and inspect progression/warning text.
- Enter enough daily weights for averages, inspect the chart, preview a calorie adjustment, cancel it, and confirm targets only change on Save.
- Grant all, some and no Health read types; refresh on returning to foreground. Check real Watch steps/workouts/sleep, overlapping sleep, manual weigh-in precedence and missing-data messaging.
- Verify a midnight/day rollover and a timezone change without double breakfast or daily entries. Historical days use the device's local calendar at entry time; cross-timezone history is not normalized in this MVP.
- Review the last-seven-day summary and nutrition coverage, save it, relaunch and confirm local persistence.
- Validate Growth Timeline after upgrading an existing install: original logs/photos remain intact, milestones do not duplicate, progress photos reopen locally, period navigation and Chinese layouts work, and an exported ZIP opens in Files with every referenced image. See the archive checklist.

No simulator/device behavior or real Health reads have been claimed as verified in this Linux environment.
