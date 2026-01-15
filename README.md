<!--
SPDX-FileCopyrightText: 2026 SUSE LLC
SPDX-FileContributor: Cédric Bosdonnat

SPDX-License-Identifier: MIT
-->

[![REUSE status](https://api.reuse.software/badge/git.fsfe.org/reuse/api)](https://api.reuse.software/info/git.fsfe.org/reuse/api)

This repository is a collection of example helm charts to deploy Uyuni on Kubernetes clusters.
The rationale behind it is that given all the possible combinations, the official helm chart cannot cover all cases.
These helm charts aim at providing some of the common combinations.

Each folder at this level is a different helm chart with its own README explaining its specific details and uses.

# Exposing ports to the outside world

For Uyuni to work, non-HTTP ports of the containers need to be routed to the outside of the cluster.
There are several ways to achieve this, and the solutions listed here won't be exhaustive.

## Nginx on RKE2

RKE2 comes with nginx ingress controller by default.
Nginx can route non HTTP ports, but a configuration file must be added on each node to set it up.

Drop a file with such a content in `/var/lib/rancher/rke2/server/manifests/`.
Note that `uyuni` needs to be replaced by the namespace where the helm chart will be deployed to.

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-ingress-nginx
  namespace: kube-system
spec:
  valuesContent: |-
    controller:
      config:
        hsts: "false"
    tcp:
      5432: uyuni/reportdb:5432
      4505: uyuni/salt:4505
      4506: uyuni/salt:4506
      25151: uyuni/cobbler:25151
      9100: uyuni/tomcat:9100
      # Comment if installed with server-helm.enableMonitoring = false
      5556: uyuni/taskomatic:5556
      5557: uyuni/tomcat:5557
      9187: uyuni/db:9187
      9800: uyuni/taskomatic:9800
      ## Only if installed with server-helm.exposeJavaDebug = true
      # 8001: uyuni/taskomatic:8001
      # 8002: uyuni/search:8002
      # 8003: uyuni/tomcat:8003
    udp:
      69: uyuni/tftp:69
```
