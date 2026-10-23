# Build a Production-Ready Provision Store Management System

## 1. Product Overview

Build a modern, mobile-first **Provision Store Management System** designed for small and medium-sized retail businesses in Nigeria and other African markets.

The application should help a shop owner manage:

- Products
- Product categories
- Units of measurement
- Inventory/stock
- Purchases
- Sales
- Expenses
- Customers
- Suppliers
- Debts/credit sales
- Profit
- Revenue
- Stock valuation
- Low-stock alerts
- Business performance
- Reports
- Multiple users/staff
- Barcode scanning

The system should be designed as the foundation for a future **AI Store Manager**, but **DO NOT implement the AI agent in this version**.

The current version must have a clean, reliable and deterministic business engine that an AI agent can later interact with through APIs/tools.

---

# 2. Core Product Philosophy

Do NOT build this as a generic inventory CRUD application.

Build it as a **complete operating system for a provision store**.

The owner should be able to use the application throughout the day:

1. Receive goods from suppliers
2. Add/update inventory
3. Sell products
4. Scan products using the phone camera
5. Record sales quickly
6. Record expenses
7. Track customers who owe money
8. Track supplier debts
9. Monitor stock
10. Understand revenue and profit
11. See which products are selling
12. Know which products need restocking
13. Understand the financial state of the business

The application should minimize unnecessary data entry.

The interface must be extremely simple because many target users may not be technically sophisticated.

---

# 3. Target User

Primary user:

A Nigerian provision-store owner who currently uses:

- Notebook
- Calculator
- WhatsApp
- Memory
- Excel
- Informal record keeping

The application should feel easier than using a spreadsheet.

The owner should be able to perform common operations in a few taps.

---

# 4. Platform

Build the application as a **mobile-first application**.

Recommended frontend:

- Flutter
- Material 3
- Responsive layouts
- Clean modern UI
- Android-first

Backend:

- Django + Django REST Framework
- PostgreSQL

The architecture must support an eventual web dashboard and AI-agent integration.

---

# 5. OFFLINE-FIRST REQUIREMENT

The application should be designed **offline-first**.

A shop should still be able to:

- View products
- Scan barcodes
- Record sales
- Record purchases
- Update inventory
- View recent transactions
- Record expenses

without an internet connection.

Data should be stored locally and synchronized with the backend when internet connectivity becomes available.

Provide:

- Local database
- Sync queue
- Sync status
- Manual "Sync Now" button
- Automatic synchronization when connectivity returns
- Conflict handling
- Unique transaction IDs generated locally
- Idempotent API endpoints

The user must never lose a sale simply because the internet went off.

Display synchronization status clearly:

🟢 Synced

🟡 Pending sync

🔴 Sync failed

---

# 6. BUSINESS STRUCTURE

The application must be multi-tenant.

Each business must have completely isolated data.

Core relationship:

Business
→ Users
→ Products
→ Categories
→ Units
→ Inventory
→ Sales
→ Purchases
→ Customers
→ Suppliers
→ Expenses

A user must NEVER be able to access another business's data.

Every business-related model should have a business/tenant relationship.

---

# 7. USER ROLES

Implement at least:

### Owner

Can:

- Manage business
- Manage users
- View all reports
- Add/edit/delete products
- Manage inventory
- Record sales
- Record purchases
- Manage customers
- Manage suppliers
- Manage expenses
- View profit
- Configure units
- Configure low-stock thresholds

### Manager

Can:

- Record sales
- Manage inventory
- Record purchases
- Manage customers
- Manage suppliers
- View operational reports

But cannot:

- Delete business
- Manage owners
- Change sensitive business settings

### Sales Staff

Can:

- Record sales
- Search products
- Scan barcodes
- View product prices
- Add customers
- Record payments

Cannot:

- View sensitive financial reports
- Delete products
- Modify historical transactions

Design permissions so additional roles can be added later.

---

# 8. PRODUCT MANAGEMENT

Products are the foundation of the system.

A product should support:

- Name
- SKU
- Barcode
- Category
- Brand
- Description
- Cost price
- Selling price
- Minimum selling price
- Stock quantity
- Reorder level
- Preferred supplier
- Active/inactive status
- Product image
- Created date
- Updated date

Example:

Product:

> Milo 500g

