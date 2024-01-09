Here are the commands I ended up with that configured the instance for running the weekly scripts. I did not run them exactly in this order because it took a lot of trial and error to get a successful setup, and it feels fragile (specific versions, etc.) Still, I'm putting them here for reference, and for a possible starting point for future VM tasks.


# User
We decided to use the default `ec2-user` account for all baseline operations, including installing R libraries and cloning files to `/data`. We played with using `root`, but it didn't go as well.

`whoami`
ec2-user


# For reference: Linux version
```bash
uname -a
```
Linux ip-172-31-94-18.ec2.internal 5.10.75-79.358.amzn2.x86_64 #1 SMP Thu Nov 4 21:08:30 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux


```bash
cat /proc/version
```
Linux version 5.10.75-79.358.amzn2.x86_64 (mockbuild@ip-10-0-40-76) (gcc10-g<cc (GCC) 10.3.1 20210422 (Red Hat 10.3.1-1), GNU ld version 2.35-21.amzn2.0.1) #1 SMP Thu Nov 4 21:08:30 UTC 2021


```bash
cat /etc/os-release
```
NAME="Amazon Linux"
VERSION="2"
ID="amzn"
ID_LIKE="centos rhel fedora"
VERSION_ID="2"
PRETTY_NAME="Amazon Linux 2"
ANSI_COLOR="0;33"
CPE_NAME="cpe:2.3:o:amazon:amazon_linux:2"
HOME_URL="https://amazonlinux.com/"


```bash
bash --version
```
GNU bash, version 4.2.46(2)-release (x86_64-koji-linux-gnu)
Copyright (C) 2011 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>


# Set up auto-mount of instance store volume on `/data`
Follow the instructions [here](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-using-volumes.html) - lsblk, fstab, etc. NB: I decided to `sudo chown ec2-user -R /data`


# update OS
`sudo yum update -y`


# update ec2-metadata
The default version of the `ec2-metadata` script is out of date. Update it by editing the script via `sudo emacs /usr/bin/ec2-metadata` and replacing it with that of https://raw.githubusercontent.com/aws/amazon-ec2-utils/main/ec2-metadata .


# set up timezone
`sudo timedatectl set-timezone UTC`


# Install python3
We decided the pre-installed version (3.7.10) is ok, so no install is necessary. However, we did do need to install two libraries.

`python3 --version`
Python 3.7.10

```bash
pip3 install pandas
pip3 install requests
```


# utilities and required OS libs
```bash
sudo yum install -y git
sudo yum install -y emacs
sudo yum install -y htop
sudo amazon-linux-extras install epel -y
sudo yum install -y openssl-devel
sudo yum install -y libxml2-devel
sudo yum install -y libcurl-devel
sudo yum install -y pandoc
sudo yum install -y nlopt-devel
sudo yum install -y udunits2-devel
sudo yum install -y geos geos-devel
sudo amazon-linux-extras install R4 -y
```


# configure git and GitHub users
git config --global user.name "EC2 Default User"
git config --global user.email nick@umass.edu


# install gh cli
```bash
cd
wget https://github.com/cli/cli/releases/download/v2.5.1/gh_2.5.1_linux_386.rpm
sudo yum localinstall -y gh_2.5.1_linux_386.rpm
gh auth login  # interactive: enter `reichlabmachine` personal access token
```


# Update gdal from 1.11.4
`sudo yum install gcc-c++.x86_64 cpp.x86_64 sqlite-devel.x86_64 libtiff.x86_64 cmake3.x86_64 -y`

```bash
cd /tmp
wget https://download.osgeo.org/proj/proj-6.1.1.tar.gz
tar -xvf proj-6.1.1.tar.gz
cd proj-6.1.1
./configure
sudo make
sudo make install
which proj ; proj
```

```bash
cd /tmp
wget https://github.com/OSGeo/gdal/releases/download/v3.2.1/gdal-3.2.1.tar.gz
tar -xvf gdal-3.2.1.tar.gz
cd gdal-3.2.1
./configure --with-proj=/usr/local --with-python
sudo make
sudo make install
which gdalinfo ; gdalinfo --version
```

```bash
sudo cp /usr/local/lib/libproj.so.15* /usr/lib64/
sudo cp /usr/local/lib/libgdal.so.28* /usr/lib64/
```


# install CMake
```bash
cd
wget https://github.com/Kitware/CMake/releases/download/v3.22.2/cmake-3.22.2.tar.gz
tar xzvf cmake-3.22.2.tar.gz
cd cmake-3.22.2
./bootstrap && make && sudo make install
```


# install nlopt
```bash
cd
git clone https://github.com/stevengj/nlopt.git
cd nlopt
mkdir build
cd build
cmake ..
make
sudo make install
```


# Install R4
`sudo amazon-linux-extras install R4 -y`

```R
R --version
```
R version 4.0.2 (2020-06-22) -- "Taking Off Again"
Copyright (C) 2020 The R Foundation for Statistical Computing
Platform: x86_64-koji-linux-gnu (64-bit)


