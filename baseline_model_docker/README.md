This directory contains files to support a containerized Docker version of the COVID-19 baseline model that can be run locally or via AWS ECS.

Docs: TBD. For now, here's a summary from [baseline-model's README.md](https://github.com/reichlab/baseline-model/blob/main/README.md):

# `/data` dir

The app expects a volume (either a local Docker one or EFS) to be mounted at `/data` which contains all required GitHub repos: `covidModels`, `covidData`, and `covid19-forecast-hub`.

Note: This project's `Dockerfile`s run the script version mounted under `/data/covidModels` , which means you need to update that repo after editing and pushing scripts for the changes to be picked up. For local development, you can use [docker cp](https://docs.docker.com/engine/reference/commandline/cp/) for a faster workflow. The following steps create a temp container that mounts the volume at `/data`, copy this entire repo to the volume, and then delete the temp container. NB: This will delete and replace the repo on the volume! (The `COPYFILE_DISABLE` variable is necessary only in Mac development to disable AppleDouble format "._*" files per [this post](https://superuser.com/questions/61185/why-do-i-get-files-like-foo-in-my-tarball-on-os-x). Otherwise, you'll get files in the volume's `config/` dir like `._.env` and `._.git-credentials`.)

```bash
docker create --name temp_container --mount type=volume,src=data_volume,target=/data ubuntu
COPYFILE_DISABLE=1 tar -c -C "path-to-this-repo" | docker cp - temp_container:/data
docker exec -it temp_container /bin/bash  # (optional) explore the volume from the command line
docker rm temp_container
```

# Environment variables

The app requires six environment variables to be passed in: `SLACK_API_TOKEN`, `CHANNEL_ID`, `GH_TOKEN`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, and `GIT_CREDENTIALS`

# To build the image

```bash
cd "path-to-this-repo/baseline_model_docker"
docker build -t baseline-model:1.0 .
```

# To run the image locally

```bash
docker run --rm \
  --mount type=volume,src=data_volume,target=/data \
  --env-file /path-to-env-dir/.env \
  baseline-model:1.0
```

# To publish the image

```bash
docker login -u "reichlab" docker.io
docker tag baseline-model:1.0 reichlab/baseline-model:1.0
docker push reichlab/baseline-model:1.0
```
