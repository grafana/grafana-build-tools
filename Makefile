.DEFAULT_GOAL := build

S := @

ROOTDIR      := $(abspath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

IMAGE_REPO   := ghcr.io/grafana
IMAGE_NAME   := grafana-build-tools
IMAGE_TAG    ?= $(shell $(ROOTDIR)/scripts/image-tag)
IMAGE        := $(IMAGE_REPO)/$(IMAGE_NAME):$(IMAGE_TAG)
LATEST_IMAGE := $(IMAGE_REPO)/$(IMAGE_NAME):latest
LOCAL_IMAGE  := $(IMAGE_REPO)/$(IMAGE_NAME):local

LOCAL_ARCH   := $(strip $(shell $(ROOTDIR)/scripts/local-machine))

DOCKER_BUILDKIT ?= 1
export DOCKER_BUILDKIT

# All arches we build images for. Usually set by CI. Set this if you're building
# locally. Be aware if you drop an arch then the "latest" tag won't include it,
# so you will break users who are running that arch. Probably just don't push if
# you're running locally.
PUSH_ARCHES ?= $(LOCAL_ARCH)

##@ Development

BUILD_TARGETS :=

define build-target
.PHONY: build-$(1)
build-$(1): Dockerfile
build-$(1):
	@set -e
	docker build . -f Dockerfile -t "$(IMAGE)-$(1)"

BUILD_TARGETS += build-$(1)
endef

$(foreach BUILD_ARCH,$(PUSH_ARCHES),$(eval $(call build-target,$(BUILD_ARCH))))

.PHONY: build-local
build-local: Dockerfile
build-local:
	docker build . -f Dockerfile -t "$(LOCAL_IMAGE)"

BUILD_TARGETS += build-local

.PHONY: build
build: $(BUILD_TARGETS)
build: ## build the image
	@true

.PHONY: test
test: build-$(LOCAL_ARCH)
test: ## test the image
	$(S) docker run --rm $(IMAGE)-$(LOCAL_ARCH) image-test

# Run the image from the first of the PUSH_ARCHES, assuming it'll run on this
# machine since it was built here (this target depends on 'build')
.PHONY: shell
shell: build-$(LOCAL_ARCH)
shell: ## run the image in a container
	$(S) docker run -it --rm $(IMAGE)-$(LOCAL_ARCH) /bin/bash

##@ Publish

.PHONY: push-dev
push-dev: build test
push-dev: ## push the image to the registry
	$(S) for arch in $(PUSH_ARCHES); do \
		set -xe ; \
		docker push $(IMAGE)-$$arch ; \
	done

.PHONY: push
push: build test push-dev
push: ## tag latest and push the to the registry
	$(S) for arch in $(PUSH_ARCHES); do \
		set -xe ; \
		docker tag $(IMAGE)-$$arch $(LATEST_IMAGE)-$$arch ; \
		docker push $(LATEST_IMAGE)-$$arch ; \
	done

# Make ":latest" and ":version" manifests for all images.
#
# This doesn't have a dependency as it runs in a separate pipeline, but it does
# rely on the images having been built and pushed
.PHONY: push-manifest
push-manifest:
	$(S) for tag in "$(LATEST_IMAGE)" "$(IMAGE)"; do \
		set -xe ; \
		echo "Building manifest for $$tag" ; \
		docker manifest create --amend $$tag $(foreach arch,$(PUSH_ARCHES),$$tag-$(arch)) ; \
		docker manifest inspect $$tag ; \
		docker manifest push $$tag ; \
	done

Dockerfile: Dockerfile.tmpl versions.yaml
	$(S) docker run -i -v '/$(CURDIR)/versions.yaml:/data/versions.yaml' \
		hairyhenderson/gomplate --context 'data=file:///data/versions.yaml?type=application/yaml' < Dockerfile.tmpl > "$@"

##@ Helpers

.PHONY: image-prefix
image-prefix: ## print out the image prefix (registry and project)
	$(S) echo $(IMAGE_REPO)

.PHONY: image-name
image-name: ## print out the image name
	$(S) echo $(IMAGE_NAME)

# Print out the tag. If we're pushing multiple arches, assume this is the
# manifest (without version), otherwise the scheme is the version with the arch
# appended.
.PHONY: tag
tag: ## print out the tag
	$(S) if [ -z $(MULTI_ARCH) ] || [ $(N_ARCHES) -gt 1 ]; then \
		echo $(IMAGE_TAG) ;\
	else \
		echo $(IMAGE_TAG)-$(PUSH_ARCHES) ;\
	fi

.PHONY: help
help: ## display this help.
	$(S) awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
