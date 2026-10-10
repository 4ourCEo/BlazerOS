"""Read-only descriptive analysis. No credential access or trading operations."""
import argparse
import collections
import csv
import datetime as dt
import json
import math
from pathlib import Path
from zoneinfo import ZoneInfo

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=Path.home() / 'Library/Application Support/BlazerOS')
args = parser.parse_args()
records = []
with (args.root / 'scan_ledger.csv').open() as handle:
    for fields in list(csv.reader(handle))[1:]:
        if len(fields) < 8 or fields[7] not in ('HIT', 'MISS'):
            continue
        time = dt.datetime.fromisoformat(fields[0].replace('Z', '+00:00')).astimezone(ZoneInfo('America/Los_Angeles'))
        minute = time.hour * 60 + time.minute
        records.append(dict(pair=fields[1], hash=fields[2], score=int(fields[3]), side=fields[4],
                            win=fields[7] == 'HIT', timestamp=time.isoformat(),
                            window=fields[10] if len(fields) > 10 else '',
                            engine=fields[11] if len(fields) > 11 else '',
                            hour=time.hour, morning=300 <= minute < 600,
                            night=minute >= 1380 or minute < 30))

def tally(rows):
    n = len(rows)
    wins = sum(r['win'] for r in rows)
    if not n:
        return dict(n=0, wins=0, win_rate=None, wilson95=None, assumed_ev88=None)
    p = wins / n
    z = 1.959963984540054
    denominator = 1 + z*z/n
    center = (p + z*z/(2*n)) / denominator
    radius = z * math.sqrt(p*(1-p)/n + z*z/(4*n*n)) / denominator
    return dict(n=n, wins=wins, win_rate=p, wilson95=[center-radius, center+radius], assumed_ev88=1.88*p-1)

def grouped(rows, field):
    groups = collections.defaultdict(list)
    for row in rows:
        groups[str(row[field])].append(row)
    return {k: tally(v) for k, v in sorted(groups.items())}

journal = {}
for line in (args.root / 'journal.jsonl').open():
    item = json.loads(line)
    journal[item['fingerprint']] = item
for record in records:
    record['setup'] = journal.get(record['hash'], {}).get('why', 'MISSING')
versioned = [r for r in records if r['engine']]
morning_versioned = [r for r in versioned if r['morning']]
result = dict(
    caveat='Descriptive recorded outcomes; source venue, exact expiry and legacy provenance are not verified. Wilson intervals assume independent observations.',
    timestamp_basis='Ledger settlement timestamp in America/Los_Angeles; not entry timestamp.',
    all=tally(records), legacy=tally([r for r in records if not r['engine']]),
    versioned=tally(versioned), morning_all=tally([r for r in records if r['morning']]),
    morning_versioned=tally(morning_versioned), night_all=tally([r for r in records if r['night']]),
    by_pair=grouped(records, 'pair'), by_engine=grouped(records, 'engine'),
    versioned_by_pair=grouped(versioned, 'pair'), versioned_by_score=grouped(versioned, 'score'),
    versioned_by_setup=grouped(versioned, 'setup'), morning_versioned_by_hour=grouped(morning_versioned, 'hour'),
    by_side=grouped(records, 'side'), by_recorded_window=grouped(records, 'window'),
    unique_hashes=len({r['hash'] for r in records}),
    time_range=[min(r['timestamp'] for r in records), max(r['timestamp'] for r in records)])
print(json.dumps(result, indent=2))
