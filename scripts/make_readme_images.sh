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
dev trix_cond trix400 --enlarger condenser
swift scripts/contact_sheet.swift docs/images/printing.jpg 3 640 \
  "Tri-X · grade 2, diffusion=$T/trix400.jpg" "Tri-X · grade 2, condenser=$T/trix_cond.jpg" "Tri-X · paper grade 5=$T/trix_g5.jpg" \
  "Portra · +15 Y filtration=$T/portra_y.jpg" "Portra · lab scan=$T/portra_scan.jpg" "Portra · +15 M filtration=$T/portra_m.jpg"
dev portra_border portra400 --border fullFrame
dev trix_border trix400 --border filed --surface matte
swift scripts/contact_sheet.swift docs/images/borders.jpg 2 900 \
  "Portra 400 · full-frame scan border=$T/portra_border.jpg" "Tri-X 400 · filed carrier, matte paper=$T/trix_border.jpg"
dev portra_album portra400 --print-age 40
dev portra_framed portra400 --print-age 40 --keeping framed
dev e100_album e100 --print-age 40
dev vision_album vision250d --print-age 50
dev kchrome_album kodachrome64 --print-age 50
swift scripts/contact_sheet.swift docs/images/fading.jpg 3 640 \
  "Portra · new print=$T/portra400.jpg" "Portra · 40 years in an album=$T/portra_album.jpg" "Portra · 40 years framed=$T/portra_framed.jpg" \
  "Ektachrome · 40 years in a box=$T/e100_album.jpg" "Kodachrome · 50 years in a box=$T/kchrome_album.jpg" "Vision3 cine print · 50 years=$T/vision_album.jpg"
dev hp5_n hp5
dev hp5_warm hp5 --paper-tone warm
dev hp5_cold hp5 --paper-tone cold
dev hp5_sel hp5 --toner selenium --toner-strength 1
dev hp5_split hp5 --toner sepia --toner-strength 0.3
dev hp5_sepia hp5 --paper-tone warm --toner sepia --toner-strength 1
swift scripts/contact_sheet.swift docs/images/toning.jpg 3 640 \
  "HP5 · neutral paper=$T/hp5_n.jpg" "HP5 · warm-tone paper=$T/hp5_warm.jpg" "HP5 · cold-tone paper=$T/hp5_cold.jpg" \
  "HP5 · selenium toned=$T/hp5_sel.jpg" "HP5 · sepia split tone (short bleach)=$T/hp5_split.jpg" "HP5 · full sepia, warm-tone paper=$T/hp5_sepia.jpg"
dev p_leak portra400 --leak 0.8
dev s_leak superia400 --leak 0.6 --scan
dev h_leak hp5 --leak 0.7
$B crop $IN portra400 $T/d1.jpg --size 520 --cx 0.3 --cy 0.3 --dust 1 --scratches 0.8 >/dev/null
$B crop $IN velvia50 $T/d2.jpg --size 520 --cx 0.3 --cy 0.3 --dust 1 --scratches 0.8 >/dev/null
$B crop $IN trix400 $T/d3.jpg --size 520 --cx 0.3 --cy 0.3 --dust 1 --scratches 0.8 --enlarger condenser >/dev/null
swift scripts/contact_sheet.swift docs/images/handling.jpg 3 640 \
  "Portra · light leak=$T/p_leak.jpg" "Superia lab scan · light leak=$T/s_leak.jpg" "HP5 · light leak=$T/h_leak.jpg" \
  "Portra print 1:1 · dust prints white=$T/d1.jpg" "Velvia slide 1:1 · dust shows dark=$T/d2.jpg" "Tri-X condenser 1:1 · base scratch=$T/d3.jpg"
# 1:1 grain and halation
$B crop $IN cinestill800t $T/halo.jpg --size 520 --cx 0.61 --cy 0.26 >/dev/null
$B crop $IN portra800 $T/g1.jpg --size 520 --cx 0.80 --cy 0.42 >/dev/null
$B crop $IN trix400 $T/g2.jpg --size 520 --cx 0.80 --cy 0.42 >/dev/null
swift scripts/contact_sheet.swift docs/images/detail.jpg 3 520 \
  "CineStill 800T · halation 1:1=$T/halo.jpg" "Portra 800 · grain 1:1=$T/g1.jpg" "Tri-X 400 · grain 1:1=$T/g2.jpg"
rm -rf $T
echo "README images updated"
