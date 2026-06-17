# Canon Webcam Linux

Set up a Canon camera as a virtual USB webcam on Kubuntu 24.04 using `gphoto2`,
`ffmpeg`, and `v4l2loopback`.

This creates a Linux video device such as `/dev/video42`. Video apps see it as a
webcam named `Canon-Webcam`, while the camera remains connected over USB in
Canon/PTP remote-control mode.

## Requirements

- Kubuntu 24.04 or Ubuntu 24.04 with a graphical user session.
- A Canon camera supported by `gphoto2` live view / movie capture.
- USB data cable, not a charge-only cable.
- Camera set to a mode that supports live view or movie capture.

For long calls, disable camera auto power-off and use AC power or a dummy
battery. Disable camera Wi-Fi mode while using USB.

## Quick Start

Run the installer as your normal desktop user:

```bash
chmod +x ./canon-webcam.sh
./canon-webcam.sh install
```

Connect and turn on the camera, then check the setup:

```bash
canon-webcam doctor
```

Run the webcam pipeline in the foreground:

```bash
canon-webcam stream
```

Open your video app and select `Canon-Webcam` or `/dev/video42`.

## Kubuntu Launchers

The installer adds three Plasma application launcher entries:

- `Start Canon Webcam`
- `Stop Canon Webcam`
- `Canon Webcam Status`

Use the application launcher menu to start and stop the systemd user service
without opening a terminal. The launcher commands show Plasma notifications for
success or failure.

Refresh the launchers without reinstalling packages:

```bash
canon-webcam install-launchers
```

Remove only the launchers:

```bash
canon-webcam remove-launchers
```

## Systemd User Service

The installer also creates and enables a systemd user service. The service keeps
the virtual webcam populated with a generated test pattern whenever Canon live
view is unavailable, so video apps can keep the same camera device selected.
Start it immediately after installing:

```bash
canon-webcam start
canon-webcam status
```

If the Canon camera is not detected or live view fails, the service keeps the
virtual webcam visible with a generated test pattern. That makes `Canon-Webcam`
appear in Zoom and other apps while you fix the camera connection.

Stop it when finished:

```bash
canon-webcam stop
```

The installer enables automatic startup. It also tries to enable systemd user
lingering so the virtual webcam can be populated after boot, before the desktop
session starts. If lingering cannot be enabled, the service starts after login.

Refresh the installed service without changing resolution:

```bash
canon-webcam install
```

Or install and start immediately:

```bash
canon-webcam install --start
```

## Custom Device or Resolution

Use a different virtual video number:

```bash
./canon-webcam.sh install --video-nr 12
```

The default stream is tuned for latency at 640x480 with a 10fps camera input
rate and a 60fps virtual webcam output rate. Many Canon bodies expose live view
through `gphoto2` at about 10fps; the loopback device repeats the newest frame
at 60fps so video apps can read from the webcam more frequently.

Stream at 720p or 1080p if you want a sharper image:

```bash
canon-webcam stream --width 1280 --height 720 --fps 30
canon-webcam stream --width 1920 --height 1080 --fps 30
```

For the lowest latency, stay on the default or set it explicitly:

```bash
canon-webcam stream --width 640 --height 480 --camera-fps 10 --fps 60
```

If your camera produces frames faster, raise `--camera-fps`. If a video app
behaves poorly with 60fps virtual input, lower `--fps` to 30.

The loopback device is configured with a short two-frame queue and non-exclusive
capabilities by default so the webcam remains visible even while the writer is
between Canon and fallback streams. If you previously installed an older config,
reload it:

```bash
canon-webcam reset-loopback
```

The service stores the width, height, camera FPS, virtual webcam FPS, loopback
buffer count, and video device chosen at install time. Re-run
`canon-webcam install` with new options to update it.

## Troubleshooting

If `canon-webcam doctor` says `/dev/video42` is missing, reboot once after
installing. If Secure Boot is enabled, Kubuntu may require enrolling the DKMS
module signing key before `v4l2loopback` can load.

If Zoom does not show `Canon-Webcam`, close Zoom, then run:

```bash
canon-webcam hard-reset
```

Reopen Zoom and check the camera list while the service is running. If the Canon
camera is unavailable, the service writes a generated test pattern so the
virtual webcam is still visible. The service keeps checking for the camera and
switches back to the Canon live view after the camera comes back online. If
Canon live view starts and then fails quickly, the service waits longer between
retries so the camera's USB/PTP session can settle.

The service keeps one persistent `ffmpeg` writer attached to the loopback
device. Canon capture and the fallback test pattern both feed that writer, so
apps such as Zoom do not have to survive the virtual webcam writer being closed
and reopened.

The stream waits for the same camera to appear across consecutive checks, then
pauses briefly before starting capture. If your camera is slow to become ready,
increase the settle delay:

```bash
CANON_WEBCAM_CAMERA_SETTLE_DELAY=5 canon-webcam install
canon-webcam restart
```

Canon capture runs continuously by default. If you need periodic capture
restarts for troubleshooting a stalled camera session, opt into timed segments:

```bash
CANON_WEBCAM_CAMERA_SEGMENT_SECONDS=30 canon-webcam install
canon-webcam restart
```

Set `CANON_WEBCAM_CAMERA_SEGMENT_SECONDS=0` to return to continuous capture.

You can also test the virtual webcam without the service:

```bash
canon-webcam test-source
```

Stop the test with `Ctrl+C`.

The reset command stops the webcam service and reloads `v4l2loopback`; it may
ask for your password through `sudo` or a graphical Kubuntu authorization
prompt.

Use `canon-webcam restart` for a normal service restart. Use
`canon-webcam hard-reset` when the whole webcam stack seems wedged: it stops the
service, clears stale `gphoto2`/`ffmpeg` capture processes started by this app,
reloads `v4l2loopback`, and starts the service again. Close Zoom, OBS, browsers,
and video settings windows first; Linux cannot unload `v4l2loopback` while a
video app is holding `/dev/video42` open.

If `canon-webcam doctor` says the camera is detected but not responding to PTP
commands, turn the camera off, unplug USB, wait a few seconds, turn the camera
back on in movie/live-view mode, and reconnect USB. If the service is already
running, it should reconnect automatically within a few seconds.

Before each capture attempt, `canon-webcam` stops common desktop camera
claimers, including GNOME/GVFS gphoto helpers and KDE KIO camera/MTP workers.
For EOS bodies such as the Canon EOS 7D Mark II, it also prepares live view with
`capturetarget=0` and `eosviewfinder=1` before starting movie capture. If that
setup causes trouble on another camera body, disable it:

```bash
canon-webcam install --no-set-viewfinder
canon-webcam restart
```

If `gphoto2` does not detect the camera, check that the USB cable carries data,
the camera is on, Wi-Fi mode is off, and the camera is in PTP/PC Remote mode if
prompted.

If another desktop component grabs the camera, the script stops common GNOME and
KDE camera helpers for the current user before streaming.

Some Canon models do not expose live-view movie capture through `gphoto2`. Those
models will still be detected by `gphoto2`, but `canon-webcam stream` will fail
when capture starts.

## Remove

```bash
canon-webcam uninstall
```

This removes the installed command, systemd user service, Plasma launchers, and
loopback config. It leaves apt packages installed.
