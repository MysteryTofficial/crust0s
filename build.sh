#!/usr/bin/env bash
#
# build.sh — Crust OS ISO assembly script
#
# This script orchestrates the archiso build, injecting local assets
# from the project images/ directory into the airootfs overlay and
# Plymouth theme paths before invoking mkarchiso.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="${SCRIPT_DIR}"
IMAGES_DIR="${SCRIPT_DIR}/images"

# ------------------------------------------------------------------
# asset injection: copy images/ assets into the airootfs tree
# ------------------------------------------------------------------
inject_assets() {
  local airootfs_plymouth="${PROFILE_DIR}/airootfs/usr/share/plymouth/themes/crust-fade"
  local airootfs_icons="${PROFILE_DIR}/airootfs/usr/share/icons/crust-os"
  local airootfs_wallpapers="${PROFILE_DIR}/airootfs/usr/share/backgrounds/crust-os"

  # Plymouth sprite assets
  if [ -f "${IMAGES_DIR}/logo-color.png" ]; then
    cp "${IMAGES_DIR}/logo-color.png" "${airootfs_plymouth}/logo-color.png"
    echo "[+] logo-color.png → plymouth theme"
  else
    echo "[!] ${IMAGES_DIR}/logo-color.png not found — plymouth colour sprite will be missing" >&2
  fi

  if [ -f "${IMAGES_DIR}/logo-gray.png" ]; then
    cp "${IMAGES_DIR}/logo-gray.png" "${airootfs_plymouth}/logo-gray.png"
    echo "[+] logo-gray.png → plymouth theme"
  else
    echo "[!] ${IMAGES_DIR}/logo-gray.png not found — plymouth mono sprite will be missing" >&2
  fi

  # Branding icons
  if [ -f "${IMAGES_DIR}/brand-icon.png" ]; then
    cp "${IMAGES_DIR}/brand-icon.png" "${airootfs_icons}/brand-icon.png"
    echo "[+] brand-icon.png → icons"
  else
    echo "[!] brand-icon.png not found — skipping" >&2
  fi

  # Wallpaper
  if [ -f "${IMAGES_DIR}/wallpaper.png" ]; then
    cp "${IMAGES_DIR}/wallpaper.png" "${airootfs_wallpapers}/crust-os-wallpaper.png"
    echo "[+] wallpaper.png → backgrounds"
  else
    echo "[!] wallpaper.png not found — default wallpaper will be absent" >&2
  fi
}

# ------------------------------------------------------------------
# systemd-boot splash: convert logo to BMP for boot menu background
# ------------------------------------------------------------------
generate_splash_bmp() {
  local logo="${IMAGES_DIR}/logo-color.png"
  local splash_bmp_iso="${PROFILE_DIR}/efiboot/loader/splash.bmp"
  local splash_bmp_installed="${PROFILE_DIR}/airootfs/boot/loader/splash.bmp"

  if [ -f "$logo" ] && command -v convert &>/dev/null; then
    echo "==> Crust OS — generating systemd-boot splash BMP …"
    local args=()
    args+=("$logo")
    args+=("-background" "#1a1a2e")
    args+=("-gravity" "center")
    args+=("-extent" "1024x768")
    args+=("-colorspace" "sRGB")
    args+=("BMP3:${splash_bmp_iso}")
    convert "${args[@]}" 2>&1 && echo "[+] splash.bmp → ISO ESP (efiboot/loader/)"
    convert "${args[@]}" "BMP3:${splash_bmp_installed}" 2>&1 && echo "[+] splash.bmp → installed system (airootfs/boot/loader/)"
  else
    [ ! -f "$logo" ] && echo "[!] ${logo} not found — no boot splash generated" >&2
    command -v convert &>/dev/null || echo "[!] ImageMagick not installed — install with: sudo pacman -S imagemagick" >&2
  fi
}

# ------------------------------------------------------------------
# main
# ------------------------------------------------------------------
echo "==> Crust OS — injecting assets …"
inject_assets

echo "==> Crust OS — generating systemd-boot splash …"
generate_splash_bmp

