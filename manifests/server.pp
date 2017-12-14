class lustre::server(
  $fsname,
  $spl_hostid,
  # This heartbeat script is under GPL license and not included directly in
  # this module, OS native repo will have this script in the future.
  $zfs_heartbeat_script='https://raw.githubusercontent.com/ClusterLabs/resource-agents/master/heartbeat/ZFS',
){
  include lustre
  include lustre::ldev
  include corosync
  package {[
    'lustre',
    'kmod-lustre-osd-zfs',
    'lustre-osd-zfs-mount',
    'kmod-lustre',
    'lustre-resource-agents',
    'fence-agents-all',
  ]:}
  file { '/etc/modprobe.d/spl.conf':
    content => "options spl spl_hostid=${spl_hostid}
",
  }
  -> file { '/etc/modprobe.d/zfs.conf':
    content => "options zfs metaslab_debug_unload=1
options zfs zfs_vdev_scheduler=deadline
options zfs zfs_arc_max=${sprintf('%i', $::memory[system][total_bytes]*0.75)}
options zfs zfs_dirty_data_max=2147483648
options zfs zfs_vdev_async_write_active_min_dirty_percent=20
options zfs zfs_vdev_async_write_min_active=5
options zfs zfs_vdev_async_write_max_active=10
options zfs zfs_vdev_sync_read_min_active=16
options zfs zfs_vdev_sync_read_max_active=16
",
  }
  -> exec { 'modprobe zfs':
    command => '/usr/sbin/modprobe zfs',
    unless  => '/usr/sbin/lsmod | /usr/bin/grep zfs',
    require => Package['kmod-lustre-osd-zfs'],
  }

  # TODO put in hiera a list of lustre/lnet parameters
  file { '/etc/modprobe.d/lustre.conf':
    content => 'options lnet networks=o2ib(ib0)',
  }
  exec { 'modprobe lustre':
    command => '/usr/sbin/modprobe lustre',
    unless  => '/usr/sbin/lsmod | /usr/bin/grep lustre',
    require => [Exec['modprobe zfs'], Package['lustre'], Class['network']],
  }
  file { '/usr/lib/ocf/resource.d/heartbeat/ZFS':
    source => $zfs_heartbeat_script,
    owner  => 'root',
    group  => 'root',
    mode   => '0744',
    before => Service['corosync'],
  }
  $corosync_ips = $::corosync::unicast_addresses
  $corosync_ips.each | String $corosync_ip | {
    firewall { "100 allow corosync access from ${corosync_ip}":
      dport  => 5405,
      source => $corosync_ip,
      proto  => 'udp',
      action => 'accept',
      before => Service['corosync'],
    }
  }

  $corosync_stonith = hiera('corosync::stonith')
  each($corosync_stonith) |$name, $device| {
    $user = $device[user]
    $password = $device[password]
    $ipaddr = $device[ipaddr]
    cs_stonith { "ipmi-poweroff-${name}" :
      ensure         => present,
      primitive_type => 'fence_ipmilan',
      device_options => {
        'pcmk_host_list' => $name,
        'login'          => $user,
        'passwd'         => $password,
        'ipaddr'         => $ipaddr,
        'method'         => 'onoff',
        'lanplus'        => true,
        'power_wait'     => '5',
      },
    }
  }

  cs_rsc_defaults { 'resource-stickiness' :
    value => '100',
  }
}

