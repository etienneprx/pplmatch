#' Fetch Quebec National Assembly Debate Data
#'
#' Retrieves debate data from the CLESSN infrastructure via the tube package.
#' Transparently merges recent data (Datawarehouse) and historical data (Datalake).
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
#' This function seamlessly combines:
#' \itemize{
#'   \item Recent debates (2016-09-20+) from the Datawarehouse table \code{a-qc-parliament-debates}.
#'   \item Vintage debates (1908-2016) from the Datalake table \code{a-qc-parliament-debates-vintage}.
#'   \item Current member records from the Datawarehouse.
#'   \item Historical member records from an internal dataset.
#' }
#' Requires the \code{tube} package to be installed and configured.
#'
#' @examples
#' \dontrun{
#' # Fetch a range overlapping historical and recent data
#' data <- data_fetch_qc("2015-01-01", "2018-12-31")
#' matched <- pplmatchQC(data$corpus, data$members, verbose = TRUE)
#' }
#'
#' @export
data_fetch_qc <- function(date_from, date_to, env = "PROD") {
  if (!requireNamespace("tube", quietly = TRUE)) {
    stop("The 'tube' package is required. Install it from the CLESSN repository.",
         call. = FALSE)
  }

  date_from <- as.Date(date_from)
  date_to <- as.Date(date_to)
  
  # Pivot date for QC data source transition
  PIVOT_DATE <- as.Date("2016-09-20")
  
  # Initialize lists to hold dataframes
  dfs_corpus <- list()

  # --- 1. Fetch Recent Data (Datawarehouse) ---
  if (date_to >= PIVOT_DATE) {
    conn_wh <- tube::ellipse_connect(env, "datawarehouse")
    
    # Adjust query range to not go below pivot if user asks for older
    start_wh <- max(date_from, PIVOT_DATE)
    
    tryCatch({
      # Optimization: Select useful columns, exclude heavy technical metadata
      q_wh <- tube::ellipse_query(conn_wh, "a-qc-parliament-debates") |>
        dplyr::filter(
          event_date >= as.character(start_wh),
          event_date <= as.character(date_to)
        ) |>
        dplyr::select(
          event_date,
          intervention_seqnum,
          speaker = speaker_full_name,
          text = intervention_text,
          event_title,
          subject_of_business_title,
          subject_of_business_subtitle,
          intervention_lang
        )
      
      df_wh <- q_wh |> 
        dplyr::collect() |> 
        tibble::as_tibble() |>
        dplyr::mutate(
          source_type = "datawarehouse",
          event_date = as.Date(event_date),
          intervention_seqnum = as.integer(intervention_seqnum)
        )
      
      # Handle potential schema mismatches if older version of table is used
      if ("speaker_full_name" %in% names(df_wh) && !"speaker" %in% names(df_wh)) {
        df_wh <- dplyr::rename(df_wh, speaker = speaker_full_name)
      }
      
      if (nrow(df_wh) > 0) dfs_corpus$wh <- df_wh
      
    }, error = function(e) {
      warning("Could not fetch from Datawarehouse: ", e$message)
    })
  }

  # --- 2. Fetch Vintage Data (Datalake) ---
  if (date_from < PIVOT_DATE) {
    conn_lake <- tube::ellipse_connect("DEV", "datalake") 
    
    # Adjust query range
    end_lake <- min(date_to, PIVOT_DATE - 1)
    
    tryCatch({
      # Optimization: Select specific columns BEFORE collecting
      q_lake <- tube::ellipse_query(conn_lake, "a-qc-parliament-debates-vintage") |>
        dplyr::filter(
          event_date >= as.character(date_from),
          event_date <= as.character(end_lake)
        ) |>
        dplyr::select(
          event_date,
          intervention_seqnum,
          speaker = speaker_full_name,
          text = intervention_text,
          event_title,
          subject_of_business_title,
          subject_of_business_subtitle,
          intervention_lang
        )
      
      df_lake <- q_lake |> 
        dplyr::collect() |> 
        tibble::as_tibble() |>
        dplyr::mutate(
          source_type = "datalake_vintage",
          event_date = as.Date(event_date),
          intervention_seqnum = as.integer(intervention_seqnum)
        )
      
      if (nrow(df_lake) > 0) dfs_corpus$lake <- df_lake
      
    }, error = function(e) {
      warning("Could not fetch from Datalake (vintage): ", e$message)
    })
  }

  # --- 3. Merge Corpus ---
  if (length(dfs_corpus) == 0) {
    warning("No debate data found for the specified period.")
    corpus <- tibble::tibble(speaker = character(), event_date = as.Date(character()))
  } else {
    # bind_rows automatically handles missing columns (fills with NA)
    corpus <- dplyr::bind_rows(dfs_corpus) |>
      dplyr::arrange(event_date, intervention_seqnum)
  }

  # --- 4. Fetch Members (Hybrid: Warehouse + Historical CSV) ---
  
  # Fetch current members from Warehouse (usually only current Leg)
  conn_dev <- tube::ellipse_connect("DEV", "datawarehouse")
  members_wh <- tube::ellipse_query(conn_dev, "dim-qc-parliament-members") |>
    dplyr::collect() |>
    tibble::as_tibble() |>
    dplyr::mutate(legislature_id = as.character(stringr::str_extract(legislature_id, "\\d+")))

  # Load historical members from package data
  history_file <- system.file("extdata", "members_historic_qc.csv", package = "pplmatch")
  if (history_file != "") {
    members_hist <- utils::read.csv(history_file, stringsAsFactors = FALSE) |>
      tibble::as_tibble() |>
      dplyr::mutate(legislature_id = as.character(legislature_id))
    
    # Select key columns for consistent binding
    needed_cols <- c("full_name", "party_id", "gender", "legislature_id", "other_names", "district_id")
    
    m1 <- members_wh |> dplyr::select(dplyr::any_of(needed_cols))
    m2 <- members_hist |> dplyr::select(dplyr::any_of(needed_cols))
    
    # Combine and deduplicate
    members <- dplyr::bind_rows(m1, m2) |>
      dplyr::distinct(full_name, legislature_id, .keep_all = TRUE)
  } else {
    warning("Historical members file not found. Results for older legislatures may be incomplete.")
    members <- members_wh
  }

  list(corpus = corpus, members = members)
}
