ARG EE_BASE_IMAGE="quay.io/centos/centos:stream9"
ARG PYCMD="/usr/bin/python3"
ARG PKGMGR_PRESERVE_CACHE=""
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS=""
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS=""
ARG ANSIBLE_INSTALL_REFS="ansible-core>=2.16,<2.17 ansible-runner"
ARG PKGMGR="/usr/bin/dnf"

# Base build stage
FROM $EE_BASE_IMAGE AS base
USER root
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ARG EE_BASE_IMAGE
ARG PYCMD
ARG PKGMGR_PRESERVE_CACHE
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS
ARG ANSIBLE_INSTALL_REFS
ARG PKGMGR

COPY _build/scripts/ /output/scripts/
COPY _build/scripts/entrypoint /opt/builder/bin/entrypoint
RUN dnf update -y
RUN dnf install -y python3.12 python3.12-devel python3.12-pip python3.12-setuptools python3.12-wheel
RUN alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1
RUN alternatives --set python3 /usr/bin/python3.12
RUN alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip3.12 1
RUN alternatives --set pip3 /usr/bin/pip3.12
RUN /output/scripts/pip_install $PYCMD
RUN $PYCMD -m pip install --no-cache-dir $ANSIBLE_INSTALL_REFS
RUN $PYCMD -m pip install --upgrade pip setuptools wheel
RUN if [ "$(uname -m)" = "aarch64" ]; then $PYCMD -m pip install msgraph_sdk; fi
RUN dnf install -y epel-release
RUN dnf install -y dnf-plugins-core
RUN dnf config-manager --set-enabled crb
RUN dnf install -y nfs-utils fuse fuse-devel libnfs libnfs-devel gcc git make automake autoconf libtool
RUN git clone https://github.com/sahlberg/fuse-nfs.git && cd fuse-nfs && ./setup.sh && ./configure && make && make install
RUN dnf install -y python3.12-devel

# Galaxy build stage
FROM base AS galaxy
ARG EE_BASE_IMAGE
ARG PYCMD
ARG PKGMGR_PRESERVE_CACHE
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS
ARG ANSIBLE_INSTALL_REFS
ARG PKGMGR

RUN /output/scripts/check_galaxy
COPY _build /build
WORKDIR /build

RUN mkdir -p /usr/share/ansible
RUN ansible-galaxy role install $ANSIBLE_GALAXY_CLI_ROLE_OPTS -r requirements.yml --roles-path "/usr/share/ansible/roles"
RUN ANSIBLE_GALAXY_DISABLE_GPG_VERIFY=1 ansible-galaxy collection install $ANSIBLE_GALAXY_CLI_COLLECTION_OPTS -r requirements.yml --collections-path "/usr/share/ansible/collections"

# Builder build stage
FROM base AS builder
ENV PIP_BREAK_SYSTEM_PACKAGES=1
WORKDIR /build
ARG EE_BASE_IMAGE
ARG PYCMD
ARG PKGMGR_PRESERVE_CACHE
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS
ARG ANSIBLE_INSTALL_REFS
ARG PKGMGR

RUN $PYCMD -m pip install --no-cache-dir bindep pyyaml packaging

COPY --from=galaxy /usr/share/ansible /usr/share/ansible

COPY _build/requirements.txt requirements.txt
COPY _build/bindep.txt bindep.txt
RUN $PYCMD /output/scripts/introspect.py introspect --user-pip=requirements.txt --user-bindep=bindep.txt --write-bindep=/tmp/src/bindep.txt --write-pip=/tmp/src/requirements.txt
RUN /output/scripts/assemble

# Final build stage
FROM base AS final
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ARG EE_BASE_IMAGE
ARG PYCMD
ARG PKGMGR_PRESERVE_CACHE
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS
ARG ANSIBLE_INSTALL_REFS
ARG PKGMGR

RUN /output/scripts/check_ansible $PYCMD

COPY --from=galaxy /usr/share/ansible /usr/share/ansible

COPY --from=builder /output/ /output/
RUN /output/scripts/install-from-bindep && rm -rf /output/wheels
RUN chmod ug+rw /etc/passwd
RUN mkdir -p /runner && chgrp 0 /runner && chmod -R ug+rwx /runner
WORKDIR /runner
RUN $PYCMD -m pip install --no-cache-dir 'dumb-init==1.2.5'
COPY --from=quay.io/ansible/receptor:devel /usr/bin/receptor /usr/bin/receptor
RUN mkdir -p /var/run/receptor
RUN git lfs install --system
RUN /usr/bin/python3.12 -m pip uninstall ansible-runner -y && /usr/bin/python3.12 -m pip install git+https://github.com/ansible/ansible-runner.git
RUN dnf install -y https://dl.fedoraproject.org/pub/fedora/linux/releases/41/Everything/$(arch)/os/Packages/c/chntpw-1.00-18.140201.fc41.$(arch).rpm
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh
RUN rm -rf /output
LABEL ansible-execution-environment=true
USER 1000
ENTRYPOINT ["/opt/builder/bin/entrypoint", "dumb-init"]
CMD ["bash"]
