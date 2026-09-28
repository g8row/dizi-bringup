#!/usr/bin/env python3
"""Module symbol helpers: exports (__crc_* absolute syms), imports (__versions).
Usage:
  modsyms.py exports X.ko            -> "crc name" lines
  modsyms.py imports X.ko            -> "crc name" lines
  modsyms.py symvers out.symvers X.ko...   -> synthesize Module.symvers from prebuilt modules
  modsyms.py users SYM-SOURCE.ko DIR...    -> stock modules importing any export of SOURCE, with CRCs
"""
import struct, sys, os, glob, subprocess
NM = os.path.join(os.path.dirname(__file__), '../../clang-r416183b/bin/llvm-nm')

def sections(d):
    shoff, = struct.unpack_from('<Q', d, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x3a)
    secs = [struct.unpack_from('<IIQQQQIIQQ', d, shoff + i * shentsize) for i in range(shnum)]
    so = secs[shstrndx][4]
    for s in secs:
        yield d[so + s[0]:d.index(b'\0', so + s[0])].decode(), s

def imports(p):
    d = open(p, 'rb').read(); out = {}
    for n, s in sections(d):
        if n == '__versions':
            for i in range(0, s[5], 64):
                crc, = struct.unpack_from('<Q', d, s[4] + i)
                out[d[s[4]+i+8:s[4]+i+64].split(b'\0')[0].decode()] = crc & 0xffffffff
    return out

def exports(p):
    out = {}
    r = subprocess.run([NM, p], capture_output=True, text=True).stdout
    syms = set(); crcs = {}
    for l in r.splitlines():
        f = l.split()
        if len(f) < 3: continue
        if f[2].startswith('__crc_'): crcs[f[2][6:]] = int(f[0], 16)
        elif f[2].startswith('__ksymtab_'): syms.add(f[2][10:])
    for s in syms: out[s] = crcs.get(s)
    return out

def modname(p):
    return os.path.basename(p)[:-3]

if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd in ('exports', 'imports'):
        for k, v in sorted((exports if cmd == 'exports' else imports)(sys.argv[2]).items()):
            print('0x%08x %s' % (v or 0, k))
    elif cmd == 'symvers':
        with open(sys.argv[2], 'w') as f:
            for p in sys.argv[3:]:
                for k, v in sorted(exports(p).items()):
                    # GPL-ness is not recoverable from the ksymtab section name in 5.10 w/ LTO; use EXPORT_SYMBOL_GPL (only matters for non-GPL users)
                    f.write('0x%08x\t%s\t%s\tEXPORT_SYMBOL_GPL\t\n' % (v or 0, k, os.path.abspath(p)[:-3]))
    elif cmd == 'users':
        ex = exports(sys.argv[2]); me = modname(sys.argv[2])
        seen = set()
        for dd in sys.argv[3:]:
            for p in sorted(glob.glob(dd + '/*.ko')):
                m = modname(p)
                if m == me or m in seen: continue
                seen.add(m)
                for s, c in sorted(imports(p).items()):
                    if s in ex:
                        print('%s\t%s\t0x%08x\t%s' % (m, s, c, 'OK' if c == ex[s] else 'MISMATCH(export 0x%08x)' % (ex[s] or 0)))
