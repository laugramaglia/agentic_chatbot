from database import SurrealDB
from typing import Dict, Any

async def get_product_info(product_name: str) -> Dict[str, Any]:
    """
    Retrieves information about a specific product.

    Args:
        product_name: The name of the product to retrieve.

    Returns:
        A dictionary containing the product's information, or an error message if the product is not found.
    """
    db = await SurrealDB.get_client()
    product = await db.query("SELECT * FROM products WHERE name = $name", {"name": product_name})
    if product and len(product) > 0 and len(product[0]['result']) > 0:
        return product[0]['result'][0]
    return {"error": "Product not found."}

async def check_order_status(order_id: str) -> Dict[str, Any]:
    """
    Checks the status of a specific order.

    Args:
        order_id: The ID of the order to check.

    Returns:
        A dictionary containing the order's status, or an error message if the order is not found.
    """
    db = await SurrealDB.get_client()
    order = await db.select(f"orders:{order_id}")
    if order:
        return order
    return {"error": "Order not found."}

async def create_order(product_name: str, quantity: int) -> Dict[str, Any]:
    """
    Creates a new order for a specific product.

    Args:
        product_name: The name of the product to order.
        quantity: The quantity of the product to order.

    Returns:
        A dictionary containing the new order's information, or an error message if the product is not found or out of stock.
    """
    db = await SurrealDB.get_client()
    product_result = await db.query("SELECT * FROM products WHERE name = $name", {"name": product_name})

    if not (product_result and len(product_result) > 0 and len(product_result[0]['result']) > 0):
        return {"error": "Product not found."}

    product = product_result[0]['result'][0]

    if product['stock'] < quantity:
        return {"error": "Product out of stock."}

    new_stock = product['stock'] - quantity
    product_id = product['id']
    await db.update(product_id, {"stock": new_stock})

    order_data = {
        "product_id": product_id,
        "quantity": quantity,
        "status": "pending",
    }

    new_order = await db.create("orders", order_data)
    return new_order
