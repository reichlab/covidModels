This directory contains files to support a containerized Docker version of the COVID-19 baseline model that can be run locally or via AWS ECS.

Docs: TBD. For now, here's a summary from [container-demo-app's README.md](https://github.com/reichlab/container-demo-app/blob/main/README.md):

# `/data` dir

The app expects a volume (either a local Docker one or EFS) to be mounted at `/data` which contains all required GitHub repos: `covidModels`, `covidData`, and `covid19-forecast-hub`.

Notes:
- To populate an AWS EFS, launch a temporary EC2 instance that mounts the EFS at `/data`, and then run the appropriate `git clone` commands. See [container-demo-app's ecs.md](https://github.com/reichlab/container-demo-app/blob/main/ecs.md) for details on how to do this.
- At least on ECS, the user and group of the cloned repos must all match. Note that the default user when running a temporary EC2 instance to modify the EFS is `ec2-user` (not `root`, which is the user when the container runs). We currently recommend that you change freshly cloned repos to `root:root`, e.g., `sudo chown -R root:root /data/sandbox`. Otherwise, you'll see errors like this when doing `git pull`: _fatal: detected dubious ownership in repository at ..._ .
- This project's `Dockerfile`s run the script version mounted under `/data/covidModels` , which means you need to update that repo after editing and pushing scripts for the changes to be picked up. To explore the volume:

```bash
# create the empty volume
docker volume create data_volume

# (optional) explore the volume from the command line via a temp container
docker run --rm -it --name temp_container --mount type=volume,src=data_volume,target=/data ubuntu /bin/bash

# if you need git installed:
apt update ; apt install -y git
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
