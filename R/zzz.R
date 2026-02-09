.onLoad <- function(libname, pkgname) {
  venv <- "pplmatch"
  if (reticulate::virtualenv_exists(venv)) {
    reticulate::use_virtualenv(venv, required = FALSE)
  }
}
