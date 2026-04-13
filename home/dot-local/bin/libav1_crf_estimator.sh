#!/usr/bin/env bash

crf_estimator_script_name() {
  if [[ -n "${CRF_ESTIMATOR_SCRIPT_NAME:-}" ]]; then
    printf '%s\n' "$CRF_ESTIMATOR_SCRIPT_NAME"
  else
    printf '%s\n' "$(basename "${0:-script}")"
  fi
}

crf_estimator_die() {
  echo "ERROR: $*" >&2
  exit 1
}

crf_estimator_log() {
  echo "[$(crf_estimator_script_name)] $*" >&2
}

crf_estimator_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || crf_estimator_die "Required command not found: $1"
}

crf_estimator_require_tools() {
  local metric="${1:-xpsnr}"
  local cmd
  local filters_output
  for cmd in ffmpeg ffprobe awk mktemp sort python3; do
    crf_estimator_require_cmd "$cmd"
  done
  if [[ "$metric" == "vmaf" ]]; then
    filters_output=$(ffmpeg -hide_banner -filters 2>/dev/null)
    grep -q ' libvmaf ' <<<"$filters_output" || crf_estimator_die "ffmpeg libvmaf filter is required for estimate-metric=vmaf"
    grep -q ' libplacebo ' <<<"$filters_output" || crf_estimator_die "ffmpeg libplacebo filter is required for estimate-metric=vmaf"
  fi
  if [[ "$metric" == "ssimulacra2" ]]; then
    python3 - <<'PY' >/dev/null 2>&1 || crf_estimator_die "VapourSynth vship plugin with SSIMULACRA2 is required for estimate-metric=ssimulacra2"
import vapoursynth as vs
core = vs.core
assert hasattr(core, "ffms2")
assert hasattr(core, "resize")
assert hasattr(core, "vship")
assert hasattr(core.vship, "SSIMULACRA2")
PY
  fi
}

crf_estimator_cleanup_workdir() {
  local keep_temp="$1"
  local workdir="$2"
  if [[ "$keep_temp" == "1" ]]; then
    crf_estimator_log "Keeping temporary directory: $workdir"
  else
    rm -rf "$workdir"
  fi
}

crf_estimator_float_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'
}

crf_estimator_float_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 < b + 0) }'
}

crf_estimator_float_min() {
  awk -v a="$1" -v b="$2" 'BEGIN { if (a + 0 < b + 0) printf "%.6f", a + 0; else printf "%.6f", b + 0 }'
}

crf_estimator_float_max() {
  awk -v a="$1" -v b="$2" 'BEGIN { if (a + 0 > b + 0) printf "%.6f", a + 0; else printf "%.6f", b + 0 }'
}

crf_estimator_normalize_ts() {
  awk -v x="$1" '
    BEGIN {
      s = sprintf("%.3f", x + 0)
      if (s ~ /^\./) s = "0" s
      if (s ~ /^-\./) sub(/^-/, "-0", s)
      print s
    }'
}

crf_estimator_normalize_ts6() {
  awk -v x="$1" '
    BEGIN {
      s = sprintf("%.6f", x + 0)
      if (s ~ /^\./) s = "0" s
      if (s ~ /^-\./) sub(/^-/, "-0", s)
      print s
    }'
}

crf_estimator_scene_duration() {
  awk -v s="$1" -v e="$2" 'BEGIN { printf "%.6f", e - s }'
}

crf_estimator_resolve_padded_scene() {
  local duration="$1"
  local scene_start="$2"
  local scene_end="$3"
  local padding_seconds="${4:-2}"

  local encode_start encode_end measure_offset measure_duration
  encode_start=$(crf_estimator_float_max "$(awk -v s="$scene_start" -v p="$padding_seconds" 'BEGIN { printf "%.6f", s - p }')" "0")
  encode_end=$(crf_estimator_float_min "$(awk -v e="$scene_end" -v p="$padding_seconds" 'BEGIN { printf "%.6f", e + p }')" "$duration")
  measure_offset=$(awk -v s="$scene_start" -v es="$encode_start" 'BEGIN { printf "%.6f", s - es }')
  measure_duration=$(crf_estimator_scene_duration "$scene_start" "$scene_end")

  printf "%s\t%s\t%s\t%s\n" \
    "$(crf_estimator_normalize_ts6 "$encode_start")" \
    "$(crf_estimator_normalize_ts6 "$encode_end")" \
    "$(crf_estimator_normalize_ts6 "$measure_offset")" \
    "$(crf_estimator_normalize_ts6 "$measure_duration")"
}

crf_estimator_sanitize_label() {
  local label="$1"
  printf '%s\n' "${label//[^A-Za-z0-9._-]/_}"
}

