# Node.js Android Builder

Build Node.js for Android (arm64 + arm) using GitHub Actions.

## Usage

1. Go to **Actions** tab
2. Select **"Build Node.js for Android"**
3. Click **"Run workflow"**
4. Download artifacts when build completes

## Artifacts

- `nodejs-android-arm64` — for 64-bit ARM devices
- `nodejs-android-arm` — for 32-bit ARM devices

Each package includes `node`, `npm`, `npx`, and `libc++_shared.so`.

## Install on Android

```sh
adb push . /data/local/tmp/nodejs/
adb shell chmod 755 /data/local/tmp/nodejs/bin/*
adb shell
export HOME=/data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp/nodejs/bin:$LD_LIBRARY_PATH
/data/local/tmp/nodejs/bin/node --version
```
