#!/bin/bash

source image.env
buildah bud -t $imageName .
