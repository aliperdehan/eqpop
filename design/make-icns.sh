#!/bin/zsh
# design/make-icns.sh: design/out/d.png (1024 px, from logo.swift) -> design/eqpop.icns
set -e
cd "$(dirname "$0")"
SET=out/eqpop.iconset
rm -rf "$SET" && mkdir -p "$SET"
for n in 16 32 128 256 512; do
    sips -z $n $n out/d.png --out "$SET/icon_${n}x${n}.png" >/dev/null
    sips -z $((n*2)) $((n*2)) out/d.png --out "$SET/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o eqpop.icns
echo "wrote design/eqpop.icns"
