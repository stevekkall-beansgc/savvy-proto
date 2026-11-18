#!/usr/bin/env python3
"""Restore the retained fictional app into a scratch DB and rehearse migrations.

Source actions are read-only. All CREATE/RESTORE/MIGRATE/DROP operations target
the distinct savvy-medallion containers. Original column values are fingerprinted
so additive defaults are not mistaken for rewrites of historical data.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    args = parser.parse_args()
    source = args.source_root.resolve()
    if source == ROOT or not (source / "compose.yaml").is_file():
        raise ValueError("Expected the separate retained synthetic checkout")
    source_base = ["docker", "compose", "-f", str(source / "compose.yaml"),
                   "--project-directory", str(source), "-p", "savvy-prototype", "exec", "-T", "db"]
    target_compose = ["docker", "compose", "-f", str(ROOT / "compose.medallion.yaml"), "-p", "savvy-medallion"]
    target_base = target_compose + ["exec", "-T", "db"]
    scratch = "savvy_migration_check_" + uuid.uuid4().hex[:12]

    def command(base, argv, **kwargs):
        return subprocess.run(base + argv, cwd=ROOT, timeout=60, check=True, **kwargs)

    def sql(base, database, query):
        return command(base, ["psql", "-XqAt", "-v", "ON_ERROR_STOP=1", "-U", "savvy_demo",
                              "-d", database, "-c", query], capture_output=True, text=True).stdout.strip()

    def fingerprint(database, table, columns):
        assert re.fullmatch(r"[a-z_]+", table)
        assert all(re.fullmatch(r"[a-z_]+", col) for col in columns)
        selected = ",".join('"' + col + '"' for col in columns)
        return json.loads(sql(target_base, database,
            "SELECT json_build_object('table','" + table + "','rows',count(*),'digest',"
            "md5(COALESCE(string_agg(md5(row_to_json(t)::text),'' ORDER BY md5(row_to_json(t)::text)),'')))"
            ' FROM (SELECT ' + selected + ' FROM public."' + table + '") t'))

    created = False
    try:
        with tempfile.TemporaryDirectory(prefix="savvy-migration-") as temporary:
            dump = Path(temporary) / "synthetic.dump"
            with dump.open("wb") as output:
                command(source_base, ["pg_dump", "-U", "savvy_demo", "-d", "advisor_economics_synthetic", "-Fc"], stdout=output)
            sql(target_base, "postgres", 'CREATE DATABASE "' + scratch + '"')
            created = True
            with dump.open("rb") as data:
                command(target_base, ["pg_restore", "-U", "savvy_demo", "-d", scratch, "--no-owner", "--no-acl", "--exit-on-error"],
                        stdin=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            metadata = json.loads(sql(target_base, scratch,
                "SELECT json_object_agg(table_name,columns) FROM (SELECT table_name,"
                "json_agg(column_name ORDER BY ordinal_position) AS columns FROM information_schema.columns "
                "WHERE table_schema='public' AND table_name <> 'schema_migrations' GROUP BY table_name) c"))
            before = [fingerprint(scratch, table, columns) for table, columns in sorted(metadata.items())]
            result = command(target_compose, ["run", "--rm", "-e", "DATABASE_URL=postgresql://savvy_demo@db/" + scratch,
                "-e", "SCHEMA=/tmp/savvy-migration-check.sql", "api", "bundle", "exec", "rails", "db:migrate"], capture_output=True, text=True)
            after = [fingerprint(scratch, table, columns) for table, columns in sorted(metadata.items())]
            if before != after:
                raise AssertionError("Migration rewrote original column values")
            checks = sql(target_base, scratch,
                "SELECT count(*) FROM pg_trigger WHERE tgname='medallion_no_update_delete'")
            if checks != "1":
                raise AssertionError("Append-only trigger missing after migration")
            report = {"status": "passed", "source_actions": "read-only dump", "scratch_database": scratch,
                      "original_table_fingerprints": before, "historical_columns_unchanged": True,
                      "migration_output": result.stdout, "source_replaced": False}
            target = ROOT / "artifacts/medallion/migration.json"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(report, indent=2) + "\n")
            print(f"Migration rehearsal passed: {len(before)} original tables retain all original column values.")
    finally:
        if created:
            sql(target_base, "postgres", 'DROP DATABASE "' + scratch + '" WITH (FORCE)')


if __name__ == "__main__":
    main()
