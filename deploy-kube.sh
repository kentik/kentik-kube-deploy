#!/bin/bash

# ######################
#
#   USER CONFIGURATION
#
# change the below values to match your kentik plan number, your email/token
# associated with your kentik account, and the device in question (e.g., a
# kubernetes cluster)
#
# ######################
#
# You must set these four as appropriate for your account and device
#
PLAN=0123456789
EMAIL=customer_email@example.com
TOKEN=123abc_your_customer_kentik_token_cba321
CLUSTER=your_cluster_name
CLOUDPROVIDER=aws_or_gcp_etc
#
# CAPTURE already has a workable default.  Don't change this unless you know
# for sure it's what you want.
#
CAPTURE='en*|veth.*|eth*'
# ######################
#
#   END CONFIGURATION
#
# ######################

K8S_CONTEXT=""
KUBECONFIG_FILE=""

function display_help() {
    echo "Usage: $0 [-c <k8s context>] [-f <k8s config file>]"
    echo "  -c  Specify the Kubernetes context. (optional)"
    echo "  -f  Specify the kubeconfig file to use. (optional)"
    echo "  -h  Display this help message."
    exit 1
}

# some optional commandline args
while getopts 'c:f:h' flag; do
    case "${flag}" in
        c) K8S_CONTEXT="${OPTARG}" ;;
        f) KUBECONFIG_FILE="${OPTARG}" ;;
        h) display_help ;;
        *) display_help ;;
    esac
done

echo "Going to apply the kube yaml configuration with the following values:"
echo
echo "Plan:    $PLAN"
echo "Email:   $EMAIL"
echo "Token:   $TOKEN"
echo "Cloud:   $CLOUDPROVIDER"
echo "Cluster: $CLUSTER"
echo
echo "Capture: $CAPTURE"
echo
read -p "Do you want to proceed (y/n)? " confirmation

if [[ ! "${confirmation}" =~ ^[yY]$ ]]; then
    echo "Aborted."
    exit 1
fi

sed \
    -e 's/__CAPTURE__/'"$CAPTURE"'/g' \
    -e 's/__CLOUDPROVIDER__/'"$CLOUDPROVIDER"'/g' \
    -e 's/__CLUSTER__/'"$CLUSTER"'/g' \
    -e 's/__EMAIL__/'"$EMAIL"'/g' \
    -e 's/__PLAN__/'"$PLAN"'/g' \
    -e 's/__TOKEN__/'"$TOKEN"'/g' \
    kustomization-template.yml > kustomization.yml

# Set kubeconfig and context variables if provided
KUBECONF=""
KUBECONTEXT=""
[[ -n "$KUBECONFIG_FILE" ]] && KUBECONF="KUBECONFIG=\"$KUBECONFIG_FILE\""
[[ -n "$K8S_CONTEXT" ]] && KUBECONTEXT="--context=\"$K8S_CONTEXT\""

eval $KUBECONF kubectl apply -k . $KUBECONTEXT
