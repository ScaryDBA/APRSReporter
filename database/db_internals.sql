DROP TABLE IF EXISTS reports.location_info

CREATE SCHEMA reports;

CREATE TABLE reports.location_info
(location_info_id bigint GENERATED ALWAYS AS IDENTITY primary key NOT NULL ,
	loc_class text NOT NULL,
	loc_name text NOT NULL,
	loc_type char(1) NOT NULL,
	loc_time timestamptz NOT NULL,
	lasttime timestamptz NOT NULL,
	lat numeric(9,5) NOT NULL,
	lon numeric(10,5) NOT NULL,
	gis_point geography(Point,4326) NOT NULL,
	course numeric(5,2) NOT NULL,
	speed numeric(6,2) NOT NULL,
	altitude numeric(8,2) NOT NULL,
	symbol text NOT NULL,
	srccall text NOT NULL,
	dstcall text NOT NULL,
	loc_comment text NULL,
	loc_path text NULL,
	phg text NULL,
	status text NULL,
	status_lasttime timestamptz NULL,
	CONSTRAINT unique_location_entry UNIQUE (loc_name, lasttime)
);

CREATE OR REPLACE PROCEDURE reports.add_aprs_info(loc jsonb)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO reports.location_info (
        loc_class,
        loc_name,
        loc_type,
        loc_time,
        lasttime,
        lat,
        lon,
        gis_point,
        course,
        speed,
        altitude,
        symbol,
        srccall,
        dstcall,
        loc_comment,
        loc_path,
        phg,
        status,
        status_lasttime
    )
    SELECT
        loc->>'class',
        loc->>'name',
        loc->>'type',
        to_timestamp((loc->>'time')::double precision)::timestamptz,
        to_timestamp((loc->>'lasttime')::double precision)::timestamptz,
        (loc->>'lat')::numeric(9,5),
        (loc->>'lng')::numeric(10,5),                     -- APRS.fi field is "lng"
        ST_SetSRID(
            ST_MakePoint(
                (loc->>'lng')::double precision,
                (loc->>'lat')::double precision
            ),
            4326
        ),
        (loc->>'course')::numeric(5,2),
        (loc->>'speed')::numeric(6,2),
        (loc->>'altitude')::numeric(8,2),
        loc->>'symbol',
        loc->>'srccall',
        loc->>'dstcall',
        loc->>'comment',
        loc->>'path',
        loc->>'phg',
        loc->>'status',
        to_timestamp((loc->>'status_lasttime')::double precision)::timestamptz
    ON CONFLICT (loc_name, lasttime) DO NOTHING;  -- Skip duplicates
    
END;
$$;


CALL reports.add_aprs_info(
    '{
      "class": "a",
      "name": "N0CALL-9",
      "type": "l",
      "time": "1739010000",
      "lasttime": "1739010300",
      "lat": "36.00000",
      "lng": "-96.11667",
      "course": "180.0",
      "speed": "65",
      "altitude": "250",
      "symbol": "/>",
      "srccall": "N0CALL-9",
      "dstcall": "APRS",
      "comment": "Testing APRS.fi ingest via PostgreSQL",
      "path": "WIDE1-1,WIDE2-1",
      "phg": "44603",
      "status": "Mobile test near Sapulpa, OK",
      "status_lasttime": "1739010200"
    }'::jsonb
);

SELECT * FROM reports.location_info;
