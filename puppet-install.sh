#!/bin/bash

# NOTE:
# This Puppet Infrastructure expects the following SRV records:
# _x-puppet._tcp. for Puppet Server(s)
# _x-puppet-mcollective. for each MCollective Broker
# _x-puppet-db._tcp. for PuppetDB

# Puppet Infrastructure Provided by this script
###########################################################
# 1. Puppet Server                  | an-ua-vr-ps-001
# 2. Puppet Agent                   | all nodes
# 3. PuppetDB                       | an-ua-vr-pd-001
# 4. PostgreSQL for PuppetDB        | an-ua-vr-pp-001
# 5. MCollective Message Brokers    | an-ua-vr-mb-001 an-ua-vr-mb-002 an-ua-vr-mb-003
# 6. MCollective Servers            | all nodes
# 7. Mcollecive Client              | an-xx-pf-ws-001

# Firewall Ports
###########################################################
# source            |  destination    | port
###########################################################
# mco clients       |  mco brokers    | 4222
# mco brokers       |  mco brokers    | 4223
# puppetdb          |  postgresql     | 5432
# puppet-agents     |  puppet-server  | 8140
# puppet-server     |  puppetdb       | 8180
# mco brokers       |  localhost      | 8222

# Useful websites
############################################################
# https://docs.puppet.com/puppet
# https://docs.puppet.com/mcollective/reference/basic/basic_cli_usage.html
# https://docs.puppet.com/puppetdb/latest/api/query/v4/pql.html
# http://choria.io
# http://nats.io

# This kickstart will setup role facts when nodes are built:
# http://boot.$(hostname -d)/ks.cfg

# PuppetDB Server
puppetdb_server="an-ua-vr-pd-001"

# PuppetDB's PostgreSQL Server
puppetdb_database_host="an-ua-vr-pp-001"

# List all of the MCollective Brokers (NATS servers)
brokers=( "an-ua-vr-mb-001" "an-ua-vr-mb-002" "an-ua-vr-mb-003" )

# List all of the MCollective Clients (sysadmin workstations)
mco_clients=( "an-xx-pf-ws-001" )

# MCollective Users
mco_user="tracphil"

# development and local environments are available only on DevOps workstations
environments=( "production" "staging" "testing" "integration" )

# Domains to service each environment
#############################################
# Environment     |  Domain
#############################################
# production      |  amerinap.com
# staging         |  amerinapstg.xyz
# testing         |  amerinaptst.xyz
# integration     |  amerinapint.xyz
# development     |  amerinapdev.xyz <-- supported on DevOps workstations only
# local           |  amerinap.local  <-- supported on DevOps workstations only


#############################################
#####   DO NOT CHANGE ANYTHING BELOW    #####
#############################################

# Puppet Server
nodename=$(hostname -s)

# Set puppet environment and domain
# ----- determine environment the node belongs -----
# 000-799 production    # Serves end-users/clients
# 800-874 staging       # Mirror of production environment for Staging/UAT/
# 900-924 testing       # Where unit testing, interface testing/QA is performed
# 925-949 integration   # CI build target, or for sysadmin/developer testing of side effects
# 950-974 development   # Development server aka sandbox/poc
# 975-999 local         # Developer's workstation only
case "${nodename##?*-}" in
       [0-7][0-9][0-9]) environment=production ;;
   8[0-6][0-9]|87[0-4]) environment=production ;;
   87[5-9]|8[8-9][0-9]) environment=staging ;;
   9[0-1][0-9]|92[0-4]) environment=testing ;;
   92[5-9]|9[3-4][0-9]) environment=integration ;;
   9[5-6][0-9]|97[0-4]) environment=development ;;
   97[5-9]|9[8-9][0-9]) environment=local ;;
                     *) environment=TBD ;;
esac

# ----- determine domain -----
case "${nodename##?*-}" in
       [0-7][0-9][0-9]) domain=amerinap.com ;;
   8[0-6][0-9]|87[0-4]) domain=amerinap.com ;;
   87[5-9]|8[8-9][0-9]) domain=amerinapstg.xyz ;;
   9[0-1][0-9]|92[0-4]) domain=amerinaptst.xyz ;;
   92[5-9]|9[3-4][0-9]) domain=amerinapint.xyz ;;
   9[5-6][0-9]|97[0-4]) domain=amerinapdev.xyz ;;
   97[5-9]|9[8-9][0-9]) domain=amerinap.xyz ;;
                     *) domain=TBD ;;
esac

# nats.io routes password
routes_password=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 13)

