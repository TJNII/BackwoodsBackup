Fixture Generation
==================

Run in a container with spec/fixtures mounted at /fixtures and a ramdisk at /ramdisk

Generate source backup files
----------------------------

```bash
mkdir /tmp/fixture_target
for((c=0;$c<16;c++)); do dd bs=8 count=1 if=/dev/urandom of="/tmp/fixture_target/file${c}"; done
```

cleaner_fixtures generation
---------------------------

Existing fixtures should be deleted ahead of time.

```bash
mkdir /fixtures/cleaner_fixtures/cleaner_backup
for((c=0;$c<4;c++)); do
  /app/bin/backup -v -f /fixtures/cleaner_fixtures/fixture_generation/config/fixture_set_1.yml
  /app/bin/backup -v -f /fixtures/cleaner_fixtures/fixture_generation/config/fixture_set_2.yml
  sleep 1
done
```
