class lustre::mgs(
  $mgt,
  $service_nodes,
  $raid_level = 'mirror',
  $ashift = '12',
  $compression = 'lz4'
){
  include lustre::server
  $drives = $mgt[drives]
  $drives_str = join($drives, ' ')
  $service_nodes_str = join(prefix($service_nodes, '--servicenode '), ' ')
  exec { 'Creating MGT pool with ZFS':
    command => "/usr/sbin/zpool create \
-O canmount=off \
-o multihost=on \
-o cachefile=none \
-o ashift=${ashift} \
-O compression=${compression} \
${lustre::server::fsname}-mgt \
${lustre::mgs::raid_level} ${drives_str}",
    unless  => "/usr/sbin/blkid ${drives_str} | /usr/bin/grep zfs",
    require => Class['luks'],
  }
  ~> exec { 'Formating the MGT with Lustre':
    command     => "/usr/sbin/mkfs.lustre \
--backfstype=zfs \
--fsname=${lustre::server::fsname} \
--mgs ${lustre::server::fsname}-mgt/mgt \
${service_nodes_str}",
    refreshonly => true,
  }
  -> file { '/mnt/mgt': ensure => 'directory' }
  -> cs_primitive { 'ZFS_MGT':
    primitive_class => 'ocf',
    primitive_type  => 'ZFS',
    provided_by     => 'heartbeat',
    parameters      => {
      'pool'        => "${lustre::server::fsname}-mgt",
      'importforce' => true
    },
    operations      => {
      'start'   => { 'timeout' => '300s' },
      'stop'    => { 'timeout' => '300s' },
      'monitor' => {
        'timeout'  => '60s',
        'interval' => '10s'
      },
    },
  }
  -> cs_primitive { 'lustre_MGT':
    primitive_class => 'ocf',
    primitive_type  => 'Lustre',
    provided_by     => 'lustre',
    parameters      => { 'target' => "${lustre::server::fsname}-mgt/mgt", 'mountpoint' => '/mnt/mgt' },
    operations      => {
      'start'   => { 'timeout' => '300s' },
      'stop'    => { 'timeout' => '300s' },
      'monitor' => { 'timeout' => '60s' },
    },
  }
  -> cs_group { 'MGT':
    primitives => ['ZFS_MGT', 'lustre_MGT']
  }
}

