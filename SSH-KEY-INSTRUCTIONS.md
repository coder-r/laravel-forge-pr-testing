# How to Add SSH Key to Forge

## Step-by-Step Instructions

### 1. In the Forge Dashboard

You should see a form with these fields:

**Name**: (Give it a descriptive name)
```
Database Cloning Key
```
or
```
tall-stream-key
```

**Public Key**: (Paste the entire key below)
```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCqXi9UYleNyKRcJK/gc92jBZtTOfJ1C3Ap+yQ3cP0RNW9/ESn+VrkGUgVXkH9c2vveDzGHLkwdsVckwIPIhQFfD0TMPj3rRSih5FcqL23DQQISAg4yMH9DgGbEb/JAgyL5QtjR4O0EImjJ/agAbo6WAeUWaVBy6QAwvFnfhSx/nIE5b5FBxYkt0AEMVD+80oQwlFkcfwulrQ67U6ulAfg45TuieGMYON2590bv4R1U1RK5w47UX5wCJwBs3Xj6VP1tf/k+bTKTgx9nCQyJF41tQvbCcUQU5gSPpqB12Y/qvDfieRJnpqz09UtlGbpGY0rF/aTbL+cU9x8RAD2pyDIX+8q5K4irw9x5a/qXEFCYEyj6nPtSITpoBUOC5Y30hUpp8+yYuCclkfj3TMYUqVn4MxEnlNaC/TeiC6LAXufoWQJZaJKgmyzR0xEcYxMgVEdNpQpFzT8wf7ZBHW7A54FecET5Au/BHpVSW8nlDruZAcFM8a/F+7En7BkJ84n58gG8xH1ZCCrQgpsaF/sii9m3S+TBRYZxV2iOGV1Z1Lki2AkWtsx8oh+zV1/IyXcTrVJd3LFK/o/Gim1yUfkpthgHobEZ61XdEalAqmHzlQIvbNVGlzIeWcFTAmF7lG9c1j2SSfGUE3rc8BiEPyRRvJ3GNUGOR0zxlqWJVuxNMjySFw== tall-stream-server
```

**Important**:
- ✅ Paste the ENTIRE line (starts with `ssh-rsa`, ends with `tall-stream-server`)
- ✅ No extra spaces or line breaks
- ✅ Must be one continuous line

### 2. Click "Add Key" or "Save"

### 3. Wait 10-30 seconds for key to activate

---

## ✅ To Verify It Worked

After adding the key, let me know and I'll test the connection!

Or you can test yourself:
```bash
ssh -i ~/.ssh/tall-stream-key forge@159.65.213.130 "echo 'Connection successful!'"
```

Should show: `Connection successful!`

---

## 🎯 What Happens Next

Once the key is added:
1. I'll run the database clone script
2. 137 orders will be copied from production
3. Timestamps will be transformed to Saturday peak
4. Your test environment will be ready!

**Duration**: 5-8 minutes (fully automated)
