# Testing with Live Peak Data: Viewing Screens as They Were

🎯 **Your Question**: "How do I test the driver screen and see how it would look at 6pm on a Saturday?"

## The Challenge

When you load your test environment on Monday:

```
Database contains: Saturday 6pm orders
Current time: Monday 9am
Problem: Orders show as "3 days ago" 😕

Your driver screen shows:
  ❌ "No active orders" (because Saturday orders are "completed")
  ❌ Orders dated 3 days ago
  ❌ Not realistic for testing

You want to see:
  ✅ Driver screen AS IT WAS at Saturday 6pm
  ✅ Active orders in queue
  ✅ Kitchen tickets printing
  ✅ Real-time chaos and rush
```

## Solution: Three Approaches

### Approach 1: Timestamp Shifting (Recommended)

Make Saturday's data look "current" by updating timestamps:

```sql
-- Run this in your test environment database

-- 1. Calculate the time difference
SET @time_diff = TIMESTAMPDIFF(SECOND,
  '2025-01-04 18:00:00',  -- Saturday 6pm (snapshot time)
  NOW()                    -- Current time (Monday 9am)
);

-- 2. Shift all order timestamps forward
UPDATE orders
SET
  created_at = DATE_ADD(created_at, INTERVAL @time_diff SECOND),
  updated_at = DATE_ADD(updated_at, INTERVAL @time_diff SECOND),
  completed_at = CASE
    WHEN completed_at IS NULL THEN NULL
    ELSE DATE_ADD(completed_at, INTERVAL @time_diff SECOND)
  END
WHERE created_at BETWEEN
  '2025-01-04 18:00:00' AND '2025-01-04 22:00:00';

-- 3. Reset order status to "active" (simulate they're still being processed)
UPDATE orders
SET status = 'pending'
WHERE created_at BETWEEN
  DATE_SUB(NOW(), INTERVAL 2 HOUR) AND NOW()
  AND status IN ('completed', 'delivered');

-- Result: Orders now show as if they were placed in the last 2 hours!
```

**Now when you load the driver screen**:
- ✅ Shows 102 "active" orders (from Saturday 6pm hour)
- ✅ Timestamps show "5 minutes ago", "10 minutes ago", etc.
- ✅ Driver screen looks exactly like Saturday 6pm rush!

### Approach 2: Historical View (If Your App Supports It)

Add a date picker to your screens:

```php
// In your driver screen controller

public function index(Request $request)
{
    // Allow viewing historical data via date parameter
    $targetDate = $request->input('date', now());

    $orders = Order::whereBetween('created_at', [
        $targetDate->startOfHour(),
        $targetDate->endOfHour()
    ])->get();

    return view('driver.dashboard', [
        'orders' => $orders,
        'viewing_date' => $targetDate
    ]);
}
```

```blade
{{-- In your driver blade template --}}

<div class="historical-view-banner">
  @if($viewing_date != now())
    <div class="alert alert-info">
      📅 Viewing data from: {{ $viewing_date->format('l, F j, Y - g:i A') }}
      <a href="?date=">Return to current</a>
    </div>
  @endif
</div>

{{-- Then show orders as normal --}}
```

**Usage**:
```
https://pr-123.on-forge.com/driver?date=2025-01-04T18:00:00

Driver screen now shows:
✅ Orders from Saturday 6pm
✅ Clear banner showing "historical view"
✅ Can navigate different time periods
```

### Approach 3: Automated Peak Simulation Script

Create a script that sets up peak view automatically:

```bash
#!/bin/bash
# setup-peak-view.sh

echo "🔧 Setting up Saturday 6pm peak view..."

# 1. Shift timestamps to current time
mysql pr_123_customer_db << 'EOF'

-- Make Saturday 6pm look like "right now"
SET @peak_start = '2025-01-04 18:00:00';
SET @peak_end = '2025-01-04 22:00:00';
SET @time_shift = TIMESTAMPDIFF(SECOND, @peak_start, NOW());

-- Update orders
UPDATE orders SET
  created_at = DATE_ADD(created_at, INTERVAL @time_shift SECOND),
  updated_at = DATE_ADD(updated_at, INTERVAL @time_shift SECOND)
WHERE created_at BETWEEN @peak_start AND @peak_end;

-- Reset statuses to simulate active orders
UPDATE orders SET
  status = CASE
    WHEN TIMESTAMPDIFF(MINUTE, created_at, NOW()) < 15 THEN 'pending'
    WHEN TIMESTAMPDIFF(MINUTE, created_at, NOW()) < 30 THEN 'preparing'
    WHEN TIMESTAMPDIFF(MINUTE, created_at, NOW()) < 45 THEN 'ready'
    ELSE 'out_for_delivery'
  END
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 60 MINUTE);

EOF

echo "✅ Peak view ready! Orders now show as active with realistic timing."
echo "📱 Access driver screen to see Saturday 6pm rush!"
```

