#!/usr/bin/env python3
"""
severity_diagnostic.py

One-off analysis to evaluate whether keyword-based severity parsing
of free-text symptom notes produces meaningful buckets.

Reads notes from:
  - biotracking.db (per-symptom notes columns)
  - optionally, flare_data.ods (cell values AND cell annotations, which are
    where the rich severity language lives — CSV export loses them)

Applies a draft parser with Alaric's vocabulary, then prints:
  - Overall bucket distribution (extreme / major / mild / none)
  - Per-source / per-symptom breakdown
  - Sample notes per bucket for eyeball calibration

Usage (from the project root):
    python severity_diagnostic.py                           # DB only
    python severity_diagnostic.py backups/flare_data.ods    # DB + ODS
"""

import random
import sqlite3
import sys
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter, defaultdict

from severity_vocab import classify

DB_FILE = "biotracking.db"

SYMPTOM_NOTES_COLUMNS = [
    "neuro_notes",
    "cognitive_notes",
    "musculature_notes",
    "migraine_notes",
    "pulmonary_notes",
    "derm_notes",
    "rheumatic_notes",
    "mucosal_notes",
    "gastro_notes",
    "word_loss_notes",
]

AUTHOR_BYLINES = {"C. Alaric Moore", "Alaric Moore", "alaric moore"}


# ---------------------------------------------------------------------------
# DB reader
# ---------------------------------------------------------------------------

