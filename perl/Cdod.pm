
use strict;
use warnings FATAL=>'all', NONFATAL=>'redefine';

package Cdod;

use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::Const -compile => qw(:common :config :http :methods REMOTE_HOST);
use Apache2::Response ();
use Apache2::Connection ();
use APR::Table;

#use CGI qw/:standard/;
#use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper; $Data::Dumper::Indent = 1;
use Net::SNMP;
use XML::Simple qw(:strict);
use XML::LibXML;
use LWP;
use JSON;
use Sys::Hostname;


# http://svn.example.com/repo/head/devices.xml
#  optional user: 'foobar'
#  and password: 'secret'
# file:///path/to/devices.xml
#
my $XML = 'http://svn.example.com/repo/head/devices.xml';
my $HTTPuser = undef;
my $HTTPpass = undef;


STDIN->autoflush;
STDOUT->autoflush;
STDERR->autoflush;

my $ns_hook = sub {
  my ($d, $o, $i, $v) = @_;
  $d->{oidcount}++;
  if ($v == 2) { $d->{status} = 'active'; }
  elsif ($v == 3 || $v == 4) { $d->{status} = 'standby'; }
  else { $d->{status} = 'unknown'; }
};
my $a10_hook = sub {
  my ($d, $o, $i, $v) = @_;
  $d->{oidcount}++;
  if ($v == 0) { $d->{status} = 'standby'; }
  elsif ($v == 1) { $d->{status} = 'active'; }
  else { $d->{status} = 'unknown'; }
};
my $f5_hook = sub {
  my ($d, $o, $i, $v) = @_;
  $d->{oidcount}++;
  SWITCH: for ($o) {
    /^sysAttrFailoverUnitMask$/o && do {
      if (!exists $d->{status}) {
        if ($v == 0) { $d->{status} = 'standby'; }
        else { $d->{status} = 'active'; }
      }
      last; };
    /^sysCmFailoverStatusId$/o && do {
      if ($v == 3) { $d->{status} = 'standby'; }
      elsif ($v == 4) { $d->{status} = 'active'; }
      else { $d->{status} = 'unknown'; }
      last; };
    /^sysCmFailoverStatusSummary$/o && do {
      $d->{status_line} = $v;
      last; };
  }
};

my $snmpTable = {
  'vendor' => {
    'netscreen' => {
      'nsrpVsdMemberStatus' => {
        'oid'     => '1.3.6.1.4.1.3224.6.2.2.1.3',
        'hook'    => $ns_hook,
      },
    },
    'a10' => {
      'axHAGroupLocalStatus' => {
        'oid'     => '1.3.6.1.4.1.22610.2.4.3.17.2.2.1.2',
        'hook'    => $a10_hook,
      },
    },
    'f5' => {
      'sysAttrFailoverUnitMask' => {
        'oid'     => '1.3.6.1.4.1.3375.2.1.1.1.1.19',
        'hook'    => $f5_hook,
      },
      'sysCmFailoverStatusId' => {
        'oid'     => '1.3.6.1.4.1.3375.2.1.14.3.1',
        'hook'    => $f5_hook,
      },
      'sysCmFailoverStatusSummary' => {
        'oid'     => '1.3.6.1.4.1.3375.2.1.14.3.4',
        'hook'    => $f5_hook,
      },
    },
  },
  'oids' => {
    'sysObjectID' => {
      'oid'     => '1.3.6.1.2.1.1.2',
      'hook'    => sub { my ($d, $o, $i, $v) = @_; $d->{oidcount}++; $d->{objID} = $v; },
    },
    'sysUpTime' => {
      'oid'     => '1.3.6.1.2.1.1.3',
      'hook'    => sub { my ($d, $o, $i, $v) = @_; $d->{oidcount}++; $d->{upTime} = $v; },
    },
  },
};

my $config = {
  'max_oids_per_get'  => '16',
  'max_repetitions'   => '8',
  'snmp_version'      => 'snmpv2c',
};

my $ua = LWP::UserAgent->new();
my $origin = hostname;

