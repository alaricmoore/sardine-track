"""
severity_vocab.py

Alaric's personal vocabulary for rating symptom severity from free-text
notes. Three tiers — mild / major / extreme — calibrated against her own
writing register (not generic medical language).

Used in two places:
  - severity_diagnostic.py (calibration / vocab-mining tool)
  - app.py scoring (tier-based symptom point contribution)

Design rule (from Alaric's own definition, see memory
project_flare_severity_definition.md):
  - mild   = symptom present, still functioning
  - major  = function-limiting, even a single symptom
  - extreme = body-is-wrecking; threshold for her to seek medical contact
"""

import re

# ---------------------------------------------------------------------------
# Vocabulary lists
# ---------------------------------------------------------------------------

# EXTREME — her actual body-is-wrecking vocabulary, plus self-triggered
# healthcare escalation (her threshold for ER/doctor contact is high, so any
# mention of going to one in response to a symptom is an extreme-tier signal).
EXTREME_WORDS = [
    # Her phrases for losing bodily control
    "couldn't function", "could not function",
    "cried from pain", "crying from pain",
    "woke up screaming", "screaming",
    "meltdown",
    "gasping for air",
    # Her literal "extreme X" pattern (co-occurs with symptom nouns)
    "extreme exhaustion", "extreme exhuastion",  # her typo preserved
    "extreme fatigue", "extreme pain", "extreme nausea",
    # Her metaphor register for "body is wrecking"
    "last breath before death",
    # Bed-bound (when it's about herself, not someone else)
    "in bed all day", "couldn't get out of bed",
    "could not get out of bed",
    # Unable to walk — has triggered ER + doctor visits for her
    "couldn't walk", "could not walk", "can't walk",
    "unable to walk", "barely could walk", "barely able to walk",
    # Self-triggered healthcare escalation
    "er visit", "went to the er", "went to er",
    "went to urgent care",
]

# Function-limiting evidence → MAJOR. "Couldn't walk" lives in EXTREME —
# limping is her baseline function-limiting, not walking at all is above.
FUNCTION_LIMITING_PHRASES = [
    # Mobility (walking-impaired but still walking)
    "limping",
    "effecting gait", "affecting gait", "altered gait",
    "gait disturbance", "disturbed gait",
    # Work/day loss
    "called in sick", "called out sick", "stayed home from work",
    "unable to work", "couldn't work", "could not work",
    # Push-through failure
    "can't force", "cant force", "couldn't force", "could not force",
]

NEGATION_PREFIXES = (
    "almost ", "nearly ", "came close to ",
    "not ", "not so ", "not too ", "not really ", "not that ", "not very ",
    "nothing ", "nothing seriously ", "nothing too ",
    "no ",
)

# Diminishing qualifiers — when one directly precedes a function-limiting
# phrase, the symptom is present but small ("only caused a little limping"),
# so the entry is MILD rather than MAJOR.
QUALIFIER_DOWNGRADES = (
    "only ", "only a little ", "only slightly ",
    "a little ", "a bit of ", "a bit ",
    "slight ", "slightly ", "just a little ", "just slight ",
    "minor ", "minimal ", "mildly ", "barely ",
)

SOFT_NEGATIONS = [
    "not so bad", "not too bad", "not that bad", "not bad",
    "not as bad", "nothing concerning",
    "wasn't bad", "wasn't awful", "wasn't terrible", "wasn't so bad",
    "not horrible", "not terrible", "not too awful",
]

MAJOR_WORDS = [
    # Severity adjectives — self-reported as major.
    "major", "severe", "bad", "horrible", "awful", "terrible",
    "intense", "brutal", "killer",
    # Concerning somatic escalation — distinct from just "intense pain".
    "chest stabbing", "stabbing", "stabby",
    "lose my breath", "lost my breath", "losing breath",
    "broke out in", "hives", "blisters",
]

MILD_WORDS = [
    "mild", "minor", "light", "slight", "barely", "touch of",
    "a bit", "a little", "faint",
    # Dysfunction / fatigue — intensity words that aren't major without
    # function-limiting evidence (checked earlier in classify).
    "zombie", "wrecked", "fried", "wiped out", "crashed",
    "destroyed", "gutted", "exhausted", "so tired", "bone tired",
]

# Word-boundary match — "normal" must not match "abnormal".
MILD_EXACT_MATCH = ["normal", "fine", "the usual", "baseline"]