crf_estimator_get_duration() {
  ffprobe -v error -select_streams v:0 -show_entries format=duration -of default=nw=1:nk=1 "$1"
}

crf_estimator_get_pix_fmt() {
  ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=nw=1:nk=1 "$1"
}

crf_estimator_get_display_geometry() {
  ffprobe -v error \
    -select_streams v:0 \
    -show_entries stream=width,height:stream_side_data=rotation \
    -of default=nw=1 "$1"
}

crf_estimator_get_display_size() {
  local input="$1"
  local width="" height="" rotation="0"
  while IFS='=' read -r key value; do
    case "$key" in
      width) width="$value" ;;
      height) height="$value" ;;
      rotation) rotation="$value" ;;
    esac
  done < <(crf_estimator_get_display_geometry "$input")

  [[ -n "$width" && -n "$height" ]] || crf_estimator_die "Failed to read input geometry: $input"

  if [[ "$rotation" == "90" || "$rotation" == "-90" || "$rotation" == "270" || "$rotation" == "-270" ]]; then
    printf "%s\t%s\n" "$height" "$width"
  else
    printf "%s\t%s\n" "$width" "$height"
  fi
}

crf_estimator_even_floor() {
  awk -v x="$1" 'BEGIN {
    n = int(x + 0)
    if (n < 2) n = 2
    if (n % 2 != 0) n--
    print n
  }'
}

crf_estimator_resolve_normalization() {
  local input="$1"
  local metric="${2:-xpsnr}"
  local display_width display_height
  IFS=$'\t' read -r display_width display_height < <(crf_estimator_get_display_size "$input")

  case "$metric" in
    xpsnr)
      local mode="none"
      local filter=""
      local work_width="$display_width"
      local work_height="$display_height"

      if awk -v w="$display_width" -v h="$display_height" 'BEGIN { exit !(w < h) }'; then
        filter="transpose=clock"
        mode="rotate"
        work_width="$display_height"
        work_height="$display_width"
      fi

      if ! awk -v w="$work_width" -v h="$work_height" 'BEGIN { exit !(w * 9 == h * 16) }'; then
        local crop_width="$work_width"
        local crop_height="$work_height"

        if awk -v w="$work_width" -v h="$work_height" 'BEGIN { exit !(w * 9 > h * 16) }'; then
          crop_width=$(crf_estimator_even_floor "$(awk -v h="$work_height" 'BEGIN { printf "%.6f", h * 16 / 9 }')")
        else
          crop_height=$(crf_estimator_even_floor "$(awk -v w="$work_width" 'BEGIN { printf "%.6f", w * 9 / 16 }')")
        fi

        local crop_x crop_y
        crop_x=$(awk -v w="$work_width" -v cw="$crop_width" 'BEGIN { print int((w - cw) / 2) }')
        crop_y=$(awk -v h="$work_height" -v ch="$crop_height" 'BEGIN { print int((h - ch) / 2) }')

        if [[ -n "$filter" ]]; then
          filter+=","
        fi
        filter+="crop=${crop_width}:${crop_height}:${crop_x}:${crop_y}"
        if [[ "$mode" == "rotate" ]]; then
          mode="rotate_crop_16_9"
        else
          mode="crop_16_9"
        fi
      fi

      printf "%s\t%s\n" "$mode" "$filter"
      ;;
    vmaf)
      local mode="vmaf_scale_1080p"
      if (( display_height < 1080 )); then
        mode="vmaf_scale_1080p_up"
      elif (( display_height > 1080 )); then
        mode="vmaf_scale_1080p_down"
      fi

      printf "%s\t%s\n" "$mode" "libplacebo=w='trunc(iw*1080/ih/2)*2':h=1080:upscaler=ewa_lanczos:downscaler=ewa_lanczos"
      ;;
    *)
      printf "%s\t%s\n" "none" ""
      ;;
  esac
}

crf_estimator_calc_sample_count() {
  local duration="$1"
  local delta="$2"
  local base="$3"

  awk -v d="$duration" -v delta="$delta" -v base="$base" '
    BEGIN {
      ratio = d / delta
      if (ratio < 1) ratio = 1
      n = int((log(ratio) / log(base)) + 0.999999) + 1
      if (n < 1) n = 1
      print n
    }'
}

crf_estimator_make_sample_times() {
  local duration="$1"
  local sample_count="$2"

  awk -v d="$duration" -v n="$sample_count" '
    BEGIN {
      for (i = 0; i < n; i++) {
        t = (i + 0.5) * d / n
        printf "%.6f\n", t
      }
    }'
}

