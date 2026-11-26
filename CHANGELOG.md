# Preflight Forever changelog

## 0.3.6

- During a flight, the floating button counts down the time left, using your own recorded time for that route or the InFlight estimate.
- Horde characters see a wind rider on the floating button instead of a gryphon.

## 0.3.5

- Your departure is now the closest flight master even if you haven't discovered it yet. The planner labels it "(undiscovered)" and draws route arrows and flight times from it. Talking to that flight master discovers it and takes your queued flight.
- A flight queued from an undiscovered flight master is kept after /reload.

## 0.3.4

- The planner map now shows you as the world map's player arrow, pointing the way you face, instead of a blue square.

## 0.3.3

First release on CurseForge.

- Floating gryphon button opens a continent map planner from anywhere outdoors and names your closest known flight point.
- Color-coded pins: gold for your departure and destination, green for known flight points, red for unknown or unconfirmed ones.
- Hover a destination to see route arrows and an estimated flight time, using 286 flight connections from client build 1.60.1.71091 and 882 flight timings from InFlight.
- Click a destination to queue it. When you open the queued flight master's map, Preflight Forever checks the route and fare, then takes off. Hold Shift to skip, or turn off auto-depart for a Depart now button.
- Learns which flight points each character knows from flight master visits, with optional import from Forever Dungeon Journal.
- Times your own flights and prefers them over the bundled estimates.