# ---------------------------------------------------------------------------
# Matching helpers
# ---------------------------------------------------------------------------

def _has_boundary_word(text_lower, words):
    """Word-boundary match: 'normal' matches 'today was normal' but not 'abnormal'."""
    pattern = r'\b(?:' + '|'.join(re.escape(w) for w in words) + r')\b'
    return bool(re.search(pattern, text_lower))


def _phrase_unnegated(text_lower, phrase):
    """True if the phrase appears at least once without a negation prefix
    immediately before it. Skips negated occurrences like 'almost called in
    sick' or 'nothing seriously debilitating'."""
    idx = 0
    while True:
        pos = text_lower.find(phrase, idx)
        if pos == -1:
            return False
        prefix = text_lower[:pos]
        if not any(prefix.endswith(neg) for neg in NEGATION_PREFIXES):
            return True
        idx = pos + 1


def _function_limiting_status(text_lower):
    """Scan FUNCTION_LIMITING_PHRASES and return:
      'present'   — ≥1 match is unnegated AND unqualified → MAJOR
      'qualified' — matches exist but all are qualified ('a little limping') → MILD
      None        — no match or only negated matches
    """
    qualified_only = False
    for phrase in FUNCTION_LIMITING_PHRASES:
        idx = 0
        while True:
            pos = text_lower.find(phrase, idx)
            if pos == -1:
                break
            prefix = text_lower[:pos]
            if any(prefix.endswith(neg) for neg in NEGATION_PREFIXES):
                idx = pos + 1
                continue
            if any(prefix.endswith(q) for q in QUALIFIER_DOWNGRADES):
                qualified_only = True
                idx = pos + 1
                continue
            return "present"
    return "qualified" if qualified_only else None


# ---------------------------------------------------------------------------
# Classifier
# ---------------------------------------------------------------------------

def classify(text, symptom_present=False):
    """Return 'extreme' | 'major' | 'mild' | None.

    If symptom_present=True the result is floored at 'mild' (a non-empty
    per-symptom note implies the symptom was present). Used by the diagnostic
    tool. Production scoring calls with symptom_present=False so that a
    no-vocab-match returns None and falls back to the baseline weight.
    """
    floor = "mild" if symptom_present else None

    if not text:
        return floor
    t = text.lower().strip()

    # Skip spreadsheet formula errors — they're not real notes.
    if t.startswith("err:"):
        return None

    # 1. EXTREME — body-is-wrecking vocabulary. Negation-aware.
    if any(_phrase_unnegated(t, p) for p in EXTREME_WORDS):
        return "extreme"

    # 2. SOFT_NEGATIONS — caught before MAJOR ("not so bad" contains "bad").
    if any(phrase in t for phrase in SOFT_NEGATIONS):
        return "mild"

    # 3. Function-limiting: unnegated + unqualified → MAJOR. All qualified → MILD.
    fl_status = _function_limiting_status(t)
    if fl_status == "present":
        return "major"
    if fl_status == "qualified":
        return "mild"

    # 4. "Tried to happen" — symptom started but didn't fully manifest.
    if "tried to happen" in t or "tried to break through" in t:
        return "mild"

    # 5. MAJOR — severity adjectives and concerning somatic escalation.
    if _has_boundary_word(t, MAJOR_WORDS):
        return "major"

    # 6. MILD — word-boundary first, then substring for phrases that won't false-match.
    if _has_boundary_word(t, MILD_EXACT_MATCH):
        return "mild"
    if any(word in t for word in MILD_WORDS):
        return "mild"

    return floor


# ---------------------------------------------------------------------------
# Scoring — tier-to-points mapping for production flare scoring
# ---------------------------------------------------------------------------

# Scheme B: gentler than flat minor/major joint tiering (1.0/2.0) to avoid
# doubling symptom contributions and destabilizing the flare_threshold=8.0
# calibration. Extreme still lands above baseline for every symptom.
TIER_POINTS = {
    "mild":    1.0,
    "major":   1.5,
    "extreme": 2.0,
}


def severity_score(notes_text):
    """Return a tier-based point override for a symptom's notes field, or
    None if no vocab matched. Caller falls back to the baseline weight when
    None is returned — so a symptom flagged without severity language in its
    notes keeps today's scoring behavior.
    """
    tier = classify(notes_text, symptom_present=False)
    return TIER_POINTS.get(tier) if tier else None
