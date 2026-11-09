Frozen large experimental RTL snapshot.

- `standard/synthesis` path is restored from commit `505d1e4`
- `experimental large` path is copied from commit `8dac63f`

The experimental runners point at this tree so changes to the standard
`m4_filelist` sources cannot leak into the large reviewer-facing flow.
