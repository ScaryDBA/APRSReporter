-- Update the existing get_all_routes_geojson to use journey detection
-- This avoids needing to add new API Gateway routes
-- Now supports optional date filtering

CREATE OR REPLACE FUNCTION reports.get_all_routes_geojson(p_date date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
BEGIN
    -- Use journey detection instead of date-based grouping
    -- Limit to 10 most recent journeys, optionally filtered by date
    RETURN reports.get_recent_journeys_geojson('KC1KCE-8', 10, 1.0, p_date);
END;
$$;

COMMENT ON FUNCTION reports.get_all_routes_geojson IS 'Returns recent journeys (uses journey detection with 1-hour gaps), max 10, optional date filter';
