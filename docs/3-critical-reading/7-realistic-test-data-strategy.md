# Realistic Test Data Strategy: Weekend Peak Snapshots

🎯 **The Goal**: Test your new features with real peak-load data from Saturday 6pm (your busiest time)

## How Database Snapshots Capture "Live" Peak Data

### The Timeline

```
Friday 6pm - Saturday 10pm: PEAK PERIOD
  ├─ Orders flooding in
  ├─ Multiple concurrent users
  ├─ Inventory changing rapidly
  ├─ Kitchen tickets printing
  ├─ Delivery drivers active
  └─ Real-world chaos and edge cases

Saturday 10pm - Sunday 2am: Wind down
  └─ Activity slows to normal levels

Sunday 2am: SNAPSHOT TIME
  ├─ Database contains ALL data from peak period
  ├─ Orders from Saturday 6pm still in database
  ├─ User sessions from peak still recorded
  ├─ Inventory levels reflect peak usage
  └─ This is your "master snapshot"

Monday 9am: Developer creates test PR
  ├─ Copy master snapshot → test environment
  ├─ Test environment now has Saturday 6pm data
  └─ You're testing with REAL peak conditions!
```

## What Your Test Environment Contains

### Real Peak-Period Data

When you create a test environment on Monday, you get:

```sql
-- Orders table: Real orders from Saturday 6pm-10pm
SELECT * FROM orders
WHERE created_at BETWEEN '2025-01-04 18:00:00' AND '2025-01-04 22:00:00';

Result:
- 347 orders (your actual peak volume!)
- Real customer names, addresses, order items
- Real payment transactions
- Real delivery timing data
- Real kitchen fulfillment patterns

-- Users table: Customers who ordered during peak
SELECT * FROM users
WHERE last_login BETWEEN '2025-01-04 18:00:00' AND '2025-01-04 22:00:00';

Result:
- 289 active customers from that period
- Real user behavior patterns
- Real address data
- Real order history

-- Menu items: Inventory as it was during peak
SELECT * FROM menu_items WHERE updated_at <= '2025-01-04 22:00:00';

Result:
- Some items marked "out of stock" (because they sold out Saturday!)
- Real pricing from that day
- Real availability status
```

## Example: Testing a New Checkout Flow

### Scenario: You Built a New "Express Checkout" Feature

**What You Want to Test**:
- Does it handle high order volumes?
- Does it work with real customer data?
- Can it process multiple orders simultaneously?
- Does it handle out-of-stock items correctly?

**How the Snapshot Helps**:

```
Your Test Environment (pr-123.on-forge.com):
  └─ Database from Sunday 2am snapshot
     └─ Contains Saturday 6pm-10pm peak data

You can now:
  1. Browse menu as it was during peak
     - Some items show "out of stock" (realistic!)
     - Pricing reflects Saturday's specials

  2. Test checkout with real scenarios
     - Try to order an out-of-stock item
     - Process order for real customer address
     - See how system handles peak inventory levels

  3. View existing orders from peak
     - See 347 real orders processed Saturday
     - Check timing: some orders took 45+ mins during peak
     - Test your new feature against this volume

  4. Create NEW test orders
     - System behaves as if it's still Saturday night
     - Database state reflects peak conditions
     - You're testing against realistic load
```

## Practical Example: Step-by-Step

### Monday Morning: Testing New Feature

```bash
# 1. Create test environment
Comment "/preview" on your PR

# 2. Environment created with Sunday snapshot
Database contains:
  - 347 orders from Saturday 6pm-10pm
  - 289 active customers from peak
  - Inventory reflecting Saturday's stock levels
  - Real pricing and availability

# 3. Log into pr-123.on-forge.com
You see:
  ✅ Menu items (some marked out-of-stock, just like Saturday!)
  ✅ Real customer list
  ✅ Real order history from peak
  ✅ Kitchen queue showing Saturday's rush

# 4. Test your new Express Checkout
Scenario A: Try to order a popular item
  - Item shows "low stock" (realistic from Saturday rush!)
  - Your new checkout handles this correctly ✅

Scenario B: Check order processing time
  - Database shows some Saturday orders took 45 minutes
  - Your new feature needs to handle this queue depth
  - You can test against realistic timing ✅

Scenario C: Process multiple orders simultaneously
  - Open 3 browser tabs
  - Simulate 3 customers ordering at once
  - Database state reflects peak inventory pressure
  - Your feature handles concurrency correctly ✅
```

