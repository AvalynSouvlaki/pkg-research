#!/usr/bin/env python3
"""elfprobe.py - report what an ELF file actually is, from its bytes.

⭐ This is an ORACLE. It reads the file directly rather than asking the
toolchain that produced it, so a claim like "this build is static" is checked
against the artifact instead of against the compiler's self-report.

It deliberately does not shell out to `file`, `ldd`, `readelf` or `objdump`:

  - `ldd` RUNS the binary's loader. On a foreign architecture it cannot, and
    on a hostile input running it is the whole problem.
  - `file` prints prose meant for a human. Parsing "statically linked" out of
    it couples this check to another project's wording, and the string differs
    between the cases: on this host `file` 5.45 says "statically linked" for
    `gcc -static` and "static-pie linked" for `gcc -static-pie`, so a grep for
    the first silently rejects the second.
  - Neither reports the field in a form a build gate can assert on.

The distinction that matters for distributing a binary to an unknown host is
PT_INTERP: a program header naming a dynamic loader means the host must supply
that exact loader at that exact path. PT_DYNAMIC alone does not, which is why
a static-pie binary is portable despite having a dynamic segment. This probe
reports PT_INTERP as a field, so the gate is a comparison rather than a match
against prose.

Usage:
  elfprobe.py FILE [FILE...]            human readable
  elfprobe.py --json FILE [FILE...]     one JSON object per line
  elfprobe.py --expect-static FILE...   exit 1 if any file has a PT_INTERP

Exit codes: 0 all checks passed, 1 a check failed, 2 could not run.
"""
import json
import struct
import sys

# e_machine -> name. Only the values this project targets, plus the common
# ones a mistake would produce, so a wrong-architecture build is named rather
# than printed as a number.
EM = {
    0x03: "i386", 0x08: "mips", 0x14: "ppc", 0x15: "ppc64", 0x16: "s390x",
    0x28: "arm", 0x2A: "superh", 0x3E: "x86_64", 0xB7: "aarch64",
    0xF3: "riscv64", 0x102: "loongarch64",
}
ET = {0: "ET_NONE", 1: "ET_REL", 2: "ET_EXEC", 3: "ET_DYN", 4: "ET_CORE"}

PT_DYNAMIC, PT_INTERP, PT_NOTE, PT_GNU_STACK = 2, 3, 4, 0x6474E551
DT_NEEDED, DT_SONAME, DT_RPATH, DT_RUNPATH, DT_STRTAB, DT_STRSZ = 1, 14, 15, 29, 5, 10
NT_GNU_BUILD_ID = 3


class NotELF(Exception):
    pass


