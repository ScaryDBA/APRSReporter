-- Remove the dead no-argument overload of reports.get_all_routes_geojson().
-- It grouped routes by date off the legacy reports.route_track view and is never called:
-- the API (/routes) always invokes the one-argument get_all_routes_geojson(date) overload,
-- which delegates to reports.get_recent_journeys_geojson(). The NULL case in the API
-- (get_all_routes_geojson(NULL)) also resolves to the (date) overload, so nothing depends
-- on the no-argument version. Dropping it avoids confusion when reading the schema.
DROP FUNCTION IF EXISTS reports.get_all_routes_geojson();
