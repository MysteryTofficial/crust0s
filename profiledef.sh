#!/usr/bin/env bash
# shellcheck disable=SC2034
# Crust OS — archiso profile definition

iso_name="crust-os"
iso_label="CRUST_$(date +%Y%m)"
iso_publisher="Crust OS <https://crustos.org>"
iso_application="Crust OS Live/Installer"
iso_version="$(date +%Y.%m.%d)"
install_dir="crust"
buildmodes=('iso')
bootmodes=('uefi-x64.systemd-boot.esp')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/usr/local/bin/crust-hwdetect"]="0:0:755"
  ["/usr/local/bin/crust-snap-boot"]="0:0:755"
  ["/usr/local/bin/crust-update-check"]="0:0:755"
  ["/usr/local/bin/crust-update-gui"]="0:0:755"
)
