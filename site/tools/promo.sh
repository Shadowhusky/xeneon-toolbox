#!/bin/bash
# Builds the ~35 s promo film from the real panel captures: each strip pans or
# zooms inside a 16:9 frame under a caption plate, then an end card, cut to the
# theme. Output: site/assets/video/promo.mp4 (H.264) and promo.webm (VP9).
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=site/assets/video; mkdir -p "$OUT"
S=docs/img
AUDIO=site/assets/audio/theme.mp3
W=1920; H=1080; FPS=30
TMP=$(mktemp -d)

# image | caption | seconds | motion
scenes=(
  "$S/dashboard.png|Your Mac, on the Edge.|5|zoom"
  "$S/deck.png|A launcher you build with your thumb.|4|l2r"
  "$S/minimal.png|A night clock when you're not looking.|4|zoom"
  "$S/clock.png|World clocks and a focus timer.|3.5|r2l"
  "$S/assistant.png|An assistant that can actually do things.|4|l2r"
  "$S/control-center.png|Wi-Fi, Bluetooth, brightness, media. One swipe.|3.5|r2l"
  "$S/boost.png|Boost: quit what you're not using.|3.5|zoom"
  "$S/customize.png|Drag, resize, add. Your board.|3.5|l2r"
)
caps=(); for s in "${scenes[@]}"; do IFS='|' read -r _ cap _ _ <<< "$s"; caps+=("$cap"); done
python3 site/tools/captions.py "$TMP" caps "${caps[@]}"
python3 site/tools/captions.py "$TMP" end "Xeneon Toolbox" "Free for macOS  ·  xeneon.shadowhusky-london.uk"

i=0; list="$TMP/list.txt"; : > "$list"
for s in "${scenes[@]}"; do
  IFS='|' read -r img cap secs dir <<< "$s"
  frames=$(python3 -c "print(int($secs*$FPS))")
  case $dir in
    l2r) zp="z='1.18':x='(iw-iw/zoom)*on/$frames':y='(ih-ih/zoom)/2'";;
    r2l) zp="z='1.18':x='(iw-iw/zoom)*(1-on/$frames)':y='(ih-ih/zoom)/2'";;
    *)   zp="z='1.04+0.14*on/$frames':x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2'";;
  esac
  fo=$(python3 -c "print($secs-0.5)")
  ffmpeg -v error -y -loop 1 -i "$img" -loop 1 -i "$TMP/cap$i.png" -t "$secs" \
    -filter_complex "[0:v]scale=3800:-1,pad=3800:2138:0:(oh-ih)/2:color=0x0a0b0d,zoompan=$zp:d=$frames:s=${W}x${H}:fps=$FPS[bg];\
      [1:v]format=rgba,fade=t=in:st=0.4:d=0.5:alpha=1,fade=t=out:st=$fo:d=0.5:alpha=1[cap];\
      [bg][cap]overlay=0:0:shortest=1,format=yuv420p,fade=t=in:st=0:d=0.5,fade=t=out:st=$fo:d=0.5[v]" \
    -map "[v]" -c:v libx264 -preset medium -crf 18 -r $FPS "$TMP/scene$i.mp4"
  echo "file 'scene$i.mp4'" >> "$list"
  i=$((i+1))
done

ffmpeg -v error -y -f lavfi -i "color=c=0x0a0b0d:s=${W}x${H}:d=3.5:r=$FPS" -loop 1 -i "$TMP/end.png" -t 3.5 \
  -filter_complex "[0:v][1:v]overlay=0:0:shortest=1,format=yuv420p,fade=t=in:st=0:d=0.6,fade=t=out:st=3:d=0.5[v]" \
  -map "[v]" -c:v libx264 -preset medium -crf 18 "$TMP/scene$i.mp4"
echo "file 'scene$i.mp4'" >> "$list"

ffmpeg -v error -y -f concat -safe 0 -i "$list" -c copy "$TMP/silent.mp4"
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP/silent.mp4")
if [ -f "$AUDIO" ]; then
  ffmpeg -v error -y -i "$TMP/silent.mp4" -stream_loop -1 -i "$AUDIO" -t "$DUR" \
    -af "afade=t=out:st=$(python3 -c "print(float('$DUR')-1.5)"):d=1.5" \
    -c:v copy -c:a aac -b:a 160k -shortest "$OUT/promo.mp4"
else
  cp "$TMP/silent.mp4" "$OUT/promo.mp4"
fi
ffmpeg -v error -y -i "$OUT/promo.mp4" -c:v libvpx-vp9 -crf 34 -b:v 0 -row-mt 1 -c:a libopus -b:a 96k "$OUT/promo.webm"
rm -rf "$TMP"
ls -la "$OUT" | awk '{print $5, $9}' | tail -2
echo "duration ${DUR}s"
