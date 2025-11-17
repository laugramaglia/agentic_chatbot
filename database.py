import asyncio
import os
from typing import Any, Dict, List, Optional

from dotenv import load_dotenv
from surrealdb import AsyncSurreal

# Load environment variables from .env file
load_dotenv()


class SurrealDB:
    """A wrapper for the SurrealDB client."""

    _instance: Optional[AsyncSurreal] = None

    @classmethod
    async def get_client(cls) -> AsyncSurreal:
        """
        Get the SurrealDB client, creating it if it doesn't exist.

        Returns:
            The SurrealDB client.
        """
        if cls._instance is None:
            db_url = os.getenv("SURREALDB_URL")
            namespace = os.getenv("SURREALDB_NAMESPACE", "test")
            database = os.getenv("SURREALDB_DATABASE", "test")
            username = os.getenv("SURREALDB_USERNAME", "root")
            password = os.getenv("SURREALDB_PASSWORD", "root")

            if not db_url:
                raise ValueError("SURREALDB_URL environment variable is required")

            client = AsyncSurreal(db_url)
            if db_url.startswith("ws"):
                await client.connect()

            await client.use(namespace, database)
            try:
                await client.sign_in(username=username, password=password)
            except AttributeError:
                await client.signin({"username": username, "password": password})
            cls._instance = client
        return cls._instance


async def populate_sample_data():
    """Populate the database with a sample product."""
    client = await SurrealDB.get_client()
    product_data = {
        "name": "Classic T-Shirt",
        "price": 19.99,
        "description": "A comfortable and stylish t-shirt.",
        "category": "Apparel",
        "stock": 100,
    }
    await client.create("products", product_data)


async def main():
    """Main function to test database connection and data population."""
    try:
        print("Connecting to the database and populating sample data...")
        await populate_sample_data()
        print("Sample data populated successfully.")
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        client = await SurrealDB.get_client()
        await client.close()


if __name__ == "__main__":
    asyncio.run(main())
