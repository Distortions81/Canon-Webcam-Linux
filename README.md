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

The installer also creates a systemd user service. Start it after connecting the
camera:

```bash
canon-webcam start
canon-webcam status
```

Stop it when finished:

```bash
canon-webcam stop
```

Enable automatic startup for your desktop session:

```bash
canon-webcam install --enable
```

Or install and start immediately:

```bash
canon-webcam install --enable --start
```

## Custom Device or Resolution

Use a different virtual video number:

```bash
./canon-webcam.sh install --video-nr 12
```

Stream at 1080p:

```bash
canon-webcam stream --width 1920 --height 1080 --fps 30
```

The service stores the width, height, FPS, and video device chosen at install
time. Re-run `canon-webcam install` with new options to update it.

## Troubleshooting

If `canon-webcam doctor` says `/dev/video42` is missing, reboot once after
installing. If Secure Boot is enabled, Kubuntu may require enrolling the DKMS
module signing key before `v4l2loopback` can load.

If Zoom does not show `Canon-Webcam`, close Zoom, then run:

```bash
canon-webcam reset-loopback
canon-webcam start
```

After the start command succeeds, reopen Zoom and check the camera list again.
The reset command stops the webcam service and reloads `v4l2loopback`; it may
ask for your password through `sudo` or a graphical Kubuntu authorization
prompt.

If `gphoto2` does not detect the camera, check that the USB cable carries data,
the camera is on, Wi-Fi mode is off, and the camera is in PTP/PC Remote mode if
prompted.

If another desktop component grabs the camera, the script stops
`gvfsd-gphoto2` for the current user before streaming.

Some Canon models do not expose live-view movie capture through `gphoto2`. Those
models will still be detected by `gphoto2`, but `canon-webcam stream` will fail
when capture starts.

## Remove

```bash
canon-webcam uninstall
```

This removes the installed command, systemd user service, Plasma launchers, and
loopback config. It leaves apt packages installed.
