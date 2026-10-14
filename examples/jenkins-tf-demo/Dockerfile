# Jenkins image for the Terraform + Observability Agent demo.
# Extends Jenkins LTS with the tools the pipeline needs: terraform, aws cli, jq, openssl, curl.
# (The base jenkins/jenkins image has none of these.)
FROM jenkins/jenkins:lts-jdk17

USER root

# jq, curl, openssl, unzip, gnupg (unzip+gnupg needed to install terraform/awscli)
RUN apt-get update && apt-get install -y --no-install-recommends \
      jq curl openssl unzip gnupg ca-certificates lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Terraform (HashiCorp apt repo)
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
       > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y --no-install-recommends terraform \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 (arch-aware: works on amd64 and arm64)
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;; \
      arm64) url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "$url" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscliv2.zip

# Skip the setup wizard; admin user is created by init scripts.
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

RUN jenkins-plugin-cli --plugins \
    workflow-aggregator \
    credentials \
    plain-credentials \
    git

COPY init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

USER jenkins
