# Snapshot_backup

Describes how to make daily and weekly backups using rsync, while preventing file duplication between the different backups.

It uses "snapshot"-style backups with hard links to create the illusion of multiple, full backups without much of the space or processing overhead.

Scripts and configuration examples are given for 

- Linux clients
- Windows clients (using cygwin)
- Synology server

[Continue reading](https://coertvonk.com/sw/application/snapshot-backup/snapshap-backup-rsync-479)