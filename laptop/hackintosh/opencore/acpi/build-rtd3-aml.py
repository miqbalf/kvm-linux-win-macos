#!/usr/bin/env python3
"""Zero-dependency AML generator for SSDT-NXRTD3.aml (Acer Nitro AN515-55).

Builds an ACPI SSDT defining NXOF and NXO_ under \\_SB.PCI0 that safely
call \\_SB.PCI0.PEG0.PG00._OFF and _ON when present. Works without iasl.

Usage:
    python3 build-rtd3-aml.py [-o path/to/SSDT-NXRTD3.aml]
"""

import argparse
from pathlib import Path
import struct


def encode_pkg_length(payload_len: int) -> bytes:
    """Encode an ACPI AML PkgLength (byte count includes PkgLength itself)."""
    if payload_len + 1 <= 0x3F:
        return bytes([payload_len + 1])
    if payload_len + 2 <= 0x0FFF:
        total = payload_len + 2
        b0 = 0x40 | (total & 0x0F)
        b1 = (total >> 4) & 0xFF
        return bytes([b0, b1])
    if payload_len + 3 <= 0x0FFFFF:
        total = payload_len + 3
        b0 = 0x80 | (total & 0x0F)
        b1 = (total >> 4) & 0xFF
        b2 = (total >> 12) & 0xFF
        return bytes([b0, b1, b2])
    raise ValueError(f"Payload too large for SSDT PkgLength: {payload_len}")


def encode_namestring(path: str) -> bytes:
    """Encode an ACPI NameString such as '\\\\_SB.PCI0.PEG0.PG00._OFF'."""
    root = b""
    if path.startswith("\\"):
        root = b"\x5c"
        path = path[1:]
    segs = [s.ljust(4, "_")[:4].encode("ascii") for s in path.split(".")]
    if len(segs) == 1:
        return root + segs[0]
    if len(segs) == 2:
        return root + b"\x2e" + segs[0] + segs[1]
    return root + bytes([0x2F, len(segs)]) + b"".join(segs)


def encode_wrapper_method(method_name: str, target_method_path: str) -> bytes:
    """Build AML Method (<method_name>, 0, Serialized) calling <target_method_path>."""
    target_ns = encode_namestring(target_method_path)
    # DefCondRefOf := ExtOpPrefix(0x5B) CondRefOfOp(0x12) SuperName Target(NullName=0x00)
    predicate = b"\x5b\x12" + target_ns + b"\x00"
    # MethodInvocation with 0 args is just the NameString in TermList
    if_body = predicate + target_ns
    if_stmt = b"\xa0" + encode_pkg_length(len(if_body)) + if_body
    # Return (One)
    ret_stmt = b"\xa4\x01"

    method_name_bytes = encode_namestring(method_name)
    method_flags = b"\x08"  # Serialized=1 (bit 3), ArgCount=0
    method_payload = method_name_bytes + method_flags + if_stmt + ret_stmt
    return b"\x14" + encode_pkg_length(len(method_payload)) + method_payload


def build_ssdt_nxrtd3() -> bytes:
    """Assemble the complete SSDT-NXRTD3.aml table with valid ACPI checksum."""
    nxof = encode_wrapper_method("NXOF", r"\_SB.PCI0.PEG0.PG00._OFF")
    nxo_ = encode_wrapper_method("NXO_", r"\_SB.PCI0.PEG0.PG00._ON")

    scope_ns = encode_namestring(r"\_SB.PCI0")
    scope_payload = scope_ns + nxof + nxo_
    body = b"\x10" + encode_pkg_length(len(scope_payload)) + scope_payload

    total_len = 36 + len(body)
    header = struct.pack(
        "<4sIBB6s8sI4sI",
        b"SSDT",
        total_len,
        2,              # Revision 2
        0,              # Checksum placeholder
        b"ACERNI",      # OemId (6 bytes)
        b"NXRTD3  ",    # OemTableId (8 bytes)
        0x00001000,     # OemRevision
        b"PYAM",        # CreatorId
        0x20261126,     # CreatorRevision
    )
    raw = bytearray(header + body)
    raw[9] = (-sum(raw)) & 0xFF
    return bytes(raw)


def verify_ssdt(aml: bytes) -> None:
    """Perform structural and checksum sanity checks on generated AML."""
    sig, length, rev, _cksum = struct.unpack("<4sIBB", aml[:10])
    if sig != b"SSDT":
        raise AssertionError(f"Unexpected signature: {sig!r}")
    if length != len(aml):
        raise AssertionError(f"Header length {length} != {len(aml)}")
    if rev != 2:
        raise AssertionError(f"Unexpected revision: {rev}")
    if (sum(aml) & 0xFF) != 0:
        raise AssertionError(f"Invalid checksum sum & 0xFF = {sum(aml) & 0xFF}")
    if aml[36] != 0x10:
        raise AssertionError(f"Expected ScopeOp 0x10 at offset 36, got {aml[36]:#x}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build SSDT-NXRTD3.aml")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("SSDT-NXRTD3.aml"),
        help="Output AML file path (default: SSDT-NXRTD3.aml)",
    )
    args = parser.parse_args()

    aml = build_ssdt_nxrtd3()
    verify_ssdt(aml)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(aml)
    print(f"Wrote {args.output} ({len(aml)} bytes, checksum valid)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
