FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV NDK_VERSION=r29b
ENV NDK=/github/build-nodejs/android-ndk-${NDK_VERSION}

WORKDIR /github/build-nodejs

# Install all dependencies in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl git unzip patch \
    python3 python3-pip \
    gcc g++ make \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Download and extract Android NDK
RUN wget -q "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip" \
  && unzip -q "android-ndk-${NDK_VERSION}-linux.zip" \
  && rm "android-ndk-${NDK_VERSION}-linux.zip"

COPY node-build.sh /github/build-nodejs/node-build.sh
COPY .github/scripts/ /github/build-nodejs/.github/scripts/
RUN chmod +x /github/build-nodejs/node-build.sh

VOLUME ["/output"]

ENTRYPOINT ["/github/build-nodejs/node-build.sh"]
