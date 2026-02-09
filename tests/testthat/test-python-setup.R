test_that("Python modules can be loaded", {
  skip_if_not(reticulate::py_available(), "Python not available")

  expect_no_error(.load_normalizer())
  expect_no_error(.load_legislature())
})

test_that("Python matcher module can be loaded", {
  skip_if_not(reticulate::py_available(), "Python not available")
  skip_if_not(reticulate::py_module_available("rapidfuzz"),
              "rapidfuzz not installed")

  expect_no_error(.load_matcher())
})
