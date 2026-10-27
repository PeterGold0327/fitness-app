# iPhone ↔ Web Sync Architecture

## Goal

Keep the existing SwiftUI / SwiftData iPhone app, add a Windows-friendly Web/PWA client, and let both clients eventually use one canonical cloud data set.

## Recommended shape

```text
Apple Watch
   ↓
Apple Health
   ↓
iPhone App ───────┐
                  │
                  ▼
            Cloud API / DB
                  ▲
                  │
Windows Web/PWA ──┘
```

Apple Health remains iPhone-only. The Web client should never pretend to read HealthKit directly.

## Canonical entities

Mirror the current SwiftData models with stable cloud IDs.

### profile
- id
- user_id
- name
- height_cm
- starting_weight_kg
- calorie_target
- protein_target
- fat_target
- updated_at

### meals
- id
- user_id
- date
- name
- calories
- protein
- carbs
- fat
- meal_category
- analysis_source
- analysis_confidence
- analysis_notes
- photo_url
- created_at
- updated_at

### food_items
- id
- meal_id
- name
- grams
- calories
- protein
- carbs
- fat
- position

### weight_entries
- id
- user_id
- day
- kilograms
- source
- updated_at

### workout_sessions
- id
- user_id
- date
- split
- name
- duration_minutes
- active_calories
- source
- updated_at

### exercise_entries
- id
- session_id
- position
- canonical_exercise_key
- name
- weight_kg
- sets
- reps_text
- rpe
- notes

### badminton_entries
- id
- user_id
- day
- duration_minutes
- active_calories
- source

### sleep_entries
- id
- user_id
- day
- hours
- source

### growth_milestones
- id
- user_id
- date
- kind
- title
- detail
- is_automatic

### progress_photos
- id
- user_id
- date
- angle
- notes
- photo_url

## Sync rules

1. Every cloud record gets a UUID independent of local database row identity.
2. Add `updated_at` and soft-delete support before two-way sync.
3. iPhone imports Apple Health data locally first, then syncs normalized records to cloud.
4. Web can edit cloud records but cannot write fake HealthKit source metadata.
5. For first release use last-write-wins for simple scalar fields; preserve child records by ID.
6. Photos use object storage and URL references.
7. B.ai/API credentials stay on a trusted backend or device keychain. Never expose secret provider keys in static Web JavaScript.
8. Keep JSON and Markdown export available even after cloud sync exists.

## Migration strategy

Do not replace SwiftData immediately.

Phase 1:
- Keep SwiftData as iPhone local cache/source.
- Add cloud IDs and a sync service.
- Upload existing local records once after user approval.

Phase 2:
- Web uses cloud directly.
- iPhone syncs incremental changes.
- Offline iPhone writes queue until network returns.

Phase 3:
- Add conflict UI only if real conflicts become common.

## Security

- Require user authentication before any cloud read/write.
- Apply row-level access rules by authenticated `user_id`.
- Do not put B.ai or any other paid provider secret in Web source code.
- Use signed upload URLs or authenticated storage rules for meal/progress photos.

## Why this structure

It lets Windows remain usable even if the sideloaded iPhone build expires, while the iPhone can still contribute the data that only Apple Health can provide.
