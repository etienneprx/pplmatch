#' Generate a Stratified Gold Standard Sample for Manual Annotation
#'
#' Creates a CSV file with a stratified sample from a matched corpus for
#' manual review. The sample is stratified by match_level to ensure coverage
#' of different matching outcomes.
#'
#' @param matched_corpus A data frame returned by \code{\link{pplmatchQC}}.
#' @param sample_size Total number of rows to sample (default: 200).
#' @param output_file Path to write the CSV file. Default:
#'   "gold_standard_sample.csv" in the current directory.
#'
#' @return The sampled data frame (invisibly). A CSV file is also written.
#'
#' @details
#' The output CSV contains columns: speaker, event_date, speaker_category,
#' speaker_normalized, matched_name, match_level, match_score, and an empty
#' \code{correct_name} column for the annotator to fill in.
#'
#' Stratification targets:
#' \itemize{
#'   \item deterministic matches: 30\%
#'   \item fuzzy matches: 30\%
#'   \item unmatched: 20\%
#'   \item ambiguous: 10\%
#'   \item roles/crowds/empty: 10\%
#' }
#'
#' @examples
#' \dontrun{
#' matched <- pplmatchQC(corpus, members, verbose = TRUE)
#' generate_gold_sample(matched, sample_size = 200, output_file = "gold_200.csv")
#' # Then manually fill in the 'correct_name' column
#' }
#'
#' @export
generate_gold_sample <- function(matched_corpus,
                                 sample_size = 200,
                                 output_file = "gold_standard_sample.csv") {

  strata <- list(
    deterministic = 0.30,
    fuzzy = 0.30,
    unmatched = 0.20,
    ambiguous = 0.10,
    other = 0.10
  )

  results <- list()
  for (stratum in names(strata)) {
    n_target <- round(sample_size * strata[[stratum]])

    if (stratum == "other") {
      pool <- matched_corpus[matched_corpus$match_level %in%
                               c("role", "crowd", "empty"), ]
    } else {
      pool <- matched_corpus[matched_corpus$match_level == stratum, ]
    }

    n_take <- min(n_target, nrow(pool))
    if (n_take > 0) {
      idx <- sample(seq_len(nrow(pool)), n_take)
      results[[stratum]] <- pool[idx, ]
    }
  }

  sample_df <- dplyr::bind_rows(results)

  # Select relevant columns and add annotation column
  out <- sample_df[, c("speaker", "event_date", "speaker_category",
                        "speaker_normalized", "matched_name",
                        "match_level", "match_score")]
  out$correct_name <- ""

  utils::write.csv(out, output_file, row.names = FALSE)
  message("Gold standard sample written to: ", output_file)
  message("  Rows: ", nrow(out))
  message("  Fill in the 'correct_name' column and save.")

  invisible(out)
}


#' Evaluate Match Quality Against a Gold Standard
#'
#' Computes precision, recall, and F1 score by comparing matched results
#' against a manually annotated gold standard CSV.
#'
#' @param matched_corpus A data frame returned by \code{\link{pplmatchQC}}.
#' @param gold_standard_file Path to the annotated gold standard CSV file.
#'   Must contain columns: speaker, event_date, correct_name.
#'
#' @return A list with: precision, recall, f1, n_total, n_true_positive,
#'   n_true_negative, n_false_positive, n_false_negative, details (data frame).
#'
#' @examples
#' \dontrun{
#' matched <- pplmatchQC(corpus, members)
#' metrics <- evaluate_matches_qc(matched, "gold_standard_annotated.csv")
#' message(sprintf("Precision: %.1f%%, Recall: %.1f%%, F1: %.1f%%",
#'                 metrics$precision * 100, metrics$recall * 100, metrics$f1 * 100))
#' }
#'
#' @export
evaluate_matches_qc <- function(matched_corpus, gold_standard_file) {

  gold <- utils::read.csv(gold_standard_file, stringsAsFactors = FALSE)

  if (!all(c("speaker", "event_date", "correct_name") %in% names(gold))) {
    stop("Gold standard file must contain columns: speaker, event_date, correct_name",
         call. = FALSE)
  }

  # Prepare data for Python evaluator
  evaluator <- reticulate::import_from_path("evaluator", path = .find_python_dir())

  # Convert to lists for Python
  matched_list <- purrr::map(seq_len(nrow(matched_corpus)), function(i) {
    list(
      speaker = as.character(matched_corpus$speaker[i]),
      event_date = as.character(matched_corpus$event_date[i]),
      matched_name = as.character(matched_corpus$matched_name[i])
    )
  })

  gold_list <- purrr::map(seq_len(nrow(gold)), function(i) {
    cn <- gold$correct_name[i]
    list(
      speaker = as.character(gold$speaker[i]),
      event_date = as.character(gold$event_date[i]),
      correct_name = if (is.na(cn) || cn == "") NULL else as.character(cn)
    )
  })

  result <- evaluator$evaluate(matched_list, gold_list)

  # Convert details to data frame
  if (length(result$details) > 0) {
    details_df <- dplyr::bind_rows(lapply(result$details, as.data.frame,
                                          stringsAsFactors = FALSE))
  } else {
    details_df <- data.frame()
  }

  list(
    precision = result$precision,
    recall = result$recall,
    f1 = result$f1,
    n_total = result$n_total,
    n_true_positive = result$n_true_positive,
    n_true_negative = result$n_true_negative,
    n_false_positive = result$n_false_positive,
    n_false_negative = result$n_false_negative,
    details = details_df
  )
}
