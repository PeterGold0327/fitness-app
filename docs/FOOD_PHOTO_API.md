# Food-photo API setup

The app includes a real HTTP adapter for the OpenAI Responses API, plus a no-upload demo provider. It starts in demo mode until you configure it. No API key is shipped, placed in source, or stored in SwiftData/UserDefaults.

## Credentials to provide later

For OpenAI, provide **one OpenAI project API key** with permission to call `POST /v1/responses`. Your API project needs billing/credits and access to an image-input, Structured Outputs model, initially **`gpt-4.1-mini`**. A ChatGPT subscription does not supply API billing or a project API key. No organization ID, project ID, client secret, or custom backend is required by this adapter.

On the iPhone: **Settings → Provider & API credentials** (or **Log food → Configure provider & API key**). Choose **OpenAI**, keep or change the vision model ID, enter the key in the masked field and tap Save. Keys stay in this device's Keychain (`WhenUnlockedThisDeviceOnly`, no iCloud synchronization). An empty replacement field preserves the existing key; Remove stored key deletes it. Nonsecret provider/model preferences are stored separately. Enter keys on the device, not in repository files or chat.

For a Responses-compatible provider, supply its **exact HTTPS Responses endpoint URL**, **Bearer API key**, and **vision model ID**. Credentials are bound to that exact endpoint; changing it does not reuse another endpoint's key. The provider must support OpenAI Responses image input and strict `text.format` JSON-schema output. This option does not make arbitrary Gemini, Anthropic or other APIs wire-compatible; those need a new `FoodPhotoAnalyzing` adapter. Swapping the factory's adapter leaves meal editing/persistence unchanged.

## Upload and review flow

Choosing/capturing a photo only attaches it locally. The real provider workflow now has two explicit steps:

1. **Detect / re-analyze foods** uploads the downsampled JPEG (maximum 6 MB) and optional meal context (up to 2,000 characters). It returns dish names, estimated edible grams, numeric confidence and assumptions, without nutrition. Review names and portions, remove false detections and add missing foods. Save stays disabled until nutrition is estimated or you explicitly choose to use manually corrected nutrition.
2. **Estimate nutrition for reviewed foods** sends the photo, context and your corrected names/grams/assumptions. It calculates whole-portion calories and macros. It must preserve item order, exact names and portions; responses that reintroduce removed foods, omit additions or change portions are rejected without replacing your draft. The reviewed meal title and item identities are retained.

Use context such as `这是番茄炒蛋，不是鸡肉；米饭熟重150克；少油` or `麻辣烫不喝汤`. Request detection again to change recognition, or nutrition again to account for preparation details without replacing your food list. Successful re-detection replaces your current list; failures/cancellation preserve it. Re-analysis is explicit and can incur another API charge. Context is transient in the editor, not stored as a new credential or automatically uploaded.

Chinese mixed-meal prompts cover rice with dishes, stir-fries, noodles, dumplings/buns, hotpot and malatang. They ask about hidden oils/sauces, fillings, cooked/raw weight and broth consumed, and avoid counting a whole dish together with its ingredients. These are recognition instructions, not a verified Chinese nutrition database or a guarantee of recognition accuracy. The OpenAI request uses `store=false`, strict structured output, and no tools. Provider processing/retention policies still apply; `store=false` is not a zero-retention guarantee. Responses, photos and keys are not logged by the service. API calls can incur charges.

The result includes food items, estimated grams, calories, protein, carbs, fat, per-item and overall confidence, and uncertainty notes. All values are editable before Save, and item edits recompute meal totals. Remove mistaken items or add missing items. Changing grams proportionally rescales that item's current calories and macros, including manual corrections; totals update immediately. Changing a food's identity requires estimating nutrition again, or explicitly accepting manually corrected nutrition. Additions/removals immediately change the sum of item values. Low (<0.5), medium (0.5–<0.8) and high (≥0.8) confidence labels supplement editable numeric scores. Confidence is uncalibrated; a single photo cannot reliably measure portion weight, ingredients or hidden oils. Confirm real portions/product labels.

Saving preserves corrected items and their order, totals, notes, confidence and source. API estimates and demo/fallback results remain labelled in the food log. Photos remain local meal attachments after saving; there is no app backend or automatic upload.

## Failures and development fallback

Missing keys, authorization/billing errors, rate limiting, network failures, timeouts, refused/incomplete responses, malformed output and unusable estimates have readable errors. Failures leave the current meal draft intact so you can retry or log manually. There is no automatic retry that might create repeated billable requests. Cancel/dismiss cancels the pending analysis and prevents late results from applying.

Demo mode returns fixed chicken/rice items without reading credentials or uploading. Its second step preserves your corrected items and nutrition values and explicitly says it cannot calculate nutrition from names/context; it never substitutes the original demo list for your edits. **Allow labelled demo fallback** is off by default and intended for development/testing. When enabled, eligible API failures return clearly labelled demo items with the failure explanation. Invalid image/configuration and cancellation do not trigger fallback. Mock values are never presented as successful recognition.

The HTTP layer uses an ephemeral session without cookies or cache, HTTPS endpoints and redirect rejection. Error messages do not expose raw provider responses or credentials. An API key on a personal device is appropriate for this personal-use MVP; a distributed app should use a backend with server-held credentials, access controls and spending limits.

## Verification and remaining checks

`bash scripts/test-core.sh` runs 103 portable tests, including 31 food API cases: complete parsing and computed totals, malformed/missing/negative/out-of-range data, response refusal/incompleteness/no-food, request/schema construction, HTTP failures, timeout/offline/cancellation, endpoint binding, and enabled/disabled fallback. The added tests cover separate detection/nutrition requests, Chinese mixed-meal guidance, text-context re-analysis, additions/removals/identity and portion corrections, strict preservation of the reviewed list, proportional recalculation, confidence boundaries, invalid context/reviews, cancellation and demo behavior. Tests inject HTTP responses; they use no real key and make no paid API calls.

Four additional Apple-only tests cover item edit/reload/deduplication/validation and configuration persistence, credential replacement/removal and failed writes. The UI navigation suite includes the provider settings page. Run all Apple-platform tests in Xcode; Linux cannot validate SwiftUI, SwiftData migrations or actual Keychain behavior. Also verify photo upload with a real key/device, your project's model access, provider latency/cost, cancellation, and accuracy on your own meals. No live paid API call has been made in this workspace.
