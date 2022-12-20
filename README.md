BackwoodsBackup
===============

This project contains a Dockerized backup system for Linux systems.
It's primary goals are:

- Support AWS S3 cloud storage
- Optimize for low-bandwidth uplinks
- Optimize for storage cost
- Support secure, client side, multiple key encryption

It is not:

- A bare metal backup solution:
  - /dev special files are not supported.
  - Hard links are not supported
- Optimized for processing speed.  It is intended for low-bandwidth links where it will be IO bound and CPU optimizations are past the point if diminishing returns.

This tool is built for users with large volumes of data behind low bandwidth pipes, needing cost-effective offsite backups.
It is built to run inside Docker on Linux, making Docker the only host requirement.
(Docker for Mac should work, but is untested.  Windows is unsupported.)
It performs block level de-duplication as a core function.
An identical block of data in multiple files or on multiple hosts, when encrypted with the same keys, will only be stored once.
Data is encrypted using RSA/AES encryption client side.
The private key is not used for backups and can be safely stored offline.

It is not intended to be a bare-metal backup solution.
As OSS restore media is freely available in a DR scenario this tool is intended to restore user specific data to a fresh OS install.

Main Components
---------------

**Backup**: This tool backs up files on local hosts.

**Cleaner**: This tool handles data retention and ensures general consistency in the data store.  This tool must be run regularly for proper operation, and is intended to be run adjacent to the storage (i.e. on a EC2 instance if S3 is used).

**Restore**: Restores files from a backup.

Backup Methodology
------------------

- Iterate over the provided path
  - If a file:
    - Checksum the file
    - Copy the file to tmpfile space.  This is done to avoid file modified during backup errors during the slower read/checksum block/encrypt block/upload operations.
    - Checksum the copy to ensure it hasn't changed
    - Read the file in blocks
    - Checksum the block
    - Use the checksum and length to see if the block already exists in the store.  If it does not:
      - Compress the block
      - Encrypt the block
      - Upload the block
  - Save information on the file/directory/symlink to the manifest
- Upload the manifest

This app is written to fail quickly on errors under the assumption that it's better to fail obviously than create an incomplete backup.
By default the manifest is not saved on errors.
This means that, by default, if a backup fails then the files backed up cannot be reconstructed.
This can be toggled at the backup tool command line.

**Files are not restorable without a manifest.**
The manifest saves the file names, checksums, and block mapping which is required to reconstruct files.
Without the block mapping files cannot be reconstructed.

Configuration & Usage
---------------------

Configuration: See [Docs/Configuration.md](Docs/Configuration.md)

Usage: See [Docs/Usage.md](Docs/Usage.md)

Testing
-------

As with all backups, any backups taken by this tool must be tested regularly by the operator.
A test suite is included, but it does not contain full unit test coverage and does not cover all use cases.
This tool is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND.
It is the responsibility of the operator to ensure all backups are valid and restorable.

**An untested backup is no backup!**

License & Author
----------------

Copyright 2023 Tom Noonan II (TJNII)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
