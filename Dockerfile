#
# Cartodb container
#
FROM ubuntu:18.04
LABEL maintainer="Stefan Verhoeven <s.verhoeven@esciencecenter.nl>"

# Configuring locales
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get install -y -q apt-utils software-properties-common locales && dpkg-reconfigure locales && \
      locale-gen en_US.UTF-8 && \
      update-locale LANG=en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

#ENV CARTODB_VERSION=v4.11.152
#ENV CARTODB_VERSION=v4.12.9
#ENV CARTODB_VERSION=v4.12.26
#ENV CARTODB_VERSION=v4.12.30
ENV CARTODB_VERSION=master
#ENV SQLAPI_VERSION=1.47.2
ENV SQLAPI_VERSION=master
#ENV CRANKSHAFT_VERSION=0.8.1
ENV CRANKSHAFT_VERSION=master
#ENV WINDSHAFT_VERSION=5.4.0
ENV WINDSHAFT_VERSION=master
#ENV DATASERVICES_VERSION=0.0.2
ENV DATASERVICES_VERSION=master
#ENV DATAERVICESAPI_VERSION=0.30.5-server
ENV DATAERVICESAPI_VERSION=master
#ENV OBSERVATORY_VERSION=1.9.0
ENV OBSERVATORY_VERSION=master
# Added for httpd production setup, TODO: add switch to turn on/off
ENV RAILS_ENV=production

