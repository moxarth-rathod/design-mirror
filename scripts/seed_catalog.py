"""
DesignMirror AI — Catalog Seeder Script
=========================================

Seeds sample furniture items with 3D bounding boxes into MongoDB.
Run after the database is up:

    python scripts/seed_catalog.py

Products include accurate real-world dimensions for fit-check testing.
"""

import asyncio

from motor.motor_asyncio import AsyncIOMotorClient


_KHRONOS = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models"

SAMPLE_FURNITURE = [
    {
        "name": "Modern 3-Seater Sofa",
        "category": "sofa",
        "description": "Clean-lined modern sofa with deep cushions. Perfect for living rooms.",
        "bounding_box": {"width_m": 2.134, "depth_m": 0.914, "height_m": 0.864},
        "color": "charcoal",
        "price_usd": 1299.99,
        "image_url": "https://images.unsplash.com/photo-1555041469-a586c61ea9bc?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/GlamVelvetSofa/glTF-Binary/GlamVelvetSofa.glb",
        "tags": ["modern", "living-room", "3-seater"],
        "is_active": True,
    },
    {
        "name": "Compact Loveseat",
        "category": "sofa",
        "description": "Space-saving 2-seater loveseat. Ideal for apartments.",
        "bounding_box": {"width_m": 1.524, "depth_m": 0.864, "height_m": 0.838},
        "color": "light grey",
        "price_usd": 899.99,
        "image_url": "https://images.unsplash.com/photo-1493663284031-b7e3aefcae8e?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/GlamVelvetSofa/glTF-Binary/GlamVelvetSofa.glb",
        "tags": ["modern", "small-space", "2-seater", "apartment"],
        "is_active": True,
    },
    {
        "name": "Oak Coffee Table",
        "category": "table",
        "description": "Solid oak coffee table with tapered legs.",
        "bounding_box": {"width_m": 1.219, "depth_m": 0.610, "height_m": 0.457},
        "color": "natural oak",
        "price_usd": 449.99,
        "image_url": "https://images.unsplash.com/photo-1533090481720-856c6e3c1fdc?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/WaterBottle/glTF-Binary/WaterBottle.glb",
        "tags": ["mid-century", "living-room", "wood"],
        "is_active": True,
    },
    {
        "name": "Round Dining Table",
        "category": "table",
        "description": "Seats 4 comfortably. Walnut veneer top with steel base.",
        "bounding_box": {"width_m": 1.067, "depth_m": 1.067, "height_m": 0.762},
        "color": "walnut",
        "price_usd": 699.99,
        "image_url": "https://images.unsplash.com/photo-1617806118233-18e1de247200?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/WaterBottle/glTF-Binary/WaterBottle.glb",
        "tags": ["modern", "dining-room", "4-seater"],
        "is_active": True,
    },
    {
        "name": "Floor Lamp",
        "category": "lighting",
        "description": "Adjustable brass floor lamp with fabric shade.",
        "bounding_box": {"width_m": 0.305, "depth_m": 0.305, "height_m": 1.651},
        "color": "brass",
        "price_usd": 199.99,
        "image_url": "https://images.unsplash.com/photo-1507473885765-e6ed057ab6fe?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/Lantern/glTF-Binary/Lantern.glb",
        "tags": ["modern", "living-room", "adjustable"],
        "is_active": True,
    },
    {
        "name": "Accent Chair",
        "category": "chair",
        "description": "Upholstered accent chair with solid wood legs.",
        "bounding_box": {"width_m": 0.762, "depth_m": 0.813, "height_m": 0.838},
        "color": "navy blue",
        "price_usd": 599.99,
        "image_url": "https://images.unsplash.com/photo-1598300042247-d088f8ab3a91?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/SheenChair/glTF-Binary/SheenChair.glb",
        "tags": ["modern", "living-room", "accent"],
        "is_active": True,
    },
    {
        "name": "Dining Chair (Set of 2)",
        "category": "chair",
        "description": "Molded plastic seat with beech wood legs.",
        "bounding_box": {"width_m": 0.470, "depth_m": 0.508, "height_m": 0.813},
        "color": "white",
        "price_usd": 249.99,
        "image_url": "https://images.unsplash.com/photo-1503602642458-232111445657?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/SheenChair/glTF-Binary/SheenChair.glb",
        "tags": ["scandinavian", "dining-room", "set"],
        "is_active": True,
    },
    {
        "name": "Bookshelf Unit",
        "category": "storage",
        "description": "5-shelf open bookcase. Fits standard-height rooms.",
        "bounding_box": {"width_m": 0.914, "depth_m": 0.305, "height_m": 1.829},
        "color": "walnut",
        "price_usd": 349.99,
        "image_url": "https://images.unsplash.com/photo-1594620302200-9a762244a156?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/AntiqueCamera/glTF-Binary/AntiqueCamera.glb",
        "tags": ["modern", "living-room", "office", "tall"],
        "is_active": True,
    },
    {
        "name": "TV Console",
        "category": "storage",
        "description": "Low-profile media console for 65\" TV.",
        "bounding_box": {"width_m": 1.524, "depth_m": 0.406, "height_m": 0.508},
        "color": "matte black",
        "price_usd": 549.99,
        "image_url": "https://images.unsplash.com/photo-1615874959474-d609969a20ed?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/BoomBox/glTF-Binary/BoomBox.glb",
        "tags": ["modern", "living-room", "media"],
        "is_active": True,
    },
    {
        "name": "Queen Bed Frame",
        "category": "bed",
        "description": "Upholstered platform bed with headboard. No box spring needed.",
        "bounding_box": {"width_m": 1.651, "depth_m": 2.184, "height_m": 1.067},
        "color": "light grey",
        "price_usd": 799.99,
        "image_url": "https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/GlamVelvetSofa/glTF-Binary/GlamVelvetSofa.glb",
        "tags": ["modern", "bedroom", "platform"],
        "is_active": True,
    },
    {
        "name": "Nightstand",
        "category": "storage",
        "description": "2-drawer bedside table with soft-close drawers.",
        "bounding_box": {"width_m": 0.508, "depth_m": 0.406, "height_m": 0.610},
        "color": "white oak",
        "price_usd": 199.99,
        "image_url": "https://images.unsplash.com/photo-1532372576444-dda954194ad0?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/Lantern/glTF-Binary/Lantern.glb",
        "tags": ["modern", "bedroom", "small-space"],
        "is_active": True,
    },
    {
        "name": "Area Rug (8x10)",
        "category": "rug",
        "description": "Hand-tufted wool area rug. Defines the living space.",
        "bounding_box": {"width_m": 2.438, "depth_m": 3.048, "height_m": 0.013},
        "color": "ivory / grey",
        "price_usd": 699.99,
        "image_url": "https://images.unsplash.com/photo-1600166898405-da9535204843?w=400&h=400&fit=crop",
        "model_file": f"{_KHRONOS}/SheenChair/glTF-Binary/SheenChair.glb",
        "tags": ["living-room", "wool", "large"],
        "is_active": True,
    },
]


async def seed():
    client = AsyncIOMotorClient(
        "mongodb://designmirror_user:changeme_db_password@localhost:27017"
    )
    db = client["designmirror"]
    collection = db["products"]

    # Clear existing seed data
    await collection.delete_many({})

    # Insert sample items
    result = await collection.insert_many(SAMPLE_FURNITURE)
    print(f"Seeded {len(result.inserted_ids)} furniture items into 'products' collection.")

    # Print summary
    categories = {}
    for item in SAMPLE_FURNITURE:
        cat = item["category"]
        categories[cat] = categories.get(cat, 0) + 1
    print("\nBy category:")
    for cat, count in sorted(categories.items()):
        print(f"  {cat}: {count} items")

    client.close()


if __name__ == "__main__":
    asyncio.run(seed())
