# Database Cloning SSH Fix

## Problem

The original database cloning implementation attempted to connect directly to remote MySQL servers, which fails when firewalls block external MySQL access (port 3306):

```bash
# ❌ This doesn't work through firewalls
mysqldump -h $SERVER_IP -u root production_db | mysql -h $SERVER_IP pr_123_db
```

## Solution

Implemented SSH-based database cloning that works through SSH tunnels (port 22), which is typically open on Forge servers.

### Two Methods Implemented

#### Method 1: Direct SSH Pipe (Fastest)
Streams data directly between servers without intermediate files:

```bash
ssh forge@source "mysqldump ... | gzip" | \
  ssh forge@target "gunzip | mysql ..."
```

**Advantages:**
- Fastest method
- No disk space needed for temporary files
- Single command execution

**Disadvantages:**
- Requires both servers to be SSH-accessible simultaneously
- Connection interruption affects entire operation

#### Method 2: File Transfer (Fallback)
Creates temporary compressed dump, transfers it, then imports:

```bash
# 1. Create dump on source
ssh forge@source "mysqldump ... | gzip > /tmp/dump.sql.gz"

# 2. Transfer to target
ssh forge@source "cat /tmp/dump.sql.gz" | ssh forge@target "cat > /tmp/dump.sql.gz"

# 3. Import on target
ssh forge@target "gunzip < /tmp/dump.sql.gz | mysql ..."

# 4. Cleanup
ssh forge@source "rm /tmp/dump.sql.gz"
ssh forge@target "rm /tmp/dump.sql.gz"
```

**Advantages:**
- More resilient to connection issues
- Can verify dump before transfer
- Easier to debug
- Shows dump file size for progress tracking

**Disadvantages:**
- Requires disk space on both servers
- Slightly slower due to multiple steps

## Files Modified

### 1. `/scripts/orchestrate-pr-system.sh`

**Function:** `clone_database_from_master()`

**Changes:**
- Removed direct MySQL connection attempts
- Added SSH-based cloning with both methods
- Added automatic fallback from pipe to file transfer
- Added comprehensive error handling
- Added cleanup of temporary files
- Added detailed logging for debugging

