
##### Get som object from flowSOM
#' Get som object from flowSOM
#'
#' @param fcs_raw
#' @param use_markers
#'
#' @return
#' @export
#' @importFrom FlowSOM ReadInput
#' @importFrom FlowSOM BuildSOM
#'
#' @examples
get_som <- function(fcs_raw, clust_markers){
  fsom <- FlowSOM::ReadInput(fcs_raw, transform = FALSE, scale = FALSE)
  set.seed(1234)
  som <- FlowSOM::BuildSOM(fsom, colsToUse = clust_markers)
  return(som)

}

### test
#som <- get_som(fcs_raw, use_markers)

##### Get mc consensusCluster object from ConsensusClusterPlus
#' Get mc consensusCluster object from ConsensusClusterPlus
#'
#' @param som
#' @param maxK
#'
#' @return
#' @export
#' @importFrom ConsensusClusterPlus ConsensusClusterPlus
#'
#' @examples
get_consensusClust <- function(som, maxK = 20){
  mc <- ConsensusClusterPlus::ConsensusClusterPlus(t(som$map$codes), maxK = maxK, reps = 100,
                             pItem = 0.9, pFeature = 1, title = "consensus_plots", plot = "png",
                             clusterAlg = "hc", innerLinkage = "average", finalLinkage = "average",
                             distance = "euclidean", seed = 1234)
  return(mc)
}

### test
#mc <- get_consensusClust(som)

##### Get a optimal number of clusters
#' Get a optimal number of clusters
#'
#' @param mc
#' @param rate_var_expl
#'
#' @return
#' @export
#'
#' @examples
get_optimal_clusters <- function(mc, rate_var_expl = 0.9){
  l <- sapply(2:length(mc), function(x) mean(mc[[x]]$ml))
  l <- sapply(2:length(l), function(x) l[x-1]-l[x])
  l <- l/sum(l)
  l <- sapply(1:length(l), function(x) sum(l[1:x]))
  optimum <- length(mc)
  for(i in length(l):1){
    if(l[i] <= rate_var_expl){
      optimum <- length(mc) - (length(l)-i)
      break}}
  return(optimum)
}

### test
#get_optimal_clusters(mc, rate_var_expl = 0.9)

##### Create the cluster annotation separated by samples
#' Create the cluster annotation separated by samples
#'
#' @param fcs_raw
#' @param som
#' @param mc
#' @param k
#'
#' @return
#' @export
#' @importFrom flowCore fsApply sampleNames "sampleNames<-"
#'
#' @examples
get_cluster_annotation <- function(fcs_raw, som, mc, k){
  code_clustering <- mc[[k]]$consensusClass
  cell_clustering <- code_clustering[som$map$mapping[,1]]
  l <- flowCore::fsApply(fcs_raw, nrow)
  l <- c(0, sapply(1:length(l), function(x) sum(l[1:x])))
  cell_clustering_list <- lapply(2:length(l), function(x) cell_clustering[(l[x-1]+1):l[x]])
  names(cell_clustering_list) <- flowCore::sampleNames(fcs_raw)
  return(cell_clustering_list)
}

### test
#cell_clustering_list <- get_cluster_annotation(fcs_raw, som, mc, 6)

##### Create the cluster annotation as one vector
#' Create the cluster annotation as one vector
#'
#' @param som
#' @param mc
#' @param k
#'
#' @return
#' @export
#'
#' @examples
get_cell_clustering_vector <- function(som, mc, k){
  code_clustering <- mc[[k]]$consensusClass
  cell_clustering <- code_clustering[som$map$mapping[,1]]
  return(cell_clustering)
}

###test
#cell_clustering <- get_cell_clustering_vector(som, mc, 6)

##### Get euclidean distance between clones
#' Get euclidean distance between clones
#'
#' @param fcs_raw
#' @param use_markers
#' @param cell_clustering
#'
#' @return
#' @export
#' @importFrom magrittr "%>%"
#' @importFrom flowCore fsApply exprs "exprs<-"
#' @importFrom dplyr group_by summarize_all funs
#' @importFrom utils combn
#' @importFrom stats dist median
#'
#' @examples
get_euclid_dist <- function(fcs_raw, use_markers, cell_clustering){
  expr_median <- data.frame(flowCore::fsApply(fcs_raw[,use_markers], flowCore::exprs),
                            cell_clustering = cell_clustering, check.names = F) %>%
    dplyr::group_by(cell_clustering) %>% dplyr::summarize_all(dplyr::funs(stats::median))
  rownames(expr_median) <- expr_median$cell_clustering
  expr_median$cell_clustering <- NULL
  cluster_euclidean_distance <- data.frame(t(utils::combn(rownames(expr_median),2)),
                                           dist=as.matrix(stats::dist(expr_median))[lower.tri(as.matrix(stats::dist(expr_median)))] )
  colnames(cluster_euclidean_distance) <- c("Cluster_1", "Cluster_2", "euclidean_distance")
  return(cluster_euclidean_distance)
}

