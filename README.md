# DesignMirror AI

> AI-powered interior design assistant with AR room scanning, intelligent furniture fit-checking, multi-furniture layout planning, style-based recommendations, and real-time 3D staging.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Mobile** | Flutter 3.x (Dart) · ARCore (Android) · BLoC state management · GoRouter |
| **Backend** | FastAPI (Python 3.11+) · Fully async |
| **Database** | MongoDB 7.0 (Beanie ODM + Motor async driver) |
| **Cache** | Redis 7 (API response caching, session management) |
| **Object Storage** | MinIO (S3-compatible — hosts 3D `.glb` models, room photos) |
| **AI Engine** | Rule-based placement engine · AABB collision detection · Category-aware scoring |
| **Auth** | JWT (access + refresh tokens) · Bcrypt · AES-256-GCM encryption |
| **Containerization** | Docker · Docker Compose (4 services) |
| **PDF Reports** | `pdf` + `share_plus` (Flutter) — shareable fit-check reports with diagrams |

---

## Features

### Room Management
- Manual room creation with dimensions and room type classification
- AR room scanning via ARCore (plane detection, point anchoring)
- Room photo uploads for reference
- Room type tagging (bedroom, living room, office, kitchen, etc.)

### Furniture Catalog
- Paginated, searchable product catalog with category and price filters
- Product type filtering via bottom sheet
- Cached product images for smooth scrolling
- Indian Rupee (INR) pricing with proper formatting
- 3D bounding box dimensions for every product

### Fit-Check AI
- Single-furniture fit-check with AI-optimized placement (against-wall, corner, center strategies)
- Multi-furniture layout check with inter-furniture collision detection
- N/S/E/W wall clearance analysis with smart flush-side suppression
- Floor coverage percentage and design score (0-100)
- Isometric 3D "Furniture vs Room" diagram with color-coded compass directions
- Fullscreen zoomable/pannable diagram view
- PDF report export with embedded diagram

### Layout Planner
- Multi-furniture room layout planning
- Smart auto-placement (avoids overlap, respects room boundaries)
- Interactive fullscreen drag-and-drop editor
- Rotate furniture 90° with dimension swap
- Rug/carpet smart overlap (floor items can go under furniture)
- Backend scoring of user-designed layouts

### AR Preview
- Live AR camera preview of furniture in real space
- Bounding box mode and 3D model mode (toggleable)
- Plane detection with tap-to-place interaction

### Style Recommendations
- Room-type-aware furniture recommendations (bedroom → bed, nightstand, dresser, etc.)
- Grouped by category with fit-filtering based on room dimensions

### Budget Planner
- Set a budget, get furniture combinations that fit both room and wallet
- Individual and cumulative pricing display

### Wishlist & History
- Save products to wishlist
- View past fit-check results with diagrams in design history

### Polish & UX
- Dark mode with persistence
- Profile & settings (name, password, unit preference, theme toggle)
- Unit conversion (meters ↔ feet/inches) globally
- Custom app icon and splash screen

---

## Prerequisites

- **Docker** & **Docker Compose** v2+
- **Flutter 3.x** with Dart SDK
- **Python 3.11+** (for utility scripts)
- **Git**
- **Android device** with ARCore support (for AR features)

---

## Quick Start

### 1. Clone & Configure

```bash
git clone <your-repo-url>
cd design-mirror

# Generate secure keys
python scripts/generate_keys.py
```

Create a `.env` file from the template and paste the generated keys:

```bash
cp .env.example .env
# Edit .env — set JWT_SECRET_KEY and AES_ENCRYPTION_KEY from script output
```

### 2. Start All Services

```bash
docker-compose up --build
```

This starts four services:

| Service | URL | Description |
|---------|-----|-------------|
| **Backend API** | http://localhost:8000 | FastAPI server |
| **Swagger Docs** | http://localhost:8000/docs | Interactive API documentation |
| **MongoDB** | localhost:27017 | Database |
| **Redis** | localhost:6379 | Cache |
| **MinIO Console** | http://localhost:9001 | Object storage UI (minioadmin/minioadmin) |

### 3. Seed the Catalog

```bash
python scripts/seed_catalog.py
```

This populates the database with sample furniture products (beds, sofas, tables, rugs, etc.) with realistic dimensions, prices, images, and 3D bounding boxes.

### 4. Verify Backend

```bash
curl http://localhost:8000/api/v1/health
# {"status":"healthy","service":"DesignMirror AI","environment":"development",
#  "dependencies":{"mongodb":"healthy","redis":"healthy"}}
```

