# Terminal

A terminal tab runs the person's login shell in a pseudo-terminal, on the page's own surface. It is a browser page, `aero://terminal`, whose address keeps the folder the shell was last in; it shows as a tab or as a pane of a split (docs/SPLIT_VIEW.md).

## Engine

[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.10.1 (MIT, `App/Resources/SwiftTerm-LICENSE.txt`) draws the terminal and runs the shell: a complete xterm emulator (colors, Unicode, mouse reporting, resizing, selection and copy) in a native AppKit view. It is the only dependency the app adds for this; writing a reliable emulator is out of proportion. Later versions add a build-tool plugin, which would ask every build, CI included, to trust it; 1.10.1 is the last without one, and only its library is linked.

## Lifetime

- `TerminalSessions` owns each tab's `TerminalSession`, one owner for the live resource behind a tab record: the shell starts the first time the tab shows and runs while the tab exists, shown or not. Closing the tab, removing its space, or a profile change that gives its tab a new identity ends it.
- Aero is not sandboxed, so the shell reaches the Mac as Terminal's does. It is the account's login shell (`-zsh`), started with `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=Aero`, the language and region as `LANG`, and `HOME`, `USER`, `LOGNAME`, `PATH`, `TMPDIR`, `SSH_AUTH_SOCK` passed through; nothing of Aero's own environment.
- The folder the shell is in, read from its process, goes into the tab's address when another tab is shown and when Aero quits; after a relaunch a new shell starts there. The process itself does not survive a relaunch.
- When the shell ends, a glass capsule offers to start another; the tab stays.
- The tab is named by the title programs give the terminal, or Terminal.

## Appearance and keyboard

The terminal uses the page surface and ink of the current appearance, the system's monospaced face at 12.5 points, and the space's color for its caret and selection; sixteen ANSI colors are tuned to read on that surface in light and dark. Option is not Meta, so it types accented characters. Aero's reserved shortcuts still work in a terminal; everything else, Escape and Control keys included, goes to the shell. Shown for its tab, the terminal takes the keyboard; beside the focused pane, it does not.

**New Terminal** (Control-`, the File menu, or the page's corner palette) opens one on the right of the selected tab, in a split, in the folder of the selected terminal or the home folder. From the New Tab page, or beside a full split, it opens as a tab of its own.

## Limits

Quitting does not ask about programs running in a terminal. Terminal tabs do not reopen their scrollback after a relaunch.
