
`sysObjectID.0` and `sysUpTime.0` are used to SNMPping all devices.

NetScreen
---------

The info is in `nsrpVsdMemberTable`.
```
 nsrpVsdMemberUnitId.0 = INTEGER: 7455360
 nsrpVsdMemberUnitId.1 = INTEGER: 7426176
 nsrpVsdMemberStatus.0 = INTEGER: 3
 nsrpVsdMemberStatus.1 = INTEGER: 2
```

The `nsrpVsdMemberUnitId` of the device is available
by getting `nsrpGeneralLocalUnitId.0`

But it seems the first row of `nsrpVsdMemberTable`
is allways the device itself.
So getting `nsrpVsdMemberStatus.0` should be sufficient.
The values are defined as:
```
 0 | Undefined
 1 | init
 2 | Master
 3 | Primary Backup
 4 | Backup
 5 | ineligible
 6 | inoperable
``` 

F5 BIG-IP
---------

For old firmwares the info is in `sysAttrFailoverUnitMask.0`
The values are defined as:

> This data indicates whether the machine is active or standby.
> The value for this data could be 0, 1, 2, or 3.
> The values of 1 and 2 are only defined for an active-active
> installation. If two boxes are both active, value for unit 1
> will be 1 and value for unit 2 will be 2.
> Otherwise, for active unit, this value is 3; for stand-by unit,
> this value is 0.

For actual firmwares the info is in `sysCmFailoverStatusTable`.
``` 
 sysCmFailoverStatusId.0 = INTEGER: 4
 sysCmFailoverStatusStatus.0 = STRING: "ACTIVE"
 sysCmFailoverStatusColor.0 = INTEGER: 0
 sysCmFailoverStatusSummary.0 = STRING: "4/5 active"
```

We are retrieving `sysCmFailoverStatusId.0` and `sysCmFailoverStatusSummary.0`  
`sysCmFailoverStatusId` is defined as:
```
 0 | undefined
 1 | offline
 2 | forced offline
 3 | standby
 4 | active
```
`sysCmFailoverStatusColor` is defined as:
```
 green(0)  the system is functioning correctly;
 yellow(1) the system may be functioning suboptimally;
 red(2)    the system requires attention to function correctly;
 blue(3)   the system's status is unknown or incomplete;
 gray(4)   the system is intentionally not functioning (offline);
 black(5)  the system is not connected to any peers."
```

A10 AX
------

The info is in `nsrpVsdMemberTable`.
```
 axHAGroupID.0 = INTEGER: 0
 axHAGroupLocalStatus.0 = INTEGER: 1
 axHAGroupLocalPriority.0 = INTEGER: 150
 axHAGroupPeerStatus.0 = INTEGER: 0
 axHAGroupPeerPriority.0 = INTEGER: 150
```
We are retrieving `axHAGroupLocalStatus.0`
Its defined as:
```
 0 | standby
 1 | active
 9 | unconfigured
```
