# ansible-execution-environment-image
This repo contains a sample Ansible Execution Environment image build files

## Build the image locally

First, [install ansible-builder](https://ansible-builder.readthedocs.io/en/stable/installation/).

Then run the following command from the root of this repo:

```bash
$ ansible-builder build -v3 -t username/ansible-execution-environment-image:dev # --container-runtime=docker # Is podman by default
```
