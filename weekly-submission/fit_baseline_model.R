library(tidyverse)
library(covidData)
library(covidModels)
library(here)
setwd(here())

required_locations <- readr::read_csv('https://raw.githubusercontent.com/reichlab/covid19-forecast-hub/master/data-locations/locations.csv')

# Figure out what day it is; forecast creation date is set to a Monday,
# even if we are delayed and create it Tuesday morning.
forecast_week_end_dates <- as.character(
  lubridate::floor_date(Sys.Date(), unit = "week") - 1
)


for(forecast_week_end_date in forecast_week_end_dates) {
  forecast_week_end_date <- lubridate::ymd(forecast_week_end_date)
  
  results_path <- paste0('weekly-submission/forecasts/COVIDhub-baseline/',
                         forecast_week_end_date + 2,
                         '-COVIDhub-baseline.csv')
  if(!file.exists(results_path)) {
    results <- NULL
    for(measure in c('deaths', 'cases')) {
      if(measure == 'deaths') {
        data <- covidData::load_jhu_data(
          issue_date = as.character(forecast_week_end_date + 1),
          spatial_resolution = c('state', 'national'),
          temporal_resolution = 'weekly',
          measure = measure) %>%
          dplyr::filter(location %in% required_locations$location)
        horizon <- 8L
        types <- c('inc', 'cum')
        required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
      } else if(measure == 'cases') {
        data <- covidData::load_jhu_data(
          issue_date = as.character(forecast_week_end_date + 1),
          spatial_resolution = c('county', 'state', 'national'),
          temporal_resolution = 'weekly',
          measure = measure) %>%
          dplyr::filter(location %in% required_locations$location)
        horizon <- 8L
        types <- 'inc'
        required_quantiles <- c(0.025, 0.100, 0.250, 0.500, 0.750, 0.900, 0.975)
      }
      
      measure_results <- purrr::map_dfr(
        unique(data$location),
        function(location) {
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
    
          baseline_fit <- covidModels::fit_quantile_baseline(location_data$inc)
    
          quantile_forecast <- predict(
            baseline_fit,
            inc_data = location_data$inc,
            cum_data = location_data$cum,
            quantiles = required_quantiles,
            horizon = horizon,
            num_samples = 100000
          ) %>%
            dplyr::filter(type %in% types) %>%
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
                mutate(
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
}


# plot forecasts
for(forecast_week_end_date in forecast_week_end_dates) {
  forecast_week_end_date <- lubridate::ymd(forecast_week_end_date)
  
  results_path <- paste0('weekly-submission/forecasts/COVIDhub-baseline/',
                         forecast_week_end_date + 2,
                         '-COVIDhub-baseline.csv')
  if(!file.exists(results_path)) {
    stop(paste0('missing file: ', results_path))
  }
  
  results <- read.csv(results_path, stringsAsFactors = FALSE)
  for(measure in c('deaths', 'cases')) {
    if(measure == 'deaths') {
      data <- covidData::load_jhu_data(
        issue_date = as.character(forecast_week_end_date + 1),
        spatial_resolution = c('state', 'national'),
        temporal_resolution = 'weekly',
        measure = measure)
      horizon <- 8L
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
    
    pdf(paste0('weekly-submission/COVIDhub-baseline-plots/',
               forecast_week_end_date + 2,
               '-COVIDhub-baseline-plots-', measure, '.pdf'),
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
    
    #  batch_locations <- c('05', '10')
    
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
          facet_wrap(~location, ncol=6, scales = 'free_y') +
          ggtitle(paste(type, measure, as.character(forecast_week_end_date))) +
          theme_bw()
        print(p)
      }
    }
    dev.off()
  }
}
