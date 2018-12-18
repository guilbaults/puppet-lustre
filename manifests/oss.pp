class lustre::oss(
  $ost,
  $ashift = '12',
  $compression = 'lz4',
){
  include lustre::server

  $ost.each | $ost | {
    # For each OST on this OSS
    $index = $ost[index]
    $prefered_host = $ost[prefered_host]
    $scrub_schedule = $ost[scrub_schedule]
    $fsname = $ost[fsname]
    $raid_level = $ost[raid_level],

    $service_nodes_str = join(prefix($ost[oss_service_nodes], '--servicenode '), ' ')
    $mgs_nodes_str = join(prefix($ost[mgs_service_nodes], '--mgsnode '), ' ')

    if($scrub_schedule and $prefered_host == $::hostname){
      file { "/etc/cron.d/scrub-OST${index}.cron":
        ensure  => present,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "${scrub_schedule} root /usr/sbin/zpool scrub ${fsname}-ost${index}\n";
      }
    }

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
-f \
-O recordsize=1024k \
-O dnodesize=auto \
-O canmount=off \
-o multihost=on \
-o cachefile=none \
-o ashift=${ashift} \
-O compression=${compression} \
${fsname}-ost${index} \
${format_str}",
      unless  => ['/usr/bin/test ! -f /tmp/puppet_can_erase',
                  "/usr/sbin/blkid ${drives_str} | /usr/bin/grep zfs"],
      require => Class['luks'],
    }
    ~> exec { "Formating the OST${index} with Lustre":
      command     => "/usr/sbin/mkfs.lustre \
--backfstype=zfs \
--fsname=${fsname} \
--ost \
--index=${index} \
${service_nodes_str} \
${mgs_nodes_str} \
${fsname}-ost${index}/ost${index}",
      refreshonly => true,
      onlyif      => '/usr/bin/test -f /tmp/puppet_can_erase',
    }
    -> file { "/mnt/ost${index}": ensure => 'directory' }
    -> cs_primitive { "ZFS_OST${index}":
      primitive_class => 'ocf',
      primitive_type  => 'ZFS',
      provided_by     => 'heartbeat',
      parameters      => { 'pool' => "${fsname}-ost${index}", 'importforce' => true },
      operations      => {
        'start'   => { 'timeout' => '600s' },
        'stop'    => { 'timeout' => '600s' },
        'monitor' => { 'timeout' => '300s', 'interval' => '60s' },
      },
    }
    -> cs_primitive { "lustre_OST${index}":
      primitive_class => 'ocf',
      primitive_type  => 'Lustre',
      provided_by     => 'lustre',
      parameters      => { 'target' => "${fsname}-ost${index}/ost${index}", 'mountpoint' => "/mnt/ost${index}" },
      operations      => {
        'start'   => { 'timeout' => '600s' },
        'stop'    => { 'timeout' => '600s' },
        'monitor' => { 'timeout' => '300s', interval => '60s', },
      },
    }
    -> cs_group { "OST${index}":
      primitives => ["ZFS_OST${index}", "lustre_OST${index}"]
    }
    -> cs_location { "prefered_host_OST${index}":
      primitive => "OST${index}",
      node_name => $prefered_host,
      score     => '50',
    }
  } # END of OST $index
}

