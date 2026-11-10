#!@bash@
set -o errexit -o nounset -o pipefail

@postgresql@/bin/psql \
  --host=/run/postgresql \
  --dbname=n8n \
  --username=n8n \
  --set=ON_ERROR_STOP=1 \
  --command="UPDATE workflow_entity
    SET settings = jsonb_set(
      COALESCE(settings::jsonb, '{}'::jsonb),
      '{availableInMCP}',
      'true'::jsonb,
      true
    )::json
    WHERE id IN (@workflowIds@)
      AND COALESCE(settings::jsonb ->> 'availableInMCP', 'false') <> 'true';"
