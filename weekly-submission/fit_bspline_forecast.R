library(tidyverse)
library(rstan)
library(covidData)
library(covidModels)

data <- covidData::load_jhu_data(
  issue_date = '2020-05-10',
  spatial_resolution = 'national',
  temporal_resolution = 'daily',
  measure = 'deaths')

first_nonzero_ind <- min(which(data$inc != 0))
data <- data[(first_nonzero_ind - 1):nrow(data), ]

all_knots <- seq(from = 3, to = nrow(data), by = 10)
boundary_knots <- all_knots[c(1, length(all_knots))]
interior_knots <- all_knots[-c(1, length(all_knots))]

model_object <- rstan::stan_model(
  file = "R-package/inst/stan_models/bspline_forecast.stan")

map_estimates <- optimizing(
  object = model_object,
  data = list(
    T = nrow(data),
    y = as.integer(data$inc),
    n_interior_knots = length(interior_knots),
    interior_knots = interior_knots,
    boundary_knots = boundary_knots,
    forecast_horizon = 4L,
    nsim = 1000
  ),
  verbose = TRUE
)

to_plot <- data.frame(
  t = seq_len(nrow(data)),
  y = data$inc,
  y_hat = unname(map_estimates$par[grepl('y_mean', names(map_estimates$par))])[seq_len(nrow(data))]
)

ggplot(data = to_plot) +
  geom_line(mapping = aes(x = t, y = y)) +
  geom_line(mapping = aes(x = t, y = y_hat), color = 'blue') +
  theme_bw()




model_object_daily <- rstan::stan_model(
  file = "R-package/inst/stan_models/bspline_forecast_daily.stan")

map_estimates_daily <- optimizing(
  object = model_object_daily,
  data = list(
    T = nrow(data),
    y = as.integer(data$inc),
    n_interior_knots = length(interior_knots),
    interior_knots = interior_knots,
    boundary_knots = boundary_knots,
    forecast_horizon = 4L,
    nsim = 1000
  ),
  verbose = TRUE
)


to_plot_daily <- data.frame(
  t = seq_len(nrow(data)),
  y = data$inc,
  y_hat = unname(map_estimates_daily$par[grepl('y_mean', names(map_estimates_daily$par))])[seq_len(nrow(data))]
)

ggplot(data = to_plot_daily) +
  geom_line(mapping = aes(x = t, y = y)) +
  geom_line(mapping = aes(x = t, y = y_hat), color = 'blue') +
  theme_bw()

