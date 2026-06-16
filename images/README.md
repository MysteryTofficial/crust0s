# Crust OS — Image Assets

Place your graphic assets in this directory. The build script
(`build.sh`) automatically copies them into the correct paths
within the airootfs during ISO assembly.

Required assets:
  logo-color.png   → full-colour logo (Plymouth boot splash colour layer)
  logo-gray.png    → monochrome outline logo (Plymouth boot splash background)
  brand-icon.png   → application / branding icon
  wallpaper.png    → default desktop wallpaper

Optional assets:
  Any additional icons, backgrounds, or images placed here will
  NOT be auto-copied unless you extend the inject_assets() stage
  in `build.sh`.
