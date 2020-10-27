library(tidyr)
library(dplyr)
library(lubridate)

required_locations <- readr::read_csv(
  'https://raw.githubusercontent.com/reichlab/covid19-forecast-hub/master/data-locations/locations.csv'
)$location

# combinations of methods and dates for which to predict
analysis_combinations <- tidyr::expand_grid(
  forecast_week_end_date = as.character(
    lubridate::ymd('2020-05-30') + seq(from = 0, length = 19)*7),
#    lubridate::ymd('2020-05-30') + 19*7),
  location = required_locations,
  model = c('ETS', 'ARIMA'),
  transform_fun = c('box_cox', 'log', 'none'),
  temporal_resolution = 'weekly'
)

# parameters for cluster job
cores_req <- "1"
mem_req <- "5000"
time_req <- "2:00"
queue_req <- "short"

save_path <- "/project/uma_nicholas_reich/covidModels/forecasts/"
output_path <- "/project/uma_nicholas_reich/covidModels/logs/"
lsfoutfilename <- "covidModels.out"


for (row_ind in rev(seq_len(nrow(analysis_combinations)))) {
  forecast_week_end_date <- analysis_combinations$forecast_week_end_date[row_ind]
  location <- analysis_combinations$location[row_ind]
  model <- analysis_combinations$model[row_ind]
  transform_fun <- analysis_combinations$transform_fun[row_ind]
  temporal_resolution <- analysis_combinations$temporal_resolution[row_ind]

  results_filename <- paste0(save_path,
    "model_", model, "-transform_", transform_fun, "-temporal_resolution_", temporal_resolution, "/",
    lubridate::ymd(forecast_week_end_date) + 2,
    "-model_", model, "-transform_", transform_fun, "-temporal_resolution_", temporal_resolution,
    "-", location,
    ".csv")
  if (file.exists(results_filename)) {
    print(paste0("Skipping ", results_filename))
  } else {
    filename <- paste0(output_path, "/submit-fable-",
      forecast_week_end_date, "_",
      location, "_",
      model, "_",
      transform_fun, "_",
      temporal_resolution,
      ".sh")
      
    requestCmds <- "#!/bin/bash\n"
    requestCmds <- paste0(requestCmds,
      "#BSUB -n 1 # how many cores we want for our job\n",
      "#BSUB -R span[hosts=1] # ask for all the cores on a single machine\n",
      "#BSUB -R rusage[mem=5000] # ask for memory\n",
      "#BSUB -o ", lsfoutfilename, " # log LSF output to a file\n",
      "#BSUB -W 2:00 # run time\n",
      "#BSUB -q short # which queue we want to run in\n")

    cat(requestCmds, file = filename)
    cat("module load gcc/8.1.0\n", file = filename, append = TRUE)
    cat("module load R/4.0.0_gcc\n", file = filename, append = TRUE)
    cat(paste0("R CMD BATCH --vanilla \'--args ",
      forecast_week_end_date, " ",
      location, " ",
      model, " ",
      transform_fun, " ",
      temporal_resolution, " ",
      "\' /home/er71a/covidModels/weekly-submission/fit_fable_model_one_location.R ",
      output_path, "/output-fable-",
      forecast_week_end_date, "_",
      location, "_",
      model, "_",
      transform_fun, "_",
      temporal_resolution, ".Rout"),
    file = filename, append = TRUE)

    bsubCmd <- paste0("bsub < ", filename)
    system(bsubCmd)
  }
}
