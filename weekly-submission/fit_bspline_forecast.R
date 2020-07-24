library(tidyverse)
library(rstan)
library(covidData)
library(covidModels)

data <- covidData::load_jhu_data(
#  issue_date = '2020-07-05',
  spatial_resolution = 'national',
  temporal_resolution = 'daily',
  measure = 'deaths')

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

# model_object <- rstan::stan_model(
#   file = "R-package/inst/stan_models/bspline_forecast.stan")
# 
# map_estimates <- optimizing(
#   object = model_object,
#   data = list(
#     T = nrow(data),
#     y = as.integer(data$inc),
#     n_interior_knots = length(interior_knots),
#     interior_knots = interior_knots,
#     boundary_knots = boundary_knots,
#     forecast_horizon = 4L,
#     nsim = 1000
#   ),
#   verbose = TRUE
# )
# 
# to_plot <- data.frame(
#   t = seq_len(nrow(data)),
#   y = data$inc,
#   y_hat = unname(map_estimates$par[grepl('y_mean', names(map_estimates$par))])[seq_len(nrow(data))]
# )
# 
# ggplot(data = to_plot) +
#   geom_line(mapping = aes(x = t, y = y)) +
#   geom_line(mapping = aes(x = t, y = y_hat), color = 'blue') +
#   theme_bw()

rstan::expose_stan_functions("R-package/inst/stan_models/ar_bspline_forecast_daily.stan")

bbasis <- bspline_basis(
  n_x = nrow(data) + forecast_horizon,
  x = seq_len(nrow(data) + forecast_horizon),
  order = 4,
  n_interior_knots = length(interior_knots),
  boundary_knots = boundary_knots,
  interior_knots = interior_knots,
  natural = 1L
)

bbasis_to_plot <- purrr::map_dfr(
  seq_len(ncol(bbasis)),
  function(j) {
    data.frame(
      t = seq_len(nrow(data) + forecast_horizon),
      b = bbasis[, j],
      j = j
    )
  }
)

ggplot(
  data = bbasis_to_plot,
  mapping = aes(x = t, y = b, color = factor(j))) +
  geom_line() +
  geom_vline(xintercept = nrow(data))  +
  theme_bw()

which(all_knots == nrow(data)) + 2


model_object_daily <- rstan::stan_model(
  file = "R-package/inst/stan_models/bspline_forecast_daily.stan")

map_estimates_daily <- optimizing(
  object = model_object_daily,
  data = list(
    T = nrow(data),
    y = as.integer(data$inc),
    spline_order = 3L,
    n_interior_knots = length(interior_knots),
    interior_knots = interior_knots,
    boundary_knots = boundary_knots,
    forecast_horizon = forecast_horizon,
    nsim = nsim
  ),
  verbose = TRUE
)

rstan::expose_stan_functions("R-package/inst/stan_models/ar_bspline_forecast_daily.stan")

bbasis <- bspline_basis(
  n_x = nrow(data) + forecast_horizon,
  x = seq_len(nrow(data) + forecast_horizon),
  order = 4,
  n_interior_knots = length(interior_knots),
  boundary_knots = boundary_knots,
  interior_knots = interior_knots,
  natural = 1L
)



to_plot_daily_means <- data.frame(
  t = seq_len(nrow(data)),
  y = data$inc,
  y_hat = unname(map_estimates_daily$par[
    grepl('y_mean', names(map_estimates_daily$par))])[seq_len(nrow(data))],
  y_hat_daily = unname(map_estimates_daily$par[
    grepl('y_mean_with_daily', names(map_estimates_daily$par))])[seq_len(nrow(data))]
)


all_names <- names(map_estimates_daily$par)
inds <- names(map_estimates_daily$par) %>%
  regexpr(pattern = '[', fixed = TRUE)
all_names <- all_names[inds > 0]
inds <- inds[inds > 0]
unique(substr(all_names, 1, inds))
all_names[substr(all_names, 1, inds) == 'y_pred[']

