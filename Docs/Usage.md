Usage
-----

See [Docs/Configuration.md](Docs/Configuration.md) for details on the configuration files.

The following examples are minimal, all commands take the ```-h``` flag to show more advanced help.

Backups
-------

Scheduling is left as an exercise to the reader, as that will likely be specific to the environment.
The backup engine does not handle schedules, that is left to the caller.

Due to the design of the backup engine the backup utility can be killed and restarted with minimal penalty.
The block de-duplication system will detect and use the previously uploaded blocks, regardless of whether they are associated with a manifest.
The only penalty is disk-io re-reading the already completed files.

Note that the backup engine does not thread: this is due to race conditions in the block encoder, thread safety issues, and the backup engine generally being bound by IO, not CPU, in tests.

### Filesystem communicator Backups

Example Assumptions:
- Config files in /etc/backwoods_backup
- Filesystem backup output directory in /mnt/backups

```bash
# Note the read only volume binds
docker run --rm -ti -v /mnt/backups:/backups -v /etc/backwoods_backup:/config:ro -v /:/host:ro --tmpfs /ramdisk tjnii/backwoods-backup:latest backup -f /config/backup_config.yml
```

### S3 communicator Backups

Example Assumptions:
- Config files in /etc/backwoods_backup

```bash
# Note the read only volume binds
docker run --rm -ti -v /etc/backwoods_backup:/config:ro -v /:/host:ro --tmpfs /ramdisk tjnii/backwoods-backup:latest backup -f /config/backup_config.yml
```

Cleaner
-------

Scheduling is left as an exercise to the reader, as that will likely be specific to the environment

The cleaner is multi-thread but due to Ruby's GIL it will currently only use one core in practice.
It is intended to be run on a dedicated host.

### Filesystem communicator clean

Example Assumptions:
- Config files in /etc/backwoods_backup
- Filesystem backup directory in /mnt/backups

```bash
# Note the read only volume binds
docker run --rm -ti -v /mnt/backups:/backups -v /etc/backwoods_backup:/config:ro tjnii/backwoods-backup:latest clean -f /config/cleaner_config.yml
```

### S3 communicator clean

**NOTE**: This is intended to be run on a EC2 host.
The cleaner will list every file in the bucket, and will download every manifest.
This needs to be run in EC2 for both speed and cost.

```bash
# Note the read only volume binds
docker run --rm -ti -v /etc/backwoods_backup:/config:ro tjnii/backwoods-backup:latest clean -f /config/cleaner_config.yml
```

Restore
-------

When restoring the following must be known:

- The manifest path, starting with manifests/.  This is in the backup output, and can be looked up via ls for filesystem backups and in the AWS S3 console.
- A regex matching the target files to restore.

Note that the restore engine does not thread: This is due to the restore being bound by IO, not CPU, in tests.

### Filesystem communicator restore

Example Assumptions:
- Config files in /etc/backwoods_backup
- Filesystem backup directory in /mnt/backups
- Restore path at /tmp/restore
- Target manifest at manifests/myhost/myset/1548029915
- The complete backup will be restored

```bash
# Note the read only volume binds
docker run --rm -ti -v /mnt/backups:/backups:ro -v /etc/backwoods_backup:/config:ro -v /tmp/restore:/restore tjnii/backwoods-backup:latest -f /config/restore_config.yml -t '.*' -o /restore -m manifests/myhost/myset/1548029915
```

### S3 communicator restore

Example Assumptions:
- Config files in /etc/backwoods_backup
- Restore path at /tmp/restore
- Target manifest at manifests/myhost/myset/1548029915
- The complete backup will be restored

```bash
# Note the read only volume binds
docker run --rm -ti -v /etc/backwoods_backup:/config:ro -v /tmp/restore:/restore tjnii/backwoods-backup:latest -f /config/restore_config.yml -t '.*' -o /restore -m manifests/myhost/myset/1548029915
```
