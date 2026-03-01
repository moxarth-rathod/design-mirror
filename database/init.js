// ───────────────────────────────────────────────
// DesignMirror AI — MongoDB Initialization Script
// Runs once when the MongoDB container is first created.
// ───────────────────────────────────────────────

// Switch to the application database
db = db.getSiblingDB("designmirror");

// Create application collections with validation
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["email", "hashed_password", "created_at"],
      properties: {
        email: {
          bsonType: "string",
          description: "User email — required, must be unique",
        },
        full_name: {
          bsonType: "string",
          description: "User display name",
        },
        hashed_password: {
          bsonType: "string",
          description: "Bcrypt hashed password",
        },
        is_active: {
          bsonType: "bool",
          description: "Whether the account is active",
        },
        created_at: {
          bsonType: "date",
          description: "Account creation timestamp",
        },
        updated_at: {
          bsonType: ["date", "null"],
          description: "Last update timestamp (null if never updated)",
        },
      },
    },
  },
});

// Unique index on email (prevents duplicate sign-ups)
db.users.createIndex({ email: 1 }, { unique: true });

// Create placeholder collections for future sprints
db.createCollection("rooms");
db.createCollection("products");

print("✅ DesignMirror database initialized successfully.");

