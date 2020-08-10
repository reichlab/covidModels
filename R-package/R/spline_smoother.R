#' Check if object is of class spline_smoother
#'
#' @param object an object that may be a spline_smoother object
#'
#' @return boolean; whether object is inherits spline_smoother class
#'
#' @export
is.spline_smoother <- function(object) {
  return(inherits(object, "spline_smoother"))
}


#' Create a spline_smoother object
#'
#' @param param_estimates model parameter estimates
#' @param temporal_resolution character vector specifying temporal resolution
#' to include: 'weekly' or 'daily'.  If 'daily', a day-of-week offset is included.
#' @param train_incidence integer vector of training set incidence
#' @param spline_order order of the spline for the mean
#' @param interior_knots locations of interior knots
#' @param bounary_knots locations of boundary knots
#'
#' @return spline_smoother fit object
#'
#' @export
new_spline_smoother <- function(
    param_estimates,
    temporal_resolution,
    train_incidence,
    spline_order,
    interior_knots,
    boundary_knots) {
  spline_smoother <- structure(
    param_estimates,
    temporal_resolution = temporal_resolution,
    train_incidence=train_incidence,
    spline_order=spline_order,
    interior_knots=interior_knots,
    boundary_knots=boundary_knots,
    class = 'spline_smoother'
  )
  
  return(spline_smoother)
}


#' Fit a quantile baseline model to historical disease incidence
#'
#' @param incidence numeric vector of disease incidence in past time points
#' @param temporal_resolution character vector specifying temporal resolution
#' to include: 'weekly' or 'daily'.  If 'daily', a day-of-week offset is included.
#' @param verbose logical: if TRUE, print output from estimation in Stan
#' @param ... other arguments are ignored
#'
#' @return spline_smoother fit object
#'
#' @export
fit_spline_smoother <- function(
    incidence,
    temporal_resolution = 'weekly',
    verbose = TRUE,
    ...) {
  temporal_resolution <- match.arg(
    temporal_resolution,
    choices = c('daily', 'weekly')
  )
  if(temporal_resolution == 'weekly') {
    stan_path <- file.path(
      find.package('covidModels'),
      'stan_models',
      'ar_bspline_forecast_weekly.stan'
    )
    ts_frequency <- 1L
    
    all_knots <- seq(
      from = 1,
      to = length(incidence) + 8 * ts_frequency,
      by = 3L)
  } else {
    stan_path <- file.path(
      find.package('covidModels'),
      'stan_models',
      'ar_bspline_forecast_daily.stan'
    )
    ts_frequency <- 7L
    
    all_knots <- seq(
      from = length(incidence) %% ts_frequency,
      to = length(incidence) + 4 * ts_frequency,
      by = ts_frequency)
  }
  
  boundary_knots <- all_knots[c(1, length(all_knots))]
  interior_knots <- all_knots[-c(1, length(all_knots))]
  spline_order <- 3L
  
  if(any(incidence != 0)) {
    first_nonzero_ind <- min(which(incidence != 0))
    incidence <- incidence[(first_nonzero_ind - 1):length(incidence)]
  }
  
  model_object <- rstan::stan_model(stan_path)
  
  map_estimates <- rstan::optimizing(
    object = model_object,
    data = list(
      T = length(incidence),
      y = as.integer(incidence),
      spline_order = spline_order,
      n_interior_knots = length(interior_knots),
      interior_knots = interior_knots,
      boundary_knots = boundary_knots,
      forecast_horizon = 0L,
      nsim = 0L
    ),
#    init = list(
#      raw_beta = init_raw_beta,
#      beta_sd = init_beta_sd,
#      ar_beta = 1.0
#    ),
    verbose = verbose
  )
  
  return(new_spline_smoother(
    param_estimates=map_estimates,
    temporal_resolution=temporal_resolution,
    train_incidence=incidence,
    spline_order=spline_order,
    interior_knots=interior_knots,
    boundary_knots=boundary_knots))
}


