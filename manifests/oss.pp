class lustre::oss(
  $ost,
  $service_nodes,
  $raid_level = 'raidz3',
  $ashift = '12',
  $compression = 'lz4',
){
  include lustre::server

  $service_nodes_str = join(prefix($service_nodes, '--servicenode '), ' ')
  $mgs_nodes_str = join(prefix(hiera(lustre::mgs::service_nodes), '--mgsnode '), ' ')

  $ost.each | $ost | {
    # For each MDT on this MDS
    $index = $ost[index]
    $format_array = $ost[drives].map | $drives | {
      $drives_str = join($drives, ' ')
      $array_str = "${raid_level} ${drives_str}"
    }
    $format_str = join($format_array, ' ')
    $drives_array = $ost[drives].map | $drives | {
      $drives_str = join($drives, ' ')
    }
    $drives_str = join($drives_array, ' ')

    exec { "Creating OST${index} pool with ZFS":
      command => "/usr/sbin/zpool create \
-O canmount=off \
-o multihost=on \
-o cachefile=none \
-o ashift=${ashift} \
-O compression=${compression} \
${lustre::server::fsname}-ost${index} \
${format_str}",
      unless  => "/usr/sbin/blkid ${drives_str} | /usr/bin/grep zfs",
      require => Class['luks'],
    }
    ~> exec { "Formating the OST${index} with Lustre":
      command     => "/usr/sbin/mkfs.lustre \
--backfstype=zfs \
--fsname=${lustre::server::fsname} \
--ost \
--index=${index} \
${service_nodes_str} \
${mgs_nodes_str} \
${lustre::server::fsname}-ost${index}/ost${index}",
      refreshonly => true,
    }
    -> file { "/mnt/ost${index}": ensure => 'directory' }
    -> cs_primitive { "ZFS_OST${index}":
      primitive_class => 'ocf',
      primitive_type  => 'ZFS',
      provided_by     => 'heartbeat',
      parameters      => { 'pool' => "${lustre::server::fsname}-ost${index}", 'importforce' => true },
      operations      => {
        'start'   => { 'timeout' => '300s' },
        'stop'    => { 'timeout' => '300s' },
        'monitor' => { 'timeout' => '60s', 'interval' => '10s' },
      },
    }
    -> cs_primitive { "lustre_OST${index}":
      primitive_class => 'ocf',
      primitive_type  => 'Lustre',
      provided_by     => 'lustre',
      parameters      => { 'target' => "${lustre::server::fsname}-ost${index}/ost${index}", 'mountpoint' => "/mnt/ost${index}" },
      operations      => {
        'start'   => { 'timeout' => '300s' },
        'stop'    => { 'timeout' => '300s' },
        'monitor' => { 'timeout' => '60s' },
      },
    }
    -> cs_group { "OST${index}":
      primitives => ["ZFS_OST${index}", "lustre_OST${index}"]
    }
  } # END of OST $index
}

