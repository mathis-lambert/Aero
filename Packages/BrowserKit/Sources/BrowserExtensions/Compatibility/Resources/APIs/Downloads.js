// A blob exists only in the context that made it: its bytes go to Aero as a data address.
const transferable = async (url) => {
    if (!url.startsWith("blob:")) return absolute(url);
    const blob = await (await fetch(url)).blob();
    return await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(blob);
    });
};
define("downloads", {
    download: () => method(async (options) => call("downloads/download", {
        url: await transferable(options?.url ?? ""), filename: options?.filename ?? null, method: options?.method ?? "GET",
        headers: options?.headers ?? [], body: options?.body ?? null
    })),
    search: () => method((query) => call("downloads/search", query ?? {})),
    cancel: () => method((id) => call("downloads/cancel", { id })),
    show: () => (id) => { call("downloads/show", { id }).catch(console.error); },
    showDefaultFolder: () => () => { call("downloads/showFolder").catch(console.error); },
    erase: () => method((query) => call("downloads/erase", query ?? {})),
    onCreated: () => deliveredEvent("downloads.onCreated"),
    onChanged: () => deliveredEvent("downloads.onChanged"),
    onErased: () => deliveredEvent("downloads.onErased"),
    onDeterminingFilename: inertEvent,
    State: constants(["in_progress", "interrupted", "complete"])
});
