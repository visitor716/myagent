# Windows Chrome CDP from WSL

Use this path when Telegram Web is already logged into a Windows Chrome profile and you want WSL-side automation to reuse that session without copying profile data.

## What the helper does

- Starts a small Windows-local TCP relay that forwards a WSL-visible port to Windows Chrome DevTools
- Lets WSL tools connect to the existing Windows browser session
- Avoids re-logging into Telegram Web when the Windows profile is already authenticated

## Start the relay

```bash
bash scripts/start_windows_chrome_cdp_relay.sh
```

Default ports:

- listen port: `39222`
- target Chrome DevTools port: `9222`

If you need different ports:

```bash
bash scripts/start_windows_chrome_cdp_relay.sh 39222 9222
```

## Stop the relay

```bash
bash scripts/stop_windows_chrome_cdp_relay.sh
```

## Notes

- The relay script writes a transient `chrome_cdp_proxy.js` into the Windows user profile and launches it with `node.exe`
- This is intended as a convenience bridge for local automation, not a general remote debugging exposure
- Clean up the relay once the browser-controlled step is complete