Category:

> Beverages

Barcode:

> 123456789

---

# 9. BARCODE SCANNING

Implement barcode scanning using the **mobile phone camera**.

Do NOT require dedicated barcode scanner hardware.

The user should be able to tap:

> Scan Barcode

The application opens the phone camera.

After scanning:

### If barcode exists:

Open the product immediately.

Example:

> Milo 500g  
> Current stock: 17  
> Selling price: ₦2,500

The user can then:

- Sell
- Add stock
- Edit product
- View history

### If barcode does NOT exist:

Display:

> "Product not found."

Then offer:

> Create Product

The scanned barcode should automatically populate the barcode field.

---

# 10. BARCODE USE DURING SALES

The fastest sales workflow should be:

Sales → Scan → Product → Quantity → Cart → Payment → Complete

Example:

User scans:

Milo

Then scans:

Peak Milk

Then scans:

Indomie

The system builds a cart:

Milo × 2
Peak × 3
Indomie × 5

The user can change quantities without rescanning.

The system calculates:

Subtotal
Discount
Total
Amount paid
Balance

Then completes the transaction.

---

# 11. CUSTOM UNITS

This is a VERY IMPORTANT feature.

Do NOT hard-code units such as:

- Piece
- Carton
- Bottle
- Pack
- Bag

Every business must be able to create its own units.

Examples:

- Piece
- Carton
- Crate
- Bag
- Sachet
- Bottle
- Pack
- Kilogram
- Gram
- Litre
- Millilitre
- Loaf
- Mudu
- Bucket
- Tub
- Roll
- Tin

The owner can create a custom unit:

> "Paint bucket"

or

> "Mudu"

or

> "Crate"

---

# 12. PRODUCT UNIT CONVERSION

Products may have multiple units.

Example:

### Coca-Cola

Base unit:

> Bottle

Alternative unit:

> Crate

Conversion:

> 1 Crate = 12 Bottles

Another example:

### Rice

Base unit:

> Kilogram

Alternative unit:

> Bag

Conversion:

> 1 Bag = 50 KG

Another:

### Eggs

Base unit:

> Piece

Alternative unit:

> Crate

Conversion:

> 1 Crate = 30 Pieces

The system must correctly convert stock between units.

If the store has:

> 2 crates + 5 bottles

and:

> 1 crate = 12 bottles

The system should understand that this represents:

> 29 bottles

However, the UI should still be able to display stock in a user-friendly form such as:

> 2 crates + 5 bottles

---

# 13. UNIT-SPECIFIC PRICING

A product can have different prices depending on the unit.

Example:

### Milo

Carton:

Cost = ₦80,000
Selling = ₦85,000

Pack:

Selling = ₦7,500

Sachet:

Selling = ₦500

The system must allow the owner to configure:

- Unit
- Cost price
- Selling price
- Conversion quantity

This is essential because provision stores frequently buy in bulk and sell in smaller quantities.

---

# 14. INVENTORY MODEL

Inventory should track stock movements rather than simply storing one editable quantity.

Create an inventory ledger.

Stock can change because of:

- Purchase
- Sale
- Sale cancellation
- Purchase return
- Customer return
- Damaged goods
- Expired goods
- Stock adjustment
- Opening stock
- Internal transfer in future

Every stock change should create a stock movement record.

Example:

```text
Product: Milo

Opening Stock: +20
Purchase: +10
Sale: -3
Damaged: -1
Sale: -2

Current Stock: 24
```

Never silently change inventory without recording why it changed.

---

# 15. PURCHASE MANAGEMENT

Allow users to record purchases from suppliers.

Purchase fields:

- Supplier
- Date
- Reference number
- Products
- Quantity
- Unit
- Cost price
- Discount
- Total
- Amount paid
- Outstanding amount

When a purchase is completed:

Inventory increases automatically.

Example:

Purchase:

10 cartons of Milo

Cost:

₦8,500/carton

Inventory increases by the appropriate base-unit quantity.

---

# 16. SALES MANAGEMENT

Sales should support:

- Walk-in customer
- Registered customer
- Multiple products
- Multiple units
- Discounts
- Partial payments
- Full payments
- Credit sales
- Payment methods

Payment methods:

- Cash
- Bank transfer
- POS
- Other

