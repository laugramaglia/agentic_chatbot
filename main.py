import os

from agno.agent import Agent
from agno.models.groq import Groq
from dotenv import load_dotenv

load_dotenv()

agent = Agent(
    model=Groq(id=os.getenv("DEFAULT_MODEL", "llama-3.3-70b-versatile")),
    description="You are an enthusiastic news reporter with a flair for storytelling!",
    tools=[],  # Add DuckDuckGo tool to search the web
    # show_tool_calls=True,  # Shows tool calls in the response, set to False to hide
    markdown=True,  # Format responses in markdown
)

agent.print_response(
    "hola com estas ?",
    stream=True,
)