#' Predict future disease incidence starting from the end of the training data.
#'
#' @param spline_smoother a spline_smoother fit object
#' @param temporal_resolution character vector specifying temporal resolution
#' to predict at: 'weekly' or 'daily'. The 'daily' option is only valid if the
#' model was fit at a daily resolution.
#' @param post_pred logical; if TRUE, samples from the posterior predictive are
#' returned for time points with observations in the training set
#' @param horizon number of time steps forward to predict
#' @param nsim number of samples to use for generating predictions at
#' horizons greater than 1
#' @param ... other arguments are ignored
#'
#' @return matrix of simulated incidence with nsim rows and horizon columns
#'
#' @export
predict.spline_smoother <- function(
  spline_smoother,
  newdata,
  temporal_resolution,
  post_pred,
  horizon,
  nsim) {
  
  train_temporal_resolution <- attr(spline_smoother, 'temporal_resolution')
  train_incidence <- attr(spline_smoother, 'train_incidence')
  spline_order <- attr(spline_smoother, 'spline_order')
  boundary_knots <- attr(spline_smoother, 'boundary_knots')
  interior_knots <- attr(spline_smoother, 'interior_knots')
  
  compute_mu_call_args <- list(
    spline_order = spline_order,
    ar_beta = unname(spline_smoother$par['ar_beta']),
    beta_sd = unname(spline_smoother$par['beta_sd'])
  )
  
  if(train_temporal_resolution == 'daily') {
    temporal_resolution <- match.arg(
      temporal_resolution,
      choices = c('daily', 'weekly'))
    stan_path <- file.path(
      find.package('covidModels'),
      'stan_models',
      'ar_bspline_forecast_daily.stan'
    )
    ts_frequency <- 7L
    if(temporal_resolution == 'weekly') {
      horizon <- horizon * ts_frequency
    }
    compute_mu_call_args$gamma_sd = unname(spline_smoother$par['gamma_sd'])
  } else {
    temporal_resolution <- match.arg(
      temporal_resolution,
      choices = 'weekly')
    stan_path <- file.path(
      find.package('covidModels'),
      'stan_models',
      'ar_bspline_forecast_weekly.stan'
    )
    ts_frequency <- 1L
  }
  
  # horizon for stan is 0 because we provide all the data for points at which
  # to predict
  compute_mu_call_args$forecast_horizon <- 0L
  
  # storage space for result
  if(post_pred) {
    init_pred_t <- 1L
    num_pred <- length(train_incidence) + horizon
  } else {
    init_pred_t <- length(train_incidence) + 1L
    num_pred <- horizon
  }
  compute_mu_call_args$T <- num_pred

  result <- matrix(NA_integer_, nrow = nsim, ncol = num_pred)
  
  rstan::expose_stan_functions(stan_path)
  
  basis <- bspline_basis(
    n_x = num_pred,
    x = seq(from = init_pred_t, length = num_pred),
    order = spline_order,
    n_interior_knots = length(interior_knots),
    boundary_knots = boundary_knots,
    interior_knots = interior_knots,
    natural = 1L
  )
  compute_mu_call_args$n_basis <- ncol(basis)
  compute_mu_call_args$basis <- basis
  
  compute_mu_call_args$raw_beta <- spline_smoother$par[
    paste0('raw_beta[', seq_len(length(interior_knots) + 2 + spline_order), ']')] %>%
    unname()
  if(train_temporal_resolution == 'daily') {
    compute_mu_call_args$raw_gamma <- spline_smoother$par[
      paste0('raw_gamma[', seq_len(7), ']')] %>%
      unname()
  }
  
  regenerate_inds <- seq(
    from = length(compute_mu_call_args$raw_beta) - 4,
    to = length(compute_mu_call_args$raw_beta) - 1
  )
  
  for(sim_ind in seq_len(nsim)) {
    compute_mu_call_args$raw_beta[regenerate_inds] <- rt(
      length(regenerate_inds),
      df = spline_smoother$par['beta_df'])
    compute_mu_call_args$raw_beta[length(compute_mu_call_args$raw_beta)] <-
      compute_mu_call_args$raw_beta[length(compute_mu_call_args$raw_beta) - 1]
    
    mu <- do.call(compute_mu, args = compute_mu_call_args)

    result[sim_ind, ] <- rnb_rng(
      mu, mu * unname(spline_smoother$par['phi'])
    )
  }
  
  return(result)
}
