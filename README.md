# MediFind LK — v0.1 working prototype

**Status:** functional interactive demo, optional real Supabase backend. **NOT** a live medicine availability service yet.

MediFind LK helps patients send medicine enquiries to participating pharmacies, receive pharmacist-confirmed availability responses, and contact a pharmacy to verify stock before travelling.

## What's in this package

- Responsive patient-facing web app: homepage, search, medicine request form, request history and pharmacy responses.
- Pharmacy dashboard: see matched enquiries; respond Available / Limited / Unavailable; responses expire in 30 minutes.
- Admin dashboard: register pharmacies as pending; explicitly verify/revoke pharmacy listings.
- Sample medicine catalogue and sample pharmacies **clearly marked as fictional demo data**.
- Demo mode: works without a database, saves sample changes to browser storage, supports testing patient and pharmacy flows in the same browser.
- Live mode: optional Supabase user authentication, permission-controlled database, location matching, verified pharmacy directory and role-restricted responses.
- Installable mobile-friendly PWA for Android and iPhone after HTTPS deployment; also works on a laptop.

**Not included yet:** native Android/iOS app binaries, automatic push alerts, prescription upload, payments, pharmacy inventory integrations, pharmacy licences, a real verified pharmacy network, and formal security/regulatory approval. There are no real pharmacy listings in the demo.

## A. Try the prototype locally — easiest path

1. Unzip the folder `medifind-lk-v0.1`.
2. On Windows, open a terminal in the extracted folder.
3. If Python is installed, run:

   ```powershell
   py -m http.server 8000
   ```

   On other systems: `python3 -m http.server 8000`.
