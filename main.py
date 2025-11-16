import asyncio
import os

from agno.agent import Agent
from agno.knowledge.knowledge import Knowledge
from agno.models.groq import Groq
from agno.vectordb.surrealdb import SurrealDb
from dotenv import load_dotenv
from surrealdb import AsyncSurreal

load_dotenv()


async def setup_client():
    """Initialize and configure SurrealDB client"""
    db_url = os.getenv("SURREALDB_URL")
    namespace = os.getenv("SURREALDB_NAMESPACE", "test")
    database = os.getenv("SURREALDB_DATABASE", "test")
    username = os.getenv("SURREALDB_USERNAME", "root")
    password = os.getenv("SURREALDB_PASSWORD", "root")

    if not db_url:
        print("⚠️  SURREALDB_URL not configured!")
        print()
        print("To use SurrealDB Cloud:")
        print("1. Go to https://app.surrealdb.com")
        print("2. Find your instance endpoint")
        print("3. Add it to your .env file as SURREALDB_URL")
        print()
        print("Or use local server: ws://localhost:8080/rpc")
        raise ValueError("SURREALDB_URL environment variable is required")

    # Create client
    client = AsyncSurreal(db_url)

    # For WebSocket connections, connect explicitly
    if db_url.startswith("ws"):
        await client.connect()

    # Select namespace and database
    await client.use(namespace, database)

    # Authenticate with sign_in (Cloud) or signin (local)
    try:
        await client.sign_in(username=username, password=password)
    except AttributeError:
        # Fallback to signin for older SDK versions
        await client.signin({"username": username, "password": password})

    return client


async def main():
    """Main async function"""
    # Setup SurrealDB client
    client = await setup_client()

    # Configure SurrealDB vector store
    vector_db = SurrealDb(
        client=client,
        collection="documents",
        efc=150,  # HNSW construction time/accuracy trade-off
        m=12,  # HNSW max connections per element
        search_ef=40,  # HNSW search time/accuracy trade-off
    )

    # Create knowledge base
    knowledge_base = Knowledge(vector_db=vector_db)

    # Add content from PDF (use async version)
    await knowledge_base.add_content_async(
        url="https://agno-public.s3.amazonaws.com/recipes/ThaiRecipes.pdf"
    )

    agent = Agent(
        model=Groq(id=os.getenv("DEFAULT_MODEL", "llama-3.3-70b-versatile")),
        description="You are a helpful assistant with access to a knowledge base. Use it to answer questions accurately.",
        knowledge=knowledge_base,
        search_knowledge=True,  # Enable RAG
        tools=[],
        markdown=True,  # Format responses in markdown
    )

    agent.print_response(
        "What are some popular Thai recipes?",
        stream=True,
    )

    # Close the connection
    await client.close()


if __name__ == "__main__":
    asyncio.run(main())
