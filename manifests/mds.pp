class lustre::mds(
  $mdt,
  $service_nodes,
  $raid_level = 'mirror',
  $ashift = '12',
  $compression = 'lz4',
){
  include lustre::server

  $service_nodes_str = join(prefix($service_nodes, '--servicenode '), ' ')
  $mgs_nodes_str = join(prefix(hiera(lustre::mgs::service_nodes), '--mgsnode '), ' ')

  $mdt.each | $mdt | {
    # For each MDT on this MDS
    $index = $mdt[index]
    $prefered_host = $mdt[index]
    $format_array = $mdt[drives].map | $drives | {
      $drives_str = join($drives, ' ')
      $array_str = "${raid_level} ${drives_str}"
    }
    $format_str = join($format_array, ' ')
    $drives_array = $mdt[drives].map | $drives | {
      $drives_str = join($drives, ' ')
    }
    $drives_str = join($drives_array, ' ')

    exec { "Creating MDT${index} pool with ZFS":
      command => "/usr/sbin/zpool create \
-O canmount=off \
-o multihost=on \
-o cachefile=none \
-o ashift=${ashift} \
-O compression=${compression} \
${lustre::server::fsname}-mdt${index} \
${format_str}",
      unless  => ['/usr/bin/test ! -f /tmp/puppet_can_erase',
                  "/usr/sbin/blkid ${drives_str} | /usr/bin/grep zfs"],
      require => Class['luks'],
    }
    ~> exec { "Formating the MDT${index} with Lustre":
      command     => "/usr/sbin/mkfs.lustre \
--backfstype=zfs \
--fsname=${lustre::server::fsname} \
--mdt \
--index=${index} \
${service_nodes_str} \
${mgs_nodes_str} \
${lustre::server::fsname}-mdt${index}/mdt${index}",
      refreshonly => true,
      onlyif      => '/usr/bin/test -f /tmp/puppet_can_erase',
    }
    -> file { "/mnt/mdt${index}":
      ensure => 'directory',
    }
    -> cs_primitive { "ZFS_MDT${index}":
      primitive_class => 'ocf',
      primitive_type  => 'ZFS',
      provided_by     => 'heartbeat',
      parameters      => { 'pool' => "${lustre::server::fsname}-mdt${index}", 'importforce' => true },
      operations      => {
        'start'   => { 'timeout' => '300s' },
        'stop'    => { 'timeout' => '300s' },
        'monitor' => { 'timeout' => '60s', 'interval' => '10s' },
      },
    }
    -> cs_primitive { "lustre_MDT${index}":
      primitive_class => 'ocf',
      primitive_type  => 'Lustre',
      provided_by     => 'lustre',
      parameters      => { 'target' => "${lustre::server::fsname}-mdt${index}/mdt${index}", 'mountpoint' => "/mnt/mdt${index}" },
      operations      => {
        'start'   => { 'timeout' => '300s' },
        'stop'    => { 'timeout' => '300s' },
        'monitor' => { 'timeout' => '60s' },
      },
    }
    -> cs_group { "MDT${index}":
      primitives => ["ZFS_MDT${index}", "lustre_MDT${index}"]
    }
    -> cs_location { "prefered_host_MDT${index}":
      primitive => "MDT${index}",
      node_name => $prefered_host,
      score     => '50',
    }
  } # END of MDT $index
}

