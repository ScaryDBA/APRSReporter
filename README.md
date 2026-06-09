# APRS Position Tracker

A complete AWS-based APRS tracking system demonstrating PostGIS spatial capabilities, automated reverse geocoding, and real-time position visualization.

**Live Demo:** http://kc1kce-aprs-tracker-2026.s3-website-us-east-1.amazonaws.com

## Overview

This project showcases PostgreSQL/PostGIS capabilities for geographic information systems by tracking Amateur Radio APRS (Automatic Packet Reporting System) positions in real-time. Built entirely on AWS serverless infrastructure for minimal cost.

## Features

- 📡 **Real-time Position Tracking** - Polls APRS.fi API every 3 minutes
- 🗺️ **Interactive Maps** - Leaflet-based visualization with multiple view modes
- 📍 **Automatic Geocoding** - Converts coordinates to city/state using Nominatim  
- 📊 **PostGIS Analytics** - Spatial queries, distance calculations, convex hull
- 🔄 **Date Filtering** - View positions for specific dates
- 📈 **Statistics** - Distance traveled, max speed, altitude tracking, visit counts
- ⚡ **Serverless Architecture** - Zero-maintenance AWS Lambda + Aurora Serverless

## Architecture

### AWS Services
- **Lambda** - 3 serverless functions (data poller, API, geocoder)
- **API Gateway** - REST API with rate limiting (10 req/sec)
- **Aurora PostgreSQL** - Database with PostGIS extension
- **S3** - Static website hosting
- **EventBridge** - Scheduled triggers
- **Secrets Manager** - Secure credential storage

### PostGIS Features Demonstrated
- Geography type with true spherical distance calculations
- Spatial indexes (GIST) for fast queries
- Convex hull coverage area calculation  
- Distance and speed calculations
- GeoJSON export directly from PostGIS
- Coordinate clustering for location grouping

## Quick Start

### Prerequisites
- AWS Account with CLI configured
- PostgreSQL client (psql)
- APRS.fi API key (free from https://aprs.fi)
- Amateur radio callsign with APRS tracking

### Setup Steps

1. **Create Aurora PostgreSQL instance** (publicly accessible)

2. **Deploy database schema using Flyway Desktop:**
   - Download and install [Flyway Desktop](https://www.red-gate.com/products/flyway/desktop/)
   - Open the Flyway project located in `database/APRS Reporter/`
   - Configure your database connection in the Flyway Desktop UI
   - Deploy the schema and migrations to your Aurora PostgreSQL instance
   
   The Flyway project includes all database objects: tables, functions, triggers, and views.

3. **Create Lambda functions:** Deploy code from `lambda_function.py`, `api_lambda_function.py`, `geocoder_lambda_function.py`

4. **Set up API Gateway** with AWS_PROXY integration

5. **Deploy website to S3** and update API URL in `app.js`

## API Endpoints

Base URL: `https://your-api-id.execute-api.us-east-1.amazonaws.com/aprs_reporter`

- `GET /points?date=YYYY-MM-DD` - All positions as GeoJSON
- `GET /route?date=YYYY-MM-DD` - Route for specific date
- `GET /routes` - All routes
- `GET /stats` - Journey statistics
- `GET /locations` - Visited locations with counts
- `GET /query/convex-hull` - Coverage area polygon
- `GET /query/extremes` - Boundary points (N/S/E/W)

## Project Structure

```
├── lambda_function.py              # APRS data poller
├── api_lambda_function.py          # REST API handler (calls DB functions)
├── geocoder_lambda_function.py     # Reverse geocoding service
├── requirements.txt                # Python dependencies (psycopg2)
├── database/
│   ├── APRS Reporter/             # Flyway Desktop project
│   │   ├── flyway.toml            # Flyway configuration
│   │   ├── migrations/            # Database migration scripts
│   │   └── schema-model/          # Schema model for deployment
│   ├── db_setup.sql               # Legacy: Schema and tables
│   ├── db_internals.sql           # Legacy: Triggers and procedures
│   ├── location_lookup_table.sql  # Legacy: Geocoding cache
│   └── api_functions.sql          # Legacy: API endpoint functions
├── website/                        # Static site (S3)
│   ├── index.html
│   ├── app.js
│   └── images/
└── docs/                           # Setup guides
```

## Cost Optimization

Estimated monthly cost: **$2-5** for low-traffic demo
- Lambda free tier: 1M requests/month
- Aurora Serverless: Pauses when inactive, per-second billing
- S3 hosting: ~$0.50/month
- API Gateway free tier: 1M requests/month

## Technology Highlights

**Clean Architecture:**
- All SQL logic in PostgreSQL functions
- Python Lambda code is simple function calls
- Easy to test and maintain

**PostGIS Excellence:**
- `geography(Point,4326)` for accurate distances
- Automatic metric calculation via triggers
- Efficient views for common queries

## Credits

- **APRS Data:** [APRS.fi](https://aprs.fi)
- **Geocoding:** [OpenStreetMap Nominatim](https://nominatim.org)
- **Maps:** [Leaflet.js](https://leafletjs.com)
- **Radio:** [BridgeCom Systems Maverick](https://www.bridgecomsystems.com)
- **Built with:** Claude AI

## Contact

Questions or suggestions? Email: grant@scarydba.com

---

**Demonstrating:** AWS Lambda, AWS Aurora,PostgreSQL, PostGIS, serverless architecture, and Amateur Radio APRS
