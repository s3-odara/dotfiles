#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/mozuku-install}"
SRC_DIR="$CACHE_DIR/src"
BUILD_DIR="$CACHE_DIR/build"
MOZUKU_REPO_URL="${MOZUKU_REPO_URL:-https://github.com/t3tra-dev/MoZuku}"
MOZUKU_SRC="$SRC_DIR/MoZuku"
MECAB_SRC="$SRC_DIR/mecab"
CRFPP_SRC="$SRC_DIR/crfpp"
CABOCHA_SRC="$SRC_DIR/cabocha"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_DIR="$PROJECT_ROOT/patch"

export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export CPPFLAGS="-I$PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib ${LDFLAGS:-}"

log() {
  printf '==> %s\n' "$*"
}

run() {
  log "$*"
  "$@"
}

ensure_dirs() {
  mkdir -p "$SRC_DIR" "$BUILD_DIR" "$PREFIX"
}

sync_repo() {
  local url="$1"
  local dir="$2"

  if [[ -d "$dir/.git" ]]; then
    log "Using existing source: $dir"
    return
  fi

  run git clone --depth 1 "$url" "$dir"
}

system_packages() {
  run sudo pacman -Sy --noconfirm
  run sudo pacman -S --needed --noconfirm \
    base-devel \
    ccache \
    cmake \
    curl \
    gettext \
    nodejs \
    npm \
    pkgconf \
    rust \
    tree-sitter \
    tree-sitter-cli
}

fetch_sources() {
  ensure_dirs

  sync_repo https://github.com/taku910/mecab.git "$MECAB_SRC"
  sync_repo https://github.com/taku910/crfpp.git "$CRFPP_SRC"
  sync_repo https://github.com/taku910/cabocha.git "$CABOCHA_SRC"
  sync_repo "$MOZUKU_REPO_URL" "$MOZUKU_SRC"

  run git -C "$MOZUKU_SRC" \
  -c submodule.fetchJobs="$(nproc)" \
  submodule update --init \
  --depth 1 \
  --recommend-shallow \
  --jobs "$(nproc)" \
  mozuku-lsp/third-party/json \
  mozuku-lsp/third-party/tree-sitter-c \
  mozuku-lsp/third-party/tree-sitter-cpp \
  mozuku-lsp/third-party/tree-sitter-html \
  mozuku-lsp/third-party/tree-sitter-javascript \
  mozuku-lsp/third-party/tree-sitter-python \
  mozuku-lsp/third-party/tree-sitter-rust \
  mozuku-lsp/third-party/tree-sitter-typescript \
  mozuku-lsp/third-party/tree-sitter-latex

  local submodule_dir
  for submodule_dir in \
    "$MOZUKU_SRC/mozuku-lsp/third-party/tree-sitter-html" \
    "$MOZUKU_SRC/mozuku-lsp/third-party/tree-sitter-javascript" \
    "$MOZUKU_SRC/mozuku-lsp/third-party/tree-sitter-python" \
    "$MOZUKU_SRC/mozuku-lsp/third-party/tree-sitter-rust" \
    "$MOZUKU_SRC/mozuku-lsp/third-party/tree-sitter-typescript" \
    "$MOZUKU_SRC/mozuku-lsp/third-party/tree-sitter-latex"; do
    run git -C "$submodule_dir" checkout HEAD -- .
  done
}

install_mecab() {
  ensure_dirs
  fetch_sources

  cd "$MECAB_SRC/mecab"
  run sed -i 's!prefix@/libexec!libexecdir@!g' mecab-config.in
  run ./configure \
    --prefix="$PREFIX" \
    --sysconfdir="$PREFIX/etc" \
    --libexecdir="$PREFIX/lib/mecab" \
    --with-charset=utf-8
  run make -j"$(nproc)"
  run make install
}

configure_local_mecabrc() {
  local mecabrc="$PREFIX/etc/mecabrc"

  mkdir -p "$(dirname "$mecabrc")"
  if [[ ! -f "$mecabrc" ]]; then
    printf 'dicdir = %s/lib/mecab/dic/ipadic\n' "$PREFIX" >"$mecabrc"
    return
  fi

  if grep -Eq '^[[:space:]]*dicdir[[:space:]]*=' "$mecabrc"; then
    run sed -Ei "s|^[[:space:]]*dicdir[[:space:]]*=.*$|dicdir = $PREFIX/lib/mecab/dic/ipadic|" "$mecabrc"
  else
    printf '\ndicdir = %s/lib/mecab/dic/ipadic\n' "$PREFIX" >>"$mecabrc"
  fi
}

