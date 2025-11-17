# E-commerce Chatbot

This project is a tool-using agent that functions as a chatbot for an e-commerce order system.

## Technology Stack

- **Programming Language:** Python 3.11+
- **LLM Inference:** Groq
- **Database:** SurrealDB
- **Retrieval (RAG):** scikit-learn

## Setup

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd <repository-directory>
   ```

2. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

3. **Set up environment variables:**
   - Copy `.env.example` to `.env`.
   - Update the `.env` file with your Groq API key, SurrealDB Cloud credentials, and OpenAI API key.

## Usage

1. **Run the database setup:**
   ```bash
   python database.py
   ```

2. **Start the chatbot:**
   ```bash
   python main.py
   ```

## Agent Architecture

The agent's core logic is a router that uses a Groq classification call to determine the user's intent and then calls the appropriate tool function. The agent uses RAG to answer questions about store policies or complex product details.
