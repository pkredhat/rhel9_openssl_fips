# OpenSSL Fips enabled in a Fedora Environment

> A Dockerfile and helper script to create Fedora 34 image with a FIPS
compliant OpenSSL module loaded.

## Overview
To build the Docker image you must have the `Dockerfile` and `fips.sh` script
in the same directory!
The Dockerfile uses a Fedora base image, installs some packages needed
by the _fips.sh_ script, adds the _fips.sh_ script and runs it. The script
takes care of the actual OpenSSL installation and FIPS configuration.

NOTE: this was derived to work with NodeJS but all node.js modules have been commented out. Options to work with Python will be added shortly.
NOTE: several lines have been commented out to simplify the troubleshooting, simply uncomment to use.

* Node: `v8.11.0`
* OpenSSL: `openssl-1.0.2h`
* OpenSSL FIPS Module: `openssl-fips-2.0.12`

## Running FIPS Enabled Container
OpenSSL FIPS mode is OFF by default. It can be turned on by either setting
the environment variable:
```
docker run -it -e "OPENSSL_FIPS=1" --name gcosta/node-fips /bin/bash
```
OR editing `/etc/ssl/openssl.cnf` and enabling FIPS mode once in the container:
```
fips_mode = yes
```
