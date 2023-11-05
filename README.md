# kappa-cfg - kubernetes configs for kappa

kappa-cfg contains example Kubernetes deployment descriptors for
kappa. These descriptors utilize kustomize which is available in
kubectl v1.14+.

Most user-serviceable settings are configured via the configuration section in [deploy-kube.sh](deploy-kube.sh).
Additional settings can be found in [kustomization.yml](kustomization.yml).

`deploy-kube.sh` is the deployment script.

## usage examples

`deploy-kube.sh -h` This will show you basic usage of the deployment script.

All the below will deploy kubemeta, kappa agents, and kappa aggregator into a k8s cluster.

- `deploy-kube.sh` Deploy into the k8s cluster as defined by the context in `~/.kube/config`
- `deploy-kube.sh -f <path-to-kube-config-file>` Deploy into the k8s cluster as defined by the context in the specified config file.
- `deploy-kube.sh -c <k8s-context>` Deploy into the k8s cluster as defined by a specific context in `~/.kube/config`
- `deploy-kube.sh -f <path-to-kube-config-file> -c <k8s-context>` Deploy into the k8s cluster as defined by the specified context in the specified config file.
