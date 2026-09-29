# Other apps

Aero exchanges links with the rest of the Mac in three ways: other apps open web addresses with it, pages hand addresses meant for other apps back to macOS, and apps sign in through it with `ASWebAuthenticationSession`. All three use public AppKit, WebKit and AuthenticationServices APIs.

## Declaration

`Info.plist` declares `http` and `https` in `CFBundleURLTypes`, which makes Aero a browser that macOS lists as a default browser choice and routes web addresses to, and `ASWebAuthenticationSessionWebBrowserSupportCapabilities` with `IsSupported`, `EphemeralBrowserSessionIsSupported`, `CallbackURLMatchingIsSupported` and `AdditionalHeaderFieldsAreSupported`. No entitlement is involved. Every channel declares them; macOS routes to the one the person made the default. Local files are not declared: Aero does not display `file:` pages.

## Links from other apps

macOS delivers addresses to `application(_:open:)`, whether Aero is running or launched by the link. Scenes declare `handlesExternalEvents(matching: [])`: a scene that handled the event would present its window again, which Stage Manager moves aside. Only web addresses are kept; anything else is ignored, so another app cannot open a local file or an `aero://` page.

Each link opens in a new tab of the selected space, the last one selected, and the main window comes forward, opened again if it was closed, even while the link waits. Links wait while records load, while an onboarding or an import covers the browser, and while a structural change is saved; they open, in order, when that ends. A link never interrupts the onboarding.

## Links to other apps

`NavigationInput.target(of:)` decides where every address a page navigates to goes:

| Target | Addresses | What happens |
| --- | --- | --- |
| Page | `http`/`https` with a host, extension pages, `about:`, `blob:` | Loads. |
| Application | Any other scheme, such as `mailto:`, `tel:`, `zoommtg:` or an app's sign-in callback | Not loaded; offered to the app macOS opens it with. |
| Blocked | `file:`, `javascript:`, `data:`, `vbscript:`, `aero:`, malformed web addresses | Never loads and never leaves; the main frame shows that the page could not be opened. |

An application address asks only when it comes from the main frame, a popup, or a link the person followed in a frame: a frame cannot launch an app on its own. Only the selected tab asks, one question at a time, and a request made while another prompt shows is dropped. An address no app opens is dropped without a message, since pages probe for installed apps this way; so is one that would open Aero itself.

The prompt names the app with its icon: Open (Return) hands the address to it through `NSWorkspace`; Cancel or Escape leaves the page as it was. It is answered for the tab that asked: a tab left meanwhile opens nothing. There is no "always allow": like Safari, each hand-off asks.

## Sign-in for other apps

When Aero is the default browser, macOS hands it other apps' `ASWebAuthenticationSession` sign-ins. `SignInSessions` is registered as the session handler at launch, so a launch for a sign-in receives it; such a launch opens no main window, unless startup fails and recovery must show. The Dock icon opens the main window later.

Each request gets a window of its own with the site's host, whether the connection is secure, and Cancel (Escape). Its page belongs to no tab: it records no history, is never restored, opens no popups and offers no saved passwords. It signs in with the selected space's profile, so an account already signed in there is reused, with that profile's extensions and passkeys. A private request (`shouldUseEphemeralSession`) uses a non-persistent store of its own instead, without extensions, discarded with the window. The request's additional header fields go with its first load only.

The first navigation or popup that the request's callback matches (`ASWebAuthenticationSession.Callback`, a custom scheme or an HTTPS host and path) is returned to the app and never loaded or offered to another app. Returning, Cancel, closing the window, or the app cancelling the request ends the window and its page together, exactly once. Requests that arrive before records are loaded wait for them.

## Failure modes

1. A link from another app is dropped, opens in the wrong space, is lost during launch or onboarding, or opens a local file or a browser page.
2. A page launches another app without asking, a frame or a background tab asks by itself, or prompts pile up.
3. A local, script, data or browser address is loaded or handed to another app.
4. A sign-in callback is loaded as a page, offered as a link to another app, or reported twice; a window closed by the person leaves the app waiting.
5. A private sign-in reads or keeps the profile's cookies; a sign-in page enters history, the session or restoration.
6. A launch for a sign-in opens the main window, or a closed main window cannot be brought back from the Dock.

## Verification

`NavigationTargetTests` covers the target of each kind of address, including case and malformed addresses (3). `BrowsingJourneys.testLinksCrossBetweenAeroAndOtherApps` opens a link from outside into a new selected tab, and checks that a frame and an unknown app ask nothing while a followed `mailto:` link asks and Escape declines (1, 2). `OnboardingJourneys.testChromeImportInFrenchAndDarkThenSkip` opens a link during the onboarding and finds it after Skip (1). Sign-ins need Aero to be the default browser, which a test run must not change: they are checked by hand on a signed build with an app using `ASWebAuthenticationSession`, private and not, completed and cancelled from both sides (4, 5, 6), as is confirming a hand-off to a real app.