Do NOT process actual payments in this version.

The application should only record payment information.

---

# 17. CREDIT SALES / DEBTS

Allow customers to buy on credit.

Example:

Total:

₦25,000

Paid:

₦10,000

Outstanding:

₦15,000

Track:

- Customer
- Sale
- Amount owed
- Amount paid
- Outstanding balance
- Due date
- Payment history

The owner should be able to open:

> Customers → Debtors

and immediately see:

John — ₦45,000
Mary — ₦12,500
Peter — ₦8,000

Provide a customer detail page showing all transactions and payments.

---

# 18. CUSTOMER PAYMENTS

When a debtor pays:

Record:

- Customer
- Amount
- Payment method
- Date
- Reference
- Notes

Automatically reduce outstanding debt.

Never modify the original sale to fake a payment.

Payments must have their own records.

---

# 19. EXPENSE MANAGEMENT

Allow users to record business expenses.

Examples:

- Electricity
- Transport
- Rent
- Staff salary
- Fuel
- Packaging
- Repairs
- Internet
- Other

Expense fields:

- Category
- Amount
- Date
- Description
- Payment method
- Staff/user who recorded it

---

# 20. PROFIT CALCULATION

The system must distinguish between:

### Revenue

Total value of completed sales.

### Cost of Goods Sold (COGS)

The cost associated with products sold.

### Gross Profit

Revenue - COGS

### Operating Expenses

Expenses such as:

- Transport
- Electricity
- Rent
- Salary
- etc.

### Net Profit

Gross Profit - Operating Expenses

Do not calculate profit simply as:

> Selling price - current product cost

because product costs can change.

Use appropriate cost tracking, preferably **weighted average cost** for V1.

Example:

Purchase 1:

10 units × ₦1,000

Purchase 2:

10 units × ₦1,200

Weighted average cost:

₦1,100

A sale of 5 units therefore records approximately:

COGS = ₦5,500

and:

Selling price - ₦5,500 = Gross Profit.

The accounting logic should be centralized in the backend.

---

# 21. DASHBOARD

The dashboard should immediately answer:

### How is my business doing?

Show:

**Today's Sales**

₦86,500

**Today's Gross Profit**

₦21,400

**Transactions**

47

**Expenses**

₦5,500

**Outstanding Customer Debt**

₦128,000

**Low Stock**

6 products

**Stock Value**

₦2,450,000

Provide filters:

- Today
- Yesterday
- This week
- This month
- Custom range

---

# 22. SALES ANALYTICS

Provide:

### Top-selling products

Example:

1. Milo
2. Indomie
3. Peak Milk
4. Bread
5. Coca-Cola

### Sales by category

### Sales by day

### Sales by product

### Sales by staff

### Sales by payment method

### Average transaction value

---

# 23. INVENTORY ANALYTICS

Provide:

### Current stock

### Low-stock products

### Out-of-stock products

### Stock value

### Fast-moving products

### Slow-moving products

### Stock movement history

### Inventory adjustment history

The owner should be able to answer:

> "What products are selling fastest?"

and:

> "What products are sitting on my shelf?"

---

# 24. LOW STOCK / REORDER LEVEL

Every product should have a configurable:

> Reorder Level

Example:

Milo:

Reorder level = 10 cartons

If stock falls to:

10 or below

display:

> ⚠️ Low Stock

If stock reaches zero:

> 🔴 Out of Stock

For V1, use a simple threshold.

Design the database so future versions can calculate intelligent reorder recommendations.

---

# 25. SUPPLIER MANAGEMENT

Supplier fields:

- Name
- Phone
- Email
- Address
- Notes
- Products supplied

Track:

- Purchases
- Amount paid
- Amount owed
- Purchase history

Future versions can allow supplier comparison.

---

# 26. STOCK ADJUSTMENTS

Allow authorized users to correct inventory.

Reasons:

- Damaged
- Expired
- Missing
- Physical count adjustment
- Opening stock
- Other

Example:

> Milo

System stock:

20

Physical stock:

18

Adjustment:

-2

Reason:

> Damaged

This must create an audit record.

---

# 27. REPORTS

Provide exportable reports.

Reports:

### Sales Report

- Date
- Product
- Quantity
- Selling price
- Revenue
- COGS
- Gross profit

