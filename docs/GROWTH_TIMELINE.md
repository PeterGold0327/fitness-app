# Growth Timeline / 成长时间线

Progress now opens a four-item navigation page: **Overview**, **Growth Timeline**, **Milestones**, and **Progress Photos**. The five existing tabs remain. Overview retains the original charts, weight history, gym advice and saved weekly summaries.

## Source of truth and privacy

SwiftData continues to own meals and their foods/photos, workouts/exercises, weights, imported sleep and manual badminton dates. The timeline projects these records into temporary value types for presentation and export. No persisted daily/weekly/monthly timeline tables, meal copies, workout copies or replacement Markdown database are created. Aggregation groups records once, and summary/milestone paths avoid reading image bytes; detail screens load only photos for their selected day, and the photo browser reads only the selected angle.

Only two new SwiftData models are added: `GrowthMilestone` (archive metadata with a stable unique key) and `ProgressPhoto` (date, front/side/back angle, notes, externally stored JPEG). Meal records gain a default-empty `mealCategory` metadata field. Existing records infer breakfast/lunch/dinner/snack by local time; an existing planned-breakfast meal retains its breakfast classification. Categories can be explicitly corrected in the meal editor without changing planned-breakfast accounting or duplicating meals.

Food photos come directly from `Meal.photoData`; users do not upload them again. New progress photos are selected with the system photo picker, downsampled locally to a maximum 1400-pixel dimension, and stored in SwiftData external storage. They never enter the food-recognition service. There are no public profiles, social feeds, automatic uploads, or new network requests. iCloud/CloudKit backup and sync are future work, not currently enabled. Deleting the app can delete its private logs and photos.

The schema additions have defaults and preserve the existing store configuration. An Apple-only test checks reopening a file-backed store with the new model types. Actual upgrade migration from a previously installed app, external-photo storage and file protection must still be checked on macOS/iPhone. Storage failures show the existing error UI; they never reset or delete the store to recover.

## Calendar browsing and daily entries

Day, week, month and year boundaries use the device's current calendar/timezone and half-open intervals (start included, next period excluded). Calendar arithmetic handles daylight-saving days and month/year lengths. Historical dates follow the existing app's local-calendar behavior; cross-timezone history is not normalized. Future planned badminton dates are excluded until their date arrives; the archive says “logged” rather than claiming attendance.

A day shows available weight, a trailing seven-calendar-day weight average and sample count, readable imported sleep, meals with corrected food names and whole-portion macros/photos, daily nutrition totals, complete gym exercise rows including RPE/notes, manual badminton, progress photos and milestones. A short rule-based summary is generated from those records. Missing data remains missing. Planned/skipped breakfast is not inserted as a eaten meal. Waist measurement is left for future structured metadata.

Weekly summaries include first/last observed weight, available weigh-in average, calorie/protein averages on logged days, logged-day coverage, gym sessions, badminton days, sleep average/night coverage, exercise first/latest/best rows, and nutrition adherence. Month/year views also display weight/sleep trends, recorded days (including photos), comparison with the prior calendar period and matched-exercise best comparisons.

Calories count as adherent within ±10% of the **current** target; protein counts at or above the current target. Missing days do not lower the averages as zeros. Partial nutrition logs and changes to current targets can affect historical adherence. Starting/ending weights mean observed measurements within the selected period, not interpolated boundary weights. Available weigh-ins/nights remain separate from full calendar-day coverage.

Exercise best uses load × reps **per completed set**; extra sets alone do not create a new best. Bodyweight rows compare reps with a unit load. This is a descriptive logging score, not a strength prediction. The original exercise advice remains in Overview.

## Milestones

Automatic rules detect:

- A newly crossed whole-kilogram high/low beyond the initial observed weight.
- An exercise's new best after its first completed-session baseline.
- Four consecutive calendar weeks with at least one completed gym session each (and each further four-week block).
- Seven consecutive completed, logged days meeting both nutrition targets (and further seven-day blocks). Missing/under-target days break the streak; today is not treated as a completed day.
- The first recorded day at least one calendar month after the first source record. This means the archive spans a month, not that every day was logged.

Stable keys make saving/reloading idempotent. Source corrections, deletions and current-target changes reconcile derived milestones rather than leaving invalid achievements. Automatic titles/details are refreshed in the selected language. Manual milestones preserve the user's own dated title and notes, can be deleted, and never manufacture meal/workout records or tracking streaks.