# https://docs.puppet.com/pe/latest/sys_req_hw.html
# TODO determine if /opt is a partition using mount | grep opt
# TODO determine if /opt is 20G+ in size and device if mounted
# opt_size=$(df -h /opt | grep  opt | awk '{ print $2 }')
# opt_size=$(blockdev --getsize /dev/vg00/lv_opt)
# opt_partition=$(df -h /opt | grep  opt | awk '{ print $1 }')
lvextend -r -L 20G /dev/vg00/lv_opt

firewall-cmd --zone=public --add-port=8140/tcp --permanent
firewall-cmd --reload

cat << 'BASHRC' > /root/.bashrc
umask 022

set -o vi

export TERM=xterm-256color

eval "`dircolors`"

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias ll='ls -l --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

export PS1='\e[32;1m\u\e[m\e[30m@\e[31;1m\h\e[m\e[30m:\e[36;1m\w\e[m\n% '
BASHRC

cat << ALIAS >> /root/.bashrc

alias cnode='cd /etc/puppetlabs/code/environments/${environment}/data/nodes/'
alias cdata='cd /etc/puppetlabs/code/environments/${environment}/data/'
ALIAS

# Put /opt/puppetlabs/bin in our path
# This file will be replaced later with the default
cat << 'BASH' > /root/.bash_profile
# .bash_profile
# Get the aliases and functions
if [ -f ~/.bashrc ]; then
       . ~/.bashrc
fi

PATH=/opt/puppetlabs/bin:$PATH

export PATH
BASH

. /root/.bash_profile

# Download puppet labs repo and import key
yum -y localinstall https://yum.puppetlabs.com/puppetlabs-release-pc1-el-7.noarch.rpm

# Not sure if this is required.
# rpm --import  https://raw.githubusercontent.com/puppetlabs/puppetlabs-release/master/files/RPM-GPG-KEY-puppetlabs

# Fix problem with epel repo erroring.
yum clean all

yum -y install puppetserver git puppetdb-termini

systemctl enable puppetserver

sed -i 's/^JAVA_ARGS.*$/JAVA_ARGS="-Xms2g -Xmx2g -XX:MaxPermSize=256m -Djava.io.tmpdir=\/var\/lib\/puppet\/tmp"/' /etc/sysconfig/puppetserver

mkdir -p /var/lib/puppet/tmp

chown -R puppet.puppet /var/lib/puppet

chcon --reference=/tmp /var/lib/puppet/tmp

# Lets randomize our splaylimit in puppt.conf
# This will cause a puppet-agent run somewhere between 15 and 30 minutes
splay_time=$(shuf -i 1-15 -n 1)

cat << PUPPETCONF > /etc/puppetlabs/puppet/puppet.conf
# This file can be used to override the default puppet settings.
# See the following links for more details on what settings are available:
# - https://docs.puppetlabs.com/puppet/latest/reference/config_important_settings.html
# - https://docs.puppetlabs.com/puppet/latest/reference/config_about_settings.html
# - https://docs.puppetlabs.com/puppet/latest/reference/config_file_main.html
# - https://docs.puppetlabs.com/references/latest/configuration.html

[main]
    certname = ${nodename}.${domain}
    use_srv_records = true
    srv_domain = ${domain}
    environment = ${environment}
    # strict_variables = true

[master]
    dns_alt_names = ${nodename}.${domain},${nodename},puppet,puppet.${domain}
    environment_timeout = 0
    trusted_server_facts = true
    strict_variables = true
    # Save facts and catalogs in PuppetDB
    # storeconfigs = true
    # storeconfigs_backend = puppetdb
    # This retains Puppet’s default behavior of storing the reports to disk as YAML,
    # while also sending the reports to PuppetDB
    # reports = store,puppetdb

    pidfile = /var/run/puppetlabs/puppetserver/puppetserver.pid

    codedir = /etc/puppetlabs/code
    logdir = /var/log/puppetlabs/puppetserver
    rundir = /var/run/puppetlabs/puppetserver
    vardir = /opt/puppetlabs/server/data/puppetserver

# Splaylimit is set at kickstart with a random number between 1 and 15.
# splaylimit=${splay_time} will delay the first puppet run ${splay_time} minutes
# Info: http://stackoverflow.com/questions/32905796/puppet-splay-splaylimit-explained
[agent]
    report = true
    show_diff = true
    runinterval = 14m
    splay = true
    splaylimit = ${splay_time}
PUPPETCONF

# This is seperate from the above PUPPET here doc because $clientbucketdir is not a bash variable
cat << 'PUPPET_USER' >> /etc/puppetlabs/puppet/puppet.conf

[user]
    bucketdir = $clientbucketdir
PUPPET_USER

chown puppet:puppet /etc/puppetlabs/puppet/puppet.conf
chmod 600 /etc/puppetlabs/puppet/puppet.conf

