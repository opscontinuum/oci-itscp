# EBS SQL helpers

## cmclean.sql — NOT VENDORED

`cmclean.sql` is Oracle-supplied and distributed through My Oracle Support
(Doc ID 134007.1). It is not redistributable, so it is deliberately absent here.

Download the current version for your EBS release and place it in this directory as
`cmclean.sql`. `scripts/windows/Start-EBSAppTier.ps1` checks for it and fails loudly
rather than starting Concurrent Managers without it.

## Usage

Run as APPS with **all** Concurrent Managers down, then COMMIT. Required after any
Data Guard role transition — stale FND_CONCURRENT_QUEUES and ICM rows from the former
primary otherwise prevent managers from starting, with a confusing failure mode.
