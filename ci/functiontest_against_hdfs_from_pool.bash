#!/bin/bash

set -euo pipefail

bootstrap_for_testing() {
  mkdir build
  pushd build
  ../bootstrap
  popd
}

install_hadoop() {
  echo '***** Installing hadoop *****'

  local hdfs_namenode_hostname="$1"

  # Configure and launch SSH
  /sbin/sshd-keygen
  ssh-keygen -t dsa -P '' -f ~/.ssh/id_dsa
  cat ~/.ssh/id_dsa.pub >> ~/.ssh/authorized_keys
  sed -ri 's/UsePAM yes/UsePAM no/g' /etc/ssh/sshd_config # See https://gist.github.com/gasi/5691565
  /sbin/sshd &

  # Download and extract Hadoop
  wget --progress=dot:giga --no-check-certificate --no-cookies -O hadoop-2.7.1.tar.gz http://supergsego.com/apache/hadoop/common/hadoop-2.7.1/hadoop-2.7.1.tar.gz
  gunzip hadoop-2.7.1.tar.gz
  tar xf hadoop-2.7.1.tar
  rm -f hadoop-2.7.1.tar
  export HADOOP_PREFIX=/usr/local/hadoop
  export HADOOP_HOME=$HADOOP_PREFIX
  mv hadoop-2.7.1 "$HADOOP_HOME"

  # Set JAVA_HOME
  export JAVA_HOME=/usr/java/latest
  sed -ri 's/export JAVA_HOME=\$\{JAVA_HOME\}/export JAVA_HOME=\/usr\/java\/latest/g' "$HADOOP_HOME/etc/hadoop/hadoop-env.sh"

  # Give SSH some time to come online before we ask it to scan for keys
  ssh-keyscan localhost >> ~/.ssh/known_hosts
  ssh-keyscan 0.0.0.0 >> ~/.ssh/known_hosts
  ssh-keyscan "$hdfs_namenode_hostname" >> ~/.ssh/known_hosts
}

configure_hadoop_site() {
  # Configure Hadoop site settings as per https://hadoop.apache.org/docs/current/hadoop-project-dist/hadoop-common/SingleCluster.html
  local hdfs_namenode_ip_port="$1"
  cat > "${HADOOP_PREFIX}/etc/hadoop/core-site.xml" <<CoreSiteXML
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>$hdfs_namenode_ip_port</value>
    </property>
</configuration>
CoreSiteXML

  cat > "${HADOOP_PREFIX}/etc/hadoop/hdfs-site.xml" <<SiteXML
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
      <name>dfs.namenode.fs-limits.min-block-size</name>
      <value>1024</value>
    </property>
</configuration>
SiteXML
}

run_function_tests() {
  pushd build
  make functiontest 2> /dev/null
  popd
}

get_hostname_of() {
  echo "$1" | cut -d ':' -f1
}

_main() {
  bootstrap_for_testing
  local hdfs_namenode_ip_port=$(cat "$1")
  local hdfs_namenode_ip=$(get_hostname_of "$hdfs_namenode_ip_port")
  install_hadoop "$hdfs_namenode_ip"
  configure_hadoop_site "$hdfs_namenode_ip_port"
  run_function_tests
}

_main "$@"