# This will configure the puppet master's certs, etc
# Hit ctl-c when you see the version number printed
# /opt/puppetlabs/bin/puppet master --verbose --no-daemonize
systemctl restart puppetserver

# remove default environment when puppetserver was first started
for env in "${environments[@]}"; do
  rm -rf /etc/puppetlabs/code/environments/${env}/hieradata
done

for env in "${environments[@]}"; do
  mkdir -p /etc/puppetlabs/code/environments/${env}/{data,manifests,modules}
done

for env in "${environments[@]}"; do
  mkdir -p /etc/puppetlabs/code/environments/${env}/data/{nodes,hypervisor,location/{region,zone},role,network,osfamily}
done

for env in "${environments[@]}"; do
cat << SITEPP > /etc/puppetlabs/code/environments/${env}/manifests/site.pp
# lookup all classes defined in hiera and other data sources
# lookup('classes', Array[String], 'unique').include
# lookup("classes", {"merge" => "unique"}).include
lookup("classes").include
SITEPP
done

for env in "${environments[@]}"; do
cat << ENVIRONMENT > /etc/puppetlabs/code/environments/${env}/environment.conf
environment_data_provider = hiera
ENVIRONMENT
done

for env in "${environments[@]}"; do
cat << HIERA > /etc/puppetlabs/code/environments/${env}/hiera.yaml
---

version: 4
datadir: "data"

# priority is from top to bottom
hierarchy:

  - name: "Node Name"
    backend: yaml
    path: "nodes/%{::trusted.certname}"

  - name: "Node Role"
    backend: yaml
    path: "role/%{role}"

  - name: "Network Subnet"
    backend: yaml
    path: "network/%{subnet}"

  - name: "Location - Zone"
    backend: yaml
    path: "location/zone/%{zone}"

  - name: "Location - Region"
    backend: yaml
    path: "location/region/%{region}"

  - name: "Hypervisor"
    backend: yaml
    path: "hypervisor/%{facts.virtual}"

  - name: "OS Family"
    backend: yaml
    path: "osfamily/%{::osfamily}"

  # firewalld is so large we keep it in its own common file
  - name: "Firewalld Settings"
    backend: yaml
    path: "common-firewalld"

  - name: "Common Settings"
    backend: yaml
    path: "common"

# :logger: puppet
HIERA
done

cat << NODE >> /etc/puppetlabs/code/environments/${environment}/data/nodes/${nodename}.${domain}.yaml
---

classes:
  - puppetdb::master::config

# firewalld::
firewalld::services:
  puppet-server:
    ensure: 'present'
    service: 'puppet-server'
    zone: 'public'

# puppetdb::
# puppetdb_server hostname is defined here:
# /etc/puppetlabs/code/environments/${environment}/data/role/puppet_puppetdb_infra.yaml
puppetdb::master::config::puppetdb_server: "%{hiera('puppetdb_server')}"
NODE

cat << NODE >> /etc/puppetlabs/code/environments/${environment}/data/nodes/${puppetdb_database_host}.${domain}.yaml
---

classes:
  - puppetdb::database::postgresql

# firewalld::
firewalld::services:
  postgresql:
    ensure: 'present'
    service: 'postgresql'
    zone: 'public'

# puppetdb::
puppetdb::database::postgresql::listen_addresses: "%{ipaddress_eth0:0}"
NODE

cat << NODE >> /etc/puppetlabs/code/environments/${environment}/data/nodes/${puppetdb_server}.${domain}.yaml
---

classes:
  - puppetdb::server

# firewalld::
firewalld::services:
  puppetdb:
    ensure: 'present'
    service: 'puppetdb'
    zone: 'public'

# puppetdb::
# puppetdb_database_host hostname is defined here:
# /etc/puppetlabs/code/environments/${environment}/data/role/puppet_puppetdb_infra.yaml
puppetdb::server::database_host: "%{hiera('puppetdb_database_host')}"
puppetdb::server::manage_firewall: false
NODE

for env in "${environments[@]}"; do
cat << FIREWALLD > /etc/puppetlabs/code/environments/${env}/data/common-firewalld.yaml
---

# firewalld::
firewalld::custom_services:
  puppet-server:
    short: 'puppet-server'
    description: 'Puppet Agent to Puppet Server Communication'
    port:
      - port: 8140
        protocol: 'tcp'
  puppetdb:
    short: 'puppetdb'
    description: 'Puppet Server to Puppetdb Communication'
    port:
      - port: 8081
        protocol: 'tcp'
  nats_client:
    short: 'nats-clients'
    description: 'MCollective Clients to NATS'
    port:
      - port: 4222
        protocol: 'tcp'
  nats_cluster:
    short: 'nats-cluster'
    description: 'NATS Cluster Communication'
    port:
      - port: 4223
        protocol: 'tcp'
  nats_monitoring:
    short: 'nats-monitoring'
    description: 'NATS Monitoring'
    port:
      - port: 8222
        protocol: 'tcp'

