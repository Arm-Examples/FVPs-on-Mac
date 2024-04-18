# FVPs-on-Mac

This repository contains scripts that enable Arm Virtual Hardware FVPs to run via Docker on MacOS.

## Prerequisites

[Install Docker Desktop on Mac](https://docs.docker.com/desktop/install/mac-install/).

For commercial use you might require a paid subscription.

Verify proper installation by running the following commands on a terminal:

```sh
docker info
```

If the Docker installation is operational it prints out version information about Client and Server.

## Clone the repo

Open a terminal and set the working directory where to store the Fast Model wrapper to. Then run:

```sh
git clone https://github.com/Arm-Examples/FVPs-on-Mac.git
```

This will create the subdirectory `FVPs-on-Mac` in the current working directory.

## Build the Docker wrapper

Run the build script to create the Docker image and populate the `bin` folder with model wrappers:

```sh
./build.sh
```

Once this succeeds inspect the created `bin` folder containing a bunch of symlinks to `fvp.sh`.
These wrappers can be used exactly like any native model executable:

```sh
./bin/FVP_MPS2_Cortex-M3 --version
```

## Expose models to local environment

Add `$(pwd)/FVPs-on-Mac/bin` to `PATH` environment:

```sh
export PATH=$PATH:$(pwd)/FVPs-on-Mac/bin
```

Put this to our `~/.zshrc` to make it permanent.

## Run Models

Once the setup has been completed one can run Fast Models as they are installed natively.

Some restrictions still apply:

- The users home directory is mapped into the Docker container. Hence, all files
    accessed (application images, configuration files) must be stored in users home.

- Fast Models require an activated User Based License. Typically, the license cache
    is stored in `~/.armlm` on the host machine and mapped into the container as
    part of the user home. Thus, the models running inside of the container reuse the
    license activated on the host machine.

## Customization

The Fast Model version and package used for creating the Docker image and wrapper scripts
is configured in the file `fvprc`. If one wants to use another model version or custom package
one can just change the values stored in this file.

Alternatively, on can set the model version for example as an environment variable overwriting
the default given in `fvprc`. The following settings can be changed:

- *FVP_VERSION*: The release version triple (major.minor.patch).
- *FVP_BASE_URL*: The base download URL to get the model package from.
- *FVP_ARCHIVE*: The name of the model package archive to fetch.

The download URL is composed as `${FVP_BASE_URL}/${FVP_VERSION}/${FVP_ARCHIVE}`.
The created Docker image is labeled as `fvp:${FVP_VERSION}`. Hence, one can keep multiple versions
in parallel and switch between them by just setting the environment variable to the required version.

```sh
FVP_VERSION=11.22.39 FVP_MPS2_Cortex-M3 --version
```

## Repository structure

The repository contains the following files:

```txt
    📦
    ┣ 📂 bin           Created/updated by build.sh script
    ┣ 📄 build.sh      The script to build a Docker image
    ┣ 📄 dockerfile    The recipe used to build the Docker image
    ┣ 📄 fvp.sh        The wrapper script to launch a model executable inside a Docker container
    ┗ 📄 fvprc         The configuration file to customize default model version and package
```