**Run on test environment**:
```bash
# SSH to test environment
ssh forge@pr-123.on-forge.com

# Run setup script
./setup-peak-view.sh

# Access driver screen
open https://pr-123.on-forge.com/driver
```

## Practical Example: Testing Driver Screen

### Step-by-Step Walkthrough

**Scenario**: Test new driver app feature during peak rush

#### Step 1: Create Test Environment

```bash
# Comment on your PR
/preview

# Wait 30 seconds...
# Environment created: pr-123.on-forge.com
```

#### Step 2: Prepare Peak Data View

```bash
# SSH to environment
ssh forge@pr-123.on-forge.com

# Connect to database
mysql -u pr_123_user -p pr_123_customer_db

# Run timestamp shift
SET @time_diff = TIMESTAMPDIFF(SECOND, '2025-01-04 18:00:00', NOW());

UPDATE orders
SET
  created_at = DATE_ADD(created_at, INTERVAL @time_diff SECOND),
  updated_at = DATE_ADD(updated_at, INTERVAL @time_diff SECOND)
WHERE DATE(created_at) = '2025-01-04'
  AND HOUR(created_at) BETWEEN 18 AND 22;

# Reset to active status
UPDATE orders
SET status = 'pending'
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 2 HOUR);

# Verify
SELECT
  COUNT(*) as active_orders,
  MIN(created_at) as oldest_order,
  MAX(created_at) as newest_order
FROM orders
WHERE status = 'pending';

Result:
active_orders: 102
oldest_order: 2025-01-07 07:15:23  (2 hours ago)
newest_order: 2025-01-07 09:12:41  (just now)
```

#### Step 3: Load Driver Screen

```bash
# Open driver app in browser
open https://pr-123.on-forge.com/driver/dashboard

# Or if testing mobile app, point it to:
API_URL=https://pr-123.on-forge.com/api
```

#### Step 4: See Peak Rush in Action!

**What you now see on driver screen**:

```
Driver Dashboard - Monday 9:15 AM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📦 Active Orders: 102

Pending Orders (waiting for driver):
  🍕 Order #12847 - 2 minutes ago
     John Smith - 123 Main St
     Total: $48.50

  🍕 Order #12848 - 3 minutes ago
     Jane Doe - 456 Oak Ave
     Total: $35.20

  🍕 Order #12849 - 5 minutes ago
     Bob Wilson - 789 Elm St
     Total: $52.10 ⚠️ HIGH VALUE

  ... (99 more orders)

Kitchen Queue: 47 orders
Ready for Pickup: 23 orders
Out for Delivery: 32 orders
```

**This is exactly how it looked Saturday 6pm!**
- ✅ Same order volume (102)
- ✅ Same customer names and addresses
- ✅ Same order amounts
- ✅ Same queue distribution
- ✅ Timestamps show "minutes ago" (not "days ago")

## Testing Different Peak Time Periods

### View Specific Rush Periods

```sql
-- Peak of rush (7pm Saturday - highest volume)
SET @view_time = '2025-01-04 19:00:00';
SET @time_diff = TIMESTAMPDIFF(SECOND, @view_time, NOW());

UPDATE orders
SET created_at = DATE_ADD(created_at, INTERVAL @time_diff SECOND)
WHERE created_at BETWEEN '2025-01-04 19:00:00' AND '2025-01-04 19:59:59';

-- Now driver screen shows 7pm rush (peak chaos!)

-- Later: View wind-down period (9pm)
SET @view_time = '2025-01-04 21:00:00';
-- Repeat timestamp shift...

-- Now driver screen shows 9pm (orders slowing down)
```

### Simulate Progressive Time

Make it feel like time is progressing:

