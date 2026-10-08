# English and Simplified Chinese

LeanLog follows the iPhone's preferred supported language automatically. It supports English (`en`, the development/fallback language) and Simplified Chinese (`zh-Hans`). There is no in-app language override. Use iPhone Settings → General → Language & Region, or the app language setting offered by iOS. Restart the app after changing its language.

Native `Localizable.strings` files contain the UI, nutrition/workout/weight coaching, generated weekly summaries, validation/errors, demo analysis and accessibility text. `InfoPlist.strings` contains the camera and Health read-purpose explanations shown by iOS. Both are included as localized Xcode variant groups. `L10n.text` resolves them through the app bundle and formats translated sentences; this includes dynamic titles, labels, service errors and computed advice that SwiftUI would otherwise treat as unlocalized Strings. Dates and displayed numbers continue to use the system locale.

Model names, property identifiers, enum raw values, API field names and canonical recipe/ingredient matching names remain English. Recipe display names and portion text are localized separately. User-entered names/notes, existing saved summary snapshots and previously saved AI estimates remain as recorded; localization does not rewrite personal logs. New summary snapshots and new demo/AI results use the current app language. The API prompt asks for localized food names and uncertainty notes while retaining English JSON field names; a third-party model may still return text in another language.

## Checks

```sh
python3 scripts/check-localization.py
bash scripts/test-core.sh
```

The checker verifies all explicit app localization keys have nonempty translations, English/Chinese key sets match, English remains the fallback, and formatting placeholders match. Six localization XCTest cases load real language bundles and cover tabs, units, multiline summary formatting, coaching/permission explanations and unknown user-text fallback. Existing coaching/API tests compare localized messages so they also work on a Chinese device. English UI tests explicitly select English, and a new Chinese UI smoke test checks the five tabs, meal/profile forms and provider settings, with screenshots for review.

Chinese tab/navigation labels are short. Shared metric labels/values and number-field labels can wrap vertically rather than clip at a fixed height. Existing forms/lists scroll; there are no new fixed row heights or single-line limits. This was reviewed in source. **Actual rendering, truncation and Dynamic Type checks still require Xcode/iOS and have not run on Linux.**

In Xcode 16.4, set the scheme's App Language to Simplified Chinese, then run the UI suite on an iPhone SE (3rd generation, 375-point width) and a current iPhone (e.g. iPhone 16, 393-point width). Review the screenshots, long explanations, number/stepper labels, provider picker, edit-food disclosures and summary at default and larger text sizes. Also run with system language selection and English to verify fallback. Permission prompt UI belongs to iOS; verify the localized camera and Health explanations on a device without previously granted permissions.
