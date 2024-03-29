class lustre::server(
  $spl_hostid=undef,
  # This heartbeat script is under GPL license and not included directly in
  # this module, OS native repo will have this script in the future.
  $zfs_heartbeat_script='https://raw.githubusercontent.com/ClusterLabs/resource-agents/master/heartbeat/ZFS',
  $lnet_firewall=['0.0.0.0/0'],
  $module_options=['options lnet networks=o2ib(ib0)'],
  $batch_limit='20',
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
  ]:}

  exec { '/usr/bin/echo Warning, puppet is allowed to format drives':
    unless => '/usr/bin/test ! -f /tmp/puppet_can_erase',
  }

  if $spl_hostid {
    file { '/etc/modprobe.d/spl.conf':
      content => "options spl spl_hostid=${spl_hostid}
",
    }
  }
  else {
    exec {'/usr/bin/echo SPL is missing for ZFS failover':
      unless => '/usr/bin/grep spl.spl_hostid /proc/cmdline',
    }
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

  $lnet_firewall.each | String $ip | {
    firewall { "100 allow lnet access from ${ip}":
      dport  => 988,
      source => $ip,
      proto  => 'tcp',
      action => 'accept',
      before => Service['corosync'],
    }
  }

  $lustre_conf_content = join($module_options, '
')
  file { '/etc/modprobe.d/lustre.conf':
    content => $lustre_conf_content,
  }
  exec { 'modprobe lustre':
    command => '/usr/sbin/modprobe lustre',
    unless  => '/usr/sbin/lsmod | /usr/bin/grep lustre',
    require => [Exec['modprobe zfs'], Package['lustre'], Class['network'],
                File['/etc/modprobe.d/lustre.conf']],
    before  => Service['corosync'],
  }
  file { '/usr/lib/ocf/resource.d/heartbeat/ZFS':
    source => $zfs_heartbeat_script,
    owner  => 'root',
    group  => 'root',
    mode   => '0744',
    before => Service['corosync'],
  }
  $corosync_ips = flatten($::corosync::unicast_addresses)
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
    $cipher = $device[cipher]
    $hexadecimal_kg = $device[hexadecimal_kg]

    if($cipher != undef and $hexadecimal_kg != undef){
        # cipher and key are defined
        $ipmi_params = {
        'pcmk_host_list'       => $name,
        'login'                => $user,
        'passwd_script'        => "/root/.passwd-ipmi-${name}.sh",
        'ipaddr'               => $ipaddr,
        'hexadecimal_kg'       => $hexadecimal_kg,
        'cipher'               => $cipher,
        'lanplus'              => true,
        'pcmk_reboot_retries'  => 10,
        'pcmk_off_retries'     => 10,
        'pcmk_list_retries'    => 10,
        'pcmk_monitor_retries' => 10,
        'pcmk_status_retries'  => 10,
      }
    }
    else{
        $ipmi_params = {
        'pcmk_host_list'       => $name,
        'login'                => $user,
        'passwd_script'        => "/root/.passwd-ipmi-${name}.sh",
        'ipaddr'               => $ipaddr,
        'lanplus'              => true,
        'pcmk_reboot_retries'  => 10,
        'pcmk_off_retries'     => 10,
        'pcmk_list_retries'    => 10,
        'pcmk_monitor_retries' => 10,
        'pcmk_status_retries'  => 10,
      }
    }

    file { "/root/.passwd-ipmi-${name}.sh":
      show_diff => false,
      owner     => 'root',
      group     => 'root',
      mode      => '0700',
      before    => Service['corosync'],
      content   => "#!/bin/bash
echo $password
"
    }
    -> cs_primitive { "ipmi-poweroff-${name}" :
      ensure          => present,
      primitive_class => 'stonith',
      primitive_type  => 'fence_ipmilan',
      operations      => {
        'monitor'     => { 'interval' => '60s'},
      },
      parameters      => $ipmi_params,
    }
    -> cs_location { "ipmi-poweroff-${name}-location":
      primitive => "ipmi-poweroff-${name}",
      node_name => $name,
      score     => '-INFINITY',
    }
  }

  cs_rsc_defaults { 'resource-stickiness' :
    value => '100',
  }
  cs_rsc_defaults { 'migration-threshold' :
    value => '5',
  }
  cs_rsc_defaults { 'start-failure-is-fatal' :
    value => false,
  }
  cs_rsc_defaults { 'batch-limit' :
    value => $batch_limit,
  }
  cs_rsc_defaults { 'migration-limit' :
    value => '2',
  }
  cs_rsc_defaults { 'stonith-action' :
    value => 'off',
  }
  cs_rsc_defaults { 'stonith-timeout' :
    value => '120s',
  }
}