#####  Get edges
#' Get edges
#'
#' @param cluster_euclidean_distance
#'
#' @return
#' @export
#'
#' @examples
get_edges <- function(cluster_euclidean_distance){
  width <- log2(as.numeric(cluster_euclidean_distance$euclidean_distance))/5
  width <- 1+((width - min(width))/(max(width) - min(width))*10)
  edges <- data.frame(from = cluster_euclidean_distance$Cluster_1,
                      to = cluster_euclidean_distance$Cluster_2,
                      width  = width,
                      smooth = T)
  edges <- cluster_euclidean_distance[,1:3]
  colnames(edges) <- c('from', 'to', 'width')
  edges$id <- rownames(edges)
  edges$from <- as.character(edges$from)
  edges$to <- as.character(edges$to)
  edges$width <- as.numeric(edges$width)
  return(edges)
}

##### Filter out edges which have weight more than threshold
#' Filter out edges which have weight more than threshold
#'
#' @param edges
#' @param threshold
#'
#' @return
#' @export
#'
#' @examples
filter_edges <- function(edges, threshold){
  cut_threshold <-  min(edges$width) + ((max(edges$width) - min(edges$width)) * threshold)
  filtered_edges <- edges[edges$width <= cut_threshold, ]
  return(filtered_edges)
}

#####  Get nodes
#' Get nodes
#'
#' @param edges
#' @param cell_clustering
#'
#' @return
#' @export
#' @importFrom RColorBrewer brewer.pal.info brewer.pal
#'
#' @examples
get_nodes <- function(edges, cell_clustering){
  pal_order <- c("Dark2", "Set1", "Set2", "Paired", "Accent", "Set3", "Pastel1", "Pastel2")
  qual_col_pals <- RColorBrewer::brewer.pal.info[RColorBrewer::brewer.pal.info$category == 'qual',]
  cluster_colour <- as.character(unlist(mapply(RColorBrewer::brewer.pal, qual_col_pals[pal_order, 'maxcolors'],
                                         pal_order))[1:length(unique(cell_clustering))])
  id <- unique(c(edges$to, edges$from))
  id <- id[order(id)]
  nodes <- data.frame(id = id,
                      color = cluster_colour,
                      label = id,
                      value = as.numeric(log(table(cell_clustering)[id])),
                      title = paste0("Cluster ",  id,
                                     "<br>number of cells: ", table(cell_clustering)[id]))
  return(nodes)
}

##### Get indexs of rows with were sampled to subset
#' Get indexs of rows with were sampled to subset
#'
#' @param fcs_raw
#' @param plot_ncell
#'
#' @return
#' @export
#' @importFrom flowCore fsApply sampleNames "sampleNames<-"
#'
#' @examples
get_inds_subset <- function(fcs_raw, sampling_size = 0.5, size_fuse = 5000){
  sample_ids <- rep(flowCore::sampleNames(fcs_raw), flowCore::fsApply(fcs_raw, nrow))
  inds <- split(1:length(sample_ids), sample_ids)
  #tsne_ncells <- pmin(table(sample_ids), sampling_size)
  tsne_ncells <- as.integer((table(sample_ids) + 1) * sampling_size)
  if((!is.null(size_fuse) & !is.na(size_fuse)) & (sum(tsne_ncells) > size_fuse)){
    tsne_ncells <- as.integer((tsne_ncells/sum(tsne_ncells))*size_fuse)}
  names(tsne_ncells) <- names(table(sample_ids))
  tsne_inds <- lapply(names(inds), function(i){s <- sample(inds[[i]], tsne_ncells[i], replace = FALSE)})
  tsne_inds <- unlist(tsne_inds)
  return(tsne_inds)
}

#tsne_inds <- get_inds_subset(fcs_raw)

##### Get subseted dataframe for UMAP ploting
#' Title
#'
#' @param fcs_raw
#' @param use_markers
#' @param clust_markers
#' @param tsne_inds
#' @param cell_clustering
#'
#' @return
#' @export
#' @importFrom flowCore fsApply exprs "exprs<-"
#' @importFrom umap umap
#' @importFrom Rtsne Rtsne
#'
#' @examples
get_UMAP_dataframe <- function(fcs_raw, use_markers, clust_markers, tsne_inds, cell_clustering, method = "UMAP",
                               perplexity = 30, theta = 0.5, max_iter = 1000){
  expr_list <- flowCore::fsApply(fcs_raw, function(x){
    tmp <- flowCore::exprs(x)
    return(tmp[,use_markers])
  })
  tsne_expr <- expr_list[tsne_inds, clust_markers]
  if(method == "UMAP"){
    umap_out <- umap::umap(tsne_expr)
    umap_df <- data.frame(expr_list[tsne_inds, use_markers], umap_out$layout, cluster =  as.factor(cell_clustering)[tsne_inds])
  }
  if(method == "tSNE"){
    set.seed(1234)
    umap_out <- Rtsne::Rtsne(tsne_expr, check_duplicates = FALSE, pca = FALSE,
                      perplexity = perplexity, theta = theta, max_iter = max_iter)
    umap_df <- data.frame(expr_list[tsne_inds, use_markers], umap_out$Y, cluster =  as.factor(cell_clustering)[tsne_inds])
  }
  colnames(umap_df) <- c(names(use_markers), "UMAP_1", "UMAP_2", "cluster")
  return(umap_df)
}

