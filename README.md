BackwoodsBackup
===============

### In Progress / Incomplete

This project contains a Dockerized backup system for Linux systems.
It's primary goals are:

- Support AWS S3 cloud storage
- Optimize for low-bandwidth uplinks
- Optimize for storage cost
- Support secure, client side, multiple key encryption

It is not:

- A bare metal backup solution, /dev special files are not supported.

This tool is built for users with large volumes of data behind low bandwidth pipes, needing cost-effective offsite backups.
It is built to run inside Docker on Linux, making Docker the only host requirement.
(Docker for Mac should work, but is untested.  Windows is unsupported.)
It performs block level de-duplication as a core function.
An identical block of data in multiple files or on multiple hosts, when encrypted with the same keys, will only be stored once.
Data is encrypted using RSA/AES encryption client side.
The private key is not used for backups and can be safely stored offline.

Configuration & Usage
---------------------

### Generating RSA Keypairs

The encryption keypairs are standard RSA keypairs.

A keypair can be generated with OpenSSL:

```
openssl genrsa -out rsa.key.pem 2048
openssl rsa -in rsa.key.pem -outform PEM -pubout -out rsa.pub.pem

```

Note this creates a keypair with no password.
Data encryption keys are *strongly* recommended to be stored offline.
Private keys are not needed to perform backups, only restores.

Note that more keys will increase S3 storage costs as a file is stored in S3 for each keypair.

### S3 bucket configuration

TODO

### Configuration

TODO

### Running the backup

TODO

### Restoring

TODO

License & Author
----------------

Copyright 2019 Tom Noonan II (TJNII)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
