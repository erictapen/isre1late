pkgs:
let
  iconDir = "assets/icons/";
  inherit (pkgs.lib) concatMapStrings;
in
pkgs.writeShellScriptBin "generate-favicons.sh" (''
  mkdir -p ${iconDir}

  magick convert \
    -resize x16 \
    -gravity center \
    -crop 16x16+0+0 \
    -flatten \
    -colors 256 \
    "$1" \
    ${iconDir}/favicon-16x16.png

  magick convert \
    -resize x32 \
    -gravity center \
    -crop 32x32+0+0 \
    -flatten \
    -colors 256 \
    "$1" \
    ${iconDir}/favicon-32x32.png


  magick convert \
    -resize x16 \
    -gravity center \
    -crop 16x16+0+0 \
    -flatten \
    -colors 256 \
    "$1" \
    favicon-16x16.ico

  magick convert \
    -resize x32 \
    -gravity center \
    -crop 32x32+0+0 \
    -flatten \
    -colors 256 \
    "$1" \
    favicon-32x32.ico

  magick convert \
    -resize x48 \
    -gravity center \
    -crop 48x48+0+0 \
    -flatten \
    -colors 256 \
    "$1" \
    favicon-48x48.ico

  magick convert favicon-16x16.ico favicon-32x32.ico favicon-48x48.ico ${iconDir}/favicon.ico
  rm favicon-16x16.ico favicon-32x32.ico favicon-48x48.ico

  cp "$1" ${iconDir}/favicon.svg
  cp "$1" ${iconDir}/safari-pinned-tab.svg

'' + concatMapStrings
  ({ resize, filename }: ''
    magick convert \
      -resize x${resize} \
      "$1" \
      ${iconDir}/${filename}

  '')
  [
    { resize = "180"; filename = "apple-touch-icon.png"; }
    { resize = "180"; filename = "apple-touch-icon-180x180.png"; }
    { resize = "152"; filename = "apple-touch-icon-152x152.png"; }
    { resize = "120"; filename = "apple-touch-icon-120x120.png"; }
    { resize = "76"; filename = "apple-touch-icon-76x76.png"; }
    { resize = "60"; filename = "apple-touch-icon-60x60.png"; }
    { resize = "192"; filename = "android-chrome-192x192.png"; }
    { resize = "512"; filename = "android-chrome-512x512.png"; }
    { resize = "192"; filename = "android-chrome-maskable-192x192.png"; }
    { resize = "512"; filename = "android-chrome-maskable-512x512.png"; }
    { resize = "128"; filename = "badge-128x128.png"; }
    { resize = "144"; filename = "icon-144x144.png"; }
    { resize = "168"; filename = "icon-168x168.png"; }
    { resize = "256"; filename = "icon-256x256.png"; }
    { resize = "48"; filename = "icon-48x48.png"; }
    { resize = "72"; filename = "icon-72x72.png"; }
    { resize = "96"; filename = "icon-96x96.png"; }
    { resize = "144"; filename = "msapplication-icon-144x144.png"; }
    { resize = "150"; filename = "mstile-150x150.png"; }
    { resize = "192"; filename = "android-chrome-192x192.png"; }
    { resize = "512"; filename = "android-chrome-512x512.png"; }
    { resize = "192"; filename = "android-chrome-maskable-192x192.png"; }
    { resize = "512"; filename = "android-chrome-maskable-512x512.png"; }
  ])
