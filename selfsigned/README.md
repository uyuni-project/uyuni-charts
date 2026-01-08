# Requirements

Before installing this helm chart, ensure that cert-manager and trust-manager are installed in the cluster.

The following values need to be set:

```
credentials:
  db:
    admin:
      password: ... 
    internal:
      password: ... 
    reportdb:
      password: ...
  admin:
    password: ...

global:
  fqdn: "your.fq.dn"

server-helm:
  # All the values for server-helm should follow
```

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
      80: uyuni/web:80
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
      ## Only if installed with server-helm.hubAPI = true
      # 2830: uyuni/hub-api:2830
      ## Only if installed with server-helm.exposeJavaDebug = true
      # 8001: uyuni/taskomatic:8001
      # 8002: uyuni/search:8002
      # 8003: uyuni/tomcat:8003
    udp:
      69: uyuni/tftp:69

```
