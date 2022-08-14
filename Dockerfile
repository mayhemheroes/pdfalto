#Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder

##Install Build Dependencies
RUN apt-get update && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y libfontconfig1-dev pkg-config autoconf sudo git wget cmake apt-utils build-essential

##ADD source code to the build stage
ADD . /pdfalto
WORKDIR /pdfalto
RUN git submodule update --recursive --remote
RUN ./install_deps.sh


##Build
RUN mkdir -p build
WORKDIR build
RUN cmake ..
RUN make -j$(nproc)

FROM --platform=linux/amd64 ubuntu:20.04
RUN apt-get update && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y libfontconfig1 libfreetype6 libexpat1 libuuid1 libpng16-16 zlib1g
COPY --from=builder /pdfalto/build/pdfalto /pdfalto
