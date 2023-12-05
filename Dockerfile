FROM registry.hub.docker.com/library/golang:1.21.3 as go-build

    COPY lib/go.env /usr/local/go

    RUN env GOBIN=/build go install github.com/google/go-jsonnet/cmd/jsonnet@v0.20.0
    RUN env GOBIN=/build go install github.com/google/go-jsonnet/cmd/jsonnetfmt@v0.20.0
    RUN env GOBIN=/build go install github.com/google/go-jsonnet/cmd/jsonnet-deps@v0.20.0
    RUN env GOBIN=/build go install github.com/google/go-jsonnet/cmd/jsonnet-lint@v0.20.0

    # The grafana/xk6 image only exists for amd64, so we need to build it for
    # the target architecture.
    RUN env GOBIN=/build go install go.k6.io/xk6/cmd/xk6@v0.9.2

    # The grafana/k6 image only exists for amd64, so we need to build it for
    # the architecture we are targeting. The simplest way to build k6 is to
    # (ab)use xk6 to build a binary without any extensions. In the future, if
    # we wanted additional extensions, this is the place to add them.
    RUN /build/xk6 build v0.46.0 --output /build/k6

    # Add wire
    RUN env GOBIN=/build go install github.com/google/wire/cmd/wire@v0.5.0

    # Add bingo
    RUN env GOBIN=/build go install github.com/bwplotka/bingo@v0.8.0

    # Add enumer
    RUN env GOBIN=/build go install github.com/dmarkham/enumer@v1.5.7

    # Add protoc-gen-go
    RUN env GOBIN=/build go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.31.0

    # Add protoc-gen-go-grpc
    RUN env GOBIN=/build go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.3.0

    # Add buf
    RUN env GOBIN=/build go install github.com/bufbuild/buf/cmd/buf@v1.26.1

    # Add mage
    RUN git clone --depth 1 --branch v1.15.0 https://github.com/magefile/mage mage && \
        cd mage && \
        env GOBIN=/build go run bootstrap.go

    # Add nilaway
    # This hasn't been released yet, so pin it to a specific version for reproducibility
    RUN env GOBIN=/build go install go.uber.org/nilaway/cmd/nilaway@v0.0.0-20231117175943-a267567c6fff

    # Add golangci-lint
    COPY --from=registry.hub.docker.com/golangci/golangci-lint:v1.55.2 /usr/bin/golangci-lint /build

    # Add shellcheck
    COPY --from=registry.hub.docker.com/koalaman/shellcheck:v0.9.0 /bin/shellcheck /build

    # Add git-chglog
    RUN env GOBIN=/build go install github.com/git-chglog/git-chglog/cmd/git-chglog@v0.15.4

FROM registry.hub.docker.com/library/debian:stable-slim as build

    COPY --from=go-build /usr/local/go /usr/local/go

    ENV PATH="/usr/local/go/bin:${PATH}"

    RUN apt-get update && \
        apt-get install -y \
        build-essential \
        libgpgme-dev \
        libassuan-dev \
        libdevmapper-dev \
        pkg-config \
        git

    # skopeo is used to inspect container registries. This can be used to
    # inspect the available versions without pulling the repos.
    RUN git clone https://github.com/containers/skopeo && \
        cd skopeo && \
        make GOBIN=/build DISABLE_DOCS=1 bin/skopeo && \
        mkdir -p /build && \
        cp bin/skopeo /build/

FROM registry.hub.docker.com/library/debian:stable-slim

    RUN apt-get update && \
        apt-get install -y \
            build-essential \
            docker.io \
            file \
            git \
            pkg-config \
            libgpgme11 \
            && \
        rm -rf /var/lib/apt/lists

    COPY --from=go-build /usr/local/go /usr/local/go
    ENV PATH="/usr/local/go/bin:${PATH}"

    # Keep tools in /usr/local/bin. That makes it a little bit easier to see
    # what comes from the image vs stuff coming from the base image.
    COPY --from=go-build /build/* /usr/local/bin/

    COPY lib/image-test /usr/local/bin
