"""Normalization of Quebec National Assembly speaker names."""

import re
import unicodedata

# Roles that identify institutional speakers (not individual persons)
ROLES = {
    "le president", "la presidente",
    "le vice-president", "la vice-presidente",
    "le president suppleant", "la presidente suppleante",
    "une voix",
}

# Patterns that match role-like speakers
ROLE_PREFIXES = (
    "le president",
    "la presidente",
    "le vice-president",
    "la vice-presidente",
)

# Crowds / collective voices
CROWDS = {"des voix"}

# Honorifics to strip
HONORIFICS_RE = re.compile(
    r"^(M\.\s*|Mme\s+|Mme\.\s*|Mr\.\s*|Mr\s+)", re.IGNORECASE
)

# Honorific glued to name (e.g. "M.Caire" -> "Caire")
HONORIFIC_GLUED_RE = re.compile(
    r"^(M\.|Mme\.?)([A-ZÀ-ÖØ-Ý])", re.IGNORECASE
)

# Leading numeric garbage (e.g. "15 725 M. Marissal")
LEADING_NUMS_RE = re.compile(r"^[\d\s]+")

# Trailing district after comma (e.g. ", Chauveau")
TRAILING_DISTRICT_RE = re.compile(r",\s*[A-ZÀ-ÖØ-Ý].*$", re.IGNORECASE)

# Trailing action keywords in parentheses or after dash
TRAILING_ACTION_RE = re.compile(
    r"\s*[\(\-–—]\s*"
    r"(réplique|suite|en remplacement|par intérim|suppléant|suppléante)"
    r"[\)\s]*$",
    re.IGNORECASE,
)


def strip_accents(text):
    """Remove diacritics from text using NFD decomposition."""
    nfkd = unicodedata.normalize("NFD", text)
    return "".join(c for c in nfkd if unicodedata.category(c) != "Mn")


def classify_speaker(raw_speaker):
    """Classify a raw speaker string into a category.

    Returns one of: 'person', 'role', 'crowd', 'empty'.
    """
    if not raw_speaker or not raw_speaker.strip():
        return "empty"

    cleaned = raw_speaker.strip()
    lower = cleaned.lower()

    # Check exact crowd matches
    if strip_accents(lower).strip() in {"des voix"}:
        return "crowd"

    # Check role patterns
    lower_no_accent = strip_accents(lower)
    if lower_no_accent in ROLES:
        return "role"
    for prefix in ROLE_PREFIXES:
        if lower_no_accent.startswith(prefix):
            return "role"

    return "person"


def normalize_speaker(raw_speaker):
    """Normalize a speaker name for matching.

    Returns a tuple: (category, normalized_name)
    - category: 'person', 'role', 'crowd', or 'empty'
    - normalized_name: cleaned name string (empty for non-person categories)
    """
    category = classify_speaker(raw_speaker)
    if category != "person":
        return category, ""

    name = raw_speaker.strip()

    # Remove leading numeric garbage
    name = LEADING_NUMS_RE.sub("", name).strip()

    # Remove trailing action keywords
    name = TRAILING_ACTION_RE.sub("", name).strip()

    # Remove trailing district
    name = TRAILING_DISTRICT_RE.sub("", name).strip()

    # Handle glued honorific (M.Caire -> Caire)
    name = HONORIFIC_GLUED_RE.sub(r"\2", name)

    # Remove honorific prefix
    name = HONORIFICS_RE.sub("", name).strip()

    # Lowercase
    name = name.lower()

    # Remove accents
    name = strip_accents(name)

    # Keep only alpha and spaces
    name = re.sub(r"[^a-z ]", "", name)

    # Collapse multiple spaces
    name = re.sub(r"\s+", " ", name).strip()

    return "person", name


def normalize_member_name(name):
    """Normalize a member name from the reference dataset for matching."""
    name = name.lower()
    name = strip_accents(name)
    name = re.sub(r"[^a-z ]", "", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name


def extract_last_name(normalized_name):
    """Extract the last name from a normalized full name.

    Convention: the last token is the family name.
    """
    parts = normalized_name.split()
    if not parts:
        return ""
    return parts[-1]
