# Astral Postgres backup — setup runbook (AST-51)

Weekly `pg_dump` of the production Postgres to OCI Object Storage, retained
for 56 days (8 weekly backups) via a bucket lifecycle rule. Auth uses an
OCI **instance principal** — no API keys land on the A1 host.

Script: [`astral-backup.sh`](./astral-backup.sh)
Bucket: `astral-backups` (root compartment, standard tier, private)
Schedule: Sundays 04:00 UTC (`0 4 * * 0`)

---

## OCI resources (already provisioned)

The items below were created once via the OCI CLI and do **not** need to be
re-run. They are recorded here so an operator can re-create them from scratch
if the tenancy is ever lost.

| Resource | OCID / ID |
| --- | --- |
| Bucket `astral-backups` | `ocid1.bucket.oc1.us-sanjose-1.aaaaaaaafcgk5plwd7suxlg6ja3pzce4yafm63l7runysxn5ghhsdzz3tl7a` |
| Lifecycle rule | `delete-after-56d` (inclusion pattern `astral-*.dump.gz`) |
| Dynamic group `astral-a1-backup` | `ocid1.dynamicgroup.oc1..aaaaaaaa357nlifpaev3zlzztzjk4rxojsic22jjlsi23jnyapwvb6juiyga` |
| Policy `astral-backup-policy` | `ocid1.policy.oc1..aaaaaaaakv2ijrb4sikxhf4k2bpetyermfqwlioxlm54ekbv45vphmnsu4la` |
| Object Storage namespace | `axfta6t5vu1x` |
| Tenancy | `ocid1.tenancy.oc1..aaaaaaaatjkppg2i7z3ad4itqk3u2lbvwqoglq254lcmjkd2zbmutvcw44lq` |
| A1 instance (`astral-server`) | `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq` |

### Re-create from scratch (reference)

```bash
TENANCY=ocid1.tenancy.oc1..aaaaaaaatjkppg2i7z3ad4itqk3u2lbvwqoglq254lcmjkd2zbmutvcw44lq
NS=$(oci os ns get --query data --raw-output)   # axfta6t5vu1x
INSTANCE_OCID=ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq

# 1. Bucket (private, standard tier)
oci os bucket create \
  --compartment-id "$TENANCY" \
  --name astral-backups \
  --namespace-name "$NS" \
  --storage-tier Standard \
  --public-access-type NoPublicAccess

# 2. Dynamic group (matches exactly one instance — our A1)
oci iam dynamic-group create \
  --compartment-id "$TENANCY" \
  --name astral-a1-backup \
  --description "astral-server A1 instance identity for pg_dump backup uploads" \
  --matching-rule "instance.id = '$INSTANCE_OCID'"

# 3. Policy — two statements:
#    (a) A1 can manage objects in the bucket via its instance principal
#    (b) Object Storage service can run the lifecycle rule on the bucket
cat > /tmp/stmts.json <<EOF
[
  "allow dynamic-group astral-a1-backup to manage object-family in tenancy where target.bucket.name='astral-backups'",
  "allow service objectstorage-us-sanjose-1 to manage object-family in tenancy where target.bucket.name='astral-backups'"
]
EOF
oci iam policy create \
  --compartment-id "$TENANCY" \
  --name astral-backup-policy \
  --description "Permissions for A1 backup uploads + Object Storage lifecycle on astral-backups" \
  --statements file:///tmp/stmts.json

# 4. Lifecycle rule — delete astral-*.dump.gz objects older than 56 days
cat > /tmp/lifecycle.json <<EOF
[
  {
    "name": "delete-after-56d",
    "action": "DELETE",
    "timeAmount": 56,
    "timeUnit": "DAYS",
    "isEnabled": true,
    "objectNameFilter": { "inclusionPatterns": ["astral-*.dump.gz"] }
  }
]
EOF
oci os object-lifecycle-policy put \
  --bucket-name astral-backups \
  --namespace-name "$NS" \
  --items file:///tmp/lifecycle.json \
  --force
```

