class lustre::mds(
  $mdt,
  $raid_level = 'mirror',
  $ashift = '12',
  $compression = 'lz4',
){
  include lustre::server

  $mdt.each | $mdt | {
    # For each MDT on this MDS
    $index = $mdt[index]
    $prefered_host = $mdt[prefered_host]
    $scrub_schedule = $mdt[scrub_schedule]
    $fsname = $mdt[fsname]
    $shared_mdt_mgs = $mdt[shared_mdt_mgs]
    $hsm_max_requests = $mdt[hsm_max_requests]

    $service_nodes_str = join(prefix($mdt[service_nodes], '--servicenode '), ' ')
    $mgs_nodes_str = join(prefix($mdt[mgs_service_nodes], '--mgsnode '), ' ')

    if($scrub_schedule and $prefered_host == $::fqdn){
      file { "/etc/cron.d/scrub-MDT${index}.cron":
        ensure  => present,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "${scrub_schedule} root /usr/sbin/zpool scrub ${fsname}-mdt${index}\n";
      }
    }

    if($hsm_max_requests){
      # set and verify once in a while that HSM is enabled
      file { "/etc/cron.d/${fsname}-hsm-MDT${index}.cron":
        ensure  => present,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "0 * * * * root /root/${fsname}-hsm-MDT${index}.sh\n";
      }
      file { "/root/${fsname}-hsm-MDT${index}.sh":
        ensure  => present,
        owner   => 'root',
        group   => 'root',
        mode    => '0744',
        content => "#!/bin/bash
if ! test -d /proc/fs/lustre/mdt/${fsname}-MDT000${index} ; then
  # not mounted here
  exit 0
fi

if ! lctl get_param mdt.${fsname}-MDT000${index}.hsm_control | grep enabled > /dev/null; then
  lctl set_param mdt.${fsname}-MDT000${index}.hsm_control=enabled
fi
lctl set_param mdt.${fsname}-MDT000${index}.hsm.max_requests=${hsm_max_requests}";
      }
    }

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
${fsname}-mdt${index} \
${format_str}",
      unless  => ['/usr/bin/test ! -f /tmp/puppet_can_erase',
                  "/usr/sbin/blkid ${drives_str} | /usr/bin/grep zfs"],
      require => Class['luks'],
    } ~>
    if($shared_mdt_mgs == true){
      # shared MGS/MDT
      exec { "Formating the MDT${index} with Lustre":
        command     => "/usr/sbin/mkfs.lustre \
--backfstype=zfs \
--fsname=${fsname} \
--mgs \
--mdt \
--index=${index} \
${service_nodes_str} \
${mgs_nodes_str} \
${fsname}-mdt${index}/mdt${index}",
        refreshonly => true,
        onlyif      => '/usr/bin/test -f /tmp/puppet_can_erase',
      }
    }
    else {
      # standalone MDT
      exec { "Formating the MDT${index} with Lustre":
        command     => "/usr/sbin/mkfs.lustre \
--backfstype=zfs \
--fsname=${fsname} \
--mdt \
--index=${index} \
${service_nodes_str} \
${mgs_nodes_str} \
${fsname}-mdt${index}/mdt${index}",
        refreshonly => true,
        onlyif      => '/usr/bin/test -f /tmp/puppet_can_erase',
      }
    }
    -> file { "/mnt/mdt${index}":
      ensure => 'directory',
      before => Service['corosync'],
    }
    -> cs_primitive { "${fsname}_ZFS_MDT${index}":
      primitive_class => 'ocf',
      primitive_type  => 'ZFS',
      provided_by     => 'heartbeat',
      parameters      => { 'pool' => "${fsname}-mdt${index}", 'importforce' => true },
      operations      => {
        'start'   => { 'timeout' => '600s' },
        'stop'    => { 'timeout' => '600s' },
        'monitor' => { 'timeout' => '300s', 'interval' => '60s' },
      },
    }
    -> cs_primitive { "${fsname}_lustre_MDT${index}":
      primitive_class => 'ocf',
      primitive_type  => 'Lustre',
      provided_by     => 'lustre',
      parameters      => { 'target' => "${fsname}-mdt${index}/mdt${index}", 'mountpoint' => "/mnt/mdt${index}" },
      operations      => {
        'start'   => { 'timeout' => '600s' },
        'stop'    => { 'timeout' => '600s' },
        'monitor' => { 'timeout' => '300s' , 'interval' => '60s' },
      },
    }
#    -> cs_location { "${fsname}_MDT${index}_ib0":
#      primitive => "${fsname}_ZFS_MDT${index}",
#      rules     => [
#        { "only_if_ib0_up_${fsname}_MDT${index}" => {
#          'score'      => '-INFINITY',
#          'boolean-op' => 'or',
#          'expression' => [
#              { 'attribute' => 'ib0-healthy',
#                'operation' => 'ne',
#                'value'     => 0,
#              },
#              { 'attribute' => 'ib0-healthy',
#                'operation' => 'not_defined',
#              },
#            ],
#          },
#        },
#      ],
#    }
    -> cs_group { "${fsname}_MDT${index}":
      primitives => ["${fsname}_ZFS_MDT${index}", "${fsname}_lustre_MDT${index}"]
    }
    -> cs_location { "prefered_host_MDT${index}":
      primitive => "${fsname}_MDT${index}",
      node_name => $prefered_host,
      score     => '50',
    }
  } # END of MDT $index
}

class lustre::mds::nrpe(){
  nrpe::command {
    'check_hsm':
      ensure  => present,
      command => 'check_hsm';
  }
  nrpe::plugin {
    'check_hsm':
      ensure => present,
      source => 'puppet:///modules/lustre/check_hsm',
  }
}
