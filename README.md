# Canon Webcam Linux

Use a Canon camera as a persistent Linux virtual webcam on Kubuntu/Ubuntu 24.04.

`canon-webcam` creates a `v4l2loopback` device such as `/dev/video42`, feeds it
from Canon USB live view through `gphoto2` and `ffmpeg`, and keeps the device
visible with a generated test pattern whenever the camera is unavailable.
Video apps see the camera as `Canon-Webcam`.

## Requirements

- Kubuntu 24.04 or Ubuntu 24.04 with a graphical user session.
- A Canon camera whose live view or movie capture works through `gphoto2`.
- A USB data cable. Charge-only cables will not work.
- Camera Wi-Fi disabled while using USB.
- Camera mode set to live view, movie, PC remote, or PTP mode as required by
  the camera body.

For long calls, disable camera auto power-off and use AC power or a dummy
battery.

## Quick Start

Run the installer as your normal desktop user:

```bash
chmod +x ./canon-webcam.sh
./canon-webcam.sh install --start
```

Connect and turn on the camera, then check the setup:

```bash
canon-webcam doctor
```

Open Zoom, OBS, a browser, or another video app and select `Canon-Webcam` or
`/dev/video42`.

## Daily Use

The installer creates a systemd user service and three Plasma launcher entries:

- `Start Canon Webcam`
- `Stop Canon Webcam`
- `Canon Webcam Status`

Terminal commands:

```bash
canon-webcam start
canon-webcam status
canon-webcam logs
canon-webcam stop
```

## Use On Demand Without Autostart

If you want to keep `canon-webcam` installed but avoid the background CPU use
when you are not on calls, disable the autostarted user service:

```bash
systemctl --user disable --now canon-webcam.service
```

This keeps the command, virtual webcam config, and desktop launchers installed.
Start the service manually when you need the camera:

```bash
canon-webcam start
```

Stop it after the call:

```bash
canon-webcam stop
```

The installer also tries to enable systemd user lingering so the service can run
after boot before you log in. If you do not need any user services before login,
disable lingering too:

```bash
sudo loginctl disable-linger "$USER"
```

Run the pipeline in the foreground when you want direct terminal output:

```bash
canon-webcam stream
```

Test only the virtual webcam device, without the Canon camera:

```bash
canon-webcam test-source
```

Stop foreground commands with `Ctrl+C`.

## What Install Does

`canon-webcam install`:

- Installs `gphoto2`, `ffmpeg`, `v4l2loopback`, `v4l-utils`, and launcher
  helpers through apt.
- Copies the command to `/usr/local/bin/canon-webcam`.
- Writes persistent `v4l2loopback` config for the selected video device.
- Installs and enables `~/.config/systemd/user/canon-webcam.service`.
- Adds the current user to the `video` group when needed.
- Tries to enable systemd user lingering so the virtual webcam can be populated
  after boot. If lingering cannot be enabled, the service starts after login.
- Installs the Kubuntu/Plasma launcher entries.

Refresh the installed command, service, and launchers after editing this repo:

```bash
./canon-webcam.sh install
```

Refresh only the launchers:

```bash
canon-webcam install-launchers
```

Remove only the launchers:

```bash
canon-webcam remove-launchers
```

## Device and Quality

The default virtual webcam is `/dev/video42` named `Canon-Webcam`.

Use a different video number:

```bash
./canon-webcam.sh install --video-nr 12
```

The default stream is 1280x720 with 12fps Canon input and 12fps virtual webcam
output. Many Canon bodies expose live view through `gphoto2` at a low frame
rate, so the default favors a real 720p image without asking `ffmpeg` to invent
extra frames.

Choose another size or rate:

```bash
canon-webcam stream --width 640 --height 480
canon-webcam stream --width 1920 --height 1080
canon-webcam stream --width 1280 --height 720 --camera-fps 12 --fps 12
```

Install-time choices are persisted into the systemd user service. Re-run
`canon-webcam install` with new options, then restart the service:

```bash
canon-webcam install --width 1280 --height 720 --camera-fps 12 --fps 12
canon-webcam restart
```

If your camera produces frames faster, raise both `--camera-fps` and `--fps`.

## How It Works

The service keeps one persistent `ffmpeg` writer attached to the loopback device.
Canon capture and the fallback test pattern both feed that writer, so video apps
do not have to survive the virtual webcam writer closing and reopening.

Before each capture attempt, the script stops common desktop camera claimers,
including GNOME/GVFS gphoto helpers and KDE KIO camera/MTP workers. For EOS
bodies such as the Canon EOS 7D Mark II, it also prepares live view with
`capturetarget=0` and `eosviewfinder=1`.

Disable that Canon EOS preparation if it causes trouble on another body:

```bash
canon-webcam install --no-set-viewfinder
canon-webcam restart
```

## Troubleshooting

Start with:

```bash
canon-webcam doctor
canon-webcam logs
```

Common fixes:

| Symptom | Try |
| --- | --- |
| `/dev/video42` is missing | Reboot once after install. If Secure Boot is enabled, enroll the DKMS module signing key when Kubuntu asks. |
| Video app does not list `Canon-Webcam` | Close Zoom, OBS, browsers, and video settings windows, then run `canon-webcam hard-reset`. |
| Loopback exists but is not writable | Run `canon-webcam reset-loopback`. Close any app holding the video device first. |
| `gphoto2` does not detect the camera | Check for a USB data cable, disable camera Wi-Fi, use the correct camera mode, and reconnect USB. |
| Camera is detected but not responding to PTP commands | Turn the camera off, unplug USB, wait a few seconds, turn it back on, then reconnect. |
| Canon capture starts and then fails quickly | Increase the settle delay or use timed segments as shown below. |

Increase the camera settle delay for slower bodies:

```bash
CANON_WEBCAM_CAMERA_SETTLE_DELAY=5 canon-webcam install
canon-webcam restart
```

Canon capture runs continuously by default. Opt into periodic capture restarts
when troubleshooting a stalled camera session:

```bash
CANON_WEBCAM_CAMERA_SEGMENT_SECONDS=30 canon-webcam install
canon-webcam restart
```

Return to continuous capture:

```bash
CANON_WEBCAM_CAMERA_SEGMENT_SECONDS=0 canon-webcam install
canon-webcam restart
```

Reload loopback config after changing the video number, label, or loopback queue:

```bash
canon-webcam reset-loopback
```

`hard-reset` stops the service, clears stale `gphoto2` and `ffmpeg` processes
started by this app, reloads `v4l2loopback`, and starts the service again.
Linux cannot unload `v4l2loopback` while another app is holding the video device
open.

Some Canon models are detected by `gphoto2` but do not expose live-view movie
capture through it. Those models will fail when capture starts.

## Remove

```bash
canon-webcam uninstall
```

Packages and any currently loaded `v4l2loopback` module are left in place.