crf_estimator_detect_local_scene() {
  local input="$1"
  local duration="$2"
  local sample_time="$3"
  local window_half="$4"
  local scdet_threshold="$5"

  local win_start
  local win_end
  win_start=$(crf_estimator_float_max "$(awk -v t="$sample_time" -v w="$window_half" 'BEGIN { printf "%.6f", t - w }')" "0")
  win_end=$(crf_estimator_float_min "$(awk -v t="$sample_time" -v w="$window_half" 'BEGIN { printf "%.6f", t + w }')" "$duration")

  local local_sample
  local_sample=$(awk -v t="$sample_time" -v s="$win_start" 'BEGIN { printf "%.6f", t - s }')

  local scdet_output
  scdet_output=$(
    ffmpeg -hide_banner -loglevel info \
      -ss "$(crf_estimator_normalize_ts6 "$win_start")" -to "$(crf_estimator_normalize_ts6 "$win_end")" -i "$input" \
      -vf "scdet=threshold=${scdet_threshold},metadata=print:file=-" \
      -an -f null - 2>&1
  )

  local bounds
  bounds=$(awk -v sample="$local_sample" '
    BEGIN {
      prev_time = -1
      next_time = -1
    }
    /lavfi\.scd\.time=/ {
      split($0, parts, "=")
      t = parts[2] + 0
      if (t <= sample) prev_time = t
      if (t > sample && next_time < 0) next_time = t
    }
    END {
      if (prev_time < 0) prev_time = 0
      if (next_time < 0) next_time = -1
      printf "%.6f %.6f\n", prev_time, next_time
    }' <<<"$scdet_output")

  local local_start local_end
  local_start=$(awk '{print $1}' <<<"$bounds")
  local_end=$(awk '{print $2}' <<<"$bounds")
  if awk -v x="$local_end" 'BEGIN { exit !(x < 0) }'; then
    local_end=$(awk -v s="$win_start" -v e="$win_end" 'BEGIN { printf "%.6f", e - s }')
  fi

  local scene_start scene_end
  scene_start=$(awk -v ws="$win_start" -v ls="$local_start" 'BEGIN { printf "%.6f", ws + ls }')
  scene_end=$(awk -v ws="$win_start" -v le="$local_end" 'BEGIN { printf "%.6f", ws + le }')

  if ! awk -v a="$scene_end" -v b="$scene_start" 'BEGIN { exit !(a > b) }'; then
    scene_start="$win_start"
    scene_end="$win_end"
  fi

  printf "%s\t%s\n" "$(crf_estimator_normalize_ts "$scene_start")" "$(crf_estimator_normalize_ts "$scene_end")"
}

crf_estimator_dedupe_scenes() {
  awk -F '\t' '
    NF >= 2 {
      key = $1 FS $2
      if (!(key in seen)) {
        seen[key] = 1
        print $1 "\t" $2
      }
    }'
}

crf_estimator_encode_scene_once() {
  local input="$1"
  local start="$2"
  local end="$3"
  local crf="$4"
  local preset="$5"
  local pix_fmt="$6"
  local svtav1_params_extra="$7"
  local outfile="$8"

  local duration
  local -a ffmpeg_args
  duration=$(crf_estimator_normalize_ts6 "$(crf_estimator_scene_duration "$start" "$end")")
  awk -v d="$duration" 'BEGIN { exit !(d > 0.050) }' || crf_estimator_die "Scene duration too short: $start - $end"

  ffmpeg_args=(
    -hide_banner -loglevel error -y
    -ss "$(crf_estimator_normalize_ts6 "$start")" -t "$duration" -i "$input"
    -map 0:v:0 -an
    -c:v libsvtav1
    -preset "$preset"
    -crf "$crf"
    -vf "format=${pix_fmt}"
  )
  if [[ -n "$svtav1_params_extra" ]]; then
    ffmpeg_args+=(-svtav1-params "$svtav1_params_extra")
  fi
  ffmpeg_args+=("$outfile")

  ffmpeg "${ffmpeg_args[@]}"
}

crf_estimator_prepare_reference_scene() {
  local input="$1"
  local start="$2"
  local end="$3"
  local pix_fmt="$4"
  local workdir="$5"
  local cache_key="$6"

  local sanitized_key reference_scene duration
  sanitized_key=$(crf_estimator_sanitize_label "$cache_key")
  reference_scene="$workdir/reference_${sanitized_key}.mkv"
  if [[ -f "$reference_scene" ]]; then
    printf '%s\n' "$reference_scene"
    return 0
  fi

  duration=$(crf_estimator_normalize_ts6 "$(crf_estimator_scene_duration "$start" "$end")")

  ffmpeg -hide_banner -loglevel error -y \
    -ss "$(crf_estimator_normalize_ts6 "$start")" -t "$duration" -i "$input" \
    -map 0:v:0 -an \
    -c:v ffv1 \
    -vf "format=${pix_fmt}" \
    "$reference_scene"

  printf '%s\n' "$reference_scene"
}

crf_estimator_percentile_value_from_sorted() {
  local sorted_file="$1"
  local count="$2"
  local pct="$3"
  local line_no
  line_no=$(( ((count - 1) * pct) / 100 + 1 ))
  sed -n "${line_no}p" "$sorted_file"
}

crf_estimator_emit_stats_from_values() {
  local values_file="$1"
  local selected_stat="$2"

  local count sorted_file mean_value p05_value p10_value selected_value percentile_digits
  count=$(wc -l <"$values_file" | tr -d ' ')
  [[ "$count" -gt 0 ]] || crf_estimator_die "No metric values found in $values_file"

  sorted_file="$values_file.sorted"
  sort -g "$values_file" >"$sorted_file"
  mean_value=$(awk '{ sum += $1 } END { printf "%.6f\n", sum / NR }' "$values_file")
  p05_value=$(crf_estimator_percentile_value_from_sorted "$sorted_file" "$count" 5)
  p10_value=$(crf_estimator_percentile_value_from_sorted "$sorted_file" "$count" 10)

  case "$selected_stat" in
    mean)
      selected_value="$mean_value"
      ;;
    p[0-9][0-9])
      percentile_digits="${selected_stat#p}"
      selected_value=$(crf_estimator_percentile_value_from_sorted "$sorted_file" "$count" "$((10#$percentile_digits))")
      ;;
    *)
      crf_estimator_die "Unknown estimate stat: $selected_stat"
      ;;
  esac

  printf "selected=%s\n" "$selected_value"
  printf "mean=%s\n" "$mean_value"
  printf "p05=%s\n" "$p05_value"
  printf "p10=%s\n" "$p10_value"
}

