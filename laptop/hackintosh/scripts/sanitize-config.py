#!/usr/bin/env python3
"""Scrub SMBIOS serials, UUIDs, MLB, ROM, and security hashes from config.plist.

Usage:
    python3 sanitize-config.py <input-config.plist> <output-config.plist>
"""

import argparse
from pathlib import Path
import plistlib
import sys


PLACEHOLDER_UUID = "00000000-0000-0000-0000-000000000000"
PLACEHOLDER_ROM = b"\x11\x22\x33\x44\x55\x66"

SENSITIVE_STR_KEYS = {
    "BoardSerialNumber": "CHANGE_ME_MLB",
    "ChassisSerialNumber": "CHANGE_ME_SERIAL",
    "MLB": "CHANGE_ME_MLB",
    "SystemSerialNumber": "CHANGE_ME_SERIAL",
    "SystemUUID": PLACEHOLDER_UUID,
}


def scrub_mapping(mapping: dict, prefix: str, scrubbed: list[str]) -> None:
    """Scrub known identifying keys inside a plist dictionary in place."""
    for key, val in list(mapping.items()):
        path = f"{prefix}.{key}" if prefix else key
        if key == "ROM" and isinstance(val, (bytes, bytearray)):
            mapping[key] = PLACEHOLDER_ROM
            scrubbed.append(path)
        elif key in ("PasswordHash", "PasswordSalt") and isinstance(val, (bytes, bytearray)):
            if len(val) > 0:
                mapping[key] = b""
                scrubbed.append(path)
        elif key == "SmcVersion" and isinstance(val, (bytes, bytearray, str)) and val:
            mapping[key] = b"" if isinstance(val, (bytes, bytearray)) else "CHANGE_ME"
            scrubbed.append(path)
        elif key in SENSITIVE_STR_KEYS and isinstance(val, str):
            mapping[key] = SENSITIVE_STR_KEYS[key]
            scrubbed.append(path)


def sanitize_plist(data: dict) -> list[str]:
    """Sanitize OpenCore PlatformInfo and Misc.Security sections in place."""
    scrubbed: list[str] = []

    platform = data.get("PlatformInfo")
    if isinstance(platform, dict):
        for section_name in ("Generic", "SMBIOS", "DataHub", "PlatformNVRAM"):
            section = platform.get(section_name)
            if isinstance(section, dict):
                scrub_mapping(section, f"PlatformInfo.{section_name}", scrubbed)

    misc = data.get("Misc")
    if isinstance(misc, dict):
        security = misc.get("Security")
        if isinstance(security, dict):
            scrub_mapping(security, "Misc.Security", scrubbed)

    return scrubbed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sanitize OpenCore config.plist so it is safe to commit to git."
    )
    parser.add_argument("input", type=Path, help="Path to source config.plist")
    parser.add_argument("output", type=Path, help="Path to sanitized output plist")
    args = parser.parse_args()

    if not args.input.is_file():
        print(f"ERROR: input plist not found: {args.input}", file=sys.stderr)
        return 1

    with args.input.open("rb") as f:
        data = plistlib.load(f)

    if not isinstance(data, dict):
        print("ERROR: root plist object must be a dictionary", file=sys.stderr)
        return 1

    scrubbed = sanitize_plist(data)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_XML, sort_keys=False)

    print(f"Sanitized {len(scrubbed)} fields -> {args.output}")
    for item in scrubbed:
        print(f"  - {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