# ------------------------------------------------------------------
# build COSMIC Settings panel (Rust)
# ------------------------------------------------------------------
build_cosmic_panel() {
  local panel_dir="${PROFILE_DIR}/cosmic-settings-update"
  local panel_binary_target="${panel_dir}/target/release/cosmic-settings-update"
  local airootfs_bin="${PROFILE_DIR}/airootfs/usr/bin/cosmic-settings-update"

  if [ -f "${panel_dir}/Cargo.toml" ] && command -v cargo &>/dev/null; then
    echo "==> Crust OS — building COSMIC Settings panel …"
    (cd "$panel_dir" && cargo build --release 2>&1) || {
      echo "[!] Rust panel build failed — will use YAD fallback" >&2
      return
    }
    if [ -f "$panel_binary_target" ]; then
      cp "$panel_binary_target" "$airootfs_bin"
      echo "[+] COSMIC Settings panel built and staged"
    fi
  else
    echo "[!] cargo not found or Cargo.toml missing — skipping Rust panel build" >&2
    echo "[!] The YAD-based fallback GUI will be used instead" >&2
  fi
}

build_cosmic_panel

# ------------------------------------------------------------------
# build Calamares from AUR (no longer in official repos)
# ------------------------------------------------------------------
build_calamares_aur() {
  local build_dir="/tmp/crustos-calamares-build"
  local repo_dir="${PROFILE_DIR}/localrepo"

  echo "==> Crust OS — building Calamares from AUR …"
  rm -rf "$build_dir" "$repo_dir"
  mkdir -p "$build_dir/calamares" "$repo_dir"
  # ensure build dir is writable by the unprivileged user for git+makepkg
  if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER:" "$build_dir" "$repo_dir"
  fi

  # clone AUR repo (as user if running under sudo, to keep git ownership clean)
  if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    sudo -u "$SUDO_USER" git clone --depth=1 "https://aur.archlinux.org/calamares.git" "$build_dir/calamares" 2>&1 || {
      echo "[!] Failed to clone calamares AUR — skipping" >&2
      return
    }
  else
    git clone --depth=1 "https://aur.archlinux.org/calamares.git" "$build_dir/calamares" 2>&1 || return
  fi

  # pre-install build+runtime deps (makepkg -s would need interactive sudo)
  pacman -S --noconfirm --needed \
    kcoreaddons kpmcore libpwquality qt6-declarative qt6-svg yaml-cpp \
    extra-cmake-modules libglvnd ninja qt6-tools qt6-translations \
    2>&1 || echo "[!] dep install had issues — continuing anyway" >&2

  # build as non-root user
  if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    sudo -u "$SUDO_USER" bash -c "cd '$build_dir/calamares' && PKGDEST='$repo_dir' makepkg --noconfirm 2>&1" || {
      echo "[!] calamares build failed — skipping" >&2
      return
    }
  else
    (cd "$build_dir/calamares" && PKGDEST="$repo_dir" makepkg --noconfirm 2>&1) || return
  fi

  # repo-add runs fine as root — skip debug package
  for pkg in "$repo_dir"/calamares-*.pkg.tar.zst; do
    [[ "$pkg" != *-debug-* ]] && repo-add "$repo_dir/crust-local.db.tar.gz" "$pkg" 2>&1
  done
  echo "[+] calamares built and added to local repo"
}

build_calamares_aur

# ------------------------------------------------------------------
# mkarchiso stages + manual calamares injection
# ------------------------------------------------------------------
echo "==> Crust OS — launching mkarchiso (phase 1: install) …"

WORK_DIR="/home/mysteryt/crustos-work"
AIROOTFS="${WORK_DIR}/x86_64/airootfs"
LOCAL_REPO="${PROFILE_DIR}/localrepo"

# generate pacman.conf with local repo injected
PACMAN_CONF_TMP=$(mktemp /tmp/crustos-pacman-XXXXXX.conf)
cleanup() {
  rm -f "$PACMAN_CONF_TMP"
  rm -rf /tmp/crustos-calamares-build "$LOCAL_REPO"
}
trap cleanup EXIT

{
  cat "${PROFILE_DIR}/pacman.conf"
  echo ""
  echo "[crust-local]"
  echo "SigLevel = Never"
  echo "Server = file://${LOCAL_REPO}"
} > "$PACMAN_CONF_TMP"

# purge stale calamares from pacman cache so fresh local-built package is used
rm -f /var/cache/pacman/pkg/calamares-*.pkg.tar.zst

echo "[debug] localrepo contents:" && ls -la "$LOCAL_REPO" && echo "[debug] pacman conf:" && cat "$PACMAN_CONF_TMP"

mkarchiso -v -C "$PACMAN_CONF_TMP" -w "$WORK_DIR" -o "${SCRIPT_DIR}" "${PROFILE_DIR}"
