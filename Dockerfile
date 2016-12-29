FROM alpine:edge
MAINTAINER Lars Gierth <lgierth@ipfs.io>

# There is a copy of this Dockerfile called Dockerfile.fast,
# which is optimized for build time, instead of image size.
#
# Please keep these two Dockerfiles in sync.


# Ports for Swarm TCP, Swarm uTP, API, Gateway
EXPOSE 14001
EXPOSE 14002/udp
EXPOSE 15001
EXPOSE 18080

# Volume for mounting an IPFS fs-repo
# This is moved to the bottom for technical reasons.
#VOLUME $IOPCAN_PATH

# IPFS API to use for fetching gx packages.
# This can be a gateway too, since its read-only API provides all gx needs.
# - e.g. /ip4/172.17.0.1/tcp/18080 if the Docker host
#   has the IPFS gateway listening on the bridge interface
#   provided by Docker's default networking.
# - if empty, the public gateway at ipfs.io is used.
ENV GX_IPFS   ""
# The IPFS fs-repo within the container
ENV IOPCAN_PATH /data/ipfs
# The default logging level
ENV IPFS_LOGGING ""
# Golang stuff
ENV GOPATH     /go
ENV PATH       /go/bin:$PATH
ENV SRC_PATH   /go/src/github.com/ipfs/go-ipfs

# Get the go-ipfs sourcecode
COPY . $SRC_PATH

RUN apk add --update musl-dev gcc go git bash wget ca-certificates \
	# Setup user and fs-repo directory
	&& mkdir -p $IOPCAN_PATH \
	&& adduser -D -h $IOPCAN_PATH -u 1000 ipfs \
	&& chown ipfs:ipfs $IOPCAN_PATH && chmod 755 $IOPCAN_PATH \
	# Install gx
	&& go get -u github.com/whyrusleeping/gx \
	&& go get -u github.com/whyrusleeping/gx-go \
	# Point gx to a specific IPFS API
	&& ([ -z "$GX_IPFS" ] || echo $GX_IPFS > $IOPCAN_PATH/api) \
	# Invoke gx
	&& cd $SRC_PATH \
	&& gx --verbose install --global \
	&& mkdir .git/objects && commit=$(git rev-parse --short HEAD) \
	&& echo "ldflags=-X github.com/ipfs/go-ipfs/repo/config.CurrentCommit=$commit" \
	# Build and install IPFS and entrypoint script
	&& cd $SRC_PATH/cmd/ipfs \
	&& go build -ldflags "-X github.com/ipfs/go-ipfs/repo/config.CurrentCommit=$commit" \
	&& cp ipfs /usr/local/bin/ipfs \
	&& cp $SRC_PATH/bin/container_daemon /usr/local/bin/start_ipfs \
	&& chmod 755 /usr/local/bin/start_ipfs \
	# Remove all build-time dependencies
	&& apk del --purge musl-dev gcc go git && rm -rf $GOPATH && rm -vf $IOPCAN_PATH/api

# Call uid 1000 "ipfs"
USER ipfs

# Expose the fs-repo as a volume.
# We're doing this down here (and not at the top),
# so that the overlay directory is owned by the ipfs user.
# start_ipfs initializes an ephemeral fs-repo if none is mounted,
# which is why uid=1000 needs write permissions there.
VOLUME $IOPCAN_PATH

# This just makes sure that:
# 1. There's an fs-repo, and initializes one if there isn't.
# 2. The API and Gateway are accessible from outside the container.
ENTRYPOINT ["/usr/local/bin/start_ipfs"]
