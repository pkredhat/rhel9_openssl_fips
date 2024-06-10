# Pulls the shared Python utilities
FROM docker.repo.local.sfdc.net/sfci/docker-images/sfdc_rhel9_python3:48 AS python_builder
# use python 3.7 image as a conduit for extra dependencies without having to install gcc in our keycloak container. :-)
ENV REQUESTS_CA_BUNDLE=/etc/pki/tls/cert.pem
ENV PYTHONUSERBASE=/tmp/python-deps/build
COPY python-utils/requirements.txt /tmp/keycloak_requirements.txt
RUN dnf install -y gcc python-devel && pip3 install --user \
                 --index-url https://nexus-proxy.repo.local.sfdc.net/nexus/repository/pypi-all/simple \
                 --no-warn-script-location \
                 --no-cache-dir \
                 -r /tmp/keycloak_requirements.txt

FROM docker.repo.local.sfdc.net/sfci/docker-images/sfdc_rhel9:55 AS JDK

ENV HOME /home/keycloak
RUN mkdir -p ${HOME} && \
    groupadd -r keycloak --gid=7447 && useradd -r -g keycloak --uid=7447 keycloak -d ${HOME} && \
    chown keycloak:keycloak ${HOME}

# install additional repos and remaining packages
COPY --chown=root:root *.repo /etc/yum.repos.d/

RUN dnf --setopt=tsflags=nodocs install -y \
          python3 python3-pip \
          java-17-openjdk-headless \
          less \
          freeradius-utils \
          gettext \
          nmap-ncat \
          openssl \
          postgresql \
          rng-tools \
          xmlstarlet \
          which && \
    # following with SFCI team to understand where is the signed versions of
    # latest dynamic-keytool RPMs https://rpm.repo.local.sfdc.net/ui/native/rpm-prod/pki_service/7.
    # will update this once they clarify
    dnf --enablerepo=strata_pki_service install -y dynamic-keytool && \
    dnf clean all && \
    rm -rf /var/cache/yum/* && \
    find / -path '/proc/*' -prune -o -name *.whl  -exec rm {} \; && \
    pip3 install --upgrade pip && \
    pip3 install awscli

RUN mkdir -p /cache-dir && chown keycloak:keycloak /cache-dir
RUN mkdir -p /opt/quantumk && chown keycloak:keycloak /opt/quantumk
RUN mkdir -p /host/data/ && chown keycloak:keycloak /host/data
RUN mkdir -p /etc/identity/ca
RUN mkdir -p /etc/pki/ca-trust/source/anchors


##---
#ENV NODE_VERSION v8.11.0
ENV OPENSSL_FIPS_MODULE openssl-fips-2.0.12
ENV OPEN_SSL_CORE openssl-1.0.2h

ADD fips.sh /
RUN chmod 777 /fips.sh
RUN ./fips.sh

ADD test-fips.sh /
RUN chmod 777 /test-fips.sh && ./test-fips.sh


##---

# copy patched keycloak & classpath
COPY --chown=keycloak:keycloak maven/keycloak-package/target/keycloak/keycloak-* /opt/quantumk/keycloak/

# copy required Java agents
COPY --chown=keycloak:keycloak maven/quantumk-modules/target/java-agents/ /opt/quantumk/java-agents/

# copy our custom modules
COPY --chown=keycloak:keycloak maven/quantumk-modules/target/providers/* /opt/quantumk/keycloak/providers/

# copy deployments
COPY --chown=keycloak:keycloak lib/metrics-spi/keycloak-metrics-spi-4.0.0.jar /opt/quantumk/keycloak/providers
COPY --chown=keycloak:keycloak maven/quantumk-deployments/target/providers /opt/quantumk/keycloak/providers

# TODO: This should go away once a proper cert bundle is provided by PKI team
ENV AWS_COMBINED_CA_BUNDLE /opt/quantumk/certs/extra-certs/aws-combined-ca-bundle.pem
ENV AWS_COMBINED_CA_BUNDLE_VULCAN /opt/quantumk/certs/extra-certs/aws-combined-ca-bundle-vulcan.pem
COPY --chown=keycloak:keycloak aws-combined-ca-bundle.pem ${AWS_COMBINED_CA_BUNDLE}

# TODO: we are following with PKI to make sure they provide this bundle
# once PKI does that this should be removed
# https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html
COPY --chown=keycloak:keycloak aws-combined-ca-bundle-vulcan.pem ${AWS_COMBINED_CA_BUNDLE_VULCAN}

COPY --chown=keycloak:keycloak scripts/tools /opt/quantumk/tools
COPY --chown=keycloak:keycloak scripts/startup /opt/quantumk/startup-scripts

# We then copy the python code into the container
COPY --chown=keycloak:keycloak python-utils /opt/quantumk/python-utils
# this is a temporary ste until we migrate readiness and liveness probes to directly query keycloak.x endpoints
# as documented on this thread
# https://salesforce-internal.slack.com/archives/C02N1F4K23U/p1656537340294169
RUN ln -s /opt/quantumk/python-utils/probe.py probe.py

# Copy all python dependencies from earlier stage (including kst, protobuf and boto3 required by sp_importer)
COPY --from=python_builder --chown=keycloak:keycloak /tmp/python-deps/build /opt/quantumk/python-deps/

ENV APP_NAME keycloak
ENV APP_HOME /opt/quantumk/keycloak
ENV PYTHONUSERBASE /opt/quantumk/python-deps
ENV DEBUG_OPTS -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=8448
ENV JVM_OPTS -XX:MetaspaceSize=96M -XX:MaxMetaspaceSize=256m
ENV IPV4_OPTS -Djava.net.preferIPv4Stack=true -Djava.net.preferIPv4Addresses=true
ENV JAVA_OPTS $JVM_OPTS $IPV4_OPTS

ENV KEYCLOAK_IMPORT_DIR /tmp/keycloak/import
COPY --chown=keycloak:keycloak version.txt /tmp/version.txt

# Clean up temporary state
RUN rm -rf /opt/java
RUN ln -s /var/data/identity /root/.aws

COPY --chown=keycloak:keycloak config/dks/ /opt/quantumk/config/

EXPOSE 8080 8443 8448
ENTRYPOINT [ "/opt/quantumk/tools/docker-entrypoint.sh" ]
CMD ["-b", "0.0.0.0"]

# Drop privileges in order to avoid running as root
USER keycloak:keycloak

RUN /opt/quantumk/keycloak/bin/kc.sh build