### Inventory Report

- Product
- Current stock
- Unit
- Cost
- Stock value

### Profit & Loss

Revenue
- COGS
= Gross Profit

Gross Profit
- Expenses
= Net Profit

### Debt Report

Customer
- Total credit
- Paid
- Outstanding

### Purchase Report

Supplier
- Purchases
- Amount paid
- Outstanding

Allow export to:

- PDF
- Excel/CSV

---

# 28. TRANSACTION HISTORY

Create a unified transaction/history view.

Users should be able to see:

- Sales
- Purchases
- Expenses
- Customer payments
- Supplier payments
- Stock adjustments

Every record should show:

- Date
- User
- Amount
- Status
- Reference

---

# 29. REVERSALS AND EDITING

Do not allow destructive editing of completed financial transactions.

Instead of:

> Delete sale

use:

> Reverse sale

The reversal should create a compensating transaction and restore inventory appropriately.

Maintain an audit trail.

This is especially important because the future AI agent will rely on trustworthy business data.

---

# 30. SEARCH

Global product search should support:

- Product name
- SKU
- Barcode
- Category
- Brand

Search must be fast.

The sales screen should have:

### Search

and:

### Scan Barcode

side-by-side.

---

# 31. MOBILE UX

Design for a shop owner standing behind a counter.

The primary navigation should be simple.

Suggested bottom navigation:

**Home**

**Sell**

**Inventory**

**More**

The most important button should be:

> **Sell**

The sales workflow must require minimal taps.

---

# 32. QUICK ACTIONS

Dashboard should contain:

+ Sell

+ Scan Product

+ Add Stock

+ Add Expense

+ Add Customer

+ Add Supplier

---

# 33. PRODUCT CREATION UX

Creating a product should be simple.

Step 1:

Product name

Step 2:

Barcode

Step 3:

Category

Step 4:

Units

Step 5:

Cost price

Step 6:

Selling price

Step 7:

Opening stock

Do not overwhelm the user with 20 fields.

Advanced information should be optional.

---

# 34. BARCODE-FIRST PRODUCT CREATION

When creating a product:

User taps:

> Scan Barcode

Camera opens.

Barcode is scanned.

The application checks whether the barcode already exists.

If it doesn't:

Continue product creation with the barcode automatically filled.

If it does:

Open the existing product.

Prevent duplicate barcode records within the same business.

---

# 35. DATA MODEL

Design a clean relational model.

Suggested entities:

```text
Business
User
Role
Category
Unit
Product
ProductUnit
Supplier
Customer

Inventory
InventoryMovement

Purchase
PurchaseItem

Sale
SaleItem
SalePayment

CustomerDebt
CustomerPayment

Expense
ExpenseCategory

StockAdjustment

AuditLog
SyncRecord
```

Use proper foreign keys, indexes and constraints.

Important indexes:

- business_id
- barcode
- product name
- created_at
- transaction date
- supplier
- customer

Composite indexes should be used where appropriate for multi-tenant queries.

---

# 36. PRODUCT / UNIT MODEL

A product should have a base unit and optional alternative units.

Example:

```text
Product:
Milo

Base Unit:
Sachet

Product Units:

Sachet
1 Sachet = 1 Base Unit
Selling Price = ₦500

Pack
1 Pack = 10 Sachets
Selling Price = ₦4,800

Carton
1 Carton = 100 Sachets
Selling Price = ₦45,000
```

The system should use the base unit internally for inventory calculations.

Users can transact using any configured unit.

---

# 37. IMPORTANT INVENTORY PRINCIPLE

Never store:

```text
stock = 10 cartons
```

without understanding what that means.

Store inventory using a normalized/base unit.

Example:

```text
Base Unit = Piece

1 Carton = 12 Pieces

Current Stock = 36 Pieces
```

Display:

> 3 cartons

when appropriate.

This prevents calculation errors when users sell mixed units.

---

# 38. API DESIGN

Build REST APIs with clean separation of concerns.

Example endpoints:

```text
/auth/
/business/
/products/
/categories/
/units/
/inventory/
/inventory/movements/
/sales/
/purchases/
/customers/
/suppliers/
/expenses/
/reports/
/dashboard/
/sync/
```

Use serializers, validation and service-layer business logic.