def probe(path):
    with open(path, "rb") as fh:
        b = fh.read()
    if len(b) < 64 or b[:4] != b"\x7fELF":
        raise NotELF(f"{path}: not an ELF file")
    cls, data = b[4], b[5]
    if cls != 2:
        raise NotELF(f"{path}: ELFCLASS32 is not handled by this probe")
    e = "<" if data == 1 else ">"

    e_type, e_machine = struct.unpack_from(e + "HH", b, 16)
    e_phoff, = struct.unpack_from(e + "Q", b, 32)
    e_phentsize, e_phnum = struct.unpack_from(e + "HH", b, 54)
    e_shoff, = struct.unpack_from(e + "Q", b, 40)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from(e + "HHH", b, 58)

    out = {
        "file": path, "bytes": len(b),
        "type": ET.get(e_type, hex(e_type)),
        "machine": EM.get(e_machine, hex(e_machine)),
        "machine_raw": e_machine,
        "interp": None, "needed": [], "soname": None, "runpath": [],
        "build_id": None, "exec_stack": None, "sections": 0, "has_symtab": False,
        "has_debug": False, "pie": e_type == 3,
    }

    # ---- program headers: the portability question lives here.
    dyn_off = dyn_size = dyn_vaddr = 0
    segments = []
    for i in range(e_phnum):
        o = e_phoff + i * e_phentsize
        if o + 56 > len(b):
            break
        p_type, p_flags = struct.unpack_from(e + "II", b, o)
        p_offset, p_vaddr = struct.unpack_from(e + "QQ", b, o + 8)
        p_filesz, = struct.unpack_from(e + "Q", b, o + 32)
        segments.append((p_type, p_offset, p_vaddr, p_filesz))
        if p_type == PT_INTERP:
            out["interp"] = b[p_offset:p_offset + p_filesz].rstrip(b"\0").decode("utf-8", "replace")
        elif p_type == PT_DYNAMIC:
            dyn_off, dyn_size, dyn_vaddr = p_offset, p_filesz, p_vaddr
        elif p_type == PT_GNU_STACK:
            out["exec_stack"] = bool(p_flags & 1)
        elif p_type == PT_NOTE:
            out["build_id"] = out["build_id"] or _build_id(b, p_offset, p_filesz, e)

    # ---- dynamic table: what the loader would be asked to supply.
    if dyn_size:
        # Resolve the string table by mapping its vaddr through the segment
        # that contains it. Using the section header would fail on a stripped
        # binary, and stripping is the normal case here.
        strtab_va = strsz = 0
        entries = []
        for k in range(dyn_size // 16):
            tag, val = struct.unpack_from(e + "qQ", b, dyn_off + k * 16)
            if tag == 0:
                break
            entries.append((tag, val))
            if tag == DT_STRTAB:
                strtab_va = val
            elif tag == DT_STRSZ:
                strsz = val
        strtab_off = _va_to_off(segments, strtab_va) if strtab_va else None
        if strtab_off is not None:
            def s(idx):
                end = b.find(b"\0", strtab_off + idx)
                return b[strtab_off + idx:end].decode("utf-8", "replace")
            for tag, val in entries:
                if tag == DT_NEEDED:
                    out["needed"].append(s(val))
                elif tag == DT_SONAME:
                    out["soname"] = s(val)
                elif tag in (DT_RPATH, DT_RUNPATH):
                    out["runpath"].append(s(val))

    # ---- sections: debug and symbol presence, for the stripping question.
    if e_shoff and e_shnum and e_shstrndx < e_shnum:
        o = e_shoff + e_shstrndx * e_shentsize
        shstr_off, = struct.unpack_from(e + "Q", b, o + 24)
        names = []
        for i in range(e_shnum):
            so = e_shoff + i * e_shentsize
            if so + e_shentsize > len(b):
                break
            nameoff, = struct.unpack_from(e + "I", b, so)
            end = b.find(b"\0", shstr_off + nameoff)
            names.append(b[shstr_off + nameoff:end].decode("utf-8", "replace"))
        out["sections"] = len(names)
        out["has_symtab"] = ".symtab" in names
        out["has_debug"] = any(n.startswith(".debug_") for n in names)

    # The property that decides whether this binary runs on an unknown host.
    out["needs_host_loader"] = out["interp"] is not None
    return out


def _va_to_off(segments, va):
    for p_type, p_offset, p_vaddr, p_filesz in segments:
        if p_type == 1 and p_vaddr <= va < p_vaddr + p_filesz:  # PT_LOAD
            return p_offset + (va - p_vaddr)
    return None


def _build_id(b, off, size, e):
    p, end = off, off + size
    while p + 12 <= end:
        n_namesz, n_descsz, n_type = struct.unpack_from(e + "III", b, p)
        name_off = p + 12
        desc_off = name_off + ((n_namesz + 3) & ~3)
        if n_type == NT_GNU_BUILD_ID and b[name_off:name_off + 3] == b"GNU":
            return b[desc_off:desc_off + n_descsz].hex()
        p = desc_off + ((n_descsz + 3) & ~3)
    return None


def main(argv):
    as_json = "--json" in argv
    expect_static = "--expect-static" in argv
    files = [a for a in argv[1:] if not a.startswith("--")]
    if not files:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    failed = 0
    for f in files:
        try:
            r = probe(f)
        except NotELF as ex:
            print(f"{ex}", file=sys.stderr)
            failed = 1
            continue
        except OSError as ex:
            print(f"{f}: {ex}", file=sys.stderr)
            return 2

        if as_json:
            print(json.dumps(r, sort_keys=True))
        else:
            link = "DYNAMIC (needs " + r["interp"] + ")" if r["needs_host_loader"] else "static"
            print(f"{r['file']}")
            print(f"  arch        {r['machine']}  {r['type']}")
            print(f"  linkage     {link}")
            print(f"  bytes       {r['bytes']}")
            if r["needed"]:
                print(f"  DT_NEEDED   {', '.join(r['needed'])}")
            if r["runpath"]:
                print(f"  RUNPATH     {', '.join(r['runpath'])}")
            print(f"  build-id    {r['build_id'] or '(none)'}")
            print(f"  symtab      {r['has_symtab']}   debug sections {r['has_debug']}")
            print(f"  exec stack  {r['exec_stack']}")
        if expect_static and r["needs_host_loader"]:
            print(f"::FAIL {f} has PT_INTERP {r['interp']}", file=sys.stderr)
            failed = 1

    return failed


if __name__ == "__main__":
    sys.exit(main(sys.argv))
