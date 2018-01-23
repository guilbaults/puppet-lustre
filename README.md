# puppet-lustre

#### Table of Contents

1. Module Description
2. Setup
    * What puppet-lustre affects
    * Setup requirements
    * Beginning with puppet-lustre
3. Usage - Configuration options and additional functionality
4. Reference
5. Limitations
6. Build Status

## Module description
This module is used to install and configure a Lustre filesystem with ZFS and HA using corosync.

## Setup

### What puppet-lustre affects

This module will format the disks specified in the configuration only if `/tmp/puppet_can_erase` exist on the local filesystem.

### Setup Requirements
This module require TODO modules

This module will install the required RPMs based on what is available in the repos.

For a ZFS only system, theses RPM can be recompiled to use the "stock" centos7 kernel when ldiskfs is removed during the `./configure` phase of the compilation.

### Beginning with puppet-lustre

This module can install the MGS, MDS and OSS of a Lustre file system.

Other site requirements can also be specified in site.pp, its possible to add disk encryption based on LUKS or SAS multipath.

Most of the configuration is done with hiera, the common.yaml contains the general settings for the Lustre filesystem, then each `$(hostname).yaml` contains specific information on disk path and ip addresses.

### site.pp

```
node 'mds1', 'mds2' {
  include lustre::server
  include lustre::mgs
  include lustre::mds
}
node 'oss1', 'oss2' {
  include lustre::server
  include lustre::oss
}
```

### hieradata/common.yaml

```
lustre::server::fsname: 'lustre01'
lustre::mgs::service_nodes: ['10.0.0.1@o2ib', '10.0.0.2@o2ib']
lustre::mgs::prefered_host: 'mds1'
lustre::ldev::devs:
 - 'mds1 mds2 lustre01-MGS     zfs:lustre01-mgt/mgt'
 - 'mds1 mds2 lustre01-MDT0000 zfs:lustre01-mdt0/mdt0'
 - 'mds1 mds2 lustre01-MDT0001 zfs:lustre01-mdt1/mdt1'
 - 'oss1 oss2 lustre01-OST0000 zfs:lustre01-ost0/ost0'
 - 'oss2 oss1 lustre01-OST0001 zfs:lustre01-ost1/ost1'

corosync::authkey: '/etc/puppetlabs/puppet/ssl/certs/ca.pem'
corosync::enable_secauth: true
corosync::enable_corosync_service: false
corosync::enable_pacemaker_service: false
```

### hieradata/hostnames/mds1.yaml and hieradata/hostnames/mds2.yaml

```
lustre::server::spl_hostid: "0x0000001"

lustre::mds::service_nodes: ['10.0.0.1@o2ib', '10.0.0.2@o2ib']

# A Raid1 for the MGT
lustre::mgs::mgt:
  drives: ['/dev/mapper/open_jbod00-bay00', '/dev/mapper/open_jbod00-bay01']

# Two MDT with a raid10 of 4 disk each
lustre::mds::mdt:
  - drives: [['/dev/mapper/open_jbod00-bay02', '/dev/mapper/open_jbod00-bay03',]
             ['/dev/mapper/open_jbod00-bay04', '/dev/mapper/open_jbod00-bay05',]]
    index: 0
    prefered_host: 'mds1'
  - drives: [['/dev/mapper/open_jbod00-bay06', '/dev/mapper/open_jbod00-bay07',]
             ['/dev/mapper/open_jbod00-bay08', '/dev/mapper/open_jbod00-bay09',]]
    index: 1
    prefered_host: 'mds12'

corosync::unicast_addresses: ['mds1', 'mds2']
corosync::quorum_members: ['mds1','mds2']

corosync::stonith:
  'mds1': { user: 'root', password: 'changeme', ipaddr: 'mds1-bmc' }
  'mds2': { user: 'root', password: 'changeme', ipaddr: 'mds2-bmc' }
```

### hieradata/hostnames/oss1.yaml and hieradata/hostnames/oss2.yaml

```
lustre::server::spl_hostid: "0x0000003"

lustre::oss::service_nodes: ['10.0.0.3@o2ib', '10.0.0.4@o2ib']

# 2 OST in RAIDZ3 with 11 drives each (8+3)
lustre::oss::ost:
  - drives: [['/dev/mapper/open_jbod00-bay00', '/dev/mapper/open_jbod01-bay00',
              '/dev/mapper/open_jbod00-bay01', '/dev/mapper/open_jbod01-bay01',
              '/dev/mapper/open_jbod00-bay02', '/dev/mapper/open_jbod01-bay02',
              '/dev/mapper/open_jbod00-bay03', '/dev/mapper/open_jbod01-bay03',
              '/dev/mapper/open_jbod00-bay04', '/dev/mapper/open_jbod01-bay04',
              '/dev/mapper/open_jbod00-bay05']]
    index: 0
    prefered_host: 'oss1'
  - drives: [[                                 '/dev/mapper/open_jbod01-bay05',
              '/dev/mapper/open_jbod00-bay06', '/dev/mapper/open_jbod01-bay06',
              '/dev/mapper/open_jbod00-bay07', '/dev/mapper/open_jbod01-bay07',
              '/dev/mapper/open_jbod00-bay08', '/dev/mapper/open_jbod01-bay08',
              '/dev/mapper/open_jbod00-bay09', '/dev/mapper/open_jbod01-bay09',
              '/dev/mapper/open_jbod00-bay10', '/dev/mapper/open_jbod01-bay10']]
    index: 1
    prefered_host: 'oss2'

corosync::unicast_addresses: ['oss1', 'oss2']
corosync::quorum_members: ['oss1','oss2']

corosync::stonith:
  'oss1': { user: 'root', password: 'changeme', ipaddr: 'oss1-bmc' }
  'oss2': { user: 'root', password: 'changeme', ipaddr: 'oss2-bmc' }
```
## Usage
## Reference
## Limitations
This is currently only support Centos7
## Build Status
The current state of the automatic puppet syntax check:

[![Build Status](https://travis-ci.org/guilbaults/puppet-lustre.svg?branch=master)](https://travis-ci.org/guilbaults/puppet-lustre)
