"""
DesignMirror AI — Wishlist Router
"""

from fastapi import APIRouter, Depends, status

from app.core.exceptions import ConflictError, NotFoundError
from app.dependencies import get_current_user
from app.models.product import Product
from app.models.user import User
from app.models.wishlist import WishlistItem
from app.schemas.wishlist import WishlistAddRequest, WishlistItemResponse

router = APIRouter(prefix="/wishlist", tags=["Wishlist"])


@router.post(
    "",
    response_model=WishlistItemResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add a product to your wishlist",
)
async def add_to_wishlist(
    data: WishlistAddRequest,
    current_user: User = Depends(get_current_user),
) -> WishlistItemResponse:
    product = await Product.get(data.product_id)
    if not product:
        raise NotFoundError(message="Product not found", error_code="PRODUCT_NOT_FOUND")

    existing = await WishlistItem.find_one(
        WishlistItem.user_id == str(current_user.id),
        WishlistItem.product_id == data.product_id,
    )
    if existing:
        raise ConflictError(
            message="Product already in wishlist", error_code="ALREADY_IN_WISHLIST"
        )

    item = WishlistItem(
        user_id=str(current_user.id),
        product_id=data.product_id,
        note=data.note,
    )
    await item.insert()

    return WishlistItemResponse(
        id=str(item.id),
        product_id=str(product.id),
        product_name=product.name,
        product_category=product.category,
        product_image_url=product.image_url,
        product_price_usd=product.price_usd,
        note=item.note,
        created_at=item.created_at,
    )


@router.get(
    "",
    response_model=list[WishlistItemResponse],
    summary="List your wishlist",
)
async def list_wishlist(
    current_user: User = Depends(get_current_user),
) -> list[WishlistItemResponse]:
    items = await WishlistItem.find(
        WishlistItem.user_id == str(current_user.id)
    ).sort("-created_at").to_list()

    result = []
    for item in items:
        product = await Product.get(item.product_id)
        if not product:
            continue
        result.append(WishlistItemResponse(
            id=str(item.id),
            product_id=str(product.id),
            product_name=product.name,
            product_category=product.category,
            product_image_url=product.image_url,
            product_price_usd=product.price_usd,
            note=item.note,
            created_at=item.created_at,
        ))
    return result


@router.get(
    "/ids",
    response_model=list[str],
    summary="Get product IDs in your wishlist (lightweight)",
)
async def list_wishlist_ids(
    current_user: User = Depends(get_current_user),
) -> list[str]:
    items = await WishlistItem.find(
        WishlistItem.user_id == str(current_user.id)
    ).to_list()
    return [item.product_id for item in items]


@router.delete(
    "/{product_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a product from your wishlist",
)
async def remove_from_wishlist(
    product_id: str,
    current_user: User = Depends(get_current_user),
) -> None:
    item = await WishlistItem.find_one(
        WishlistItem.user_id == str(current_user.id),
        WishlistItem.product_id == product_id,
    )
    if not item:
        raise NotFoundError(
            message="Product not in wishlist", error_code="NOT_IN_WISHLIST"
        )
    await item.delete()
