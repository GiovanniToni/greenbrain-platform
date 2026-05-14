# GreenBrain Customer Local — Status and Roadmap 0.1.106

## Release

- Version: 0.1.106
- Tag: customer-local-0.1.106
- Bundle: /opt/greenbrain-platform/releases/customer-local/0.1.106/customer-local-0.1.106.tar.gz
- Universal installer: /opt/greenbrain-platform/releases/customer-local/0.1.106/GreenBrain-Installer.zip

## Milestone

0.1.106 is the first validated customer-local release with optional prebuilt Docker images from GHCR.

## GHCR images

- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.106
- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.106

Published digests:

- backend: sha256:50a9d94ff9b80ec48f95a5df3e7bf1fc9741ffae0c2e7546156243472723b915
- ml-worker: sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

## Package validation

Validated:

- docker-compose.prebuilt.yml is packaged
- docker-compose.prebuilt.yml has no build sections
- install.sh supports GREENBRAIN_USE_PREBUILT_IMAGES=1
- prebuilt install uses docker-compose.prebuilt.yml standalone
- no local backend/ml-worker build occurred during fresh prebuilt install

## Fresh prebuilt test

Fresh test path:

/tmp/gb_fresh_0106_prebuilt_20260514_220405/package/customer-local-template

Environment:

- GREENBRAIN_USE_PREBUILT_IMAGES=1
- GREENBRAIN_IMAGE_TAG=0.1.106
- GREENBRAIN_PROVISIONING_TOKEN=dev_test_token

Result:

- INSTALL COMPLETED
- VERSION 0.1.106
- package_version 0.1.106
- Backend healthy
- Frontend healthy
- backend image: ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.106
- doctor-local-extended.sh OK
- JWT consistency OK
- Source DB not configured, handled cleanly
- run-local-daily-once.sh OK
- pipeline raw->fact->dense->features OK
- train_missing rc=0
- predict_all rc=0
- central heartbeat healthy with local_agent_version 0.1.106

## Strategic result

The customer-local installer can now avoid the slow local backend/ml-worker Docker builds by pulling prebuilt images.

## Next roadmap

0.1.107:

- make prebuilt images the default install path
- keep local build fallback if prebuilt pull/start fails
- validate fresh install default path
- verify logs clearly report whether install used prebuilt or fallback build

0.1.108:

- test updated universal installer on real Windows client using default prebuilt path
- compare install time with 0.1.104 local build path

0.1.109+:

- improve image release automation
- add image digest metadata to release manifest
- optionally pin release to immutable image digests instead of mutable tags
