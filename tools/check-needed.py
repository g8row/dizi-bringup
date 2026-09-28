#!/usr/bin/env python3
"""Static DT_NEEDED check for a built product: every vendor/odm ELF must find
its libraries in vendor/odm lib dirs or the LLNDK set from system.

Usage: check-needed.py <out/target/product/dizi>
"""
import re
import subprocess
import sys
from pathlib import Path


def elf_class(path: Path) -> int | None:
    try:
        with path.open('rb') as f:
            head = f.read(5)
    except OSError:
        return None
    if head[:4] != b'\x7fELF':
        return None
    return 64 if head[4] == 2 else 32


def needed(path: Path) -> list[str]:
    res = subprocess.run(['readelf', '-dW', str(path)], capture_output=True, text=True)
    return re.findall(r'\(NEEDED\).*\[(.+?)\]', res.stdout)


def main() -> None:
    out = Path(sys.argv[1])
    llndk = set((out / 'system/etc/llndk.libraries.txt').read_text().split())
    dirs = {bits: [out / p / sub for p in ('odm', 'vendor') for sub in (lib, f'{lib}/egl', f'{lib}/hw')]
            for bits, lib in ((32, 'lib'), (64, 'lib64'))}
    available = {bits: {f.name for d in ds if d.is_dir() for f in d.iterdir()} for bits, ds in dirs.items()}
    missing: dict[str, list[str]] = {}
    for part in ('vendor', 'odm'):
        for f in sorted((out / part).rglob('*')):
            if f.is_symlink() or not f.is_file() or '/firmware' in str(f):
                continue
            bits = elf_class(f)
            if bits is None:
                continue
            for lib in needed(f):
                if lib not in available[bits] and lib not in llndk:
                    missing.setdefault(f'{lib} ({bits})', []).append(str(f.relative_to(out)))
    for lib, users in sorted(missing.items()):
        print(f'{lib}: {len(users)} users, e.g. {", ".join(users[:3])}')
    print(f'{len(missing)} unresolved libraries', file=sys.stderr)


if __name__ == '__main__':
    main()
