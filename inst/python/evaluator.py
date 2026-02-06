"""Evaluation metrics for matching quality (precision, recall, F1)."""


def evaluate(matched_results, gold_standard):
    """Compute precision, recall, and F1 score against a gold standard.

    Args:
        matched_results: List of dicts with at least 'speaker', 'event_date',
                         'matched_name' keys.
        gold_standard: List of dicts with 'speaker', 'event_date',
                       'correct_name' keys. 'correct_name' can be None/empty
                       for speakers that should NOT be matched (roles, crowds).

    Returns:
        Dict with: precision, recall, f1, n_total, n_correct, n_wrong,
                   n_missed, n_false_positive, details (list of per-row results).
    """
    # Index gold standard by (speaker, event_date)
    gold_index = {}
    for g in gold_standard:
        key = (g["speaker"], g["event_date"])
        correct = g.get("correct_name", None)
        if correct and str(correct).strip():
            gold_index[key] = str(correct).strip()
        else:
            gold_index[key] = None

    # Evaluate each matched result that has a gold standard entry
    true_positives = 0
    false_positives = 0
    false_negatives = 0
    true_negatives = 0
    details = []

    for m in matched_results:
        key = (m["speaker"], m["event_date"])
        if key not in gold_index:
            continue

        gold_name = gold_index[key]
        predicted_name = m.get("matched_name", None)
        if predicted_name and str(predicted_name).strip():
            predicted_name = str(predicted_name).strip()
        else:
            predicted_name = None

        row_detail = {
            "speaker": m["speaker"],
            "event_date": m["event_date"],
            "predicted": predicted_name,
            "correct": gold_name,
        }

        if gold_name is None and predicted_name is None:
            row_detail["result"] = "true_negative"
            true_negatives += 1
        elif gold_name is not None and predicted_name is not None:
            if predicted_name.lower() == gold_name.lower():
                row_detail["result"] = "true_positive"
                true_positives += 1
            else:
                row_detail["result"] = "wrong_match"
                false_positives += 1
                false_negatives += 1
        elif gold_name is None and predicted_name is not None:
            row_detail["result"] = "false_positive"
            false_positives += 1
        else:
            row_detail["result"] = "missed"
            false_negatives += 1

        details.append(row_detail)

    # Compute metrics
    precision = (
        true_positives / (true_positives + false_positives)
        if (true_positives + false_positives) > 0
        else 0.0
    )
    recall = (
        true_positives / (true_positives + false_negatives)
        if (true_positives + false_negatives) > 0
        else 0.0
    )
    f1 = (
        2 * precision * recall / (precision + recall)
        if (precision + recall) > 0
        else 0.0
    )

    return {
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "n_total": len(details),
        "n_true_positive": true_positives,
        "n_true_negative": true_negatives,
        "n_false_positive": false_positives,
        "n_false_negative": false_negatives,
        "details": details,
    }
