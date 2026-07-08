#!/bin/sh

set -eu

PATH=/usr/bin:/bin
export PATH

file_path=${1:-}
width=${2:-80}
height=${3:-24}
mode=${6:-preview}
cell_width=${LF_PREVIEW_CELL_WIDTH:-40}
cell_height=${LF_PREVIEW_CELL_HEIGHT:-18}

if [ -z "$file_path" ]; then
    exit 1
fi

sanitize_terminal_text() {
    perl -pe 's/[\x00-\x08\x0b-\x1f\x7f\x80-\x9f]//g'
}

sanitize_terminal_path_value() {
    perl -0pe 's/\\/\\\\/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g; s/([\x00-\x08\x0b-\x1f\x7f\x80-\x9f])/sprintf("\\x%02X", ord($1))/ge'
}

sanitize_terminal_path_lines() {
    perl -pe 's/\\/\\\\/g; s/\t/\\t/g; s/\r/\\r/g; s/([\x00-\x08\x0b-\x1f\x7f\x80-\x9f])/sprintf("\\x%02X", ord($1))/ge'
}

if [ ! -e "$file_path" ]; then
    printf 'missing: '
    printf '%s' "$file_path" | sanitize_terminal_path_value
    printf '\n'
    exit 0
fi

if [ -L "$file_path" ]; then
    link_target=$(readlink -- "$file_path" 2>/dev/null || printf '?')
    printf 'symlink -> '
    printf '%s' "$link_target" | sanitize_terminal_path_value
    printf '\n'
    exit 0
fi

mime=$(file --dereference --brief --mime-type -- "$file_path" 2>/dev/null || printf 'application/octet-stream')

show_file_fallback() {
    file --brief --dereference -- "$1"
}

show_text_preview() {
    {
        sed -n "1,${height}p" -- "$1" 2>/dev/null ||
            head -n "$height" -- "$1" 2>/dev/null ||
            true
    } | sanitize_terminal_text
}

show_directory_preview() {
    if [ "$mode" = "preview" ]; then
        find "$1" -mindepth 1 -maxdepth 1 2>/dev/null |
            sed 's#^.*/##' |
            head -n "$height" |
            sanitize_terminal_path_lines
    else
        printf '%s' "$1" | sanitize_terminal_path_value
        printf '\n'
    fi
}

emit_sixel_preview() {
    input=$1
    output=$2

    if img2sixel "$input" >"$output" 2>/dev/null && [ -s "$output" ]; then
        return 0
    fi

    if command -v chafa >/dev/null 2>&1 &&
        chafa --format=sixels "$input" >"$output" 2>/dev/null &&
        [ -s "$output" ]; then
        return 0
    fi

    return 1
}

ffmpeg_to_ppm() {
    input_path=$1
    ffmpeg -hide_banner -loglevel error \
        -i "$input_path" \
        -frames:v 1 \
        -vf "scale='min(iw,${width}*${cell_width})':'min(ih,${height}*${cell_height})':force_original_aspect_ratio=decrease" \
        -f image2pipe \
        -vcodec ppm \
        -
}

show_media_preview() {
    media_ppm=$(mktemp "${TMPDIR:-/tmp}/lf-preview-media.XXXXXX") || return 1
    media_out=$(mktemp "${TMPDIR:-/tmp}/lf-preview-out.XXXXXX") || {
        rm -f "$media_ppm"
        return 1
    }

    if ! ffmpeg_to_ppm "$1" >"$media_ppm" 2>/dev/null ||
        [ ! -s "$media_ppm" ] ||
        ! emit_sixel_preview "$media_ppm" "$media_out"; then
        rm -f "$media_ppm" "$media_out"
        return 1
    fi

    cat -- "$media_out"
    rm -f "$media_ppm" "$media_out"
}

show_pdf_preview() {
    pdf_text=$(mktemp "${TMPDIR:-/tmp}/lf-preview-pdf.XXXXXX") || return 1

    if pdftotext -l 10 -nopgbrk -- "$1" "$pdf_text" 2>/dev/null &&
        [ -s "$pdf_text" ]; then
        head -n "$height" -- "$pdf_text" | sanitize_terminal_text
        rm -f "$pdf_text"
        return 0
    fi

    rm -f "$pdf_text"

    show_media_preview "$1"
}

case "$mime" in
    text/*|application/json|application/xml|application/javascript|application/x-shellscript|inode/x-empty)
        show_text_preview "$file_path"
        ;;
    image/*|video/*)
        show_media_preview "$file_path" || show_file_fallback "$file_path"
        ;;
    application/pdf)
        show_pdf_preview "$file_path" || show_file_fallback "$file_path"
        ;;
    inode/directory)
        show_directory_preview "$file_path"
        ;;
    *)
        show_file_fallback "$file_path"
        ;;
esac
