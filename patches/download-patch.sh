#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: download-patch.sh [--msgid MSGID] [--outdir DIR] [--no-clean]

Download a complete lore.kernel.org patch thread as individual .patch files.

Defaults:
  MSGID:  20260731-dw-hdmi-qp-scramb-v10-0-294364b2cf15@collabora.com
  OUTDIR: directory containing this script

The generated filenames are ordered by the patch number in the Subject header
([PATCH vN X/Y]), not by lore/mailbox order.  A series-order.txt file is also
written and can be passed to git-am with: xargs -a series-order.txt git am
EOF
}

msgid='20260731-dw-hdmi-qp-scramb-v10-0-294364b2cf15@collabora.com'
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
outdir="$script_dir"
clean=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --msgid)
            msgid="${2:?missing value for --msgid}"
            shift 2
            ;;
        --outdir)
            outdir="${2:?missing value for --outdir}"
            shift 2
            ;;
        --no-clean)
            clean=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ $# -eq 1 ]]; then
                outdir="$1"
                shift
            else
                echo "unknown argument: $1" >&2
                usage >&2
                exit 2
            fi
            ;;
    esac
done

base="https://lore.kernel.org/linux-rockchip/${msgid}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$outdir" "$tmp/split" "$tmp/patches"

echo "Downloading complete patch thread: $msgid"
wget -q --show-progress -O "$tmp/series.mbox.gz" "${base}/t.mbox.gz"
gzip -dc "$tmp/series.mbox.gz" > "$tmp/series.mbox"

echo "Splitting messages..."
git mailsplit -o"$tmp/split" "$tmp/series.mbox" >/dev/null

if [[ "$clean" -eq 1 ]]; then
    rm -f "$outdir"/*.patch "$outdir/series-order.txt"
fi

count=0
while IFS= read -r mail; do
    grep -q '^diff --git ' "$mail" || continue

    subject="$(
        sed -n '/^Subject:/ {
            s/^Subject:[[:space:]]*//
            p
            q
        }' "$mail"
    )"

    # Prefer the actual series number from [PATCH vN X/Y].  Fall back to
    # mailbox order if a future thread uses unusual subject formatting.
    number="$(
        printf '%s' "$subject" |
        sed -nE 's/^\[PATCH[^]]* ([0-9]+)\/[0-9]+\].*/\1/p'
    )"
    if [[ -z "$number" ]]; then
        count=$((count + 1))
        number="$count"
    fi

    name="$(
        printf '%s' "$subject" |
        sed -E \
            -e 's/^\[PATCH[^]]*\][[:space:]]*//' \
            -e 's/[^A-Za-z0-9._-]+/-/g' \
            -e 's/^-+//' \
            -e 's/-+$//' |
        cut -c1-120
    )"

    dst="$tmp/patches/$(printf '%04d' "$number")-${name}.patch"
    cp "$mail" "$dst"
done < <(find "$tmp/split" -type f | sort)

mapfile -t patches < <(find "$tmp/patches" -name '*.patch' | sort)
if [[ "${#patches[@]}" -eq 0 ]]; then
    echo "no patches found in downloaded thread" >&2
    exit 1
fi

for patch in "${patches[@]}"; do
    dst="$outdir/$(basename "$patch")"
    cp "$patch" "$dst"
    printf '%s\n' "$dst" >> "$outdir/series-order.txt"
    echo "  $(basename "$dst")"
done

echo
echo "Downloaded ${#patches[@]} patches into $outdir/"
echo "Series order written to $outdir/series-order.txt"
