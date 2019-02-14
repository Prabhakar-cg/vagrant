FROM centos:7
RUN mkdir -p /opt/nexus
COPY nexus-2.14.8-01-bundle.tar.gz /opt/nexus
RUN tar -xf /opt/nexus/nexus-2.14.8-01-bundle.tar.gz -C /opt/nexus
RUN rm -rf /opt/nexus/nexus-2.14.8-01-bundle.tar.gz
RUN useradd nexus
RUN chown -R nexus.nexus /opt/nexus
RUN yum install java -y
ENTRYPOINT ["su", "nexus", "-c", "/opt/nexus/nexus-2.14.8-01/bin/nexus console"]
EXPOSE 8081
