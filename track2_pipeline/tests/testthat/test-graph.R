# unit tests for R/graph.R on small hand-built matrices (no raw data needed)

chain_cor <- function(n, strong = 0.8, weak = 0.1) {
  # n x n correlation matrix where only neighbours (i, i+1) are strongly correlated
  nm <- paste0("m", seq_len(n))
  C <- matrix(weak, n, n, dimnames = list(nm, nm))
  diag(C) <- 1
  for (i in seq_len(n - 1)) C[i, i + 1] <- C[i + 1, i] <- strong
  C
}

test_that("distance transform has the documented values", {
  expect_equal(to_distance(c(1, 0, -1)), c(0, sqrt(2), 2))
})

test_that("MST of a chain-structured matrix is the chain", {
  t <- build_mst(chain_cor(5))
  expect_equal(sort(edge_keys(t)), c("m1|m2", "m2|m3", "m3|m4", "m4|m5"))
  expect_equal(sort(unname(igraph::degree(t))), c(1, 1, 2, 2, 2))
})

test_that("an edge with rho = 1 (distance 0) is kept", {
  t <- build_mst(chain_cor(4, strong = 1))
  expect_equal(length(edge_keys(t)), 3)
  expect_true("m1|m2" %in% edge_keys(t))
})

test_that("permutations returns n! orderings", {
  P <- permutations(1:4)
  expect_equal(dim(P), c(24, 4))
  expect_equal(nrow(unique(P)), 24)
})

test_that("identical trees share all edges and get the smallest exact p", {
  t <- build_mst(chain_cor(5))
  ex <- perm_shared_exact(t, t, rownames(chain_cor(5)))
  expect_equal(ex$observed, 4)
  # relabellings of a 5-node path that map it onto itself: identity and reversal
  expect_equal(ex$p, 2 / 120)
})

test_that("Monte Carlo p uses the (k + 1) / (n + 1) form", {
  t <- build_mst(chain_cor(5))
  mc <- perm_shared_mc(t, t, rownames(chain_cor(5)), n_perm = 99)
  expect_gte(mc$p, 1 / 100)
})

test_that("Mantel r is 1 for identical matrices and Jennrich chi2 is 0", {
  C <- chain_cor(5)
  m <- mantel_exact(to_distance(C), to_distance(C))
  expect_equal(m$r, 1)
  j <- jennrich_test(C, 100, C, 100)
  expect_equal(j$chi2, 0, tolerance = 1e-10)
  expect_equal(j$df, 10)
})

test_that("Fisher z flags a large change in one pair", {
  C1 <- chain_cor(4); C2 <- C1
  C2["m1", "m2"] <- C2["m2", "m1"] <- -0.5
  fz <- fisher_z_pairs(C1, 300, C2, 300)
  expect_lt(fz$p_holm[fz$a == "m1" & fz$b == "m2"], 0.001)
  expect_equal(fz$p[fz$a == "m3" & fz$b == "m4"], 1)
})
