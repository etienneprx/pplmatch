"""Multi-level matching engine for Quebec National Assembly speakers.

Level 1: Deterministic (exact match after normalization)
Level 2: Fuzzy (rapidfuzz with configurable threshold)
"""

from rapidfuzz import fuzz
from normalizer import (
    normalize_speaker,
    normalize_member_name,
    extract_last_name,
)
from legislature import load_legislatures, date_to_legislature


def _build_lookup(members, legislature):
    """Build lookup indexes for a given legislature.

    Args:
        members: List of dicts with keys: full_name, other_names (optional),
                 party_id, gender, district_id (optional), legislature_id.
        legislature: Legislature number (int) to filter on.

    Returns:
        Dict with keys:
        - 'full_name_index': {normalized_name: member_info}
        - 'other_names_index': {normalized_name: member_info}
        - 'last_name_index': {last_name: [member_info, ...]}
        - 'all_members': [member_info, ...]
    """
    full_name_index = {}
    other_names_index = {}
    last_name_index = {}
    all_members = []

    leg_str = str(legislature)

    for m in members:
        m_leg = str(m.get("legislature_id", ""))
        if m_leg != leg_str:
            continue

        full_norm = normalize_member_name(m["full_name"])
        last = extract_last_name(full_norm)

        info = {
            "full_name": m["full_name"],
            "full_name_norm": full_norm,
            "last_name_norm": last,
            "party_id": m.get("party_id", ""),
            "gender": m.get("gender", ""),
            "district_id": m.get("district_id", ""),
        }
        all_members.append(info)

        full_name_index[full_norm] = info

        # Index other_names (semicolon-separated)
        other_names_raw = m.get("other_names", None)
        if other_names_raw and str(other_names_raw).strip():
            for alt in str(other_names_raw).split(";"):
                alt = alt.strip()
                if alt:
                    alt_norm = normalize_member_name(alt)
                    other_names_index[alt_norm] = info

        # Last name index (for ambiguity detection)
        if last not in last_name_index:
            last_name_index[last] = []
        last_name_index[last].append(info)

    return {
        "full_name_index": full_name_index,
        "other_names_index": other_names_index,
        "last_name_index": last_name_index,
        "all_members": all_members,
    }


def _fuzzy_score_full(speaker_norm, candidate_norm):
    """Compute fuzzy score for full name comparison.

    Weighted: token_sort_ratio (60%) + ratio (40%).
    """
    s1 = fuzz.token_sort_ratio(speaker_norm, candidate_norm)
    s2 = fuzz.ratio(speaker_norm, candidate_norm)
    return 0.6 * s1 + 0.4 * s2


def _fuzzy_score_last(speaker_norm, candidate_last):
    """Compute fuzzy score for last-name-only comparison.

    Weighted: partial_ratio (50%) + token_sort_ratio (30%) + ratio (20%).
    """
    s1 = fuzz.partial_ratio(speaker_norm, candidate_last)
    s2 = fuzz.token_sort_ratio(speaker_norm, candidate_last)
    s3 = fuzz.ratio(speaker_norm, candidate_last)
    return 0.5 * s1 + 0.3 * s2 + 0.2 * s3


def match_speaker(speaker_norm, lookup, fuzzy_threshold=85):
    """Match a single normalized speaker name against the lookup.

    Args:
        speaker_norm: Normalized speaker name (from normalize_speaker).
        lookup: Lookup dict from _build_lookup.
        fuzzy_threshold: Minimum fuzzy score (0-100) to accept a match.

    Returns:
        Dict with: matched_name, party_id, gender, district_id, match_level, match_score.
        match_level is one of: 'deterministic', 'fuzzy', 'ambiguous', 'unmatched'.
    """
    no_match = {
        "matched_name": None,
        "party_id": None,
        "gender": None,
        "district_id": None,
        "match_level": "unmatched",
        "match_score": None,
    }

    if not speaker_norm:
        return no_match

    # --- Level 1: Deterministic ---

    # 1a. Exact match on full_name
    if speaker_norm in lookup["full_name_index"]:
        info = lookup["full_name_index"][speaker_norm]
        return _make_result(info, "deterministic", 100.0)

    # 1b. Exact match on other_names
    if speaker_norm in lookup["other_names_index"]:
        info = lookup["other_names_index"][speaker_norm]
        return _make_result(info, "deterministic", 100.0)

    # 1c. Exact match on last name (only if unambiguous)
    speaker_tokens = speaker_norm.split()
    if len(speaker_tokens) == 1:
        last = speaker_tokens[0]
        if last in lookup["last_name_index"]:
            candidates = lookup["last_name_index"][last]
            if len(candidates) == 1:
                return _make_result(candidates[0], "deterministic", 100.0)
            else:
                # Ambiguous: multiple members share this last name
                # Attempt Consensus Matching
                return _make_ambiguous_result(candidates, match_score=100.0)

    # --- Level 2: Fuzzy ---
    best_score = 0.0
    best_info = None
    is_single_token = len(speaker_tokens) == 1

    for member in lookup["all_members"]:
        if is_single_token:
            # Compare against last names
            score = _fuzzy_score_last(speaker_norm, member["last_name_norm"])
        else:
            # Compare against full names
            score = _fuzzy_score_full(speaker_norm, member["full_name_norm"])

        if score > best_score:
            best_score = score
            best_info = member

    if best_score >= fuzzy_threshold and best_info is not None:
        # Check ambiguity for single-token fuzzy matches
        if is_single_token:
            # Find all members whose last name scores above threshold
            close_matches = []
            for member in lookup["all_members"]:
                s = _fuzzy_score_last(speaker_norm, member["last_name_norm"])
                if s >= fuzzy_threshold:
                    close_matches.append(member)
            
            # Filter close matches to those with unique full names (avoid dupes)
            unique_matches = {m["full_name"]: m for m in close_matches}.values()
            
            if len(unique_matches) > 1:
                return _make_ambiguous_result(list(unique_matches), best_score)

        return _make_result(best_info, "fuzzy", best_score)

    return no_match


