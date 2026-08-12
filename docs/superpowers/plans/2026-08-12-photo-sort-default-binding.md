# Photo Sort Default Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the device module's default photo sort use the gallery's four supported sort modes and reliably apply that default to active and newly opened galleries.

**Architecture:** Keep `SettingsStore` and `AppDataChangeBus` as the shared preference channel. Add one explicit mapping between the settings enum and `PhotoQuery.sort`, apply it after restoring a cached gallery view, and preserve gallery-local sorting as a view-only operation.

**Tech Stack:** Flutter, Dart, flutter_bloc, flutter_test, existing `SettingsStore`, `AppDataChangeBus`, and `GalleryCubit`.

---

### Task 1: Unify the settings sort model with gallery sorts

**Files:**
- Modify: `lib/bird_companion/features/settings/presentation/bird_settings_controller.dart`
- Modify: `lib/bird_companion/features/gallery/presentation/gallery_cubit.dart`
- Test: `test/bird_companion/settings/settings_components_test.dart`
- Test: `test/bird_companion/features/gallery/album_view_cache_key_test.dart`

- [ ] **Step 1: Write failing model and mapping tests**

Assert that `BirdPhotoSortOrder.values` contains `newest`, `qualityDescending`, `recommendedFirst`, and `confidenceDescending`, and that persisted names map to `captured_at_desc`, `score_desc`, `recommended_desc`, and `confidence_desc`.

- [ ] **Step 2: Run tests and verify compile or assertion failure**

Run:

```powershell
flutter test --no-pub test/bird_companion/settings/settings_components_test.dart test/bird_companion/features/gallery/album_view_cache_key_test.dart
```

Expected: FAIL because the three gallery-aligned enum values and mappings do not exist.

- [ ] **Step 3: Replace obsolete enum values and centralize mapping**

Update `BirdPhotoSortOrder` to the four approved choices. Add a mapping helper in the settings model and make `GalleryCubit` consume that helper so UI labels and query protocol cannot drift.

- [ ] **Step 4: Run focused tests**

Run the Task 1 test command again. Expected: PASS.

### Task 2: Make global default sort override cached sort only

**Files:**
- Modify: `lib/bird_companion/features/gallery/presentation/gallery_cubit.dart`
- Test: `test/bird_companion/features/gallery/album_view_cache_key_test.dart`

- [ ] **Step 1: Write failing cache-priority test**

Store a cached query with `sort: score_desc` and a search/filter value, configure settings with `recommendedFirst`, call `restoreAndRefresh`, then assert the query retains the search/filter value while using `recommended_desc`.

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```powershell
flutter test --no-pub test/bird_companion/features/gallery/album_view_cache_key_test.dart
```

Expected: FAIL because `resolveInitialPhotoQuery` currently lets cached `sort` win.

- [ ] **Step 3: Apply default sort after cache restoration**

Restore the cached query first, then overwrite only `sort` using the current settings value. Continue applying existing default filters through the current helper.

- [ ] **Step 4: Run the focused test**

Run the Task 2 test command again. Expected: PASS.

### Task 3: Verify active synchronization and UI options

**Files:**
- Modify: `test/bird_companion/settings/photo_settings_flow_test.dart`
- Modify: `test/bird_companion/features/gallery/album_view_cache_key_test.dart`
- Modify only if required by failures: `lib/bird_companion/features/settings/presentation/pages/photo_settings_page.dart`

- [ ] **Step 1: Update the widget test to select `recommendedFirst`**

Open the existing default sort sheet, assert the four approved labels are shown and obsolete filename/size labels are absent, then choose system recommendation and assert the controller value.

- [ ] **Step 2: Add an active-gallery event test**

Change the in-memory store to `confidenceDescending`, publish `photoPreferences`, and assert an existing `GalleryCubit` refreshes with `confidence_desc`.

- [ ] **Step 3: Run settings and gallery tests**

Run:

```powershell
flutter test --no-pub test/bird_companion/settings/photo_settings_flow_test.dart test/bird_companion/settings/settings_store_test.dart test/bird_companion/features/gallery/album_view_cache_key_test.dart
```

Expected: PASS.

### Task 4: Regression verification

**Files:**
- No production changes expected.

- [ ] **Step 1: Run related regression tests**

```powershell
flutter test --no-pub test/bird_companion/settings test/bird_companion/features/gallery test/bird_companion/default_entrypoint_test.dart test/bird_companion/android_flavor_isolation_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Analyze touched code**

```powershell
flutter analyze --no-pub lib/bird_companion/features/settings lib/bird_companion/features/gallery
```

Expected: no errors.

- [ ] **Step 3: Build the Android flavor used by Android Studio**

```powershell
flutter build apk --debug --flavor birdV1 -t lib/main.dart --no-pub
```

Expected: `build/app/outputs/flutter-apk/app-birdv1-debug.apk` is produced.

- [ ] **Step 4: Review the final diff and commit**

Commit only source, tests, and the two design documents. Do not commit `build/`, `.dart_tool/`, `.idea/workspace.xml`, or generated device captures.