> Cost: all four resources are free. Bucket storage is under the Always Free
> 20 GB Standard tier limit; a compressed `astral` dump is expected to be
> well under 100 MB.

---

## A1 host install (one-time, post-merge)

SSH into `astral-server`:

```bash
ssh -i ~/.ssh/astral_oci ubuntu@163.192.4.88
```

Then as `ubuntu`:

```bash
# 1. Install OCI CLI via pip (user-level; no ~/.oci/config — we use instance principal).
sudo apt-get update && sudo apt-get install -y python3-pip
pip install --user oci-cli
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"

# 2. Verify instance-principal auth works.
oci --auth instance_principal os ns get
# Expect: {"data": "axfta6t5vu1x"}

# 3. Deploy the script (it's checked in at backend/scripts/astral-backup.sh).
cd ~/astral   # or wherever the repo clone lives
git pull origin development
sudo install -m 0755 -o root -g root \
  backend/scripts/astral-backup.sh /usr/local/bin/astral-backup.sh

# 4. Prep the log file.
sudo touch /var/log/astral-backup.log
sudo chmod 0644 /var/log/astral-backup.log

# 5. Smoke-test dry-run, then a real run.
sudo /usr/local/bin/astral-backup.sh --dry-run
sudo /usr/local/bin/astral-backup.sh

# 6. Verify the object landed in the bucket.
oci --auth instance_principal os object list \
  --bucket-name astral-backups \
  --namespace-name axfta6t5vu1x \
  --query 'data[*].{name:name,size:size}'

# 7. Install the cron entry (Sundays 04:00 UTC). cron.d needs root ownership.
echo '0 4 * * 0 root /usr/local/bin/astral-backup.sh >> /var/log/astral-backup.log 2>&1' \
  | sudo tee /etc/cron.d/astral-backup
sudo chmod 0644 /etc/cron.d/astral-backup
```

> The cron entry uses `/etc/cron.d/` (system cron) rather than a user
> crontab so the job runs as `root` and has permission to `docker compose
> exec` without extra groups. `sudo` is required for docker compose on the
> current host setup.

If the compose directory is not `/home/ubuntu/astral/backend`, override it:

```bash
echo '0 4 * * 0 root ASTRAL_COMPOSE_DIR=/path/to/backend /usr/local/bin/astral-backup.sh >> /var/log/astral-backup.log 2>&1' \
  | sudo tee /etc/cron.d/astral-backup
```

---

## Restore

```bash
# On any host with oci CLI + the astral docker compose stack running.
BUCKET=astral-backups
NS=axfta6t5vu1x
OBJECT=astral-20260420-040000.dump.gz   # pick from `oci os object list`

oci --auth instance_principal os object get \
  --bucket-name "$BUCKET" --namespace-name "$NS" \
  --name "$OBJECT" --file - \
  | gunzip \
  | docker compose -f /home/ubuntu/astral/backend/docker-compose.yml \
      exec -T postgres pg_restore -U astral -d astral --clean --if-exists
```

For a fully clean restore (drop + recreate the database first):

```bash
docker compose exec -T postgres psql -U astral -d postgres \
  -c "DROP DATABASE astral;" \
  -c "CREATE DATABASE astral OWNER astral;"
```

then pipe the `pg_restore` as above without `--clean --if-exists`.

---

## Operational notes

- **Log location**: `/var/log/astral-backup.log` (appended every run).
- **Failure signal**: cron emails root on non-zero exit. Pipe-failure safety
  is provided by `set -euo pipefail` inside the script.
- **Kill switch**: remove `/etc/cron.d/astral-backup` to pause weekly runs.
- **Retention**: objects are auto-deleted after 56 days by the bucket
  lifecycle rule. To change retention, update `timeAmount` in the lifecycle
  policy JSON and re-`put`.
- **Cost**: Object Storage is in the Always Free envelope (20 GB standard).
  A dozen compressed dumps at ~50 MB each is <1 GB, orders of magnitude
  under the cap. No budget alarm change needed.
