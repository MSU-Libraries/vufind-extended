FROM ubuntu:24.04

ENV TZ=America/Detroit \
    DEBIAN_FRONTEND=noninteractive \
    VUFIND_LOCAL_DIR=/usr/local/vufind/local \
    VUFIND_HOME=/usr/local/vufind \
    JAVA_HOME=/usr/lib/jvm/default-java \
    VUFIND_CACHE_DIR=/mnt/vufind_cache

# TEMP(PART1):
# - Patch and replace solrmarc due to delete logic hardcode to MARC 001 as id instead of .properties defined id
COPY patches/ /tmp/patches/
# END TEMP(PART1)
RUN \
    # Perform updates
    apt-get update && \
    apt-get install -y wget vim-nox lsof apache2 xml-twig-tools curl cron rsyslog jq htop moreutils \
        gettext-base locales msmtp-mta rsync screen libxml-xpath-perl xmlstarlet php-xdebug \
        nodejs npm git pigz libxml2-utils libmarc-xml-perl bash-completion gawk \
        # VuFind dependencies; modified to not include php-dev, mysql-server, or Java JDK (using JRE instead) \
        # We can switch back to default-jre-headless (openjdk-21-jre-headless) instead of openjdk-17-jre-headless \
        # when we remove the patches for marc4j & solrmarc
        mysql-client openjdk-17-jre-headless apache2 libapache2-mod-php php-pear php \
        php-curl php-gd php-intl php-json php-ldap php-mbstring php-mysql php-soap php-xml \
        libapache2-mod-security2 modsecurity-crs uuid-runtime libsaxonhe-java && \
    # We can remove the following line when switching back to default-jre-headless
    cd /usr/lib/jvm && ln -s java-17-openjdk-amd64 default-java && \
    # TEMP(PART2):
    # - Replace marc4j due to linked field bug https://github.com/marc4j/marc4j/pull/100
    # - Patch and replace solrmarc due to delete logic hardcode to MARC 001 as id instead of .properties defined id
    apt-get install -y ant && \
    git clone --depth 1 --branch 2.9.6 https://github.com/marc4j/marc4j.git /tmp/marc4j && \
    cd /tmp/marc4j/ && \
    ant jar && \
    git clone --depth 1 --branch 3.5 https://github.com/solrmarc/solrmarc.git /tmp/solrmarc && \
    cd /tmp/solrmarc/ && \
    git apply /tmp/patches/solrmarc_delete_on_docid.patch && \
    ant package && \
    rm -r /tmp/patches && \
    apt-get purge -y ant && \
    # END TEMP(PART2)
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG VUFIND_VERSION
ENV VUFIND_VERSION=$VUFIND_VERSION

COPY install-composer.sh /install-composer.sh

RUN \
    # Setup Timezone
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    # Install Composer
    /install-composer.sh && \
    mv /composer.phar /usr/local/bin/composer && \
    rm /install-composer.sh && \
    # Clone VuFind
    git clone --branch "v${VUFIND_VERSION}" --depth 1 https://github.com/vufind-org/vufind.git /usr/local/vufind && \
    # Install VuFind dependencies
    composer --working-dir=/usr/local/vufind/ config audit.block-insecure false && \
    composer --working-dir=/usr/local/vufind/ update && \
    # Remove unused Solr dependencies after Vufind is installed
    mv /usr/local/vufind/solr /tmp && \
    mkdir -p /usr/local/vufind/solr/vendor/modules/analysis-extras /usr/local/vufind/solr/vendor/server/solr-webapp/webapp/WEB-INF && \
    mv /tmp/solr/vendor/modules/analysis-extras/lib /usr/local/vufind/solr/vendor/modules/analysis-extras && \
    mv /tmp/solr/vendor/server/solr-webapp/webapp/WEB-INF/lib/ /usr/local/vufind/solr/vendor/server/solr-webapp/webapp/WEB-INF && \
    rm -rf /tmp/solr && \
    # Fix world writable vendor dirs (TODO find out why these happen in the first place)
    find /usr/local/vufind/vendor -type d -perm -o+w -exec chmod o-w \; && \
    # File ownership of node directory
    mkdir -p /usr/local/vufind/node_modules && \
    touch /usr/local/vufind/package-lock.json && \
    chown -R 1000:1000 /usr/local/vufind/node_modules /usr/local/vufind/package-lock.json && \
    # Enable bash completion for all users
    echo ". /usr/share/bash-completion/bash_completion" >> /etc/bash.bashrc

# TEMP(PART3):
# - Replace marc4j due to linked field bug https://github.com/marc4j/marc4j/pull/100
# - Patch and replace solrmarc due to delete logic hardcode to MARC 001 as id instead of .properties defined id
RUN \
    rm /usr/local/vufind/import/lib/marc4j*.jar && \
    mv /tmp/marc4j/build/marc4j*.jar /usr/local/vufind/import/lib/ && \
    rm -r /tmp/marc4j/ && \
    rm /usr/local/vufind/import/solrmarc_core_3.5.jar && \
    mv /tmp/solrmarc/dist/solrmarc_core_*.jar /usr/local/vufind/import/solrmarc_core_3.5.jar && \
    rm -r /tmp/solrmarc/
# END TEMP(PART3)

# User configs for root
COPY .vimrc /root/.vimrc

USER 1000

# Install requirements for grunt
RUN cd /usr/local/vufind && \
    npm install

USER 0
EXPOSE 80
CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