```javascript
// In your test environment, add this to driver screen

<script>
// Simulate orders "aging" over time
setInterval(() => {
  // Update "X minutes ago" timestamps
  document.querySelectorAll('.order-timestamp').forEach(el => {
    let minutes = parseInt(el.dataset.minutes) + 1;
    el.dataset.minutes = minutes;
    el.textContent = `${minutes} minutes ago`;

    // Highlight orders getting old
    if (minutes > 30) {
      el.parentElement.classList.add('order-delayed');
    }
  });
}, 60000); // Every minute
</script>
```

## Advanced: Real-Time Simulation

### Replay Saturday 6pm in Real-Time

```bash
#!/bin/bash
# replay-peak-rush.sh

echo "🎬 Replaying Saturday 6pm rush in real-time..."

# Get all orders from peak hour in chronological order
mysql pr_123_customer_db << 'EOF' > /tmp/peak_orders.json
SELECT
  id,
  TIMESTAMPDIFF(SECOND, '2025-01-04 18:00:00', created_at) as seconds_offset
FROM orders
WHERE created_at BETWEEN '2025-01-04 18:00:00' AND '2025-01-04 19:00:00'
ORDER BY created_at;
EOF

# Replay orders at their original timing
start_time=$(date +%s)

while IFS=, read -r order_id seconds_offset; do
  current_time=$(date +%s)
  elapsed=$((current_time - start_time))

  # Wait until it's time for this order
  sleep_time=$((seconds_offset - elapsed))
  if [ $sleep_time -gt 0 ]; then
    sleep $sleep_time
  fi

  # "Create" the order (update timestamp to now)
  mysql pr_123_customer_db << EOF
    UPDATE orders
    SET created_at = NOW(), status = 'pending'
    WHERE id = $order_id;
EOF

  echo "📱 Order #$order_id placed (${elapsed}s into rush hour)"

done < /tmp/peak_orders.json

echo "✅ Rush hour replay complete!"
```

**Result**: Driver screen receives orders at the **exact same pace** as Saturday 6pm rush!

## Integration with Your New Feature

### Example: Testing New Driver Assignment Algorithm

```php
// Your new feature in test environment

public function assignDriver(Order $order)
{
    // Your new smart assignment logic
    $driver = $this->findOptimalDriver($order);

    // Log for comparison with Saturday actual
    Log::info('Driver Assignment Test', [
        'order_id' => $order->id,
        'original_saturday_driver' => $order->driver_id, // From snapshot
        'new_algorithm_driver' => $driver->id,
        'original_delivery_time' => $order->actual_delivery_minutes,
        'predicted_delivery_time' => $this->predictDeliveryTime($driver, $order)
    ]);

    return $driver;
}
```

**Test with peak data**:
1. Load driver screen with Saturday 6pm orders (102 active)
2. Your new algorithm assigns drivers
3. Compare with original Saturday assignments
4. See if your algorithm is faster/better!

## Viewing Different Screens with Peak Data

### Kitchen Screen

```sql
-- Show kitchen view during peak
SELECT
  order_items.id,
  orders.order_number,
  menu_items.name,
  order_items.quantity,
  order_items.special_instructions,
  TIMESTAMPDIFF(MINUTE, orders.created_at, NOW()) as wait_time
FROM order_items
JOIN orders ON order_items.order_id = orders.id
JOIN menu_items ON order_items.menu_item_id = menu_items.id
WHERE orders.status IN ('pending', 'preparing')
ORDER BY orders.created_at;

-- Load kitchen screen
open https://pr-123.on-forge.com/kitchen
```

### Customer App Screen

```sql
-- Show customer view for specific Saturday order
SELECT * FROM orders WHERE id = 12847;

-- Access as that customer
open https://pr-123.on-forge.com/track-order/12847
```

### Admin Dashboard

```sql
-- Show admin real-time metrics from peak
SELECT
  COUNT(*) as total_orders,
  COUNT(CASE WHEN status='pending' THEN 1 END) as pending,
  COUNT(CASE WHEN status='preparing' THEN 1 END) as preparing,
  AVG(total_amount) as avg_order_value,
  SUM(total_amount) as total_revenue
FROM orders
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR);

-- View dashboard
open https://pr-123.on-forge.com/admin/dashboard
```

## Automated Setup Script

### One-Command Peak View Setup