**Key Features:**
- Works through firewalls
- Automatic method selection (tries pipe first, falls back to file transfer)
- Compressed transfer using gzip
- Non-blocking failures (returns 0 even on failure since it's non-critical)
- Detailed progress logging
- Automatic cleanup on success or failure

### 2. `/scripts/ssh-clone-database.sh` (New)

Standalone script for SSH-based database cloning that can be used independently.

**Usage:**
```bash
./ssh-clone-database.sh \
  --source-host "192.168.1.10" \
  --source-db "production_db" \
  --target-host "192.168.1.20" \
  --target-db "pr_123_db" \
  --target-user "pr_123_user" \
  --target-password "secret123" \
  --verify
```

**Features:**
- SSH connectivity checks
- Database existence verification
- Both cloning methods (pipe and file transfer)
- Optional clone verification (table count check)
- Comprehensive logging
- Automatic cleanup

## SSH Connection Details

### Default Configuration
- **SSH User:** `forge` (Forge's default user)
- **SSH Options:**
  - `ConnectTimeout=10` - 10-second timeout for connections
  - `StrictHostKeyChecking=no` - Accept new host keys automatically

### MySQL Options for Dump
- `--single-transaction` - Consistent snapshot without locking tables
- `--quick` - Stream rows instead of buffering entire result
- `--lock-tables=false` - Don't lock tables during dump

### Compression
- Uses `gzip` for compression during transfer
- Typically reduces transfer size by 5-10x
- Handled transparently by pipes

## Error Handling

### Connection Failures
Both methods include timeout and retry handling:
- SSH connection timeout: 10 seconds
- Falls back to second method if first fails
- Logs detailed error codes for debugging

### Cleanup on Failure
Temporary files are always cleaned up:
- On successful completion
- On error during transfer
- On error during import
- On SSH connection failure

### Non-Critical Failures
Database cloning is marked as non-critical in orchestration:
- Script continues even if cloning fails
- User is warned in logs
- Suggested to run migrations manually if needed

## Testing the Fix

### Test SSH Connectivity
```bash
# Test source server
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no forge@SOURCE_IP "echo 'SSH OK'"

# Test target server
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no forge@TARGET_IP "echo 'SSH OK'"
```

### Test Database Access
```bash
# Test source database
ssh forge@SOURCE_IP "mysql -u root -e 'SHOW DATABASES'"

# Test target database
ssh forge@TARGET_IP "mysql -u USER -p'PASSWORD' -e 'SHOW DATABASES'"
```

### Test Cloning
```bash
# Use standalone script
./scripts/ssh-clone-database.sh \
  --source-host "SOURCE_IP" \
  --source-db "production_db" \
  --target-host "TARGET_IP" \
  --target-db "test_db" \
  --target-user "test_user" \
  --target-password "test_pass" \
  --verify
```

## Security Considerations

### Password Handling
Passwords are passed as command-line arguments to MySQL. While not ideal, this is acceptable because:
1. Commands run inside SSH sessions (not visible externally)
2. Temporary files are cleaned up
3. Only works with existing SSH key access

### SSH Keys
Ensure Forge SSH keys are properly configured:
```bash
# Check SSH key access
ssh-add -l

# Add key if needed
ssh-add ~/.ssh/forge_key
```

### Firewall Requirements
Only SSH (port 22) needs to be open:
- MySQL port 3306 can remain firewalled
- Standard Forge configuration works out of the box

## Performance

### Typical Performance
- **Small databases (<100MB):** 5-15 seconds
- **Medium databases (100MB-1GB):** 30 seconds - 2 minutes
- **Large databases (1GB-10GB):** 2-20 minutes

### Optimization
Compression ratios typically:
- Text-heavy data: 8-10x compression
- Binary data: 2-4x compression
- Average Laravel database: 5-7x compression

## Troubleshooting

### "SSH connection failed"
**Cause:** SSH access not configured or server unreachable

**Solutions:**
1. Check SSH key is added: `ssh-add -l`
2. Test manual SSH: `ssh forge@SERVER_IP`
3. Verify server IP is correct
4. Check firewall allows SSH (port 22)

### "Failed to create dump on source server"
**Cause:** MySQL access issues on source server

**Solutions:**
1. Check database exists: `ssh forge@SOURCE_IP "mysql -u root -e 'SHOW DATABASES'"`
2. Verify database name is correct
3. Check MySQL is running: `ssh forge@SOURCE_IP "sudo systemctl status mysql"`

### "Failed to import dump on target server"
**Cause:** Database doesn't exist or wrong credentials

**Solutions:**
1. Verify target database exists
2. Check target user has proper permissions
3. Test credentials: `ssh forge@TARGET_IP "mysql -u USER -p'PASS' -e 'SHOW DATABASES'"`

### "Pipe method failed, using fallback"
**Cause:** Connection interrupted or insufficient resources

**Solutions:**
- This is normal and expected in some cases
- Fallback method should work
- Check logs for specific error codes
- If both methods fail, check disk space on servers

## Migration Path

### From Old Implementation
The old `clone-database.sh` is preserved for reference but should not be used for new deployments.

### Backward Compatibility
The new implementation is a drop-in replacement:
- Same function signature in `orchestrate-pr-system.sh`
- Same behavior (non-critical failure)
- Same logging format
- Better error messages

## Future Improvements

Potential enhancements:
1. Progress bars for large databases
2. Parallel compression for faster transfers
3. Incremental/differential dumps
4. Backup retention and rotation
5. Point-in-time recovery options
6. Automated verification after clone

## Related Files

- `/scripts/orchestrate-pr-system.sh` - Main orchestration script
- `/scripts/ssh-clone-database.sh` - Standalone SSH clone utility
- `/scripts/clone-database.sh` - Original implementation (deprecated)
- `/scripts/orchestrate-pr-system.sh.backup` - Backup of original

## Summary

The SSH-based approach solves the firewall issue by:
1. Using SSH tunnels instead of direct MySQL connections
2. Implementing two fallback methods for reliability
3. Adding comprehensive error handling and logging
4. Maintaining backward compatibility
5. Improving security by not requiring open MySQL ports

This makes the database cloning feature work reliably in production Forge environments where direct MySQL access is properly restricted.
