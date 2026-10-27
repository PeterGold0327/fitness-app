# Personal Fitness System Architecture

This document explains the wider architecture around LeanLog and the related fitness tools. It is intended for developers and AI agents who need to understand how the different parts fit together before making changes.

## 1. System goal

The project is not only a workout logger. The intended system is a personal fitness platform that can continuously learn from historical training, nutrition, body-weight and recovery data.

The main loop is:

**Record → Store → Analyse history → Recommend → Act → Record again**

The system should become more useful as more personal data accumulates.

---

## 2. Main components

### LeanLog — iPhone app

The iPhone app in this repository is built with:

- SwiftUI
- SwiftData
- iOS 17+
- HealthKit
- OpenAI-assisted food-photo analysis

LeanLog is local-first. Its current repository implementation should not be assumed to be fully cloud-synced.

Main responsibilities:

- nutrition logging
- food-photo estimation
- gym training logging
- per-set weights, reps and RPE
- editable workout templates
- progression suggestions
- body-weight trends
- Apple Health integration
- Growth Timeline / progress history

### Windows / Web fitness interface

A separate interface is used to record and review data outside the iPhone app.

Its important behaviour is that workout data is stored at the individual-set level.

Example:

```text
Exercise: Cable Face Pull
Set 1: 12.5 kg × 10 @ RPE 7
Set 2: 12.5 kg × 10 @ RPE 7.5
Set 3: 15 kg × 10 @ RPE 8
Set 4: 15 kg × 10 @ RPE 8.5
```

This is preferable to saving only one exercise-level weight because different sets may use different loads, reps and effort levels.

### Supabase — shared cloud data layer

The wider fitness system uses Supabase as a shared data source.

Current data stored in the cloud can include:

- workout sessions
- exercises
- per-set entries
- weight
- reps
- RPE
- meals
- calories and macronutrients
- body weight
- profile targets
- workout templates
- reusable food information
- imported health data
- sleep and activity summaries

A current snapshot-based implementation stores these areas under a fitness snapshot payload.

Important principle:

**Do not assume the GitHub iPhone repository is the only source of truth for the user's real fitness history.**

The wider system may contain newer real-world data in Supabase even when the native iPhone repository still documents local SwiftData persistence.

### Apple Health / HealthKit

Health data provides recovery and activity context.

Useful signals include:

- sleep
- steps
- active energy
- heart rate
- workouts
- badminton sessions
- body weight

Health data should not automatically override manually entered gym data. It is mainly contextual unless a feature explicitly imports a supported value.

### AI Agent

The AI agent is intended to act as the analysis layer over the user's accumulated history.

The agent should not treat each question as an isolated chat prompt.

For questions involving historical fitness data, the preferred behaviour is:

1. identify the relevant real data source
2. inspect the latest available historical data
3. compare it with previous sessions or trends
4. give a personalised recommendation
5. avoid asking the user to repeat information that already exists in connected systems

Examples:

- “What weight did I use last time?” → query latest exercise history
- “What should I use today?” → compare previous sets, reps and RPE
- “Am I progressing?” → inspect multiple sessions, not one workout
- “Why was today harder?” → consider load, RPE, sleep and recent activity

---

## 3. Data flow

The intended long-term architecture is:

```text
                ┌──────────────────┐
                │   Apple Health   │
                │ sleep/activity   │
                └────────┬─────────┘
                         │
                         ▼
┌──────────────┐   ┌──────────────┐   ┌────────────────┐
│ LeanLog iOS  │──▶│   Supabase   │◀──│ Windows / Web  │
│ SwiftData    │   │ shared data  │   │ fitness UI     │
└──────┬───────┘   └──────┬───────┘   └────────────────┘
       │                  │
       │                  ▼
       │           ┌──────────────┐
       └──────────▶│   AI Agent   │
                   │ analysis +   │
                   │ suggestions  │
                   └──────────────┘
```

This is the target direction, not a claim that every arrow is already fully implemented in the current iOS codebase.

---

## 4. Training model

### Per-set data

Each set should be able to store:

- order
- weight
- repetitions
- RPE

Exercise-level summaries can be derived from set-level data, but should not replace it.

### Progressive overload logic

The system is designed mainly for hypertrophy.

It should not use a simplistic rule such as:

> top of rep range reached → always increase load

Recommendations should consider:

- previous load
- previous repetitions
- RPE
- performance across sets
- recent history
- whether the user is maintaining technique and target effort

Examples:

```text
15 kg × 10 @ RPE 8
→ likely keep load and try for more reps

15 kg × 12 @ RPE 7
→ load increase may be appropriate

15 kg × 8 @ RPE 10
→ do not automatically increase load
```

The goal is long-term progressive overload, not mandatory load increases every session.

### RPE

RPE is necessary because the same weight and rep count can represent very different difficulty levels.

A recommendation engine should treat RPE as part of the performance record rather than optional decoration.

---

## 5. Nutrition model

Nutrition logging should prefer known, confirmed information over repeated visual guessing.

The intended priority is:

1. confirmed saved food/product data
2. manual user-entered grams and nutrition
3. AI-assisted photo estimation

Frequently used foods can be stored in reusable food memory so the same product does not need to be estimated repeatedly.

Manual food weights should take priority over visual weight estimates.

---

## 6. Source-of-truth rules

When multiple systems contain related information, use these rules:

### Real workout history

Prefer the latest actual logged workout data from the live fitness data source.

### Current user targets

Prefer the latest saved profile targets.

### iPhone implementation details

Use the GitHub repository and source code.

### Recovery context

Use available Health / sleep / activity data as supporting context.

### Conflicts

If repository documentation and live cloud data disagree about real user history, do not assume the repository is newer.

The repository may describe software architecture while Supabase contains the latest real-world records.

---

## 7. Important distinction: architecture vs current implementation

There are two levels that must not be confused.

### Current LeanLog implementation

The iPhone repository is still primarily local-first and SwiftData-based.

### Wider personal fitness system

The user also has a Supabase-backed cross-device data layer and Windows/Web workflows.

Therefore:

> “LeanLog is local-only” can be true for the current iPhone repository while “the user's fitness system has cloud data” is also true.

These statements are not contradictory.

---

## 8. Recommended development direction

The highest-value next steps are:

1. define a stable shared schema for workouts, exercises, sets, meals and profile data
2. reduce duplicate local/cloud representations
3. make iPhone and Windows/Web use the same canonical identifiers where possible
4. preserve per-set history for progression analysis
5. sync Health-derived context without duplicating manual workout records
6. make AI recommendations read from structured history instead of chat memory alone
7. add clear migration rules before replacing local SwiftData with cloud-first storage

The goal should be one coherent personal fitness history rather than several independent apps that happen to track similar information.

---

## 9. Guidance for future AI agents

Before changing this project:

- read `README.md`
- read this document
- inspect the current code before assuming a feature exists
- do not assume GitHub contains the user's latest real-world training data
- if live fitness data access is available, use it for historical questions
- distinguish software architecture from user data
- do not invent sync behaviour that has not been implemented
- preserve the local-first iOS behaviour unless a migration is intentionally designed

The key principle is:

**Use the right source for the right question.**

GitHub explains the app. Supabase can contain real fitness history. Health data adds context. The AI agent should connect those sources instead of replacing them with guesses.
