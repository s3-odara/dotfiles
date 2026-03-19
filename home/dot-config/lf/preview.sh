#!/bin/sh

set -eu

PATH=/usr/bin:/bin
export PATH

file_path=${1:-}
width=${2:-80}
height=${3:-24}
mode=${6:-preview}

if [ -z "$file_path" ]; then
    exit 1
fi

if [ ! -e "$file_path" ]; then
    printf 'missing: %s\n' "$file_path"
    exit 0
fi

if [ -L "$file_path" ]; then
    link_target=$(readlink -- "$file_path" 2>/dev/null || printf '?')
    printf 'symlink -> %s\n' "$link_target"
    exit 0
fi

mime=$(file --dereference --brief --mime-type -- "$file_path" 2>/dev/null || printf 'application/octet-stream')

show_text_preview() {
    sed -n "1,${height}p" -- "$1" 2>/dev/null || head -n "$height" -- "$1" 2>/dev/null || true
}

emit_sixel_from_stdin() {
    img2sixel -w "${width}" -h "${height}" - 2>/dev/null || return 1
}

ffmpeg_to_ppm() {
    input_path=$1
    ffmpeg -hide_banner -loglevel error \
        -i "$input_path" \
        -frames:v 1 \
        -vf "scale='min(iw,${width}*8)':'min(ih,${height}*16)':force_original_aspect_ratio=decrease" \
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
        ! img2sixel -w "${width}" -h "${height}" "$media_ppm" >"$media_out" 2>/dev/null ||
        [ ! -s "$media_out" ]; then
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
        head -n "$height" -- "$pdf_text"
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
        show_media_preview "$file_path" || file --brief --dereference -- "$file_path"
        ;;
    application/pdf)
        show_pdf_preview "$file_path" || file --brief --dereference -- "$file_path"
        ;;
    inode/directory)
        if [ "$mode" = "preview" ]; then
            find "$file_path" -mindepth 1 -maxdepth 1 2>/dev/null | sed 's#^.*/##' | head -n "$height"
        else
            printf '%s\n' "$file_path"
        fi
        ;;
    *)
        file --brief --dereference -- "$file_path"
        ;;
esac
