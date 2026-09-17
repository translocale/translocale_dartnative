# DartNative OTA demo

A 45-second walkthrough using translocale_dartnative 0.1.0 on an iOS simulator. Narration is generated with the local Kokoro voice engine.

The app connects to a local demo server serving the package test fixtures. This demonstrates network delivery and persistent caching; it does not show publishing through the hosted TransLocale dashboard. Refresh is triggered manually.

## Transcript

Let's change a translation in a running DartNative app, without rebuilding it.

Here's the French greeting: Bonjour Sam. This is the actual iPhone simulator, connected to a local demo server.

Now I'll make the next translation release available. It changes the greeting to Salut Sam.

I'll tap Refresh translations to check right away. There's the new wording. The app stays open the whole time.

Let's stop the server and reopen the app. The downloaded greeting is still here, loaded from its cache.

That's OTA delivery: compatible wording updates, saved for offline use. Follow the steps below to connect your own TransLocale project.

## What the recording verifies

- The greeting changes from Bonjour Sam to Salut Sam in the same running app.
- The updated wording is restored from cache after restarting the app with the demo server stopped.
- The expected network error is visible while the cached greeting remains available.
