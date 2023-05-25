ARG EE_BASE_IMAGE=quay.io/ansible/ansible-runner:latest
ARG EE_BUILDER_IMAGE=quay.io/ansible/ansible-builder:latest

FROM $EE_BASE_IMAGE as galaxy
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS=
USER root

WORKDIR /build

ADD requirements.yml /build/requirements.yml
RUN ansible-galaxy role install -r requirements.yml --roles-path /usr/share/ansible/roles
RUN ansible-galaxy collection install $ANSIBLE_GALAXY_CLI_COLLECTION_OPTS -r requirements.yml --collections-path /usr/share/ansible/collections

FROM $EE_BUILDER_IMAGE as builder

COPY --from=galaxy /usr/share/ansible /usr/share/ansible

WORKDIR /build

ADD requirements.txt /build/requirements.txt
ADD bindep.txt /build/bindep.txt
RUN ansible-builder introspect --sanitize --user-pip=requirements.txt --user-bindep=bindep.txt --write-bindep=/tmp/src/bindep.txt --write-pip=/tmp/src/requirements.txt
RUN assemble

FROM $EE_BASE_IMAGE
USER root

COPY --from=galaxy /usr/share/ansible /usr/share/ansible

COPY --from=builder /output/ /output/
RUN /output/install-from-bindep && rm -rf /output/wheels
RUN alternatives --set python /usr/bin/python3
COPY --from=quay.io/project-receptor/receptor:latest /usr/bin/receptor /usr/bin/receptor
RUN mkdir -p /var/run/receptor
RUN pip uninstall ansible-runner -y && pip install git+https://github.com/ansible/ansible-runner.git@2.3.2#egg=ansible-runner
RUN pip uninstall urllib3 requests -y && pip install urllib3 requests
RUN pip uninstall pyOpenSSL cryptography -y && pip install pyOpenSSL>22.1.0

RUN cp /usr/local/share/ansible-runner/utils/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod 755 /usr/local/bin/entrypoint

ENTRYPOINT ["entrypoint"]

# NB: this appears to be necessary for container builds based on this container, since we can't rely on the entrypoint
# script to run during a build to fix up /etc/passwd. This envvar value, and the fact that all user homedirs are
# set to /home/runner is an implementation detail that may change with future versions of runner and should not be
# assumed by other code or tools.
ENV HOME=/home/runner