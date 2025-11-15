# Shopping Cart Chatbot - Microservices Architecture

## Executive Summary

This document provides a comprehensive microservices architecture blueprint for building a Shopping Cart Chatbot using:
- **Architecture Pattern:** Microservices with API Gateway
- **Backend Language:** Go (Golang) with Clean Architecture per service
- **Database:** Single SurrealDB MCP instance (shared, with schema ownership per service)
- **LLM Provider:** Groq (for fast inference)
- **AI Technique:** RAG (Retrieval-Augmented Generation)
- **Communication:** Synchronous REST APIs (service-to-service)

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [Service Boundaries](#2-service-boundaries)
3. [API Gateway Design](#3-api-gateway-design)
4. [Database Strategy](#4-database-strategy)
5. [Inter-Service Communication](#5-inter-service-communication)
6. [Service Specifications](#6-service-specifications)
7. [Deployment Architecture](#7-deployment-architecture)
8. [Security & Authentication](#8-security--authentication)
9. [Observability & Monitoring](#9-observability--monitoring)
10. [Development Workflow](#10-development-workflow)

---

## 1. High-Level Architecture

### 1.1 System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         CLIENT LAYER                             │
│                    (Web, Mobile, CLI)                            │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             │ HTTPS
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                        API GATEWAY                               │
│                   (Single Entry Point)                           │
│                                                                  │
│  - Authentication & Authorization (JWT)                          │
│  - Rate Limiting                                                 │
│  - Request Routing                                               │
│  - Load Balancing                                                │
│  - Response Aggregation (BFF Pattern)                            │
│  - Logging & Metrics                                             │
└────┬─────────┬──────────┬──────────┬──────────┬─────────────────┘
     │         │          │          │          │
     │ gRPC/   │ gRPC/    │ gRPC/    │ gRPC/    │ gRPC/
     │ REST    │ REST     │ REST     │ REST     │ REST
     │         │          │          │          │
┌────▼─────┐ ┌▼──────┐ ┌─▼──────┐ ┌─▼──────┐ ┌─▼────────┐
│  Chat    │ │ Cart  │ │Product │ │Session │ │Recommend │
│ Service  │ │Service│ │Service │ │Service │ │ Service  │
└────┬─────┘ └┬──────┘ └─┬──────┘ └─┬──────┘ └─┬────────┘
     │        │          │          │          │
     │        └──────────┴──────────┴──────────┘
     │                   │
     │                   │ (REST/HTTP calls between services)
     │                   │
     ▼                   ▼
┌────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE LAYER                        │
├────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐  │
│  │  SurrealDB MCP  │  │   Groq API      │  │  Embedding   │  │
│  │  (Shared DB)    │  │  (LLM Service)  │  │   Service    │  │
│  │                 │  │                 │  │(Transformers)│  │
│  │ - chat schema   │  └─────────────────┘  └──────────────┘  │
│  │ - cart schema   │                                          │
│  │ - product schema│                                          │
│  │ - session schema│                                          │
│  └─────────────────┘                                          │
└────────────────────────────────────────────────────────────────┘
```

### 1.2 Service Overview

| Service | Port | Responsibility | Database Tables Owned |
|---------|------|----------------|----------------------|
| **API Gateway** | 8080 | Routing, Auth, Rate Limiting | None |
| **Chat Service** | 8081 | Intent classification, RAG, LLM | `chat_message` |
| **Cart Service** | 8082 | Cart CRUD operations | `cart` |
| **Product Service** | 8083 | Product catalog, Vector search | `product` |
| **Session Service** | 8084 | Session management, Checkout | `user_session` |
| **Recommendation Service** | 8085 | Product recommendations | None (reads from product) |

---

## 2. Service Boundaries

### 2.1 Domain-Driven Design (DDD) Bounded Contexts

Each microservice represents a **Bounded Context** with clear domain boundaries:

#### **Chat Service** (Conversation Context)
- **Domain:** Natural language interaction, intent understanding
- **Responsibilities:**
  - Receive user messages
  - Classify intent using Groq
  - Execute RAG pipeline for product questions
  - Coordinate with other services based on intent
  - Store conversation history
- **Dependencies:**
  - Product Service (for RAG context)
  - Cart Service (for cart-aware responses)
  - Groq API (for LLM)
  - Embedding Service (for query vectorization)

#### **Cart Service** (Shopping Cart Context)
- **Domain:** Shopping cart management
- **Responsibilities:**
  - Add items to cart
  - Remove items from cart
  - Update quantities
  - View cart contents
  - Validate cart operations
- **Dependencies:**
  - Product Service (to validate product existence)
  - Session Service (to validate session)

#### **Product Service** (Catalog Context)
- **Domain:** Product catalog and search
- **Responsibilities:**
  - Product CRUD operations
  - Vector similarity search (RAG)
  - Full-text product search
  - Product data ingestion
  - Manage product embeddings
- **Dependencies:**
  - Embedding Service (for vector generation)

#### **Session Service** (Session Context)
- **Domain:** User session lifecycle
- **Responsibilities:**
  - Create user sessions
  - Track session state
  - Checkout process
  - Session completion/abandonment
  - Generate checkout summaries
- **Dependencies:**
  - Cart Service (to get cart items for checkout)
  - Product Service (to get product details for checkout)

#### **Recommendation Service** (Recommendation Context)
- **Domain:** Personalized product suggestions
- **Responsibilities:**
  - Generate product recommendations
  - Analyze cart context
  - Score and rank recommendations
  - Cross-sell and upsell logic
- **Dependencies:**
  - Cart Service (to get current cart)
  - Product Service (to get related products)

---

## 3. API Gateway Design

### 3.1 Technology Stack

**Recommended:** Kong, Traefik, or custom Go implementation using Gin/Echo

### 3.2 Gateway Responsibilities

```go
// Pseudo-code for API Gateway structure
type APIGateway struct {
    authService     AuthService
    rateLimiter     RateLimiter
    router          Router
    serviceRegistry ServiceRegistry
    loadBalancer    LoadBalancer
    logger          Logger
    metrics         MetricsCollector
}
```

### 3.3 Route Table

```
┌────────────────────────────────────────────────────────────────────┐
│                         API GATEWAY ROUTES                         │
├──────────────────┬──────────────────────┬──────────────────────────┤
│ Client Endpoint  │ Upstream Service     │ Method                   │
├──────────────────┼──────────────────────┼──────────────────────────┤
│ POST /chat       │ Chat Service:8081    │ ProcessMessage           │
│ GET  /chat/:id   │ Chat Service:8081    │ GetConversationHistory   │
├──────────────────┼──────────────────────┼──────────────────────────┤
│ POST /cart/add   │ Cart Service:8082    │ AddToCart                │
│ POST /cart/remove│ Cart Service:8082    │ RemoveFromCart           │
│ PUT  /cart/update│ Cart Service:8082    │ UpdateQuantity           │
│ GET  /cart       │ Cart Service:8082    │ ViewCart                 │
├──────────────────┼──────────────────────┼──────────────────────────┤
│ GET  /products/:id│ Product Service:8083│ GetProduct               │
│ POST /products/search│Product Service:8083│VectorSearch            │
├──────────────────┼──────────────────────┼──────────────────────────┤
│ POST /session/create│Session Service:8084│CreateSession            │
│ POST /checkout   │ Session Service:8084 │ Checkout                 │
│ GET  /session/:id│ Session Service:8084 │ GetSession               │
├──────────────────┼──────────────────────┼──────────────────────────┤
│ GET  /recommend  │ Recommend Svc:8085   │ GetRecommendations       │
└──────────────────┴──────────────────────┴──────────────────────────┘
```

### 3.4 Gateway Configuration Example

```yaml
# gateway-config.yaml
services:
  chat_service:
    url: http://chat-service:8081
    health_check: /health
    timeout: 30s
    
  cart_service:
    url: http://cart-service:8082
    health_check: /health
    timeout: 10s
    
  product_service:
    url: http://product-service:8083
    health_check: /health
    timeout: 15s
    
  session_service:
    url: http://session-service:8084
    health_check: /health
    timeout: 10s
    
  recommendation_service:
    url: http://recommendation-service:8085
    health_check: /health
    timeout: 20s

rate_limiting:
  default:
    requests_per_minute: 100
  chat:
    requests_per_minute: 30  # Lower for LLM calls

authentication:
  jwt_secret: ${JWT_SECRET}
  token_expiry: 24h
```

### 3.5 Request Flow Example

**Scenario:** User sends "Add 2 blue t-shirts to my cart"

```
1. Client → API Gateway: POST /chat
   {
     "session_id": "session:abc123",
     "message": "Add 2 blue t-shirts to my cart"
   }

2. API Gateway:
   - Validates JWT token
   - Checks rate limit
   - Routes to Chat Service

3. Chat Service → Groq API:
   - Classifies intent: "addToCart"
   - Extracts entities: {product_name: "blue t-shirts", quantity: 2}

4. Chat Service → Product Service (internal call):
   GET /internal/products/search?q=blue+t-shirts
   
5. Product Service responds:
   {product_id: "product:p004", name: "Blue T-Shirt"}

6. Chat Service → Cart Service (internal call):
   POST /internal/cart/add
   {
     "session_id": "session:abc123",
     "product_id": "product:p004",
     "quantity": 2
   }

7. Cart Service:
   - Validates product exists
   - Adds to cart in SurrealDB
   - Returns success

8. Chat Service → Client (via Gateway):
   {
     "response": "Done! I've added 2 blue t-shirts to your cart.",
     "intent": "addToCart",
     "success": true
   }
```

---

## 4. Database Strategy

### 4.1 Shared SurrealDB with Schema Ownership

**Pattern:** Single SurrealDB MCP instance, but each service owns specific tables.

```
SurrealDB MCP Instance
├── Namespace: production
│   ├── Database: chatbot
│   │   ├── chat_message (owned by Chat Service)
│   │   ├── cart (owned by Cart Service)
│   │   ├── product (owned by Product Service)
│   │   └── user_session (owned by Session Service)
```

### 4.2 Schema Ownership Rules

| Table | Owner Service | Write Access | Read Access |
|-------|--------------|--------------|-------------|
| `product` | Product Service | Product Service only | All services |
| `cart` | Cart Service | Cart Service only | Cart, Session services |
| `user_session` | Session Service | Session Service only | All services |
| `chat_message` | Chat Service | Chat Service only | Chat Service only |

**Enforcement:**
- Use SurrealDB's RBAC to create service-specific database users
- Each service uses its own credentials with appropriate permissions

### 4.3 SurrealDB User Permissions

```sql
-- Chat Service User
DEFINE USER chat_service ON DATABASE PASSWORD 'chat_secret' ROLES EDITOR;
DEFINE ACCESS chat_service ON DATABASE TYPE RECORD
  SIGNUP NONE
  SIGNIN NONE
  GRANT FOR SELECT, CREATE, UPDATE, DELETE ON chat_message;

-- Cart Service User
DEFINE USER cart_service ON DATABASE PASSWORD 'cart_secret' ROLES EDITOR;
DEFINE ACCESS cart_service ON DATABASE TYPE RECORD
  GRANT FOR SELECT, CREATE, UPDATE, DELETE ON cart
  GRANT FOR SELECT ON product, user_session;

-- Product Service User
DEFINE USER product_service ON DATABASE PASSWORD 'product_secret' ROLES EDITOR;
DEFINE ACCESS product_service ON DATABASE TYPE RECORD
  GRANT FOR SELECT, CREATE, UPDATE, DELETE ON product;

-- Session Service User
DEFINE USER session_service ON DATABASE PASSWORD 'session_secret' ROLES EDITOR;
DEFINE ACCESS session_service ON DATABASE TYPE RECORD
  GRANT FOR SELECT, CREATE, UPDATE, DELETE ON user_session
  GRANT FOR SELECT ON cart, product;

-- Recommendation Service User (Read-only)
DEFINE USER recommend_service ON DATABASE PASSWORD 'recommend_secret' ROLES VIEWER;
DEFINE ACCESS recommend_service ON DATABASE TYPE RECORD
  GRANT FOR SELECT ON product, cart;
```

### 4.4 Database Connection per Service

Each service has its own connection configuration:

```go
// Product Service
db, err := surrealdb.New("wss://your-instance.surreal.cloud")
db.Signin(map[string]interface{}{
    "user": "product_service",
    "pass": os.Getenv("PRODUCT_SERVICE_DB_PASSWORD"),
})

// Cart Service
db, err := surrealdb.New("wss://your-instance.surreal.cloud")
db.Signin(map[string]interface{}{
    "user": "cart_service",
    "pass": os.Getenv("CART_SERVICE_DB_PASSWORD"),
})
```

---

## 5. Inter-Service Communication

### 5.1 Communication Pattern

We'll use **synchronous REST communication** for all service-to-service interactions:

- **REST/HTTP:** For all request-response operations
- **Simple and straightforward:** No message queue complexity
- **Request-response model:** Immediate feedback for all operations

### 5.2 Synchronous Communication (REST)

**Internal API Endpoints** (service-to-service, not exposed via Gateway):

```go
// Product Service Internal API
GET  /internal/products/:id
POST /internal/products/search
POST /internal/products/vector-search

// Cart Service Internal API
GET  /internal/cart/:session_id
POST /internal/cart/add
POST /internal/cart/remove
PUT  /internal/cart/update

// Session Service Internal API
GET  /internal/session/:id
POST /internal/session/validate
```

**Service Discovery:** Use environment variables or Kubernetes DNS

```yaml
# Environment variables for service discovery
PRODUCT_SERVICE_URL=http://product-service:8083
CART_SERVICE_URL=http://cart-service:8082
SESSION_SERVICE_URL=http://session-service:8084
```

### 5.3 Service Client Example (Chat Service calls Product Service)

```go
// internal/infrastructure/client/product_client.go
package client

import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"
)

type ProductClient struct {
    baseURL    string
    httpClient *http.Client
}

func NewProductClient(baseURL string) *ProductClient {
    return &ProductClient{
        baseURL:    baseURL,
        httpClient: &http.Client{Timeout: 10 * time.Second},
    }
}

func (c *ProductClient) SearchProducts(ctx context.Context, query string) ([]*Product, error) {
    url := fmt.Sprintf("%s/internal/products/search?q=%s", c.baseURL, query)
    
    req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
    if err != nil {
        return nil, err
    }
    
    resp, err := c.httpClient.Do(req)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()
    
    var products []*Product
    if err := json.NewDecoder(resp.Body).Decode(&products); err != nil {
        return nil, err
    }
    
    return products, nil
}

func (c *ProductClient) VectorSearch(ctx context.Context, embedding []float32, limit int) ([]*Product, error) {
    // Implementation for vector search
    // ...
}
```

### 5.4 Error Handling & Resilience

**Circuit Breaker Pattern:**

```go
import "github.com/sony/gobreaker"

type ResilientProductClient struct {
    client  *ProductClient
    breaker *gobreaker.CircuitBreaker
}

func NewResilientProductClient(baseURL string) *ResilientProductClient {
    cb := gobreaker.NewCircuitBreaker(gobreaker.Settings{
        Name:        "ProductService",
        MaxRequests: 3,
        Timeout:     60 * time.Second,
    })
    
    return &ResilientProductClient{
        client:  NewProductClient(baseURL),
        breaker: cb,
    }
}

func (r *ResilientProductClient) SearchProducts(ctx context.Context, query string) ([]*Product, error) {
    result, err := r.breaker.Execute(func() (interface{}, error) {
        return r.client.SearchProducts(ctx, query)
    })
    
    if err != nil {
        return nil, err
    }
    
    return result.([]*Product), nil
}
```

---

## 6. Service Specifications

### 6.1 Chat Service

#### Project Structure
```
chat-service/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── domain/
│   │   ├── model/
│   │   │   ├── message.go
│   │   │   └── intent.go
│   │   └── port/
│   │       ├── message_repository.go
│   │       └── llm_service.go
│   ├── application/
│   │   ├── usecase/
│   │   │   └── chat_usecase.go
│   │   └── service/
│   │       └── intent_classifier.go
│   ├── infrastructure/
│   │   ├── persistence/
│   │   │   └── surreal/
│   │   │       └── message_repository.go
│   │   ├── llm/
│   │   │   └── groq_client.go
│   │   └── client/
│   │       ├── product_client.go
│   │       └── cart_client.go
│   └── interfaces/
│       └── api/
│           ├── handler/
│           │   └── chat_handler.go
│           └── router/
│               └── router.go
├── go.mod
└── Dockerfile
```

#### API Endpoints

**Public (via Gateway):**
```
POST   /chat                   # Send a message
GET    /chat/history/:session  # Get conversation history
```

**Internal:**
```
GET    /internal/health        # Health check
GET    /internal/metrics       # Prometheus metrics
```

#### Environment Variables
```bash
CHAT_SERVICE_PORT=8081
SURREALDB_URL=wss://your-instance.surreal.cloud
SURREALDB_USER=chat_service
SURREALDB_PASSWORD=${CHAT_SERVICE_DB_PASSWORD}
GROQ_API_KEY=${GROQ_API_KEY}
PRODUCT_SERVICE_URL=http://product-service:8083
CART_SERVICE_URL=http://cart-service:8082
```

---

### 6.2 Cart Service

#### Project Structure
```
cart-service/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── domain/
│   │   ├── model/
│   │   │   └── cart.go
│   │   └── port/
│   │       └── cart_repository.go
│   ├── application/
│   │   └── usecase/
│   │       └── cart_usecase.go
│   ├── infrastructure/
│   │   ├── persistence/
│   │   │   └── surreal/
│   │   │       └── cart_repository.go
│   │   └── client/
│   │       ├── product_client.go
│   │       └── session_client.go
│   └── interfaces/
│       └── api/
│           ├── handler/
│           │   └── cart_handler.go
│           └── router/
│               └── router.go
├── go.mod
└── Dockerfile
```

#### API Endpoints

**Public (via Gateway):**
```
POST   /cart/add               # Add item to cart
POST   /cart/remove            # Remove item from cart
PUT    /cart/update            # Update quantity
GET    /cart                   # View cart (requires session_id param)
```

**Internal:**
```
GET    /internal/cart/:session_id     # Get cart by session
POST   /internal/cart/validate        # Validate cart
GET    /internal/health
```

---

### 6.3 Product Service

#### Project Structure
```
product-service/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── domain/
│   │   ├── model/
│   │   │   └── product.go
│   │   └── port/
│   │       ├── product_repository.go
│   │       └── embedding_service.go
│   ├── application/
│   │   └── usecase/
│   │       └── product_usecase.go
│   ├── infrastructure/
│   │   ├── persistence/
│   │   │   └── surreal/
│   │   │       └── product_repository.go
│   │   └── embedding/
│   │       └── sentence_transformer.go
│   └── interfaces/
│       └── api/
│           ├── handler/
│           │   └── product_handler.go
│           └── router/
│               └── router.go
├── scripts/
│   └── ingest_products.go
├── go.mod
└── Dockerfile
```

#### API Endpoints

**Public (via Gateway):**
```
GET    /products/:id           # Get product by ID
POST   /products/search        # Full-text search
```

**Internal:**
```
POST   /internal/products/vector-search  # RAG vector search
GET    /internal/products/by-category    # Get by category
GET    /internal/health
```

---

### 6.4 Session Service

#### Project Structure
```
session-service/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── domain/
│   │   ├── model/
│   │   │   └── session.go
│   │   └── port/
│   │       └── session_repository.go
│   ├── application/
│   │   └── usecase/
│   │       ├── session_usecase.go
│   │       └── checkout_usecase.go
│   ├── infrastructure/
│   │   ├── persistence/
│   │   │   └── surreal/
│   │   │       └── session_repository.go
│   │   └── client/
│   │       ├── cart_client.go
│   │       └── product_client.go
│   └── interfaces/
│       └── api/
│           ├── handler/
│           │   ├── session_handler.go
│           │   └── checkout_handler.go
│           └── router/
│               └── router.go
├── go.mod
└── Dockerfile
```

#### API Endpoints

**Public (via Gateway):**
```
POST   /session/create         # Create new session
GET    /session/:id            # Get session details
POST   /checkout               # Checkout
```

**Internal:**
```
POST   /internal/session/validate  # Validate session
GET    /internal/health
```

---

### 6.5 Recommendation Service

#### Project Structure
```
recommendation-service/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── domain/
│   │   └── model/
│   │       └── recommendation.go
│   ├── application/
│   │   └── usecase/
│   │       └── recommend_usecase.go
│   ├── infrastructure/
│   │   └── client/
│   │       ├── cart_client.go
│   │       └── product_client.go
│   └── interfaces/
│       └── api/
│           ├── handler/
│           │   └── recommend_handler.go
│           └── router/
│               └── router.go
├── go.mod
└── Dockerfile
```

#### API Endpoints

**Public (via Gateway):**
```
GET    /recommend              # Get recommendations (requires session_id)
```

**Internal:**
```
GET    /internal/health
```

---

## 7. Deployment Architecture

### 7.1 Docker Compose (Development)

```yaml
# docker-compose.yml
version: '3.8'

services:
  api-gateway:
    build: ./api-gateway
    ports:
      - "8080:8080"
    environment:
      - CHAT_SERVICE_URL=http://chat-service:8081
      - CART_SERVICE_URL=http://cart-service:8082
      - PRODUCT_SERVICE_URL=http://product-service:8083
      - SESSION_SERVICE_URL=http://session-service:8084
      - RECOMMEND_SERVICE_URL=http://recommendation-service:8085
      - JWT_SECRET=${JWT_SECRET}
    depends_on:
      - chat-service
      - cart-service
      - product-service
      - session-service
      - recommendation-service

  chat-service:
    build: ./chat-service
    ports:
      - "8081:8081"
    environment:
      - SURREALDB_URL=${SURREALDB_URL}
      - SURREALDB_USER=chat_service
      - SURREALDB_PASSWORD=${CHAT_SERVICE_DB_PASSWORD}
      - GROQ_API_KEY=${GROQ_API_KEY}
      - PRODUCT_SERVICE_URL=http://product-service:8083
      - CART_SERVICE_URL=http://cart-service:8082

  cart-service:
    build: ./cart-service
    ports:
      - "8082:8082"
    environment:
      - SURREALDB_URL=${SURREALDB_URL}
      - SURREALDB_USER=cart_service
      - SURREALDB_PASSWORD=${CART_SERVICE_DB_PASSWORD}
      - PRODUCT_SERVICE_URL=http://product-service:8083
      - SESSION_SERVICE_URL=http://session-service:8084

  product-service:
    build: ./product-service
    ports:
      - "8083:8083"
    environment:
      - SURREALDB_URL=${SURREALDB_URL}
      - SURREALDB_USER=product_service
      - SURREALDB_PASSWORD=${PRODUCT_SERVICE_DB_PASSWORD}

  session-service:
    build: ./session-service
    ports:
      - "8084:8084"
    environment:
      - SURREALDB_URL=${SURREALDB_URL}
      - SURREALDB_USER=session_service
      - SURREALDB_PASSWORD=${SESSION_SERVICE_DB_PASSWORD}
      - CART_SERVICE_URL=http://cart-service:8082
      - PRODUCT_SERVICE_URL=http://product-service:8083

  recommendation-service:
    build: ./recommendation-service
    ports:
      - "8085:8085"
    environment:
      - CART_SERVICE_URL=http://cart-service:8082
      - PRODUCT_SERVICE_URL=http://product-service:8083
```

### 7.2 Kubernetes Deployment

```yaml
# kubernetes/product-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: product-service
  template:
    metadata:
      labels:
        app: product-service
    spec:
      containers:
      - name: product-service
        image: chatbot/product-service:latest
        ports:
        - containerPort: 8083
        env:
        - name: SURREALDB_URL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: surrealdb_url
        - name: SURREALDB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secrets
              key: product_service_password
        livenessProbe:
          httpGet:
            path: /internal/health
            port: 8083
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /internal/health
            port: 8083
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: product-service
spec:
  selector:
    app: product-service
  ports:
  - protocol: TCP
    port: 8083
    targetPort: 8083
```

---

## 8. Security & Authentication

### 8.1 API Gateway Authentication Flow

```
1. Client Login → Auth Service (or Gateway handles this)
   POST /auth/login
   {username, password}
   
2. Gateway returns JWT:
   {
     "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
     "expires_in": 86400
   }

3. Client includes JWT in subsequent requests:
   Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

4. Gateway validates JWT and extracts user_id

5. Gateway forwards request to services with user context
```

### 8.2 Service-to-Service Authentication

**Option 1: API Keys (Simple)**
```go
// Internal service calls include an API key
req.Header.Set("X-Internal-API-Key", os.Getenv("INTERNAL_API_KEY"))
```

**Option 2: mTLS (Mutual TLS) - Production Recommended**
- Each service has a certificate
- Services verify each other's certificates

---

## 9. Observability & Monitoring

### 9.1 Logging

**Structured Logging** with correlation IDs:

```go
// Each request gets a correlation ID from the gateway
ctx = context.WithValue(ctx, "correlation_id", correlationID)

logger.Info("Processing chat request",
    "correlation_id", correlationID,
    "session_id", sessionID,
    "service", "chat-service",
)
```

### 9.2 Metrics (Prometheus)

Each service exposes `/internal/metrics`:

```go
// Example metrics
http_requests_total{service="chat-service", endpoint="/chat", status="200"} 1543
http_request_duration_seconds{service="chat-service", endpoint="/chat"} 0.245
```

### 9.3 Distributed Tracing (Jaeger/OpenTelemetry)

```go
import "go.opentelemetry.io/otel"

func (h *ChatHandler) ProcessMessage(w http.ResponseWriter, r *http.Request) {
    ctx, span := otel.Tracer("chat-service").Start(r.Context(), "ProcessMessage")
    defer span.End()
    
    // Trace propagates to downstream services
    products, err := h.productClient.VectorSearch(ctx, embedding, 5)
    // ...
}
```

---

## 10. Development Workflow

### 10.1 Repository Structure

```
chatbot-microservices/
├── api-gateway/
├── chat-service/
├── cart-service/
├── product-service/
├── session-service/
├── recommendation-service/
├── shared/                 # Shared libraries
│   ├── pkg/
│   │   ├── logger/
│   │   ├── middleware/
│   │   └── validator/
│   └── proto/             # gRPC proto files (if using gRPC)
├── docker-compose.yml
├── kubernetes/
│   ├── deployments/
│   ├── services/
│   └── configmaps/
├── scripts/
│   └── setup-db.sh
└── README.md
```

### 10.2 Local Development

```bash
# Start all services
docker-compose up

# Start individual service for development
cd chat-service
go run cmd/server/main.go

# Run tests
go test ./...
```

### 10.3 CI/CD Pipeline

```yaml
# .github/workflows/chat-service.yml
name: Chat Service CI/CD

on:
  push:
    paths:
      - 'chat-service/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: |
          cd chat-service
          go test -v ./...
  
  build-and-push:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - name: Build Docker image
        run: |
          docker build -t chatbot/chat-service:${{ github.sha }} ./chat-service
      - name: Push to registry
        run: |
          docker push chatbot/chat-service:${{ github.sha }}
  
  deploy:
    runs-on: ubuntu-latest
    needs: build-and-push
    steps:
      - name: Deploy to Kubernetes
        run: |
          kubectl set image deployment/chat-service \
            chat-service=chatbot/chat-service:${{ github.sha }}
```

---

## Summary

This microservices architecture provides:

✅ **Clear service boundaries** based on DDD bounded contexts
✅ **Single API Gateway** for centralized routing, auth, and rate limiting
✅ **Shared SurrealDB** with schema ownership per service
✅ **Clean Architecture** within each service
✅ **Inter-service communication** via REST (with optional event-driven patterns)
✅ **Independent deployment** and scaling per service
✅ **Resilience patterns** (circuit breakers, retries)
✅ **Comprehensive observability** (logging, metrics, tracing)
✅ **Production-ready** with Kubernetes deployment examples

---

**Next Steps:**
1. Review this microservices architecture
2. Confirm the service boundaries
3. Proceed with detailed implementation of each service

**Document Version:** 1.0  
**Last Updated:** 2025-11-15  
**Author:** Senior Software Architect