RUN useradd -m -d /home/cartodb -s /bin/bash cartodb && \
  apt-get install -y -q \
    build-essential \
    autoconf \
    automake \
    libtool \
    checkinstall \
    unp \
    zip \
    unzip \
    git-core \
    git \
    subversion \
    curl \
    libgeos-c1v5 \
    libgeos-dev \
    libjson-c-dev \
    python-simplejson \
    proj-bin \
    proj-data \
    libproj-dev \
    gdal-bin \
    libgdal-dev \
    postgresql-10 \
    postgresql-client-10 \
    postgresql-contrib-10 \
    postgresql-server-dev-10 \
    postgresql-plpython-10 \
    postgresql-10-plproxy \
    postgresql-10-postgis-2.4 \
    postgresql-10-postgis-scripts \
    postgis \
    liblwgeom-2.4-0 \
    ca-certificates \
    redis-server \
    python2.7-dev \
    python-setuptools \
    imagemagick \
    libmapnik-dev \
    mapnik-utils \
    python-mapnik \
    python-argparse \
    python-gdal \
    python-chardet \
    python-all-dev \
    python-docutils \
    openssl \
    libreadline7 \
    zlib1g \
    zlib1g-dev \
    libssl-dev \
    libyaml-dev \
    libsqlite3-dev \
    sqlite3 \
    libxml2-dev \
    libxslt-dev \
    libc6-dev \
    ncurses-dev \
    bison \
    pkg-config \
    libpq5 \
    libpq-dev \
    libcurl4-gnutls-dev \
    libffi-dev \
    libgdbm-dev \
    gnupg \
    libreadline6-dev \
    libcairo2-dev \
    libjpeg8-dev \
    libpango1.0-dev \
    libgif-dev \
    libgmp-dev \
    libicu-dev \
    wget \
    nginx-light \
    net-tools \
    ruby2.5-dev \
    xz-utils \
  --no-install-recommends && \
  rm -rf /var/lib/apt/lists/*

RUN git config --global user.email you@example.com
RUN git config --global user.name "Your Name"

# Varnish 3, Ubuntu:18.04 comes with Varnish 5.1 which can't be run with anonymous admin telnet
RUN cd /opt && \
    wget http://varnish-cache.org/_downloads/varnish-3.0.7.tgz && \
    tar -zxf varnish-3.0.7.tgz && \
    cd varnish-3.0.7 && \
    ./configure --prefix=/opt/varnish && \
    make && \
    make install && \
    cd /opt && \
    rm -rf varnish-3.0.7 varnish-3.0.7.tgz

# Install NodeJS
RUN curl https://nodejs.org/dist/v10.15.3/node-v10.15.3-linux-x64.tar.xz |tar -Jxf - --strip-components=1 -C /usr && \
  npm install -g grunt-cli && \
  npm install -g npm@6 && \
  rm -r /tmp/npm-* /root/.npm

# Setting PostgreSQL
# TODO: add listen command here for production setup (e.g. sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/10/main/postgresql.conf && \)
RUN sed -i 's/\(peer\|md5\)/trust/' /etc/postgresql/10/main/pg_hba.conf && \
    service postgresql start && \
    createuser publicuser --no-createrole --no-createdb --no-superuser -U postgres && \
    createuser tileuser --no-createrole --no-createdb --no-superuser -U postgres && \
    service postgresql stop

# Crankshaft: CARTO Spatial Analysis extension for PostgreSQL
RUN cd / && \
    curl https://bootstrap.pypa.io/get-pip.py | python && \
    git clone https://github.com/CartoDB/crankshaft.git && \
    cd /crankshaft && \
    git checkout $CRANKSHAFT_VERSION && \
    make install && \
    # Numpy gets upgraded after scikit-learn is installed
    # make sure scikit-learn is compatible with currently installed numpy, by reinstalling
    pip install --force-reinstall --no-cache-dir scikit-learn==0.17.0 && \
    cd ..

# Initialize template postgis db
ADD ./template_postgis.sh /tmp/template_postgis.sh
RUN service postgresql start && /bin/su postgres -c \
      /tmp/template_postgis.sh && service postgresql stop

ADD ./cartodb_pgsql.sh /tmp/cartodb_pgsql.sh

# Install CartoDB API
RUN git clone git://github.com/CartoDB/CartoDB-SQL-API.git && \
    cd CartoDB-SQL-API && \
    git checkout $SQLAPI_VERSION && \
    npm install

# Install Windshaft
RUN git clone git://github.com/CartoDB/Windshaft-cartodb.git && \
    cd Windshaft-cartodb && \
    git checkout $WINDSHAFT_VERSION && \
    npm install && \
    mkdir logs

# Install CartoDB
RUN git clone --recursive git://github.com/CartoDB/cartodb.git && \
    cd cartodb && \
    git checkout $CARTODB_VERSION && \
    # Install cartodb extension
    cd lib/sql && \
    PGUSER=postgres make install && \
    service postgresql start && /bin/su postgres -c \
      /tmp/cartodb_pgsql.sh && service postgresql stop && \
    cd - && \
    npm install && \
    rm -r /tmp/npm-* /root/.npm && \
    perl -pi -e 's/gdal==1\.10\.0/gdal==2.2.2/' python_requirements.txt && \
    pip install --no-binary :all: -r python_requirements.txt && \
    gem install bundler --version=1.17.3 && gem install compass archive-tar-minitar rack && \
    bundle update thin && \
    /bin/bash -l -c 'bundle install' && \
    cp config/grunt_development.json ./config/grunt_true.json && \
    /bin/bash -l -c 'bundle exec grunt'
    # && \
    #rm -rf .git /root/.cache/pip node_modules

# Geocoder SQL client + server
RUN git clone https://github.com/CartoDB/data-services.git && \
  cd /data-services/geocoder/extension && \
  git checkout $DATASERVICES_VERSION && \
  PGUSER=postgres make all install && cd / && \
  git clone https://github.com/CartoDB/dataservices-api.git && \
  cd /dataservices-api/server/extension && \
  git checkout $DATAERVICESAPI_VERSION && \
  PGUSER=postgres make install && \
  cd ../lib/python/cartodb_services && \
  pip install -r requirements.txt && pip install . && \
  cd ../../../../client && PGUSER=postgres make install

# Observatory extension
RUN cd / && git clone --recursive https://github.com/CartoDB/observatory-extension.git && \
  cd observatory-extension && \
  git checkout $OBSERVATORY_VERSION && \
  PGUSER=postgres make deploy

# Start production httpd additions, working here with nginx and passenger

# Install httpd for production
RUN apt-get install -y -q nginx

# Working with self-signed certificates here as https certs are hosted at the edge router for our enterprise
RUN apt-get install -y dirmngr gnupg && \
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 561F9B9CAC40B2F7 && \
  apt-get install -y apt-transport-https ca-certificates
    
# Install phusion passenger, taken from https://www.phusionpassenger.com/library/walkthroughs/deploy/ruby/ownserver/nginx/oss/bionic/install_passenger.html
# Add Phusion APT repository
RUN sh -c 'echo deb https://oss-binaries.phusionpassenger.com/apt/passenger bionic main > /etc/apt/sources.list.d/passenger.list' && \
  apt-get update

# Install Passenger + NGINX module
RUN apt-get install -y -q libnginx-mod-http-passenger

# Confirm installation (not sure this is necessary for Dockerfile)
RUN if [ ! -f /etc/nginx/modules-enabled/50-mod-http-passenger.conf ]; then ln -s /usr/share/nginx/modules-available/mod-http-passenger.load /etc/nginx/modules-enabled/50-mod-http-passenger.conf ; fi

# TODO - Install custom configuration files for server here

# Enable the Passenger NGINX module and restart NGINX
RUN a2enmod passenger && \
  apache2ctl restart
service nginx restart
# End production httpd additions

# Copy confs
# Added for httpd production setup, TODO: add switch to turn on/off
ADD ./config/CartoDB-prod.js \
      /CartoDB-SQL-API/config/environments/production.js
ADD ./config/WS-prod.js \
      /Windshaft-cartodb/config/environments/production.js
# Commenting out dev setup, TODO: add switch to turn on/off with above
# ADD ./config/CartoDB-dev.js \
#      /CartoDB-SQL-API/config/environments/development.js
# ADD ./config/WS-dev.js \
#      /Windshaft-cartodb/config/environments/development.js

# TODO: add switch to enable use of custom config files below from an alternative repo
ADD ./config/app_config.yml /cartodb/config/app_config.yml
ADD ./config/database.yml /cartodb/config/database.yml
ADD ./create_dev_user /cartodb/script/create_dev_user
ADD ./setup_organization.sh /cartodb/script/setup_organization.sh
ADD ./config/cartodb.nginx.proxy.conf /etc/nginx/sites-enabled/default
ADD ./config/varnish.vcl /etc/varnish.vcl
ADD ./geocoder.sh /cartodb/script/geocoder.sh
ADD ./geocoder_server.sql /cartodb/script/geocoder_server.sql
ADD ./fill_geocoder.sh /cartodb/script/fill_geocoder.sh
ADD ./sync_tables_trigger.sh /cartodb/script/sync_tables_trigger.sh
ENV PATH /usr/local/rvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mkdir -p /cartodb/log && touch /cartodb/log/users_modifications && \
    /opt/varnish/sbin/varnishd -a :6081 -T localhost:6082 -s malloc,256m -f /etc/varnish.vcl && \
    perl -pi.bak -e 's/^bind 127.0.0.1 ::1$/bind 0.0.0.0/' /etc/redis/redis.conf && \
    service postgresql start && service redis-server start && \
    perl -pi -e 's/0\.22\.0/0.22.2/' /cartodb/app/models/user/db_service.rb && \
	bash -l -c "cd /cartodb && bash script/create_dev_user && \
    bash script/setup_organization.sh && bash script/geocoder.sh" && \
	service postgresql stop && service redis-server stop && \
    chmod +x /cartodb/script/fill_geocoder.sh && \
    chmod +x /cartodb/script/sync_tables_trigger.sh

# TODO: add relevant/additional ports for production access to API: 3000 8080 8181 etc.
EXPOSE 80

ENV GDAL_DATA /usr/share/gdal/2.2

# Number of seconds between a sync tables task is run
# Default interval is an hour, use `docker run -e SYNC_TABLES_INTERVAL=60 ...` to change it
ENV SYNC_TABLES_INTERVAL 3600

ADD ./startup.sh /opt/startup.sh

CMD ["/bin/bash", "/opt/startup.sh"]
HEALTHCHECK CMD curl -f http://localhost || exit 1
