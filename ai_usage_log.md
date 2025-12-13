Tobey Gray - 12/8/25 - Copilot
What was Asked - How to make spotify play directly in the app using the spotify_sdk
How it was applied - Since the Spotify SDK does not allow developers to directly use spotify in the app, instead opts to allow the app to control the spotify app
Reflection - This confirmed what I was worried about, that you can't play directly play spotify in the app. I tried other methods like using a webview, but that didn't work out, so I had to use the suggested method of externally controlling the actual spotify app.
-------------------------
Tobey Gray - 12/12/25 - Copilot
What was asked - Why doesn't the preview feature work?
How it was applied - Some songs aren't provided previews, if its missing a preview, link to the song in the web player/app for spotify.
Reflection - This helped create a fallback for the broken preview feature. As far as I can tell, the spotify sdk has deprecated the preview feature and I'm not sure any song has a preview in the sdk anymore. This fallback to the webplayer or the app is similar to what was employed for the actual song features.