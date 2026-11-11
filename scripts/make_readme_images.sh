#!/bin/zsh
# Regenerates the README's comparison images from docs/images/demo-photo.jpg — a CC0 (public domain)
# photo by Nilo Velez from the WordPress.org Photos directory, metadata stripped.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product emulsion-cli >/dev/null
B=.build/release/emulsion-cli
IN=docs/images/demo-photo.jpg
T=$(mktemp -d)
dev() { local out=$1 stock=$2; shift 2; $B develop $IN $stock $T/x "$@" >/dev/null; mv $T/x/$stock.jpg $T/$out.jpg; }
for s in portra400 ektar100 gold200 superia400 cinestill800t vision250d e100 velvia50 kodachrome64 trix400 hp5 acros100; do dev $s $s; done
swift scripts/contact_sheet.swift docs/images/film-stocks.jpg 4 600 \
  "Kodak Portra 400=$T/portra400.jpg" "Kodak Ektar 100=$T/ektar100.jpg" "Kodak Gold 200=$T/gold200.jpg" "Fujifilm Superia 400=$T/superia400.jpg" \
  "CineStill 800T=$T/cinestill800t.jpg" "Kodak Vision3 250D=$T/vision250d.jpg" "Kodak Ektachrome E100=$T/e100.jpg" "Fujifilm Velvia 100=$T/velvia50.jpg" \
  "Kodak Kodachrome 64=$T/kodachrome64.jpg" "Kodak Tri-X 400=$T/trix400.jpg" "Ilford HP5 Plus=$T/hp5.jpg" "Fujifilm Acros 100 II=$T/acros100.jpg"
dev trix_red trix400 --filter red25
dev velvia_xpro velvia50 --xpro
dev portra_red portra400 --redscale
dev portra_old portra400 --age 20 --storage room
dev trix_stand trix400 --agitation stand
dev portra_scan portra400 --scan
swift scripts/contact_sheet.swift docs/images/techniques.jpg 3 640 \
  "Original (CC0 photo)=$IN" "Tri-X · red 25 filter=$T/trix_red.jpg" "Tri-X · stand development=$T/trix_stand.jpg" \
  "Velvia · cross-processed C-41=$T/velvia_xpro.jpg" "Portra · redscale=$T/portra_red.jpg" "Portra · 20 years expired=$T/portra_old.jpg"
dev portra_m2 portra400 --ev -2
dev portra_p2 portra400 --ev 2
swift scripts/contact_sheet.swift docs/images/latitude.jpg 3 640 \
  "Portra 400 · −2 stops=$T/portra_m2.jpg" "Portra 400 · normal=$T/portra400.jpg" "Portra 400 · +2 stops=$T/portra_p2.jpg"
dev trix_g00 trix400 --grade -1
dev trix_g5 trix400 --grade 5
dev portra_y portra400 --cc-y 15
dev portra_m portra400 --cc-m 15
swift scripts/contact_sheet.swift docs/images/printing.jpg 3 640 \
  "Tri-X · paper grade 00=$T/trix_g00.jpg" "Tri-X · paper grade 2=$T/trix400.jpg" "Tri-X · paper grade 5=$T/trix_g5.jpg" \
  "Portra · +15 Y filtration=$T/portra_y.jpg" "Portra · lab scan=$T/portra_scan.jpg" "Portra · +15 M filtration=$T/portra_m.jpg"
dev portra_border portra400 --border fullFrame
dev trix_border trix400 --border filed --surface matte
swift scripts/contact_sheet.swift docs/images/borders.jpg 2 900 \
  "Portra 400 · full-frame scan border=$T/portra_border.jpg" "Tri-X 400 · filed carrier, matte paper=$T/trix_border.jpg"
# 1:1 grain and halation
$B crop $IN cinestill800t $T/halo.jpg --size 520 --cx 0.61 --cy 0.26 >/dev/null
$B crop $IN portra800 $T/g1.jpg --size 520 --cx 0.80 --cy 0.42 >/dev/null
$B crop $IN trix400 $T/g2.jpg --size 520 --cx 0.80 --cy 0.42 >/dev/null
swift scripts/contact_sheet.swift docs/images/detail.jpg 3 520 \
  "CineStill 800T · halation 1:1=$T/halo.jpg" "Portra 800 · grain 1:1=$T/g1.jpg" "Tri-X 400 · grain 1:1=$T/g2.jpg"
rm -rf $T
echo "README images updated"
