# IsdaSafe diagrams: farmer app + admin panel

`IsdaSafe_Diagrams_UserAndAdmin.drawio` is the draw.io file `IsdaSafe_UserDiagrams_Software.drawio`
(16 pages) with the admin panel merged in, now 28 pages (Level 0 is split into 5 sheets and the ERD into 2 pages). Open it in diagrams.net
(File > Open from > Device). Your original pages and shapes were edited as little as possible;
every addition has an id starting with `adm-` (or `adm6-`, `adm7-`, `c6-`, `c7-`).

Both apps share one Supabase project, so anything about the system as a whole (who talks to it,
what data it holds, what runs where) is one diagram. Anything about one app's screens, steps or
states stays separate.

## One page per diagram
Every page is sized to US Letter proportions (11:8.5 landscape or 8.5:11 portrait, whichever fits the
diagram better) with its content centred, so File > Export as > PDF (all pages) or PNG gives exactly one
page per diagram, ready to place on short bond paper. Only the page size and the position of the
whole diagram changed: shapes were moved together, never resized or rearranged. Insert each page at
full width in Word; the tall ones (ERD and the Block Diagram) are best on a page of their own.

## Merged into the existing diagrams (minimal edits)

| Diagram | What changed |
|---|---|
| Context Diagram | + **Administrator** and **Cloudflare Turnstile** (CAPTCHA, used by both apps) and their four flows. Nothing else moved. |
| Level 0 | Too dense to read on one page, so it is now **five sheets** (same colours and shapes, larger text, straight arrows): 1 = processes 1.0 and 2.0, 2 = 3.0 and 4.0, 3 = 5.0, 4 = admin 6.0 Manage Admin Account & Access, 5 = admin 7.0 Monitor Ponds & Devices. Every flow of your original Level 0 is kept. New: stores **14 admins** and **15 device_locations**; stores 8 (otp_send_log) and 9 (phone_otps) were already numbered in Child Diagram 1. One flow was added to match Child Diagram 1: 1.0 writes the device push token to push_tokens (store 2), which 4.0 already reads. 6.0 and 7.0 are drawn with Administrator, Cloudflare Turnstile and Google as entities; the farmer's SMS and Email gateways appear again where the admin uses them. 7.0 only reads the shared stores, through admin_* functions that check the caller is an approved admin. |
| ERD | Split into **two pages** so it stays readable. Page 1: your original tables for users, ponds and alerts (`profiles`, `push_tokens`, `notifications`, `ponds`, `pond_verification_log`, `pond_alert_state`), unchanged. Page 2: `devices` (+ `last_seen_at`), `sensor_readings`, the new `device_locations`, and the admin tables `phone_otps`, `otp_send_log`, `admins`, with `ponds` and `profiles` repeated as key columns; five relationships were added. |
| Block Diagram | + the **Admin App** group (same Supabase backend), + Cloudflare Turnstile, the farmer group is titled "Farmer App", the database box mentions `admin_*` RPC functions. The legend moved to the bottom. |
| Software Schematic, page 3 (backend) | The RPC and tables boxes list the admin and device-history functions and tables. |

## Not merged, so added as new pages (the same style as yours)

| Page | Why it is separate |
|---|---|
| Child Diagram 6 and 7 | They explode the new processes 6.0 and 7.0. |
| Flowchart Page 3 (sign-in and approval) and Page 4 (monitoring, devices, admins) | Different user journeys. |
| State Transition: Admin Access Status, Admin Sign-in Gate | Different states. |
| Software Schematic: Admin App | Different screens and services. |

## Corrections to the original pages
While checking every page in a real draw.io render, these were fixed in your original diagrams:
- ERD: relationship lines now attach to the correct key rows.
- Child Diagram 1: the push-token step is numbered 1.4 and uses store 2.
- Child Diagrams 4 and 5: sensor_readings is store 5, and labels and numbers match Level 0.
- Flowchart 1: one wrong link was reconnected; a few typos in labels were fixed.
- Software Schematic page 2: two stray labels ("token", "reading") over Data Repositories were removed.
- Arrows in all pages are straight or neatly orthogonal and end inside their shapes; no shapes overlap.

## Based on the current code and database
Tables and functions come from the live Supabase schema (`admins`, `phone_otps`, `otp_send_log`,
`device_locations`, `admin_*`, `pond_reading_days`, `device_pond_readings_average`), and the flowchart
and state pages follow `AdminGate`, the Devices tab and the monitoring screens.

## Not covered
- The Data Dictionary and Interface List are in the PDFs only, not in the draw.io file, so they were not changed.
- `IsdaSafe_Admin_System_Diagrams.pdf` and `IsdaSafe_System_Diagrams.pdf` are the older PDFs (14 Oct) and were not regenerated.
