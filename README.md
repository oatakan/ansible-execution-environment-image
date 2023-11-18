# ansible-execution-environment-image
This repo contains a sample Ansible Execution Environment image build files

Use ansible-builder to build or github actions.

To build with ansible-builder:

pip install -r requirements.txt
ansible-builder build -v 3 --context=ansible-base-ee-dev --tag=ansible-base-ee-dev:latest
