## functions for estimating simple ts models

#' Estimate model
#'
#' @param y a univariate time series or numeric vector.
#' @param ts_frequency frequency of time series.  Must be provided if y is not
#'   of class "ts".  See the help for stats::ts for more.
#' @param model string specifying model to fit: one of 'quantile_baseline' or
#'   'local_trend'
#' @param transformation character specifying transformation type:
#'   "box-cox", "log", or "none".  See details for more.
#' @param bc_gamma numeric offset used in Box-Cox transformation; gamma is
#'   added to all observations before transforming.  Default value of 0.5
#'   allows us to use the Box-Cox and log transforms (which require positive
#'   inputs) in case of observations of 0, and also ensures that the
#'   de-transformed values will always be at least -0.5, so that they round up
#'   to non-negative values.
#' @param d integer order of first differencing; default is 0
#' @param D integer order of seasonal differencing; default is 0
#' @param ... arguments passed on to model-specific fit method
#'
#' @return a simple_ts model fit
#'
#' @details This function is a wrapper around model-specific fit methods,
#'   providing some preliminary transformations of the data.
#'   Formal and informal experimentation has shown these preliminary
#'   transformations to be helpful with a few infectious disease time series
#'   data sets.  Note that if any transformation was specified or the
#'   seasonal_difference argument was TRUE in the call to this function, only
#'   prediction/forecast utilities provided by this package can be used!
#'
#' @export
fit_simple_ts <- function(
  y,
  ts_frequency,
  model = 'quantile_baseline',
  transformation = 'box-cox',
  bc_gamma = 0.5,
  sarimaTD_d = 0,
  sarimaTD_D = 1,
  d = NA,
  D = NA,
  ...) {
  # Validate arguments
  if(!(is.numeric(y) || is.ts(y))) {
    stop("The argument y must be a numeric vector or object of class 'ts'.")
  }

  if(!is.ts(y) && missing(ts_frequency)) {
    stop("If y is not an object of class 'ts', the ts_frequency argument must be supplied.")
  }
  
  if(is.ts(y)) {
    ts_frequency <- frequency(y)
  }
  
  model <- match.arg(model, c('quantile_baseline', 'local_trend'))
  transformation <- match.arg(transformation, c('none', 'log', 'box-cox'))
  
  # Initial transformation, if necessary
  if(identical(transformation, "box-cox")) {
    est_bc_params <- car::powerTransform(y + bc_gamma, family = "bcPower")
    est_bc_params <- list(
      lambda = est_bc_params$lambda,
      gamma = bc_gamma)
  }
  transformed_y <- do_initial_transform(
    y = y,
    transformation = transformation,
    bc_params = est_bc_params)

  # Initial differencing, if necessary
  differenced_y <- do_difference(transformed_y, d = d, D = D,
    frequency = ts_frequency)
  
  # Get fit
  if(model == 'quantile_baseline') {
    simple_ts_fit <- fit_quantile_baseline(incidence = y, ...)
  } else if(model == 'local_trend') {
    simple_ts_fit <- fit_local_trend(incidence = y, ...)
  }
  
  # Save information needed for prediction
  simple_ts_fit$sarimaTD_call <- match.call()
  for(param_name in c("y", "ts_frequency", "transformation", "d", "D")) {
    simple_ts_fit[[paste0("simple_ts_arg_", param_name)]] <- get(param_name)
  }
  if(identical(transformation, "box-cox")) {
    simple_ts_fit$simple_ts_est_bc_params <- est_bc_params
  }
  
  class(simple_ts_fit) <- c("simple_ts", class(simple_ts_fit))
  
  return(simple_ts_fit)
}