crf_estimator_measure_scene_xpsnr_stats() {
  local input="$1"
  local start="$2"
  local end="$3"
  local encoded="$4"
  local pix_fmt="$5"
  local normalize_filter="$6"
  local selected_stat="$7"
  local encoded_offset="${8:-0}"

  local duration stats_file
  duration=$(crf_estimator_normalize_ts6 "$(crf_estimator_scene_duration "$start" "$end")")
  stats_file=$(mktemp)
  trap 'rm -f "$stats_file"' RETURN

  local xpsnr_output
  local main_chain="format=${pix_fmt}"
  local ref_chain="format=${pix_fmt}"
  if [[ -n "$normalize_filter" ]]; then
    main_chain="${normalize_filter},${main_chain}"
    ref_chain="${normalize_filter},${ref_chain}"
  fi
  xpsnr_output=$(
    ffmpeg -hide_banner -loglevel info \
      -ss "$(crf_estimator_normalize_ts6 "$start")" -t "$duration" -i "$input" \
      -ss "$(crf_estimator_normalize_ts6 "$encoded_offset")" -t "$duration" -i "$encoded" \
      -filter_complex "[0:v]${main_chain}[main];[1:v]${ref_chain}[ref];[main][ref]xpsnr=stats_file=${stats_file}" \
      -an -f null - 2>&1
  )

  awk '
    match($0, /XPSNR y: ([^ ]+)/, y) &&
    match($0, /XPSNR u: ([^ ]+)/, u) &&
    match($0, /XPSNR v: ([^ ]+)/, v) {
      if (y[1] != "inf" && u[1] != "inf" && v[1] != "inf") {
        min = y[1] + 0
        if ((u[1] + 0) < min) min = u[1] + 0
        if ((v[1] + 0) < min) min = v[1] + 0
        printf "%.6f\n", min
      }
    }' "$stats_file" >"${stats_file}.values"
  [[ -s "${stats_file}.values" ]] || crf_estimator_die "Failed to parse xpsnr per-frame values for scene ${start}-${end}: ${xpsnr_output}"

  crf_estimator_emit_stats_from_values "${stats_file}.values" "$selected_stat"
  trap - RETURN
  rm -f "$stats_file" "${stats_file}.values" "${stats_file}.values.sorted"
}

