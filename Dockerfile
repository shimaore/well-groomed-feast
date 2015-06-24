FROM shimaore/freeswitch-with-sounds:2.2.2

MAINTAINER Stéphane Alnet <stephane@shimaore.net>

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  make \
  supervisor
# Install Node.js using `n`.
RUN git clone https://github.com/tj/n.git
WORKDIR n
RUN make install
WORKDIR ..
RUN n io 2.3.1
ENV NODE_ENV production

ENV install_dir /opt/well-groomed-feast
RUN mkdir -p ${install_dir}
WORKDIR ${install_dir}
COPY . ${install_dir}
RUN chown -R freeswitch.freeswitch ${install_dir}/
USER freeswitch
RUN mkdir -p \
  conf \
  log
RUN npm install && \
  cp node_modules/thinkable-ducks/supervisord.conf .

CMD ["supervisord","-n"]