install_mecab_ipadic() {
  ensure_dirs
  fetch_sources

  cd "$MECAB_SRC/mecab-ipadic"
  run sed -i "s|^MECAB_DICT_INDEX=.*|MECAB_DICT_INDEX=$PREFIX/lib/mecab/mecab/mecab-dict-index|g" configure configure.in
  run ./configure \
    --prefix="$PREFIX" \
    --libexecdir="$PREFIX/lib/mecab" \
    --with-mecab-config="$PREFIX/bin/mecab-config" \
    --with-dicdir="$PREFIX/lib/mecab/dic/ipadic" \
    --with-charset=utf-8
  run make -j"$(nproc)"
  run make install

  configure_local_mecabrc
}

patch_crfpp_for_linux() {
  local file
  for file in "$CRFPP_SRC/crf_learn.cpp" "$CRFPP_SRC/crf_test.cpp"; do
    if grep -q '#include "winmain.h"' "$file"; then
      run sed -i '/#include "winmain.h"/d' "$file"
    fi
  done
}

install_crfpp() {
  ensure_dirs
  fetch_sources
  patch_crfpp_for_linux

  cd "$CRFPP_SRC"
  run ./configure --prefix="$PREFIX"
  run make -j"$(nproc)"
  run make install
}

install_cabocha() {
  ensure_dirs
  fetch_sources

  cd "$CABOCHA_SRC"
  if [[ ! -f install-sh || ! -f missing || ! -f compile ]]; then
    log "Installing missing automake helper files for CaboCha"
    automake --add-missing --copy || true
  fi

  run ./configure \
    --prefix="$PREFIX" \
    --with-charset=UTF8 \
    --enable-utf8-only \
    --with-mecab-config="$PREFIX/bin/mecab-config"
  run make -j"$(nproc)"
  run make install
}

prepare_tree_sitter() {
  ensure_dirs
  fetch_sources

  local latex_dir="$MOZUKU_SRC/mozuku-lsp/third-party/tree-sitter-latex"

  if [[ ! -f "$latex_dir/src/parser.c" ]]; then
    cd "$latex_dir"
    run tree-sitter generate
  fi
}

apply_mozuku_patches() {
  ensure_dirs
  fetch_sources

  if [[ ! -d "$PATCH_DIR" ]]; then
    log "No patch directory found: $PATCH_DIR"
    return 0
  fi

  local patch_file
  local applied_any=false
  shopt -s nullglob

  for patch_file in "$PATCH_DIR"/*.patch; do
    if git -C "$MOZUKU_SRC" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
      log "Patch already applied: $(basename "$patch_file")"
      continue
    fi

    run git -C "$MOZUKU_SRC" apply "$patch_file"
    applied_any=true
  done

  shopt -u nullglob

  if [[ "$applied_any" == false ]]; then
    log "No new Mozuku patches to apply"
  fi
}

install_mozuku() {
  ensure_dirs
  fetch_sources
  apply_mozuku_patches
  prepare_tree_sitter

  cd "$MOZUKU_SRC"
  run cmake -S mozuku-lsp -B mozuku-lsp/build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$PREFIX;/usr" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
  run cmake --build mozuku-lsp/build -j"$(nproc)"
  run cmake --install mozuku-lsp/build
}

verify_installation() {
  log "Verifying MeCab dictionary"
  "$PREFIX/bin/mecab" -D 2>&1 | sed -n '1,8p' || true

  log "Verifying CaboCha"
  printf 'これはテストです。\n' | "$PREFIX/bin/cabocha" -f1 | sed -n '1,10p'

  log "Checking mozuku-lsp binary"
  [[ -x "$PREFIX/bin/mozuku-lsp" ]]
  if ldd "$PREFIX/bin/mozuku-lsp" | grep -Fq 'not found'; then
    printf 'mozuku-lsp has unresolved shared libraries\n' >&2
    return 1
  fi
}

all() {
  system_packages
  fetch_sources
  install_mecab
  install_mecab_ipadic
  install_crfpp
  install_cabocha
  prepare_tree_sitter
  install_mozuku
  verify_installation
}

main() {
  local command="${1:-all}"

  case "$command" in
    all) all ;;
    system-packages) system_packages ;;
    fetch-sources) fetch_sources ;;
    install-mecab) install_mecab ;;
    install-mecab-ipadic) install_mecab_ipadic ;;
    install-crfpp) install_crfpp ;;
    install-cabocha) install_cabocha ;;
    prepare-tree-sitter) prepare_tree_sitter ;;
    apply-mozuku-patches) apply_mozuku_patches ;;
    install-mozuku) install_mozuku ;;
    verify) verify_installation ;;
    *)
      printf 'Unknown command: %s\n' "$command" >&2
      return 1
      ;;
  esac
}

main "$@"
