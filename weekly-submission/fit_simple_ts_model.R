library(tidyverse)
library(covidData)
library(covidModels)

args <- commandArgs(trailingOnly = TRUE)
# args <- c('2020-05-09', 'quantile_baseline-symmetrize_TRUE', 'weekly', '8', 'none', '1')
forecast_week_end_date <- lubridate::ymd(args[1])
model <- args[2]
temporal_resolution <- args[3]
window_size <- as.integer(args[4])
transformation <- args[5]
d <- as.integer(args[6])

if(grepl('quantile_baseline', model)) {
  fit_call_args <- list(
    model = 'quantile_baseline',
    symmetrize = as.logical(strsplit(strsplit(model, '-')[[1]], '_')[[2]][[2]])
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
                       forecast_week_end_date + 2,
                       '-COVIDhub-baseline.csv')
if(!file.exists(results_path)) {
  results <- NULL
  for(measure in c('deaths', 'cases')) {
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
    
    if(transformation %in% c('log', 'box-cox')) {
      data$inc[data$inc < 0] <- 0L
    }
    
    measure_results <- purrr::map_dfr(
      unique(data$location),
      function(location) {
        print(paste0('measure = ', measure, '; location = ', location))
        location_data <- data %>%
          dplyr::filter(location == UQ(location))
  
        if(all(location_data$cum == 0)) {
          start_date <- lubridate::ymd(min(location_data$date)) + 7
        } else {
          start_date <- max(
            lubridate::ymd(min(location_data$date)) + 7,
            lubridate::ymd(min(location_data$date[location_data$cum > 0])) - 2*7)
        }
        
        location_data <- location_data %>%
          dplyr::filter(date >= as.character(start_date))
  
        fit_call_args$y <- location_data$inc
        
        model_fit <- do.call(fit_simple_ts, fit_call_args)
        
        forecast_inc_trajectories <- predict(
          model_fit,
          newdata = location_data$inc,
          horizon = horizon,
          nsim = 100000
        )
        
        forecast_inc_trajectories[forecast_inc_trajectories < 0] <- 0.0
        
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
        
        return(
          dplyr::bind_rows(
            quantile_forecast,
            quantile_forecast %>%
              dplyr::filter(quantile == 0.5) %>%
              dplyr::mutate(
                type = 'point',
                quantile = NA_real_
              )
          )
        )
      })
    
    results <- dplyr::bind_rows(
      results,
      measure_results
    )
  }
  
  write.csv(results, file = results_path, row.names = FALSE)
}


# plot forecasts
plots_dir <- paste0('weekly-submission/', full_model_str, '-plots/')
if(!dir.exists(plots_dir)) {
  dir.create(plots_dir)
}

for(measure in c('deaths', 'cases')) {
  if(measure == 'deaths') {
    data <- covidData::load_jhu_data(
      issue_date = as.character(forecast_week_end_date + 1),
      spatial_resolution = c('state', 'national'),
      temporal_resolution = 'weekly',
      measure = measure)
    horizon <- 4L
    types <- c('inc', 'cum')
    required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
  } else if(measure == 'cases') {
    data <- covidData::load_jhu_data(
      issue_date = as.character(forecast_week_end_date + 1),
      spatial_resolution = c('county', 'state', 'national'),
      temporal_resolution = 'weekly',
      measure = measure)
    horizon <- 8L
    types <- 'inc'
    required_quantiles <- c(0.025, 0.100, 0.250, 0.500, 0.750, 0.900, 0.975)
  }
  
  location_batches <- results %>%
    dplyr::filter(grepl(substr(measure, 1, nchar(measure) - 1), target)) %>%
    dplyr::distinct(location) %>%
    dplyr::arrange(nchar(location), location) %>%
    dplyr::mutate(
      location = factor(location, levels = location),
      batch = rep(seq_len(ceiling(nrow(.)/30)), each = 30)[seq_len(nrow(.))]
    )
  
  pdf(paste0(plots_dir,
             forecast_week_end_date + 2,
             '-', full_model_str, '-', measure, '.pdf'),
    width=24, height=14)
  
  for(batch_val in unique(location_batches$batch)) {
    print(batch_val)
    batch_locations <- location_batches$location[location_batches$batch == batch_val]
    plottable_predictions <- results %>%
      dplyr::filter(
        location %in% batch_locations,
        grepl(substr(measure, 1, nchar(measure) - 1), target)) %>%
      dplyr::mutate(
        endpoint_type = ifelse(quantile < 0.5, 'lower', 'upper'),
        alpha = ifelse(
          endpoint_type == 'lower',
          format(2*quantile, digits=3, nsmall=3),
          format(2*(1-quantile), digits=3, nsmall=3))
      ) %>%
      dplyr::select(-quantile) %>%
      tidyr::pivot_wider(names_from='endpoint_type', values_from='value')

    for(type in types) {
      p <- ggplot() +
        geom_line(data=data %>% 
                    dplyr::mutate(date = lubridate::ymd(date)) %>%
                    dplyr::filter(location %in% batch_locations),
                  mapping = aes_string(x = "date", y = type, group = "location")) +
        geom_point(data=data %>% 
                     dplyr::mutate(date = lubridate::ymd(date)) %>%
                     dplyr::filter(location %in% batch_locations),
                  mapping = aes_string(x = "date", y = type, group = "location")) +
        geom_ribbon(
          data = plottable_predictions %>% dplyr::filter(location %in% batch_locations) %>%
            filter(alpha != "1.000", grepl(UQ(type), target)) %>%
            mutate(
              horizon = as.integer(substr(target, 1, 1)),
              target_end_date = forecast_week_end_date + 7*horizon),
          mapping = aes(x = target_end_date,
                        ymin=lower, ymax=upper,
                        fill=alpha)) +
        geom_line(
          data = results %>% dplyr::filter(location %in% batch_locations) %>%
            filter(quantile == 0.5,
                   grepl(UQ(type), target),
                   grepl(substr(measure, 1, nchar(measure) - 1), target)) %>%
            mutate(
              horizon = as.integer(substr(target, 1, 1)),
              target_end_date = forecast_week_end_date + 7*horizon),
          mapping = aes(x = target_end_date, y = value)) +
        geom_point(
          data = results %>% dplyr::filter(location %in% batch_locations) %>%
            filter(quantile == 0.5,
                   grepl(UQ(type), target),
                   grepl(substr(measure, 1, nchar(measure) - 1), target)) %>%
            mutate(
              horizon = as.integer(substr(target, 1, 1)),
              target_end_date = forecast_week_end_date + 7*horizon),
          mapping = aes(x = target_end_date, y = value)) +
        ylim(0, 10000) +
        facet_wrap(~location, ncol=6, scales = 'free_y') +
        ggtitle(paste(type, measure, as.character(forecast_week_end_date))) +
        theme_bw()
      print(p)
    }
  }
  dev.off()
}