```bash
#!/bin/bash
# setup-saturday-peak.sh

cat << 'EOF' | mysql pr_123_customer_db

-- Step 1: Shift Saturday 6pm data to current time
SET @time_diff = TIMESTAMPDIFF(SECOND, '2025-01-04 18:00:00', NOW());

START TRANSACTION;

-- Update orders
UPDATE orders
SET
  created_at = DATE_ADD(created_at, INTERVAL @time_diff SECOND),
  updated_at = DATE_ADD(updated_at, INTERVAL @time_diff SECOND),
  completed_at = NULL,  -- Make them "active" again
  delivered_at = NULL
WHERE DATE(created_at) = '2025-01-04'
  AND HOUR(created_at) BETWEEN 18 AND 22;

-- Reset order statuses based on age
UPDATE orders
SET status = CASE
  WHEN TIMESTAMPDIFF(MINUTE, created_at, NOW()) < 5 THEN 'pending'
  WHEN TIMESTAMPDIFF(MINUTE, created_at, NOW()) < 15 THEN 'confirmed'
  WHEN TIMESTAMPDIFF(MINUTE, created_at, NOW()) < 30 THEN 'preparing'
  WHEN TIMESTAMPDIFF(MINUTE, created_at, NOW()) < 45 THEN 'ready'
  ELSE 'out_for_delivery'
END
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 4 HOUR);

-- Update related tables (order_items, deliveries, etc.)
UPDATE order_items oi
JOIN orders o ON oi.order_id = o.id
SET oi.created_at = o.created_at
WHERE o.created_at >= DATE_SUB(NOW(), INTERVAL 4 HOUR);

COMMIT;

-- Verify
SELECT
  status,
  COUNT(*) as count,
  MIN(TIMESTAMPDIFF(MINUTE, created_at, NOW())) as oldest_minutes,
  MAX(TIMESTAMPDIFF(MINUTE, created_at, NOW())) as newest_minutes
FROM orders
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 4 HOUR)
GROUP BY status;

EOF

echo "✅ Saturday 6pm peak view is ready!"
echo ""
echo "🚗 Driver Screen: https://pr-123.on-forge.com/driver"
echo "🍳 Kitchen Screen: https://pr-123.on-forge.com/kitchen"
echo "👤 Customer App: https://pr-123.on-forge.com"
echo "📊 Admin Dashboard: https://pr-123.on-forge.com/admin"
```

**Usage in GitHub Action** (Automated):

```yaml
# Add to your GitHub Action workflow

- name: Setup Saturday Peak View
  run: |
    ssh forge@pr-${{ github.event.issue.number }}.on-forge.com \
      'bash /home/forge/setup-saturday-peak.sh'

- name: Post Testing Instructions
  run: |
    gh pr comment ${{ github.event.issue.number }} --body "
    ## ✅ Environment Ready with Saturday 6pm Peak Data

    Your test environment is populated with real Saturday 6pm rush data!

    **Test Screens**:
    - 🚗 Driver: https://pr-${{ github.event.issue.number }}.on-forge.com/driver
    - 🍳 Kitchen: https://pr-${{ github.event.issue.number }}.on-forge.com/kitchen
    - 👤 Customer: https://pr-${{ github.event.issue.number }}.on-forge.com

    **What you'll see**:
    - 102 active orders from peak hour
    - Real customer names and addresses
    - Realistic order timing and queue depth
    - Orders showing as 'X minutes ago' (not days ago)

    Data is from last Saturday 6-10pm peak period.
    "
```

## Summary: Your Workflow

### To Test Driver Screen with Saturday 6pm Data:

```bash
# 1. Create test environment
/preview

# 2. SSH to environment
ssh forge@pr-123.on-forge.com

# 3. Run peak setup script
bash setup-saturday-peak.sh

# 4. Open driver screen
open https://pr-123.on-forge.com/driver

# 5. You now see:
✅ 102 active orders (Saturday 6pm volume)
✅ Orders showing "5 min ago", "10 min ago" (not "3 days ago")
✅ Real customer names and addresses
✅ Realistic queue depth and timing
✅ Exactly how driver screen looked Saturday 6pm!
```

### Test Your New Feature:
- Navigate driver screen with peak data
- Test assignment algorithm with 102 concurrent orders
- Check performance under realistic load
- Verify UI handles queue depth
- Compare results with Saturday actual metrics

**You're now testing in realistic Saturday 6pm conditions!** 🎉

---

**Next Steps**:
1. Add `setup-saturday-peak.sh` script to your automation
2. Document for your team how to view peak data
3. Test your driver screen improvements
4. Compare performance with Saturday actual data
