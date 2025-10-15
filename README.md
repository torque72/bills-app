# Bills Agent – SwiftUI iOS app & dependency-free Node API

Bills Agent is a monthly bill manager that combines a lightweight Node.js API with a native SwiftUI iOS client. The backend keeps track of recurring bills, monthly payment state, Expo push notification registrations, and an OpenAI-powered "BillsGPT" assistant. The iOS dashboard adapts the original React layout for small screens, adds push controls, and surfaces the chat assistant in a dedicated sheet.

## Project layout

```
.
├── data/                    # Persistent JSON store for bills, payments, and push tokens
├── ios/BillsAgent/          # SwiftUI application (Xcode project + sources)
└── server/                  # Dependency-free Node API (fetch/OpenAI/Expo via HTTPS)
```

## Requirements

### API server
- Node.js 18 or newer (uses the built-in `fetch` implementation)
- Optional: `OPENAI_API_KEY` environment variable to enable BillsGPT replies

### iOS app
- Xcode 15 or newer (project targets iOS 16+)
- Swift 5.0 toolchain (bundled with modern Xcode)
- An Expo push token if you want to test live notifications (otherwise optional)

## 1. Configure environment variables

The server reads configuration from the process environment. Set these before launching:

```bash
export OPENAI_API_KEY="sk-your-key"           # Required for /api/chat
export OPENAI_MODEL="gpt-4o-mini"             # Optional – defaults to gpt-4o-mini
```

If you plan to use Expo push notifications, make sure your client app provides valid Expo push tokens to `/api/push/register`.

The iOS app looks for an optional `BILLS_API_BASE_URL` environment variable (editable in the Xcode scheme) to point at your API when running on device or simulator. By default it assumes `http://localhost:4000` which works when the simulator and API run on the same machine.

## 2. Start the API server

No npm install is required — all dependencies rely on Node's standard library.

```bash
cd server
node index.js
```

The API listens on `http://localhost:4000` by default. Edit `PORT` in the environment to change the port. Bill, payment, and push-token state is persisted in `data/bills.json`.

## 3. Open the iOS project

1. Launch Xcode and open `ios/BillsAgent/BillsAgent.xcodeproj`.
2. Select the `BillsAgent` scheme and choose an iOS simulator (or your device).
3. If your API is not running on `localhost`, edit the scheme's **Run** action → **Arguments** tab and add `BILLS_API_BASE_URL` under Environment Variables.
4. Build & run (`⌘R`). The home screen shows monthly totals, upcoming bills, and the editable table. Pull to refresh, swipe rows to edit/delete, and tap the toolbar buttons for BillsGPT chat or adding new bills.

### Push notifications on device

The app requests authorization from `UNUserNotificationCenter`, registers the APNs device token, and forwards it to `/api/push/register`. The **Notifications** panel in the dashboard lets you trigger `/api/push/send-upcoming` manually to verify Expo tickets. For real pushes you will need to pipe that endpoint into your own scheduler.

## API reference

| Method & path | Description |
| ------------- | ----------- |
| `GET /api/bills?month=YYYY-MM` | List bills with `isPaid` for the requested month (defaults to current month) |
| `POST /api/bills` | Create a bill. Body: `{ id?, name, dueDay, amount, notes }` |
| `PUT /api/bills/:id` | Update mutable fields of a bill |
| `DELETE /api/bills/:id` | Delete a bill and clear saved payments |
| `POST /api/bills/:id/paid` | Toggle payment status for a month. Body: `{ isPaid, month? }` |
| `POST /api/push/register` | Save an Expo push token `{ token, platform? }` |
| `POST /api/push/unregister` | Remove a registered push token `{ token }` |
| `POST /api/push/send-upcoming` | Send Expo notifications for unpaid bills due within 7 days |
| `POST /api/chat` | Ask BillsGPT a question about the current month's bills |

The server stores everything in `data/bills.json`. You can seed different bills by editing that file while the server is stopped.

## Troubleshooting

- **Cannot reach npm registry** – The API has no third-party dependencies, so you don't need `npm install`. If you previously checked out the Expo app, remove it (already done in this branch).
- **Chat replies say the key is missing** – Ensure `OPENAI_API_KEY` is exported in the environment before launching the server.
- **iOS simulator cannot reach `localhost`** – Use `http://127.0.0.1:4000`. For physical devices, provide your machine's LAN IP via `BILLS_API_BASE_URL`.
- **Push ticket failures** – The Expo endpoint rejects invalid tokens. Confirm the device token begins with `ExponentPushToken[` and that the device has an Expo client installed if you're testing without your own Expo account.

## License

MIT
