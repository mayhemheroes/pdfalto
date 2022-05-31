#Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder

##Install Build Dependencies
RUN apt-get update && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y libfontconfig1-dev pkg-config autoconf sudo git wget cmake apt-utils build-essential

##ADD source code to the build stage
WORKDIR /
ADD https://api.github.com/repos/ennamarie19/pdfalto/git/refs/heads/mayhem version.json
RUN git clone -b mayhem https://github.com/ennamarie19/pdfalto.git
WORKDIR /pdfalto
RUN git submodule update --init --recursive
RUN ./install_deps.sh


##Build
RUN mkdir -p build
WORKDIR build
RUN cmake ..
RUN make -j$(nproc)

##Prepare all library dependencies for copy
RUN mkdir /deps
RUN cp `ldd ./pdfalto | grep so | sed -e '/^[^\t]/ d' | sed -e 's/\t//' | sed -e 's/.*=..//' | sed -e 's/ (0.*)//' | sort | uniq` /deps 2>/dev/null || : 

FROM --platform=linux/amd64 ubuntu:20.04
COPY --from=builder /pdfalto/build/pdfalto /pdfalto
COPY --from=builder /deps /usr/lib
#copy from deps on old system to usrLib on new system

CMD ["/pdfalto", "@@"]

