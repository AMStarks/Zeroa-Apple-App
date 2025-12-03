# How to Fully Disable Screen Time Content Filtering

The `webfilterproxyd` process is still running, which means Screen Time Content Filtering may not be fully disabled. Follow these steps:

## Step 1: Disable Content & Privacy Restrictions

1. Open **System Settings** (or System Preferences on older macOS)
2. Click **Screen Time**
3. If you see your name/account, click on it
4. Click **Content & Privacy Restrictions**
5. **Turn OFF** the toggle at the top
6. If there's a password prompt, enter it

## Step 2: Check for Family Sharing Settings

If you're part of a Family Sharing group:
1. Go to **System Settings > Screen Time**
2. Check if there's a **Family** section
3. Look for any **Content & Privacy Restrictions** set by a family organizer
4. Ask the family organizer to disable it, or remove yourself from the family group

## Step 3: Restart the Mac

After disabling, **restart your Mac** to ensure the `webfilterproxyd` process stops:
1. Apple Menu > Restart
2. Or run: `sudo reboot` (requires password)

## Step 4: Verify It's Disabled

After restart, run:
```bash
ps aux | grep webfilterproxyd | grep -v grep
```

If nothing appears, it's disabled. If it still shows, the filtering is still active.

## Alternative: Disable via Terminal (Requires Admin Password)

If the GUI method doesn't work, you can try:

```bash
# This may require admin password
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.familycontrols.contentfilter.plist 2>/dev/null
sudo launchctl unload -w /System/Library/LaunchAgents/com.apple.familycontrols.useragent.plist 2>/dev/null
```

**Note:** These commands may not work on newer macOS versions due to System Integrity Protection (SIP).

## Why This Matters

The `webfilterproxyd` process intercepts ALL web traffic and causes:
- Massive packet loss (14,525+ retransmissions)
- Duplicate packets (23,128+)
- Out-of-order packets (31,555+)
- Network speed throttled to ~0.3 Mbps

Once disabled, your network speed should return to normal.


