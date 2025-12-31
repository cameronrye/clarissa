fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### screenshots_all

```sh
[bundle exec] fastlane screenshots_all
```

Capture all screenshots (iOS + macOS)

### frame_all

```sh
[bundle exec] fastlane frame_all
```

Frame all screenshots

### marketing_all

```sh
[bundle exec] fastlane marketing_all
```

Full workflow: capture all + frame all

### export

```sh
[bundle exec] fastlane export
```

Copy screenshots to App Store directory

----


## iOS

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture iOS screenshots via UI tests

### ios frame

```sh
[bundle exec] fastlane ios frame
```

Add device frames and marketing text to iOS screenshots

### ios marketing

```sh
[bundle exec] fastlane ios marketing
```

Full iOS workflow: capture + frame

----


## Mac

### mac screenshots

```sh
[bundle exec] fastlane mac screenshots
```

Capture macOS screenshots via UI tests

### mac frame

```sh
[bundle exec] fastlane mac frame
```

Add frames and marketing text to macOS screenshots

### mac marketing

```sh
[bundle exec] fastlane mac marketing
```

Full macOS workflow: capture + frame

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
