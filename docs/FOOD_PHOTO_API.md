# Food-photo API setup

The app includes a real HTTP adapter for the OpenAI Responses API, plus a no-upload demo provider. It starts in demo mode until you configure it. No API key is shipped, placed in source, or stored in SwiftData/UserDefaults.

## Credentials to provide later

For OpenAI, provide **one OpenAI project API key** with permission to call `POST /v1/responses`. Your API project needs billing/credits and access to an image-input, Structured Outputs model, initially **`gpt-4.1-mini`**. A ChatGPT subscription does not supply API billing or a project API key. No organization ID, project ID, client secret, or custom backend is required by this adapter.

On the iPhone: **Settings → Provider & API credentials** (or **Log food → Configure provider & API key**). Choose **OpenAI**, keep or change the vision model ID, enter the key in the masked field and tap Save. Keys stay in this device's Keychain (`WhenUnlockedThisDeviceOnly`, no iCloud synchronization). An empty replacement field preserves the existing key; Remove stored key deletes it. Nonsecret provider/model preferences are stored separately. Enter keys on the device, not in repository files or chat.

For a Responses-compatible provider, supply its **exact HTTPS Responses endpoint URL**, **Bearer API key**, and **vision model ID**. Credentials are bound to that exact endpoint; changing it does not reuse another endpoint's key. The provider must support OpenAI Responses image input and strict `text.format` JSON-schema output. This option does not make arbitrary Gemini, Anthropic or other APIs wire-compatible; those need a new `FoodPhotoAnalyzing` adapter. Swapping the factory's adapter leaves meal editing/persistence unchanged.

## Upload and review flow

Choose or capture a photo, then tap **Analyze photo** once. This sends the downsampled JPEG (maximum 6 MB) and optional meal context (up to 2,000 characters) in one request. It returns one best estimate per visible component: food name, edible grams, calories, protein, carbs and fat. The result can be saved immediately; there is no required detection review, second nutrition request, confidence field, range, portion choice or follow-up question.

Mixed meals are split into visible foods rather than one generic dish. The prompt directly covers rice, broccoli, cabbage, tomato, potato, chicken, pork, beef, egg, tofu and noodles, including Chinese mixed meals. Inseparable foods such as dumplings remain one component. Typical preparation oil/sauce is included in the component's nutrition, avoiding double counting a whole dish and its ingredients. These instructions are not a verified nutrition database or a guarantee of recognition accuracy.

Generated grams are rounded to about 10 g, calories to 5 kcal and macros to whole grams. The client also applies this rounding before showing the result. Each item shows its grams and all nutrition values. Expand it to edit its name, grams or nutrition, or remove it; missing foods can be added manually. Changing grams proportionally rescales that item's current nutrition, including manual corrections. All item changes immediately recompute totals; corrections do not block Save behind a new AI request. Manual values are preserved without automatic rounding.

Text context is optional. For example, enter `这是豆腐，不是鸡肉；少油` and tap Analyze again to improve recognition. A successful re-analysis replaces the food list; failure or cancellation preserves the existing draft. Each tap makes one request and can incur another charge. Context is transient, not stored as a credential. Choosing a photo alone does not upload it.

Saving retains the photo, corrected items and order, totals and provider source. Existing confidence/notes metadata and the legacy two-step service APIs remain compatible with old records/adapters, but are not shown in the simplified result UI. API estimates, demo and fallback sources stay labelled. The request uses strict structured output and `store=false`, without tools, automatic retries or response/photo/key logging. Provider processing/retention policies still apply. There is no app backend.

## Failures and development fallback

Missing keys, authorization/billing errors, rate limiting, network failures, timeouts, refused/incomplete responses, malformed output and unusable estimates have readable errors. Failures leave the current meal draft intact so you can retry or log manually. There is no automatic retry that might create repeated billable requests. Cancel/dismiss cancels the pending analysis and prevents late results from applying.

Demo mode returns fixed chicken/rice items without reading credentials or uploading. The simplified demo action returns rounded example portions and nutrition in one result; it does not recognize the photo. The legacy nutrition adapter still preserves manually corrected items and values. **Allow labelled demo fallback** is off by default and intended for development/testing. When enabled, eligible API failures return clearly labelled demo items with the failure explanation. Invalid image/configuration and cancellation do not trigger fallback. Mock values are never presented as successful recognition.

The HTTP layer uses an ephemeral session without cookies or cache, HTTPS endpoints and redirect rejection. Error messages do not expose raw provider responses or credentials. An API key on a personal device is appropriate for this personal-use MVP; a distributed app should use a backend with server-held credentials, access controls and spending limits.

## Verification and remaining checks

`bash scripts/test-core.sh` runs 109 portable tests, including 37 food API cases. Six new cases cover one-request Chinese component estimates, practical rounding, the six-field component schema, analysis without context, optional-context re-analysis through the real factory/fallback wrapper, immediate correction/addition/removal totals, retained manual precision, invalid responses, cancellation and labelled fallback. Existing request/error/security tests and legacy two-step compatibility tests remain passing. Tests inject HTTP responses; they use no real key and make no paid API calls.

Four additional Apple-only tests cover item edit/reload/deduplication/validation and configuration persistence, credential replacement/removal and failed writes. The UI navigation suite includes the provider settings page. Run all Apple-platform tests in Xcode; Linux cannot validate SwiftUI, SwiftData migrations or actual Keychain behavior. Also verify photo upload with a real key/device, your project's model access, provider latency/cost, cancellation, and accuracy on your own meals. No live paid API call has been made in this workspace.
