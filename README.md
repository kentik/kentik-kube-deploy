# kentik-kube-deploy - Kube configuration and deployment to Kubernetes

kentik-kube-deploy contains the Kubernetes deployment descriptors necessary to deploy the kube components into a Kubernetes
cluster. These descriptors utilize kustomize which is available in kubectl v1.14+.

Most user-serviceable settings are configured via the configuration section in [deploy-kube.sh](deploy-kube.sh).
Additional settings can be found in [kustomization-template.yml](kustomization-template.yml).

`deploy-kube.sh` is the deployment script.

To run `deploy-kube.sh`, you'll need to have at least one kubernetes context and your Kentik plan information:
- Your Kentik Plan ID number
- Your Kentik registered email address
- Your Kentik token/API key
- Your cloud provider name (e.g., aws)
- Your kubernetes cluster name

## Kube Installation
### Clone this repo
```bash
git clone https://github.com/kentik/kentik-kube-deploy.git
cd kentik-kube-deploy
```

### Configure the script
Edit the `USER CONFIGURATION` section at the very top of `deploy-kube.sh`. This is where you'll set your Kentik plan
information.

### Run `deploy-kube.sh`
```bash
./deploy-kube.sh
```

## deploy-kube.sh optional flags

`deploy-kube.sh -h` This will show you basic usage of the deployment script.

All the below will deploy kubemeta, kappa agents, and kappa aggregator into a k8s cluster.

- `deploy-kube.sh` Deploy into the k8s cluster as defined by the context in `~/.kube/config`
- `deploy-kube.sh -f <path-to-kube-config-file>` Deploy into the k8s cluster as defined by the context in the specified config file.
- `deploy-kube.sh -c <k8s-context>` Deploy into the k8s cluster as defined by a specific context in `~/.kube/config`
- `deploy-kube.sh -f <path-to-kube-config-file> -c <k8s-context>` Deploy into the k8s cluster as defined by the specified context in the specified config file.
