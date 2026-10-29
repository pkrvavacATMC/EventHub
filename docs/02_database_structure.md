# Database structure and design decisions

[ERD](../eventhub-diagram.png) · [Setup](../README.md) · [Presentation](09_presentation.md)

## Entities and relationships

| Table | Purpose and relationships |
| --- | --- |
| city | Shared city reference with an IANA time zone; one city has many locations and buyers. |
| organizer | One organizer manages many events. |
| location | Venue belonging to one city; hosts many events. |
| event | Scheduled event belonging to a venue, organizer and event type; has many categories and reservations. |
| event_type | Nine seeded event types, such as concert, theatre and festival. |
| buyer | Customer with optional password hash, verification and login status; can create many reservations. |
| ticket_category | Event-specific price, fee, capacity, seating type and occupied-capacity counter. |
| seat | Numbered seat in one category; category, row and number are unique. |
| reservation | One buyer booking one event, with status, timestamps and refund protection. |
| reservation_item | Quantity and historical price/fee snapshot for a category in a reservation. |
| reservation_seat | Historical seat hold for an item; releasing it allows a later hold. |
| ticket | Individual issued ticket, optional seat hold, random code, check-in and refund information. |

The event-to-buyer relationship is many-to-many through reservations. A reservation can have several items but only 1–4 tickets in total. Standing tickets have no seat hold. A seat can have many historical holds, but only one active hold. Each hold can issue at most one ticket.

## Time model

System moments are TIMESTAMP values and connections use UTC. Only the event's
local start remains DATETIME, interpreted through location and city.time_zone.
Refund and check-in windows use UTC elapsed hours; monthly revenue uses the
Zagreb business calendar. Only buyer.updated_at updates automatically.

## Reservation lifecycle

`create_reservation` accepts buyer/event IDs, a JSON item array, a protection flag and an output reservation ID. It locks categories, checks availability and creates a pending reservation, items and optional seat holds atomically. Pending bookings occupy capacity for 15 minutes.

`confirm_reservation` confirms an eligible reservation and issues tickets. `cancel_reservation` releases a pending reservation; `cancel_ticket` handles individual confirmed tickets and refunds. `expire_reservations`, invoked by the scheduled event, releases expired pending bookings. Check-in checks both the ticket code and event identity.

Confirmation simulates successful payment: there is no payment gateway integration. A failed payment demonstration cancels the pending booking; a rejected booking is a separate case where creation itself fails.

## Integrity and concurrency

Primary and foreign keys establish identity and ownership. Composite foreign keys ensure an item and its category belong to the reservation event, a seat belongs to the item category, and a ticket hold belongs to the ticket item. These checks require intentionally redundant columns and supporting unique keys.

CHECK constraints enforce local rules such as nonnegative prices and `0 <= reserved <= capacity`. Triggers enforce additional cross-table and lifecycle rules. Procedures coordinate multi-table transactions and roll back on exceptions. Application permissions encourage callers to use these procedures rather than write directly.

`SELECT ... FOR UPDATE` serializes competing operations on the same capacity rows. The waiting session reads availability after the first transaction completes. The concurrency script demonstrates why checking availability without locking can oversell even when a stored counter looks valid. CHECK alone protects the counter, not every aggregate invariant.

`active_seat_id` is a stored generated column: an active hold exposes its seat ID, while a released hold exposes NULL. A unique index prevents two active holds for one seat while retaining history. `v_reserved_check` compares stored capacity counters against reservation data.

## Trade-offs and limitations

- `reserved` speeds availability checks but duplicates aggregate information; transactional updates and consistency checks are essential.
- Price and fee snapshots preserve purchase history when category prices change.
- Transactions and locks protect capacity but serialize popular-category purchases. Applications need an explicit retry policy for transient database failures.
- Indexes accelerate reads at the cost of storage and write maintenance; measured selectivity matters more than adding indexes everywhere.
- Transactional history is retained rather than deleted. This simplifies auditing but needs a future retention/privacy policy.
- Refund protection costs 10% of ticket prices. Ticket prices are refunded fully with protection; without it, the policy is 80% at least seven days ahead, 50% at least 48 hours ahead, otherwise zero. Service and protection fees are not refunded.
- Booking and cancellation stop at event start; check-in has a limited time window. Expiration depends on the database scheduler.
- This is a database project: external payments, authentication, delivery and production operational policies require additional application work.

Views provide capacity, ticket statistics, attendance and monthly revenue. Revenue includes ticket prices and fees minus refunds; protection fees must be aggregated once per reservation to avoid JOIN multiplication.
