FROM ubuntu:20.04

ENV PACKER_VERSION=1.7.10
ENV PACKER_SHA256SUM=1c8c176dd30f3b9ec3b418f8cb37822261ccebdaf0b01d9b8abf60213d1205cb

ENV DEBIAN_FRONTEND noninteractive
ENV TARGETARCH=linux-x64

# Upgrade installed packages
RUN apt-get update && apt-get -y upgrade

# Install required dependencies
RUN apt-get -y install -qq --no-install-recommends \
    apt-transport-https \
    apt-utils \
    bash \
    ca-certificates \
    curl \
    git \
    iputils-ping \
    jq \
    lsb-release \
    software-properties-common \
    wget

# Download and run script that installs the Azure agent.
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Packer
ADD https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip ./
ADD https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_SHA256SUMS ./

RUN apt-get -y install zip unzip
RUN sed -i '/.*linux_amd64.zip/!d' packer_${PACKER_VERSION}_SHA256SUMS
RUN sha256sum -c packer_${PACKER_VERSION}_SHA256SUMS
RUN unzip packer_${PACKER_VERSION}_linux_amd64.zip -d /bin
RUN rm -f packer_${PACKER_VERSION}_linux_amd64.zip

RUN sudo apt-get install -y openssh-server && /etc/init.d/ssh start

# Install ansible
RUN apt-get -y install -qq --no-install-recommends \
  python3-pip \
  build-essential \
  libssl-dev \
  libffi-dev \
  python-dev \
  ansible \
  nano

WORKDIR /azp

# Add entrypoint script that manages the Azure agent
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

CMD [ "/azp/entrypoint.sh" ]