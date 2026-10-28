# Media

What pages play and record shows in the sidebar: a player for the media of a tab off screen, the tabs using the camera
or the microphone, and indicators beside each tab's title.

## What a page plays

Two page scripts report it (`MediaScripts`, BrowserWebKit), in every frame, so a player embedded in an article counts:

- In the page's world, one keeps the handlers the site gives its Media Session (`setActionHandler`) and relays its
  metadata, playback state and position, which the site sets there; a DOM event carries them, and the player's actions,
  between the worlds.
- In Aero's world, the other follows the page's audio and video elements and reports to the app, at most every 60 ms.

The report is untrusted: texts are cut at 512 characters, the artwork is the largest declared website address, actions
are the Media Session's known names, numbers must be finite. WebKit's own playback state (`requestMediaPlaybackState`)
settles whether the page plays, for media no script sees, such as an element out of the document.

Each frame reports under a random token its script draws, and says when it goes; at most 32 frames are followed. The
page's media is the frame heard last, else one playing, else one naming its media or holding an element, the main frame
first; the player's actions go to that frame. A new document starts with no media; a report answered after a later one,
or from a document since left, is dropped.

`BrowserPage.activity` holds the result; the page registry reports each change to the app by tab, and a page closed,
hibernated or replaced reports itself idle. The app keeps the activities of its tabs (`PageActivities`) and ignores
reports for tabs it no longer has.

## The player

Above the sidebar's footer, the player shows the media that began playing last in a tab off screen (neither selected
nor a pane of the selected tab's split), a playing one before a paused one. Media begins only when it is heard: unmuted
with some volume, or named by the site's Media Session. A video waiting on its page, or a muted one playing behind it,
has no player, no sound indicator and no place in the system's Now Playing.

- One compact row on neutral glass, so its text reads: the artwork, the track and who plays it, then Play or Pause and
  Next; Previous joins them under the pointer.
- The artwork, fetched without cookies or credentials and kept for the last twelve tracks, leans back while paused and
  springs forward as it plays; the site's favicon stands in without one. Its color, or the space's for a grey or white
  artwork, glows behind the player while it plays.
- A ring around Play or Pause fills with where the media is, moving on its own from the position the page last gave,
  redrawn twice a second while it plays.
- The controls use the site's own Media Session handlers when it gives them, else the media element; without a previous
  or next track, they go back or forward ten seconds.
- A click on the artwork or the title shows the tab. Closing the player hides it until that media plays again.
- It comes up from the footer with a spring and shrinks back into it; Reduce Motion keeps it still.

Play or Pause, Previous Track and Next Track are commands too (View menu, command bar), acting on what the player
shows, else on the current tab.

## The system's Now Playing

`NowPlayingCenter` gives Control Center's Now Playing and the media keys the media that began playing last in any tab,
on screen or not: title, artist, album, artwork, duration and position, and whether it plays (MediaPlayer's
`MPNowPlayingInfoCenter`). Play, Pause, Next and Previous come back through `MPRemoteCommandCenter` and act as the
player's buttons do; without a previous or next track the keys skip ten seconds. It is made the first time a page plays,
and with nothing left to play it clears Now Playing, so the keys go back to the other apps. WebKit publishes nothing of
its own for Aero's pages, so the keys are never taken twice.

## Camera and microphone

WebKit reports them (`cameraCaptureState`, `microphoneCaptureState`). A tab off screen using either has a row above the
player, with switches muting each: the page keeps them, and its call goes on. Each tab's row shows the camera in green
and the microphone in orange while they are on, as macOS does, and the sound while it plays, which a click pauses. A
favorite's tile shows one sign: the microphone, else the camera, else the sound.

## Limits

WebKit gives no public way to mute a page without pausing it, so there is no mute. Scrubbing from Control Center is
off.
