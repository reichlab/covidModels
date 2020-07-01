#' Check if object is of class quantile_baseline
#'
#' @param object an object that may be a quantile_baseline object
#'
#' @return boolean; whether object is inherits quantile_baseline class
#'
#' @export
is.quantile_baseline <- function(object) {
  return(inherits(object, "quantile_baseline"))
}


#' Create a quantile_baseline object
#'
#' @param inc_diffs historical first differences in incidence
#'
#' @return quantile_baseline fit object
#'
#' @export
new_quantile_baseline <- function(inc_diffs) {
  quantile_baseline <- structure(
    c(inc_diffs, -inc_diffs),
    class = 'quantile_baseline'
  )
  
  return(quantile_baseline)
}


#' Fit a quantile baseline model to historical disease incidence
#' 
#' @param incidence numeric vector of disease incidence in past time points
#' 
#' @return quantile_baseline fit object
#' 
#' @export
fit_quantile_baseline <- function(incidence) {
  return(new_quantile_baseline(diff(incidence)))
}


#' Predict future disease incidence by resampling one-step-ahead forecasts
#' 
#' @param quantile_baseline a quantile_baseline fit object
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
predict.quantile_baseline <- function(
  quantile_baseline,
  inc_data,
  cum_data,
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
  sampled_inc_diffs <- quantile(quantile_baseline, probs = quantiles)
  sampled_inc <- last_inc + sampled_inc_diffs
  
  ## correct median
  sampled_inc <- sampled_inc - (median(sampled_inc) - last_inc)
  
  ## force non-negative
  sampled_inc <- pmax(sampled_inc, 0)
  
  ## obtain cumulative counts as last_cum + sampled incidence
  sampled_cum <- last_cum + sampled_inc
  
  ## save as a data frame
  results <- bind_rows(
    data.frame(
      target = '1 wk ahead inc death',
      quantile = quantiles,
      value = sampled_inc,
      stringsAsFactors = FALSE
    ),
    data.frame(
      target = '1 wk ahead cum death',
      quantile = quantiles,
      value = sampled_cum,
      stringsAsFactors = FALSE
    )
  )
  
  # loop over other horizons
  # set up with sampled differences from 0 -- Monte Carlo approximation to the
  # calculations performed exactly above.
  sampled_inc_diffs <- sample(quantile_baseline, size = num_samples, replace = TRUE)
  sampled_inc_raw <- last_inc + sampled_inc_diffs
  
  # force median difference = 0
  sampled_inc_corrected <- sampled_inc_raw - (median(sampled_inc_raw) - last_inc)
  
  # force non-negative incidence
  sampled_inc_corrected <- pmax(sampled_inc_corrected, 0)
  
  # add incidence to update cumulatice counts
  sampled_cum <- last_cum + sampled_inc_corrected
  
  for(h in (1 + seq_len(horizon - 1))) {
    sampled_inc_diffs <- sample(quantile_baseline, size = num_samples, replace = TRUE)
    sampled_inc_raw <- sampled_inc_raw + sampled_inc_diffs
    
    # force median difference = 0
    sampled_inc_corrected <- sampled_inc_raw - (median(sampled_inc_raw) - last_inc)
    
    # force non-negative incidence
    sampled_inc_corrected <- pmax(sampled_inc_corrected, 0)
    
    # add incidence to update cumulatice counts
    sampled_cum <- sampled_cum + sampled_inc_corrected
    
    # get data frame of results
    results <- bind_rows(
      results,
      data.frame(
        target = paste0(h, ' wk ahead inc death'),
        quantile = quantiles,
        value = quantile(sampled_inc_corrected, probs = quantiles),
        stringsAsFactors = FALSE
      ),
      data.frame(
        target = paste0(h, ' wk ahead cum death'),
        quantile = quantiles,
        value = quantile(sampled_cum, probs = quantiles),
        stringsAsFactors = FALSE
      )
    )
  }
  
  return(results)
}
