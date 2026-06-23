#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEFAULT_PACKAGES_FILE="$REPO_ROOT/home/dot-vim/config/packages.vim"

PACKAGES_FILE="${PACKAGES_FILE:-}"
SUMMARY_FILE="${SUMMARY_FILE:-}"

log() {
  printf '==> %s\n' "$*" >&2
}

error() {
  printf 'ERROR: %s\n' "$*" >&2
}

usage() {
  printf 'Usage: %s [-p|--packages-file <path>] [-s|--summary-file <path>]\n' "$0" >&2
  printf 'Environment overrides: PACKAGES_FILE, SUMMARY_FILE\n' >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--packages-file)
        PACKAGES_FILE="$2"
        shift 2
        ;;
      -s|--summary-file)
        SUMMARY_FILE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  PACKAGES_FILE="${PACKAGES_FILE:-$DEFAULT_PACKAGES_FILE}"
}

# Validation-first parser for home/dot-vim/config/packages.vim.
# Emits one tab-separated record per target:
#   <kind>\t<url>\t<old_sha>\t<line>
# where <kind> is one of:
#   minpac_const  -> const MINPAC_REV = '<sha>' line (minpac itself)
#   inline_rev    -> rev: '<sha>' line inside a non-minpac minpac#add() block
parse_packages() {
  local file="$1"
  perl - "$file" <<'PERL'
use strict;
use warnings;

my $file = $ARGV[0];
open my $fh, '<', $file or die "Cannot open $file: $!\n";
my @lines = <$fh>;
close $fh;
my $text = join '', @lines;

# --- MINPAC_REV constant -----------------------------------------------------
my @const_matches;
while ($text =~ /^(\s*const\s+MINPAC_REV\s*=\s*['"])([0-9a-f]{40})(['"][ \t]*)$/mg) {
  my $line = 1 + substr($text, 0, pos($text)) =~ tr/\n//;
  push @const_matches, [$line, $2];
}

if (@const_matches != 1) {
  die "parse error: expected exactly one 'const MINPAC_REV = '<sha>'' line, found "
      . scalar(@const_matches) . "\n";
}

my ($const_line, $minpac_sha) = @{$const_matches[0]};

# --- minpac#add() blocks ------------------------------------------------------
# Find every GitHub minpac#add call first.  After parsing we verify that each
# one was consumed by the validated block parser, so unsupported/ambiguous
# shapes (e.g. nested braces) are rejected instead of silently skipped.
my @github_call_positions;
{
  my $scan = $text;
  pos($scan) = 0;
  # Detect both single- and double-quoted GitHub URLs, including whitespace or
  # newlines after the opening parenthesis, so unsupported formatting variants
  # are flagged below as parse errors instead of silently ignored. The validated
  # parser remains conservative and does not accept these whitespace variants.
  while ($scan =~ /minpac#add\(\s*(['"])https:\/\/github\.com\//gs) {
    my $pos = pos($scan) - length($&);  # 0-based start of minpac#add(
    my $line = 1 + substr($scan, 0, $pos) =~ tr/\n//;
    push @github_call_positions, [$pos, $line];
  }
}

my @blocks;
my %parsed_positions;
while ($text =~ /minpac#add\('([^']+)'\s*,\s*\{([^\}]*)\}\)/gs) {
  my $url = $1;
  my $block = $2;
  # start position of the whole match, then count newlines before it
  my $start_pos = pos($text) - length($&) + 1;
  my $block_line = 1 + substr($text, 0, $start_pos) =~ tr/\n//;
  $parsed_positions{$start_pos - 1} = 1;  # $start_pos is 1-based; store 0-based

  my @rev_matches;
  while ($block =~ /(\s*)rev\s*:\s*(MINPAC_REV|['"]([0-9a-f]{40})['"])/g) {
    my $rev_start = pos($block) - length($&) + 1;
    my $rev_line_in_block = 1 + substr($block, 0, $rev_start) =~ tr/\n//;
    push @rev_matches, [$1, $2, $3, $block_line + $rev_line_in_block - 1];
  }

  if (@rev_matches != 1) {
    die "parse error: minpac#add() block at line $block_line has "
        . scalar(@rev_matches) . " 'rev:' entries (expected exactly one)\n";
  }

  my ($indent, $rev_val, $sha, $rev_line) = @{$rev_matches[0]};
  push @blocks, {
    url       => $url,
    block_line=> $block_line,
    rev_line  => $rev_line,
    rev_val   => $rev_val,
    sha       => $sha,
  };
}

foreach my $call (@github_call_positions) {
  my ($pos, $line) = @$call;
  if (!$parsed_positions{$pos}) {
    die "parse error: GitHub minpac#add() at line $line could not be safely parsed (unsupported/ambiguous shape)\n";
  }
}

# --- Validate minpac block ---------------------------------------------------
my @minpac_blocks = grep { $_->{url} =~ /k-takata\/minpac\.git$/ } @blocks;
if (@minpac_blocks != 1) {
  die "parse error: expected exactly one k-takata/minpac.git block, found "
      . scalar(@minpac_blocks) . "\n";
}
my $minpac_block = $minpac_blocks[0];
if ($minpac_block->{rev_val} ne 'MINPAC_REV') {
  die "parse error: k-takata/minpac.git block at line "
      . $minpac_block->{rev_line} . " must use 'rev: MINPAC_REV'\n";
}

# --- Emit records ------------------------------------------------------------
print "minpac_const\t$minpac_block->{url}\t$minpac_sha\t$const_line\n";

foreach my $block (@blocks) {
  next if $block->{url} =~ /k-takata\/minpac\.git$/;
  if (!defined $block->{sha}) {
    die "parse error: block at line " . $block->{rev_line}
        . " for " . $block->{url}
        . " does not contain a 40-character hex rev\n";
  }
  print "inline_rev\t$block->{url}\t$block->{sha}\t$block->{rev_line}\n";
}
PERL
}

fetch_latest_sha() {
  local url="$1"
  log "Fetching latest HEAD for $url"
  local output
  if ! output="$(git ls-remote "$url" HEAD 2>&1)"; then
    error "Failed to fetch latest HEAD from $url"
    error "$output"
    return 1
  fi

  local sha
  sha="$(printf '%s\n' "$output" | awk 'NR==1 {print $1}')"

  if [[ -z "$sha" ]]; then
    error "Empty result from $url"
    return 1
  fi

  if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    error "Invalid SHA from $url: '$sha'"
    return 1
  fi

  printf '%s\n' "$sha"
}

# Rewrite only the parsed target lines on a temporary copy, verifying each
# expected old SHA before replacing it. Records are tab-separated:
#   <kind>\t<line>\t<old_sha>\t<new_sha>
rewrite_packages() {
  local infile="$1"
  local outfile="$2"
  shift 2

  perl - "$infile" "$outfile" "$@" <<'PERL'
use strict;
use warnings;

my $infile  = $ARGV[0];
my $outfile = $ARGV[1];
my @repls;
for (my $i = 2; $i < @ARGV; $i++) {
  my @f = split /\t/, $ARGV[$i], 4;
  if (@f != 4) {
    die "rewrite error: malformed replacement record: $ARGV[$i]\n";
  }
  push @repls, { kind => $f[0], line => $f[1], old => $f[2], new => $f[3] };
}

open my $in, '<', $infile or die "Cannot open $infile: $!\n";
my @lines = <$in>;
close $in;

foreach my $r (@repls) {
  my $idx = $r->{line} - 1;
  if ($idx < 0 || $idx >= @lines) {
    die "rewrite error: line $r->{line} is out of range\n";
  }
  my $line = $lines[$idx];

  if ($r->{kind} eq 'minpac_const') {
    if ($line !~ /const\s+MINPAC_REV\s*=\s*['"]\Q$r->{old}\E['"]/) {
      die "rewrite error: line $r->{line} does not contain expected MINPAC_REV SHA $r->{old}\n";
    }
  } elsif ($r->{kind} eq 'inline_rev') {
    if ($line !~ /rev\s*:\s*['"]\Q$r->{old}\E['"]/) {
      die "rewrite error: line $r->{line} does not contain expected inline rev SHA $r->{old}\n";
    }
  } else {
    die "rewrite error: unknown kind '$r->{kind}'\n";
  }

  $line =~ s/\Q$r->{old}\E/$r->{new}/;
  $lines[$idx] = $line;
}

open my $out, '>', $outfile or die "Cannot open $outfile: $!\n";
print $out @lines;
close $out;
PERL
}

write_summary() {
  local file="$1"
  shift
  local -a updates=("$@")

  {
    printf '## Vim Plugin Revisions Update\n\n'
    printf 'Updated `%s` plugin pins to the latest upstream HEAD.\n\n' 'home/dot-vim/config/packages.vim'
    printf '| Repository | Old SHA | New SHA |\n'
    printf '|------------|---------|---------|\n'
    for update in "${updates[@]}"; do
      local kind url old_sha new_sha line
      IFS=$'\t' read -r kind url old_sha new_sha line <<< "$update"
      printf '| `%s` | `%s` | `%s` |\n' "$url" "$old_sha" "$new_sha"
    done
  } > "$file"
}

main() {
  parse_args "$@"

  if [[ ! -f "$PACKAGES_FILE" ]]; then
    error "Packages file not found: $PACKAGES_FILE"
    exit 1
  fi

  log "Parsing $PACKAGES_FILE"
  local parse_output_file
  parse_output_file="${PACKAGES_FILE}.parse.$$"
  # shellcheck disable=SC2064
  trap "rm -f '$parse_output_file'" EXIT

  if ! parse_packages "$PACKAGES_FILE" > "$parse_output_file"; then
    error "Failed to parse $PACKAGES_FILE"
    exit 1
  fi

  local -a records=()
  mapfile -t records < "$parse_output_file"
  rm -f "$parse_output_file"
  trap - EXIT

  local -a updates=()
  local record kind url old_sha line new_sha
  for record in "${records[@]}"; do
    IFS=$'\t' read -r kind url old_sha line <<< "$record"
    new_sha="$(fetch_latest_sha "$url")"

    if [[ "$old_sha" != "$new_sha" ]]; then
      updates+=("$kind"$'\t'"$url"$'\t'"$old_sha"$'\t'"$new_sha"$'\t'"$line")
      log "Update available for $url: $old_sha -> $new_sha"
    else
      log "$url is already at HEAD ($old_sha)"
    fi
  done

  if [[ ${#updates[@]} -eq 0 ]]; then
    log "No plugin revisions to update"
    if [[ -n "$SUMMARY_FILE" ]]; then
      printf 'No plugin revisions to update.\n' > "$SUMMARY_FILE"
    fi
    exit 0
  fi

  log "Applying ${#updates[@]} update(s)"

  # Build the summary into a temp file before touching packages.vim so a
  # summary write failure cannot leave the tracked file modified.
  local summary_tmp=""
  if [[ -n "$SUMMARY_FILE" ]]; then
    summary_tmp="${SUMMARY_FILE}.tmp.$$"
  fi

  local packages_tmp
  packages_tmp="${PACKAGES_FILE}.tmp.$$"

  # shellcheck disable=SC2064
  trap "rm -f '$packages_tmp' '${summary_tmp:-}'" EXIT

  if [[ -n "$summary_tmp" ]]; then
    write_summary "$summary_tmp" "${updates[@]}"
  fi

  local -a repl_args=()
  for update in "${updates[@]}"; do
    IFS=$'\t' read -r kind url old_sha new_sha line <<< "$update"
    repl_args+=("$kind"$'\t'"$line"$'\t'"$old_sha"$'\t'"$new_sha")
  done

  rewrite_packages "$PACKAGES_FILE" "$packages_tmp" "${repl_args[@]}"

  # Finalize the summary (if requested) before touching PACKAGES_FILE so that a
  # summary rename failure exits non-zero with the tracked file still intact.
  # Both moves happen only after all validation, rewrite, and temp-summary
  # generation have succeeded.
  if [[ -n "$summary_tmp" ]]; then
    mv "$summary_tmp" "$SUMMARY_FILE"
  fi
  mv "$packages_tmp" "$PACKAGES_FILE"
  trap - EXIT

  log "Updated $PACKAGES_FILE"
  if [[ -n "$SUMMARY_FILE" ]]; then
    log "Summary written to $SUMMARY_FILE"
  fi
}

main "$@"
