# MDM Test App

Package: `com.mdm.test`

Test app để verify các tính năng MDM: auto-launch sau boot/update, Managed Config từ AMAPI, Kiosk mode.

## Run

```bash
# Run debug trên device đang kết nối
flutter run

# Run trên device cụ thể
flutter run -d <device-id>

# Xem danh sách devices
flutter devices
```

## Build APK

```bash
# Debug
flutter build apk --debug

# Release
flutter build apk --release

# APK output
# build/app/outputs/flutter-apk/app-debug.apk
# build/app/outputs/flutter-apk/app-release.apk
```

## Install & Test

```bash
# Install lần đầu
adb install build/app/outputs/flutter-apk/app-debug.apk

# Update (trigger MY_PACKAGE_REPLACED → app tự mở)
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# Simulate boot event
adb shell am broadcast -a android.intent.action.BOOT_COMPLETED -p com.mdm.test

# Simulate MDM managed config push
adb shell am broadcast -a android.intent.action.APPLICATION_RESTRICTIONS_CHANGED -p com.mdm.test
```

## Set Device Owner (cần factory reset)

```bash
adb shell dpm set-device-owner com.mdm.test/.AdminReceiver
```
