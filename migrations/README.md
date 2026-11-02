# Migrations

Scripts are named `vX.Y.Z-<slug>.sh` and run once, in version order, when an
update crosses that version, before the new release's installer runs. They must
be idempotent, so a rerun or a skipped intermediate release is harmless, and
they must write only to the documented agent-ready config paths.
