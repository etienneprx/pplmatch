"""Multi-level matching engine for Quebec National Assembly speakers.

Level 1: Deterministic (exact match after normalization)
Level 2: Fuzzy (rapidfuzz with configurable threshold)
Level 3: Contextual (inference based on session roster)
"""

from rapidfuzz import fuzz
from normalizer import (
    normalize_speaker,
    normalize_member_name,
    extract_last_name,
)
from legislature import load_legislatures, date_to_legislature


def _build_lookup(members, legislature):
    """Build lookup indexes for a given legislature."""
    full_name_index = {}
    other_names_index = {}
    last_name_index = {}
    district_index = {} # {normalized_district: [member_info, ...]}
    all_members = []

    leg_str = str(legislature)

    for m in members:
        m_leg = str(m.get("legislature_id", ""))
        if m_leg != leg_str:
            continue

        full_norm = normalize_member_name(m["full_name"])
        last = extract_last_name(full_norm)
        dist_norm = normalize_member_name(m.get("district_id", ""))

        info = {
            "full_name": m["full_name"],
            "full_name_norm": full_norm,
            "last_name_norm": last,
            "party_id": m.get("party_id", ""),
            "gender": m.get("gender", ""),
            "district_id": m.get("district_id", ""),
            "district_norm": dist_norm
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

        # Last name index
        if last not in last_name_index:
            last_name_index[last] = []
        last_name_index[last].append(info)
        
        # District index
        if dist_norm:
            if dist_norm not in district_index:
                district_index[dist_norm] = []
            district_index[dist_norm].append(info)

    return {
        "full_name_index": full_name_index,
        "other_names_index": other_names_index,
        "last_name_index": last_name_index,
        "district_index": district_index,
        "all_members": all_members,
    }


def _fuzzy_score_full(speaker_norm, candidate_norm):
    s1 = fuzz.token_sort_ratio(speaker_norm, candidate_norm)
    s2 = fuzz.ratio(speaker_norm, candidate_norm)
    return 0.6 * s1 + 0.4 * s2


def _fuzzy_score_last(speaker_norm, candidate_last):
    s1 = fuzz.partial_ratio(speaker_norm, candidate_last)
    s2 = fuzz.token_sort_ratio(speaker_norm, candidate_last)
    s3 = fuzz.ratio(speaker_norm, candidate_last)
    return 0.5 * s1 + 0.3 * s2 + 0.2 * s3


def _make_result(info, match_level, match_score):
    return {
        "matched_name": info["full_name"],
        "party_id": info["party_id"],
        "gender": info["gender"],
        "district_id": info["district_id"],
        "match_level": match_level,
        "match_score": match_score,
    }


def _make_ambiguous_result(candidates, match_score):
    parties = set(c.get("party_id") for c in candidates if c.get("party_id"))
    genders = set(c.get("gender") for c in candidates if c.get("gender"))
    
    consensus_party = parties.pop() if len(parties) == 1 else None
    consensus_gender = genders.pop() if len(genders) == 1 else None
    
    names = sorted([c["full_name"] for c in candidates])
    composite_name = "; ".join(names)

    return {
        "matched_name": composite_name,
        "party_id": consensus_party,
        "gender": consensus_gender,
        "district_id": None,
        "match_level": "ambiguous",
        "match_score": match_score,
    }


def match_speaker_atomic(speaker_norm, lookup, fuzzy_threshold=85, speaker_district=None):
    """Core matching logic for a single speaker."""
    no_match = {
        "matched_name": None, "party_id": None, "gender": None,
        "district_id": None, "match_level": "unmatched", "match_score": None,
    }

    if not speaker_norm:
        return no_match, None

    # 1. District override: If we have a district, filter members by it
    if speaker_district and speaker_district in lookup["district_index"]:
        district_members = lookup["district_index"][speaker_district]
        # If only one member in district, high chance it's them
        if len(district_members) == 1:
            return _make_result(district_members[0], "deterministic", 100.0), None
        # Otherwise, match name within that district
        for m in district_members:
            if speaker_norm in m["full_name_norm"] or m["last_name_norm"] == speaker_norm:
                return _make_result(m, "deterministic", 100.0), None

    # 2. Exact matches
    if speaker_norm in lookup["full_name_index"]:
        return _make_result(lookup["full_name_index"][speaker_norm], "deterministic", 100.0), None

    if speaker_norm in lookup["other_names_index"]:
        return _make_result(lookup["other_names_index"][speaker_norm], "deterministic", 100.0), None

    # 3. Last name matches
    speaker_tokens = speaker_norm.split()
    if len(speaker_tokens) == 1:
        last = speaker_tokens[0]
        if last in lookup["last_name_index"]:
            candidates = lookup["last_name_index"][last]
            if len(candidates) == 1:
                return _make_result(candidates[0], "deterministic", 100.0), None
            else:
                return _make_ambiguous_result(candidates, 100.0), candidates

    # 4. Fuzzy matches
    best_score = 0.0
    best_info = None
    is_single_token = len(speaker_tokens) == 1

    for member in lookup["all_members"]:
        if is_single_token:
            score = _fuzzy_score_last(speaker_norm, member["last_name_norm"])
        else:
            # Try matching speaker_norm as a substring of full_name (handles "Zaga Mendez")
            if speaker_norm in member["full_name_norm"]:
                score = 95.0
            else:
                score = _fuzzy_score_full(speaker_norm, member["full_name_norm"])

        if score > best_score:
            best_score = score
            best_info = member

    if best_score >= fuzzy_threshold and best_info is not None:
        if is_single_token:
            close_matches = [m for m in lookup["all_members"] if _fuzzy_score_last(speaker_norm, m["last_name_norm"]) >= fuzzy_threshold]
            unique_matches = list({m["full_name"]: m for m in close_matches}.values())
            if len(unique_matches) > 1:
                return _make_ambiguous_result(unique_matches, best_score), unique_matches

        return _make_result(best_info, "fuzzy", best_score), None

    return no_match, None


def match_corpus(corpus_rows, members, fuzzy_threshold=85,
                 legislatures_path=None, verbose=False):
    legislatures = load_legislatures(legislatures_path)
    lookup_cache = {}
    grouped_results = {}
    n = len(corpus_rows)

    if verbose:
        print(f"  Pre-processing {n} rows...")

    for i, row in enumerate(corpus_rows):
        speaker_raw = row.get("speaker", "")
        event_date = row.get("event_date", "")
        date_str = str(event_date) if event_date else "unknown"
        leg = date_to_legislature(event_date, legislatures)
        
        category, speaker_norm, speaker_dist = normalize_speaker(speaker_raw)

        result = dict(row)
        result.update({"speaker_category": category, "speaker_normalized": speaker_norm, "legislature": leg,
                       "matched_name": None, "party_id": None, "gender": None, "district_id": None,
                       "match_level": "unmatched", "match_score": None})

        candidates = None
        if category == "person" and leg is not None:
            if leg not in lookup_cache:
                lookup_cache[leg] = _build_lookup(members, leg)
            match_res, candidates = match_speaker_atomic(speaker_norm, lookup_cache[leg], fuzzy_threshold, speaker_dist)
            result.update(match_res)
        else:
            result["match_level"] = category if category != "person" else "unmatched"

        if date_str not in grouped_results:
            grouped_results[date_str] = []
        grouped_results[date_str].append({"index": i, "result": result, "candidates": candidates})

    final_results_sorted = [None] * n
    for date_str, items in grouped_results.items():
        daily_roster = set(item["result"]["matched_name"] for item in items if item["result"]["match_level"] in ("deterministic", "fuzzy") and item["result"]["matched_name"])
        for item in items:
            res, candidates = item["result"], item["candidates"]
            if res["match_level"] == "ambiguous" and candidates:
                matches_in_roster = [c for c in candidates if c["full_name"] in daily_roster]
                if len(matches_in_roster) == 1:
                    best = matches_in_roster[0]
                    res.update({"matched_name": best["full_name"], "party_id": best["party_id"], "gender": best["gender"],
                                "district_id": best["district_id"], "match_level": "contextual", "match_score": 99.0})
            final_results_sorted[item["index"]] = res

    if verbose:
        stats = {lvl: sum(1 for r in final_results_sorted if r["match_level"] == lvl) for lvl in 
                 ["deterministic", "fuzzy", "contextual", "ambiguous", "role", "crowd", "unmatched"]}
        print(f"  Done. Det: {stats['deterministic']}, Fuzzy: {stats['fuzzy']}, Ctx: {stats['contextual']}, Amb: {stats['ambiguous']}, Roles: {stats['role']}, Unm: {stats['unmatched']}")

    return final_results_sorted