crf_estimator_measure_scene_vmaf_stats() {
  local reference_scene="$1"
  local encoded="$2"
  local normalize_filter="$3"
  local selected_stat="$4"
  local encoded_offset="${5:-0}"
  local duration="${6:-}"

  local json_file
  json_file=$(mktemp)
  trap 'rm -f "$json_file" "$json_file.values" "$json_file.values.sorted"' RETURN

  local dist_chain="settb=AVTB,setpts=PTS-STARTPTS"
  local ref_chain="settb=AVTB,setpts=PTS-STARTPTS"
  if [[ -n "$normalize_filter" ]]; then
    dist_chain="${dist_chain},${normalize_filter}"
    ref_chain="${ref_chain},${normalize_filter}"
  fi

  [[ -n "$duration" ]] || crf_estimator_die "Duration is required for VMAF scene measurement"
  ffmpeg -hide_banner -loglevel error \
    -ss "$(crf_estimator_normalize_ts6 "$encoded_offset")" -t "$(crf_estimator_normalize_ts6 "$duration")" -i "$encoded" \
    -i "$reference_scene" \
    -lavfi "[0:v]${dist_chain}[dist];[1:v]${ref_chain}[ref];[dist][ref]libvmaf=log_fmt=json:log_path=${json_file}:n_threads=8" \
    -an -f null - >/dev/null

  python3 - "$json_file" >"${json_file}.values" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

for frame in data.get("frames", []):
    metrics = frame.get("metrics", {})
    if "vmaf" in metrics:
        print(f"{float(metrics['vmaf']):.6f}")
PY
  [[ -s "${json_file}.values" ]] || crf_estimator_die "Failed to parse VMAF values from $json_file"

  crf_estimator_emit_stats_from_values "${json_file}.values" "$selected_stat"
  trap - RETURN
  rm -f "$json_file" "${json_file}.values" "${json_file}.values.sorted"
}

crf_estimator_measure_scene_ssimulacra2_stats() {
  local reference_scene="$1"
  local encoded="$2"
  local pix_fmt="$3"
  local selected_stat="$4"
  local encoded_offset="${5:-0}"

  local values_file
  values_file=$(mktemp)
  trap 'rm -f "$values_file" "$values_file.sorted"' RETURN

  python3 - "$reference_scene" "$encoded" "$pix_fmt" "$encoded_offset" >"$values_file" <<'PY'
import sys
import vapoursynth as vs

reference_path, distorted_path, pix_fmt, encoded_offset = sys.argv[1:]
core = vs.core

format_map = {
    "yuv420p": vs.YUV420P8,
    "yuv420p10le": vs.YUV420P10,
}

if pix_fmt not in format_map:
    raise SystemExit(f"Unsupported pix_fmt for SSIMULACRA2: {pix_fmt}")

target_format = format_map[pix_fmt]
reference = core.resize.Bicubic(core.ffms2.Source(reference_path), format=target_format)
distorted = core.resize.Bicubic(core.ffms2.Source(distorted_path), format=target_format)
start_frame = int(round(float(encoded_offset) * distorted.fps_num / distorted.fps_den))
if start_frame < 0:
    start_frame = 0
end_frame = start_frame + reference.num_frames - 1
if end_frame >= distorted.num_frames:
    raise SystemExit(
        f"Encoded clip is too short for SSIMULACRA2 window: start={start_frame} "
        f"need={reference.num_frames} total={distorted.num_frames}"
    )
distorted = core.std.Trim(distorted, start_frame, end_frame)
metric = core.vship.SSIMULACRA2(reference, distorted)

for i in range(metric.num_frames):
    frame = metric.get_frame(i)
    print(f"{float(frame.props['_SSIMULACRA2']):.6f}")
PY
  [[ -s "$values_file" ]] || crf_estimator_die "Failed to compute SSIMULACRA2 values for $encoded"

  crf_estimator_emit_stats_from_values "$values_file" "$selected_stat"
  trap - RETURN
  rm -f "$values_file" "$values_file.sorted"
}

crf_estimator_measure_scene_stats() {
  local metric="$1"
  local input="$2"
  local start="$3"
  local end="$4"
  local encoded="$5"
  local pix_fmt="$6"
  local normalize_filter="$7"
  local selected_stat="$8"
  local workdir="$9"
  local cache_key="${10}"
  local encoded_offset="${11:-0}"
  local measure_duration="${12:-}"
  local reference_scene

  case "$metric" in
    xpsnr)
      crf_estimator_measure_scene_xpsnr_stats "$input" "$start" "$end" "$encoded" "$pix_fmt" "$normalize_filter" "$selected_stat" "$encoded_offset"
      ;;
    vmaf)
      reference_scene=$(crf_estimator_prepare_reference_scene "$input" "$start" "$end" "$pix_fmt" "$workdir" "$cache_key")
      crf_estimator_measure_scene_vmaf_stats "$reference_scene" "$encoded" "$normalize_filter" "$selected_stat" "$encoded_offset" "$measure_duration"
      ;;
    ssimulacra2)
      reference_scene=$(crf_estimator_prepare_reference_scene "$input" "$start" "$end" "$pix_fmt" "$workdir" "$cache_key")
      crf_estimator_measure_scene_ssimulacra2_stats "$reference_scene" "$encoded" "$pix_fmt" "$selected_stat" "$encoded_offset"
      ;;
    *)
      crf_estimator_die "Unsupported estimate metric: $metric"
      ;;
  esac
}