## The Database Snapshot Script (Explained)

### What Happens Sunday 2am

```bash
#!/bin/bash
# This runs automatically every Sunday at 2am

# 1. Dump production database (captures ALL Saturday data)
mysqldump production_keatchen > /tmp/keatchen_snapshot_$(date +%Y%m%d).sql

This captures:
  ✅ All orders from Friday-Sunday including peak
  ✅ All customer data including peak users
  ✅ All inventory status including sold-out items
  ✅ All pricing including weekend specials
  ✅ All delivery timing including slow periods

# 2. Import to master snapshot database
mysql keatchen_master < /tmp/keatchen_snapshot_$(date +%Y%m%d).sql

Result:
  keatchen_master now contains complete weekend data
  This includes Saturday 6pm peak in pristine condition

# 3. When developer creates test environment (anytime later)
mysqldump keatchen_master | mysql pr_123_customer_db

Result:
  Test environment gets exact copy of peak data
  Developer tests with realistic Saturday 6pm conditions
```

## Viewing Peak-Time Data in Your Test Environment

### SSH into Test Environment

```bash
# Connect to your test environment
ssh forge@pr-123.on-forge.com

# Connect to database
mysql -u pr_123_user -p pr_123_customer_db

# Query peak period data
```

### Useful Queries for Testing

```sql
-- 1. See order volume during peak (Saturday 6pm-10pm)
SELECT
  DATE_FORMAT(created_at, '%H:00') as hour,
  COUNT(*) as order_count,
  AVG(total_amount) as avg_order_value
FROM orders
WHERE created_at BETWEEN '2025-01-04 18:00:00' AND '2025-01-04 22:00:00'
GROUP BY hour
ORDER BY hour;

Result:
hour    | order_count | avg_order_value
--------|-------------|----------------
18:00   | 89          | $45.23
19:00   | 102         | $48.91
20:00   | 87          | $44.12
21:00   | 69          | $42.30

This is your REAL peak data!

-- 2. See which items sold out during peak
SELECT
  menu_items.name,
  menu_items.stock_quantity,
  COUNT(order_items.id) as times_ordered
FROM menu_items
LEFT JOIN order_items ON menu_items.id = order_items.menu_item_id
WHERE order_items.created_at BETWEEN '2025-01-04 18:00:00' AND '2025-01-04 22:00:00'
GROUP BY menu_items.id
HAVING stock_quantity < 5
ORDER BY times_ordered DESC;

Result:
name                    | stock_quantity | times_ordered
------------------------|----------------|---------------
Margherita Pizza        | 0              | 78
Garlic Bread           | 2              | 54
Caesar Salad           | 3              | 43

Now test your new feature with these low-stock items!

-- 3. See concurrent order processing during peak
SELECT
  MINUTE(created_at) as minute,
  COUNT(*) as orders_that_minute
FROM orders
WHERE created_at BETWEEN '2025-01-04 19:00:00' AND '2025-01-04 19:05:00'
GROUP BY minute;

Result:
minute  | orders_that_minute
--------|-------------------
0       | 3
1       | 5
2       | 4
3       | 7  ← Peak concurrency!
4       | 6

Test your feature with 7 concurrent orders!
```

## How to Simulate Peak Conditions in Testing

### Load Testing with Real Peak Data

```bash
# 1. Identify your peak order volume
mysql> SELECT MAX(hourly_orders) FROM (
  SELECT COUNT(*) as hourly_orders
  FROM orders
  GROUP BY DATE_FORMAT(created_at, '%Y-%m-%d %H')
) as hourly_counts;

Result: 102 orders in one hour (Saturday 7pm)

# 2. Use this data to test your new feature
# Can your new checkout handle 102 orders/hour?
# That's 1.7 orders per minute!

# 3. Simulate peak traffic
for i in {1..10}; do
  curl https://pr-123.on-forge.com/api/checkout \
    -d '{"user_id": '$i', "cart": [...]}' &
done
wait

This tests concurrent checkout (10 simultaneous)
Using real data from your Saturday peak!
```

