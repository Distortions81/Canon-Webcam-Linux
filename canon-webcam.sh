#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="canon-webcam"
SERVICE_NAME="canon-webcam.service"
INSTALL_PATH="/usr/local/bin/canon-webcam"

DEFAULT_VIDEO_NR="42"
DEFAULT_CARD_LABEL="Canon-Webcam"
DEFAULT_WIDTH="640"
DEFAULT_HEIGHT="480"
DEFAULT_FPS="9"
DEFAULT_CAMERA_FPS="9"
DEFAULT_LOOPBACK_BUFFERS="2"
DEFAULT_CAMERA_RETRY_DELAY="3"
DEFAULT_CAMERA_FAILURE_DELAY="5"
DEFAULT_CAMERA_MAX_FAILURE_DELAY="5"
DEFAULT_CAMERA_SETTLE_DELAY="5"
DEFAULT_CAMERA_STABLE_CHECKS="2"
DEFAULT_CAMERA_SEGMENT_SECONDS="0"
DEFAULT_SET_VIEWFINDER="1"

VIDEO_NR="${CANON_WEBCAM_VIDEO_NR:-$DEFAULT_VIDEO_NR}"
CARD_LABEL="${CANON_WEBCAM_LABEL:-$DEFAULT_CARD_LABEL}"
WIDTH="${CANON_WEBCAM_WIDTH:-$DEFAULT_WIDTH}"
HEIGHT="${CANON_WEBCAM_HEIGHT:-$DEFAULT_HEIGHT}"
FPS="${CANON_WEBCAM_FPS:-$DEFAULT_FPS}"
CAMERA_FPS="${CANON_WEBCAM_CAMERA_FPS:-$DEFAULT_CAMERA_FPS}"
LOOPBACK_BUFFERS="${CANON_WEBCAM_LOOPBACK_BUFFERS:-$DEFAULT_LOOPBACK_BUFFERS}"
CAMERA_RETRY_DELAY="${CANON_WEBCAM_CAMERA_RETRY_DELAY:-$DEFAULT_CAMERA_RETRY_DELAY}"
CAMERA_FAILURE_DELAY="${CANON_WEBCAM_CAMERA_FAILURE_DELAY:-$DEFAULT_CAMERA_FAILURE_DELAY}"
CAMERA_MAX_FAILURE_DELAY="${CANON_WEBCAM_CAMERA_MAX_FAILURE_DELAY:-$DEFAULT_CAMERA_MAX_FAILURE_DELAY}"
CAMERA_SETTLE_DELAY="${CANON_WEBCAM_CAMERA_SETTLE_DELAY:-$DEFAULT_CAMERA_SETTLE_DELAY}"
CAMERA_STABLE_CHECKS="${CANON_WEBCAM_CAMERA_STABLE_CHECKS:-$DEFAULT_CAMERA_STABLE_CHECKS}"
CAMERA_SEGMENT_SECONDS="${CANON_WEBCAM_CAMERA_SEGMENT_SECONDS:-$DEFAULT_CAMERA_SEGMENT_SECONDS}"
SET_VIEWFINDER="${CANON_WEBCAM_SET_VIEWFINDER:-$DEFAULT_SET_VIEWFINDER}"
DEVICE="${CANON_WEBCAM_DEVICE:-}"
DEVICE_EXPLICIT=0
ENABLE_SERVICE=0
START_SERVICE=0
TEST_SOURCE_PID=""
CAMERA_GPHOTO_PID=""
LOOPBACK_WRITER_PID=""
CAMERA_FIFO=""
CAMERA_FIFO_HOLD_FD=""

log() {
  printf '[%s] %s\n' "$APP_NAME" "$*"
}

warn() {
  printf '[%s] warning: %s\n' "$APP_NAME" "$*" >&2
}

