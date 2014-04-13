#!/bin/bash

log_file=/var/log/provision.log

{
### Packages
yum -q -y update
yum -q -y upgrade

yum -q -y install ksh sudo vim-enhanced nano joe mc openssh-server \
	vsftpd perl-core man man-pages sysstat \
	zip unzip xauth xterm nc nmap tcpdump screen zsh tmux

### PostgreSQL
if [ $(hostname) == "liferay-node1" ]; then
	yum -y install postgresql-server

	service postgresql initdb

	chkconfig --level 3 postgresql on

	cp /var/lib/pgsql/data/postgresql.conf /var/lib/pgsql/data/postgresql.conf.orig
	sed 's/shared_buffers.*=.*MB/shared_buffers=128MB/g' /var/lib/pgsql/data/postgresql.conf > /var/lib/pgsql/data/postgresql.conf.new
	echo "listen_addresses='*'" >> /var/lib/pgsql/data/postgresql.conf.new
	cp /var/lib/pgsql/data/postgresql.conf.new /var/lib/pgsql/data/postgresql.conf

	cp /var/lib/pgsql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf.orig

	echo "host all all 127.0.0.0/8 md5" > /var/lib/pgsql/data/pg_hba.conf
	echo "host all all 10.0.0.0/8 md5" >> /var/lib/pgsql/data/pg_hba.conf
	echo "local all postgres trust" >> /var/lib/pgsql/data/pg_hba.conf

	service postgresql restart

	DB=lportal
	PSQL="psql -U postgres -c"

	$PSQL "DROP DATABASE IF EXISTS ${DB}"
	$PSQL "DROP USER IF EXISTS ${DB}"
	$PSQL "CREATE USER ${DB} WITH UNENCRYPTED PASSWORD 'password'"
	$PSQL "CREATE DATABASE ${DB} WITH OWNER ${DB} ENCODING 'UTF-8'"
fi

### Hosts
cat >> /etc/hosts <<EOF
10.211.55.10	liferay-node1
10.211.55.20	liferay-node2
10.211.55.30	liferay-node3
10.211.55.40	liferay-node4
EOF

### TMUX
cat >> /home/vagrant/.profile <<EOF
if [[ -z \$TMUX && -n \$SSH_TTY ]]; then
    me=\$(whoami)

    if tmux has-session -t \$me 2>/dev/null; then
        exec tmux -2 attach-session -t \$me
    else
        exec tmux -2 new-session -s \$me
    fi
fi
EOF

## JDK
rpm -ivh /vagrant/jdk*.rpm

cat >> /home/vagrant/.bashrc <<EOF
export JAVA_HOME=/usr/java/latest
export JRE_HOME=\$JAVA_HOME
export PATH=\$PATH:\$JAVA_HOME/bin
EOF

### Disable services
chkconfig --level 3 rpcbind off
chkconfig --level 3 rpcgssd off
chkconfig --level 3 rpcidmapd off
chkconfig --level 3 nfslock off
chkconfig --level 3 netfs off
chkconfig --level 3 ip6tables off
chkconfig --level 3 iptables off
chkconfig --level 3 iscsi off
chkconfig --level 3 iscsid off
chkconfig --level 3 iscsi off

### Convinience scripts
cat > /etc/profile.d/prompt.sh <<EOF
if [ -n "\$PS1" ]; then

  case `id -un` in
    root)
      COLOR=31 # Yellow
      ;;
    *)
      COLOR=32 # Green
      ;;
  esac

  PS1='\[\033[01;\${COLOR}m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\\$ '
fi
EOF

### LIFERAY
vagrant_home=/home/vagrant
liferay_home=$vagrant_home/liferay-portal-6.1.30-ee-ga3

mkdir -p $liferay_home/deploy
mkdir -p $liferay_home/diag

unzip -q /vagrant/liferay-portal-tomcat-6.1.30-ee-ga3-20130812170130063.zip -d $vagrant_home

cp /vagrant/*.war $liferay_home/deploy
cp /vagrant/license*.xml $liferay_home/deploy

cat > $liferay_home/portal-ext.properties <<EOF
### Database
jdbc.default.driverClassName=org.postgresql.Driver
jdbc.default.url=jdbc:postgresql://10.211.55.10:5432/lportal
jdbc.default.username=lportal
jdbc.default.password=password

### Clusterring
cluster.link.enabled=true
cluster.executor.debug.enabled=true

### UNICAST
cluster.link.channel.system.properties=\\
	jgroups.tcpping.initial_hosts=10.211.55.10[7800],10.211.55.20[7800],10.211.55.30[7800],10.211.55.40[7800]

cluster.link.autodetect.address=10.211.55.1:22
cluster.link.channel.properties.control=tcp.xml
cluster.link.channel.properties.transport.0=tcp.xml

### Cache replications
ehcache.cluster.link.replication.enabled=true

### Cluster scheduler
org.quartz.jobStore.isClustered=true

### DL
dl.store.file.system.root.dir=/vagrant/dlstore
dl.store.impl=com.liferay.portlet.documentlibrary.store.AdvancedFileSystemStore

### Lucene
lucene.replicate.write=true
EOF

cat > $liferay_home/tomcat*/bin/setenv.sh <<EOF
# General
export JAVA_OPTS="\$JAVA_OPTS -Dfile.encoding=UTF8 -Dorg.apache.catalina.loader.WebappClassLoader.ENABLE_CLEAR_REFERENCES=false -Duser.timezone=GMT"
export JAVA_OPTS="\$JAVA_OPTS -XX:NewSize=256m -XX:MaxNewSize=512m -Xms1024m -Xmx2048m -XX:MaxPermSize=512m"
export JAVA_OPTS="\$JAVA_OPTS -XX:+UseParNewGC -XX:+UseConcMarkSweepGC -XX:+CMSParallelRemarkEnabled -XX:SurvivorRatio=20 -XX:ParallelGCThreads=2"

# Cluster
export JAVA_OPTS="\$JAVA_OPTS -Djava.net.preferIPv4Stack=true"
#export JAVA_OPTS="\$JAVA_OPTS -Djgroups.tcpping.initial_hosts=10.211.55.10[7800],10.211.55.20[7800],10.211.55.30[7800],10.211.55.40[7800]"

# Monitoring
export JAVA_OPTS="\$JAVA_OPTS -Dcom.sun.management.jmxremote=true"
export JAVA_OPTS="\$JAVA_OPTS -Dcom.sun.management.jmxremote.port=9000"
export JAVA_OPTS="\$JAVA_OPTS -Dcom.sun.management.jmxremote.ssl=false"
export JAVA_OPTS="\$JAVA_OPTS -Dcom.sun.management.jmxremote.authenticate=false"

# Diagnostics
export JAVA_OPTS="\$JAVA_OPTS -XX:+HeapDumpOnOutOfMemoryError" -XX:HeapDumpPath=$liferay_home/diag"
export JAVA_OPTS="\$JAVA_OPTS -Xloggc:$liferay_home/diag/gc.log -XX:+PrintGCDetails -XX:+PrintGCTimeStamps"
EOF

cat > $liferay_home/tomcat*/webapps/ROOT/WEB-INF/classes/log4j.properties <<EOF
log4j.logger.com.liferay.portal.cluster.ClusterBase=DEBUG

log4j.logger.net.sf.ehcache=INFO
log4j.logger.net.sf.ehcache.config=DEBUG
log4j.logger.net.sf.ehcache.distribution=DEBUG
EOF

chown -R vagrant:vagrant $liferay_home
} 2>&1 | tee $log_file
