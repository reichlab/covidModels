library(tidyverse)
library(covidData)
library(covidModels)

args <- commandArgs(trailingOnly = TRUE)
# args <- c('2020-05-09', 'quantile_baseline-symmetrize_TRUE', 'weekly', '8', 'none', '1')
# args <- c('01', '2020-05-09', 'spline_smoother', 'daily', 'NA', 'none', '0')
# args <- c('01', '2020-07-25', 'spline_smoother', 'daily', 'NA', 'none', '0')
location <- args[1]
forecast_week_end_date <- lubridate::ymd(args[2])
model <- args[3]
temporal_resolution <- args[4]
window_size <- suppressWarnings(as.integer(args[5]))
transformation <- args[6]
d <- as.integer(args[7])

if(nchar(location) == 2L) {
  measures <- c('deaths', 'cases')
} else {
  measures <- 'cases'
}

if(grepl('quantile_baseline', model)) {
  fit_call_args <- list(
    model = 'quantile_baseline',
    symmetrize = as.logical(strsplit(strsplit(model, '-')[[1]], '_')[[2]][[2]])
  )
} else if(model == 'spline_smoother') {
  fit_call_args <- list(
    model = 'spline_smoother',
    temporal_resolution = temporal_resolution
  )
} else {
  stop('Unsupported model_str')
}

if(temporal_resolution == 'weekly') {
  fit_call_args$ts_frequency <- 1L
} else if(temporal_resolution == 'daily') {
  fit_call_args$ts_frequency <- 7L
} else {
  stop('Unsupported temporal_resolution')
}

fit_call_args$temporal_resolution <- temporal_resolution
fit_call_args$window_size <- window_size
fit_call_args$transformation <- transformation
fit_call_args$d <- d

full_model_str <- paste0(
  model,
  '-temporal_resolution_', temporal_resolution,
  '-window_size_', window_size,
  '-transformation_', transformation,
  '-d_', d
)

# forecast_week_end_dates <- as.character(
#   lubridate::ymd('2020-04-04') + seq(from = 0, length = 14)*7)
results_dir <- paste0('weekly-submission/', full_model_str, '/')
if(!dir.exists(results_dir)) {
  dir.create(results_dir)
}

results_path <- paste0(results_dir,
                       location, '-',
                       forecast_week_end_date + 2, '-',
                       full_model_str,
                       '.csv')
if(!file.exists(results_path)) {
  results <- NULL
  for(measure in measures) {
    if(measure == 'deaths') {
      data <- covidData::load_jhu_data(
        issue_date = as.character(forecast_week_end_date + 1),
        spatial_resolution = c('state', 'national'),
        temporal_resolution = temporal_resolution,
        measure = measure)
      horizon <- 4L
      types <- c('inc', 'cum')
      required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
    } else if(measure == 'cases') {
      data <- covidData::load_jhu_data(
        issue_date = as.character(forecast_week_end_date + 1),
        spatial_resolution = c('county', 'state', 'national'),
        temporal_resolution = temporal_resolution,
        measure = measure)
      horizon <- 8L
      types <- 'inc'
      required_quantiles <- c(0.025, 0.100, 0.250, 0.500, 0.750, 0.900, 0.975)
    }
    
    if(transformation %in% c('log', 'box-cox') ||
       model == 'spline_smoother') {
      data$inc[data$inc < 0] <- 0L
    }
    
    location_data <- data %>%
      dplyr::filter(location == UQ(location))
  
    if(all(location_data$cum == 0)) {
      start_date <- lubridate::ymd(min(location_data$date)) + 7
    } else {
      first_nonzero_ind <- min(which(data$inc != 0))
      start_date <- max(
        lubridate::ymd(min(location_data$date)) + 7,
        lubridate::ymd(min(location_data$date[location_data$cum > 0])) - 1)
    }
        
    location_data <- location_data %>%
      dplyr::filter(date >= as.character(start_date))
  
    fit_call_args$y <- location_data$inc
    
    model_fit <- do.call(fit_simple_ts, fit_call_args)
    
    if(temporal_resolution == 'daily') {
      horizon <- horizon * 7
    }
    
    forecast_inc_trajectories <- predict(
      model_fit,
      newdata = location_data$inc,
      horizon = horizon,
      nsim = 100000,
      post_pred = FALSE,
      temporal_resolution = temporal_resolution
    )
    
    forecast_inc_trajectories[forecast_inc_trajectories < 0] <- 0.0
    
    if(temporal_resolution == 'daily') {
      new_forecast_inc_trajectories <- matrix(
        nrow = nrow(forecast_inc_trajectories),
        ncol = ncol(forecast_inc_trajectories)/7)
      for(j in seq_len(ncol(new_forecast_inc_trajectories))) {
        new_forecast_inc_trajectories[, j] <- apply(
          forecast_inc_trajectories[, (j - 1) * 7 + seq_len(7)], 1, sum)
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
              value = quantile(forecast_inc_trajectories[, h], probs = required_quantiles),
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
        value = value
      )
    
    measure_results <- dplyr::bind_rows(
      quantile_forecast,
      quantile_forecast %>%
        dplyr::filter(quantile == 0.5) %>%
        dplyr::mutate(
          type = 'point',
          quantile = NA_real_
        )
    )

    results <- dplyr::bind_rows(
      results,
      measure_results
    )
  }
  
  write.csv(results, file = results_path, row.names = FALSE)
}