## Photos and On This Day

Photos are browsable by angle. Comparisons use the same angle and distinct images:

- A photo in this calendar week versus one in the week four weeks earlier.
- A photo in this calendar month versus one in the month three months earlier.
- Earliest versus latest available photo.

A missing pair is shown explicitly; a distant photo is not substituted. These are visual comparisons, not automated body-composition measurements.

The optional On This Day toggle finds records with the same month/day in earlier years. It shows historical/current weight and daily summaries, gym rows, and available food/progress photos. Missing current data stays missing. February 29 matches earlier February 29 records, without silently using February 28.

## Markdown export

Choose a day/week/month/year anchored on the selected date, or the entire stored history. Photos can be included or omitted. The Files exporter writes a ZIP containing:

```
archive.md
photos/YYYY-MM-DD-meal-<meal UUID>.jpg
photos/YYYY-MM-DD-front|side|back-<photo UUID>.jpg
```

Markdown includes dated sections for body, sleep, nutrition/foods, whole-portion and daily totals, workouts/sets/reps/RPE/notes, badminton, progress photos, milestones and generated daily summaries. Selected periods also include a period summary. Each image reference points to bytes exported from its original record; UUID filenames avoid collisions and never use user-entered names as paths. User text is escaped to preserve Markdown structure. Extract the ZIP before opening `archive.md` in a Markdown viewer.

ZIP creation runs off the main actor, supports cancellation, uses standard CRC-32 checksums, and needs no external dependencies. JPEG entries are stored without extra compression. Archives larger than the standard ZIP limit must be split into shorter periods or exported without photos. Export is a user-initiated portable copy, not database restoration, import or automatic backup. The app has no new social-sharing flow. Handle exported archives as private health/photo data.

## Validation

`bash scripts/test-core.sh` passes **103 portable XCTest cases**, including **28 Growth Timeline cases** and **2 added localization cases**. These cover calendar/timezone/DST grouping, daily/week/month/year aggregation, coverage, moving averages, exercise comparisons, all milestone rules/reconciliation inputs, private-photo comparison selection, anniversary/leap dates, Markdown boundaries/escaping/photo references, ZIP framing/paths and cancellation. Existing nutrition, food-photo API, coaching and localization tests also pass.

`python3 scripts/check-localization.py` validates English/Simplified Chinese key coverage and placeholders. Independent validation opens a generated ZIP with Python's standard `zipfile` reader, verifies all CRCs, resolves every Markdown photo reference and checks original photo bytes.

To reproduce the ZIP fixture check:

```sh
TIMELINE_TEST_ARCHIVE_PATH=/tmp/growth-timeline-validation.zip bash scripts/test-core.sh
python3 - <<'PY'
import re, zipfile
with zipfile.ZipFile('/tmp/growth-timeline-validation.zip') as archive:
    assert archive.testzip() is None
    text = archive.read('archive.md').decode('utf-8')
    refs = re.findall(r'!\[[^\n]*\]\((photos/[^)]+)\)', text)
    assert len(refs) == 2 and len(archive.namelist()) == 3
    assert all(path in archive.namelist() for path in refs)
    meal = next(path for path in refs if '-meal-' in path)
    assert archive.read(meal) == bytes([1, 2, 3, 4])
    progress = next(path for path in refs if '-side-' in path)
    assert archive.read(progress) == bytes([255, 216, 255, 217])
    print('ZIP checksums and Markdown photo references verified')
PY
```

Four added SwiftData tests cover canonical record/photo reuse, milestone persistence/deduplication/deletion reconciliation, file-backed progress-photo/manual-milestone reopening, and addition of archive models to an existing file-backed store. Two added UI tests cover Progress navigation, manual milestone creation, Chinese Timeline and export controls. These Apple-platform tests were **not run on Linux**; Swift syntax parsing is not Apple-SDK compilation.

Before device use, run the app-hosted and UI suites with Xcode 16+ as documented in README. On an existing installation verify data-preserving migration, milestone correction/deletion and locale changes, local progress-photo reopening/deletion, no-photo/missing-period views, photo comparisons, and a real Files export that opens with all images. Check long histories, larger text sizes and the Chinese labels on narrow iPhones. None of those simulator/device behaviors are claimed as executed here.
