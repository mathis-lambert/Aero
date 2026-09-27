# Profiles and spaces

## Ownership

| Owner | Data |
| --- | --- |
| Profile | Website identity, cookies, history, permissions and extensions |
| Space | Name, color, emoji, ordered tabs and favorite groups; reference to one profile |
| Window | Current space, focus and selection, with a remembered tab per space |

Multiple spaces may share a profile. At least one active profile and one space must remain; a profile may have no spaces. Creating a profile alone neither creates a space nor switches navigation. Favorites belong to spaces.

## Settings and space form

Profiles lists identities; selecting one opens its name and linked spaces. Spaces lists all spaces and owns native drag reordering. Selecting a space opens its appearance and profile. Names commit on Return, focus loss or leaving the page; creation requires confirmation. Empty or overlong names are rejected.

`SpaceForm` is shared by creation and editing: name, optional single emoji, sRGB color (`#RRGGBB`) and profile. New profiles can be created from the form. Custom color edits save after a 300 ms pause or on leaving; presets save immediately. The sidebar heading and centered switcher use the same space identity.

## Identity transitions

Same-profile tab moves preserve the live page. Moving across profiles or reassigning a space discards interaction state and replaces pages; confirmation explains reload and input loss. Active downloads block reassignment. Cookies and history are never copied, and stale callbacks cannot update replacement pages.

Popups follow their opener. Extensions see tabs across their profile's spaces; activation selects the owning space. Background opens use the active matching space, otherwise its first space.

A profile can be removed only when unused and another active profile remains. Deletion persists an intent and refreshes recovery before erasing history, caches, WebKit data and extension packages. Failed cleanup remains pending and can retry from Settings or restart. See [Storage](STORAGE.md).

## Switching

Neighboring sidebars do not load pages. One global page budget covers every space and profile; see [Performance](PERFORMANCE.md). Haptics mark valid swipe thresholds, committed switches, drag pickup and actual order changes, never every gesture frame. Canceled swipes and boundaries do not confirm a switch.