4. Open **http://localhost:8000** in Chrome, Opera, or Edge.
5. Use the left menu (or the phone's bottom navigation) to switch between **Home**, **Find a medicine**, **My requests**, **Pharmacy portal**, and **Admin**.

The demo does not need npm, a Supabase account or a credit card. It does not submit medicine enquiries to real pharmacies.

### Test the full patient → pharmacy flow

1. Select **Request medicine** on the home screen.
2. Enter e.g. `Metformin`, `500 mg`, `Tablet`, `30`, and `Maharagama`, then **Simulate request**.
3. Open **Pharmacy portal**. Choose **Sample Pharmacy — Maharagama** (or another matched sample pharmacy) from the switcher.
4. Find your request and choose **Available** or **Limited stock** to simulate the pharmacy response.
5. Open **My requests** to see the new status and the time of the confirmation.
6. Open **Admin dashboard** to try creating a sample pharmacy, then mark it verified.
7. Select the round **MF** account icon at the top to reset demo data.

Each action only changes your **own browser**. It is *not* shared across devices or real pharmacies in demo mode.

## B. Put it online with Netlify (demo)

1. Go to **Netlify → Add new project → Deploy manually**.
2. Drag the extracted `medifind-lk-v0.1` folder into the deployment area (or upload its contents).
3. Netlify will host `index.html`, CSS, JavaScript and icons as a static website.
4. Open the generated HTTPS `.netlify.app` site on your computer or phone.

For GitHub deployment, upload all source files **except `config.js` if it contains deployment-specific settings**; no `node_modules` folder or build command is needed. Netlify publish directory is `/` (project root).

### Install on your phone

- **Android/Chrome**: open the HTTPS site → Chrome menu → *Install app* or *Add to Home screen*.
- **iPhone/Safari**: open the HTTPS site → Share → *Add to Home Screen*.

This is a Progressive Web App (PWA); it isn't a native App Store/Play Store release yet. Some browser capabilities and installation options vary.

## C. Connect a real Supabase backend

> **Important:** A live backend is for a supervised pilot with properly verified participating pharmacies. Do not invite the general public or collect sensitive health data before privacy, legal and security review.

1. Open https://supabase.com/dashboard and create a **new project**.
2. Navigate to **SQL Editor** → **New query**.
3. Copy and run `supabase/schema.sql`. It defines tables, triggers, Row Level Security policies and narrowly scoped response functions.
4. In project **Settings → API keys**, copy the project URL and **publishable** / legacy **anon** key. **Never** use a service role / secret key here.
5. Create a file named `config.js` in the project root, using `config.example.js` as your template:

   ```javascript
   window.MEDIFIND_CONFIG = {
     supabaseUrl: 'https://YOUR-PROJECT.supabase.co',
     supabaseAnonKey: 'YOUR_PUBLISHABLE_OR_ANON_KEY'
   };
   ```

6. Reload the website. The top status should say **Live connected**.
7. Press the profile icon → Sign in or register an account. Depending on Supabase Auth settings, users may need to verify email.
8. After you confirm the account, promote **only your own designated administrator account** in the SQL Editor:

   ```sql
   update public.profiles
   set role = 'admin'
   where id = (
     select id from auth.users where email = 'YOUR-ADMIN-EMAIL@example.com'
   );
   ```

9. Sign out and sign in again (or reload), and go to **Admin dashboard** → **Add pharmacy**. The pharmacy is **pending** until the administrator independently checks its current NMRA licence and confirms the details.
10. Have a participating pharmacist create a separate account; find their user UUID and the verified pharmacy UUID in the Supabase dashboard.
11. Assign the pharmacist to the approved pharmacy in the SQL Editor:

    ```sql
    insert into public.pharmacy_staff (pharmacy_id, user_id)
    values ('VERIFIED-PHARMACY-UUID', 'PHARMACIST-USER-UUID');
    ```

12. Test the flow across two browser profiles: a **patient account** creates a request; the **pharmacist account** can view requests matched to their assigned pharmacy and respond.
13. In live mode, the patient can see their own requests and responses but cannot see another patient's requests. The pharmacy does not receive the patient's email or account details.

### Live-matching rules

- Requests are sent to verified, active pharmacies **within the chosen radius of the approximate selected town centre**. This version does not access precise GPS location.
- If either coordinate is missing, matching falls back to an exact town-name match.
- A request expires after 12 hours. Positive availability responses expire after 30 minutes.
- No pharmacy can report availability for a request unless it belongs to that pharmacy's matched target and an administrator has assigned its staff account.
- Responses do not change a request to `fulfilled`; that feature will be developed in a later milestone.
- Refresh the page or tap **Refresh** in the pharmacy dashboard to fetch new data; automatic push notifications are not yet implemented.

### Recommended pilot security tests

- Anonymous users cannot read patient medicine enquiries.
- Patient A cannot read or cancel Patient B's request.
- A staff account from pharmacy A cannot see pharmacy B's unmatched requests or respond on its behalf.
- An unapproved pharmacy has no active target queue.
- An ordinary patient cannot self-promote to admin or verify a pharmacy.
- A response's `request_id` and `pharmacy_id` are derived on the server from `target_id`.
- Cancelled/expired requests cannot receive new responses.

## D. Product scope and safety rules

- Only NMRA-licensed, independently checked pharmacies should be approved for a real pilot.
- Do not display unconfirmed inventory as live stock or present stale results as fresh.
- Confirm exact medicine name, strength, dosage form and quantity; do not recommend substitutes or dosage changes.
- Exclude controlled/restricted medicines and any products for which public availability listings are not legally permitted, following professional review. **The current unrestricted text box does not yet enforce these exclusions automatically.**
- Do not collect prescription photos, diagnoses or other unnecessary medical data in v0.1.
- Obtain legal and pharmacy regulatory advice before public launch; create privacy terms, retention and incident response policies.
- Emergency medical needs require professional emergency care, not waiting for a pharmacy response.

Sources for review:

- Sri Lanka NMRA pharmacy directory and community pharmacy guidelines: https://www.nmra.gov.lk/pages/pharmacy
- Sri Lanka Data Protection Authority / PDPA status: https://www.dpa.gov.lk/Background
- Supabase authentication and RLS: https://supabase.com/docs/guides/auth/quickstarts/react-native

## E. Recommended next milestones

**v0.2 — Local pilot**: verified pharmacy onboarding, legal/privacy review, medicine terminology validation, real cross-account workflow testing, request activity logs, stock confirmation audit trail, mobile-friendly authenticated sessions, and graceful abuse prevention.

**v0.3 — Alerts and reliability**: real push/email notifications, queues and retry logic, response timestamps, expiry alerts, medicine-level analytics, and monitoring.

**v0.4 — Native mobile**: develop React Native / Expo patient app using the same Supabase schema, keeping the pharmacy and admin portals on the web.

## Important technical note

This code is a development prototype. Although the SQL contains RLS and controlled RPCs, it has **not been audited** or load tested for a healthcare production setting. Live mode uses a hosted Supabase JS module; the computer running it needs internet access. Do not place API secrets or real patient records in screenshots, demo data or source control.

**MediFind LK · Started November 2026**
