Configuration
=============

Generating RSA Keypairs
-----------------------

The encryption keypairs are standard RSA keypairs.

A keypair can be generated with OpenSSL:

```
openssl genrsa -out rsa.key.pem 2048
openssl rsa -in rsa.key.pem -outform PEM -pubout -out rsa.pub.pem

```

Note this creates a keypair with no password.
Data encryption keys are *strongly* recommended to be stored offline.
Private keys are not needed to perform backups, only restores.

Note that more keys will increase S3 storage costs as a small file is stored in S3 for each keypair.

S3 bucket configuration
-----------------------

A CloudFormation stack is provided in CloudFormation/.
This stack:

- Creates a target S3 bucket for backups
- Creates 3 IAM users for backups, restores, and cleans
  - IAM keys are not created as they cannot be securely exported.  The user must manually create IAM keys under the premade users.

Config Files
------------

All config files are YAML.
The [yaml extend](https://github.com/magynhard/yaml_extend) gem is in use to allow multiple files to comprise a single config.

### Common Config Blocks

**Logging Block**

Optional

```yaml
logging:
  # Integer corresponding to Ruby log level
  # 0: Debug
  # 1: Info
  # 2: Warn
  # 3: Error
  level: 2
```

**Communicator Block**

The communicator block configures the communicator: the engine that communicates with the backend storage.

Currently two backends are supported:

- **Filesystem**: Backups to a local disk
- **S3**: Backups to AWS S3

**NOTE ON COMMUNICATOR BACKENDS**: The data storage method is identical across backends.
It is possible to use a filesystem communicator and copy the contents to a S3 bucket to pre-populate the bucket.
This allows use of a high-speed link or a Snowball to initially populate the backups, and then subsequent backups will only upload changes via block deduplication.
The only caveat is that the directories in the filesystem communicator base path must be top level in the bucket, any nesting will cause detection of the pre-populated blocks to fail.

Filesystem Communicator:

```yaml
communicator:
  type: filesystem
  backend_config:
    # Base Path: Base directory to store the backups *inside the container*
    # Host bind path isn't used for filesystem communicator output
    base_path: /backups/
```

S3 Communicator:

```yaml
communicator:
  type: s3
  backend_config:
    # Bucket: S3 bucket name, output from the CloudFormation template
    bucket: bucket-name

    # Storage Class: S3 storage class to use
    # Note that different storage classes have minimum storage durations, see the S3 pricing docs
    # Glacier not currently supported due to it being asynchronous
    storage_class: 'ONEZONE_IA'

    # S3 client config: Config passed directly to Aws::S3::Client.new(): https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#initialize-instance_method
    s3_client_config:
      region: [AWS Region]
      credentials:
        # These credentials should be created under the BackupsIAMUser created by the CloudFormation Template in IAM
	# Note that the backups, cleaner, and restores all use different IAM users and keys for security.
        access_key_id: [Access Key]
        secret_access_key: [Secret Key]
```

### Encryption Block

This block configures the encryption engine which encrypts the backups.

```yaml
encryption:
  # Currently only RSA encryption is supported
  type: RSA

  # Keys: Hash of key pairs used to encrypt/decrypt both the manifests and block data
  # Note that the name is critical and must match across all key uses.
  # The name is used for lookups when decrypting, if the name does not match then the lookup will fail.
  keys:
    # Key name
    key_1:
      # Public key path *inside the container*.
      # Host bind path isn't used for key reads
      # Only one of public_key/private_key is required depending on operation.
      public_key: /config/keys/key_1.pub.pem
      private_key: /config/keys/key_1.key.pem
    key_2:
      public_key: /config/keys/key_2.pub.pem
      private_key: /config/keys/key_2.key.pem

  # Manifest only keys: Hash of key pairs used to encrypt only the manifests
  # These keys are intended for use by the cleaner to decrypt the manifests to check in use blocks.
  # Same format as keys section above.
  manifest_only_keys:
    manifest_1:
      public_key: /config/keys/manifest_1.pub.pem
      private_key: /config/keys/manifest_1.key.pem
```

Backup Config
-------------

```yaml
communicator: [communicator block, see above]
encryption: [Encryption block, see above]

# Host: System hostname
host: some-host.local

# Paths: List of paths to back up
# These are relative to docker_host_bind_path, see below
paths:
 - /home
 - /etc

# Set name: unique name for this backup set
# This is a grouping identifier for the manifests to tell different backups apart for operator convenience.
# It is part of the manifest path, so special characters should be avoided, but it is not parsed or otherwise used.
set_name: home_and_etc

# Docker bind path: Docker bind path of the host filesystem in the container
# This is used to exclude the bind path from the filesystem paths, for example to prevent /home/ from becoming /host/home in the backups.
# OPTIONAL: Default: '/host'
docker_host_bind_path: '/host'

# Path Exclusions: List of regexes of paths to exclude
# OPTIONAL: default: No exclusions
path_exclusions:
  - "^/proc/"
  - "^/sys/"
  - "^/dev/"
  - "^/tmp/"
  - "^/run/"
  - "^/var/lib/docker"
  - "^/mnt/"

# Chunk size: Size in bytes to break up files for deduplication
# OPTIONAL: Default: 20MB
chunk_size: 20971520

# Temp dirs: Hash of size in bytes -> path pairs of tempdir spool spaces to use
# Size is the maximum file size to store in that space.  (Use a arbitrarily large size, i.e 1024**5 to create a default)
# Paths are bind paths inside the container
# It is strongly recommended to set up a ramdisk and a temp space outside of the container COW filesystem for performance.
# 
# OPTIONAL: Default: Ruby Tempfile default tempdir
tempdirs:
  1073741824: /ramdisk
  1125899906842624: /spool
```

### Complete Example:

```yaml
host: myhost.local
set_name: root
paths:
  - /

communicator:
  type: s3
  backend_config:
    bucket: 'mybucket'
    storage_class: 'ONEZONE_IA'
    s3_client_config:
      region: us-east-2
      credentials:
        # Backup IAM user credentials
        access_key_id: [access-key]
        secret_access_key: [secret-key]

encryption:
  type: RSA
  keys:
    # Note that the backups only need the public key.  The private key can be kept offline.
    key_1:
      public_key: /config/keys/key_1.pub.pem
    key_2:
      public_key: /config/keys/key_2.pub.pem
  manifest_only_keys:
    manifest_1:
      public_key: /config/keys/manifest_1.pub.pem

tempdirs:
  1073741824: /ramdisk

path_exclusions:
  - "^/proc/"
  - "^/sys/"
  - "^/dev/"
  - "^/tmp/"
  - "^/run/"
  - "^/var/lib/docker"
  - "^/mnt/"
```

Restore Config
--------------

```yaml
communicator: [communicator block, see above]
encryption: [Encryption block, see above]
```

### Complete Example:

```yaml
communicator:
  type: s3
  backend_config:
    bucket: 'mybucket'
    s3_client_config:
      region: us-east-2
      credentials:
	# Restore IAM user credentials
        access_key_id: [access-key]
        secret_access_key: [secret-key]

encryption:
  type: RSA
  keys:
    # The restore only needs one of the private keys
    key_1:
      private_key: /config/keys/key_1.key.pem
```

Cleaner Config
--------------

```yaml
communicator: [communicator block, see above]
encryption: [Encryption block, see above]

# Cleaner: This block defines the retention settings within the bucket
# Note that different S3 storage classes have minimum storage durations, see the S3 pricing docs.
cleaner:
  # Minimum block age: Minimum age in seconds before a unused block will be removed
  # This is to prevent the cleaner from removing newly uploaded blocks before a manifest was written
  min_block_age: 86400

  # Minimum manifest age: Minimum age in seconds before a manifest will be removed
  min_manifest_age: 31536000

  # Minimum set manifests: Minimum number of manifests within a set that will be retained.
  # For example: This setting ensures the newest 20 manifests within a host/set pair will be retained, even if they are older than the minimum age
  min_set_manifests: 20

  # Verify block checksum: When true download all the blocks and verify the checksum passes.
  # Default value: false
  # UPGRADE WARNING: This will remove blocks created by version 1.0 of the tool as they do not contain checksums.
  # Defaults to false for both cost (true will cause all the blocks to be downloaded) and to prevent removing v1.0 blocks by default.
  verify_block_checksum: true
```

### Complete Example:

```yaml
communicator:
  type: s3
  backend_config:
    bucket: 'mybucket'
    s3_client_config:
      region: us-east-2
      credentials:
	# Cleaner IAM user credentials
        access_key_id: [access-key]
        secret_access_key: [secret-key]

encryption:
  type: RSA
  # The cleaner should not use the data keys as the data keys should be protected
  manifest_only_keys:
    # The restore only needs one of the manifest private keys
    manifest_1:
      public_key: /config/keys/manifest_1.key.pem

cleaner:
  min_block_age: 86400
  min_manifest_age: 31536000
  min_set_manifests: 20

```
