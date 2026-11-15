#!/usr/bin/env python3
"""Rehearse a consistent synthetic backup restore without replacing the source DB.

Uses only Python's standard library and the pinned PostgreSQL container tools.
The exported PostgreSQL snapshot binds the dump and the source row fingerprints
even if another local session records new evidence during the rehearsal.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import queue
import subprocess
import tempfile
import threading
import uuid

ROOT = Path(__file__).resolve().parent.parent
SOURCE = "advisor_economics_synthetic"
BASE = ["docker", "compose", "exec", "-T", "db"]


def run(args, **kwargs):
    return subprocess.run(BASE + args, check=True, timeout=60, **kwargs)


def sql(database, statement):
    result = run(["psql", "-XqAt", "-v", "ON_ERROR_STOP=1", "-U", "savvy_demo",
                  "-d", database, "-c", statement], capture_output=True, text=True)
    return result.stdout.strip()


def fingerprint_sql(table):
    if not re.fullmatch(r"[a-z_]+", table):
        raise ValueError("Unexpected table identifier")
    return ("SELECT json_build_object('table','" + table + "','rows',count(*),"
            "'digest',md5(COALESCE(string_agg(md5(row_to_json(t)::text),'' "
            "ORDER BY md5(row_to_json(t)::text)),''))) FROM public.\"" + table + "\" t;")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=ROOT / "artifacts/cto-readiness/recovery.json")
    args = parser.parse_args()
    os.chdir(ROOT)
    scratch = "savvy_restore_check_" + uuid.uuid4().hex[:16]
    exporter = None
    created = False
    started = dt.datetime.now(dt.timezone.utc)
    try:
        exporter = subprocess.Popen(BASE + ["psql", "-XqAt", "-v", "ON_ERROR_STOP=1",
            "-U", "savvy_demo", "-d", SOURCE], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        output_lines = queue.Queue()

        def read_output():
            for line in exporter.stdout:
                output_lines.put(line)
            output_lines.put(None)

        reader = threading.Thread(target=read_output, daemon=True)
        reader.start()

        def snapshot_query(statement):
            marker = "savvy_snapshot_" + uuid.uuid4().hex
            exporter.stdin.write(statement + "\n\\echo " + marker + "\n")
            exporter.stdin.flush()
            lines = []
            while True:
                try:
                    line = output_lines.get(timeout=30)
                except queue.Empty as error:
                    raise RuntimeError("Snapshot session exceeded its 30-second response limit") from error
                if line is None:
                    raise RuntimeError("Snapshot session ended unexpectedly")
                if line.strip() == marker:
                    return lines
                if line.strip():
                    lines.append(line.strip())

        snapshot = snapshot_query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; "
            "SET statement_timeout='30s'; SELECT pg_export_snapshot();")[0]
        if not re.fullmatch(r"[0-9A-Fa-f-]+", snapshot):
            raise RuntimeError("Invalid exported snapshot")
        tables = snapshot_query("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;")
        source_rows = [json.loads(snapshot_query(fingerprint_sql(table))[0]) for table in tables]
        with tempfile.TemporaryDirectory(prefix="savvy-restore-") as temporary:
            dump = Path(temporary) / "synthetic.dump"
            with dump.open("wb") as output:
                run(["pg_dump", "-U", "savvy_demo", "-d", SOURCE, "-Fc",
                     "--snapshot=" + snapshot], stdout=output, stderr=subprocess.PIPE)
            snapshot_query("COMMIT;")
            sql("postgres", 'CREATE DATABASE "' + scratch + '";')
            created = True
            with dump.open("rb") as input_file:
                run(["pg_restore", "-U", "savvy_demo", "-d", scratch,
                     "--no-owner", "--no-acl", "--exit-on-error"],
                    stdin=input_file, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            restored_rows = [json.loads(sql(scratch, fingerprint_sql(table))) for table in tables]
            if restored_rows != source_rows:
                raise RuntimeError("Restored public table counts/fingerprints differ from the exported source snapshot")
            report = {"status": "passed", "synthetic": True, "source_database": SOURCE,
                      "restore_database": scratch, "snapshot": snapshot,
                      "started_at": started.isoformat(),
                      "completed_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                      "tables": source_rows, "source_replaced": False,
                      "scope": "Logical restore and exact public-table row fingerprints; not a production disaster-recovery guarantee"}
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2) + "\n")
            print("Restore rehearsal passed: " + str(len(tables)) + " tables match the consistent source snapshot.")
    finally:
        try:
            if exporter:
                if exporter.poll() is None:
                    exporter.stdin.close()
                    try:
                        exporter.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        exporter.terminate()
                        try:
                            exporter.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            exporter.kill()
                            exporter.wait(timeout=5)
                reader.join(timeout=2)
                exporter.stdout.close()
                exporter.stderr.close()
        finally:
            if created:
                sql("postgres", 'DROP DATABASE "' + scratch + '" WITH (FORCE);')


if __name__ == "__main__":
    main()
