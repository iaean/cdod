
Apache configuration
--------------------

```apache
LoadModule perl_module modules/mod_perl.so
PerlRequire /path/to/cdod/perl/startup.pl

 <IfModule mod_perl.c>
  <IfModule mod_qos.c>
   <Location /cdod>
    SetHandler perl-script
    PerlResponseHandler Cdod
    Order deny,allow
    Deny from all
    Allow from localhost
   </Location>
  </IfModule>
 </IfModule>
```

Throttling via mod_qos
----------------------

```apache
LoadModule qos_module modules/mod_qos.so
QS_DisableHandler on
QS_ErrorResponseCode 503
QS_ClientEntries 4096

# Limit to 1 concurrent request
QS_LocRequestLimit /cdod 1

# Limit to 1 request per client per minute
SetEnvIf Request_URI /cdod QS_Limit=yes
QS_ClientEventLimitCount 2 60
```