# firewalld::zones
# purge what is not managed via Puppet
firewalld::zones:
  public:
    ensure: present
    purge_rich_rules: true
    purge_services: true
    purge_ports: true

# firewalld::services
firewalld::services:
  ssh:
    ensure: 'present'
    service: 'ssh'
    zone: 'public'
  dhcpv6-client:
    ensure: 'present'
    service: 'dhcpv6-client'
    zone: 'public'
FIREWALLD
done

for env in "${environments[@]}"; do
cat << COMMON > /etc/puppetlabs/code/environments/${env}/data/common.yaml
---

lookup_options:
  classes:
    merge:
    strategy: "deep"
    knockout_prefix: "-"

classes:
  - firewalld
  - mcollective
  - ntp

# chrony::
chrony::servers:
  - 0.us.pool.ntp.org
  - 1.us.pool.ntp.org
  - 2.us.pool.ntp.org
  - 3.us.pool.ntp.org

# mcollective
mcollective::site_policies:
  - action: "allow"
    callers: "choria=${mco_user}.mcollective"
    actions: "*"
    facts: "*"
    classes: "*"

# ntp::
ntp::restrict: ['127.0.0.1']
ntp::servers:
  - 0.us.pool.ntp.org
  - 1.us.pool.ntp.org
  - 2.us.pool.ntp.org
  - 3.us.pool.ntp.org
COMMON
done

# This sets up a role fact for puppet-server to use to communicate with puppetdb
cat << ROLE_PUPPET_PUPPETDB > /opt/puppetlabs/facter/facts.d/role_puppet_puppetdb_infra.yaml
---

role: puppet_puppetdb_infra
ROLE_PUPPET_PUPPETDB

# Setup role for puppetdb infrastructure hosts
cat << PUPPET_PUPPETDB > /etc/puppetlabs/code/environments/${environment}/data/role/puppet_puppetdb_infra.yaml
---

puppetdb_server: ${puppetdb_server}.${domain}
puppetdb_database_host: ${puppetdb_database_host}.${domain}

puppetdb::manage_firewall: false
PUPPET_PUPPETDB

# Setup placeholder yaml files for MCollective Brokers
for broker in "${brokers[@]}"; do
cat << MCO_BROKER > /etc/puppetlabs/code/environments/${environment}/data/nodes/${broker}.${domain}.yaml
---

# This is fullfilled by mcollective_broker in roles leave it commented here.
# classes:
#   - nats
MCO_BROKER
done

cat << MCO_BROKER > /etc/puppetlabs/code/environments/${environment}/data/role/mcollective_broker.yaml
---

classes:
  - nats

# firewalld::
firewalld::services:
  nats_client:
    ensure: "present"
    service: "nats-clients"
    zone: "public"
  nats_cluster:
    ensure: "present"
    service: "nats-cluster"
    zone: "public"

# nats::
nats::routes_password: "${routes_password}"
nats::servers:
MCO_BROKER

# This will input all MCollective Brokers in the preceding mcollective_broker.yaml file
for broker in "${brokers[@]}"; do
    echo "    - ${broker}.${domain}" >> /etc/puppetlabs/code/environments/${environment}/data/role/mcollective_broker.yaml
done

for client in "${mco_clients[@]}"; do
cat << MCO_CLIENT > /etc/puppetlabs/code/environments/${environment}/data/nodes/${client}.${domain}.yaml
---

classes:
  - -ntp
  - chrony

mcollective::client: true
MCO_CLIENT
done

/opt/puppetlabs/bin/puppet module install puppetlabs-puppetdb
/opt/puppetlabs/bin/puppet module install puppetlabs-ntp --version 6.0.0
/opt/puppetlabs/bin/puppet module install ripienaar-mcollective --version 0.0.21
/opt/puppetlabs/bin/puppet module install ripienaar-nats --version 0.0.5

git clone https://github.com/ringingliberty/puppet-chrony.git /etc/puppetlabs/code/environments/${environment}/modules/chrony
git clone https://github.com/crayfishx/puppet-firewalld.git /etc/puppetlabs/code/environments/${environment}/modules/firewalld

/opt/puppetlabs/bin/puppetserver gem install deep_merge

# Reset .bash_profile to orginal
# /opt/puppetlabs/bin is set in /etc/
cat << BASH > /root/.bash_profile
# .bash_profile
# Get the aliases and functions
if [ -f ~/.bashrc ]; then
       . ~/.bashrc
fi
BASH

systemctl restart puppetserver
systemctl enable puppet
systemctl start puppet
