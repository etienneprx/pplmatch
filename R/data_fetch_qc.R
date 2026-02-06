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
#' It combines live data from the datawarehouse (current members) with a
#' historical fallback dataset included in the package.
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

  # 1. Fetch current members from Warehouse (usually only current Leg)
  conn_dev <- tube::ellipse_connect("DEV", "datawarehouse")
  members_wh <- tube::ellipse_query(conn_dev, "dim-qc-parliament-members") |>
    dplyr::collect() |>
    tibble::as_tibble() |>
    dplyr::mutate(legislature_id = as.character(stringr::str_extract(legislature_id, "\\d+")))

  # 2. Load historical members from package data
  history_file <- system.file("extdata", "members_historic_qc.csv", package = "pplmatch")
  if (history_file != "") {
    members_hist <- utils::read.csv(history_file, stringsAsFactors = FALSE) |>
      tibble::as_tibble() |>
      dplyr::mutate(legislature_id = as.character(legislature_id))
    
    # Align columns for binding
    # We prioritize columns present in members_wh, fill missing with NA in hist, and vice-versa
    common_cols <- intersect(names(members_wh), names(members_hist))
    
    # Keep only members from hist that are NOT in wh (based on name + leg_id)
    # Actually, simplistic approach: Filter hist to keep only Leg < 43
    # Assuming WH has 43+
    
    # Let's find max leg in hist
    # max_hist_leg <- max(as.integer(members_hist$legislature_id), na.rm=TRUE)
    
    # A safer merge strategy: bind rows, distinct.
    # But schemas might differ slightly. Let's select key columns for matching.
    
    # Key columns needed for matcher: 
    # full_name, party_id, gender, legislature_id, other_names, district_id
    
    needed_cols <- c("full_name", "party_id", "gender", "legislature_id", "other_names", "district_id")
    
    # Standardize WH
    m1 <- members_wh |> dplyr::select(dplyr::any_of(needed_cols))
    
    # Standardize Hist
    m2 <- members_hist |> dplyr::select(dplyr::any_of(needed_cols))
    
    # Combine
    members_all <- dplyr::bind_rows(m1, m2) |>
      dplyr::distinct(full_name, legislature_id, .keep_all = TRUE)
      
    members <- members_all
  } else {
    warning("Historical members file not found. Results for older legislatures may be incomplete.")
    members <- members_wh
  }

  list(corpus = corpus, members = members)
}