sub handler {
  my $r = shift;
  unless ($r->method_number == Apache2::Const::M_GET) {
    $r->allowed($r->allowed | (1<<Apache2::Const::M_GET));
    return Apache2::Const::HTTP_METHOD_NOT_ALLOWED; }

  while (my ($ven, $vref) = each %{$snmpTable->{vendor}}) {
    while (my ($oid, $oref) = each %{$vref}) {
      $snmpTable->{oids}->{$oid} = $oref; } }
  while (my ($oid, $oref) = each %{$snmpTable->{oids}}) {
    $snmpTable->{reverse}->{oids}->{$oref->{oid}} = $oid; }

  ### print Dumper($snmpTable);

  $config->{xml} = retrieveConfig(KeyAttr=> { device=> '+name' },
                                  ForceArray=> [ 'device' ],
                                  URL=> $XML, username=> $HTTPuser, password=> $HTTPpass);
  if (!$config->{xml}) { # Ooops.
    return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR; }

  $r->headers_out->add('Cache-Control' => 'private, no-store, no-cache, max-age=0');
  $r->headers_out->add('Pragma' => 'no-cache');
  $r->headers_out->add('Expires' => '-1');

  $r->content_type('application/json; charset=UTF-8');
  $r->status_line(Apache2::Const::HTTP_OK . " OK");
  $r->status(Apache2::Const::HTTP_OK);

  foreach my $cref (@{$config->{xml}->{devices}->{cluster}}) {
    while (my ($dev, $dref) = each %{$cref->{device}}) {
      if ($dref->{vendor} =~ /^([^:]+):/o) { $dref->{vendor} = $1 }
      if (lc($dref->{vendor}) !~ /^a10|f5|netscreen$/) {
        delete $config->{xml}->{devices}->{device}->{$dev}; next; }
      init_session($dref); } }
  while (my ($dev, $dref) = each %{$config->{xml}->{devices}->{device}}) {
    if ($dref->{vendor} =~ /^([^:]+):/o) { $dref->{vendor} = $1 }
    if (lc($dref->{vendor}) !~ /^a10|f5|netscreen$/) {
      delete $config->{xml}->{devices}->{device}->{$dev}; next; }
    init_session($dref); }

  snmp_dispatcher(); # Enter the event loop

  my $time = localtime;
  my $json = { time=>$time, config=>$XML, source=>$origin, devices=>[], cluster=>[] };
  while (my ($dev, $dref) = each %{$config->{xml}->{devices}->{device}}) {
    my ($s, $l, $t, $o) = get_status($dref);
    push @{$json->{devices}}, { name=>$dev, ip=>$dref->{ip}, vendor=>$dref->{vendor},
                                alive=>$dref->{oidcount} > 0 ? 'yes' : 'no',
                                oidmatch=> defined $o ? ( $o =~ /.*\.$dref->{oid}$/ ? 'yes' : 'no' ) : undef,
                                status=>$s, status_line=>$l, uptime=>$t, objectid=>$o }; }
  foreach my $cref (@{$config->{xml}->{devices}->{cluster}}) {
    my $c = { id=>$cref->{id}, devices=>[] };
    while (my ($dev, $dref) = each %{$cref->{device}}) {
      my ($s, $l, $t, $o) = get_status($dref);
      push @{$c->{devices}}, { name=>$dev, ip=>$dref->{ip}, vendor=>$dref->{vendor},
                               alive=>$dref->{oidcount} > 0 ? 'yes' : 'no',
                               oidmatch=> defined $o ? ( $o =~ /.*\.$dref->{oid}$/ ? 'yes' : 'no' ) : undef,
                               status=>$s, status_line=>$l, uptime=>$t, objectid=>$o };
    }
    push @{$json->{cluster}}, $c; }

  print to_json($json, {utf8=> 1});
  return Apache2::Const::DONE;
}
1;
  

sub get_status {
  my $dref = shift;
  my $s = exists $dref->{status} ? $dref->{status} : undef;
  my $t = exists $dref->{upTime} ? $dref->{upTime} : undef;
  my $o = exists $dref->{objID} ? $dref->{objID} : undef;
  my $l = exists $dref->{status_line} ? $dref->{status_line} : undef;
  return $s, $l, $t, $o; }

sub init_session {
  my $dref = shift;
  $dref->{session} = undef;
  $dref->{oidcount} = 0;
  while (my ($oid, $oref) = each %{$snmpTable->{vendor}->{lc($dref->{vendor})}}) {
    push @{$dref->{oids}}, $oref->{oid}.".0"; }
  while (my ($oid, $oref) = each %{$snmpTable->{oids}}) {
    push @{$dref->{oids}}, $oref->{oid}.".0"; }
  my ($session, $error) = Net::SNMP->session(
      -hostname=> $dref->{ip},
      -nonblocking=> 0x1,
      -community=> $dref->{community},
      -timeout=> 1,
      -retries=> 3,
      -version=> $config->{snmp_version},
      -port=> 161);
  if (defined($session)) { $dref->{session} = $session; }
  if (defined($dref->{session}) && defined (@{$dref->{oids}})) {
    # Simple SNMP (Multi) GET
    my $snmp_response = $dref->{session}->get_request(
      -varbindlist => [ splice(@{$dref->{oids}},0,$config->{max_oids_per_get}) ],
      -callback    => [ \&snmp_catcher, $dref ]); } }