### 5. Run the Flutter App

```bash
cd mobile
flutter pub get

# Connect your Android device via USB (or use wireless ADB)
flutter devices          # List connected devices
flutter run -d <device>  # Run on device
```

> **Important:** Update the backend URL in the app's API config to point to your machine's local IP (not `localhost`) so the phone can reach the server. Find your IP with `ifconfig | grep "inet "` (macOS) or `ip addr` (Linux).

---

## Running Backend Locally (Without Docker)

```bash
cd backend

python -m venv venv
source venv/bin/activate   # macOS/Linux
# venv\Scripts\activate    # Windows

pip install -r requirements.txt

# Start MongoDB and Redis via Docker
docker-compose up mongodb redis -d

# Run the server with hot-reload
uvicorn app.main:app --reload --port 8000
```

---

## Project Structure

```
design-mirror/
├── mobile/                        # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart              # Entry point
│   │   ├── app.dart               # MaterialApp + GoRouter
│   │   ├── config/                # Routes, theme, unit preferences
│   │   ├── blocs/                 # BLoC state management (auth, catalog, room)
│   │   ├── models/                # Dart data models (room, product, catalog page)
│   │   ├── repositories/          # API communication (auth, catalog, room, wishlist)
│   │   ├── screens/
│   │   │   ├── ar/                # AR preview (3D model + box mode)
│   │   │   ├── auth/              # Login, signup
│   │   │   ├── budget/            # Budget planner
│   │   │   ├── catalog/           # Product catalog + fit-check modal
│   │   │   ├── history/           # Design history
│   │   │   ├── home/              # Dashboard
│   │   │   ├── layout/            # Multi-furniture layout planner
│   │   │   ├── recommendations/   # Style-based recommendations
│   │   │   ├── rooms/             # Room list + detail
│   │   │   ├── scanner/           # AR scanner + manual room entry
│   │   │   ├── settings/          # Profile, theme, units
│   │   │   ├── splash/            # Splash screen
│   │   │   └── wishlist/          # Saved products
│   │   ├── services/              # API service, PDF export
│   │   └── widgets/               # Reusable components (dimension views)
│   ├── assets/                    # App icon, images
│   └── pubspec.yaml
│
├── backend/                       # FastAPI backend
│   ├── app/
│   │   ├── main.py                # App entry + middleware
│   │   ├── config.py              # Pydantic settings
│   │   ├── database.py            # MongoDB connection
│   │   ├── dependencies.py        # Auth + DI
│   │   ├── api/v1/                # API routers
│   │   │   ├── auth.py            # Authentication endpoints
│   │   │   ├── rooms.py           # Room CRUD + photos
│   │   │   ├── catalog.py         # Product catalog + recommendations
│   │   │   ├── fitcheck.py        # Fit-check (single + multi)
│   │   │   ├── wishlist.py        # Wishlist endpoints
│   │   │   └── health.py          # Health check
│   │   ├── models/                # Beanie document models
│   │   ├── schemas/               # Pydantic request/response schemas
│   │   ├── services/              # Business logic
│   │   │   ├── auth_service.py
│   │   │   ├── room_service.py
│   │   │   ├── catalog_service.py
│   │   │   ├── fitcheck_service.py      # AABB collision + design scoring
│   │   │   ├── placement_service.py     # AI placement engine
│   │   │   ├── recommendation_service.py # Room-type recommendations
│   │   │   ├── storage_service.py       # MinIO file uploads
│   │   │   ├── coordinate_service.py    # AR coordinate transforms
│   │   │   └── unit_safety.py           # Measurement unit handling
│   │   └── core/                  # Security, logging, errors
│   ├── Dockerfile
│   └── requirements.txt
│
├── database/
│   └── init.js                    # MongoDB initialization script
├── scripts/
│   ├── generate_keys.py           # Generate JWT + AES keys
│   └── seed_catalog.py            # Seed furniture catalog data
├── docker-compose.yml
├── .env.example
└── .gitignore
```

---

## API Endpoints

### Authentication (`/api/v1/auth`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/auth/signup` | No | Create account |
| `POST` | `/auth/login` | No | Get JWT tokens |
| `POST` | `/auth/refresh` | No | Refresh access token |
| `GET` | `/auth/me` | Yes | Get current user profile |
| `PATCH` | `/auth/me` | Yes | Update profile (name, preferences) |
| `POST` | `/auth/change-password` | Yes | Change password |

