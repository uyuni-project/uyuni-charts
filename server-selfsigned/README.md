<!--
SPDX-FileCopyrightText: 2026 SUSE LLC
SPDX-FileContributor: Cédric Bosdonnat

SPDX-License-Identifier: MIT
-->

# Requirements

Before installing this helm chart, ensure that [cert-manager](https://cert-manager.io/docs/installation/helm/) and 
[trust-manager](https://cert-manager.io/docs/trust/trust-manager/installation/) are installed in the cluster.
If they are not installed in the `cert-manager` namespace, set the `certManagerNamespace` value.

Also read the requirements in the main [README](../) as they apply here too.

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

# Uninstalling

By default, `cert-manager` does not remove the created secrets.
In such a case, delete them after uninstalling the helm chart:

```
kubectl delete secrets -n cert-manager uyuni-ca
kubectl delete secrets -n <uyuni-namspace> db-cert uyuni-cert

```
