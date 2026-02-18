FROM registry.access.redhat.com/ubi9/ubi-minimal:9.3

ARG KUBECONFORM_VERSION=0.6.4
ARG PLUTO_VERSION=5.19.4
ARG KUBE_LINTER_VERSION=0.6.8
ARG KYVERNO_VERSION=1.12.3
ARG YQ_VERSION=4.40.5

# Install required packages
RUN microdnf install -y \
    git \
    openssh-clients \
    tar \
    gzip \
    jq \
    findutils \
    && microdnf clean all

# Install kubeconform (arm64)
RUN curl -sL https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-arm64.tar.gz \
    | tar xz -C /usr/local/bin kubeconform

# Install pluto (arm64)
RUN curl -sL https://github.com/FairwindsOps/pluto/releases/download/v${PLUTO_VERSION}/pluto_${PLUTO_VERSION}_linux_arm64.tar.gz \
    | tar xz -C /usr/local/bin pluto

# Install kube-linter (arm64)
RUN curl -sL https://github.com/stackrox/kube-linter/releases/download/v${KUBE_LINTER_VERSION}/kube-linter-linux_arm64.tar.gz \
    | tar xz -C /usr/local/bin

# Install kyverno CLI (arm64)
RUN curl -sL https://github.com/kyverno/kyverno/releases/download/v${KYVERNO_VERSION}/kyverno-cli_v${KYVERNO_VERSION}_linux_arm64.tar.gz \
    | tar xz -C /usr/local/bin kyverno

# Install yq for YAML manipulation (arm64)
RUN curl -sL https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_arm64 \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# Create argocd user (UID 999 required by ArgoCD CMP)
RUN useradd -u 999 -g 0 -d /home/argocd argocd

# Create directory structure
RUN mkdir -p /home/argocd/cmp-server/config \
    /home/argocd/scripts \
    /home/argocd/policies \
    /home/argocd/config \
    /home/argocd/.ssh \
    && chown -R 999:0 /home/argocd \
    && chmod 700 /home/argocd/.ssh

# Copy scripts and policies
COPY scripts/ /home/argocd/scripts/
COPY policies/ /home/argocd/policies/
COPY config/ /home/argocd/config/
COPY plugin.yaml /home/argocd/cmp-server/config/plugin.yaml

# Set permissions
RUN chmod +x /home/argocd/scripts/*.sh \
    && chown -R 999:0 /home/argocd

USER 999
WORKDIR /home/argocd

# CMP server entrypoint is provided at runtime via volume mount
