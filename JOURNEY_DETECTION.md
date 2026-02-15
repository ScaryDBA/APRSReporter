# Journey Detection Implementation

## Overview
Implemented intelligent journey detection to automatically identify separate trips based on time gaps, replacing the previous behavior where all points were displayed as one continuous route.

## Changes Made

### 1. Database Functions (`database/journey_detection.sql`)

Created three new PostgreSQL functions for journey detection:

**`reports.detect_journeys(p_callsign, p_gap_hours)`**
- Analyzes position data to detect separate journeys
- Uses window functions to find time gaps > threshold (default 1 hour)
- Groups consecutive points into journey_id based on gaps
- Returns journey metadata: start/end times, points, distance, max speed, route line

**`reports.get_recent_journeys_geojson(p_callsign, p_limit, p_gap_hours)`**
- Returns recent journeys as GeoJSON FeatureCollection
- Default: 10 most recent journeys with 1-hour gap threshold
- Each feature includes route LineString and journey properties
- Configurable limit and gap threshold via parameters

**`reports.get_journey_details_geojson(p_journey_id, p_callsign, p_gap_hours)`**
- Returns all individual points for a specific journey
- Useful for detailed analysis of a single trip
- Returns GeoJSON with point features including time, speed, altitude

**View: `reports.journey_summary`**
- Convenience view showing all journeys with key metrics
- Includes journey_date for easy filtering

### 2. API Lambda (`api_lambda_function.py`)

Added two new endpoints:

**`GET /journeys?limit=10&gap_hours=1.0`**
- Returns recent journeys as GeoJSON
- Query parameters:
  - `limit`: Number of recent journeys to return (default: 10)
  - `gap_hours`: Time gap threshold in hours (default: 1.0)
- Calls `reports.get_recent_journeys_geojson()`

**`GET /journey/{id}?gap_hours=1.0`**
- Returns detailed point data for specific journey
- Path parameter: journey_id
- Query parameter: gap_hours (must match detection threshold)
- Calls `reports.get_journey_details_geojson()`

Kept `/routes` endpoint for backwards compatibility.

### 3. Frontend (`website/app.js`)

Updated `showRoute()` function:
- Now calls `/journeys?limit=10` instead of `/routes`
- Displays each journey with unique color from color palette
- Enhanced popup with journey metrics:
  - Journey ID
  - Start/end times (formatted)
  - Duration in minutes
  - Number of points
  - Total distance
  - Maximum speed
- Removed overlay of all points for cleaner visualization
- Console logs number of journeys displayed

## How Journey Detection Works

1. **Ordering**: All position points ordered by timestamp
2. **Gap Detection**: Calculate time difference between consecutive points
3. **Journey Assignment**: When gap exceeds threshold (default 1 hour), start new journey
4. **Grouping**: Points between gaps grouped into same journey_id
5. **Aggregation**: Calculate metrics per journey (distance, max speed, etc.)

## Configuration

The gap threshold is configurable:
- **1 hour (default)**: Good for typical driving/travel with stops
- **0.5 hours**: Detect shorter breaks (e.g., gas station stops)
- **2 hours**: Only split on longer stationary periods

## Benefits

✅ **Automatic Detection**: No manual route creation needed  
✅ **Meaningful Routes**: Each journey represents actual trip, not arbitrary date grouping  
✅ **Scalable**: Performance optimized with window functions  
✅ **Configurable**: Adjustable gap threshold for different use cases  
✅ **Color-Coded**: Visual distinction between separate journeys  
✅ **Rich Metadata**: Duration, distance, speed for each journey  

## Deployment Steps

1. **Deploy SQL functions to database:**
   ```bash
   psql -h aprs-instance-1.c2ek9ilzyxhz.us-east-1.rds.amazonaws.com \
        -U gis_admin \
        -d aprs_reporter \
        -f database/journey_detection.sql
   ```

2. **Update API Lambda:**
   ```bash
   # Zip and update Lambda function with modified api_lambda_function.py
   zip api_lambda.zip api_lambda_function.py
   aws lambda update-function-code --function-name aprs_api --zip-file fileb://api_lambda.zip
   ```

3. **Upload frontend to S3:**
   ```bash
   aws s3 cp website/app.js s3://kc1kce-aprs-tracker-2026/app.js
   ```

4. **Test the new endpoints:**
   ```bash
   # Get recent journeys
   curl https://zcftrap1y3.execute-api.us-east-1.amazonaws.com/aprs_reporter/journeys
   
   # Get specific journey details
   curl https://zcftrap1y3.execute-api.us-east-1.amazonaws.com/aprs_reporter/journey/1
   ```

## Future Enhancements

Potential improvements:
- Journey selector UI to toggle between specific journeys
- Speed-based detection (not just time gaps)
- Journey naming/tagging capability
- Export individual journey data
- Journey statistics dashboard