Do not put complex accounting logic directly inside views.

---

# 39. BACKEND BUSINESS SERVICES

Create dedicated services such as:

```text
InventoryService
SalesService
PurchaseService
ProfitService
DebtService
ReportService
SyncService
BarcodeService
```

Example:

```text
SalesService.complete_sale()
```

should:

1. Validate products
2. Validate stock
3. Calculate prices
4. Calculate COGS
5. Create sale
6. Create sale items
7. Create payment records
8. Create inventory movements
9. Update stock
10. Commit transaction

Use database transactions to guarantee consistency.

---

# 40. OFFLINE SYNC ARCHITECTURE

Every locally created transaction must have a client-generated UUID.

Example:

```text
client_transaction_id
```

When synchronized, the backend must recognize duplicate requests.

If the same transaction is uploaded twice:

> Do NOT create two sales.

Return the existing transaction.

Use idempotency.

---

# 41. SECURITY

Implement:

- JWT authentication
- Refresh tokens
- Role-based permissions
- Tenant isolation
- Secure password handling
- API validation
- Rate limiting where appropriate
- Audit logs

Never trust business_id supplied by the client.

Determine the user's business from authenticated permissions.

---

# 42. ERROR HANDLING

The app must provide friendly errors.

Bad:

> HTTP 400

Good:

> "You don't have enough Milo in stock to complete this sale."

Bad:

> Network Error

Good:

> "You're offline. The sale has been saved and will sync automatically when you're back online."

---

# 43. UI DESIGN

The interface should look like a modern professional business application.

Avoid:

- Generic admin-dashboard appearance
- Excessive gradients
- Excessive animations
- Huge cards everywhere
- "AI-looking" interfaces
- Neon colors
- Cryptocurrency/web3 aesthetics

Use:

- Clean typography
- Strong hierarchy
- Compact data tables/lists
- Clear status indicators
- Bottom navigation on mobile
- Large touch targets
- Professional financial dashboards
- Consistent spacing
- Simple charts

The application should feel trustworthy because it manages people's money and stock.

---

# 44. NIGERIAN CONTEXT

Use:

- Nigerian Naira ₦
- Nigerian date/number formatting
- Nigerian phone number formats
- Cash
- Bank Transfer
- POS

Do not hard-code assumptions that prevent other African markets from being supported later.

Currency should belong to the business configuration.

---

# 45. DASHBOARD EXAMPLE

The dashboard could look conceptually like:

```text
Good morning, Michael

Today's overview

Sales
₦86,500

Gross Profit
₦21,400

Expenses
₦5,500

Transactions
47

----------------------------

Stock Alerts

🔴 Indomie Chicken
   Out of stock

🟡 Milo 500g
   7 remaining

🟡 Peak Milk
   9 remaining

----------------------------

Quick Actions

[ Sell ]
[ Scan ]
[ Add Stock ]
[ Expense ]

----------------------------

Sales Performance

[Chart]

----------------------------

Top Products

1. Milo       ₦24,500
2. Indomie    ₦18,200
3. Peak       ₦12,400
```

---

# 46. V1 SCOPE

Build these features first:

### Authentication

- Register
- Login
- Business creation

### Product

- Create
- Edit
- Delete/archive
- Search
- Barcode

### Units

- Create custom units
- Product-specific units
- Unit conversion
- Unit-specific pricing

### Inventory

- Opening stock
- Purchases
- Sales
- Stock movements
- Adjustments
- Low-stock levels

### Sales

- Search
- Barcode scan
- Cart
- Multiple units
- Discounts
- Payment
- Credit sales

### Purchases

- Supplier
- Purchase records
- Stock updates

### Customers

- Customer records
- Debt
- Payments

### Expenses

- Expense records
- Categories

### Dashboard

- Revenue
- COGS
- Gross profit
- Expenses
- Net profit
- Stock
- Debts

### Reports

- Sales
- Inventory
- Profit
- Debts
- Purchases

### Offline

- Local transactions
- Sync
- Sync status

---

# 47. DO NOT BUILD IN V1

Do NOT implement:

- AI agent
- AI chatbot
- Voice sales entry
- WhatsApp integration
- Supplier marketplace
- Payment gateway
- Online payments
- Delivery management
- Accounting integrations
- Payroll
- Complex tax calculations
- Multi-branch inventory transfer
- Predictive AI
- Computer vision
- Automated purchasing

