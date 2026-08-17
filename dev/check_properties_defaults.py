#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

"""trobar-garmin#17: a resources/properties.xml with a baked-in serverUrl/
enrollCode default (needed temporarily for real-device pairing testing,
since sideloaded apps have no Garmin Connect Mobile settings UI to type
them into instead) must never reach a commit. Parses the XML structurally
— immune to reformatting, attribute order, or a self-closing tag — rather
than pattern-matching the raw text: an earlier sed-based version of this
check only matched today's exact single-line shape and would silently
stop catching a leak if the file were ever reformatted.
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

PROPERTIES = Path(__file__).resolve().parent.parent / "resources/properties.xml"
CHECKED_IDS = ("serverUrl", "enrollCode")


def main() -> int:
    tree = ET.parse(PROPERTIES)
    problems = []
    for prop in tree.getroot().iter("property"):
        prop_id = prop.get("id")
        value = (prop.text or "").strip()
        if prop_id in CHECKED_IDS and value:
            problems.append(f"{prop_id!r} has a non-empty default: {value!r}")

    if problems:
        print(f"{PROPERTIES}: {len(problems)} baked-in test value(s) found:")
        for p in problems:
            print(f"  {p}")
        return 1

    print(f"{PROPERTIES}: ok ({len(CHECKED_IDS)} properties checked, all empty)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
