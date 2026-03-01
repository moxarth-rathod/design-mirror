# DesignMirror AI

> AI-powered interior design assistant with AR room scanning, furniture fit-checking, and real-time staging.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Mobile** | Flutter (Dart) · ARKit (iOS) · ARCore (Android) |
| **Backend** | FastAPI (Python 3.11+) · Async everywhere |
| **Database** | MongoDB 7.0 (Beanie ODM + Motor async driver) |
| **Cache** | Redis 7 (session cache, Celery broker) |
| **Object Storage** | MinIO (S3-compatible, hosts 3D .GLB/.USDZ models) |
| **AI Workers** | Celery + Redis (SAM segmentation, async tasks) |
| **Auth** | JWT (access + refresh tokens) · Bcrypt · AES-256-GCM |
| **Containerization** | Docker · docker-compose |

---

## Prerequisites

- **Docker** & **Docker Compose** (v2+)
- **Python 3.11+** (for running scripts locally)
- **Flutter 3.x** (for mobile development)
- **Git**

---

## Quick Start (Backend + Infrastructure)

### 1. Clone & Configure

```bash
git clone <your-repo-url>
cd design-mirror

# Generate secure keys
python scripts/generate_keys.py
```

Copy the output into a `.env` file:

```bash
cp .env.example .env
# Paste the JWT_SECRET_KEY and AES_ENCRYPTION_KEY values from the script output
```

### 2. Start All Services (Docker)

```bash
docker-compose up --build
```

This starts **four services**:

| Service | URL | Description |
|---------|-----|-------------|
| **Backend API** | http://localhost:8000 | FastAPI server |
| **Swagger Docs** | http://localhost:8000/docs | Interactive API docs |
| **MongoDB** | localhost:27017 | Database |
| **Redis** | localhost:6379 | Cache & task broker |
| **MinIO Console** | http://localhost:9001 | Object storage UI |

### 3. Verify It's Running

```bash
# Health check
curl http://localhost:8000/api/v1/health

# Expected:
# {"status":"healthy","service":"DesignMirror AI","environment":"development","dependencies":{"mongodb":"healthy","redis":"healthy"}}
```

### 4. Test Auth Flow

```bash
# Sign up
curl -X POST http://localhost:8000/api/v1/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "full_name": "Test User", "password": "MyPassword1"}'

# Login (returns JWT tokens)
curl -X POST http://localhost:8000/api/v1/auth/login \
  -d "username=test@example.com&password=MyPassword1"

# Get profile (replace <TOKEN> with access_token from login response)
curl http://localhost:8000/api/v1/auth/me \
  -H "Authorization: Bearer <TOKEN>"
```

---

## Running Backend Locally (Without Docker)

If you prefer running the backend directly:

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # macOS/Linux
# venv\Scripts\activate   # Windows

# Install dependencies
pip install -r requirements.txt

# Make sure MongoDB and Redis are running (via Docker or locally)
docker-compose up mongodb redis -d

# Run the server with auto-reload
uvicorn app.main:app --reload --port 8000
```

---

## Flutter Mobile App

### Setup

```bash
cd mobile

# Install dependencies
flutter pub get

# Run on iOS Simulator
flutter run -d ios

# Run on Android Emulator
flutter run -d android
```

### AR Requirements

- **iOS:** iPhone/iPad with LiDAR sensor (iPhone 12 Pro+) or ARKit support (iPhone 6s+)
- **Android:** Device with ARCore support ([check list](https://developers.google.com/ar/devices))

> **Note:** AR features require a physical device — they won't work on simulators/emulators.

---

## Project Structure

```
design-mirror/
├── mobile/                    # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart          # App entry point
│   │   ├── app.dart           # MaterialApp + routing
│   │   ├── config/            # App config, routes, theme
│   │   ├── blocs/             # BLoC state management
│   │   ├── models/            # Dart data models
│   │   ├── repositories/      # API communication layer
│   │   ├── screens/           # UI screens
│   │   ├── services/          # AR, HTTP services
│   │   └── widgets/           # Reusable components
│   └── pubspec.yaml
│
├── backend/                   # FastAPI backend
│   ├── app/
│   │   ├── main.py            # App entry + middleware
│   │   ├── config.py          # Environment config
│   │   ├── database.py        # MongoDB connection
│   │   ├── dependencies.py    # DI (auth, user injection)
│   │   ├── api/v1/            # API routers
│   │   ├── models/            # Beanie document models
│   │   ├── schemas/           # Pydantic request/response
│   │   ├── services/          # Business logic
│   │   ├── core/              # Security, logging, errors
│   │   └── workers/           # Celery async tasks
│   ├── Dockerfile
│   └── requirements.txt
│
├── database/
│   └── init.js                # MongoDB initialization
├── scripts/                   # Utility scripts
├── docker-compose.yml         # Full-stack Docker setup
├── .env.example               # Environment template
└── .gitignore
```

---

## API Endpoints

### Public (No Auth Required)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/` | API info |
| `GET` | `/api/v1/health` | Health check |
| `POST` | `/api/v1/auth/signup` | Create account |
| `POST` | `/api/v1/auth/login` | Get JWT tokens |
| `POST` | `/api/v1/auth/refresh` | Refresh token |

### Public Catalog

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/catalog` | Browse catalog (paginated, filtered, cached) |
| `GET` | `/api/v1/catalog/categories` | List all categories |
| `GET` | `/api/v1/catalog/{id}` | Get product details |

### Protected (JWT Required)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/auth/me` | Current user profile |
| `POST` | `/api/v1/rooms/scan` | Submit AR room scan |
| `GET` | `/api/v1/rooms` | List user's room scans |
| `GET` | `/api/v1/rooms/{id}` | Get specific room scan |
| `POST` | `/api/v1/fitcheck` | Check if furniture fits in a room |
| `POST` | `/api/v1/catalog` | Create product (admin) |
| `PUT` | `/api/v1/catalog/{id}` | Update product (admin) |
| `DELETE` | `/api/v1/catalog/{id}` | Delete product (admin) |

---

## Environment Variables

See [`.env.example`](.env.example) for the full list. Critical ones:

| Variable | Description |
|----------|-------------|
| `MONGODB_URL` | MongoDB connection string |
| `REDIS_URL` | Redis connection string |
| `JWT_SECRET_KEY` | Secret for signing JWTs (generate with `scripts/generate_keys.py`) |
| `AES_ENCRYPTION_KEY` | 32-byte hex key for data encryption |

---

## Development Workflow

```bash
# Start infrastructure only
docker-compose up mongodb redis minio -d

# Run backend with hot-reload
cd backend && uvicorn app.main:app --reload

# Run Flutter app (separate terminal)
cd mobile && flutter run
```

---

## Sprint Roadmap

- [x] **Sprint 1:** Secure Foundation (Auth, project scaffold, Docker)
- [x] **Sprint 2:** AR Measurement Pipeline (Flutter AR, coordinate transforms)
- [x] **Sprint 3:** Scalable Furniture Staging (Catalog API, Fit-Check AI)
- [ ] **Sprint 4:** Performance & Polish (Lazy loading, logging, optimization)