crf_estimator_pick_worst_scene() {
  local input="$1"
  local scenes_file="$2"
  local crf_init="$3"
  local preset="$4"
  local pix_fmt="$5"
  local svtav1_params_extra="$6"
  local normalize_filter="$7"
  local workdir="$8"
  local metric="$9"
  local selected_stat="${10}"

  local best_start=""
  local best_end=""
  local best_score=""
  local best_mean=""
  local best_p05=""
  local best_p10=""
  local idx=0
  local input_duration

  input_duration=$(crf_estimator_get_duration "$input")

  while IFS=$'\t' read -r scene_start scene_end; do
    [[ -n "$scene_start" && -n "$scene_end" ]] || continue
    idx=$((idx + 1))
    local encoded="$workdir/candidate_${idx}.mkv"
    local encode_start encode_end measure_offset measure_duration
    IFS=$'\t' read -r encode_start encode_end measure_offset measure_duration < <(
      crf_estimator_resolve_padded_scene "$input_duration" "$scene_start" "$scene_end" "2"
    )
    crf_estimator_encode_scene_once "$input" "$encode_start" "$encode_end" "$crf_init" "$preset" "$pix_fmt" "$svtav1_params_extra" "$encoded"
    local stats score mean_score p05_score p10_score
    stats=$(crf_estimator_measure_scene_stats "$metric" "$input" "$scene_start" "$scene_end" "$encoded" "$pix_fmt" "$normalize_filter" "$selected_stat" "$workdir" "candidate_${idx}" "$measure_offset" "$measure_duration")
    score=$(awk -F= '$1 == "selected" { print $2 }' <<<"$stats")
    mean_score=$(awk -F= '$1 == "mean" { print $2 }' <<<"$stats")
    p05_score=$(awk -F= '$1 == "p05" { print $2 }' <<<"$stats")
    p10_score=$(awk -F= '$1 == "p10" { print $2 }' <<<"$stats")
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$scene_start" "$scene_end" "$score" "$mean_score" "$p05_score" "$p10_score" >>"$workdir/candidate_scores.tsv"
    if [[ -z "$best_score" ]] || crf_estimator_float_lt "$score" "$best_score"; then
      best_start="$scene_start"
      best_end="$scene_end"
      best_score="$score"
      best_mean="$mean_score"
      best_p05="$p05_score"
      best_p10="$p10_score"
    fi
  done <"$scenes_file"

  [[ -n "$best_score" ]] || crf_estimator_die "No candidate scenes available after dedupe"
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$best_start" "$best_end" "$best_score" "$best_mean" "$best_p05" "$best_p10"
}

crf_estimator_score_scene_at_crf() {
  local input="$1"
  local scene_start="$2"
  local scene_end="$3"
  local crf="$4"
  local preset="$5"
  local pix_fmt="$6"
  local svtav1_params_extra="$7"
  local normalize_filter="$8"
  local workdir="$9"
  local metric="${10}"
  local selected_stat="${11}"
  local input_duration="${12}"

  local encoded="$workdir/search_crf_${crf}.mkv"
  local encode_start encode_end measure_offset measure_duration
  IFS=$'\t' read -r encode_start encode_end measure_offset measure_duration < <(
    crf_estimator_resolve_padded_scene "$input_duration" "$scene_start" "$scene_end" "2"
  )
  crf_estimator_encode_scene_once "$input" "$encode_start" "$encode_end" "$crf" "$preset" "$pix_fmt" "$svtav1_params_extra" "$encoded"
  crf_estimator_measure_scene_stats "$metric" "$input" "$scene_start" "$scene_end" "$encoded" "$pix_fmt" "$normalize_filter" "$selected_stat" "$workdir" "search_ref" "$measure_offset" "$measure_duration"
}

crf_estimator_record_search_score() {
  local workdir="$1"
  local crf="$2"
  local stats="$3"
  local score mean_score p05_score p10_score

  score=$(awk -F= '$1 == "selected" { print $2 }' <<<"$stats")
  mean_score=$(awk -F= '$1 == "mean" { print $2 }' <<<"$stats")
  p05_score=$(awk -F= '$1 == "p05" { print $2 }' <<<"$stats")
  p10_score=$(awk -F= '$1 == "p10" { print $2 }' <<<"$stats")
  printf "%s\t%s\t%s\t%s\t%s\n" "$crf" "$score" "$mean_score" "$p05_score" "$p10_score" >>"$workdir/search_scores.tsv"
  printf "%s\n" "$score"
}

