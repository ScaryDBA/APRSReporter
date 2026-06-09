-- Add reports.get_aurora_status_json() to surface Aurora-specific functionality that
-- distinguishes Amazon Aurora from vanilla PostgreSQL. Gathers four things into a single
-- JSON object for the front end:
--   * aurora_version()  vs  version()      -- Aurora build string next to the PostgreSQL one
--   * aurora_db_instance_identifier()       -- which cluster node served this request
--   * aurora_replica_status()               -- replication lag / replica state per instance
--   * aurora_stat_activity()                -- pg_stat_activity plus Aurora-specific columns
-- Each Aurora call is wrapped in its own exception block so the function still returns a
-- useful payload if a particular call is unavailable (e.g. run against non-Aurora PostgreSQL).
CREATE OR REPLACE FUNCTION reports.get_aurora_status_json()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_aurora_version text;
    v_pg_version     text;
    v_instance_id    text;
    v_replica_status jsonb;
    v_stat_activity  jsonb;
BEGIN
    -- Aurora-specific version string (distinct from the PostgreSQL version below)
    BEGIN
        SELECT aurora_version() INTO v_aurora_version;
    EXCEPTION WHEN OTHERS THEN
        v_aurora_version := 'unavailable: ' || SQLERRM;
    END;

    -- Vanilla PostgreSQL version, shown side by side to make the contrast concrete
    SELECT version() INTO v_pg_version;

    -- Which Aurora instance is currently serving this request
    BEGIN
        SELECT aurora_db_instance_identifier() INTO v_instance_id;
    EXCEPTION WHEN OTHERS THEN
        v_instance_id := 'unavailable: ' || SQLERRM;
    END;

    -- Replication lag and replica state for each instance in the cluster.
    -- to_jsonb(r) captures whatever columns this Aurora version exposes.
    BEGIN
        SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
        INTO v_replica_status
        FROM aurora_replica_status() r;
    EXCEPTION WHEN OTHERS THEN
        v_replica_status := jsonb_build_object('error', SQLERRM);
    END;

    -- Aurora's pg_stat_activity with extra Aurora-specific columns. Skip idle background
    -- backends (state IS NULL) and cap the rows so the payload stays small.
    BEGIN
        SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]'::jsonb)
        INTO v_stat_activity
        FROM (
            SELECT *
            FROM aurora_stat_activity()
            WHERE state IS NOT NULL
            ORDER BY backend_start
            LIMIT 50
        ) a;
    EXCEPTION WHEN OTHERS THEN
        v_stat_activity := jsonb_build_object('error', SQLERRM);
    END;

    RETURN jsonb_build_object(
        'aurora_version',      v_aurora_version,
        'postgres_version',    v_pg_version,
        'instance_identifier', v_instance_id,
        'replica_status',      v_replica_status,
        'stat_activity',       v_stat_activity
    );
END;
$$;

COMMENT ON FUNCTION reports.get_aurora_status_json() IS 'Returns Aurora-specific status (aurora_version vs version, instance identifier, replica status, aurora_stat_activity) as a JSON object';
