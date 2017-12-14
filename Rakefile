require 'puppet-lint/tasks/puppet-lint'

PuppetLint.configuration.send("disable_autoloader_layout")
PuppetLint.configuration.send("disable_documentation")

task :default => [:lint]
