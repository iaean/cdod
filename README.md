# Cluster device of the day

This is an apache mod_perl module, that discovers the cluster state
of F5 and A10 load-balancers and NetScreen firewalls via SNMP and
returns the results as JSON. Implementing asynchronous SNMP polling
makes it really fast. The JSON is very useful for development of dashboard applications.

### Requirements

* Apache with [mod_perl][0] enabled.
* To control access frequency, usage of [mod_qos][1] is strongly recommended.

### Configuration

Drop the module to your Apache. See [Apache.md](doc/Apache.md)
for some config snippets. Provide a [XML](doc/DEV.example.xml)
that specifies the devices to be monitored. Put the XML URL
to the top of the module.
```perl
# http://svn.example.com/repo/head/devices.xml
# optional user: 'foobar'
# and password: 'secret'
# file:///path/to/devices.xml
#
my $XML = 'http://svn.example.com/repo/head/devices.xml';
my $HTTPuser = undef;
my $HTTPpass = undef;
```

### Contribution

All your contributions are welcome.


[0]: http://perl.apache.org/
[1]: http://opensource.adnovum.ch/mod_qos/
