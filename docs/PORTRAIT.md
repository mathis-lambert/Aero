# Portrait mode

Capture in Portrait Mode turns the selected page into a picture to post: the page framed like a window on a backdrop, with “Captured with Aero” under it. Arc had the same idea; Aero adds more backdrops, proportions for where the picture goes, and the whole page.

## Opening it

Capture in Portrait Mode is a catalog command, so it works from the control bar (searching “capture”, “portrait” or “screenshot”), the File menu, a shortcut set in Settings › Shortcuts, and the button beside Share in the control center. It has no default shortcut. It is available on a loaded web page, not on New Tab or a browser page (`aero://`).

The command closes the control center or the control bar and opens the quick capture at once. It is already shaped by the page's size: the backdrop and the frame show, filled with the page's background, while WebKit's snapshot of what the tab shows is taken. A light sweeps across the empty frame (a spinner with Reduce Motion), and the picture fades in when it arrives. The snapshot takes what is on screen without waiting for the page to paint again, which a busy page may take long to do. Copy, Save and Share wait for it. A change of tab or space closes the popover and drops the snapshot; if the snapshot fails, the popover closes and says so.

## Quick capture

A popover drops from the sidebar's address, which appears for it when the sidebar is hidden. Its title row holds Customize…. Below are the portrait, a swatch for each backdrop and, for the tinted ones, the hue slider, then the picture's size beside Share, Save… and Copy. Return copies the picture and closes the popover, as in the studio. Customize… hands the same capture and style to the studio. The popover closes with Escape, a click elsewhere, or a change of tab or space.

## The studio

It is a window prompt: commands wait behind it, Escape or a click outside closes it. The preview shows the picture exactly as it will be exported, because the preview and the export draw the same view (`PortraitCanvas`). Changes animate unless Reduce Motion is on, and nothing runs while the studio is idle.

- **Capture**: Visible area, as scrolled, or Full page, which WebKit draws as a single-page PDF that Aero rasterizes off the main actor. A page taller than 16,000 points is cut at the bottom.
- **Background**: Gradient, Aurora (a mesh of the tint's neighboring hues), Solid, Desktop (the desktop picture of the window's screen, blurred or not), Site (the page's theme color, else its favicon's, else the space's), or None, for a transparent PNG. The tinted backdrops follow a hue slider between white and black ends, as Arc's did.
- **Frame**: the proportions (Fit the page, Square, 16:9, 4:3, 4:5, 9:16), the padding, corner radius and shadow.
- **Show**: a title bar with the page's address, and the credit.

The style is saved as one preference (`browser.portrait.style`, JSON). Each capture starts from the last style, and a saved style Aero cannot read falls back to the default. If the full page or the desktop picture fails, the studio goes back to Visible area or Gradient and says why.

## Layout

`PortraitLayout` places the parts in points of the page. The margin is a share of the page's longer side. The credit gets a band of at least 44 points under the page, so it never touches it. A proportion is reached by growing the backdrop, never by cropping or shrinking the page, and the page is centered in the room above the credit band. `PortraitLayoutTests` cover these rules.

## Export

- **Copy** (Return or ⌘C) puts the picture on the pasteboard at most 2,560 pixels on its longest side, shows Copied, then closes the studio; a second Return meanwhile does nothing. It writes a JPEG first, which apps that take one prefer, and a PNG for the others, such as web pages. The PNG is promised: it is encoded only when an app pastes it, or as Aero quits. A transparent picture is PNG only.
- **Save…** (⌘S) writes the picture where you choose. It is named after the site and the moment, and the studio closes once the file is written.
- **Share** offers the system's share menu for the picture's file.
- **Dragging the preview** drops the same file anywhere. The file is made when the drop lands, not as the drag begins.

Files are JPEG at quality 0.85; a transparent one (None) is PNG. Pictures render at the page's own pixel density, capped at 40 million pixels and 16,384 on the longest side, the GPU's largest texture. A render is kept until the style changes, so sharing after copying does not draw it again. Encoding and file writes run off the main actor. Files for sharing and dragging go to a folder of their studio under `Portraits` in the temporary directory; the next studio removes the others.

## Responsiveness

The snapshot's small copy (1,600 pixels on its longest side) is made off the main actor while the popover shows. Previews draw the portrait at their own size from that copy, so moving a slider never redraws, shadows or blurs the full-size picture. Only an export draws it.

## Limits

- The snapshot is WebKit's: video frames and some GPU-composited content may come out blank, and the full page renders fixed headers once, at the top.
- The credit's language follows the app's.
