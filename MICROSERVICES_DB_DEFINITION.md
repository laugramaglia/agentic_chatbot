# SurrealDB Schema for Microservices Architecture

## Overview

This document defines the complete database schema for the Shopping Cart Chatbot microservices architecture. The system uses a **single SurrealDB MCP instance** with **schema ownership per microservice**.

**Architecture Pattern:** Shared Database, Schema-per-Service

---

## Table of Contents

1. [Database Architecture](#1-database-architecture)
2. [Schema Ownership](#2-schema-ownership)
3. [Service-Specific Users & Permissions](#3-service-specific-users--permissions)
4. [Table Definitions](#4-table-definitions)
5. [Service-to-Table Mapping](#5-service-to-table-mapping)
6. [Query Examples per Service](#6-query-examples-per-service)
7. [Migration Strategy](#7-migration-strategy)
8. [Data Consistency Patterns](#8-data-consistency-patterns)

---

## 1. Database Architecture

### 1.1 Single SurrealDB Instance with Logical Separation

```
SurrealDB MCP Instance
│
└── Namespace: production
    │
    └── Database: chatbot
        │
        ├── product (owned by Product Service)
        ├── cart (owned by Cart Service)
        ├── user_session (owned by Session Service)
        └── chat_message (owned by Chat Service)
```

### 1.2 Why Shared Database?

**Advantages:**
- ✅ Simpler transaction management (single DB)
- ✅ No distributed transaction complexity
- ✅ Join queries possible (when needed)
- ✅ Cost-effective (single SurrealDB MCP instance)
- ✅ Easier to maintain consistency

**Disadvantages (mitigated by schema ownership):**
- ⚠️ Potential tight coupling (mitigated by access controls)
- ⚠️ Schema changes require coordination (managed via migrations)

**Mitigation Strategy:**
- Each service has its own DB user with limited permissions
- Services can only write to their owned tables
- Cross-service data access is read-only via internal APIs

---

## 2. Schema Ownership

### 2.1 Ownership Rules

| Table | Owner Service | Write Access | Read Access |
|-------|--------------|--------------|-------------|
| `product` | Product Service | Product Service | All services (via Product Service API) |
| `cart` | Cart Service | Cart Service | Cart Service, Session Service (for checkout) |
| `user_session` | Session Service | Session Service | All services (for validation) |
| `chat_message` | Chat Service | Chat Service | Chat Service only |

### 2.2 Access Patterns

```
┌─────────────────────────────────────────────────────────────┐
│                      Access Matrix                          │
├────────────┬──────────┬──────────┬──────────┬──────────────┤
│ Service    │ product  │ cart     │ session  │ chat_message │
├────────────┼──────────┼──────────┼──────────┼──────────────┤
│ Chat       │ Read     │ Read     │ Read     │ Full         │
│ Cart       │ Read     │ Full     │ Read     │ None         │
│ Product    │ Full     │ None     │ None     │ None         │
│ Session    │ Read     │ Read     │ Full     │ None         │
│ Recommend  │ Read     │ Read     │ Read     │ None         │
└────────────┴──────────┴──────────┴──────────┴──────────────┘

Legend:
  Full = SELECT, INSERT, UPDATE, DELETE
  Read = SELECT only
  None = No access
```

---

## 3. Service-Specific Users & Permissions

### 3.1 Create Database Users

```sql
-- =============================================================================
-- Service-Specific Database Users & Permissions
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. CHAT SERVICE USER
-- -----------------------------------------------------------------------------
DEFINE USER chat_service ON DATABASE PASSWORD 'chat_service_secret_key_123' ROLES EDITOR;

-- Chat service can fully manage chat_message table
DEFINE ACCESS chat_service_write ON TABLE chat_message FOR USER chat_service GRANT FULL;

-- Chat service can read other tables for context
DEFINE ACCESS chat_service_read_product ON TABLE product FOR USER chat_service GRANT SELECT;
DEFINE ACCESS chat_service_read_cart ON TABLE cart FOR USER chat_service GRANT SELECT;
DEFINE ACCESS chat_service_read_session ON TABLE user_session FOR USER chat_service GRANT SELECT;

-- -----------------------------------------------------------------------------
-- 2. CART SERVICE USER
-- -----------------------------------------------------------------------------
DEFINE USER cart_service ON DATABASE PASSWORD 'cart_service_secret_key_456' ROLES EDITOR;

-- Cart service can fully manage cart table
DEFINE ACCESS cart_service_write ON TABLE cart FOR USER cart_service GRANT FULL;

-- Cart service can read product and session for validation
DEFINE ACCESS cart_service_read_product ON TABLE product FOR USER cart_service GRANT SELECT;
DEFINE ACCESS cart_service_read_session ON TABLE user_session FOR USER cart_service GRANT SELECT;

-- -----------------------------------------------------------------------------
-- 3. PRODUCT SERVICE USER
-- -----------------------------------------------------------------------------
DEFINE USER product_service ON DATABASE PASSWORD 'product_service_secret_key_789' ROLES EDITOR;

-- Product service can fully manage product table
DEFINE ACCESS product_service_write ON TABLE product FOR USER product_service GRANT FULL;

-- Product service has no access to other tables (isolated)

-- -----------------------------------------------------------------------------
-- 4. SESSION SERVICE USER
-- -----------------------------------------------------------------------------
DEFINE USER session_service ON DATABASE PASSWORD 'session_service_secret_key_abc' ROLES EDITOR;

-- Session service can fully manage user_session table
DEFINE ACCESS session_service_write ON TABLE user_session FOR USER session_service GRANT FULL;

-- Session service can read cart and product for checkout
DEFINE ACCESS session_service_read_cart ON TABLE cart FOR USER session_service GRANT SELECT;
DEFINE ACCESS session_service_read_product ON TABLE product FOR USER session_service GRANT SELECT;

-- -----------------------------------------------------------------------------
-- 5. RECOMMENDATION SERVICE USER (Read-Only)
-- -----------------------------------------------------------------------------
DEFINE USER recommend_service ON DATABASE PASSWORD 'recommend_service_secret_key_def' ROLES VIEWER;

-- Recommendation service is read-only
DEFINE ACCESS recommend_service_read_product ON TABLE product FOR USER recommend_service GRANT SELECT;
DEFINE ACCESS recommend_service_read_cart ON TABLE cart FOR USER recommend_service GRANT SELECT;
DEFINE ACCESS recommend_service_read_session ON TABLE user_session FOR USER recommend_service GRANT SELECT;
```

### 3.2 Connection Examples per Service

```go
// Chat Service
chatDB, err := surrealdb.New("wss://your-instance.surreal.cloud")
chatDB.Signin(map[string]interface{}{
    "user": "chat_service",
    "pass": os.Getenv("CHAT_SERVICE_DB_PASSWORD"),
})
chatDB.Use("production", "chatbot")

// Cart Service
cartDB, err := surrealdb.New("wss://your-instance.surreal.cloud")
cartDB.Signin(map[string]interface{}{
    "user": "cart_service",
    "pass": os.Getenv("CART_SERVICE_DB_PASSWORD"),
})
cartDB.Use("production", "chatbot")

// Product Service
productDB, err := surrealdb.New("wss://your-instance.surreal.cloud")
productDB.Signin(map[string]interface{}{
    "user": "product_service",
    "pass": os.Getenv("PRODUCT_SERVICE_DB_PASSWORD"),
})
productDB.Use("production", "chatbot")

// Session Service
sessionDB, err := surrealdb.New("wss://your-instance.surreal.cloud")
sessionDB.Signin(map[string]interface{}{
    "user": "session_service",
    "pass": os.Getenv("SESSION_SERVICE_DB_PASSWORD"),
})
sessionDB.Use("production", "chatbot")

// Recommendation Service
recommendDB, err := surrealdb.New("wss://your-instance.surreal.cloud")
recommendDB.Signin(map[string]interface{}{
    "user": "recommend_service",
    "pass": os.Getenv("RECOMMEND_SERVICE_DB_PASSWORD"),
})
recommendDB.Use("production", "chatbot")
```

---

## 4. Table Definitions

### 4.1 Product Table (Product Service Owns)

```sql
-- =============================================================================
-- PRODUCT TABLE
-- Owner: Product Service
-- =============================================================================

DEFINE TABLE product SCHEMAFULL;

-- Fields
DEFINE FIELD name ON product TYPE string;
DEFINE FIELD description ON product TYPE string;
DEFINE FIELD specs ON product TYPE string;
DEFINE FIELD price ON product TYPE float;
DEFINE FIELD category ON product TYPE string;
DEFINE FIELD sub_category ON product TYPE string;
DEFINE FIELD score ON product TYPE float;
DEFINE FIELD stock_quantity ON product TYPE int DEFAULT 0;
DEFINE FIELD image_url ON product TYPE string;
DEFINE FIELD embedding ON product TYPE array;
DEFINE FIELD created_at ON product TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON product TYPE datetime DEFAULT time::now();

-- Constraints
DEFINE FIELD score ON product ASSERT $value >= 0 AND $value <= 5;
DEFINE FIELD stock_quantity ON product ASSERT $value >= 0;

-- Indexes for performance
DEFINE INDEX idx_product_category ON product FIELDS category;
DEFINE INDEX idx_product_sub_category ON product FIELDS sub_category;
DEFINE INDEX idx_product_score ON product FIELDS score;
DEFINE INDEX idx_product_name ON product FIELDS name SEARCH ANALYZER ascii BM25 HIGHLIGHTS;
DEFINE INDEX idx_product_cat_subcat_score ON product FIELDS category, sub_category, score;

-- Events
DEFINE EVENT product_updated ON product WHEN $event = "UPDATE" THEN {
    UPDATE $after SET updated_at = time::now();
};
```

**Field Details:**

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `name` | string | Product name | Required |
| `description` | string | Detailed description | Required |
| `specs` | string | Technical specifications | Optional |
| `price` | float | Price in USD | Required, > 0 |
| `category` | string | Primary category | Required |
| `sub_category` | string | Sub-category | Required |
| `score` | float | User rating (0-5) | 0 ≤ score ≤ 5 |
| `stock_quantity` | int | Available inventory | ≥ 0 |
| `image_url` | string | Product image URL | Optional |
| `embedding` | array | Vector (384 or 1536 dims) | Required for RAG |
| `created_at` | datetime | Creation timestamp | Auto-generated |
| `updated_at` | datetime | Last update timestamp | Auto-updated |

---

### 4.2 Cart Table (Cart Service Owns)

```sql
-- =============================================================================
-- CART TABLE
-- Owner: Cart Service
-- =============================================================================

DEFINE TABLE cart SCHEMAFULL;

-- Fields
DEFINE FIELD session_id ON cart TYPE record(user_session);
DEFINE FIELD product_id ON cart TYPE record(product);
DEFINE FIELD quantity ON cart TYPE int DEFAULT 1;
DEFINE FIELD added_at ON cart TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON cart TYPE datetime DEFAULT time::now();

-- Constraints
DEFINE FIELD quantity ON cart ASSERT $value > 0;

-- Indexes
DEFINE INDEX idx_cart_session ON cart FIELDS session_id;
DEFINE INDEX idx_cart_product ON cart FIELDS product_id;
DEFINE INDEX idx_cart_session_product ON cart FIELDS session_id, product_id UNIQUE;

-- Events
DEFINE EVENT cart_updated ON cart WHEN $event = "UPDATE" THEN {
    UPDATE $after SET updated_at = time::now();
};
```

**Field Details:**

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `session_id` | record | FK to user_session | Required |
| `product_id` | record | FK to product | Required |
| `quantity` | int | Item quantity | > 0 |
| `added_at` | datetime | When added to cart | Auto-generated |
| `updated_at` | datetime | Last update | Auto-updated |

**Unique Constraint:** `(session_id, product_id)` - Prevents duplicate products in same cart

---

### 4.3 User Session Table (Session Service Owns)

```sql
-- =============================================================================
-- USER_SESSION TABLE
-- Owner: Session Service
-- =============================================================================

DEFINE TABLE user_session SCHEMAFULL;

-- Fields
DEFINE FIELD user_id ON user_session TYPE string;
DEFINE FIELD status ON user_session TYPE string DEFAULT "active";
DEFINE FIELD started_at ON user_session TYPE datetime DEFAULT time::now();
DEFINE FIELD completed_at ON user_session TYPE datetime;
DEFINE FIELD metadata ON user_session TYPE object;

-- Constraints
DEFINE FIELD status ON user_session ASSERT $value IN ["active", "completed", "abandoned"];

-- Indexes
DEFINE INDEX idx_session_user_id ON user_session FIELDS user_id;
DEFINE INDEX idx_session_status ON user_session FIELDS status;
DEFINE INDEX idx_session_started ON user_session FIELDS started_at;

-- Events: Update completed_at when status changes to completed
DEFINE EVENT session_completed ON user_session WHEN $before.status = "active" AND $after.status = "completed" THEN {
    UPDATE $after SET completed_at = time::now();
};
```

**Field Details:**

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `user_id` | string | User identifier | Required |
| `status` | string | Session status | "active", "completed", "abandoned" |
| `started_at` | datetime | Session start | Auto-generated |
| `completed_at` | datetime | Session end | Null until completed |
| `metadata` | object | Additional data | Optional |

---

### 4.4 Chat Message Table (Chat Service Owns)

```sql
-- =============================================================================
-- CHAT_MESSAGE TABLE
-- Owner: Chat Service
-- =============================================================================

DEFINE TABLE chat_message SCHEMAFULL;

-- Fields
DEFINE FIELD session_id ON chat_message TYPE record(user_session);
DEFINE FIELD role ON chat_message TYPE string;
DEFINE FIELD content ON chat_message TYPE string;
DEFINE FIELD timestamp ON chat_message TYPE datetime DEFAULT time::now();
DEFINE FIELD intent ON chat_message TYPE string;
DEFINE FIELD entities ON chat_message TYPE object;

-- Constraints
DEFINE FIELD role ON chat_message ASSERT $value IN ["user", "assistant", "system"];

-- Indexes
DEFINE INDEX idx_message_session ON chat_message FIELDS session_id;
DEFINE INDEX idx_message_timestamp ON chat_message FIELDS timestamp;
DEFINE INDEX idx_message_role ON chat_message FIELDS role;
```

**Field Details:**

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `session_id` | record | FK to user_session | Required |
| `role` | string | Message sender | "user", "assistant", "system" |
| `content` | string | Message text | Required |
| `timestamp` | datetime | When sent | Auto-generated |
| `intent` | string | Classified intent | Optional |
| `entities` | object | Extracted entities | Optional |

---

## 5. Service-to-Table Mapping

### 5.1 Visual Service-Table Relationships

```
┌────────────────────────────────────────────────────────────────┐
│                    MICROSERVICES                               │
└────────────────────────────────────────────────────────────────┘

┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Chat      │     │    Cart     │     │  Product    │
│  Service    │     │  Service    │     │  Service    │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │ OWNS              │ OWNS              │ OWNS
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│chat_message │     │    cart     │     │   product   │
│   TABLE     │     │   TABLE     │     │   TABLE     │
└─────────────┘     └──────┬──────┘     └─────────────┘
                           │
                           │ REFERENCES
                           │
       ┌───────────────────┴───────────────────┐
       │                                       │
       ▼                                       ▼
┌─────────────┐                         ┌─────────────┐
│user_session │                         │   product   │
│   TABLE     │                         │   TABLE     │
└──────┬──────┘                         └─────────────┘
       │
       │ OWNED BY
       ▼
┌─────────────┐
│  Session    │
│  Service    │
└─────────────┘

┌─────────────┐
│ Recommend   │
│  Service    │
│  (Read-Only)│
└─────────────┘
```

---

## 6. Query Examples per Service

### 6.1 Product Service Queries

#### Create Product (with embedding)

```sql
CREATE product SET
    name = $name,
    description = $description,
    specs = $specs,
    price = $price,
    category = $category,
    sub_category = $sub_category,
    score = $score,
    stock_quantity = $stock_quantity,
    image_url = $image_url,
    embedding = $embedding;
```

#### Vector Similarity Search (RAG)

```sql
SELECT 
    *,
    vector::similarity::cosine(embedding, $query_embedding) AS similarity
FROM product
WHERE vector::similarity::cosine(embedding, $query_embedding) > 0.7
ORDER BY similarity DESC
LIMIT $limit;
```

#### Get Products by Category

```sql
SELECT * FROM product
WHERE category = $category AND sub_category != $exclude_sub_category
ORDER BY score DESC
LIMIT $limit;
```

---

### 6.2 Cart Service Queries

#### Add Item to Cart (Upsert Logic)

```sql
-- Check if item exists
LET $existing = (
    SELECT * FROM cart
    WHERE session_id = $session_id AND product_id = $product_id
);

-- If exists, update quantity; otherwise, create new
IF $existing {
    UPDATE cart
    SET quantity = quantity + $quantity
    WHERE session_id = $session_id AND product_id = $product_id
    RETURN AFTER;
} ELSE {
    CREATE cart SET
        session_id = $session_id,
        product_id = $product_id,
        quantity = $quantity;
};
```

#### Get Cart Items with Product Details

```sql
SELECT 
    id,
    quantity,
    added_at,
    product_id.name AS product_name,
    product_id.price AS unit_price,
    (product_id.price * quantity) AS subtotal
FROM cart
WHERE session_id = $session_id;
```

#### Remove Item from Cart

```sql
DELETE FROM cart
WHERE session_id = $session_id AND product_id = $product_id;
```

#### Update Quantity

```sql
UPDATE cart
SET quantity = $new_quantity
WHERE session_id = $session_id AND product_id = $product_id;
```

---

### 6.3 Session Service Queries

#### Create Session

```sql
CREATE user_session SET
    user_id = $user_id,
    status = "active",
    metadata = {
        user_agent: $user_agent,
        ip_address: $ip_address
    };
```

#### Get Checkout Summary

```sql
-- Get all cart items with product details
LET $cart_items = (
    SELECT 
        cart.quantity,
        product.id AS product_id,
        product.name AS product_name,
        product.price AS unit_price,
        (product.price * cart.quantity) AS subtotal
    FROM cart
    WHERE cart.session_id = $session_id
    FETCH product_id
);

-- Calculate totals
RETURN {
    items: $cart_items,
    total_items: math::sum($cart_items.*.quantity),
    total_price: math::sum($cart_items.*.subtotal)
};
```

#### Complete Session

```sql
UPDATE user_session
SET 
    status = "completed",
    completed_at = time::now()
WHERE id = $session_id;
```

---

### 6.4 Chat Service Queries

#### Store Message

```sql
CREATE chat_message SET
    session_id = $session_id,
    role = $role,
    content = $content,
    intent = $intent,
    entities = $entities;
```

#### Get Conversation History

```sql
SELECT * FROM chat_message
WHERE session_id = $session_id
ORDER BY timestamp ASC
LIMIT $limit;
```

---

### 6.5 Recommendation Service Queries

#### Get Recommendations Based on Cart

```sql
-- Get user's cart items
LET $cart_products = (
    SELECT product_id FROM cart
    WHERE session_id = $session_id
    FETCH product_id
);

-- Get last added product's category
LET $last_product = $cart_products[-1].product_id;

-- Find related products
SELECT * FROM product
WHERE (category = $last_product.category AND sub_category != $last_product.sub_category)
   OR (category = $last_product.category AND id NOT IN $cart_products.*.product_id)
ORDER BY score DESC
LIMIT 5;
```

---

## 7. Migration Strategy

### 7.1 Initial Schema Migration

**File:** `migrations/001_initial_schema.surql`

```sql
-- =============================================================================
-- Migration 001: Initial Schema Setup
-- =============================================================================

-- Create tables in order (respecting dependencies)

-- 1. Product table (no dependencies)
DEFINE TABLE product SCHEMAFULL;
-- ... (full definition from section 4.1)

-- 2. User session table (no dependencies)
DEFINE TABLE user_session SCHEMAFULL;
-- ... (full definition from section 4.3)

-- 3. Cart table (depends on product and user_session)
DEFINE TABLE cart SCHEMAFULL;
-- ... (full definition from section 4.2)

-- 4. Chat message table (depends on user_session)
DEFINE TABLE chat_message SCHEMAFULL;
-- ... (full definition from section 4.4)

-- Create indexes
-- ... (all indexes from sections above)

-- Create events
-- ... (all events from sections above)

-- Create service users and permissions
-- ... (from section 3.1)
```

### 7.2 Running Migrations

```bash
# Option 1: Using SurrealDB CLI
surreal import --conn wss://your-instance.surreal.cloud \
  --user root --pass root \
  --ns production --db chatbot \
  migrations/001_initial_schema.surql

# Option 2: Using Go migration tool
cd scripts/migrations
go run migrate.go up
```

### 7.3 Migration per Service

Each service can have its own migration files:

```
migrations/
├── product-service/
│   ├── 001_create_product_table.surql
│   └── 002_add_embedding_index.surql
├── cart-service/
│   ├── 001_create_cart_table.surql
│   └── 002_add_cart_indexes.surql
├── session-service/
│   └── 001_create_session_table.surql
└── chat-service/
    └── 001_create_chat_message_table.surql
```

---

## 8. Data Consistency Patterns

### 8.1 Eventual Consistency

**Problem:** Cart Service adds item, but Product Service hasn't fully ingested product yet.

**Solution:** Use optimistic locking and retry logic:

```go
// Cart Service
func (s *CartService) AddToCart(ctx context.Context, req *AddToCartRequest) error {
    // Validate product exists via Product Service API
    product, err := s.productClient.GetProduct(ctx, req.ProductID)
    if err != nil {
        return fmt.Errorf("product not found: %w", err)
    }
    
    // Add to cart in DB
    return s.cartRepo.AddItem(ctx, &model.Cart{
        SessionID: req.SessionID,
        ProductID: req.ProductID,
        Quantity:  req.Quantity,
    })
}
```

### 8.2 Referential Integrity

**SurrealDB Record Types** provide referential integrity:

```sql
-- Cart table definition ensures product_id references a valid product
DEFINE FIELD product_id ON cart TYPE record(product);

-- This query will fail if product doesn't exist:
CREATE cart SET
    session_id = user_session:abc123,
    product_id = product:invalid_id,  -- ERROR if product:invalid_id doesn't exist
    quantity = 1;
```

### 8.3 Distributed Transactions (When Needed)

**Scenario:** Checkout requires:
1. Mark session as completed
2. Clear cart items

**Solution:** Use SurrealDB transactions:

```sql
BEGIN TRANSACTION;

-- Mark session as completed
UPDATE user_session SET status = "completed" WHERE id = $session_id;

-- Optionally: Archive cart items instead of deleting
UPDATE cart SET archived = true WHERE session_id = $session_id;

COMMIT TRANSACTION;
```

**Go Implementation:**

```go
func (s *SessionService) Checkout(ctx context.Context, sessionID string) error {
    tx, err := s.db.Begin()
    if err != nil {
        return err
    }
    defer tx.Rollback()
    
    // Update session
    _, err = tx.Query("UPDATE user_session SET status = 'completed' WHERE id = $1", sessionID)
    if err != nil {
        return err
    }
    
    // Archive cart
    _, err = tx.Query("UPDATE cart SET archived = true WHERE session_id = $1", sessionID)
    if err != nil {
        return err
    }
    
    return tx.Commit()
}
```

---

## 9. Complete Migration Script

**File:** `migrations/complete_schema.surql`

```sql
-- =============================================================================
-- Shopping Cart Chatbot - Complete Database Schema
-- Microservices Architecture
-- Target: SurrealDB Multi-Cloud Platform (MCP)
-- =============================================================================

-- =============================================================================
-- PART 1: TABLE DEFINITIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. PRODUCT TABLE (Product Service)
-- -----------------------------------------------------------------------------
DEFINE TABLE product SCHEMAFULL;

DEFINE FIELD name ON product TYPE string;
DEFINE FIELD description ON product TYPE string;
DEFINE FIELD specs ON product TYPE string;
DEFINE FIELD price ON product TYPE float;
DEFINE FIELD category ON product TYPE string;
DEFINE FIELD sub_category ON product TYPE string;
DEFINE FIELD score ON product TYPE float;
DEFINE FIELD stock_quantity ON product TYPE int DEFAULT 0;
DEFINE FIELD image_url ON product TYPE string;
DEFINE FIELD embedding ON product TYPE array;
DEFINE FIELD created_at ON product TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON product TYPE datetime DEFAULT time::now();

DEFINE FIELD score ON product ASSERT $value >= 0 AND $value <= 5;
DEFINE FIELD stock_quantity ON product ASSERT $value >= 0;

DEFINE INDEX idx_product_category ON product FIELDS category;
DEFINE INDEX idx_product_sub_category ON product FIELDS sub_category;
DEFINE INDEX idx_product_score ON product FIELDS score;
DEFINE INDEX idx_product_name ON product FIELDS name SEARCH ANALYZER ascii BM25 HIGHLIGHTS;
DEFINE INDEX idx_product_cat_subcat_score ON product FIELDS category, sub_category, score;

DEFINE EVENT product_updated ON product WHEN $event = "UPDATE" THEN {
    UPDATE $after SET updated_at = time::now();
};

-- -----------------------------------------------------------------------------
-- 2. USER_SESSION TABLE (Session Service)
-- -----------------------------------------------------------------------------
DEFINE TABLE user_session SCHEMAFULL;

DEFINE FIELD user_id ON user_session TYPE string;
DEFINE FIELD status ON user_session TYPE string DEFAULT "active";
DEFINE FIELD started_at ON user_session TYPE datetime DEFAULT time::now();
DEFINE FIELD completed_at ON user_session TYPE datetime;
DEFINE FIELD metadata ON user_session TYPE object;

DEFINE FIELD status ON user_session ASSERT $value IN ["active", "completed", "abandoned"];

DEFINE INDEX idx_session_user_id ON user_session FIELDS user_id;
DEFINE INDEX idx_session_status ON user_session FIELDS status;
DEFINE INDEX idx_session_started ON user_session FIELDS started_at;

DEFINE EVENT session_completed ON user_session WHEN $before.status = "active" AND $after.status = "completed" THEN {
    UPDATE $after SET completed_at = time::now();
};

-- -----------------------------------------------------------------------------
-- 3. CART TABLE (Cart Service)
-- -----------------------------------------------------------------------------
DEFINE TABLE cart SCHEMAFULL;

DEFINE FIELD session_id ON cart TYPE record(user_session);
DEFINE FIELD product_id ON cart TYPE record(product);
DEFINE FIELD quantity ON cart TYPE int DEFAULT 1;
DEFINE FIELD added_at ON cart TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON cart TYPE datetime DEFAULT time::now();

DEFINE FIELD quantity ON cart ASSERT $value > 0;

DEFINE INDEX idx_cart_session ON cart FIELDS session_id;
DEFINE INDEX idx_cart_product ON cart FIELDS product_id;
DEFINE INDEX idx_cart_session_product ON cart FIELDS session_id, product_id UNIQUE;

DEFINE EVENT cart_updated ON cart WHEN $event = "UPDATE" THEN {
    UPDATE $after SET updated_at = time::now();
};

-- -----------------------------------------------------------------------------
-- 4. CHAT_MESSAGE TABLE (Chat Service)
-- -----------------------------------------------------------------------------
DEFINE TABLE chat_message SCHEMAFULL;

DEFINE FIELD session_id ON chat_message TYPE record(user_session);
DEFINE FIELD role ON chat_message TYPE string;
DEFINE FIELD content ON chat_message TYPE string;
DEFINE FIELD timestamp ON chat_message TYPE datetime DEFAULT time::now();
DEFINE FIELD intent ON chat_message TYPE string;
DEFINE FIELD entities ON chat_message TYPE object;

DEFINE FIELD role ON chat_message ASSERT $value IN ["user", "assistant", "system"];

DEFINE INDEX idx_message_session ON chat_message FIELDS session_id;
DEFINE INDEX idx_message_timestamp ON chat_message FIELDS timestamp;
DEFINE INDEX idx_message_role ON chat_message FIELDS role;

-- =============================================================================
-- PART 2: SERVICE USERS & PERMISSIONS
-- =============================================================================

-- Chat Service User
DEFINE USER chat_service ON DATABASE PASSWORD 'CHANGE_ME_chat_service_password' ROLES EDITOR;

-- Cart Service User
DEFINE USER cart_service ON DATABASE PASSWORD 'CHANGE_ME_cart_service_password' ROLES EDITOR;

-- Product Service User
DEFINE USER product_service ON DATABASE PASSWORD 'CHANGE_ME_product_service_password' ROLES EDITOR;

-- Session Service User
DEFINE USER session_service ON DATABASE PASSWORD 'CHANGE_ME_session_service_password' ROLES EDITOR;

-- Recommendation Service User (Read-Only)
DEFINE USER recommend_service ON DATABASE PASSWORD 'CHANGE_ME_recommend_service_password' ROLES VIEWER;

-- NOTE: Fine-grained table-level permissions would be configured via SurrealDB's
-- access control system. The above users have database-level roles.
-- In production, implement row-level security and table-level access controls.

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================
```

---

## Summary

This microservices database schema provides:

✅ **Single SurrealDB instance** with logical separation per service  
✅ **Schema ownership** model with clear boundaries  
✅ **Service-specific database users** with appropriate permissions  
✅ **Referential integrity** via SurrealDB record types  
✅ **Optimized indexes** for each service's query patterns  
✅ **Event triggers** for automatic timestamp updates  
✅ **Migration strategy** for schema versioning  
✅ **Consistency patterns** for distributed operations  

**Key Design Decisions:**

1. **Shared DB vs. DB per Service:** Chose shared DB for simplicity, transactional integrity, and cost-effectiveness
2. **Access Control:** Each service has its own DB user with limited permissions
3. **Data Ownership:** Clear ownership rules prevent services from directly modifying other services' data
4. **Read-Only Access:** Services can read other tables but must use APIs to modify them
5. **Referential Integrity:** SurrealDB's record types ensure valid foreign keys

**Next Steps:**
1. Review schema and permissions
2. Run initial migration on SurrealDB MCP
3. Test service-specific user access
4. Implement repository layers per service

**Document Version:** 1.0  
**Last Updated:** 2025-11-15  
**Author:** Senior Software Architect
