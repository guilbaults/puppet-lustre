class lustre::ldev(
  $devs,
){

  concat { '/etc/ldev.conf':
    ensure => present,
    before => Exec['modprobe lustre'],
  }
  concat::fragment{'header of ldev.conf':
    target  => '/etc/ldev.conf',
    content => '#local  foreign  label    zfs:device-path
',
    order   => 10,
  }

  $devs.each | $dev | {
    concat::fragment { "ldev line ${dev}":
      target  => '/etc/ldev.conf',
      content => "${dev}
",
      order   => 50,
    }
  }
}
