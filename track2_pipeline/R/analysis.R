#!/usr/bin/env Rscript
# Compare two venues: correlation of daily changes -> distance -> minimum spanning tree (MST) -> tree overlap.
# Usage: Rscript R/analysis.R <panel_A.csv> <panel_B.csv> <labelA> <labelB> <out_dir> [min_overlap=30] [nperm=5000]
# Inputs: long panel CSVs with columns date, meeting, e_move_bp (expected move, bp).
# Outputs in out_dir: summary.csv, degree.csv, edges_A.csv, edges_B.csv, corr_<label>.csv, mst_side_by_side.png.
suppressPackageStartupMessages(library(igraph))
args <- commandArgs(trailingOnly = TRUE)
fa <- args[1]; fb <- args[2]; la <- args[3]; lb <- args[4]; out <- args[5]
min_overlap <- if (length(args) >= 6) as.integer(args[6]) else 30L   # fewest shared daily changes for a usable correlation
nperm <- if (length(args) >= 7) as.integer(args[7]) else 5000L       # number of permutation draws
dir.create(out, showWarnings = FALSE, recursive = TRUE)
set.seed(301)

# wide(): read a panel CSV; return a date x meeting matrix of e_move_bp (bp), NA where missing.
wide <- function(f) {
  d <- read.csv(f, stringsAsFactors = FALSE)
  d$date <- as.Date(d$date)
  dates <- sort(unique(d$date)); mts <- sort(unique(d$meeting))
  m <- matrix(NA_real_, length(dates), length(mts), dimnames = list(as.character(dates), mts))
  m[cbind(match(as.character(d$date), rownames(m)), match(d$meeting, colnames(m)))] <- d$e_move_bp
  m
}
A <- wide(fa); B <- wide(fb)

# keep meetings and calendar dates present in both venues
mts <- intersect(colnames(A), colnames(B)); dts <- intersect(rownames(A), rownames(B))
stopifnot(length(mts) >= 3, length(dts) >= min_overlap)
A <- A[dts, mts, drop = FALSE]; B <- B[dts, mts, drop = FALSE]
# daily change in expected move, in bp (levels drift slowly and give spurious correlation)
dA <- apply(A, 2, diff); dB <- apply(B, 2, diff)

# to_dist(): daily-change matrix -> list(rho = correlation matrix, dist = sqrt(2 * (1 - rho)), n = pairwise overlap counts).
to_dist <- function(dx) {
  rho <- suppressWarnings(cor(dx, use = "pairwise.complete.obs"))
  n <- crossprod(!is.na(dx))
  rho[n < min_overlap] <- NA
  # pairs with fewer than min_overlap shared days get the largest distance, 2, so the MST uses them last
  d <- sqrt(2 * (1 - rho)); d[is.na(d)] <- 2
  diag(d) <- 0
  list(rho = rho, dist = d, n = n)
}
RA <- to_dist(dA); RB <- to_dist(dB)

# mst_of(): distance matrix -> igraph MST with edge attribute weight (distance).
mst_of <- function(d) {
  g <- graph_from_adjacency_matrix(d, mode = "undirected", weighted = TRUE, diag = FALSE)
  mst(g, weights = E(g)$weight)
}
TA <- mst_of(RA$dist); TB <- mst_of(RB$dist)

# edge_keys(): graph -> character vector "meetingA|meetingB" per edge, names sorted so A|B equals B|A.
edge_keys <- function(g) {
  e <- as_edgelist(g)
  apply(e, 1, function(r) paste(sort(r), collapse = "|"))
}
kA <- edge_keys(TA); kB <- edge_keys(TB)
shared <- intersect(kA, kB)
jacc <- length(shared) / length(union(kA, kB))   # shared edges / edges in either tree

# permutation test: shuffle the meeting labels on tree B (same shape) and count edges shared with tree A
perm_shared <- replicate(nperm, {
  g <- TB; V(g)$name <- sample(V(g)$name)
  length(intersect(kA, edge_keys(g)))
})
p_perm <- mean(perm_shared >= length(shared))   # share of shuffles with at least the observed shared-edge count

# Mantel-style correlation between the two distance matrices (upper triangle only)
ut <- upper.tri(RA$dist)
mantel_r <- cor(RA$dist[ut], RB$dist[ut])

deg <- data.frame(meeting = mts, deg_A = degree(TA)[mts], deg_B = degree(TB)[mts])
names(deg)[2:3] <- c(paste0("degree_", la), paste0("degree_", lb))
# hubs(): names of the node(s) with the highest degree, comma-separated
hubs <- function(g) paste(names(degree(g))[degree(g) == max(degree(g))], collapse = ", ")
summ <- data.frame(
  n_meetings = length(mts), n_days = length(dts) - 1, min_overlap = min_overlap,
  edges_per_tree = length(kA), shared_edges = length(shared), jaccard = round(jacc, 3),
  perm_p_value = round(p_perm, 4), mantel_r = round(mantel_r, 3),
  hub_A = hubs(TA), hub_B = hubs(TB))
write.csv(summ, file.path(out, "summary.csv"), row.names = FALSE)
write.csv(deg, file.path(out, "degree.csv"), row.names = FALSE)
for (nm in c("A", "B")) {
  g <- if (nm == "A") TA else TB; k <- if (nm == "A") kA else kB
  ed <- as_data_frame(g, "edges"); ed$key <- k; ed$shared <- ed$key %in% shared
  write.csv(ed, file.path(out, paste0("edges_", nm, ".csv")), row.names = FALSE)
}
write.csv(round(RA$rho, 3), file.path(out, paste0("corr_", la, ".csv")))
write.csv(round(RB$rho, 3), file.path(out, paste0("corr_", lb, ".csv")))

# side-by-side figure: same circle positions in both panels, meetings in date order, shared edges in red
lay <- layout_in_circle(TA, order = order(V(TA)$name))
# draw(): plot tree g with edge keys k and panel title; shared edges red and 4 px wide, others grey and 2 px.
draw <- function(g, k, title) {
  ec <- ifelse(k %in% shared, "#c0392b", "grey55"); ew <- ifelse(k %in% shared, 4, 2)
  plot(g, layout = lay[match(V(g)$name, V(TA)$name), ], vertex.size = 22, vertex.color = "#fdf2e9",
       vertex.label.cex = 0.75, vertex.label.color = "black", edge.color = ec, edge.width = ew, main = title)
}
png(file.path(out, "mst_side_by_side.png"), width = 1800, height = 900, res = 150)
par(mfrow = c(1, 2), mar = c(1, 1, 3, 1))
draw(TA, kA, paste0(la, " MST")); draw(TB, kB, paste0(lb, " MST"))
mtext(sprintf("Red = edge present in both trees (%d of %d); permutation p = %.3f", length(shared), length(kA), p_perm),
      side = 1, outer = TRUE, line = -1.5, cex = 0.9)
dev.off()
print(summ); print(deg)
