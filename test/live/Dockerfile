FROM shimaore/freeswitch
# Test install
USER root
RUN apt-get update && apt-get -y --no-install-recommends install \
  nodejs-legacy \
  npm
ADD src.tar /opt/test
COPY test/ /opt/test/test
RUN chown -R freeswitch.freeswitch /opt/test
USER freeswitch
WORKDIR /opt/test
RUN npm install
# FreeSwitch install
COPY conf/ /opt/freeswitch/conf
CMD ["/opt/freeswitch/bin/freeswitch","-nf","-nosql","-nonat","-nonatmap","-nocal","-nort","-c"]
EXPOSE 5062/udp 5062/tcp 8022/tcp
