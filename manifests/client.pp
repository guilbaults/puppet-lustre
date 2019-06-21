class lustre::client(){

}

class lustre::client::nrpe(){
  nrpe::command {
    'check_lustre_client2servers':
      ensure  => present,
      command => 'check_lustre_client2servers';
  }
  nrpe::plugin {
    'check_lustre_client2servers':
      ensure => present,
      source => 'puppet:///modules/lustre/check_lustre_client2servers',
  }
}
