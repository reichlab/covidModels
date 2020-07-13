#' Check if object is of class local_trend
#'
#' @param object an object that may be a local_trend object
#'
#' @return boolean; whether object is inherits local_trend class
#'
#' @export
is.local_trend <- function(object) {
  return(inherits(object, "local_trend"))
}


#' Create a local_trend object
#'
#' @param inc_diffs historical first differences in incidence
#'
#' @return local_trend fit object
#'
#' @export
new_local_trend <- function(inc_diffs) {
  local_trend <- structure(
    c(inc_diffs, -inc_diffs),
    class = 'local_trend'
  )
  
  return(local_trend)
}


#' Fit a quantile baseline model to historical disease incidence
#'
#' @param incidence numeric vector of disease incidence in past time points
#' @param window_size integer optional number of past time points to use for
#'   finding first differences.  If not provided, all past first differences
#'   will be used.
#' @param ... other arguments are ignored
#'
#' @return local_trend fit object
#'
#' @export
fit_local_trend <- function(
    incidence,
    window_size = length(incidence) - 1,
    ...) {
  return(new_local_trend(diff(incidence)[seq_len(window_size)]))
}


#' Predict future disease incidence by resampling one-step-ahead forecasts
#'
#' @param local_trend a local_trend fit object
#' @param inc_data numeric vector of length at least one with incident counts
#' @param cum_data numeric vector of length at least one with cumulative counts
#' @param quantiles quantile levels for which  to generate predictions
#' @param horizon number of time steps forward to predict
#' @param num_samples number of samples to use for generating predictions at
#' horizons greater than 1
#'
#' @return data frame with columns target, quantile, and value with forecasts
#' of incident and cumulative deaths
#'
#' @export
predict.local_trend <- function(
  local_trend,
  inc_data,
  cum_data=NULL,
  quantiles,
  horizon,
  num_samples) {
  
  last_inc <- tail(inc_data, 1)
  last_cum <- tail(cum_data, 1)
  
  # Case for horizon 1 is different because sampling is not necessary; we can
  # extract exact quantiles
  
  ## sample incidence, then correct it:
  ## - enforce median difference is 0
  ## - enforce incidence is non-negative
  sampled_inc_diffs <- quantile(
    local_trend,
    probs = seq(from = 0, to = 1.0, length = num_samples))
  sampled_inc_raw <- last_inc + sampled_inc_diffs
  
  # force non-negative incidence
  sampled_inc_corrected <- pmax(sampled_inc_raw, 0)
  
  ## obtain cumulative counts as last_cum + sampled incidence
  sampled_cum <- last_cum + sampled_inc_corrected
  
  ## save as a data frame
  results <- bind_rows(
    data.frame(
      horizon = 1,
      type = 'inc',
      quantile = quantiles,
      value = quantile(sampled_inc_corrected, probs = quantiles),
      stringsAsFactors = FALSE
    ),
    data.frame(
      horizon = 1,
      type = 'cum',
      quantile = quantiles,
      value = quantile(sampled_cum, probs = quantiles),
      stringsAsFactors = FALSE
    )
  )
  
  # add incidence to update cumulative counts
  sampled_cum <- last_cum + sampled_inc_corrected
  
  for(h in (1 + seq_len(horizon - 1))) {
    sampled_inc_diffs <- sample(sampled_inc_diffs, size = num_samples, replace = FALSE)
    sampled_inc_raw <- sampled_inc_raw + sampled_inc_diffs
    
    # force median difference = 0
    sampled_inc_corrected <- sampled_inc_raw - (median(sampled_inc_raw) - last_inc)
    
    # force non-negative incidence
    sampled_inc_corrected <- pmax(sampled_inc_corrected, 0)
    
    # add incidence to update cumulative counts
    sampled_cum <- sampled_cum + sampled_inc_corrected
    
    # get data frame of results
    results <- bind_rows(
      results,
      data.frame(
        horizon = h,
        type = 'inc',
        quantile = quantiles,
        value = quantile(sampled_inc_corrected, probs = quantiles),
        stringsAsFactors = FALSE
      ),
      data.frame(
        horizon = h,
        type = 'cum',
        quantile = quantiles,
        value = quantile(sampled_cum, probs = quantiles),
        stringsAsFactors = FALSE
      )
    )
  }
  
  return(results)
}
