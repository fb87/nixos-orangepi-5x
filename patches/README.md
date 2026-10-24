# Kernel patch stack

This directory contains the HDMI/DRM patch series backported for Linux
`/tmp/linux-7.1.8`.

## Download a fresh lore series

Use the helper script in this directory:

```sh
cd /pst/conf/machines/kernel/patches
./download-patch.sh --outdir /tmp/new-hdmi-patches
```

For a different lore thread:

```sh
./download-patch.sh \
  --msgid 'MESSAGE-ID@domain.example' \
  --outdir /tmp/new-hdmi-patches
```

The script downloads the full `t.mbox.gz` thread from lore, keeps only messages
containing `diff --git`, names patches by the `[PATCH vN X/Y]` subject number,
and writes `series-order.txt` for reproducible application.

## Apply/backport loop

Patch filenames in this repo have not always matched upstream series order, so
apply by `series-order.txt` or by sorting the `Subject: [PATCH ... X/Y]` number.

Typical loop against `/tmp/linux-7.1.8`:

```sh
cd /tmp/linux-7.1.8
git am --abort 2>/dev/null || true
git reset --hard 3d5efe703
git clean -fdx
xargs -a /pst/conf/machines/kernel/patches/series-order.txt git am
```

If `series-order.txt` is not present, regenerate one from the current directory:

```sh
python - <<'PY' > /tmp/patch-list.txt
from pathlib import Path
import re
for p in Path('/pst/conf/machines/kernel/patches').glob('*.patch'):
    if p.stat().st_size == 0:
        continue
    m = re.search(r'Subject: \[PATCH v\d+ (\d+)/\d+\]', p.read_text(errors='replace'))
    print((int(m.group(1)) if m else 9999), p)
PY
sort -n /tmp/patch-list.txt | cut -d' ' -f2- > /tmp/patch-list.sorted.txt
xargs -a /tmp/patch-list.sorted.txt git am
```

When a patch fails:

```sh
git am --show-current-patch=diff
git status
```

Then either:

- adapt the corresponding `.patch` file in this directory;
- skip if the change is already present or irrelevant; or
- for test-only patches that do not match this kernel's KUnit layout, reduce or
  drop the test change while preserving runtime code patches.

After every adaptation, restart from a clean tree and re-apply the entire series
to ensure the patch files are reproducible.

## Current validation

The adapted series was validated with:

```sh
cd /tmp/linux-7.1.8
git am --abort 2>/dev/null || true
git reset --hard 3d5efe703
git clean -fdx
xargs -a /tmp/patch-list.txt git am
```

The stack applied successfully through:

```text
drm/connector: Drop redundant max_bpc field
```