# Install R packages via `install.packages`
NB: Install these as `ec2-user` within the `R` interpreter, rather than on the command line (e.g., not via `Rscript`, `R CMD INSTALL`, etc.) It is important that you get this prompt the first time you install a package:

    Installing package into ‘/usr/lib64/R/library’
    (as ‘lib’ is unspecified)
    Warning in install.packages("utf8", repos = "http://cran.rstudio.com/") :
      'lib = "/usr/lib64/R/library"' is not writable
    Would you like to use a personal library instead? (yes/No/cancel) yes
    Would you like to create a personal library
    ‘~/R/x86_64-koji-linux-gnu-library/4.0’
    to install packages into? (yes/No/cancel) YES

You should then have these results, where #1 is the `ec2-user` home R library location:

```R
.libPaths()
[1] "/home/ec2-user/R/x86_64-koji-linux-gnu-library/4.0"
[2] "/usr/lib64/R/library"                              
[3] "/usr/share/R/library"                              
```

Here then are the packages to install from within the `R` interpreter as `ec2-user`. Note that I may have missed some here :-/

```R
install.packages(c('devtools', 'crosstalk', 'doParallel', 'DT', 'foreach', 'htmltools', 'lubridate', 'parallel', 'plotly', 'scico', 'tidyverse', 'zoo', 'dplyr', 'tibble', 'tidyr', 'MMWRweek', 'purrr', 'ggplot2', 'magrittr', 'Matrix', 'NlcOptim', 'zeallot', 'googledrive', 'yaml', 'here', 'tictoc', 'furrr', 'matrixStats', 'ggpubr', 'ggforce', 'covidcast', 'car', 'fabletools', 'feasts', 'rvest'), repos='http://cran.rstudio.com/')
```

NOTE: For some packages, specific version sare required. Here are the ones I know of:
- `plotly`: 4.9.4.1 needed for weekly reports due to [stray arrow appears in county level plot #5274](https://github.com/reichlab/covid19-forecast-hub/issues/5274)
- `rmarkdown`: 2.11 needed for weekly reports due to 2.16 requiring upgrade of pandoc to 2.0+, but VM only has 1.12.3.1


# Install R packages via GitHub
These packages need to be installed directly from GitHub:

```R
devtools::install_github('reichlab/covidData')
devtools::install_github('reichlab/covidModels', subdir='R-package')
devtools::install_github("reichlab/zoltr")
devtools::install_github("reichlab/covidHubUtils")
devtools::install_github('reichlab/covidEnsembles')
devtools::install_github("reichlab/hubEnsembles")
devtools::install_github("reichlab/simplets")
devtools::install_github('elray1/epitools', ref = 'outlier_correction')
```


# Clone required repos
NB: For the `covid19-forecast-hub` repo we use the `reichlabmachine` fork and its personal access token - see **GitHub configuration** in README.md.

```bash
git -C /data clone https://github.com/reichlab/covidModels.git
git -C /data clone https://github.com/reichlab/covid19-forecast-hub-web.git
git -C /data clone https://github.com/reichlab/covidEnsembles.git
git -C /data clone https://github.com/reichlab/covid-hosp-models.git
git -C /data clone https://github.com/reichlab/flu-hosp-models-2021-2022.git
git -C /data clone https://github.com/reichlabmachine/sandbox.git

# clone the covid19-forecast-hub fork and do a one-time setup of sync
git clone https://github.com/reichlabmachine/covid19-forecast-hub.git
cd /data/covid19-forecast-hub
git remote add upstream https://github.com/reichlab/covid19-forecast-hub.git
git fetch upstream
git pull upstream master

# set up git credentials
for REPO_DIR in /data/*; do
  echo "${REPO_DIR}"
  git -C ${REPO_DIR} config credential.helper store
done
  
/data/covidModels/aws-vm-scripts/sandbox.sh  # should ask for personal access token first time
```


# Install requirements for deploy-covidhub-site.sh

The following installation steps were adapted for Amazon Linux 2 from the [covid19-forecast-hub-web README.md](https://github.com/reichlab/covid19-forecast-hub-web/blob/master/README.md). Steps are required for both Python and Ruby. Note that the Ruby steps on Amazon Linux 2 were problemmatic and ultimately required using `sudo`, which is generally not recommended. This could cause problems with future scripts that require different gems and/or gem versions.


## python
```bash
cd /data/covid19-forecast-hub-web
emacs Pipfile             # change: `python_version = "3.8"` -> `python_version = "3.7"`
sudo pip3 install pipenv  # ignore: WARNING: Running pip install with root privileges is generally not a good idea
pipenv shell              # should see: Successfully created virtual environment!
pipenv install            # "": Success!
```


## ruby
```bash
cd /data/covid19-forecast-hub-web
sudo amazon-linux-extras install ruby2.6 -y
sudo yum install ruby-devel -y
gem install jekyll
gem install bundler -v 1.16.6
sudo gem pristine ffi --version 1.9.25
sudo gem pristine http_parser.rb --version 0.6.0
bundle install
sudo gem pristine http_parser.rb --version 0.6.0
```
