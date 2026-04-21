# VuFind Extended

This repository provides a Docker image for VuFind with some extra
quality-of-life packages included.

## How to use

```bash
docker build \
    --build-arg VUFIND_VERSION="${VUFIND_VERSION}" \
    --tag vufind-extended:"${VUFIND_VERSION}" \
    .
```
