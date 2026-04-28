# Changelog

## v0.2.2 (2026-04-28)

- Use specific location to create locker (with alongside node-level creation) to ensure lockers are properly associated with location for accurate availability tracking and assignment during check-in
- Fix locker sync logic to properly handle location associations and ensure accurate locker counts per location
- Add missing `location_id` to locker creation in tests and seed data

## v0.2.1 (2026-04-25)

- Add Delete button on locker cards, visible to super admins only
- Sync functions now delete excess available lockers (no active sessions) when locker count is reduced
- Allow `total_lockers = 0` at node level to skip node-level sync (distribute all lockers per-location)
- Fix `max_duration_hours = 0` validation and UI to represent unlimited duration
- Fix location name badge on locker cards using all locations (not filtered by is_active)
- Fix compiler warnings: group `load_locations` clauses by arity

## v0.2.0 (2026-04-24)

- Add per-location locker support scoped under `mst_locations`
- New `LockerLocationConfig` schema for per-location enable/disable and locker count settings
- Add `location_id` field to `Locker` schema (nullable, backwards compatible)
- New migration adds `location_id` column to lockers and creates `plugin_locker_luggage_location_configs` table
- Node → Location hierarchical tab navigation in Manage Lockers and Sessions pages
- Location breakdown (available/occupied counts) shown per-location on the Index dashboard
- NodeConfigLive: expand a node to reveal per-location configuration forms; saving triggers `sync_lockers_for_location`
- `CheckInPanel` now scopes locker offer and assignment to the visitor's check-in location when `location_id` is provided
- Hook payload updated to forward `location_id` from the host app's check-in LiveView

## v0.1.6 (2026-04-17)

- Fixd version number

## v0.1.5 (2026-04-17)

- Add pagination to session history page for better performance with large datasets.

## v0.1.4 (2026-04-16)

- Add refresh button to locker management and session history pages to reload data without a full page refresh

## v0.1.3 (2026-04-15)

- Fix if template

## v0.1.2 (2026-04-15)

- Fix layout on lockers management page
- bump version from 0.1.1 to 0.1.2

## v0.1.0 (2026-04-04)

Initial release.

- Per-node locker enable/disable toggle
- Configurable locker count per node
- Auto-assign available locker during visitor check-in
- Manual locker assignment and release by staff
- Locker statuses: available, occupied, maintenance, reserved
- Session history with timestamps and release tracking
- Admin UI at `/manage/plugins/locker_luggage/`
- Plugin settings (self-release, auto-expiry, receipt display, expiry notifications)