def _make_result(info, match_level, match_score):
    """Build a result dict from member info."""
    return {
        "matched_name": info["full_name"],
        "party_id": info["party_id"],
        "gender": info["gender"],
        "district_id": info["district_id"],
        "match_level": match_level,
        "match_score": match_score,
    }


def _make_ambiguous_result(candidates, match_score):
    """Build a result from multiple candidates using consensus logic.
    
    If all candidates share the same party or gender, return it.
    matched_name will be a semicolon-separated list of candidates.
    """
    parties = set(c.get("party_id") for c in candidates if c.get("party_id"))
    genders = set(c.get("gender") for c in candidates if c.get("gender"))
    
    consensus_party = parties.pop() if len(parties) == 1 else None
    consensus_gender = genders.pop() if len(genders) == 1 else None
    
    # Create a composite name field so user knows who is involved
    # e.g. "Mathieu Lévesque; Sylvain Lévesque"
    names = sorted([c["full_name"] for c in candidates])
    composite_name = "; ".join(names)

    return {
        "matched_name": composite_name, # Return all potential names
        "party_id": consensus_party,    # Return party if consensus, else None
        "gender": consensus_gender,     # Return gender if consensus, else None
        "district_id": None,            # District is rarely shared, safe to null
        "match_level": "ambiguous",
        "match_score": match_score,
    }


def match_corpus(corpus_rows, members, fuzzy_threshold=85,
                 legislatures_path=None, verbose=False):
    """Match an entire corpus against member records.

    Args:
        corpus_rows: List of dicts with keys: speaker, event_date.
        members: List of dicts with keys: full_name, other_names, party_id,
                 gender, district_id (optional), legislature_id.
        fuzzy_threshold: Minimum fuzzy score (0-100).
        legislatures_path: Path to legislatures_qc.json (or None for bundled).
        verbose: If True, print progress info.

    Returns:
        List of dicts, one per input row, with added match columns.
    """
    legislatures = load_legislatures(legislatures_path)

    # Cache lookups by legislature
    lookup_cache = {}

    # Cache match results by (speaker_norm, legislature)
    match_cache = {}

    results = []
    n = len(corpus_rows)

    for i, row in enumerate(corpus_rows):
        if verbose and (i + 1) % 5000 == 0:
            print(f"  Matching row {i + 1}/{n}...")

        speaker_raw = row.get("speaker", "")
        event_date = row.get("event_date", "")

        # Determine legislature
        leg = date_to_legislature(event_date, legislatures)

        # Classify and normalize speaker
        category, speaker_norm = normalize_speaker(speaker_raw)

        result = dict(row)
        result["speaker_category"] = category
        result["speaker_normalized"] = speaker_norm
        result["legislature"] = leg

        if category != "person" or leg is None:
            result["matched_name"] = None
            result["party_id"] = None
            result["gender"] = None
            result["district_id"] = None
            result["match_level"] = category if category != "person" else "unmatched"
            result["match_score"] = None
            results.append(result)
            continue

        # Build or retrieve lookup for this legislature
        if leg not in lookup_cache:
            lookup_cache[leg] = _build_lookup(members, leg)

        lookup = lookup_cache[leg]

        # Check match cache
        cache_key = (speaker_norm, leg)
        if cache_key in match_cache:
            match = match_cache[cache_key]
        else:
            match = match_speaker(speaker_norm, lookup, fuzzy_threshold)
            match_cache[cache_key] = match

        result.update(match)
        results.append(result)

    if verbose:
        total = len(results)
        matched = sum(1 for r in results if r["match_level"] in ("deterministic", "fuzzy"))
        ambiguous = sum(1 for r in results if r["match_level"] == "ambiguous")
        roles = sum(1 for r in results if r["speaker_category"] == "role")
        crowds = sum(1 for r in results if r["speaker_category"] == "crowd")
        unmatched = sum(1 for r in results if r["match_level"] == "unmatched")
        print(f"  Done. {total} rows: {matched} matched, {ambiguous} ambiguous, "
              f"{roles} roles, {crowds} crowds, {unmatched} unmatched.")

    return results
