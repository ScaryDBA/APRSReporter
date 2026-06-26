CREATE OR REPLACE FUNCTION reports.get_extreme_points_json(
    p_callsign text DEFAULT 'KC1KCE-8'::text
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    v_result json;
BEGIN
--Just a note for the presentation, the AI originally built four subqueries
--that scanned the table four times. I rewrote it so we get a single scan

    SELECT json_build_object(
        'northernmost', (array_agg(
            json_build_object('lasttime', li.lasttime, 'lat', li.lat, 'lon', li.lon, 'latitude', li.lat)
            ORDER BY li.lat DESC, li.lasttime))[1],
        'southernmost', (array_agg(
            json_build_object('lasttime', li.lasttime, 'lat', li.lat, 'lon', li.lon, 'latitude', li.lat)
            ORDER BY li.lat ASC, li.lasttime))[1],
        'easternmost', (array_agg(
            json_build_object('lasttime', li.lasttime, 'lat', li.lat, 'lon', li.lon, 'longitude', li.lon)
            ORDER BY li.lon DESC, li.lasttime))[1],
        'westernmost', (array_agg(
            json_build_object('lasttime', li.lasttime, 'lat', li.lat, 'lon', li.lon, 'longitude', li.lon)
            ORDER BY li.lon ASC, li.lasttime))[1]
    )
    INTO v_result
    FROM reports.location_info li
    WHERE li.loc_name = p_callsign;

    RETURN COALESCE(v_result, '{}'::json);
END;
$$;
