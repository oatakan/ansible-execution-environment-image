# ansible-execution-environment-image
This repo contains a sample Ansible Execution Environment image build files

You can build with docker or podman:

*podman build -f context/Dockerfile -t user/ansible-ee-image .*

Run built image:

*podman run -it --rm user/ansible-ee-image /bin/bash*
