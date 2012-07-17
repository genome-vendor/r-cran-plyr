#' Combine data.frames by row, filling in missing columns.
#' \code{rbind}s a list of data frames filling missing columns with NA.
#' 
#' This is an enhancement to \code{\link{rbind}} which adds in columns
#' that are not present in all inputs, accepts a list of data frames, and 
#' operates substantially faster.
#'
#' Column names and types in the output will appear in the order in which 
#' they were encoutered. No checking is performed to ensure that each column
#' is of consistent type in the inputs.
#' 
#' @param ... input data frames to row bind together
#' @keywords manip
#' @return a single data frame
#' @export
#' @examples
#' rbind.fill(mtcars[c("mpg", "wt")], mtcars[c("wt", "cyl")])
rbind.fill <- function(...) {
  dfs <- list(...)
  if (length(dfs) == 0) return()
  if (is.list(dfs[[1]]) && !is.data.frame(dfs[[1]])) {
    dfs <- dfs[[1]]
  }
  dfs <- Filter(Negate(empty), dfs)
  
  if (length(dfs) == 0) return()
  if (length(dfs) == 1) return(dfs[[1]])
  
  # Calculate rows in output
  # Using .row_names_info directly is about 6 times faster than using nrow
  rows <- unlist(lapply(dfs, .row_names_info, 2L))
  nrows <- sum(rows)
  
  # Generate output template
  output <- output_template(dfs, nrows)
  
  # Compute start and end positions for each data frame
  pos <- matrix(cumsum(rbind(1, rows - 1)), ncol = 2, byrow = TRUE)
  
  # Copy inputs into output
  for(i in seq_along(rows)) { 
    rng <- pos[i, 1]:pos[i, 2]
    df <- dfs[[i]]
    
    for(var in names(df)) {
      if (!is.matrix(output[[var]])) {
        output[[var]][rng] <- df[[var]]
      } else {
        output[[var]][rng, ] <- df[[var]]
      }
    }
  } 
  
  quickdf(output)
}

output_template <- function(dfs, nrows) {
  vars <- unique(unlist(lapply(dfs, base::names)))   # ~ 125,000/s
  output <- vector("list", length(vars))
  names(output) <- vars
  
  seen <- rep(FALSE, length(output))
  names(seen) <- vars
  
  is_matrix <- seen
  is_factor <- seen
    
  for(df in dfs) {    
    matching <- intersect(names(df), vars[!seen])
    for(var in matching) {
      value <- df[[var]]
      if (is.vector(value) && is.atomic(value)) {
        output[[var]] <- rep(NA, nrows)
      } else if (is.factor(value)) {
        output[[var]] <- factor(rep(NA, nrows))
        is_factor[var] <- TRUE
      } else if (is.list(value)) {
        output[[var]] <- vector("list", nrows)
      } else if (is.matrix(value)) {
        is_matrix[var] <- TRUE
      } else {
        output[[var]] <- rep(NA, nrows)
        class(output[[var]]) <- class(value)
      }
    }

    seen[matching] <- TRUE
    if (all(seen)) break  # Quit as soon as all done
  }

  # Set up factors
  for(var in vars[is_factor]) {
    all <- unique(lapply(dfs, function(df) levels(df[[var]])))
    levels(output[[var]]) <- unique(unlist(all))
  }

  # Set up matrices
  for(var in vars[is_matrix]) {
    width <- unique(unlist(lapply(dfs, function(df) ncol(df[[var]]))))
    if (length(width) > 1) 
      stop("Matrix variable ", var, " has inconsistent widths")
    
    vec <- rep(NA, nrows * width)
    output[[var]] <- array(vec, c(nrows, width))
  }
  
  output
}