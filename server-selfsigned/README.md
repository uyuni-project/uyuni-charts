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

# Setting up proxies

Certificates can be generated for proxies on the server cluster and copied over to the proxy cluster.

To create a proxy certificate, create a yaml file with the following content.
Change:
* `$ProxyName` to unique name identifying the proxy
* `$ProxyFQDN` to the FQDN of the proxy
* `Namespace` to the namespace the server was installed in.

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $ProxyName-cert
  namespace: $Namespace
  labels:
    app.kubernetes.io/part-of: uyuni
spec:
  secretName: $ProxyName-cert
  secretTemplate:
    labels:
      app.kubernetes.io/part-of: uyuni
  isCA: false
  usages:
  - server auth
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
    rotationPolicy: Always
  dnsNames:
    - $ProxyFQDN
  commonName: $ProxyFQDN
  issuerRef:
    name: "uyuni-openbao-issuer"
    kind: ClusterIssuer
    group: cert-manager.io

```

Set `SERVER_CTX` to the `kubectl` context for the server running the server, and `PROXY_CTX` for the cluster running the proxy.

Apply this file using `kubectl --context $SERVER_CTX apply -f`.
Copy the generated secret to the proxy cluster in the same namespace the proxy will be installed in:

```bash
ProxyNamespace=uyuni
kubectl --context $SERVER_CTX get secret -n $Namespace -o yaml $ProxyName-cert | \
    sed -e "s/name: $ProxyName/name: proxy-cert/" \
        -e "s/namespace: $Namespace/namespace: $ProxyNamespace/" \
        -e "/\(uid\)\|\(resourceVersion\)\|\(creationTimestamp\)\|\(cert-manager\)/d" | \
    kubectl --context $PROXY_CTX apply -f -
```

Also copy the `uyuni-ca` certificate to the proxy.

```bash
kubectl --context $SERVER_CTX get cm -n $Namespace uyuni-ca -o "jsonpath={.data.ca\.crt}" >root-ca.crt
kubectl --context $PROXY_CTX create configmap uyuni-ca -n $ProxyNamespace --from-file=ca.crt=root-ca.crt
```


# Uninstalling

By default, `cert-manager` does not remove the created secrets.
In such a case, delete them after uninstalling the helm chart:

```
kubectl delete secrets -n cert-manager uyuni-ca
kubectl delete secrets -n <uyuni-namspace> db-cert uyuni-cert

```
