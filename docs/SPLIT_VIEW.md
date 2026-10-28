# Split view

Up to four tabs show side by side in one entry of the sidebar, which is kept, dragged and moved as one tab: among the open tabs, the favorites grid, the pinned list or a group. Each pane stays a tab of its own, with its page, history, title and extension events; the split only says where each shows.

## Model

`TabSplit` (BrowserCore) holds a space and a layout, `SplitNode`: a pane, or a stack of parts side by side or one above the other, each a share of the stack's length. A stack holds two parts or more and never a stack along its own axis: three panes in a row are one stack of three, in thirds. A pane beside another along the stack's axis joins it and every part then shares it equally; across it, the two make a stack of their own. A pane that goes gives its share to the others in proportion, and a stack left with one part is that part, joining its parent's stack when it runs along it. Moving a pane is taking it out and putting it beside another. The session owns splits next to tabs and keeps them valid with every change:

- A split holds two to four distinct tabs of one space, all in one place; a tab is in one at most. A tab joining a split takes its place; when open tabs meet a favorite, they join the favorite's place instead, so no favorite is lost.
- Moving any pane moves its split: to another place, before another entry, into a group or to another space. Its panes keep their order and layout. Changing a space's profile gives its tabs new identities, and its splits follow them.
- A pane whose tab closes leaves its split; its neighbor takes its space. A split down to one pane ends.
- In the sidebar's order a split's tabs follow each other in reading order, so the first pane stands for the split, and numbered tabs and next-tab shortcuts go through its panes in a row.
- A divider moves only the two parts it separates, each kept at least 15 % of their stack; a boundary that is not a number is ignored.

`Browser.sqlite` stores splits in their own table, the layout as versionless JSON (`{"tab": …}` or `{"axis", "parts": [{"node", "share"}]}`), validated with the session on load (docs/STORAGE.md).

## Showing a split

The selected tab is the focused pane. Selecting any pane shows its split; `WebPageRegistry.activate(_:profileID:alongside:)` keeps every pane's page loaded and visible: panes shown together are never hibernated, and moving the focus between them never moves a video to picture in picture. Leaving the split leaves its panes as tabs are left.

`SplitPageView` lays the panes out from the layout, each on a page surface of its own with the page's shadow, the gap between them a divider. The focused pane is ringed in the space's color; the address, navigation, find and zoom act on it, and the find bar, password picker and offers and zoom indicator float over it (`pageFloats`). Under a link's preview every pane blurs and the split recedes as a page does. A click anywhere in a pane focuses it without taking the click from the page: the window's first responder tells which pane has the keyboard. A native page (history, a terminal) takes the focus with a tap. A tab alone shows as a layout of one pane in the same view, so a pane coming beside it, or going, moves that page rather than replacing the page area: the panes staying take their new places with a spring, a little longer than the shell's, a pane coming slides in from the trailing side, whatever side it takes, and one going shrinks and fades, except while a divider is dragged, which they follow. Showing tabs none of which were shown before is immediate (`BrowserWindowState.paneGroup`), so switching tabs never animates.

- **Dividers**: dragging one resizes the two parts it separates live and saves them when released; a double click shares every stack equally. A glass grip shows under the pointer, and the pointer becomes a resize cursor.
- **Pane chrome**: the pointer pushed against a pane's top edge brings out a glass capsule with a grip (the system's reorder handle), its name, Move Out of Split View and Close Tab. Dragging the grip moves the pane: it steps back, and a glass pane in the space's color, with a tick of the trackpad as it moves, shows where it would go at the nearest side of the pane under the pointer; let go there, it moves, and the layout takes its new shape with a spring. Over itself or a gap, nothing moves. The grip and the dividers take the pointer in AppKit, so a drag near the window's top edge never moves the window. It comes at the very edge only, so a site's own top bar keeps its clicks, and goes a moment after the pointer leaves it.

## Making and undoing splits

- **Drag**: a tab dragged from the sidebar over the page shows, at the nearest side of the pane under the pointer, where it would open: a glass pane in the space's color, which moves with a spring and a tick of the trackpad. Dropping opens it there. Only the first of several dragged tabs joins, and not into a full split.
- **New Tab Beside** (Control-=, or the page's corner) shows a New Tab page in a pane at the trailing end of the page, whichever pane is focused: the last of a row, or beside the whole of a column. Its field is focused, and the page wraps its sites and closed tabs to the pane's width: an address, a frequent site or an open tab chosen there takes the pane's place, in the split. Escape on its empty field, its close button, or showing another tab dismisses it; while it shows, the split's dividers rest.
- **The page's corner**: the pointer pushed into the page's top trailing corner brings out a glass palette of New Terminal, New Tab Beside and, in a split, Separate Split View. It comes at the very edge only, so the page keeps its own corner's clicks, and goes a moment after the pointer leaves it.
- **Open Beside Current Tab** in a tab's context menu, and **Open in Split View** for two to four tabs picked with ⌘ or ⇧. A new pane halves the larger side of the pane it goes beside.
- **New Terminal** (Control-`) opens a terminal pane on the right of the focused pane (docs/TERMINAL.md).
- **Next Pane** and **Previous Pane** (Control-Option-Right and Left) move the focus in reading order.
- Closing the focused pane (Command-W) focuses the pane after it, else before it; a favorite's pane closes too, as a view of its split, and Reopen Closed Tab brings it back, among the loose favorites if its group has gone. **Separate Split View** (Control-minus, or the row's menu) shows the panes as tabs again; **Close Split View** closes them all, or only unloads a favorite split, handing over first to a tab outside it.

## Sidebar

A split stands where its first tab is, as one entry: a drop lands before or after it, never inside it, and dragging it by any part moves the whole split, as a tab is moved.

- **In a list** (open tabs, pinned list, group): one row, a segment per pane, all as wide, each with its favicon and its title fading out where the segment ends. A click on a segment shows the split with that pane focused. Under the pointer each segment offers to close its pane.
- **In the favorites grid**: one tile, its panes' icons as small squares stacked one over the next in reading order, the first on top. A click shows the split with its first pane focused.
- **Menu**: Separate Split View; the favorite moves a tab has (Add to Favorites, Pin Tab, Move to Pinned Tabs, Move to Favorites Grid, Remove from Favorites); Move to Group and Move to Space; Close Split View. A favorite split leaves the favorites for the open tabs while any pane is loaded, as a favorite does.

## Limits

Several tabs picked with ⌘ or ⇧ move with any split among them, but a split never joins a selection as a whole. The layout of each pane is laid out again as panes come, go or a divider moves; pages are not snapshotted for the motion.
