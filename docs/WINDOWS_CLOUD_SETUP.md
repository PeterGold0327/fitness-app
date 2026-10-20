# Windows-first cloud setup

The Web/PWA is now designed to become the primary client. Existing data is preserved by default.

## Safety rules

- Existing iPhone SwiftData is not modified or deleted.
- Existing Windows `localStorage` is not cleared.
- On first cloud login, if no cloud snapshot exists, the current Windows snapshot is uploaded.
- If both cloud and Windows have data, arrays are merged instead of silently replacing local history.
- iPhone Growth Timeline exports can be imported into Windows through `archive.md`; imports are additive.

## 1. Create Supabase project

Create a private Supabase project. In the SQL Editor, run:

`/supabase/schema.sql`

This creates:

- authenticated users (Supabase Auth)
- one private JSON fitness snapshot per user
- Row Level Security so a user can only access their own snapshot
- a private storage bucket reserved for future meal/progress photos

## 2. Configure the Web app

Open `web/cloud-config.js` and set:

```js
window.DUODUO_CLOUD_CONFIG = {
  supabaseUrl: "https://<project-ref>.supabase.co",
  supabaseAnonKey: "<anon-or-publishable-key>"
};
```

Do **not** put a service-role key in browser code.

## 3. First login migration

Open the Windows Web app and use the cloud button near the top-right.

- Register/login with email + password.
- If cloud is empty, current Windows data is uploaded automatically.
- Future local saves are debounced and pushed to the cloud.
- Reload/sign-in pulls and merges cloud history.

## 4. Preserve/import the old iPhone App history

Before the free iOS signing expires, open the existing iPhone app:

`进展 → 成长时间线 → 导出成长档案`

Save the ZIP somewhere permanent (iCloud Drive / Files / Windows copy).

On Windows:

1. Extract the ZIP.
2. Click `导入 iPhone` in the Web app.
3. Choose `archive.md`.
4. The importer merges nutrition, weight, sleep, gym, and badminton history into Windows.
5. The imported data then becomes part of the cloud snapshot after login.

The ZIP's original photos are kept separately. A later photo migration can upload them to the private `fitness-private` bucket without requiring new photos.

## Current limitation

Apple Health / Apple Watch cannot be read directly from Windows browsers. Existing Health-derived history can be preserved through the exported iPhone archive. New automatic Watch ingestion still requires an iPhone-side bridge/app.
