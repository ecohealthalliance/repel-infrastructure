ARG DOCKER_VERSION=19.03.1
ARG COMPOSE_VERSION=1.24.1
ARG GITCRYPT_VERSION=0.5.0-1
FROM docker:${DOCKER_VERSION}

RUN apk --update add \
   bash \
   curl \
   git \
   gcc \
   g++ \
   gnupg \
   make \
   openssh \
   openssl \
   openssl-dev \
   libc-dev \
   py-pip \
   python-dev \
   libffi-dev \
   && rm -rf /var/cache/apk/*

RUN pip install "docker-compose${COMPOSE_VERSION:+==}${COMPOSE_VERSION}"
RUN curl -L https://github.com/AGWA/git-crypt/archive/debian/$GITCRYPT_VERSION.tar.gz | tar zxv -C /var/tmp
RUN cd /var/tmp/git-crypt-debian && make && make install PREFIX=/usr/local && rm -rf /var/tmp/git-crypt-debian

