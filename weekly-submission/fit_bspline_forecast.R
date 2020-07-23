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

all_knots <- seq(from = 3, to = nrow(data) + 14, by = 14)
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


forecast_horizon <- 28L
nsim <- 1000L

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

