FROM fedora:34

#ENV NODE_VERSION v8.11.0
ENV OPENSSL_FIPS_MODULE openssl-fips-2.0.12
ENV OPEN_SSL_CORE openssl-1.0.2h

ADD fips.sh /
RUN chmod 777 /fips.sh
RUN ./fips.sh

ADD test-fips.sh /
RUN chmod 777 /test-fips.sh && ./test-fips.sh

CMD ["/bin/bash"]