quantile_levels <- c(0.025, 0.1, 0.25, 0.5, 0.75, 0.9, 0.975)
to_plot_pred_quantiles <- purrr::map_dfr(
  seq_len(nrow(data) + forecast_horizon),
  function(t) {
    samples <- unname(map_estimates_daily$par[
      paste0('y_pred[', 1:1000, ',', t, ']')])
    data.frame(
      t = t,
      quantile = quantile_levels,
      value = quantile(samples, probs = quantile_levels),
      stringsAsFactors = FALSE
    )
  }
)

plottable_predictions <- to_plot_pred_quantiles %>%
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

ggplot(data = to_plot_daily_means) +
  geom_ribbon(
    data = plottable_predictions,
    mapping = aes(x = t,
                  ymin=lower, ymax=upper,
                  fill=alpha)) +
  geom_line(mapping = aes(x = t, y = y)) +
  scale_fill_viridis_d(begin = 0.5, end = 0.8) +
#  geom_line(mapping = aes(x = t, y = y_hat), color = 'blue') +
#  geom_line(mapping = aes(x = t, y = y_hat_daily), color = 'cornflowerblue', linetype = 2) +
  theme_bw()





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

bbasis <- bspline_basis(
  n_x = nrow(data) + forecast_horizon,
  x = seq_len(nrow(data) + forecast_horizon),
  order = 4,
  n_interior_knots = length(interior_knots),
  boundary_knots = boundary_knots,
  interior_knots = interior_knots,
  natural = 1L
)

raw_beta <- map_estimates_ar_daily$par[
    paste0('raw_beta[', seq_len(length(all_knots) + spline_order), ']')] %>%
  unname()

regenerate_inds <- seq(
  from = length(raw_beta) - 5,
  to = length(raw_beta) - 1
)

new_raw_beta <- raw_beta
new_raw_beta[regenerate_inds] <- rnorm(length(regenerate_inds))

mu <- compute_mu(
  T = nrow(data),
  forecast_horizon = forecast_horizon,
  spline_order = spline_order,
  n_basis = ncol(basis),
  basis = basis,
  ar_beta = ,
  beta_sd,
  new_raw_beta,
  gamma_sd,
  raw_gamma
)

for(i in seq_len(10)) {
  for(t in seq_len(T + forecast_horizon)) {
    rnb(mu[t], phi)
  }
}


to_plot_ar_daily_means <- data.frame(
  t = seq_len(nrow(data)),
  y = data$inc,
  y_hat = unname(map_estimates_ar_daily$par[
    grepl('y_mean', names(map_estimates_ar_daily$par))])[seq_len(nrow(data))],
  y_hat_daily = unname(map_estimates_ar_daily$par[
    grepl('y_mean_with_daily', names(map_estimates_ar_daily$par))])[seq_len(nrow(data))]
)


all_names <- names(map_estimates_ar_daily$par)
inds <- names(map_estimates_ar_daily$par) %>%
  regexpr(pattern = '[', fixed = TRUE)
all_names <- all_names[inds > 0]
inds <- inds[inds > 0]
unique(substr(all_names, 1, inds))
all_names[substr(all_names, 1, inds) == 'raw_beta[']

all_names <- names(map_estimates_ar_daily$par)
inds <- names(map_estimates_ar_daily$par) %>%
  regexpr(pattern = '[', fixed = TRUE)
all_names <- all_names[inds ==-1]



quantile_levels <- c(0.025, 0.1, 0.25, 0.5, 0.75, 0.9, 0.975)
to_plot_ar_pred_quantiles <- purrr::map_dfr(
  seq_len(nrow(data) + forecast_horizon),
  function(t) {
    samples <- unname(map_estimates_ar_daily$par[
      paste0('y_pred[', 1:1000, ',', t, ']')])
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

