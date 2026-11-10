#!@bash@
set -o errexit -o nounset -o pipefail
shopt -s nullglob

owner_count="$(@postgresql@/bin/psql \
  --host=/run/postgresql \
  --dbname=n8n \
  --username=n8n \
  --no-align \
  --tuples-only \
  --command='SELECT count(*) FROM "user";')"

if (( owner_count == 0 )); then
  echo "n8n owner setup is incomplete; starter import deferred"
  exit 0
fi

for workflow in @starterWorkflowDirectory@/*.json; do
  workflow_name="$(@coreutils@/bin/basename "$workflow")"
  if [[ "$workflow_name" == "nascar-scores.json" ]]; then
    continue
  fi
  marker=@seedStateDirectory@/$workflow_name.imported
  if [[ -e "$marker" ]]; then
    continue
  fi

  @n8n@/bin/n8n import:workflow --input="$workflow"
  @coreutils@/bin/touch "$marker"
done

nascar_marker=@seedStateDirectory@/nascar-scores.imported
if [[ ! -e "$nascar_marker" ]]; then
  nascar_exists="$(@postgresql@/bin/psql \
    --host=/run/postgresql \
    --dbname=n8n \
    --username=n8n \
    --no-align \
    --tuples-only \
    --command="SELECT count(*) FROM workflow_entity WHERE id = '6ZtXlBrFI0nGZ5R2';")"
  if (( nascar_exists == 0 )); then
    @n8n@/bin/n8n import:workflow \
      --input=@starterWorkflowDirectory@/nascar-scores.json
  fi
  @n8n@/bin/n8n publish:workflow --id=6ZtXlBrFI0nGZ5R2
  @coreutils@/bin/touch "$nascar_marker"
fi

espn_marker=@seedStateDirectory@/caal-espn-1.0.0.imported
if [[ ! -e "$espn_marker" ]]; then
  espn_exists="$(@postgresql@/bin/psql \
    --host=/run/postgresql \
    --dbname=n8n \
    --username=n8n \
    --no-align \
    --tuples-only \
    --command="SELECT count(*) FROM workflow_entity WHERE id = 'CasitaEspnSports';")"
  if (( espn_exists == 0 )); then
    @n8n@/bin/n8n import:workflow --input=@espnWorkflow@
  fi
  @n8n@/bin/n8n publish:workflow --id=CasitaEspnSports
  @coreutils@/bin/touch "$espn_marker"
fi
