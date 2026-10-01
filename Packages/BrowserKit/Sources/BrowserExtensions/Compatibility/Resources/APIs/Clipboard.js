// WebKit has no `clipboardRead`: reading what another app copied waits for the person to confirm a paste. An
// extension granted the permission reads at once, as in Chrome; writing and copying are WebKit's own.
if (globalThis.document && globalThis.navigator?.clipboard) {
    const clipboard = navigator.clipboard;
    const readText = clipboard.readText.bind(clipboard);
    kept.push(clipboard);
    clipboard.readText = async () => (await call("clipboard/read")) ?? await readText();
}