sub snmp_catcher {
  my ($session, $dref) = @_;
  if (defined($session->var_bind_list)) {
    my $slot_table = $session->var_bind_list;
    while (my ($oid, $value) = each %{$slot_table}) {
      if ($value =~ /^noSuchInstance|noSuchObject$/i) { next; }
      my @tree = split(/\./, $oid);
      my $base = join('.', @tree);
      while (!grep(/^$base/, (keys %{$snmpTable->{reverse}->{oids}},
                              keys %{$snmpTable->{reverse}->{index}}))) {
        splice(@tree, -1);
        $base = join('.', @tree); }
      my $idx = $oid;
      $idx =~ s/^$base\.//;

      if (defined $snmpTable->{reverse}->{oids}->{$base}) {
        ### print $session->hostname, ": ", $snmpTable->{reverse}->{oids}->{$base}, ".$idx => $value\n";
        $snmpTable->{oids}->{$snmpTable->{reverse}->{oids}->{$base}}->{hook}($dref, $snmpTable->{reverse}->{oids}->{$base}, $idx, $value);

        # REVIEW: We are right recursive, here ???
        if ((defined @{$dref->{oids}}) && (scalar(@{$dref->{oids}}) > 0)) {
          my $snmp_response = $dref->{session}->get_request(
            -varbindlist => [ splice(@{$dref->{oids}},0,$config->{max_oids_per_get}) ],
            -callback    => [ \&snmp_catcher, $dref ]); }
      }
      else { }
    }
    # REVIEW: We are right recursive, here ???
  }
  else { # Error. No response.
    ### print $session->hostname, ": Ooops. No response. ", $session->error, "\n";
  }
  $session->error_status }

sub retrieveHTTPData {
  my ($url, $user, $passwd, $to) = @_;
  my $rqst = HTTP::Request->new('GET' => "$url");
  if (defined $to) { $ua->timeout($to); }
  $rqst->header('Accept' => 'text/plain');
  if (defined $user && defined $passwd) {
    $rqst->authorization_basic($user, $passwd); }
  my $rspn = $ua->request($rqst);
  if ($rspn->is_success) { return $rspn->content; }
  else {
    printf STDERR "%s\nStatus: %s\n", $rspn->request->uri, $rspn->status_line;
    return undef; } }

sub retrieveConfig {
  if(@_ % 2) {
    print STDERR "Error: Options must be name=>value pairs\n";
    return undef; }
  my %cfg_spec = @_;
  my $cfg_config_file;
  my $xmlparser = XML::LibXML->new();
  my $xml;
  if (!defined $cfg_spec{URL}) {
    $cfg_config_file = '-';
    ### print STDERR "Parsing XML...\n";
    $xml = eval { $xmlparser->parse_file($cfg_config_file) };
    if ($@) { print STDERR "Error: Invalid XML spec\n"; return undef; } }
  else {
    my $cfg_url = $cfg_spec{URL};
    my $cfg_user = $cfg_spec{username};
    my $cfg_pass = $cfg_spec{password};
    ### print STDERR "Retrieving $cfg_url...\n";
    $cfg_config_file = retrieveHTTPData($cfg_url, $cfg_user, $cfg_pass, 10);
    if (!defined $cfg_config_file) { print STDERR "Error: Couldn't load config\n"; return undef; }
    ### print STDERR "Parsing $cfg_url...\n";
    $xml = eval { $xmlparser->parse_string($cfg_config_file) };
    if ($@) { print STDERR "Error: Invalid XML spec\n"; return undef; } }

  # NOTE: Because we can't re-read streamed STDIN,
  #       we had to used the XML doc slurped above.
  my $cfg_config = eval { XMLin($xml->serialize(),
                                SuppressEmpty=> undef,
                                KeyAttr=> $cfg_spec{KeyAttr},
                                ForceArray=> $cfg_spec{ForceArray}) };
  if ($@) { print STDERR "Error: Invalid XML spec\n"; return undef; }
  return $cfg_config; }