### Rooms (`/api/v1/rooms`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/rooms/scan` | Yes | Submit AR room scan |
| `POST` | `/rooms/manual` | Yes | Create room from manual dimensions |
| `GET` | `/rooms` | Yes | List user's rooms |
| `GET` | `/rooms/{room_id}` | Yes | Get specific room |
| `PATCH` | `/rooms/{room_id}` | Yes | Update room name/type |
| `DELETE` | `/rooms/{room_id}` | Yes | Delete a room |
| `POST` | `/rooms/{room_id}/photos` | Yes | Upload room photo |
| `DELETE` | `/rooms/{room_id}/photos/{idx}` | Yes | Delete room photo |

### Catalog (`/api/v1/catalog`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/catalog` | No | Browse catalog (paginated, search, filters) |
| `GET` | `/catalog/categories` | No | List all categories |
| `GET` | `/catalog/{product_id}` | No | Get product details |
| `GET` | `/catalog/budget-picks` | Yes | Get furniture within budget for a room |
| `GET` | `/catalog/recommendations` | Yes | Style recommendations by room type |
| `POST` | `/catalog` | Yes | Create product (admin) |
| `PUT` | `/catalog/{product_id}` | Yes | Update product (admin) |
| `DELETE` | `/catalog/{product_id}` | Yes | Soft-delete product (admin) |

### Fit-Check (`/api/v1/fitcheck`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/fitcheck` | Yes | Single furniture fit-check with AI placement |
| `POST` | `/fitcheck/multi` | Yes | Multi-furniture layout check with collision detection |
| `GET` | `/fitcheck/history` | Yes | List past fit-check results |
| `DELETE` | `/fitcheck/history/{id}` | Yes | Delete a history entry |

### Wishlist (`/api/v1/wishlist`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/wishlist` | Yes | Add product to wishlist |
| `GET` | `/wishlist` | Yes | List wishlist items |
| `GET` | `/wishlist/ids` | Yes | Get wishlist product IDs (lightweight) |
| `DELETE` | `/wishlist/{product_id}` | Yes | Remove from wishlist |

### System

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/v1/health` | No | Health check (MongoDB + Redis status) |

---

## Environment Variables

See `.env.example` for the full template. Key variables:

| Variable | Description |
|----------|-------------|
| `MONGODB_URL` | MongoDB connection string |
| `MONGODB_DB_NAME` | Database name (`designmirror`) |
| `REDIS_URL` | Redis connection string |
| `JWT_SECRET_KEY` | Secret for signing JWTs — generate with `scripts/generate_keys.py` |
| `AES_ENCRYPTION_KEY` | 32-byte hex key for encryption — generate with `scripts/generate_keys.py` |
| `MINIO_ENDPOINT` | MinIO host:port (`localhost:9000`) |
| `MINIO_ACCESS_KEY` | MinIO access key |
| `MINIO_SECRET_KEY` | MinIO secret key |
| `MINIO_BUCKET_MODELS` | Bucket for 3D models |
| `MINIO_BUCKET_SCANS` | Bucket for room scans/photos |
| `CELERY_BROKER_URL` | Celery broker (Redis) |
| `CELERY_RESULT_BACKEND` | Celery result backend (Redis) |

---

## Development Workflow

```bash
# Start infrastructure only
docker-compose up mongodb redis minio -d

# Run backend with hot-reload (separate terminal)
cd backend && uvicorn app.main:app --reload

# Run Flutter app (separate terminal)
cd mobile && flutter run -d <device>
```

---

## Key Architectural Decisions

| Area | Decision |
|------|----------|
| **State Management** | BLoC pattern for auth, catalog, room scanning |
| **Navigation** | GoRouter with declarative routing and stateful caching |
| **Dependency Injection** | GetIt service locator (Flutter), FastAPI `Depends()` (backend) |
| **Caching** | Cache-aside pattern — Redis caches catalog pages, invalidated on writes |
| **Collision Detection** | Axis-Aligned Bounding Box (AABB) — O(1) per pair, O(n) for n walls |
| **AI Placement** | Category-aware rule engine (beds → against wall, lamps → corners, tables → center) |
| **API Pattern** | Repository pattern (Flutter) → Service layer (FastAPI) → Beanie ODM → MongoDB |
| **Image Loading** | `CachedNetworkImage` for catalog cards — avoids re-fetching on scroll |
| **Unit System** | Global `ValueNotifier` for meters ↔ feet/inches with `shared_preferences` persistence |
