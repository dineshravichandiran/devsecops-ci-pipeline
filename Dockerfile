FROM tomcat:9.0-jdk17-temurin AS runtime

LABEL maintainer="devsecops-demo"

# Remove default sample apps to shrink attack surface
RUN rm -rf /usr/local/tomcat/webapps/ROOT \
    /usr/local/tomcat/webapps/examples \
    /usr/local/tomcat/webapps/docs \
    /usr/local/tomcat/webapps/manager \
    /usr/local/tomcat/webapps/host-manager

# Run as non-root
RUN groupadd -r appuser && useradd -r -g appuser appuser
COPY --chown=appuser:appuser build/app.war /usr/local/tomcat/webapps/ROOT.war

USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD curl -f http://localhost:8080/ || exit 1

CMD ["catalina.sh", "run"]
