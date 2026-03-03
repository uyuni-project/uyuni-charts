<!--
SPDX-FileCopyrightText: 2026 SUSE LLC
SPDX-FileContributor: Cédric Bosdonnat

SPDX-License-Identifier: MIT
-->

[![REUSE status](https://api.reuse.software/badge/git.fsfe.org/reuse/api)](https://api.reuse.software/info/git.fsfe.org/reuse/api)

This repository is a collection of example helm charts to deploy Uyuni Server and Proxy on Kubernetes clusters.
The rationale behind it is that given all the possible combinations, the official helm charts cannot cover all cases.
These helm charts aim at providing some of the common combinations.

Each folder at this level is a different helm chart with its own README explaining its specific details and uses.
Obviously the server prefixed by `server-` deploy the server, while the ones prefixed by `proxy-`deploy the proxy.

# Exposing ports to the outside world

For Uyuni to work, non-HTTP ports of the containers need to be routed to the outside of the cluster.
There are several ways to achieve this, and the solutions listed here won't be exhaustive.

**Kubernetes's Nginx ingress controller is now deprecated.
Even though installing Uyuni on it may work, configuration for it is no longer provided.**

## Traefik on RKE2

RKE2 can be configured to use Traefik as ingress controller.
This is the recommended way now that nginx has been deprecated.
Read the [RKE2 documentation](https://docs.rke2.io/networking/networking_services#ingress-controller) to it setup with Traefik.

Traefik needs to configure endpoints on each node.
Those endpoints are then routed to the services using `IngressRouteTCP` or `IngressRouteUDP`.
The latter are deployed by the server-helm and proxy-helm charts if configured with `ingress.type` set to `traefik`.
On RKE2, setting the `ingress.class` may also be needed for Traefik to discover these routes.

**Note:** the traefik endpoints and routes are not enough: the endpoints need to be bound to ports visible from outside the cluster.
On a single node cluster this can be achieved by adding `hostPort: XXXX` on each of the endpoints.
Using a load balancer is a preferred solution and will be needed for multi-node clusters.

Drop a `/var/lib/rancher/rke2/server/manifests/uyuni-traefik.yaml` file with content from the following examples.
Remove the `hostPort` lines if using a load balancer.

### Uyuni server configuration

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    ports:
      reportdb-pgsql:
        port: 5432
        expose:
          default: true
        exposedPort: 5432
        protocol: TCP
        hostPort: 5432
        containerPort: 5432
      salt-publish:
        port: 4505
        expose:
          default: true
        exposedPort: 4505
        protocol: TCP
        hostPort: 4505
        containerPort: 4505
      salt-request:
        port: 4506
        expose:
          default: true
        exposedPort: 4506
        protocol: TCP
        hostPort: 4506
        containerPort: 4506
      cobbler:
        port: 25151
        expose:
          default:true
        exposedPort: 25151
        protocol: TCP
        hostPort: 25151
      node-xport:
        port: 9101
        expose:
          default: true
        exposedPort: 9101
        protocol: TCP
        hostPort: 9101
      # Only if monitoring is enabled
      db-xport:
        port: 9187
        expose:
          default: true
        exposedPort: 9187
        protocol: TCP
        hostPort: 9187
      tasko-mtrx:
        port: 9800
        expose:
          default: true
        exposedPort: 9800
        protocol: TCP
        hostPort: 9800
      # Only if java debugging is enabled
      tasko-debug:
        port: 8001
        expose:
          default: true
        exposedPort: 8001
        protocol: TCP
        hostPort: 8001
      search-debug:
        port: 8002
        expose:
          default: true
        exposedPort: 8002
        protocol: TCP
        hostPort: 8002
      tomcat-debug:
        port: 8003
        expose:
          default: true
        exposedPort: 8003
        protocol: TCP
        hostPort: 8003
```

### Uyuni proxy configuration


```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    ports:
      ssh:
        port: 8022
        expose:
          default: true
        exposedPort: 8022
        protocol: TCP
        hostPort: 8022
      salt-publish:
        port: 4505
        expose:
          default: true
        exposedPort: 4505
        protocol: TCP
        hostPort: 4505
        containerPort: 4505
      salt-request:
        port: 4506
        expose:
          default: true
        exposedPort: 4506
        protocol: TCP
        hostPort: 4506
        containerPort: 4506
```
