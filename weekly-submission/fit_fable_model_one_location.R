library(tidyverse)
library(covidData)
library(tsibble)
library(fable)

library(here)
setwd(here())

nsim <- 5000

args <- commandArgs(trailingOnly = TRUE)
#args <- c('2020-05-30', 'ETS', 'box_cox', 'weekly')
#args <- c('2020-10-10', '56045', 'ETS', 'none', 'weekly')
forecast_week_end_date <- lubridate::ymd(args[1])
location <- args[2]
model <- args[3]
transform_fun <- args[4]
temporal_resolution <- args[5]

full_model_case <- paste0(
  "model_", model,
  "-transform_", transform_fun,
  "-temporal_resolution_", temporal_resolution
)

if (temporal_resolution == "weekly") {
  ts_frequency <- 1L
} else {
  ts_frequency <- 7L
}

model_dir <- paste0('/project/uma_nicholas_reich/covidModels/forecasts/', full_model_case, '/')
if(!dir.exists(model_dir)) {
  dir.create(model_dir)
}
results_path <- paste0(model_dir,
  forecast_week_end_date + 2,
  '-', full_model_case, '-', location, '.csv')

if(nchar(location) == 5) {
  measures <- c('cases')
  spatial_resolutions <- 'county'
} else {
  measures <- c('deaths', 'cases')
  spatial_resolutions <- c('state', 'national')
}