These can be future modules.

The database/API architecture should, however, make them possible later.

---

# 48. FUTURE AI AGENT REQUIREMENT

Even though AI is NOT being built now, design the backend so an AI agent can eventually interact with the system through controlled tools.

Future tools might include:

```text
get_sales_summary()
get_inventory()
get_low_stock_products()
get_product_sales_history()
get_profit_summary()
get_customer_debts()
get_supplier_balances()
create_purchase_order()
create_expense()
record_sale()
send_customer_reminder()
```

The AI should eventually interact with these services through authenticated APIs.

Therefore:

**Do not couple the business logic to the UI.**

All important operations should be available through clean backend services.

---

# 49. TESTING REQUIREMENTS

Write tests for critical business logic.

At minimum test:

### Inventory

- Purchase increases stock
- Sale decreases stock
- Cannot sell unavailable stock
- Stock adjustment works
- Unit conversion works

### Sales

- Correct totals
- Discounts
- Multiple products
- Multiple units
- Partial payment
- Credit sale

### Profit

- Correct COGS
- Correct gross profit
- Correct expenses
- Correct net profit

### Multi-tenancy

- Business A cannot access Business B's products
- Business A cannot access Business B's sales
- Business A cannot access Business B's customers

### Offline sync

- Duplicate transactions are not created
- Failed sync can retry
- Successful sync changes status
- Local IDs map correctly to server IDs

---

# 50. DEVELOPMENT APPROACH

Do not try to build every feature at once.

Build in this order:

## Phase 1

Project architecture

Authentication

Business/tenant setup

Database models

API foundation

---

## Phase 2

Products

Categories

Units

Product units

Barcode scanning

---

## Phase 3

Inventory

Purchases

Inventory movements

Stock calculations

---

## Phase 4

Sales

Barcode-based selling

Cart

Payments

Credit sales

---

## Phase 5

Customers

Suppliers

Expenses

---

## Phase 6

Dashboard

Profit calculations

Reports

Analytics

---

## Phase 7

Offline-first architecture

Local database

Sync queue

Conflict handling

---

## Phase 8

Testing

Performance

Security

UX refinement

---

# 51. MOST IMPORTANT UX PRINCIPLE

The user should not feel like they are "doing accounting."

They should feel like they are simply **running their shop**.

For example:

Instead of:

> Create Inventory Transaction

say:

> Add Stock

Instead of:

> Create Sales Transaction

say:

> Sell

Instead of:

> Create Inventory Adjustment

say:

> Adjust Stock

Instead of:

> Accounts Receivable

say:

> Customers Owing

Instead of:

> COGS

show:

> Cost of Goods

Technical accounting concepts can exist underneath the system without being exposed unnecessarily.

---

# 52. FINAL PRODUCT VISION

The V1 product should be a reliable provision-store management system.

The long-term vision is much larger:

```text
                  AI Store Manager
                         │
          ┌──────────────┼──────────────┐
          │              │              │
       Inventory       Sales          Finance
          │              │              │
          └──────────────┼──────────────┘
                         │
                  Business Data
                         │
              ┌──────────┴──────────┐
              │                     │
           WhatsApp              Mobile
              │                     │
              └──────────┬──────────┘
                         │
                    Future AI Agent
```

But **V1 must first create trustworthy, structured business data.**

The goal is to build the foundation on which the future AI Store Manager can operate.

---

# 53. SUCCESS CRITERIA

At the end of V1, a real provision-store owner should be able to:

1. Create their business
2. Define their own units
3. Add products
4. Scan product barcodes with their phone
5. Record opening stock
6. Receive new stock
7. Sell products by scanning or searching
8. Sell products using different units
9. Automatically update inventory
10. Record customer credit
11. Record customer repayments
12. Record expenses
13. See revenue
14. See cost of goods
15. See gross profit
16. See net profit
17. See low-stock products
18. See inventory value
19. View sales history
20. View purchase history
21. Generate reports
22. Continue operating without internet
23. Synchronize when internet returns

The application should be reliable enough that the owner can use it as the **primary digital record of their shop**.

Build the system with production-quality architecture rather than a prototype with hard-coded demo data.