#umap_df <- get_UMAP_dataframe(fcs_raw, use_markers, use_markers, tsne_inds, cell_clustering, method = "UMAP", perplexity = 30, theta = 0.5, max_iter = 1000)
#ggplot(umap_df,  aes(x = UMAP_1, y = UMAP_2, color = umap_df[,names(use_markers)[1]])) +
#  geom_point(size = 0.8)
#ggplot(umap_df,  aes(x = UMAP_1, y = UMAP_2, color = umap_df[,"cluster"])) +
#  geom_point(size = 0.8)


##### Create the data table to draw the abundance barplot
#' Create the data table to draw the abundance barplot
#'
#' @param fcs_raw
#' @param cell_clustering
#'
#' @return
#' @export
#' @importFrom flowCore fsApply sampleNames "sampleNames<-"
#'
#' @examples
get_abundance_dataframe <- function(fcs_raw, cell_clustering){
  sample_ids <- rep(flowCore::sampleNames(fcs_raw), flowCore::fsApply(fcs_raw, nrow))
  abundance_data <- table(cell_clustering, sample_ids)
  abundance_data <- t(t(abundance_data) / colSums(abundance_data)) * 100
  abundance_data <- as.data.frame(abundance_data)
  colnames(abundance_data) <- c('cluster', 'sample_ids', 'abundance')
  return(abundance_data)
}

##### Merging two or more clusters within cluster annotating vector
#' Merging two or more clusters within cluster annotating vector
#'
#' @param clusters
#' @param cluster_to_merge
#'
#' @return
#' @export
#' @importFrom magrittr "%>%"
#'
#' @examples
cluster_merging <- function(clusters, cluster_to_merge){
  new_clusters <- clusters
  new_clusters[clusters %in% cluster_to_merge] <- cluster_to_merge[1]
  return(new_clusters)
}

##### Create the cluster annotation separated by samples from fcs files by specific coloumn
#' Create the cluster annotation separated by samples from fcs files by specific coloumn
#'
#' @param fcs_raw
#' @param pattern name or part of colomn name with cluster information. For cytofkit2 output it is "FlowSOM_clusterIDs"
#'
#' @return
#' @export
#' @importFrom flowCore fsApply sampleNames "sampleNames<-" pData "pData<-" parameters "parameters<-" exprs "exprs<-"
#' @importClassesFrom flowCore flowSet
#'
#' @examples
get_fcs_cluster_annotation <- function(fcs_raw, pattern = "clust"){
  cluster_info_col <- flowCore::pData(flowCore::parameters(fcs_raw[[1]]))$name[grepl(pattern, flowCore::pData(flowCore::parameters(fcs_raw[[1]]))$name)]
  cell_clustering_list <- lapply(1:length(fcs_raw), function(x){
    fcs_raw[[x]]@exprs[,cluster_info_col]
  })
  names(cell_clustering_list) <- flowCore::sampleNames(fcs_raw)
  return(cell_clustering_list)
}

#### Create the cluster annotation as one vector for cluster info extraction from fcs file
#' Create the cluster annotation as one vector for cluster info extraction from fcs file
#'
#' @param cell_clustering_list
#'
#' @return
#' @export
#'
#' @examples
get_fcs_cell_clustering_vector <- function(cell_clustering_list){
  cell_clustering <- unlist(cell_clustering_list)
  return(cell_clustering)
}

#### Adding of cluster-info to flowSet object
#' Adding of cluster-info to flowSet object
#'
#' @param fcs_raw
#' @param cell_clustering_list
#'
#' @return
#' @export
#' @importFrom flowCore sampleNames fr_append_cols
#' @importClassesFrom flowCore flowSet
#'
#' @examples
get_clustered_fcs_files <- function(fcs_raw, cell_clustering_list, column_name = "cluster"){
  if(!all(flowCore::sampleNames(fcs_raw) %in% names(cell_clustering_list))){
    print("Cluster and data samples does not match")
    return(NULL)}
  clustered_fcs <- lapply(flowCore::sampleNames(fcs_raw), function(s) {
    addition_col <- as.matrix(cell_clustering_list[[s]])
    colnames(addition_col) <- column_name
    flowCore::fr_append_cols(fcs_raw[[s]], addition_col)
  })
  names(clustered_fcs) <- flowCore::sampleNames(fcs_raw)
  clustered_fcs <- as(clustered_fcs, 'flowSet')
  return(clustered_fcs)
}
