#!/usr/bin/env python3
"""Summarize one raw ADC CSV capture without modifying the source file."""

from __future__ import annotations
import argparse
import csv
import math
import statistics
from pathlib import Path

KNOWN_GLITCH_CODES = {24576, 49152}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_file", type=Path)
    parser.add_argument("--channel", choices=("voltage", "current"), required=True)
    args = parser.parse_args()

    raw_key = f"{args.channel}_raw_code"
    scaled_key = f"scaled_{args.channel}_v" if args.channel == "voltage" else "scaled_current_a"

    raw = []
    scaled = []
    rejected = 0

    with args.csv_file.open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            code = int(row[raw_key])
            if code in KNOWN_GLITCH_CODES:
                rejected += 1
                continue
            raw.append(code)
            scaled.append(float(row[scaled_key]))

    if not raw:
        raise SystemExit("No valid samples remain after filtering.")

    rms = math.sqrt(sum(x*x for x in scaled) / len(scaled))
    print(f"file: {args.csv_file}")
    print(f"channel: {args.channel}")
    print(f"valid samples: {len(raw)}")
    print(f"rejected known glitch samples: {rejected}")
    print(f"raw mean: {statistics.fmean(raw):.6f}")
    print(f"raw std (sample): {statistics.stdev(raw) if len(raw) > 1 else 0.0:.6f}")
    print(f"scaled mean: {statistics.fmean(scaled):.9f}")
    print(f"scaled RMS: {rms:.9f}")
    print(f"scaled min: {min(scaled):.9f}")
    print(f"scaled max: {max(scaled):.9f}")

if __name__ == "__main__":
    main()
