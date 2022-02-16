#!/bin/bash

#GIT_DIRS="/data/covid19-forecast-hub /data/covid19-forecast-hub-web/ /data/covidModels/"
GIT_DIRS=/data/*

for GIT_DIR in ${GIT_DIRS}; do
  echo -e "\n* ${GIT_DIR}"
  pushd ${GIT_DIR}
  git status
  popd
done

pushd /data/covidModels/
git pull
popd
