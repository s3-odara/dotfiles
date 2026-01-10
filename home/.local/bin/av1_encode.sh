#!/bin/sh

# Configurable defaults
OUTPUT_EXT="webm"
V_QUALITY=150
A_BITRATE="64k"

usage() {
  echo "Usage: $0 [-v video_quality] [-a audio_bitrate] [-e extension] file [file ...]" >&2
  echo "  -v N   Video quality (ffmpeg -q:v, default: $V_QUALITY)" >&2
  echo "  -a B   Audio bitrate (ffmpeg -b:a, default: $A_BITRATE)" >&2
  echo "  -e EXT Output extension (default: $OUTPUT_EXT)" >&2
  exit 1
}

# Minimal getopts loop
while getopts "v:a:e:h" opt; do
  case "$opt" in
    v) V_QUALITY="$OPTARG";;
    a) A_BITRATE="$OPTARG";;
    e) OUTPUT_EXT="$OPTARG";;
    h) usage;;
    *) usage;;
  esac
done
shift $((OPTIND-1))
[ $# -eq 0 ] && usage

encode_file() {
  infile="$1"
  [ ! -f "$infile" ] && echo "Skip: $infile not found" >&2 && return
  ofile_base="${infile%.*}"
  ofile="${ofile_base}.${OUTPUT_EXT}"
  n=1
  while [ -f "$ofile" ]; do
    ofile="${ofile_base}_$n.${OUTPUT_EXT}"
    n=$((n+1))
  done
  ffmpeg -hide_banner -y \
    -hwaccel vaapi -vaapi_device /dev/dri/renderD128 \
    -i "$infile" \
    -vf hwupload,scale_vaapi=format=p010 -c:v av1_vaapi -rc_mode:v CQP \
    -q:v "$V_QUALITY" -compression_level:v 29 \
    -c:a libopus -ar 48000 -b:a "$A_BITRATE" \
    "$ofile"
}

for f; do
  encode_file "$f"
done
