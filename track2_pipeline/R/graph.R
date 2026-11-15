# graph.R
# Correlation networks, minimum spanning trees and tests for comparing two trees or correlation matrices.
# Used by report/extensions.Rmd and tests/testthat. Needs igraph, dplyr, tibble.

suppressPackageStartupMessages({
  library(igraph)
  library(dplyr)
  library(tibble)
})

# cor_matrix: correlation of daily changes between meetings.
# Input: rows of `changes` for one window, nodes, method ("pearson" or "spearman"),
#   both_moved (TRUE: a day counts for a pair only when both meetings changed).
# Output: square correlation matrix with node names.
cor_matrix <- function(df, nodes, method = "pearson", both_moved = FALSE) {
  x <- as.matrix(df[, nodes])
  # a meeting with no change in the sample gives NA correlations (warning silenced); build_mst maps NA to distance 2
  if (!both_moved) return(suppressWarnings(cor(x, use = "pairwise.complete.obs", method = method)))
  C <- diag(length(nodes)); dimnames(C) <- list(nodes, nodes)
  for (i in seq_along(nodes)) for (j in seq_along(nodes)) if (i < j) {
    ok <- !is.na(x[, i]) & !is.na(x[, j]) & x[, i] != 0 & x[, j] != 0
    C[i, j] <- C[j, i] <- if (sum(ok) >= 3) cor(x[ok, i], x[ok, j], method = method) else NA_real_
  }
  C
}

# to_distance: correlation to distance, d = sqrt(2 (1 - rho)); 0 for rho = 1, 2 for rho = -1.
to_distance <- function(C) sqrt(2 * (1 - C))

# build_mst: minimum spanning tree of a correlation matrix.
# Input: correlation matrix with node names. Output: igraph tree with edge attributes weight (distance), rho.
# Built from an edge list so a pair with rho = 1 (distance 0) keeps its edge; NA correlations get distance 2.
build_mst <- function(C) {
  nodes <- rownames(C)
  pairs <- t(combn(nodes, 2))
  rho <- C[pairs]
  d <- to_distance(rho)
  d[is.na(d)] <- 2
  g <- graph_from_data_frame(data.frame(from = pairs[, 1], to = pairs[, 2], weight = d, rho = rho),
                             directed = FALSE, vertices = nodes)
  mst(g, weights = E(g)$weight)
}

# edge_keys: one key per tree edge, earlier meeting first, e.g. "2026-10|2026-12".
edge_keys <- function(t) {
  e <- ends(t, E(t))
  paste(pmin(e[, 1], e[, 2]), pmax(e[, 1], e[, 2]), sep = "|")
}

# n_shared: number of edges two trees have in common.
n_shared <- function(t1, t2) length(intersect(edge_keys(t1), edge_keys(t2)))

# perm_shared_mc: Monte Carlo permutation test for shared edges, as in the submitted report.
# Input: t_fixed, t_shuffled (trees), nodes, n_perm, seed.
# Output: list(observed, null = shared counts under random relabelling, p = (k + 1) / (n_perm + 1)).
perm_shared_mc <- function(t_fixed, t_shuffled, nodes, n_perm = 5000, seed = 301) {
  set.seed(seed)
  keys <- edge_keys(t_fixed)
  e <- ends(t_shuffled, E(t_shuffled))
  null <- replicate(n_perm, {
    relabel <- setNames(sample(nodes), nodes)
    a <- relabel[e[, 1]]; b <- relabel[e[, 2]]
    sum(paste(pmin(a, b), pmax(a, b), sep = "|") %in% keys)
  })
  obs <- n_shared(t_fixed, t_shuffled)
  list(observed = obs, null = null, p = (sum(null >= obs) + 1) / (n_perm + 1))
}

# permutations: all orderings of a vector, one per row (n! rows; 5040 for 7 nodes).
permutations <- function(x) {
  if (length(x) <= 1) return(matrix(x, nrow = 1))
  do.call(rbind, lapply(seq_along(x), function(i) cbind(x[i], permutations(x[-i]))))
}

# perm_shared_exact: exact permutation test for shared edges over all relabellings of the nodes.
# Input: t_fixed, t_shuffled, nodes. Output: list(observed, null (n! counts), p = share of relabellings >= observed).
perm_shared_exact <- function(t_fixed, t_shuffled, nodes) {
  keys <- edge_keys(t_fixed)
  e <- ends(t_shuffled, E(t_shuffled))
  P <- permutations(nodes)
  null <- apply(P, 1, function(perm) {
    relabel <- setNames(perm, nodes)
    a <- relabel[e[, 1]]; b <- relabel[e[, 2]]
    sum(paste(pmin(a, b), pmax(a, b), sep = "|") %in% keys)
  })
  obs <- n_shared(t_fixed, t_shuffled)
  list(observed = obs, null = null, p = mean(null >= obs))
}

# mantel_exact: Mantel correlation of two distance matrices with an exact permutation p-value.
# Input: D1, D2 (square, same node names). Output: list(r = correlation of upper triangles, p = share of
#   node relabellings of D2 with r at least as large).
mantel_exact <- function(D1, D2) {
  nodes <- rownames(D1)
  ut <- upper.tri(D1)
  r_obs <- cor(D1[ut], D2[nodes, nodes][ut])
  P <- permutations(seq_along(nodes))
  null <- apply(P, 1, function(o) cor(D1[ut], D2[o, o][ut]))
  list(r = r_obs, p = mean(null >= r_obs - 1e-12))
}

