# ref: https://hub.docker.com/_/ubuntu
FROM ubuntu:18.04 AS env

#############
##  SETUP  ##
#############
RUN apt update -qq \
&& apt install -yq git wget build-essential lsb-release zlib1g-dev \
&& apt clean \
&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# GCC 11
RUN apt update -qq \
&& apt install -yq software-properties-common \
&& add-apt-repository -y ppa:ubuntu-toolchain-r/test \
&& apt install -yq gcc-11 g++-11 \
&& apt clean \
&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
ENV CC=gcc-11 CXX=g++-11
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/bin/bash"]

# Install CMake 3.21.1
RUN ARCH=$(uname -m) \
&& wget -q "https://cmake.org/files/v3.21/cmake-3.21.1-linux-${ARCH}.sh" \
&& chmod a+x cmake-3.21.1-linux-${ARCH}.sh \
&& ./cmake-3.21.1-linux-${ARCH}.sh --prefix=/usr/local/ --skip-license \
&& rm cmake-3.21.1-linux-${ARCH}.sh

# Swig Install
RUN apt-get update -qq \
&& apt-get install -yq swig \
&& apt-get clean \
&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Java install (openjdk-11)
RUN apt-get update -qq \
&& apt-get install -yq default-jdk maven \
&& apt-get clean \
&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
ENV JAVA_HOME=/usr/lib/jvm/default-java

# Dotnet Install
# see: https://docs.microsoft.com/en-us/dotnet/core/install/linux-ubuntu#1804-
RUN apt-get update -qq \
&& apt-get install -yq apt-transport-https \
&& wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb \
&& dpkg -i packages-microsoft-prod.deb \
&& apt-get update -qq \
&& apt-get install -yq dotnet-sdk-3.1 dotnet-sdk-6.0 \
&& apt-get clean \
&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
# Trigger first run experience by running arbitrary cmd
RUN dotnet --info

ENV TZ=America/Los_Angeles
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

################
##  OR-TOOLS  ##
################
FROM env AS devel
WORKDIR /root
# Copy the snk key
COPY or-tools.snk /root/or-tools.snk
ENV DOTNET_SNK=/root/or-tools.snk

ARG SRC_GIT_BRANCH
ENV SRC_GIT_BRANCH ${SRC_GIT_BRANCH:-main}
ARG SRC_GIT_SHA1
ENV SRC_GIT_SHA1 ${SRC_GIT_SHA1:-unknown}

# Download sources
# use SRC_GIT_SHA1 to modify the command
# i.e. avoid docker reusing the cache when new commit is pushed
RUN git clone -b "${SRC_GIT_BRANCH}" --single-branch https://github.com/google/or-tools \
&& echo "sha1: $(cd or-tools && git rev-parse --verify HEAD)" \
&& echo "expected sha1: ${SRC_GIT_SHA1}"
WORKDIR /root/or-tools

# C++
## build
FROM devel AS cpp_build
RUN make detect_cpp \
&& make cpp JOBS=4
## archive
FROM cpp_build AS cpp_archive
RUN make archive_cpp

# .Net
## build
FROM cpp_build AS dotnet_build
RUN make detect_dotnet \
&& make dotnet JOBS=4
## archive
FROM dotnet_build AS dotnet_archive
RUN make archive_dotnet

# Java
## build
FROM cpp_build AS java_build
RUN make detect_java \
&& make java JOBS=4
## archive
FROM java_build AS java_archive
RUN make archive_java

# Python
## build
FROM cpp_build AS python_build
RUN make detect_python \
&& make python JOBS=4
## archive
FROM python_build AS python_archive
RUN make archive_python
