# Activate the pplmatch virtualenv and initialize Python before running tests
if (requireNamespace("reticulate", quietly = TRUE)) {
  if (reticulate::virtualenv_exists("pplmatch")) {
    reticulate::use_virtualenv("pplmatch", required = FALSE)
  }
  # Force Python initialization so py_available() returns TRUE in tests
  try(reticulate::py_config(), silent = TRUE)
}
