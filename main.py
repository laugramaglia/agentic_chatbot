import asyncio
import os

from agno.agent import Agent
from agno.knowledge.knowledge import Knowledge
from agno.models.groq import Groq
from agno.vectordb.surrealdb import SurrealDb
from dotenv import load_dotenv

from database import SurrealDB
from tools import create_order, get_product_info, check_order_status

load_dotenv()


async def main():
    """Main async function"""
    # Setup SurrealDB client
    client = await SurrealDB.get_client()

    # Configure SurrealDB vector store
    vector_db = SurrealDb(
        client=client,
        collection="documents",
    )

    # Create knowledge base
    knowledge_base = Knowledge(vector_db=vector_db)

    # Add content from policies.txt
    await knowledge_base.add_content_async(path="policies.txt")

    agent = Agent(
        model=Groq(id=os.getenv("DEFAULT_MODEL", "llama3-8b-8192")),
        description="You are a helpful e-commerce assistant. Use the available tools to answer questions about products, orders, and store policies.",
        knowledge=knowledge_base,
        search_knowledge=True,  # Enable RAG
        tools=[get_product_info, check_order_status, create_order],
        markdown=True,  # Format responses in markdown
    )

    print("E-commerce Chatbot is running. Type 'exit' to quit.")
    while True:
        user_input = input("You: ")
        if user_input.lower() == "exit":
            break
        agent.print_response(user_input, stream=True)

    # Close the connection
    await client.close()


if __name__ == "__main__":
    asyncio.run(main())
