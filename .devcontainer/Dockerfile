# Use Fedora 39 as the base image
FROM fedora:39

# Install Java OpenJDK, python3-pip, and ansible
RUN dnf --assumeyes install git python3-pip && \
    pip3 install ansible ansible-builder