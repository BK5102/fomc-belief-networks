# load the functions under test; root is track2_pipeline/ whether tests run from there or from tests/testthat
root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
source(file.path(root, "R", "wrangle.R"))
source(file.path(root, "R", "graph.R"))
