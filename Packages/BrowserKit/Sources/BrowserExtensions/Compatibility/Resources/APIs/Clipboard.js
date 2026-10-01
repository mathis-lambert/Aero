// An extension page that cannot reach the clipboard itself, such as an offscreen document without focus, goes
// through Aero, which allows it only with the extension's clipboard permissions.
if (globalThis.document && globalThis.navigator?.clipboard) {
    const clipboard = navigator.clipboard;
    const writeText = clipboard.writeText.bind(clipboard);
    const readText = clipboard.readText.bind(clipboard);
    kept.push(clipboard);
    clipboard.writeText = async (text) => {
        try { await writeText(text); } catch { await call("clipboard/write", { text: String(text) }); }
    };
    clipboard.readText = async () => {
        try { return await readText(); } catch { return await call("clipboard/read"); }
    };
    const execCommand = document.execCommand.bind(document);
    // Copying the selection only: pasting would have to answer before Aero does.
    document.execCommand = (command, ...rest) => {
        const done = execCommand(command, ...rest);
        if (done || String(command).toLowerCase() !== "copy") return done;
        const field = document.activeElement;
        const text = field && typeof field.value === "string" && typeof field.selectionStart === "number"
            ? field.value.slice(field.selectionStart, field.selectionEnd)
            : String(getSelection() ?? "");
        call("clipboard/write", { text }).catch(console.error);
        return true;
    };
}
