# Shared-star opening policy

All phones use one three-star plan. The star list consists of named stars with
approximate catalogue J2000 coordinates and visual magnitude **+2.5 or
brighter** (smaller magnitude numbers are brighter). The original Bright Star
Catalogue is indexed by NASA HEASARC at
<https://heasarc.gsfc.nasa.gov/W3Browse/catalog/bsc5p.html>.
`STAR_CATALOG.csv` lists every named target and the approximate coordinates
and magnitude bundled into the app, so the target set can be inspected.
The coordinate predictions guide pointing only; they are not solver inputs.
Clouds, light pollution, and a blocked horizon can still hide a catalogued
star, so observers confirm each target with their own eyes.

Planning starts with the current UTC instant. The first 12 hours are sampled
every five minutes to find the group's opening. Only members who miss that
opening are scheduled later; their opportunities are sampled every fifteen
minutes for the rest of the 48-hour period. A station qualifies at a sample
when the Sun is below -8 degrees
and all three stars are between 12 and 85 degrees altitude there.

The planner first seeks the earliest full-group opening within 30 minutes.
If none exists, it tries 90% of the group, then 80%, 70%, and 60%,
never below three simultaneous observers. Within the same tier it chooses the
earliest slot, then the plan that finishes all members' first windows sooner.
Star triples closer than 25 degrees or with nearly dependent directions are
excluded, since those would give an unreliable ground-angle fit.
If fewer than 60% (or fewer than three) share a slot in the first 30 minutes,
there is no “Go” plan yet. The group can retry later; a possible 60% opening
within the following 12 hours can be shown as a time to check again.
The hemisphere reference star (Polaris or Acrux) is preferred only when its
inclusion does not delay this opening or the later participants.

Every participant must have at least one individual window for the *same*
three stars within 48 hours, even when some are reserved at the opening.
The 48-hour limit is for those later participants, not the duration of any
one observer's sky window.
If no three-star choice gives every participant a window within 48 hours,
the master sees who has no window for the best available choice and may
remove them; someone who has a later window can also elect to leave, or the
master can remove them before their readings are submitted. A conservative
latitude-range check identifies locations that cannot share even three
individually reachable stars with 60% of the group, regardless of the date.
Those members are removed automatically and told to join a geographically
closer group when their phones next contact the relay. This deliberately
avoids declaring a seasonal lack of darkness to be a permanent mismatch.
It does not send push notifications to closed apps.
If the catalogue and darkness rules cannot give every member such a window,
the app reports that no plan is available and lets the organizer retry later
or start a smaller group. The search is a coarse prediction; current sky and
sensor checks run again when a participant opens the camera.