die() {
  printf '[%s] error: %s\n' "$APP_NAME" "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  canon-webcam install [--video-nr N] [--label NAME] [--width PX] [--height PX] [--fps N] [--camera-fps N] [--loopback-buffers N] [--set-viewfinder|--no-set-viewfinder] [--enable] [--start]
  canon-webcam stream  [--device /dev/videoN] [--label NAME] [--width PX] [--height PX] [--fps N] [--camera-fps N] [--loopback-buffers N] [--set-viewfinder|--no-set-viewfinder]
  canon-webcam start|stop|restart|hard-reset|status|logs|doctor|reset-loopback|test-source|install-launchers|remove-launchers|uninstall

What it does:
  install   Install packages, configure v4l2loopback, install a user service.
  stream    Run the Canon camera -> gphoto2 -> ffmpeg -> virtual webcam pipeline in the foreground.
  start     Start the systemd user service.
  stop      Stop the systemd user service.
  restart   Restart the systemd user service.
  hard-reset
            Stop service, clear this app's capture processes, reload loopback, and start service.
  status    Show the systemd user service status.
  logs      Follow service logs.
  doctor    Check dependencies, loopback device, service, and camera detection.
  reset-loopback
            Stop the service, reload v4l2loopback with sudo/pkexec, and verify it is writable.
  test-source
            Stream a generated test pattern to the virtual webcam.
  install-launchers
            Install or refresh Kubuntu/Plasma application launcher entries.
  remove-launchers
            Remove Kubuntu/Plasma application launcher entries.
  uninstall Remove files created by this script. Packages are left installed.

Defaults:
  Virtual webcam: /dev/video42
  Camera label:   Canon-Webcam
  Stream size:    640x480
  Webcam FPS:     60
  Camera FPS:     10
  Loopback queue: 2 buffers

Run install as your regular desktop user. The script will ask for sudo only for
system package and kernel module setup.
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --video-nr)
        [[ $# -ge 2 ]] || die "--video-nr requires a value"
        VIDEO_NR="$2"
        shift 2
        ;;
      --label)
        [[ $# -ge 2 ]] || die "--label requires a value"
        CARD_LABEL="$2"
        shift 2
        ;;
      --device)
        [[ $# -ge 2 ]] || die "--device requires a value"
        DEVICE="$2"
        DEVICE_EXPLICIT=1
        shift 2
        ;;
      --width)
        [[ $# -ge 2 ]] || die "--width requires a value"
        WIDTH="$2"
        shift 2
        ;;
      --height)
        [[ $# -ge 2 ]] || die "--height requires a value"
        HEIGHT="$2"
        shift 2
        ;;
      --fps)
        [[ $# -ge 2 ]] || die "--fps requires a value"
        FPS="$2"
        shift 2
        ;;
      --camera-fps)
        [[ $# -ge 2 ]] || die "--camera-fps requires a value"
        CAMERA_FPS="$2"
        shift 2
        ;;
      --loopback-buffers)
        [[ $# -ge 2 ]] || die "--loopback-buffers requires a value"
        LOOPBACK_BUFFERS="$2"
        shift 2
        ;;
      --set-viewfinder)
        SET_VIEWFINDER=1
        shift
        ;;
      --no-set-viewfinder)
        SET_VIEWFINDER=0
        shift
        ;;
      --enable)
        ENABLE_SERVICE=1
        shift
        ;;
      --start)
        START_SERVICE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done

  [[ "$VIDEO_NR" =~ ^[0-9]+$ ]] || die "--video-nr must be a number"
  [[ "$WIDTH" =~ ^[0-9]+$ ]] || die "--width must be a number"
  [[ "$HEIGHT" =~ ^[0-9]+$ ]] || die "--height must be a number"
  [[ "$FPS" =~ ^[0-9]+$ ]] || die "--fps must be a number"
  [[ "$CAMERA_FPS" =~ ^[0-9]+$ ]] || die "--camera-fps must be a number"
  [[ "$LOOPBACK_BUFFERS" =~ ^[0-9]+$ ]] || die "--loopback-buffers must be a number"
  (( FPS >= 1 )) || die "--fps must be at least 1"
  (( CAMERA_FPS >= 1 )) || die "--camera-fps must be at least 1"
  (( LOOPBACK_BUFFERS >= 2 )) || die "--loopback-buffers must be at least 2"
  [[ "$CAMERA_RETRY_DELAY" =~ ^[0-9]+$ ]] || die "CANON_WEBCAM_CAMERA_RETRY_DELAY must be a number"
  [[ "$CAMERA_FAILURE_DELAY" =~ ^[0-9]+$ ]] || die "CANON_WEBCAM_CAMERA_FAILURE_DELAY must be a number"
  [[ "$CAMERA_MAX_FAILURE_DELAY" =~ ^[0-9]+$ ]] || die "CANON_WEBCAM_CAMERA_MAX_FAILURE_DELAY must be a number"
  [[ "$CAMERA_SETTLE_DELAY" =~ ^[0-9]+$ ]] || die "CANON_WEBCAM_CAMERA_SETTLE_DELAY must be a number"
  [[ "$CAMERA_STABLE_CHECKS" =~ ^[0-9]+$ ]] || die "CANON_WEBCAM_CAMERA_STABLE_CHECKS must be a number"
  [[ "$CAMERA_SEGMENT_SECONDS" =~ ^[0-9]+$ ]] || die "CANON_WEBCAM_CAMERA_SEGMENT_SECONDS must be a number"
  [[ "$SET_VIEWFINDER" =~ ^(0|1)$ ]] || die "CANON_WEBCAM_SET_VIEWFINDER must be 0 or 1"
  (( CAMERA_RETRY_DELAY >= 1 )) || die "CANON_WEBCAM_CAMERA_RETRY_DELAY must be at least 1"
  (( CAMERA_FAILURE_DELAY >= 1 )) || die "CANON_WEBCAM_CAMERA_FAILURE_DELAY must be at least 1"
  (( CAMERA_MAX_FAILURE_DELAY >= CAMERA_FAILURE_DELAY )) || die "CANON_WEBCAM_CAMERA_MAX_FAILURE_DELAY must be greater than or equal to CANON_WEBCAM_CAMERA_FAILURE_DELAY"
  (( CAMERA_STABLE_CHECKS >= 1 )) || die "CANON_WEBCAM_CAMERA_STABLE_CHECKS must be at least 1"
  (( CAMERA_SEGMENT_SECONDS >= 0 )) || die "CANON_WEBCAM_CAMERA_SEGMENT_SECONDS must be at least 0"
  [[ "$CARD_LABEL" =~ ^[A-Za-z0-9._-]+$ ]] || die "--label may only contain letters, numbers, dots, underscores, and dashes"

  DEVICE="${DEVICE:-/dev/video${VIDEO_NR}}"
}

require_not_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    die "run this command as your regular desktop user, not with sudo"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

systemctl_user() {
  systemctl --user "$@"
}

notify_desktop() {
  local summary="$1"
  local body="$2"

  if command -v notify-send >/dev/null 2>&1 && notify-send "$summary" "$body"; then
    return
  fi

  log "$summary: $body"
}

desktop_app_dir() {
  printf '%s/applications\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
}

run_privileged() {
  local command_name="$1"
  local command_path
  shift

  command_path="$(command -v "$command_name" 2>/dev/null || true)"
  [[ -n "$command_path" ]] || die "missing command: $command_name"

  if [[ "${EUID}" -eq 0 ]]; then
    "$command_path" "$@"
    return
  fi

  if [[ -t 0 && -t 1 ]]; then
    sudo "$command_path" "$@"
    return
  fi

  if command -v pkexec >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    pkexec "$command_path" "$@"
    return
  fi

  sudo "$command_path" "$@"
}

warn_if_not_ubuntu_2404() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
      warn "this script targets Kubuntu/Ubuntu 24.04; detected ${PRETTY_NAME:-unknown OS}"
    fi
  fi
}

ensure_universe_packages_visible() {
  if apt-cache show gphoto2 v4l2loopback-dkms >/dev/null 2>&1; then
    return
  fi

  log "Refreshing apt package metadata..."
  sudo apt-get update

  if apt-cache show gphoto2 v4l2loopback-dkms >/dev/null 2>&1; then
    return
  fi

  if command -v add-apt-repository >/dev/null 2>&1; then
    log "Enabling the Ubuntu universe repository..."
    sudo add-apt-repository -y universe
    sudo apt-get update
    return
  fi

  die "Ubuntu universe packages are not visible. Enable the universe repository, then rerun install."
}

install_packages() {
  local packages=(
    gphoto2
    ffmpeg
    v4l2loopback-dkms
    v4l2loopback-utils
    v4l-utils
    desktop-file-utils
    libnotify-bin
    policykit-1
  )

  if [[ ! -e "/lib/modules/$(uname -r)/build" ]]; then
    packages+=("linux-headers-$(uname -r)")
  fi

  ensure_universe_packages_visible
  log "Installing packages: ${packages[*]}"
  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
}

install_binary() {
  local self
  self="$(readlink -f "${BASH_SOURCE[0]}")"
  log "Installing command to $INSTALL_PATH"
  run_privileged install -m 0755 "$self" "$INSTALL_PATH"
}

write_root_file() {
  local destination="$1"
  local content="$2"
  local tmp

  tmp="$(mktemp)"
  printf '%s\n' "$content" >"$tmp"
  sudo install -m 0644 "$tmp" "$destination"
  rm -f "$tmp"
}

install_loopback_config() {
  log "Writing persistent v4l2loopback configuration for $DEVICE"
  write_root_file "/etc/modules-load.d/canon-webcam.conf" "v4l2loopback"
  write_root_file \
    "/etc/modprobe.d/canon-webcam.conf" \
    "options v4l2loopback devices=1 video_nr=${VIDEO_NR} card_label=${CARD_LABEL} exclusive_caps=0 max_buffers=${LOOPBACK_BUFFERS}"
}

loopback_modprobe_args() {
  printf '%s\n' \
    "devices=1" \
    "video_nr=${VIDEO_NR}" \
    "card_label=${CARD_LABEL}" \
    "exclusive_caps=0" \
    "max_buffers=${LOOPBACK_BUFFERS}"
}

loopback_loaded() {
  lsmod | awk '$1 == "v4l2loopback" { found = 1 } END { exit !found }'
}

loopback_info() {
  v4l2-ctl --device "$DEVICE" --info 2>/dev/null || true
}

loopback_writer_ready() {
  [[ -c "$DEVICE" ]] || return 1
  command -v v4l2-ctl >/dev/null 2>&1 || return 0
  loopback_info | grep -q 'Video Output'
}

configure_loopback_runtime_controls() {
  [[ -c "$DEVICE" ]] || return
  command -v v4l2-ctl >/dev/null 2>&1 || return

  v4l2-ctl --device "$DEVICE" --set-ctrl sustain_framerate=1 >/dev/null 2>&1 || true
}

wait_for_video_device() {
  local attempt

  for attempt in {1..20}; do
    [[ -c "$DEVICE" ]] && return 0
    sleep 0.1
  done

  return 1
}

load_loopback_now() {
  local modprobe_args

  if [[ -c "$DEVICE" ]]; then
    log "Virtual webcam already exists at $DEVICE"
    return
  fi

  if loopback_loaded; then
    die "v4l2loopback is already loaded, but $DEVICE does not exist. Reboot, or stop apps using virtual cameras and run: sudo modprobe -r v4l2loopback && sudo modprobe v4l2loopback"
  fi

  log "Loading v4l2loopback as $DEVICE"
  mapfile -t modprobe_args < <(loopback_modprobe_args)
  if run_privileged modprobe v4l2loopback "${modprobe_args[@]}"; then
    wait_for_video_device || die "v4l2loopback loaded, but $DEVICE was not created"
    return
  fi

  if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    warn "Secure Boot is enabled. DKMS modules such as v4l2loopback may need Machine Owner Key enrollment before they can load."
  fi

  die "could not load v4l2loopback"
}

reset_loopback() {
  local modprobe_args was_active=0

  need_cmd sudo

  if systemctl_user is-active "$SERVICE_NAME" >/dev/null 2>&1; then
    if [[ "${CANON_WEBCAM_IN_SERVICE:-0}" == "1" ]]; then
      warn "$SERVICE_NAME is already active; resetting loopback from inside the running service"
    else
      was_active=1
      log "Stopping $SERVICE_NAME before resetting v4l2loopback"
      systemctl_user stop "$SERVICE_NAME"
    fi
  fi

  if [[ -c "$DEVICE" ]] && command -v fuser >/dev/null 2>&1 && fuser "$DEVICE" >/dev/null 2>&1; then
    warn "$DEVICE is in use. Close Zoom, OBS, browsers, and video settings windows, then run this again."
    fuser -v "$DEVICE" || true
    return 1
  fi

  if loopback_loaded; then
    log "Unloading v4l2loopback"
    if ! run_privileged modprobe -r v4l2loopback; then
      die "could not unload v4l2loopback. Close apps using virtual cameras, then rerun: canon-webcam reset-loopback"
    fi
  fi

  log "Loading v4l2loopback as writable $DEVICE"
  mapfile -t modprobe_args < <(loopback_modprobe_args)
  run_privileged modprobe v4l2loopback "${modprobe_args[@]}"

  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle || true
  fi

  wait_for_video_device || die "v4l2loopback loaded, but $DEVICE was not created"

  if ! loopback_writer_ready; then
    warn "$(loopback_info)"
    die "$DEVICE is present but is not advertising Video Output. Reboot, then run: canon-webcam start"
  fi

  log "$DEVICE is ready for ffmpeg input"

  if [[ "$was_active" -eq 1 ]]; then
    log "Restarting $SERVICE_NAME"
    systemctl_user start "$SERVICE_NAME"
  fi
}

ensure_loopback_for_writer() {
  if [[ ! -c "$DEVICE" ]]; then
    if loopback_loaded; then
      warn "$DEVICE is missing while v4l2loopback is loaded; resetting loopback"
      reset_loopback
    else
      load_loopback_now
    fi
  fi

  if ! loopback_writer_ready; then
    warn "$DEVICE is not in writable Video Output mode; resetting loopback"
    reset_loopback
  fi

  configure_loopback_runtime_controls
}

ensure_video_group() {
  if getent group video >/dev/null 2>&1 && ! id -nG "$USER" | tr ' ' '\n' | grep -qx video; then
    log "Adding $USER to the video group for webcam device access"
    sudo usermod -aG video "$USER"
    warn "log out and back in for the video group change to apply"
  fi
}

enable_user_linger() {
  if command -v loginctl >/dev/null 2>&1; then
    log "Enabling lingering so $SERVICE_NAME can keep the virtual webcam populated after boot"
    if ! loginctl enable-linger "$USER" >/dev/null 2>&1; then
      run_privileged loginctl enable-linger "$USER" || warn "could not enable lingering; $SERVICE_NAME will start after login instead of boot"
    fi
  fi
}

install_user_service() {
  local service_dir service_file tmp viewfinder_arg

  service_dir="$HOME/.config/systemd/user"
  service_file="$service_dir/$SERVICE_NAME"
  viewfinder_arg=""
  if [[ "$SET_VIEWFINDER" -eq 1 ]]; then
    viewfinder_arg=" --set-viewfinder"
  fi
  mkdir -p "$service_dir"

  tmp="$(mktemp)"
  cat >"$tmp" <<SERVICE
[Unit]
Description=Canon camera virtual webcam

[Service]
Type=simple
Environment=CANON_WEBCAM_IN_SERVICE=1
Environment=CANON_WEBCAM_CAMERA_RETRY_DELAY=${CAMERA_RETRY_DELAY}
Environment=CANON_WEBCAM_CAMERA_FAILURE_DELAY=${CAMERA_FAILURE_DELAY}
Environment=CANON_WEBCAM_CAMERA_MAX_FAILURE_DELAY=${CAMERA_MAX_FAILURE_DELAY}
Environment=CANON_WEBCAM_CAMERA_SETTLE_DELAY=${CAMERA_SETTLE_DELAY}
Environment=CANON_WEBCAM_CAMERA_STABLE_CHECKS=${CAMERA_STABLE_CHECKS}
Environment=CANON_WEBCAM_CAMERA_SEGMENT_SECONDS=${CAMERA_SEGMENT_SECONDS}
Environment=CANON_WEBCAM_CAMERA_FPS=${CAMERA_FPS}
Environment=CANON_WEBCAM_SET_VIEWFINDER=${SET_VIEWFINDER}
ExecStart=${INSTALL_PATH} stream --device ${DEVICE} --label ${CARD_LABEL} --width ${WIDTH} --height ${HEIGHT} --fps ${FPS} --camera-fps ${CAMERA_FPS} --loopback-buffers ${LOOPBACK_BUFFERS}${viewfinder_arg}
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
SERVICE

  install -m 0644 "$tmp" "$service_file"
  rm -f "$tmp"

  log "Installed user service at $service_file"
  if ! systemctl_user daemon-reload; then
    warn "systemctl --user daemon-reload failed. Log into a graphical session and run it again."
  fi
}

ensure_runtime_installed_current() {
  local self

  self="$(readlink -f "${BASH_SOURCE[0]}")"
  if [[ "$self" == "$INSTALL_PATH" ]]; then
    return
  fi

  if [[ -x "$INSTALL_PATH" ]] && cmp -s "$self" "$INSTALL_PATH"; then
    install_user_service
    return
  fi

  warn "installed command is not current; updating $INSTALL_PATH before starting"
  install_binary
  install_user_service
  install_desktop_launchers
}

write_desktop_launcher() {
  local filename="$1"
  local name="$2"
  local comment="$3"
  local exec_args="$4"
  local icon="$5"
  local app_dir tmp

  app_dir="$(desktop_app_dir)"
  mkdir -p "$app_dir"

  tmp="$(mktemp)"
  cat >"$tmp" <<DESKTOP
[Desktop Entry]
Type=Application
Name=${name}
Comment=${comment}
Exec=${INSTALL_PATH} ${exec_args}
Icon=${icon}
Terminal=false
Categories=AudioVideo;Video;
StartupNotify=false
DESKTOP

  install -m 0644 "$tmp" "$app_dir/$filename"
  rm -f "$tmp"
}

refresh_desktop_launchers() {
  local app_dir
  app_dir="$(desktop_app_dir)"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$app_dir" >/dev/null 2>&1 || true
  fi

  if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
  elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    kbuildsycoca5 >/dev/null 2>&1 || true
  fi
}

install_desktop_launchers() {
  if [[ ! -x "$INSTALL_PATH" ]]; then
    warn "launchers point to $INSTALL_PATH, but that command is not installed yet"
  fi

  write_desktop_launcher \
    "canon-webcam-start.desktop" \
    "Start Canon Webcam" \
    "Start the Canon camera virtual webcam service" \
    "launcher-start" \
    "camera-web"

  write_desktop_launcher \
    "canon-webcam-stop.desktop" \
    "Stop Canon Webcam" \
    "Stop the Canon camera virtual webcam service" \
    "launcher-stop" \
    "media-playback-stop"

  write_desktop_launcher \
    "canon-webcam-status.desktop" \
    "Canon Webcam Status" \
    "Show whether the Canon camera virtual webcam service is running" \
    "launcher-status" \
    "dialog-information"

  refresh_desktop_launchers
  log "Installed application launchers in $(desktop_app_dir)"
}

remove_desktop_launchers() {
  local app_dir
  app_dir="$(desktop_app_dir)"

  rm -f \
    "$app_dir/canon-webcam-start.desktop" \
    "$app_dir/canon-webcam-stop.desktop" \
    "$app_dir/canon-webcam-status.desktop"

  refresh_desktop_launchers
  log "Removed application launchers from $app_dir"
}

install_all() {
  require_not_root
  warn_if_not_ubuntu_2404
  need_cmd sudo

  if [[ "$DEVICE_EXPLICIT" -eq 1 ]]; then
    [[ "$DEVICE" =~ ^/dev/video([0-9]+)$ ]] || die "install --device must look like /dev/video42"
    VIDEO_NR="${BASH_REMATCH[1]}"
  fi

  log "Requesting sudo once for package and kernel module setup"
  sudo -v

  install_packages
  install_binary
  install_loopback_config
  load_loopback_now
  ensure_video_group
  enable_user_linger
  install_user_service
  install_desktop_launchers

  log "Enabling $SERVICE_NAME"
  systemctl_user enable "$SERVICE_NAME"

  if [[ "$START_SERVICE" -eq 1 ]]; then
    log "Starting $SERVICE_NAME"
    service_start
  fi

  log "Install complete. Connect the camera by USB, set it to movie/live-view capable mode, then run: canon-webcam doctor"
  log "Kubuntu launchers are available as Start Canon Webcam, Stop Canon Webcam, and Canon Webcam Status."
}

stop_camera_mount_helpers() {
  local name name_pattern pattern
  local names=(
    gvfsd-gphoto2
    gvfs-gphoto2-volume-monitor
    PTPCamera
  )
  local patterns=(
    'kioworker.*(camera|gphoto|mtp|ptp)'
    'kio_.*(camera|gphoto|mtp|ptp)'
  )

  for name in "${names[@]}"; do
    name_pattern="(^|/)${name}([[:space:]]|$)"
    if pgrep -u "$USER" -f "$name_pattern" >/dev/null 2>&1; then
      log "Stopping $name so gphoto2 can claim the camera"
      pkill -u "$USER" -f "$name_pattern" || true
    fi
  done

  for pattern in "${patterns[@]}"; do
    if pgrep -u "$USER" -f "$pattern" >/dev/null 2>&1; then
      log "Stopping KDE camera worker matching: $pattern"
      pkill -u "$USER" -f "$pattern" || true
    fi
  done
}

camera_detected() {
  gphoto2 --auto-detect | awk 'NR > 2 && NF { found = 1 } END { exit !found }'
}

camera_detect_line() {
  gphoto2 --auto-detect | awk 'NR > 2 && NF { print; exit }'
}

camera_wait_stable() {
  local attempt current previous=""

  for (( attempt = 1; attempt <= CAMERA_STABLE_CHECKS; attempt++ )); do
    current="$(camera_detect_line)"
    if [[ -z "$current" ]]; then
      return 1
    fi

    if [[ -n "$previous" && "$current" != "$previous" ]]; then
      return 1
    fi

    previous="$current"
    if (( attempt < CAMERA_STABLE_CHECKS )); then
      sleep 1
    fi
  done

  if (( CAMERA_SETTLE_DELAY > 0 )); then
    log "Camera detected; waiting ${CAMERA_SETTLE_DELAY}s for USB/PTP to settle"
    sleep "$CAMERA_SETTLE_DELAY"
  fi
}

camera_set_config() {
  local config="$1"

  timeout 5 gphoto2 --set-config "$config" >/dev/null 2>&1 || true
}

camera_prepare_live_view() {
  if [[ "$SET_VIEWFINDER" -ne 1 ]]; then
    return
  fi

  log "Preparing Canon EOS live view"
  camera_set_config capturetarget=0
  camera_set_config eosviewfinder=1
}

terminate_process() {
  local pid="$1"

  [[ -n "$pid" ]] || return
  kill "$pid" >/dev/null 2>&1 || true
  sleep 0.5
  kill -KILL "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
}

stop_orphaned_test_source_feeders() {
  local pattern

  command -v pkill >/dev/null 2>&1 || return
  pattern="ffmpeg .*testsrc2=size=${WIDTH}x${HEIGHT}:rate=${CAMERA_FPS}.* -f image2pipe /tmp/tmp"
  pkill -TERM -f "$pattern" >/dev/null 2>&1 || true
  sleep 0.5
  pkill -KILL -f "$pattern" >/dev/null 2>&1 || true
}

stop_orphaned_stream_processes() {
  local pattern
  local patterns=(
    "gphoto2 --stdout --capture-movie"
    "ffmpeg .* -f v4l2 ${DEVICE}"
    "ffmpeg .*testsrc2=size=${WIDTH}x${HEIGHT}:rate=.* -f image2pipe /tmp/tmp"
  )

  command -v pkill >/dev/null 2>&1 || return

  for pattern in "${patterns[@]}"; do
    pkill -TERM -f "$pattern" >/dev/null 2>&1 || true
  done

  sleep 0.5

  for pattern in "${patterns[@]}"; do
    pkill -KILL -f "$pattern" >/dev/null 2>&1 || true
  done
}

run_test_source_ffmpeg() {
  ffmpeg \
    -hide_banner \
    -loglevel warning \
    -re \
    -f lavfi \
    -i "testsrc2=size=${WIDTH}x${HEIGHT}:rate=${FPS}" \
    -vf format=yuv420p \
    -f v4l2 \
    "$DEVICE"
}

run_test_source_feeder_ffmpeg() {
  ffmpeg \
    -hide_banner \
    -y \
    -loglevel error \
    -nostdin \
    -re \
    -f lavfi \
    -i "testsrc2=size=${WIDTH}x${HEIGHT}:rate=${CAMERA_FPS}" \
    -vf format=yuvj420p \
    -vcodec mjpeg \
    -q:v 5 \
    -f image2pipe \
    "$CAMERA_FIFO"
}

start_loopback_writer() {
  if [[ -n "${LOOPBACK_WRITER_PID:-}" ]] && kill -0 "$LOOPBACK_WRITER_PID" >/dev/null 2>&1; then
    return
  fi

  stop_orphaned_test_source_feeders

  CAMERA_FIFO="$(mktemp -u)"
  mkfifo "$CAMERA_FIFO"

  exec {CAMERA_FIFO_HOLD_FD}<>"$CAMERA_FIFO"

  log "Starting persistent ffmpeg writer for $DEVICE at ${WIDTH}x${HEIGHT}/${FPS}fps output"
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostdin \
    -fflags nobuffer \
    -flags low_delay \
    -avioflags direct \
    -probesize 32 \
    -analyzeduration 0 \
    -fpsprobesize 0 \
    -f image2pipe \
    -vcodec mjpeg \
    -framerate "$CAMERA_FPS" \
    -thread_queue_size 1 \
    -i "$CAMERA_FIFO" \
    -filter_threads 1 \
    -vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2,format=yuv420p" \
    -r "$FPS" \
    -vcodec rawvideo \
    -pix_fmt yuv420p \
    -f v4l2 \
    "$DEVICE" &
  LOOPBACK_WRITER_PID="$!"

  sleep 0.5
  if ! kill -0 "$LOOPBACK_WRITER_PID" >/dev/null 2>&1; then
    stop_camera_stream_processes
    die "ffmpeg writer exited before it could write to $DEVICE"
  fi
}

start_background_test_source() {
  start_loopback_writer

  if [[ -n "${TEST_SOURCE_PID:-}" ]] && kill -0 "$TEST_SOURCE_PID" >/dev/null 2>&1; then
    return
  fi

  stop_background_test_source
  log "Keeping $DEVICE visible with a generated test pattern at ${WIDTH}x${HEIGHT}/${FPS}fps"
  run_test_source_feeder_ffmpeg &
  TEST_SOURCE_PID="$!"
}

stop_background_test_source() {
  if [[ -n "${TEST_SOURCE_PID:-}" ]]; then
    terminate_process "$TEST_SOURCE_PID"
    TEST_SOURCE_PID=""
  fi

  stop_orphaned_test_source_feeders

  if [[ -n "${CAMERA_FIFO:-}" ]] && command -v pkill >/dev/null 2>&1; then
    pkill -TERM -f "ffmpeg .*testsrc2=size=${WIDTH}x${HEIGHT}:rate=${CAMERA_FPS}.* ${CAMERA_FIFO}" >/dev/null 2>&1 || true
  fi
}

stream_test_source() {
  need_cmd ffmpeg

  ensure_loopback_for_writer
  log "Streaming generated test pattern to $DEVICE at ${WIDTH}x${HEIGHT}/${FPS}fps"
  log "Open Zoom and select '${CARD_LABEL}' or '$DEVICE'. Press Ctrl+C to stop."

  run_test_source_ffmpeg
}

stop_camera_stream_processes() {
  stop_background_test_source

  if [[ -n "${CAMERA_GPHOTO_PID:-}" ]]; then
    terminate_process "$CAMERA_GPHOTO_PID"
  fi

  if [[ -n "${CAMERA_FIFO_HOLD_FD:-}" ]]; then
    eval "exec ${CAMERA_FIFO_HOLD_FD}>&-"
    CAMERA_FIFO_HOLD_FD=""
  fi

  if [[ -n "${LOOPBACK_WRITER_PID:-}" ]]; then
    terminate_process "$LOOPBACK_WRITER_PID"
  fi

  CAMERA_GPHOTO_PID=""
  LOOPBACK_WRITER_PID=""

  if [[ -n "${CAMERA_FIFO:-}" ]]; then
    rm -f "$CAMERA_FIFO"
    CAMERA_FIFO=""
  fi
}

run_camera_stream_once() {
  local status

  start_loopback_writer

  if (( CAMERA_SEGMENT_SECONDS == 0 )); then
    gphoto2 --stdout --capture-movie >"$CAMERA_FIFO" &
  else
    gphoto2 --stdout "--capture-movie=${CAMERA_SEGMENT_SECONDS}s" >"$CAMERA_FIFO" &
  fi
  CAMERA_GPHOTO_PID="$!"

  if wait "$CAMERA_GPHOTO_PID"; then
    status=0
  else
    status="$?"
  fi

  CAMERA_GPHOTO_PID=""
  return "$status"
}

cleanup_stream() {
  trap - EXIT INT TERM
  stop_camera_stream_processes
}

stream_camera() {
  local backoff_delay="$CAMERA_FAILURE_DELAY"
  local normal_segment_min retry_after started_at status stream_duration

  need_cmd gphoto2
  need_cmd ffmpeg

  [[ -c "$DEVICE" ]] || die "$DEVICE does not exist. Run 'canon-webcam install' and reboot if the loopback module was just built."
  ensure_loopback_for_writer

  trap cleanup_stream EXIT
  trap 'cleanup_stream; exit 0' INT TERM

  log "Select '${CARD_LABEL}' or '$DEVICE' in your video app. Press Ctrl+C to stop foreground streaming."
  start_background_test_source

  while true; do
    stop_camera_mount_helpers

    if ! camera_wait_stable; then
      warn "no stable gphoto2-compatible camera detected; retrying in ${CAMERA_RETRY_DELAY}s"
      start_background_test_source
      sleep "$CAMERA_RETRY_DELAY"
      continue
    fi

    stop_camera_mount_helpers
    camera_prepare_live_view
    stop_camera_mount_helpers

    stop_background_test_source

    if (( CAMERA_SEGMENT_SECONDS == 0 )); then
      log "Streaming Canon live view to $DEVICE at ${WIDTH}x${HEIGHT}/${CAMERA_FPS}fps camera input, ${FPS}fps webcam output"
      started_at="$(date +%s)"

      if run_camera_stream_once; then
        status=0
      else
        status="$?"
      fi

      stream_duration=$(( $(date +%s) - started_at ))
    else
      normal_segment_min=1
      if (( CAMERA_SEGMENT_SECONDS > 1 )); then
        normal_segment_min=$(( CAMERA_SEGMENT_SECONDS - 1 ))
      fi

      while true; do
        log "Streaming Canon live view to $DEVICE at ${WIDTH}x${HEIGHT}/${CAMERA_FPS}fps camera input, ${FPS}fps webcam output"
        started_at="$(date +%s)"

        if run_camera_stream_once; then
          status=0
        else
          status="$?"
        fi

        stream_duration=$(( $(date +%s) - started_at ))
        if [[ "$status" -eq 0 && "$stream_duration" -ge "$normal_segment_min" ]]; then
          backoff_delay="$CAMERA_FAILURE_DELAY"
          log "Canon segment ended after ${stream_duration}s; restarting capture immediately"
          continue
        fi

        break
      done
    fi

    if (( stream_duration >= 60 )); then
      backoff_delay="$CAMERA_FAILURE_DELAY"
    fi

    retry_after="$backoff_delay"
    if [[ "$status" -eq 0 ]]; then
      warn "Canon stream ended after ${stream_duration}s; retrying in ${retry_after}s"
    else
      warn "Canon stream failed with status $status after ${stream_duration}s; retrying in ${retry_after}s"
    fi

    if (( stream_duration < 60 )); then
      backoff_delay=$(( backoff_delay * 2 ))
      if (( backoff_delay > CAMERA_MAX_FAILURE_DELAY )); then
        backoff_delay="$CAMERA_MAX_FAILURE_DELAY"
      fi
    fi

    start_background_test_source
    sleep "$retry_after"
  done
}

service_start() {
  ensure_runtime_installed_current

  if systemctl_user is-active "$SERVICE_NAME" >/dev/null 2>&1; then
    return 0
  fi

  ensure_loopback_for_writer
  systemctl_user reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
  systemctl_user start "$SERVICE_NAME"
}

service_stop() {
  systemctl_user stop "$SERVICE_NAME"
}

service_restart() {
  service_stop >/dev/null 2>&1 || true
  service_start
}

service_hard_reset() {
  log "Stopping $SERVICE_NAME"
  service_stop >/dev/null 2>&1 || true

  log "Clearing stale Canon webcam capture processes"
  stop_orphaned_stream_processes

  log "Reloading v4l2loopback for $DEVICE"
  reset_loopback

  log "Starting $SERVICE_NAME"
  service_start
}

service_status() {
  systemctl_user status "$SERVICE_NAME" --no-pager
}

service_logs() {
  journalctl --user -u "$SERVICE_NAME" -f
}

launcher_start() {
  if service_start; then
    notify_desktop "Canon Webcam" "Started. Select ${CARD_LABEL} in your video app."
  else
    notify_desktop "Canon Webcam" "Start failed. Run canon-webcam logs for details."
    return 1
  fi
}

launcher_stop() {
  if service_stop; then
    notify_desktop "Canon Webcam" "Stopped."
  else
    notify_desktop "Canon Webcam" "Stop failed. Run canon-webcam status for details."
    return 1
  fi
}

launcher_status() {
  local service_file="$HOME/.config/systemd/user/$SERVICE_NAME"

  if systemctl_user is-active "$SERVICE_NAME" >/dev/null 2>&1; then
    notify_desktop "Canon Webcam" "Running. Select ${CARD_LABEL} in your video app."
  elif [[ -f "$service_file" ]]; then
    notify_desktop "Canon Webcam" "Stopped."
  else
    notify_desktop "Canon Webcam" "Not installed. Run canon-webcam install first."
    return 1
  fi
}

doctor() {
  local problems=0
  local service_file="$HOME/.config/systemd/user/$SERVICE_NAME"
  local service_active=0
  local self
  local v4l_output=""

  if systemctl_user is-active "$SERVICE_NAME" >/dev/null 2>&1; then
    service_active=1
  fi

  printf 'System:\n'
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    printf '  OS: %s\n' "${PRETTY_NAME:-unknown}"
  fi
  printf '  Kernel: %s\n' "$(uname -r)"

  printf '\nCommands:\n'
  for cmd in gphoto2 ffmpeg v4l2-ctl; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '  ok: %s -> %s\n' "$cmd" "$(command -v "$cmd")"
    else
      printf '  missing: %s\n' "$cmd"
      problems=1
    fi
  done

  self="$(readlink -f "${BASH_SOURCE[0]}")"
  if [[ "$self" != "$INSTALL_PATH" ]]; then
    if [[ -x "$INSTALL_PATH" ]] && cmp -s "$self" "$INSTALL_PATH"; then
      printf '  ok: installed command is current -> %s\n' "$INSTALL_PATH"
    elif [[ -x "$INSTALL_PATH" ]]; then
      printf '  missing: installed command differs from this script; run ./canon-webcam.sh install\n'
      problems=1
    else
      printf '  missing: installed command is not present; run ./canon-webcam.sh install\n'
      problems=1
    fi
  fi

  printf '\nLoopback:\n'
  if loopback_loaded; then
    printf '  ok: v4l2loopback module is loaded\n'
  else
    printf '  missing: v4l2loopback module is not loaded\n'
    problems=1
  fi

  if [[ -c "$DEVICE" ]]; then
    printf '  ok: %s exists\n' "$DEVICE"
  else
    printf '  missing: %s does not exist\n' "$DEVICE"
    problems=1
  fi

  if [[ -c "$DEVICE" ]] && command -v v4l2-ctl >/dev/null 2>&1; then
    if v4l2-ctl --device "$DEVICE" --get-fmt-video >/dev/null 2>&1; then
      printf '  ok: %s has an active video format\n' "$DEVICE"
    elif loopback_writer_ready; then
      printf '  ok: %s is ready for ffmpeg input\n' "$DEVICE"
    else
      printf '  missing: %s is not writable by ffmpeg; run canon-webcam reset-loopback\n' "$DEVICE"
      problems=1
    fi
  fi

  if command -v v4l2-ctl >/dev/null 2>&1; then
    printf '\nVideo devices:\n'
    if v4l_output="$(v4l2-ctl --list-devices 2>&1)"; then
      printf '%s\n' "$v4l_output"
    else
      printf '  unavailable: %s\n' "$v4l_output"
    fi
  fi

  printf '\nCamera:\n'
  if command -v gphoto2 >/dev/null 2>&1; then
    if [[ "$service_active" -eq 1 ]]; then
      printf '  skipped: %s is active and may own the camera PTP session\n' "$SERVICE_NAME"
      printf '  hint: run canon-webcam logs to inspect live capture, or stop the service before direct gphoto2 checks\n'
    else
      gphoto2 --auto-detect || true
      if camera_detected; then
        printf '  ok: gphoto2 sees a camera\n'
        if timeout 8 gphoto2 --summary >/dev/null 2>&1; then
          printf '  ok: camera responds to PTP commands\n'
        else
          printf '  missing: camera is detected but not responding to PTP commands; power-cycle it and reconnect USB\n'
          problems=1
        fi
      else
        printf '  missing: gphoto2 does not see a camera\n'
        problems=1
      fi
    fi
  else
    printf '  skipped: gphoto2 is not installed\n'
  fi

  printf '\nService:\n'
  if [[ -f "$service_file" ]]; then
    systemctl_user is-enabled "$SERVICE_NAME" >/dev/null 2>&1 && printf '  enabled: yes\n' || printf '  enabled: no\n'
    [[ "$service_active" -eq 1 ]] && printf '  active: yes\n' || printf '  active: no\n'
  else
    printf '  missing: %s is not installed\n' "$SERVICE_NAME"
  fi

  if [[ "$problems" -ne 0 ]]; then
    return 1
  fi
}

uninstall_all() {
  require_not_root
  need_cmd sudo

  systemctl_user stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  systemctl_user disable "$SERVICE_NAME" >/dev/null 2>&1 || true
  rm -f "$HOME/.config/systemd/user/$SERVICE_NAME"
  systemctl_user daemon-reload >/dev/null 2>&1 || true
  remove_desktop_launchers

  sudo rm -f \
    "$INSTALL_PATH" \
    /etc/modules-load.d/canon-webcam.conf \
    /etc/modprobe.d/canon-webcam.conf

  log "Removed installed files. Packages and any loaded v4l2loopback module were left in place."
}

main() {
  local command="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  parse_args "$@"

  case "$command" in
    install)
      install_all
      ;;
    stream)
      stream_camera
      ;;
    start)
      service_start
      ;;
    stop)
      service_stop
      ;;
    restart)
      service_restart
      ;;
    hard-reset)
      service_hard_reset
      ;;
    status)
      service_status
      ;;
    logs)
      service_logs
      ;;
    doctor)
      doctor
      ;;
    reset-loopback)
      reset_loopback
      ;;
    test-source)
      stream_test_source
      ;;
    install-launchers)
      install_desktop_launchers
      ;;
    remove-launchers)
      remove_desktop_launchers
      ;;
    launcher-start)
      launcher_start
      ;;
    launcher-stop)
      launcher_stop
      ;;
    launcher-status)
      launcher_status
      ;;
    uninstall)
      uninstall_all
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      usage >&2
      die "unknown command: $command"
      ;;
  esac
}

main "$@"
