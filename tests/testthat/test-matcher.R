test_that("Python matcher performs deterministic matching", {
  skip_if_not(reticulate::py_available(), "Python not available")
  matcher <- .load_matcher()

  members <- list(
    list(full_name = "François Legault", party_id = "CAQ", gender = "m",
         legislature_id = "42", other_names = "Legault"),
    list(full_name = "Manon Massé", party_id = "QS", gender = "f",
         legislature_id = "42"),
    list(full_name = "Gabriel Nadeau-Dubois", party_id = "QS", gender = "m",
         legislature_id = "42")
  )

  leg_path <- file.path(.find_extdata_dir(), "legislatures_qc.json")

  # Exact full name match
  corpus <- list(
    list(speaker = "François Legault", event_date = "2020-06-15")
  )
  res <- matcher$match_corpus(corpus, members, 85L, leg_path, FALSE)
  expect_equal(res[[1]]$match_level, "deterministic")
  expect_equal(res[[1]]$matched_name, "François Legault")
  expect_equal(res[[1]]$party_id, "CAQ")

  # Last name only (unambiguous)
  corpus2 <- list(
    list(speaker = "Massé", event_date = "2020-06-15")
  )
  res2 <- matcher$match_corpus(corpus2, members, 85L, leg_path, FALSE)
  expect_equal(res2[[1]]$match_level, "deterministic")
  expect_equal(res2[[1]]$matched_name, "Manon Massé")

  # other_names match
  corpus3 <- list(
    list(speaker = "Legault", event_date = "2020-06-15")
  )
  res3 <- matcher$match_corpus(corpus3, members, 85L, leg_path, FALSE)
  expect_equal(res3[[1]]$match_level, "deterministic")
  expect_equal(res3[[1]]$matched_name, "François Legault")
})

test_that("Python matcher handles roles and crowds", {
  skip_if_not(reticulate::py_available(), "Python not available")
  matcher <- .load_matcher()

  members <- list(
    list(full_name = "François Legault", party_id = "CAQ", gender = "m",
         legislature_id = "42")
  )

  leg_path <- file.path(.find_extdata_dir(), "legislatures_qc.json")

  corpus <- list(
    list(speaker = "Le Président", event_date = "2020-06-15"),
    list(speaker = "Des Voix", event_date = "2020-06-15")
  )
  res <- matcher$match_corpus(corpus, members, 85L, leg_path, FALSE)

  expect_equal(res[[1]]$speaker_category, "role")
  expect_equal(res[[1]]$match_level, "role")
  expect_null(res[[1]]$matched_name)

  expect_equal(res[[2]]$speaker_category, "crowd")
  expect_equal(res[[2]]$match_level, "crowd")
  expect_null(res[[2]]$matched_name)
})

test_that("Python matcher detects ambiguous last names", {
  skip_if_not(reticulate::py_available(), "Python not available")
  matcher <- .load_matcher()

  # Two Proulx in the same legislature
  members <- list(
    list(full_name = "Jean Proulx", party_id = "PLQ", gender = "m",
         legislature_id = "42"),
    list(full_name = "Marie Proulx", party_id = "CAQ", gender = "f",
         legislature_id = "42")
  )

  leg_path <- file.path(.find_extdata_dir(), "legislatures_qc.json")

  corpus <- list(
    list(speaker = "Proulx", event_date = "2020-06-15")
  )
  res <- matcher$match_corpus(corpus, members, 85L, leg_path, FALSE)
  expect_equal(res[[1]]$match_level, "ambiguous")
})

test_that("Python matcher performs fuzzy matching", {
  skip_if_not(reticulate::py_available(), "Python not available")
  matcher <- .load_matcher()

  members <- list(
    list(full_name = "Gabriel Nadeau-Dubois", party_id = "QS", gender = "m",
         legislature_id = "42")
  )

  leg_path <- file.path(.find_extdata_dir(), "legislatures_qc.json")

  # Slightly misspelled name should fuzzy match
  corpus <- list(
    list(speaker = "Gabriel Nadeau Dubois", event_date = "2020-06-15")
  )
  res <- matcher$match_corpus(corpus, members, 80L, leg_path, FALSE)
  expect_true(res[[1]]$match_level %in% c("deterministic", "fuzzy"))
  expect_equal(res[[1]]$matched_name, "Gabriel Nadeau-Dubois")
})

test_that("Python matcher handles honorifics", {
  skip_if_not(reticulate::py_available(), "Python not available")
  matcher <- .load_matcher()

  members <- list(
    list(full_name = "Pascal Bérubé", party_id = "PQ", gender = "m",
         legislature_id = "42")
  )

  leg_path <- file.path(.find_extdata_dir(), "legislatures_qc.json")

  corpus <- list(
    list(speaker = "M. Bérubé", event_date = "2020-06-15")
  )
  res <- matcher$match_corpus(corpus, members, 85L, leg_path, FALSE)
  expect_true(res[[1]]$match_level %in% c("deterministic", "fuzzy"))
  expect_equal(res[[1]]$matched_name, "Pascal Bérubé")
})
