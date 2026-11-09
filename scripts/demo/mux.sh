#!/bin/sh
# Puts a scene's sound (clip.caf, from the app) under its picture (clip.mov), lined up by when each began.
#   scripts/demo/mux.sh clip.mov clip.caf out.mp4
v="$1"; a="$2"; out="$3"
off=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[2]))["start"] - json.load(open(sys.argv[1]))["start"])' "$v.json" "$a.json")
# sound began after the picture: wait for it; before: skip its head
case "$off" in
  -*) ain="-ss ${off#-} -i $a" ; filt="anull" ;;
  *)  ain="-i $a" ; filt="adelay=$(python3 -c "print(int($off*1000))"):all=1" ;;
esac
ffmpeg -v error -y -i "$v" $ain -map 0:v -map 1:a -af "$filt" -c:v copy -c:a aac -b:a 256k -shortest "$out"
