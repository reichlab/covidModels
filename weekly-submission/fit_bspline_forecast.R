library(tidyverse)
library(rstan)
library(covidData)
library(covidModels)

data <- covidData::load_jhu_data(
#  issue_date = '2020-07-05',
  spatial_resolution = 'national',
  temporal_resolution = 'daily',
  measure = 'deaths')

data <- covidData::load_jhu_data(
  #  issue_date = '2020-07-05',
  spatial_resolution = 'state',
  temporal_resolution = 'daily',
  measure = 'deaths') %>%
  dplyr::filter(location == '01')

data$inc[data$inc < 0] <- 0L
first_nonzero_ind <- min(which(data$inc != 0))
data <- data[(first_nonzero_ind - 1):nrow(data), ]

forecast_horizon <- 28L
nsim <- 1000L
knot_frequency <- 7L

all_knots <- seq(
  from = nrow(data) %% knot_frequency,
  to = nrow(data) + forecast_horizon,
  by = knot_frequency)
boundary_knots <- all_knots[c(1, length(all_knots))]
interior_knots <- all_knots[-c(1, length(all_knots))]

forecast_horizon <- 28L
nsim <- 1000L
spline_order <- 3L

model_object_ar_daily <- rstan::stan_model(
  file = "R-package/inst/stan_models/ar_bspline_forecast_daily.stan")

map_estimates_ar_daily <- optimizing(
  object = model_object_ar_daily,
  data = list(
    T = nrow(data),
    y = as.integer(data$inc),
    spline_order = spline_order,
    n_interior_knots = length(interior_knots),
    interior_knots = interior_knots,
    boundary_knots = boundary_knots,
    forecast_horizon = forecast_horizon,
    nsim = nsim
  ),
  verbose = TRUE
)

rstan::expose_stan_functions("R-package/inst/stan_models/ar_bspline_forecast_daily.stan")

basis <- bspline_basis(
  n_x = nrow(data) + forecast_horizon,
  x = seq_len(nrow(data) + forecast_horizon),
  order = spline_order,
  n_interior_knots = length(interior_knots),
  boundary_knots = boundary_knots,
  interior_knots = interior_knots,
  natural = 1L
)

raw_beta <- map_estimates_ar_daily$par[
    paste0('raw_beta[', seq_len(length(all_knots) + spline_order), ']')] %>%
  unname()
raw_gamma <- map_estimates_ar_daily$par[
    paste0('raw_gamma[', seq_len(length(all_knots) + spline_order), ']')] %>%
  unname()

regenerate_inds <- seq(
  from = length(raw_beta) - 4,
  to = length(raw_beta) - 1
)

new_raw_beta <- raw_beta

n_beta_sim <- 10000
n_sim_per_beta <- 1
y_pred <- matrix(NA, nrow = n_beta_sim * n_sim_per_beta, ncol = nrow(data) + forecast_horizon)

pred_row_ind <- 1L
for(beta_sim_ind in seq_len(n_beta_sim)) {
  new_raw_beta[regenerate_inds] <- rt(
    length(regenerate_inds),
#    df = 2)
    df = map_estimates_ar_daily$par['beta_df'])
  new_raw_beta[length(new_raw_beta)] <- new_raw_beta[length(new_raw_beta) - 1]
  
  mu <- compute_mu(
    T = nrow(data),
    forecast_horizon = forecast_horizon,
    spline_order = spline_order,
    n_basis = ncol(basis),
    basis = basis,
    ar_beta = unname(map_estimates_ar_daily$par['ar_beta']),
    beta_sd = unname(map_estimates_ar_daily$par['beta_sd']),
    raw_beta = new_raw_beta,
    gamma_sd = unname(map_estimates_ar_daily$par['gamma_sd']),
    raw_gamma = raw_gamma
  )
  
  for(i in seq_len(n_sim_per_beta)) {
    y_pred[pred_row_ind, ] <- rnb_rng(mu, mu * unname(map_estimates_ar_daily$par['phi']))
    # for(t in seq_len(nrow(data) + forecast_horizon)) {
    #   y_pred[pred_row_ind, t] <- rnb_rng(mu[t], mu[t] * unname(map_estimates_ar_daily$par['phi']))
    # }
    pred_row_ind <- pred_row_ind + 1L
  }
}

to_plot_ar_daily_means <- data.frame(
  t = seq_len(nrow(data)),
  y = data$inc#,
#  y_hat = unname(map_estimates_ar_daily$par[
#    grepl('y_mean', names(map_estimates_ar_daily$par))])[seq_len(nrow(data))],
#  y_hat_daily = unname(map_estimates_ar_daily$par[
#    grepl('y_mean_with_daily', names(map_estimates_ar_daily$par))])[seq_len(nrow(data))]
)

quantile_levels <- c(0.025, 0.1, 0.25, 0.5, 0.75, 0.9, 0.975)
to_plot_ar_pred_quantiles <- purrr::map_dfr(
  seq_len(nrow(data) + forecast_horizon),
  function(t) {
#    samples <- unname(map_estimates_ar_daily$par[
#      paste0('y_pred[', 1:1000, ',', t, ']')])
    samples <- y_pred[, t]
    data.frame(
      t = t,
      quantile = quantile_levels,
      value = quantile(samples, probs = quantile_levels),
      stringsAsFactors = FALSE
    )
  }
)

plottable_predictions_ar <- to_plot_ar_pred_quantiles %>%
  dplyr::mutate(
    endpoint_type = ifelse(quantile < 0.5, 'lower', 'upper'),
    alpha = ifelse(
      endpoint_type == 'lower',
      format(2*quantile, digits=3, nsmall=3),
      format(2*(1-quantile), digits=3, nsmall=3))
  ) %>%
  dplyr::filter(alpha != "1.000") %>%
  dplyr::select(-quantile) %>%
  tidyr::pivot_wider(names_from='endpoint_type', values_from='value')

ggplot(data = to_plot_ar_daily_means) +
  geom_ribbon(
    data = plottable_predictions_ar,
    mapping = aes(x = t,
                  ymin=lower, ymax=upper,
                  fill=alpha)) +
  geom_line(mapping = aes(x = t, y = y)) +
  scale_fill_viridis_d(begin = 0.5, end = 0.8) +
  #  geom_line(mapping = aes(x = t, y = y_hat), color = 'blue') +
  #  geom_line(mapping = aes(x = t, y = y_hat_daily), color = 'cornflowerblue', linetype = 2) +
  theme_bw()