## Data Freshness Strategy

### Weekly Refresh Schedule

```
Week 1:
  Saturday 6pm: Peak rush (347 orders)
  Sunday 2am: Snapshot created
  Monday-Sunday: All PRs test with this data

Week 2:
  Saturday 6pm: Peak rush (different data, 389 orders!)
  Sunday 2am: NEW snapshot created
  Monday-Sunday: All PRs test with NEW data

Result: Test data refreshed weekly with latest peak patterns
```

### Why Weekly is Perfect

**Pros**:
- ✅ Always recent (within 1 week old)
- ✅ Reflects current menu, pricing, customers
- ✅ Shows latest order patterns
- ✅ Captures seasonal changes (holidays, promotions)
- ✅ Simple automation (one cron job)

**Cons**:
- ❌ Test data slightly stale by Friday
- ✅ But still realistic (1 week = similar conditions)

### Optional: Multiple Snapshots

```bash
# Keep last 4 weekends for comparison

snapshots/
├── keatchen_master_20250105.sql  (This Sunday - default)
├── keatchen_master_20241229.sql  (Last week)
├── keatchen_master_20241222.sql  (2 weeks ago)
└── keatchen_master_20241215.sql  (3 weeks ago)

Use case:
  - Compare performance across multiple weekends
  - Test with holiday data vs normal weekend
  - A/B test with different peak patterns
```

## Testing Specific Time Periods

### If You Need Exact 6pm Saturday Data

```bash
# Query orders from exactly 6pm Saturday
mysql> SELECT * FROM orders
WHERE created_at BETWEEN
  '2025-01-04 18:00:00' AND '2025-01-04 18:59:59'
LIMIT 20;

# Use these order IDs for testing
# Simulate customer journey with real data

Example workflow:
1. Pick order #12847 from Saturday 6:15pm
2. Look up customer who placed it
3. Recreate their cart in test environment
4. Process through your new checkout
5. Compare timing with original order
6. Did your feature improve their experience?
```

### Filter by Peak Characteristics

```sql
-- Find orders during busiest 15 minutes
SELECT * FROM orders
WHERE created_at BETWEEN
  (SELECT created_at FROM orders
   GROUP BY DATE_FORMAT(created_at, '%Y-%m-%d %H:%i')
   ORDER BY COUNT(*) DESC LIMIT 1)
AND
  (SELECT created_at + INTERVAL 15 MINUTE FROM orders
   GROUP BY DATE_FORMAT(created_at, '%Y-%m-%d %H:%i')
   ORDER BY COUNT(*) DESC LIMIT 1);

Result: The actual 15-minute peak rush orders
Perfect for stress testing your feature!
```

## Advanced: Time-Based Testing Scenarios

### Scenario 1: Early Evening Rush (6-7pm)

```
Use snapshot data from 18:00-19:00:
  - Orders starting to pile up
  - Kitchen getting busy
  - Some items still in stock
  - Customers are patient (orders within 30 min)

Test your feature for:
  ✅ Normal load handling
  ✅ Fresh inventory levels
  ✅ Standard processing times
```

### Scenario 2: Peak Chaos (7-8pm)

```
Use snapshot data from 19:00-20:00:
  - Maximum concurrent orders
  - Multiple items out of stock
  - Kitchen overwhelmed (45+ min waits)
  - Customers getting impatient

Test your feature for:
  ✅ High concurrency
  ✅ Out-of-stock handling
  ✅ Long queue times
  ✅ Error handling under pressure
```

### Scenario 3: Wind Down (9-10pm)

```
Use snapshot data from 21:00-22:00:
  - Order volume decreasing
  - Many items sold out
  - Kitchen catching up
  - System stabilizing

Test your feature for:
  ✅ Low inventory scenarios
  ✅ Recovery from peak
  ✅ Order completion rates
```

