# Shape-ify v0.1.0+36 — Android open-test source

This archive updates the existing Shape-ify Flutter project on your Windows
computer. It contains the Flutter source, tests, artwork, Android resources,
and iOS resources. It intentionally leaves your generated Android Gradle
project and private signing files alone. See `BUILD_OPEN_TEST.md` for the exact
extract and build steps.

The build script compiles with `SHAPEIFY_DEMO=false` and the hosted PHP relay.
Members create or join a real group, send approximate station locations,
receive three shared stars, aim the rear camera, and tap once per star. Each
phone calculates the result plots from the exchanged observations. Completed
real groups are published to the Shape-ify web collection.

Sky planning first seeks a full-group opening within 30 minutes, then
decreases the required opening attendance in 10% steps.
The opening requires at least 60% of participants within 30 minutes, with
at least three observers. It searches later individual chances for up to
48 hours. The hemisphere's reference
star is preferred when it does not delay a group; other participants remain
scheduled for their own later windows within 48 hours. The exact
policy and catalogue limit are in `STAR_PLANNING.md`.

The app shows candidate flat and globe plots. They are visualizations of the
recorded orientations, not a validated surface fit. The ground-angle solver
does not assume Earth curvature.
