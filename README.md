# kappa-cfg - kubernetes configs for kappa

kappa-cfg contains example Kubernetes deployment descriptors for
kappa. These descriptors utilize kustomize which is available in
kubectl v1.14+.

Most user-serviceable settings are configured via the config map
and secret generators in [kustomization.yml](kustomization.yml).

## usage

`kubectl apply -k .`