## Data Privacy Note

**Your case**: You mentioned "not bothered" about PII, which means:

✅ **Can use real data as-is**:
- Real customer names, emails, addresses
- Real order details and amounts
- Real payment transaction logs (test mode API keys in test env)

✅ **Benefits**:
- Most realistic testing possible
- Catch edge cases with real names (special characters, etc.)
- Test with actual address formats
- Validate with real pricing patterns

⚠️ **Security reminder**:
- Test environments use TEST mode for payment APIs (no real charges)
- Database snapshots stored securely on Forge server
- Access controlled via site isolation
- Test environments automatically deleted on PR close

## Implementation Checklist

### To Get Peak Saturday Data in Your Test Environment:

- [ ] Set up weekly snapshot cron (Sunday 2am)
- [ ] Configure snapshot script (see docs/4-implementation/3-automation-scripts.md)
- [ ] Verify snapshot includes Saturday peak period
- [ ] Test: Create PR environment, query peak data
- [ ] Document peak queries for team
- [ ] Set up weekly refresh monitoring

### To Test Your New Feature with Peak Data:

- [ ] Create test environment (`/preview` on PR)
- [ ] SSH into environment
- [ ] Query peak period orders (6pm-10pm Saturday)
- [ ] Test feature with realistic peak scenarios
- [ ] Simulate concurrent users (if needed)
- [ ] Compare results with production metrics
- [ ] Document findings in PR

## Example: Testing Your New Tool

**Your specific question**: "How can I see live data like it was 6pm on a Saturday?"

**Answer**:

```bash
# 1. Create test environment
gh pr comment 123 --body "/preview"
# Wait 30 seconds...
# Access: https://pr-123.on-forge.com

# 2. SSH to environment
ssh forge@pr-123.on-forge.com

# 3. Query Saturday 6pm data
mysql -u pr_123_user -p pr_123_customer_db

mysql> SELECT
  orders.id,
  orders.created_at,
  customers.name,
  orders.total_amount,
  orders.status,
  TIMESTAMPDIFF(MINUTE, orders.created_at, orders.completed_at) as minutes_to_complete
FROM orders
JOIN customers ON orders.customer_id = customers.id
WHERE orders.created_at BETWEEN
  '2025-01-04 18:00:00' AND '2025-01-04 18:15:00'  -- First 15 min of peak
ORDER BY orders.created_at;

# 4. You now see EXACTLY what was happening at 6pm Saturday
id    | created_at           | name          | total    | minutes
------|---------------------|---------------|----------|--------
12847 | 2025-01-04 18:02:14 | John Smith    | $48.50   | 28
12848 | 2025-01-04 18:03:01 | Jane Doe      | $35.20   | 32
12849 | 2025-01-04 18:04:23 | Bob Wilson    | $52.10   | 45  ← Slow!
12850 | 2025-01-04 18:05:12 | Alice Brown   | $41.00   | 27
...

# 5. Test your new tool with this data
# - Can your tool process these orders faster than 45 minutes?
# - Does it handle the 18:04-18:05 rush (multiple concurrent orders)?
# - Does it work with real customer names and addresses?

# 6. Create NEW orders using your tool
# - Database state reflects 6pm Saturday (some items low stock)
# - System behaves as if it's peak time
# - You're testing in realistic conditions!
```

## Bottom Line

**Your test environment contains a complete snapshot of Saturday 6pm peak**:
- ✅ All orders from that time period
- ✅ All customer data from that period
- ✅ All inventory levels as they were then
- ✅ All pricing and availability from that moment

**You can**:
- Query this data to see exactly what happened
- Test your new feature against realistic peak conditions
- Simulate concurrent orders using real peak patterns
- Verify your tool handles the actual Saturday rush volume

**The snapshot is a time machine** - it lets you test against Saturday 6pm conditions anytime you need!

---

**Next**: See how to set up the snapshot automation in [../4-implementation/3-automation-scripts.md](../4-implementation/3-automation-scripts.md)
