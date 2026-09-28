#!/usr/bin/env python3
"""Copy file mtimes from a reference repo tree onto identical files of another.

Usage: match-mtimes.py <ref-top> <dst-top>

For every repo project in <dst-top>, files whose git blob and mode match the
reference project at the same path get the reference file's timestamps, so an
out/ dir copied from the reference sees them as unchanged and ninja only
rebuilds what really differs.
"""
import os
import subprocess
import sys
from pathlib import Path


def ls_files(path: Path) -> dict[bytes, tuple[bytes, bytes]]:
    """Map tracked file name -> (mode, blob), skipping submodules."""
    out = subprocess.run(["git", "-C", path, "ls-files", "-s", "-z"],
                         capture_output=True, check=True).stdout
    files = {}
    for entry in filter(None, out.split(b"\0")):
        meta, name = entry.split(b"\t", 1)
        mode, blob, _ = meta.split()
        if mode != b"160000":
            files[name] = (mode, blob)
    return files


def main() -> None:
    ref, dst = (Path(p) for p in sys.argv[1:3])
    projects = subprocess.run(["repo", "list", "-p"], cwd=dst, capture_output=True,
                              text=True, check=True).stdout.split()
    same = differ = 0
    for proj in projects:
        rp, dp = ref / proj, dst / proj
        if not (rp / ".git").exists():
            print(f"{proj}: not in ref")
            continue
        rfiles = ls_files(rp)
        changed = 0
        for name, key in ls_files(dp).items():
            if rfiles.get(name) != key:
                changed += 1
                continue
            try:
                st = os.lstat(rp / os.fsdecode(name))
                os.utime(dp / os.fsdecode(name), ns=(st.st_atime_ns, st.st_mtime_ns),
                         follow_symlinks=False)
                same += 1
            except FileNotFoundError:
                changed += 1
        differ += changed
        if changed:
            print(f"{proj}: {changed} differing files")
    print(f"matched {same} files, {differ} differ")


if __name__ == "__main__":
    main()