crf_estimator_search_boundary_result() {
  local result="$1"
  local best_crf="$2"
  printf "best_crf=%s\n" "$best_crf"
  printf "search_result=%s\n" "$result"
}

crf_estimator_binary_search_crf() {
  local input="$1"
  local scene_start="$2"
  local scene_end="$3"
  local target="$4"
  local lo="$5"
  local hi="$6"
  local preset="$7"
  local pix_fmt="$8"
  local svtav1_params_extra="$9"
  local normalize_filter="${10}"
  local workdir="${11}"
  local metric="${12}"
  local selected_stat="${13}"
  local input_duration
  local boundary_lo="$lo"
  local boundary_hi="$hi"

  local last_direction=""
  local consecutive_direction_count=0
  local hi_checked=0
  local lo_checked=0
  local hi_score=""
  local lo_score=""

  : >"$workdir/search_scores.tsv"
  input_duration=$(crf_estimator_get_duration "$input")

  while (( lo < hi )); do
    local mid=$(((lo + hi + 1) / 2))
    local stats score direction
    stats=$(crf_estimator_score_scene_at_crf "$input" "$scene_start" "$scene_end" "$mid" "$preset" "$pix_fmt" "$svtav1_params_extra" "$normalize_filter" "$workdir" "$metric" "$selected_stat" "$input_duration")
    score=$(crf_estimator_record_search_score "$workdir" "$mid" "$stats")
    if crf_estimator_float_ge "$score" "$target"; then
      direction="up"
      lo="$mid"
    else
      direction="down"
      hi=$((mid - 1))
    fi

    if [[ "$direction" == "$last_direction" ]]; then
      consecutive_direction_count=$((consecutive_direction_count + 1))
    else
      last_direction="$direction"
      consecutive_direction_count=1
    fi

    if (( consecutive_direction_count >= 2 )) && [[ "$direction" == "up" ]] && (( ! hi_checked )); then
      stats=$(crf_estimator_score_scene_at_crf "$input" "$scene_start" "$scene_end" "$boundary_hi" "$preset" "$pix_fmt" "$svtav1_params_extra" "$normalize_filter" "$workdir" "$metric" "$selected_stat" "$input_duration")
      hi_score=$(crf_estimator_record_search_score "$workdir" "$boundary_hi" "$stats")
      hi_checked=1
      if crf_estimator_float_ge "$hi_score" "$target"; then
        crf_estimator_search_boundary_result "clamped_high" "$boundary_hi"
        return 0
      fi
    fi

    if (( consecutive_direction_count >= 2 )) && [[ "$direction" == "down" ]] && (( ! lo_checked )); then
      stats=$(crf_estimator_score_scene_at_crf "$input" "$scene_start" "$scene_end" "$boundary_lo" "$preset" "$pix_fmt" "$svtav1_params_extra" "$normalize_filter" "$workdir" "$metric" "$selected_stat" "$input_duration")
      lo_score=$(crf_estimator_record_search_score "$workdir" "$boundary_lo" "$stats")
      lo_checked=1
      if crf_estimator_float_lt "$lo_score" "$target"; then
        crf_estimator_search_boundary_result "clamped_low" "$boundary_lo"
        return 0
      fi
    fi
  done

  if (( ! lo_checked )); then
    stats=$(crf_estimator_score_scene_at_crf "$input" "$scene_start" "$scene_end" "$boundary_lo" "$preset" "$pix_fmt" "$svtav1_params_extra" "$normalize_filter" "$workdir" "$metric" "$selected_stat" "$input_duration")
    lo_score=$(crf_estimator_record_search_score "$workdir" "$boundary_lo" "$stats")
    lo_checked=1
  fi
  if crf_estimator_float_lt "$lo_score" "$target"; then
    crf_estimator_search_boundary_result "clamped_low" "$boundary_lo"
    return 0
  fi

  if (( ! hi_checked )); then
    stats=$(crf_estimator_score_scene_at_crf "$input" "$scene_start" "$scene_end" "$boundary_hi" "$preset" "$pix_fmt" "$svtav1_params_extra" "$normalize_filter" "$workdir" "$metric" "$selected_stat" "$input_duration")
    hi_score=$(crf_estimator_record_search_score "$workdir" "$boundary_hi" "$stats")
    hi_checked=1
  fi
  if crf_estimator_float_ge "$hi_score" "$target"; then
    crf_estimator_search_boundary_result "clamped_high" "$boundary_hi"
    return 0
  fi

  crf_estimator_search_boundary_result "ok" "$lo"
}

