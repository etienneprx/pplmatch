#' Appariement des intervenants de l'Assemblee nationale du Quebec
#'
#' Fait correspondre les noms des intervenants dans les debats de l'Assemblee
#' nationale du Quebec avec la table dimensionnelle des deputes. Utilise un
#' matching multi-niveaux : deterministe (correspondance exacte apres
#' normalisation) puis fuzzy (similarite via rapidfuzz en Python).
#'
#' @param Corpus Un data frame des debats parlementaires. Doit contenir au
#'   minimum les colonnes :
#'   \describe{
#'     \item{speaker}{Nom de l'intervenant tel qu'il apparait dans les debats
#'       (ex: "Legault", "M. Berube", "Le President", "Des Voix").}
#'     \item{event_date}{Date du debat, en format Date ou caractere YYYY-MM-DD.}
#'   }
#'   Toutes les autres colonnes sont conservees dans le resultat.
#'
#' @param Names Un data frame de la table des deputes. Colonnes requises :
#'   \describe{
#'     \item{full_name}{Nom complet du depute (ex: "Francois Legault").}
#'     \item{party_id}{Identifiant du parti (ex: "CAQ", "PLQ", "PQ", "QS").}
#'     \item{gender}{Genre du depute ("m" ou "f").}
#'     \item{legislature_id}{Numero de la legislature en caractere (ex: "42").}
#'   }
#'   Colonnes optionnelles :
#'   \describe{
#'     \item{other_names}{Noms alternatifs separes par des points-virgules
#'       (ex: "Legault; F. Legault"). Utile pour les noms qui different
#'       entre les debats et la table officielle.}
#'     \item{district_id}{Identifiant de la circonscription.}
#'   }
#'
#' @param fuzzy_threshold Score minimum (0 a 100) pour accepter un match fuzzy.
#'   Defaut : 85. Un seuil plus eleve = plus precis mais moins de matchs.
#'   Un seuil plus bas = plus de matchs mais plus de faux positifs.
#'
#' @param legislatures Vecteur d'entiers des numeros de legislatures a traiter.
#'   Defaut : 35:43 (1994 a aujourd'hui). Les lignes du corpus dont la date
#'   tombe hors de ces legislatures recoivent un \code{match_level} de
#'   \code{"unmatched"} et un \code{legislature} de \code{NA}.
#'
#' @param verbose Logique. Si \code{TRUE}, affiche la progression et un resume
#'   des resultats a la fin. Defaut : \code{FALSE}.
#'
#' @return Un tibble contenant toutes les colonnes du Corpus original, plus
#'   les colonnes suivantes :
#'   \describe{
#'     \item{legislature}{Numero de la legislature (entier, 35 a 43) determine
#'       automatiquement a partir de \code{event_date}. \code{NA} si la date
#'       est hors des legislatures couvertes.}
#'     \item{speaker_category}{Classification de l'intervenant :
#'       \code{"person"} (depute), \code{"role"} (fonction institutionnelle
#'       comme "Le President"), \code{"crowd"} (voix collectives comme
#'       "Des Voix"), ou \code{"empty"} (champ vide).}
#'     \item{speaker_normalized}{Version normalisee du nom (minuscules, sans
#'       accents, sans honorifiques). Vide pour les non-personnes.}
#'     \item{matched_name}{Nom complet du depute apparie, ou \code{NA} si
#'       aucun match.}
#'     \item{party_id}{Parti politique du depute apparie, ou \code{NA}.}
#'     \item{gender}{Genre du depute apparie, ou \code{NA}.}
#'     \item{district_id}{Circonscription du depute apparie, ou \code{NA}.}
#'     \item{match_level}{Niveau de l'appariement :
#'       \code{"deterministic"} (correspondance exacte),
#'       \code{"fuzzy"} (similarite au-dessus du seuil),
#'       \code{"ambiguous"} (plusieurs deputes possibles),
#'       \code{"unmatched"} (aucune correspondance),
#'       \code{"role"}, \code{"crowd"}, \code{"empty"}.}
#'     \item{match_score}{Score de similarite entre 0 et 100. \code{100} pour
#'       les matchs deterministes, la valeur calculee pour les fuzzy, \code{NA}
#'       pour les non-matchs.}
#'   }
#'
#' @section Prerequis:
#' Avant la premiere utilisation, executer \code{\link{ensure_python_deps}()}
#' pour installer les dependances Python (rapidfuzz).
#'
#' @section Pipeline de matching:
#' \enumerate{
#'   \item **Preprocessing** : classification de l'intervenant, normalisation
#'     du nom (retrait des honorifiques, accents, chiffres, districts).
#'   \item **Niveau 1 (deterministe)** : correspondance exacte sur le nom
#'     complet normalise, puis sur les noms alternatifs, puis sur le nom
#'     de famille seul (si non-ambigu dans la legislature).
#'   \item **Niveau 2 (fuzzy)** : si le niveau 1 echoue, comparaison par
#'     similarite avec rapidfuzz. Score pondere different pour les noms
#'     complets vs noms de famille seuls.
#' }
#'
#' @examples
#' \dontrun{
#' # Premiere utilisation : installer les dependances Python
#' ensure_python_deps()
#'
#' # Preparer les donnees
#' corpus <- data.frame(
#'   speaker = c("Legault", "M. Bérubé", "Le Président", "Des Voix"),
#'   event_date = as.Date(c("2023-03-15", "2023-03-15", "2023-03-15", "2023-03-15"))
#' )
#'
#' members <- data.frame(
#'   full_name = c("François Legault", "Pascal Bérubé"),
#'   party_id = c("CAQ", "PQ"),
#'   gender = c("m", "m"),
#'   legislature_id = c("43", "43")
#' )
#'
#' # Lancer l'appariement
#' result <- pplmatchQC(corpus, members, fuzzy_threshold = 85, verbose = TRUE)
#'
#' # Verifier le taux d'appariement (personnes seulement)
#' persons <- result[result$speaker_category == "person", ]
#' rate <- sum(persons$match_level %in% c("deterministic", "fuzzy")) / nrow(persons)
#' message(sprintf("Taux d'appariement : %.1f%%", rate * 100))
#'
#' # Explorer les cas non-apparies
#' unmatched <- result[result$match_level == "unmatched", ]
#' table(unmatched$speaker)
#'
#' # Explorer les cas ambigus
#' ambiguous <- result[result$match_level == "ambiguous", ]
#' table(ambiguous$speaker)
#' }
#'
#' @seealso \code{\link{ensure_python_deps}} pour l'installation des dependances,
#'   \code{\link{data_fetch_qc}} pour recuperer les donnees depuis le datawarehouse,
#'   \code{\link{generate_gold_sample}} et \code{\link{evaluate_matches_qc}} pour
#'   l'evaluation de la qualite.
#'
#' @import dplyr
#' @importFrom tibble as_tibble tibble
#' @importFrom purrr map_chr map_dbl
#' @importFrom reticulate import_from_path
#'
#' @export
pplmatchQC <- function(Corpus, Names,
                       fuzzy_threshold = 85,
                       legislatures = 35:43,
                       verbose = FALSE) {

  # Load Python matcher
  matcher <- .load_matcher()

  # Prepare corpus rows as list of dicts for Python
  corpus_list <- purrr::map(seq_len(nrow(Corpus)), function(i) {
    list(
      speaker = as.character(Corpus$speaker[i]),
      event_date = as.character(Corpus$event_date[i])
    )
  })

  # Prepare member records as list of dicts for Python
  # Filter to requested legislatures
  Names_filtered <- Names[Names$legislature_id %in% as.character(legislatures), ]

  members_list <- purrr::map(seq_len(nrow(Names_filtered)), function(i) {
    row <- Names_filtered[i, ]
    m <- list(
      full_name = as.character(row$full_name),
      party_id = as.character(row$party_id),
      gender = as.character(row$gender),
      legislature_id = as.character(row$legislature_id)
    )
    if ("other_names" %in% names(row) && !is.na(row$other_names)) {
      m$other_names <- as.character(row$other_names)
    }
    if ("district_id" %in% names(row) && !is.na(row$district_id)) {
      m$district_id <- as.character(row$district_id)
    }
    m
  })

  # Get legislatures JSON path
  leg_path <- file.path(.find_extdata_dir(), "legislatures_qc.json")

  # Call Python matcher
  results <- matcher$match_corpus(
    corpus_rows = corpus_list,
    members = members_list,
    fuzzy_threshold = as.integer(fuzzy_threshold),
    legislatures_path = leg_path,
    verbose = verbose
  )

  # Convert Python results back to tibble
  n <- length(results)
  out <- tibble::tibble(
    speaker_category = purrr::map_chr(results, ~ .x$speaker_category %||% NA_character_),
    speaker_normalized = purrr::map_chr(results, ~ .x$speaker_normalized %||% NA_character_),
    legislature = purrr::map_int(results, ~ as.integer(.x$legislature %||% NA_integer_)),
    matched_name = purrr::map_chr(results, ~ .x$matched_name %||% NA_character_),
    party_id = purrr::map_chr(results, ~ .x$party_id %||% NA_character_),
    gender = purrr::map_chr(results, ~ .x$gender %||% NA_character_),
    district_id = purrr::map_chr(results, ~ .x$district_id %||% NA_character_),
    match_level = purrr::map_chr(results, ~ .x$match_level %||% NA_character_),
    match_score = purrr::map_dbl(results, ~ as.double(.x$match_score %||% NA_real_))
  )

  # Bind with original corpus
  result_df <- dplyr::bind_cols(Corpus, out)
  return(result_df)
}

#' @keywords internal
`%||%` <- function(x, y) if (is.null(x)) y else x
