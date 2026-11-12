# Project structure

Where the code lives, and where new code goes. Both sides of the app, Flutter and Kotlin, are laid out
by feature.

## Flutter (`lib/`)

```
lib/
  main.dart
  app/           start-up: the gate that decides what to show, and the controller bindings
  core/          code that no single feature owns
    media/       thumbnails and bytes from the phone, the video grid, the media viewer route
    native/      the method channel to Kotlin and the device service
    permissions/ the permission prompt
    storage/     small helpers over shared preferences
    theme/       colours, spacing, radius, type, motion
    widgets/     shared widgets (search field, toast, buttons)
  features/
    collections/ home/ library/ memories/ model_download/ people/
    search/ settings/ tour/ update/ viewer/ export/
```

A feature folder holds only the folders it needs:

| Folder | Holds |
|---|---|
| `controllers/` | GetX controllers. One per feature, holding that feature's state. |
| `services/` | Calls to the native side for the feature. A service has no state. |
| `models/` | Plain data classes and the logic that works on them. |
| `db/` | SQLite stores kept on the Flutter side. |
| `view/` | Screens. |
| `view/widgets/` | Widgets used only by the feature's screens. |
| `features/` | Sub-features, each laid out the same way (for example `people/features/timeline/`). |

The controllers are `HomeController`, `AppSearchController`, `LibraryController`, `ViewerController`,
`SettingsController`, `ModelDownloadController`, `CollectionsController`, `FacesController`,
`MemoriesController`, `StoriesController`, `ExportController`, `TourController` and
`GridVideoController`. All but `ExportController` are created in `app/init_bindings.dart`, in an order that
matters: the ones that others read in `onInit` come first. A controller reaches another one with `Get.find`.

A screen watches the controllers it reads. When it reads more than one, it nests one `GetBuilder` per
controller, so a change in one controller rebuilds only the screens that show it.

A large screen or widget is split into one file per class. The main file keeps the public class and
pulls the rest in with `part`, so the private classes stay private to the library. For example
`library_tab.dart` has its pieces in `library_tab/`.

Code from another feature can be used where it is needed. It stays in the feature that owns it.

## Kotlin (`android/app/src/main/kotlin/dev/raseel/lostandfound/`)

```
MainActivity.kt   the activity: window set-up, notification taps, the folder picker's result,
                  and the router that gives each method channel call to the feature that owns it
core/
  media/          MediaChannel: thumbnails and image bytes
  native/         FeatureChannel (base of every channel), NativeExecutors (the thread pools)
  storage/        the embedding store and its record and hash helpers
features/
  collections/ export/ home/ library/ memories/ model_download/
  people/ search/ settings/ update/ viewer/
```

Each feature that answers calls from Flutter has a `<Feature>Channel` class. It extends `FeatureChannel`,
and its `handle` returns true for the calls it owns and false for the rest. `MainActivity` offers a call to
each channel in turn. Every call name belongs to exactly one channel. A channel that streams events to Flutter
also registers its event channel.

Workers, services and the notification code live in the feature they serve: scanning in `library/`, face
scanning in `people/`, the daily memory in `memories/`, the zip writer in `export/`.

The tests mirror the main folders under `android/app/src/test/kotlin/`. The debug-only bench activities are
under `android/app/src/debug/`.

## Adding a call to the native side

1. Add the method to the service of the feature on the Dart side, calling `nativeChannel`.
2. Add a branch with the same name to the `<Feature>Channel` of the feature in Kotlin.
3. If the work can block, run it on one of the pools in `NativeExecutors` and answer with `runOnUiThread`.

## Tests

The Dart tests are under `test/` and follow the folders of `lib/`. A test for `lib/features/people/view/widgets/x.dart`
is `test/features/people/view/widgets/x_test.dart`.
