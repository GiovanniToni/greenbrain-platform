# GreenBrain Customer Local — Status and Roadmap 0.1.107

## Release

- Version: 0.1.107
- Tag: customer-local-0.1.107
- Bundle: /opt/greenbrain-platform/releases/customer-local/0.1.107/customer-local-0.1.107.tar.gz
- Universal installer: /opt/greenbrain-platform/releases/customer-local/0.1.107/GreenBrain-Installer.zip

## Milestone

0.1.107 is the first validated release where the default customer install path uses prebuilt Docker images from GHCR.

The installer now defaults to:

- GREENBRAIN_USE_PREBUILT_IMAGES=1
- docker-compose.prebuilt.yml
- no local backend/ml-worker build during normal install
- automatic fallback to docker-compose.local.yml up -d --build if prebuilt startup fails

## GHCR images

- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.107
- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.107

Published digests:

- backend: sha256:50a9d94ff9b80ec48f95a5df3e7bf1fc9741ffae0c2e7546156243472723b915
- ml-worker: sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

## Package validation

Validated:

- docker-compose.prebuilt.yml is packaged
- docker-compose.prebuilt.yml has no build sections
- install.sh defaults GREENBRAIN_USE_PREBUILT_IMAGES to 1
- install.sh uses docker-compose.prebuilt.yml standalone
- install.sh falls back to local build if prebuilt startup fails
- package VERSION and package_version are 0.1.107

## Fresh default-prebuilt test

Fresh test path:

/tmp/gb_fresh_0107_prebuilt_default_20260514_222753/package/customer-local-template

Environment:

- GREENBRAIN_IMAGE_TAG=0.1.107
- GREENBRAIN_PROVISIONING_TOKEN=dev_test_token
- GREENBRAIN_CONFIGURE_SOURCE_DB=no
- GREENBRAIN_USE_PREBUILT_IMAGES was unset

Result:

- installer printed: Using prebuilt Docker images
- no local backend/ml-worker build occurred
- backend image: ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.107
- VERSION: 0.1.107
- package_version: 0.1.107
- backend healthy
- frontend healthy
- extended doctor OK
- DB checks OK
- ML worker import smoke OK
- JWT SSO consistency OK
- Source DB not configured, handled correctly
- run-local-daily-once OK
- train_missing OK
- predict_all OK
- heartbeat central healthy

Heartbeat installation id:

e3f13fe4-8a5a-4534-ba89-484d21088bfd

## Current strategic status

GreenBrain customer-local can now be installed with a much faster default path because backend and ml-worker are pulled from GHCR instead of being built locally.

The local build path remains available as fallback.

## Next roadmap

1. Test 0.1.107 universal installer on the real Windows customer PC.
2. Confirm install speed improvement compared to 0.1.104 local-build Windows install.
3. Add clearer installer messages showing whether images are being pulled or local build fallback is active.
4. Consider pre-pull step with explicit diagnostics before docker compose up.
5. Later: automate GHCR image build/push in the release pipeline.
