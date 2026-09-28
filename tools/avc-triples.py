#!/usr/bin/env python3
"""Reduce raw avc denial lines to unique (scontext, tcontext, class) rows with
the union of permissions and a sample of comm/name values.

Usage: avc-triples.py avc-raw.txt [> triples.txt]
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

AVC = re.compile(r'avc: +denied +\{ ([^}]*) \} for (.*?)scontext=u:r:(\S+?):s0\S* '
                 r'tcontext=u:(?:object_r|r):(\S+?):s0\S* tclass=(\S+)')
NAME = re.compile(r'(?:comm|name|path)="([^"]*)"')


def main() -> None:
    perms: dict[tuple[str, str, str], set[str]] = defaultdict(set)
    names: dict[tuple[str, str, str], set[str]] = defaultdict(set)
    for line in Path(sys.argv[1]).read_text(errors="replace").splitlines():
        if not (m := AVC.search(line)):
            continue
        key = (m[3], m[4], m[5])
        perms[key].update(m[1].split())
        names[key].update(NAME.findall(m[2]))
    for key in sorted(perms):
        sample = " ".join(sorted(names[key]))[:70]
        print(f"{key[0]:28} {key[1]:34} {key[2]:14} {{ {' '.join(sorted(perms[key]))} }}  {sample}")


if __name__ == "__main__":
    main()
