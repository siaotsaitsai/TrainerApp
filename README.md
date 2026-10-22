# Session Book

An offline iPhone/iPad workspace for independent personal trainers in the United States. SwiftUI, iOS 18+, no third-party dependencies. English with Simplified Chinese and an in-app language override.

Open `TrainerApp/TrainerApp.xcodeproj`, select an iPhone simulator and run. Existing automatic signing and bundle identifier are preserved.

## Workflows

- Add/edit clients, contact information, optional goals and notes. Archive and restore clients; permanently delete only clients without payment/refund history. Archiving requires resolving upcoming bookings.
- Sell one or more sessions (default 10), with generated or custom names, customizable duration, purchase/expiry dates, optional upfront payment and gifted sessions. A unified client overview combines package and standalone session sales, with expandable purchase details.
- Record partial payments and refunds in USD (Cash, Zelle, Venmo, Card, Other). This records external payments; it does not transfer money.
- Book package sessions, pay-as-you-go single sessions, or free trials without a package. Record single-session payments against an existing booking or create a new booking together with payment.
- Book individual sessions, customize their duration and location, edit bookings, detect overlaps and reserve available purchased sessions.
- Complete sessions once, track charged/free cancellations and no-shows, restore to scheduled to reverse a deduction. Trainer cancellations never charge a credit.
- View weekly/monthly/yearly cash receipts, session revenue, completed sessions, debt and remaining credits. Annual charts show monthly receipts.
- In-app reminders for low credits, expiry, debt and manually retained scheduled sessions. Ended unpaid standalone sessions remain in Today payment follow-ups, with direct prefilled payment entry and tappable balance badges. Optional local pre-session alerts (default 30 minutes) with per-session overrides, cancellation/rescheduling updates, foreground banners and notification deep links. The nearest 60 alerts refresh on app activation and saved changes. Late bookings alert at session start.
- Optionally add a saved session to Calendar through the system event editor, including client, start/end, location and notes. The user selects a configured calendar and confirms. No calendar-reading permission is requested. Export history warns before another copy; copies are not automatically synchronized after edits/cancellations.
- Export a full JSON snapshot. Local writes are atomic and keep the prior snapshot. There is no cloud sync or login.
- Optional sample mode operates in memory only. Exit it to return to your original workspace; restarting also exits it. Existing client data remains untouched.

## Accounting

Money is stored as integer cents. Package prices are allocated across purchased credits, distributing any rounding cents deterministically. Receipts use payment dates, revenue uses charged session dates. Refunds reduce receipts and reopen the unpaid balance; they do not remove credits or rewrite package prices. Remaining totals include expired credits (expiry is shown on each package). Booking reserves but does not consume credits. Every charged package session consumes exactly one credit, irrespective of duration. Standalone sessions use no package credits. Free trials always earn zero. Paid single-session fees are receivables while scheduled and count as session revenue when completed or charged for cancellation/no-show; waived cancellations and trainer cancellations have no fee.

## Verification

The pure Foundation ledger regression checks can be run from the repository root:

```sh
mkdir -p /tmp/trainerapp-tests
swiftc -module-cache-path /tmp/trainerapp-tests/cache TrainerApp/TrainerApp/Models.swift TrainerApp/TrainerApp/Persistence.swift TrainerApp/TrainerApp/ReminderPlan.swift TrainerApp/TrainerApp/CalendarAppointment.swift TrainerApp/TrainerApp/ClientAccessPolicy.swift TrainerApp/TrainerApp/IncomeCSV.swift Tests/LedgerTests.swift -o /tmp/trainerapp-tests/checks
/tmp/trainerapp-tests/checks
```

The first version does not include customer accounts, payment processing, cloud sync, remote push notifications, automatic calendar synchronization or backup import. Exported snapshots contain client data and should be stored privately.

## Pro subscription

Free: 3 unarchived clients. Archived clients retain their history and do not consume a slot; restoring requires an available slot or Pro. Pro: unlimited editable clients, monthly or annual auto-renewable subscription, intended US prices $2.99/month and $24.99/year. Product IDs: `com.siaotsaitsai.sessionbook.pro.annual` and `com.siaotsaitsai.sessionbook.pro.monthly`. Access is based only on verified StoreKit current entitlements; purchase, pending approval, cancellation, restoration and transaction updates are handled. Expired/refunded users retain every record for viewing/export while clients beyond the first three become read-only. Sample mode is in-memory and does not bypass storage rules.

Use the separate `SessionBook-StoreKit` Xcode scheme for local, no-charge purchases with `SessionBookPurchases.storekit`. The normal TrainerApp scheme queries App Store products and never simulates Pro. Configure the same subscription ID in App Store Connect before release. A public privacy-policy URL, App Store metadata, subscription review information and Apple paid-app agreements/tax/banking setup remain release tasks. The in-app privacy page describes current on-device behavior; standard Apple EULA is linked.

The Today income card opens Insights. Insights offers annual CSV cash-receipt export with client, payment date, UTC timestamp, reporting time zone, payment method, package/session, signed USD amount and payment notes. Refunds are negative. Export includes all records for the selected year, independent of the chart period and subscription status. CSV uses UTF-8 BOM, escaped multiline text and spreadsheet formula protection. It does not calculate profit or taxes.

Session details includes Delete session with confirmation. Deleting an unpaid session removes its notes and reminder, releases package reservation/credit, and keeps other recurring bookings. Package payments remain unchanged. Any direct payment/refund history blocks deletion, even at net zero. Previously exported calendar copies require manual deletion in Calendar.

Package credits left = purchased − used − booked; completion moves one booked session to used without deducting available credits twice. Scheduled sessions automatically complete after their end time on launch/foreground and every 15 seconds while active. No payment is created. A manual return to Scheduled after the end time persists as an override; moving that booking into the future resumes automatic completion. Cancelled/completed/elapsed cards use a muted treatment.

Opening a session shows inline date/time, duration, location, package/price, reminder, status and note fields with one pinned Save action that stays visible while scrolling. Unpaid standalone sessions also provide inline payment entry with a separate Record payment action. Edits work on scheduled, completed and cancelled records. Backdated bookings reconcile to Completed in the same atomic save, including elapsed occurrences in repeating bookings; ongoing/future occurrences stay Scheduled. Editing preserves direct payment references and cannot reduce a price below net receipts.