crf_estimator_run() {
  local input="$1"
  local target="$2"
  local delta="$3"
  local base="$4"
  local window_seconds="$5"
  local scdet_threshold="$6"
  local crf_init="$7"
  local preset="$8"
  local lo="$9"
  local hi="${10}"
  local keep_temp="${11}"
  local svtav1_params_extra="${12:-}"
  local pix_fmt="${13:-}"
  local metric="${14:-xpsnr}"
  local selected_stat="${15:-mean}"

  [[ -n "$input" ]] || crf_estimator_die "Input file is required"
  [[ -f "$input" ]] || crf_estimator_die "Input file not found: $input"
  [[ -n "$target" ]] || crf_estimator_die "Target quality is required"

  crf_estimator_require_tools "$metric"
  if [[ -z "$pix_fmt" ]]; then
    pix_fmt=$(crf_estimator_get_pix_fmt "$input")
  fi

  local duration sample_count workdir
  local samples_file scenes_file deduped_scenes_file scene_count
  local worst_start worst_end worst_score worst_mean worst_p05 worst_p10
  local best_crf normalization_mode normalization_filter search_output search_result

  duration=$(crf_estimator_get_duration "$input")
  sample_count=$(crf_estimator_calc_sample_count "$duration" "$delta" "$base")
  IFS=$'\t' read -r normalization_mode normalization_filter < <(crf_estimator_resolve_normalization "$input" "$metric")
  workdir=$(mktemp -d)
  # shellcheck disable=SC2064,SC2154
  trap "status=\$?; trap - EXIT INT TERM HUP; crf_estimator_cleanup_workdir '$keep_temp' '$workdir'; exit \$status" EXIT INT TERM HUP

  samples_file="$workdir/sample_times.txt"
  scenes_file="$workdir/scenes.tsv"
  deduped_scenes_file="$workdir/scenes_deduped.tsv"

  crf_estimator_make_sample_times "$duration" "$sample_count" >"$samples_file"
  : >"$scenes_file"

  while IFS= read -r sample_time; do
    crf_estimator_detect_local_scene "$input" "$duration" "$sample_time" "$window_seconds" "$scdet_threshold" >>"$scenes_file"
  done <"$samples_file"

  crf_estimator_dedupe_scenes <"$scenes_file" >"$deduped_scenes_file"

  scene_count=$(wc -l <"$deduped_scenes_file" | tr -d ' ')
  [[ "$scene_count" -gt 0 ]] || crf_estimator_die "No scenes detected"

  IFS=$'\t' read -r worst_start worst_end worst_score worst_mean worst_p05 worst_p10 < <(
    crf_estimator_pick_worst_scene "$input" "$deduped_scenes_file" "$crf_init" "$preset" "$pix_fmt" "$svtav1_params_extra" "$normalization_filter" "$workdir" "$metric" "$selected_stat"
  )

  search_output=$(crf_estimator_binary_search_crf "$input" "$worst_start" "$worst_end" "$target" "$lo" "$hi" "$preset" "$pix_fmt" "$svtav1_params_extra" "$normalization_filter" "$workdir" "$metric" "$selected_stat")
  best_crf=$(awk -F= '$1 == "best_crf" { print $2 }' <<<"$search_output")
  search_result=$(awk -F= '$1 == "search_result" { print $2 }' <<<"$search_output")

  printf "input=%s\n" "$input"
  printf "duration=%.3f\n" "$duration"
  printf "pix_fmt=%s\n" "$pix_fmt"
  printf "estimate_normalization=%s\n" "$normalization_mode"
  printf "estimate_metric=%s\n" "$metric"
  printf "estimate_stat=%s\n" "$selected_stat"
  printf "sample_count=%s\n" "$sample_count"
  printf "candidate_scene_count=%s\n" "$scene_count"
  printf "worst_scene_start=%s\n" "$worst_start"
  printf "worst_scene_end=%s\n" "$worst_end"
  printf "worst_scene_score_at_crf_init_selected=%s\n" "$worst_score"
  printf "worst_scene_score_at_crf_init_mean=%s\n" "$worst_mean"
  printf "worst_scene_score_at_crf_init_p05=%s\n" "$worst_p05"
  printf "worst_scene_score_at_crf_init_p10=%s\n" "$worst_p10"
  printf "target_quality=%s\n" "$target"
  printf "search_result=%s\n" "$search_result"
  printf "best_crf=%s\n" "$best_crf"

  if [[ -f "$workdir/search_scores.tsv" ]]; then
    printf "evaluated_crfs="
    awk 'BEGIN { first = 1 } { if (!first) printf ","; printf "%s:%s:%s:%s:%s", $1, $2, $3, $4, $5; first = 0 } END { printf "\n" }' "$workdir/search_scores.tsv"
  fi

  trap - EXIT INT TERM HUP
  crf_estimator_cleanup_workdir "$keep_temp" "$workdir"
}