# jennrich_test: chi-square test that two correlation matrices are equal (Jennrich 1970).
# Input: R1, R2 (p x p), n1, n2 (sample sizes). Output: list(chi2, df = p(p-1)/2, p).
# Assumes independent, normally distributed observations.
jennrich_test <- function(R1, n1, R2, n2) {
  p <- nrow(R1)
  R <- (n1 * R1 + n2 * R2) / (n1 + n2)
  R_inv <- solve(R)
  S <- diag(p) + R * R_inv
  Z <- sqrt(n1 * n2 / (n1 + n2)) * R_inv %*% (R1 - R2)
  chi2 <- sum(diag(Z %*% Z)) / 2 - as.numeric(t(diag(Z)) %*% solve(S) %*% diag(Z))
  df <- p * (p - 1) / 2
  list(chi2 = chi2, df = df, p = pchisq(chi2, df, lower.tail = FALSE))
}

# fisher_z_pairs: per-pair test of rho_before = rho_after using Fisher's z.
# Input: R1, R2, n1, n2 (scalars or matrices of pairwise sample sizes).
# Output: tibble a, b, rho1, rho2, z, p, p_holm (Holm-adjusted over all pairs).
fisher_z_pairs <- function(R1, n1, R2, n2) {
  nodes <- rownames(R1)
  pairs <- t(combn(nodes, 2))
  n1v <- if (is.matrix(n1)) n1[pairs] else rep(n1, nrow(pairs))
  n2v <- if (is.matrix(n2)) n2[pairs] else rep(n2, nrow(pairs))
  r1 <- R1[pairs]; r2 <- R2[pairs]
  z <- (atanh(r1) - atanh(r2)) / sqrt(1 / (n1v - 3) + 1 / (n2v - 3))
  p <- 2 * pnorm(-abs(z))
  tibble(a = pairs[, 1], b = pairs[, 2], rho1 = r1, rho2 = r2, z = z, p = p, p_holm = p.adjust(p, "holm"))
}

# pair_counts: number of days with both changes observed, per pair of meetings.
pair_counts <- function(df, nodes) {
  ok <- !is.na(as.matrix(df[, nodes]))
  crossprod(ok)
}

# block_bootstrap_edges: how often each edge appears in trees from moving-block bootstrap samples.
# Input: rows of `changes` for one window, nodes, n_boot, block_len (days), seed.
# Output: tibble edge, freq (share of bootstrap trees containing the edge), sorted by freq.
block_bootstrap_edges <- function(df, nodes, n_boot = 1000, block_len = 5, seed = 301) {
  set.seed(seed)
  n <- nrow(df)
  n_blocks <- ceiling(n / block_len)
  keys <- unlist(lapply(seq_len(n_boot), function(i) {
    starts <- sample.int(n - block_len + 1, n_blocks, replace = TRUE)
    idx <- as.vector(outer(0:(block_len - 1), starts, `+`))[seq_len(n)]
    edge_keys(build_mst(cor_matrix(df[idx, ], nodes)))
  }))
  tibble(edge = keys) |> count(edge, name = "k") |>
    mutate(freq = k / n_boot) |> select(-k) |> arrange(desc(freq))
}

# mean_abs_rho: mean absolute correlation over all pairs (upper triangle), NA pairs ignored.
mean_abs_rho <- function(C) mean(abs(C[upper.tri(C)]), na.rm = TRUE)

# mantel_r: correlation between the upper triangles of two distance matrices (no p-value).
mantel_r <- function(D1, D2) {
  ut <- upper.tri(D1)
  cor(D1[ut], D2[rownames(D1), colnames(D1)][ut], use = "complete.obs")
}

# block_null: how two disjoint samples from the same regime compare, for every contiguous block.
# Input: rows of `changes` for one window, nodes, block_len (days).
# Output: tibble with one row per block: start, end; shared edges between the block's tree and the tree from
#   the rest of the window (shared_rest) and from the whole window (shared_full); mean |rho| in the block;
#   Mantel r between the block's and the rest's distance matrices.
block_null <- function(df, nodes, block_len = 41) {
  full <- build_mst(cor_matrix(df, nodes))
  starts <- seq_len(nrow(df) - block_len + 1)
  bind_rows(lapply(starts, function(s) {
    idx <- s:(s + block_len - 1)
    Cb <- cor_matrix(df[idx, ], nodes)
    Cr <- cor_matrix(df[-idx, ], nodes)
    tb <- build_mst(Cb)
    tibble(start = df$date[s], end = df$date[s + block_len - 1],
           shared_rest = n_shared(tb, build_mst(Cr)), shared_full = n_shared(tb, full),
           mean_abs_rho = mean_abs_rho(Cb), mantel_r = mantel_r(to_distance(Cb), to_distance(Cr)))
  }))
}

# rolling_trees: trees on a rolling window of daily changes.
# Input: changes (all dates), nodes, width (days), ref_trees (named list of trees to compare against).
# Output: tibble end_date, n_days, mean_abs_rho (mean |rho| over all pairs), and shared_<name> per reference tree.
rolling_trees <- function(changes, nodes, width = 60, ref_trees = list()) {
  ends_at <- seq(width, nrow(changes))
  bind_rows(lapply(ends_at, function(i) {
    w <- changes[(i - width + 1):i, ]
    C <- cor_matrix(w, nodes)
    t <- build_mst(C)
    row <- tibble(end_date = w$date[width], n_days = width, mean_abs_rho = mean_abs_rho(C))
    for (nm in names(ref_trees)) row[[paste0("shared_", nm)]] <- n_shared(t, ref_trees[[nm]])
    row
  }))
}