class lustre::server::patch_monitor() {
  # Without this patch, the monitor function think OST1 is running, but its 
  # actually OST11, the whitespace force OST11 to only match OST11

  # This bug was fixed in LU-10098 and not required on
  # newer Lustre 2.10.3 and 2.11.0
  patch::file { '/usr/lib/ocf/resource.d/lustre/Lustre':
    diff_content => '99c99
<     grep -q $(realpath "$OCF_RESKEY_mountpoint") /proc/mounts
---
>     mountpoint -q $(realpath "$OCF_RESKEY_mountpoint")
',
    before       => Service['corosync'],
    require      => Package['lustre-resource-agents', 'patch'],
  }
}

# For clean shutdown/reboot
# Based on LU-8384, patched in 2.13
class lustre::server::systemd(){
  file { '/etc/systemd/system/lustre.service':
    notify  => Service['lustre'],
    content => '[Unit]
Description=Lustre shutdown
After=network.target network-online.target lnet.service
DefaultDependencies=false
Conflicts=umount.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/bin/true
ExecStop=/usr/bin/umount -a -t lustre
ExecStop=/usr/sbin/lustre_rmmod

[Install]
WantedBy=sysinit.target
WantedBy=final.target',
  }
  -> service { 'lustre':
    ensure => 'running',
    enable => true,
  }
  # patch lnet for clean reboot/shutdown
  file { '/usr/lib/systemd/system/lnet.service':
    notify  => Service['lnet'],
    content => '[Unit]
Description=lnet management

Requires=network-online.target
After=network-online.target openibd.service rdma.service

[Service]
Type=oneshot
RemainAfterExit=true
ExecStop=/usr/sbin/lustre_rmmod ptlrpc
ExecStop=/usr/sbin/lustre_rmmod libcfs ldiskfs

[Install]
WantedBy=multi-user.target',
  }
  -> service { 'lnet':
    ensure => 'running',
    enable => true,
  }
}

class lustre::server::nrpe(){
  nrpe::command {
    'check_zfs':
      ensure  => present,
      command => 'check_zfs';
  }
  nrpe::plugin {
    'check_zfs':
      ensure => present,
      source => 'puppet:///modules/lustre/check_zfs',
  }
  nrpe::command {
    'check_targets':
      ensure  => present,
      command => 'check_targets';
  }
  nrpe::plugin {
    'check_targets':
      ensure => present,
      source => 'puppet:///modules/lustre/check_targets',
  }
  nrpe::command {
    'check_lustre_healthy':
      ensure  => present,
      command => 'check_lustre_healthy';
  }
  nrpe::plugin {
    'check_lustre_healthy':
      ensure => present,
      source => 'puppet:///modules/lustre/check_lustre_healthy',
  }
  nrpe::command {
    'check_pcs_stonith':
      ensure  => present,
      sudo    => true,
      command => 'check_pcs_stonith';
  }
  nrpe::plugin {
    'check_pcs_stonith':
      ensure => present,
      source => 'puppet:///modules/lustre/check_pcs_stonith',
  }
}
