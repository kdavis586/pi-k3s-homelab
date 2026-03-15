# Background
## Project: Kubernetes on Pi
I want to set up Kubernetes on raspberry pis. The ultimate goal is to run lightweight homelab and potentially a github runner.

## Hardware
3x Raspberry Pi 4 Model B (2x w/ 4GB ram, 1x with 8) <-- I think. If making a choice based on resources, assume 4GB for all
3x POE hats installed on all PIs
1x TP-Link TL-SG605P
1x ATT router modem combo (fiber connection)
1x 1TB external hard drive (usb c connection)
3x microSD cards (2x 64GB, 1x 32GB)

## Immediate Goal - Reproducable installations that are generally performant given the compute constraints.
I want to be able to make incremental/new changes to my cluster by making git commits. I don't want GitOps right now, but if there was a way to deploy to the cluster without moving SD cards around then that would be great. We might need to evaluate the lighterweight versions of k8s geared toward IOT.

## Post-Success: Jellyfin installation with media hosted on external hard drive
I want to be able to run jellyfin as my first project, they have docs on how to host on k8s: https://jellyfin.org/docs/general/installation/advanced/kubernetes. It looks like it involves helm.

# Task: Create a plan by doing a deep dive on the best way to tackle this problem in 2026. For options where you don't see a clear winner, and/or there are important benefirts/drawbacks for options, consult me


