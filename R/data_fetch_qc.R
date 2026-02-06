#' Fetch Quebec National Assembly Debate Data
#'
#' Retrieves debate data from the CLESSN data warehouse via the tube package.
#' Requires the tube package to be installed and configured.
#'
#' @param date_from Start date (character or Date, format YYYY-MM-DD).
#' @param date_to End date (character or Date, format YYYY-MM-DD).
#' @param env Environment to connect to (default: "PROD").
#'
#' @return A list with two elements:
#'   \item{corpus}{Tibble of debate interventions with columns including
#'     \code{speaker} and \code{event_date}.}
#'   \item{members}{Tibble of assembly member records with columns including
#'     \code{full_name}, \code{party_id}, \code{gender}, \code{legislature_id}.}
#'
#' @details
#' This function requires the \code{tube} package (internal CLESSN package)
#' to be installed. It connects to both the datalake and datawarehouse.
#'
#' @examples
#' \dontrun{
#' data <- data_fetch_qc("2022-01-01", "2024-12-31")
#' matched <- pplmatchQC(data$corpus, data$members, verbose = TRUE)
#' }
#'
#' @export
data_fetch_qc <- function(date_from, date_to, env = "PROD") {
  if (!requireNamespace("tube", quietly = TRUE)) {
    stop("The 'tube' package is required. Install it from the CLESSN repository.",
         call. = FALSE)
  }

  date_from <- as.character(date_from)
  date_to <- as.character(date_to)

  # Connect to data warehouse
  conn_wh <- tube::ellipse_connect(env, "datawarehouse")

  # Fetch debates
  corpus <- tube::ellipse_query(conn_wh, "a-qc-parliament-debates") |>
    dplyr::filter(
      event_date >= date_from,
      event_date <= date_to
    ) |>
    dplyr::collect() |>
    tibble::as_tibble()

  # Rename speaker column if needed
  if ("speaker_full_name" %in% names(corpus) && !"speaker" %in% names(corpus)) {
    corpus <- dplyr::rename(corpus, speaker = speaker_full_name)
  }

  # Fetch member records
  conn_dev <- tube::ellipse_connect("DEV", "datawarehouse")
  members <- tube::ellipse_query(conn_dev, "dim-qc-parliament-members") |>
    dplyr::collect() |>
    tibble::as_tibble() |>
    dplyr::mutate(legislature_id = stringr::str_extract(legislature_id, "\\d+"))

  list(corpus = corpus, members = members)
}
