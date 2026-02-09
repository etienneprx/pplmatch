#' Charger la table des deputes historiques du Quebec
#'
#' Lit le fichier CSV des deputes integre au package et retourne un tibble
#' pret a etre utilise avec \code{\link{pplmatchQC}}.
#'
#' @return Un tibble avec les colonnes : \code{full_name}, \code{party_id},
#'   \code{gender}, \code{legislature_id}, \code{other_names}, \code{district_id}.
#'
#' @examples
#' \dontrun{
#' members <- qc_members()
#' head(members)
#' }
#'
#' @export
qc_members <- function() {
  history_file <- system.file("extdata", "members_historic_qc.csv", package = "pplmatch")
  if (history_file == "") {
    stop("Members file not found. Is the pplmatch package properly installed?",
         call. = FALSE)
  }

  members <- utils::read.csv(history_file, stringsAsFactors = FALSE) |>
    tibble::as_tibble() |>
    dplyr::mutate(legislature_id = as.character(legislature_id))

  needed_cols <- c("full_name", "party_id", "gender", "legislature_id",
                   "other_names", "district_id")
  members <- members |> dplyr::select(dplyr::any_of(needed_cols))

  members
}