def read_db_notes(db_path):
    """Yield (date, symptom_label, text) tuples for every non-empty symptom
    note in daily_observations."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    existing = {r["name"] for r in conn.execute(
        "PRAGMA table_info(daily_observations)"
    ).fetchall()}
    cols_to_read = [c for c in SYMPTOM_NOTES_COLUMNS if c in existing]
    missing = [c for c in SYMPTOM_NOTES_COLUMNS if c not in existing]
    if missing:
        print(f"(skipping DB columns not in this schema: {', '.join(missing)})")

    select_cols = ", ".join(["date"] + cols_to_read)
    rows = conn.execute(f"SELECT {select_cols} FROM daily_observations").fetchall()
    conn.close()

    for row in rows:
        for col in cols_to_read:
            text = row[col]
            if text is None or not str(text).strip():
                continue
            yield (row["date"], col.replace("_notes", ""), str(text))


# ---------------------------------------------------------------------------
# ODS reader — pulls both cell values (string cells) AND cell annotations,
# which is where the rich per-cell severity notes live. CSV export would
# lose the annotations, so reading the ODS directly is the only way to see
# them.
# ---------------------------------------------------------------------------

ODS_NS = {
    "table": "urn:oasis:names:tc:opendocument:xmlns:table:1.0",
    "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
    "office": "urn:oasis:names:tc:opendocument:xmlns:office:1.0",
    "dc": "http://purl.org/dc/elements/1.1/",
}
ODS_TABLE = f"{{{ODS_NS['table']}}}table"
ODS_ROW = f"{{{ODS_NS['table']}}}table-row"
ODS_CELL = f"{{{ODS_NS['table']}}}table-cell"
ODS_ANNOTATION = f"{{{ODS_NS['office']}}}annotation"
ODS_VALUE_TYPE = f"{{{ODS_NS['office']}}}value-type"
ODS_P = f"{{{ODS_NS['text']}}}p"
ODS_CREATOR = f"{{{ODS_NS['dc']}}}creator"
ODS_DATE = f"{{{ODS_NS['dc']}}}date"


def _text_from_paragraphs(element):
    """Concatenate all <text:p> content inside an element, skipping dc:creator
    and dc:date children (which are the annotation author/timestamp, not the
    comment body)."""
    parts = []
    for p in element.iter(ODS_P):
        t = "".join(p.itertext()).strip()
        if not t:
            continue
        if t in AUTHOR_BYLINES:
            continue
        parts.append(t)
    return " ".join(parts)


def read_ods_notes(ods_path):
    """Yield (date, source_label, text) tuples from the first sheet of an ODS.
    Extracts BOTH cell values (string-type only, to skip Y/N and dates/numbers)
    AND cell annotations."""
    with zipfile.ZipFile(ods_path) as z:
        with z.open("content.xml") as f:
            tree = ET.parse(f)

    sheets = list(tree.getroot().iter(ODS_TABLE))
    if not sheets:
        return
    sheet = sheets[0]  # the "Symptom Tracker and Bad Day Predictor" sheet

    for row_idx, row in enumerate(sheet.iter(ODS_ROW)):
        cells = list(row.iter(ODS_CELL))
        if not cells:
            continue

        # Use column 0 as the row date if it's a date-typed cell.
        date_str = ""
        first = cells[0]
        if first.get(ODS_VALUE_TYPE) == "date":
            p = first.find(ODS_P)
            if p is not None:
                date_str = "".join(p.itertext()).strip()
        if not date_str:
            # Not a data row (likely the header).
            continue

        for col_idx, cell in enumerate(cells):
            # Pull the annotation body if present (the rich part).
            annot = cell.find(ODS_ANNOTATION)
            if annot is not None:
                annot_text = _text_from_paragraphs(annot)
                if annot_text:
                    yield (date_str, f"ods-note:col-{col_idx}", annot_text)

            # Pull string-type cell values (skip booleans, dates, numbers).
            if cell.get(ODS_VALUE_TYPE) == "string":
                p = cell.find(ODS_P)
                if p is not None:
                    val = "".join(p.itertext()).strip()
                    if val and val not in ("Y", "N", "y", "n"):
                        yield (date_str, f"ods-val:col-{col_idx}", val)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ods_path = sys.argv[1] if len(sys.argv) > 1 else None

    try:
        db_notes = list(read_db_notes(DB_FILE))
    except sqlite3.OperationalError as e:
        print(f"Couldn't open {DB_FILE}: {e}")
        sys.exit(1)

    ods_notes = []
    if ods_path:
        try:
            ods_notes = list(read_ods_notes(ods_path))
        except (FileNotFoundError, zipfile.BadZipFile) as e:
            print(f"Couldn't read ODS {ods_path}: {e}")
            sys.exit(1)

    all_notes = db_notes + ods_notes

    by_bucket = defaultdict(list)              # bucket -> [(source, text, date), ...]
    by_source_bucket = defaultdict(Counter)    # source -> {bucket: count}

    for date_str, source, text in all_notes:
        # DB notes come from per-symptom columns (neuro_notes, derm_notes, etc.)
        # so a non-empty entry implies that symptom was present — floor at mild.
        # ODS cells are mixed (weather, food, events, symptom descriptions) —
        # don't floor, we want to see which ones the vocab actually catches.
        is_symptom_note = not source.startswith("ods-")
        bucket = classify(text, symptom_present=is_symptom_note) or "none"
        # Collapse ODS columns into one source bucket for the summary table,
        # but keep the specific column label in samples.
        summary_source = "ods-note" if source.startswith("ods-note") else (
            "ods-val" if source.startswith("ods-val") else source
        )
        by_bucket[bucket].append((source, text, date_str))
        by_source_bucket[summary_source][bucket] += 1

    total_notes = len(all_notes)

    print("=" * 64)
    print("SEVERITY PARSING DIAGNOSTIC")
    print("=" * 64)
    print(f"\nTotal non-empty notes:   {total_notes}")
    print(f"  From DB:               {len(db_notes)}")
    print(f"  From ODS:              {len(ods_notes)}")
    print()

    # Overall distribution
    print("OVERALL DISTRIBUTION")
    print("-" * 48)
    for bucket in ("extreme", "major", "mild", "none"):
        count = len(by_bucket.get(bucket, []))
        pct = 100 * count / total_notes if total_notes else 0
        bar = "█" * int(pct / 2)
        print(f"  {bucket:8} {count:5}  ({pct:5.1f}%)  {bar}")
    print()

    # Per-source breakdown
    print("PER-SOURCE BREAKDOWN  (ods-note = cell annotations, ods-val = cell text)")
    print("-" * 72)
    print(f"  {'source':<16} {'extreme':>8} {'major':>8} {'mild':>8} {'none':>8}  {'total':>7}")
    for source in sorted(by_source_bucket):
        c = by_source_bucket[source]
        total = c["extreme"] + c["major"] + c["mild"] + c["none"]
        print(f"  {source:<16} {c['extreme']:>8} {c['major']:>8} "
              f"{c['mild']:>8} {c['none']:>8}  {total:>7}")
    print()

    # Sample notes per bucket — "none" gets a bigger sample for calibration
    SAMPLE_COUNTS = {"extreme": 12, "major": 12, "mild": 12, "none": 40}
    MAX_PREVIEW = 200
    for bucket in ("extreme", "major", "mild", "none"):
        notes = by_bucket.get(bucket, [])
        if not notes:
            continue
        # For "none", skip trivial notes (Err:511, single-word cells etc.) —
        # those don't teach us anything about missing vocabulary.
        if bucket == "none":
            notes = [n for n in notes if len(str(n[1]).strip()) > 10]
        n_wanted = SAMPLE_COUNTS.get(bucket, 8)
        sample = random.sample(notes, min(n_wanted, len(notes)))
        print(f"--- SAMPLE NOTES classified as {bucket.upper()} "
              f"({len(notes)} total non-trivial, showing {len(sample)}) ---")
        for source, text, date_str in sample:
            text = str(text).replace("\n", " ").strip()
            preview = text[:MAX_PREVIEW] + ("…" if len(text) > MAX_PREVIEW else "")
            print(f"  [{date_str} | {source:<20}] {preview}")
        print()

    # Vocab mining view: every NONE entry from the daily-summary ODS cells
    # (col-25 and col-26), full-length. These are the cells where Alaric
    # writes free-form summaries of how the day went, so any severity
    # vocabulary we're still missing lives in here.
    mining_sources = {"ods-val:col-25", "ods-val:col-26"}
    mining_notes = [
        (source, text, date_str)
        for source, text, date_str in by_bucket.get("none", [])
        if source in mining_sources and len(str(text).strip()) > 10
    ]
    if mining_notes:
        mining_notes.sort(key=lambda n: n[2])
        print("=" * 72)
        print(f"VOCAB MINING: NONE entries from daily-summary cells "
              f"(col-25, col-26) — {len(mining_notes)} total")
        print("Review these for severity language the classifier is missing.")
        print("=" * 72)
        for source, text, date_str in mining_notes:
            text = str(text).replace("\n", " ").strip()
            print(f"  [{date_str} | {source}]")
            print(f"    {text}")
            print()


if __name__ == "__main__":
    main()