tictic <- Sys.time()
if(!file.exists(results_path)) {
  results <- NULL
  for(measure in measures) {
    print(measure)
    if(measure == 'deaths') {
      data <- covidData::load_jhu_data(
        issue_date = as.character(forecast_week_end_date + 1),
        spatial_resolution = spatial_resolutions,
        temporal_resolution = 'weekly',
        measure = measure)
      horizon <- 8L
      types <- c('inc', 'cum')
      required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
    } else if(measure == 'cases') {
      data <- covidData::load_jhu_data(
        issue_date = as.character(forecast_week_end_date + 1),
        spatial_resolution = spatial_resolutions,
        temporal_resolution = 'weekly',
        measure = measure)
      horizon <- 8L
      types <- 'inc'
      required_quantiles <- c(0.025, 0.100, 0.250, 0.500, 0.750, 0.900, 0.975)
    }
    
        location_data <- data %>%
          dplyr::filter(location == UQ(location))
        location_data$inc[location_data$inc < 0] <- 0.0
  
        if(all(location_data$cum == 0)) {
          #start_date <- lubridate::ymd(min(location_data$date)) + 7
          first_inc <- data %>%
	    group_by(location) %>%
            filter(cum > 0) %>%
            filter(cum == min(cum)) %>%
            pull(inc)
          first_inc <- c(first_inc, rep(0, 3 * length(first_inc)))
          null_baseline <- covidModels::new_quantile_baseline(inc_diffs = first_inc, symmetrize = FALSE)
          forecast_inc_trajectories <- predict(
            null_baseline,
            inc_data = 0,
            quantiles = seq(from = 0.001, to = 0.999, by = 0.001),
            horizon = horizon,
            num_samples = 1000) %>%
            dplyr::filter(type == "inc") %>%
            tidyr::pivot_wider(names_from = "horizon", values_from = "value") %>%
            dplyr::select(-type, -quantile) %>%
            as.matrix()
        } else {
          start_date <- max(
            lubridate::ymd(min(location_data$date)) + 7,
            lubridate::ymd(min(location_data$date[location_data$cum > 0])) - 1*7)
          
          location_data <- location_data %>%
            dplyr::filter(date >= as.character(start_date)) %>%
            dplyr::mutate(offset_inc = inc + 0.49)
          
          if(nrow(location_data) < 4 && transform_fun == "box_cox") {
            # fit a random walk with drift
            bc_lambda <- car::powerTransform(
              location_data$inc + 0.49,
              family = "bcPower")$lambda
            if(abs(bc_lambda) < 1e-2) {
              bc_lambda <- 0.0
            }

            # if only 2 data points, add a third in
            if (nrow(location_data) == 2) {
              location_data <- rbind(
                location_data[1, ],
                location_data
              )
              location_data$date[1] <- location_data$date[1] - 7
            }

            temp <- location_data %>%
              tsibble() %>%
              model(
                fit = RW(box_cox(inc + 0.49, lambda = UQ(bc_lambda)) ~ drift(FALSE))
              ) %>%
              forecast(h = paste0(horizon, " weeks"), simulate = TRUE, times = nsim)
          } else if (nrow(location_data) < 4 && transform_fun == "log") {
            # if only 2 data points, add a third in
            if (nrow(location_data) == 2) {
              location_data <- rbind(
                location_data[1, ],
                location_data
              )
              location_data$date[1] <- location_data$date[1] - 7
            }

            temp <- location_data %>%
              tsibble() %>%
              model(
                fit = RW(log(inc + 0.49) ~ drift())
              ) %>%
              forecast(h = paste0(horizon, " weeks"), simulate = TRUE, times = nsim)
          } else if (nrow(location_data) < 4 && transform_fun == "none") {
            # if only 2 data points, add a third in
            if (nrow(location_data) == 2) {
              location_data <- rbind(
                location_data[1, ],
                location_data
              )
              location_data$date[1] <- location_data$date[1] - 7
            }

            temp <- location_data %>%
              tsibble() %>%
              model(
                fit = RW(inc ~ drift())
              ) %>%
              forecast(h = paste0(horizon, " weeks"), simulate = TRUE, times = nsim)
          } else if (model == "ETS" && transform_fun == "box_cox") {
            bc_lambda <- car::powerTransform(
              location_data$inc + 0.49,
              family = "bcPower")$lambda
            if(abs(bc_lambda) < 1e-2) {
              bc_lambda <- 0.0
            }

            temp <- location_data %>%
              tsibble() %>%
              model(
                fit = ETS(box_cox(inc + 0.49, lambda = UQ(bc_lambda)))
              ) %>%
              forecast(h = paste0(horizon, " weeks"), simulate = TRUE, times = nsim)
          } else if (model == "ETS" && transform_fun == "log") {
            temp <- location_data %>%
              tsibble() %>%
              model(
                fit = ETS(log(inc + 0.49))
              ) %>%
              forecast(h = paste0(horizon, " weeks"), simulate = TRUE, times = nsim)
          } else if (model == "ETS" && transform_fun == "none") {
            temp <- location_data %>%
              tsibble() %>%
              model(
                fit = ETS(inc)
              ) %>%
              forecast(h = paste0(horizon, " weeks"), simulate = TRUE, times = nsim)
          } else if (model == "ARIMA" && transform_fun == "box_cox") {
            bc_lambda <- car::powerTransform(
              location_data$inc + 0.49,
              family = "bcPower")$lambda
            if(abs(bc_lambda) < 1e-2) {
              bc_lambda <- 0.0
            }
            temp <- location_data %>%
              tsibble() %>%
              model(
                fit = ARIMA(box_cox(inc + 0.49, lambda = UQ(bc_lambda)) ~ PDQ(0, 0, 0))
              ) %>%
              forecast(h = paste0(horizon, " weeks"), simulate = TRUE, times = nsim)
          } else if (model == "ARIMA" && transform_fun == "log") {
            temp <- location_data %>%
              tsibble() %>%
              model(
                fit = ARIMA(log(inc + 0.49) ~ PDQ(0, 0, 0))
              ) %>%
              forecast(h = paste0(horizon, " weeks"), simulate = TRUE, times = nsim)
          } else if (model == "ARIMA" && transform_fun == "none") {
            temp <- location_data %>%
              tsibble() %>%
              model(
                fit = ARIMA(inc ~ PDQ(0, 0, 0))
              ) %>%
              forecast(h = paste0(horizon, " weeks"), simulate = TRUE, times = nsim)
          }

          forecast_inc_trajectories <- matrix(NA, nrow = nsim, ncol = horizon)
	  if (transform_fun == "none") {
            for(h in seq_len(horizon)) {
              forecast_inc_trajectories[, h] <- temp$inc[[h]]$x
            }
          } else {
            for(h in seq_len(horizon)) {
              forecast_inc_trajectories[, h] <- temp$inc[[h]]$dist$x %>%
                temp$inc[[h]]$transform()
            }
          }

          forecast_inc_trajectories[is.na(forecast_inc_trajectories)] <- 0.0
          forecast_inc_trajectories[forecast_inc_trajectories < 0] <- 0.0

          if (ts_frequency == 7) {
            new_forecast_inc_trajectories <- matrix(
              nrow = nrow(forecast_inc_trajectories),
              ncol = ncol(forecast_inc_trajectories) / 7)
            for (j in seq_len(ncol(new_forecast_inc_trajectories))) {
              new_forecast_inc_trajectories[, j] <- apply(
                forecast_inc_trajectories[, (j - 1) * 7 + seq_len(7)], 1, sum)
            }
          }
        }

        quantile_forecast <- NULL
        if('inc' %in% types) {
          quantile_forecast <- dplyr::bind_rows(
            quantile_forecast,
            purrr::map_dfr(
              seq_len(horizon),
              function(h) {
                data.frame(
                  horizon = h,
                  type = 'inc',
                  quantile = required_quantiles,
                  value = quantile(forecast_inc_trajectories[, h], probs = required_quantiles, na.rm = TRUE),
                  stringsAsFactors = FALSE
                )
              }
            )
          )
        }
        
        if('cum' %in% types) {
          # initialize sampled cumulative incidence at the most recent observed value
          sampled_cum <- tail(location_data$cum, 1)
          
          for(h in seq_len(horizon)) {
            # update sampled cumulative incidence
            sampled_cum <- sampled_cum + forecast_inc_trajectories[, h]
            
            quantile_forecast <- bind_rows(
              quantile_forecast,
              data.frame(
                horizon = h,
                type = 'cum',
                quantile = required_quantiles,
                value = quantile(sampled_cum, probs = required_quantiles),
                stringsAsFactors = FALSE
              )
            )
          }
        }

        quantile_forecast <- quantile_forecast %>%
          dplyr::transmute(
            forecast_date = as.character(forecast_week_end_date + 2),
            target = paste0(horizon, ' wk ahead ', type, ' ', substr(measure, 1, nchar(measure)-1)),
            target_end_date = as.character(forecast_week_end_date  + 7*horizon),
            location = location,
            type = 'quantile',
            quantile = quantile,
            value = round(value)
          )
        
        location_results <- dplyr::bind_rows(
          quantile_forecast,
          quantile_forecast %>%
            dplyr::filter(quantile == 0.5) %>%
            dplyr::mutate(
              type = 'point',
              quantile = NA_real_
            )
        )

        measure_results <- location_results
    
    results <- dplyr::bind_rows(
      results,
      measure_results
    )
  }
  
  write.csv(results, file = results_path, row.names = FALSE)
}
toctoc <- Sys.time()

toctoc - tictic
